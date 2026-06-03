"""API tests for POST /v1/matches/{id}/seats/{actor_id}/faction (C14d-1)."""

from __future__ import annotations

from fastapi.testclient import TestClient

from app.domain import factions, seats
from app.storage import file_store
from match_helpers import SEAT_TOKEN_HEADER, create_staging_match


def _claim_token(client: TestClient, match_id: str, actor_id: int) -> str:
    r = client.post(f"/v1/matches/{match_id}/seats/{actor_id}/claim")
    assert r.status_code == 200, r.text
    return str(r.json()["seat_token"])


def _faction(
    client: TestClient,
    match_id: str,
    actor_id: int,
    token: str,
    faction_id: str,
):
    return client.post(
        f"/v1/matches/{match_id}/seats/{actor_id}/faction",
        json={"faction_id": faction_id},
        headers={SEAT_TOKEN_HEADER: token},
    )


def test_faction_select_happy_path_no_tokens_in_response(client: TestClient) -> None:
    m = create_staging_match(client, {"scenario_id": "tiny_test", "player_ids": [0, 1]})
    mid = m["match_id"]
    token0 = _claim_token(client, mid, 0)
    r = _faction(client, mid, 0, token0, factions.FACTION_MALMO)
    assert r.status_code == 200
    body = r.json()
    assert body["match_id"] == mid
    assert body["status"] == seats.STATUS_STAGING
    assert seats.summary_has_no_tokens(body)
    assert "host_token" not in body
    assert body["ready_to_start"] is False
    assert len(body["available_factions"]) == 3
    seat0 = next(s for s in body["seats"] if s["actor_id"] == 0)
    assert seat0["faction_id"] == factions.FACTION_MALMO
    assert seat0["ready"] is False
    assert seat0["claimed"] is True


def test_faction_unknown_rejected(client: TestClient) -> None:
    m = create_staging_match(client, {"scenario_id": "tiny_test", "player_ids": [0]})
    mid = m["match_id"]
    token0 = _claim_token(client, mid, 0)
    r = _faction(client, mid, 0, token0, "stockholm")
    assert r.status_code == 400
    assert r.json()["detail"] == "faction_unknown"


def test_faction_taken_rejected(client: TestClient) -> None:
    m = create_staging_match(client, {"scenario_id": "tiny_test", "player_ids": [0, 1]})
    mid = m["match_id"]
    token0 = _claim_token(client, mid, 0)
    token1 = _claim_token(client, mid, 1)
    assert _faction(client, mid, 0, token0, factions.FACTION_PARIS).status_code == 200
    r = _faction(client, mid, 1, token1, factions.FACTION_PARIS)
    assert r.status_code == 409
    assert r.json()["detail"] == "faction_taken"


def test_faction_requires_claimed_seat(client: TestClient) -> None:
    m = create_staging_match(client, {"scenario_id": "tiny_test", "player_ids": [0, 1]})
    mid = m["match_id"]
    meta = file_store.read_meta(mid)
    assert meta is not None
    token0 = meta["seats"][0]["token"]
    r = _faction(client, mid, 0, token0, factions.FACTION_MALMO)
    assert r.status_code == 409
    assert r.json()["detail"] == "seat_not_claimed"


def test_faction_host_token_rejected(client: TestClient) -> None:
    m = create_staging_match(client, {"scenario_id": "tiny_test", "player_ids": [0]})
    mid = m["match_id"]
    _claim_token(client, mid, 0)
    r = _faction(client, mid, 0, m["host_token"], factions.FACTION_MALMO)
    assert r.status_code == 403
    assert r.json()["detail"] == "invalid_seat_token"


def test_faction_wrong_actor_token_rejected(client: TestClient) -> None:
    m = create_staging_match(client, {"scenario_id": "tiny_test", "player_ids": [0, 1]})
    mid = m["match_id"]
    token0 = _claim_token(client, mid, 0)
    _claim_token(client, mid, 1)
    r = _faction(client, mid, 1, token0, factions.FACTION_VASTERVIK)
    assert r.status_code == 403
    assert r.json()["detail"] == "seat_not_allowed"


def test_faction_not_staging_rejected(client: TestClient) -> None:
    m = create_staging_match(client, {"scenario_id": "tiny_test", "player_ids": [0]})
    mid = m["match_id"]
    token0 = _claim_token(client, mid, 0)
    meta = file_store.read_meta(mid)
    assert meta is not None
    meta["status"] = seats.STATUS_ONGOING
    file_store.write_meta(mid, meta)
    r = _faction(client, mid, 0, token0, factions.FACTION_MALMO)
    assert r.status_code == 409
    assert r.json()["detail"] == "match_not_in_staging"
