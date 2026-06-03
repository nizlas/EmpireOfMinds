"""API tests for staging action gate match_not_ongoing (C14d-2)."""

from __future__ import annotations

from fastapi.testclient import TestClient

from app.domain import factions, seats
from app.storage import file_store
from match_helpers import SEAT_TOKEN_HEADER, create_staging_match, post_match_action


def _end_turn(actor_id: int) -> dict:
    return {"schema_version": 1, "action_type": "end_turn", "actor_id": actor_id}


def _claim_and_stage(client: TestClient, mid: str) -> tuple[str, str]:
    token0 = client.post(f"/v1/matches/{mid}/seats/0/claim").json()["seat_token"]
    token1 = client.post(f"/v1/matches/{mid}/seats/1/claim").json()["seat_token"]
    for aid, tok, fid in (
        (0, token0, factions.FACTION_MALMO),
        (1, token1, factions.FACTION_VASTERVIK),
    ):
        client.post(
            f"/v1/matches/{mid}/seats/{aid}/faction",
            json={"faction_id": fid},
            headers={SEAT_TOKEN_HEADER: tok},
        )
    return token0, token1


def test_staging_actions_rejected_match_not_ongoing(client: TestClient) -> None:
    m = create_staging_match(client, {"scenario_id": "tiny_test", "player_ids": [0, 1]})
    mid = m["match_id"]
    meta = file_store.read_meta(mid)
    assert meta is not None
    assert seats.match_status(meta) == seats.STATUS_STAGING
    seat0 = next(s for s in meta["seats"] if s["actor_id"] == 0)
    r = post_match_action(
        client,
        mid,
        _end_turn(0),
        {SEAT_TOKEN_HEADER: seat0["token"]},
    )
    assert r.json()["accepted"] is False
    assert r.json()["reason"] == "match_not_ongoing"


def test_staging_host_token_also_rejected(client: TestClient) -> None:
    m = create_staging_match(client, {"scenario_id": "tiny_test"})
    r = post_match_action(client, m["match_id"], _end_turn(0), m["headers"])
    assert r.json()["accepted"] is False
    assert r.json()["reason"] == "match_not_ongoing"


def test_ongoing_actions_proceed(client: TestClient) -> None:
    m = create_staging_match(client, {"scenario_id": "tiny_test", "player_ids": [0, 1]})
    mid = m["match_id"]
    token0, token1 = _claim_and_stage(client, mid)
    client.post(
        f"/v1/matches/{mid}/seats/0/ready",
        json={"ready": True},
        headers={SEAT_TOKEN_HEADER: token0},
    )
    client.post(
        f"/v1/matches/{mid}/seats/1/ready",
        json={"ready": True},
        headers={SEAT_TOKEN_HEADER: token1},
    )
    meta = file_store.read_meta(mid)
    snap = file_store.read_snapshot(mid)
    assert meta is not None and snap is not None
    assert seats.match_status(meta) == seats.STATUS_ONGOING
    current = snap["turn_state"]["players"][snap["turn_state"]["current_index"]]
    token = token0 if current == 0 else token1
    r = post_match_action(
        client,
        mid,
        _end_turn(int(current)),
        {SEAT_TOKEN_HEADER: token},
    )
    assert r.json()["accepted"] is True


def test_legacy_no_meta_remains_permissive(client: TestClient) -> None:
    m = create_staging_match(client, {"scenario_id": "tiny_test", "player_ids": [0]})
    mid = m["match_id"]
    file_store.meta_path(mid).unlink()
    r = post_match_action(client, mid, _end_turn(0))
    assert r.json()["accepted"] is True


def test_meta_v1_treated_as_ongoing_for_actions(client: TestClient) -> None:
    m = create_staging_match(client, {"scenario_id": "tiny_test", "player_ids": [0]})
    mid = m["match_id"]
    meta = file_store.read_meta(mid)
    assert meta is not None
    meta["schema_version"] = seats.META_SCHEMA_VERSION_V1
    meta.pop("status", None)
    file_store.write_meta(mid, meta)
    r = post_match_action(client, mid, _end_turn(0), m["headers"])
    assert r.json()["accepted"] is True
