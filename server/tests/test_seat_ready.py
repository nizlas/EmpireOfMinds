"""API tests for POST /v1/matches/{id}/seats/{actor_id}/ready (C14d-1)."""

from __future__ import annotations

from fastapi.testclient import TestClient

from app.domain import factions, seats
from app.storage import file_store
from match_helpers import SEAT_TOKEN_HEADER, create_seated_match


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
) -> None:
    r = client.post(
        f"/v1/matches/{match_id}/seats/{actor_id}/faction",
        json={"faction_id": faction_id},
        headers={SEAT_TOKEN_HEADER: token},
    )
    assert r.status_code == 200, r.text


def _ready(client: TestClient, match_id: str, actor_id: int, token: str, ready: bool):
    return client.post(
        f"/v1/matches/{match_id}/seats/{actor_id}/ready",
        json={"ready": ready},
        headers={SEAT_TOKEN_HEADER: token},
    )


def test_ready_requires_faction(client: TestClient) -> None:
    m = create_seated_match(client, {"scenario_id": "tiny_test", "player_ids": [0]})
    mid = m["match_id"]
    token0 = _claim_token(client, mid, 0)
    r = _ready(client, mid, 0, token0, True)
    assert r.status_code == 400
    assert r.json()["detail"] == "faction_required"


def test_ready_happy_path_and_ready_to_start(client: TestClient) -> None:
    m = create_seated_match(client, {"scenario_id": "tiny_test", "player_ids": [0, 1]})
    mid = m["match_id"]
    token0 = _claim_token(client, mid, 0)
    token1 = _claim_token(client, mid, 1)
    _faction(client, mid, 0, token0, factions.FACTION_MALMO)
    _faction(client, mid, 1, token1, factions.FACTION_VASTERVIK)
    r0 = _ready(client, mid, 0, token0, True)
    assert r0.status_code == 200
    assert r0.json()["ready_to_start"] is False
    r1 = _ready(client, mid, 1, token1, True)
    assert r1.status_code == 200
    body = r1.json()
    assert body["ready_to_start"] is True
    assert seats.summary_has_no_tokens(body)
    for seat in body["seats"]:
        assert seat["ready"] is True
        assert seat["faction_id"] is not None

    meta = file_store.read_meta(mid)
    assert meta is not None
    seat0 = next(s for s in meta["seats"] if s["actor_id"] == 0)
    assert seat0.get("ready_at")
    assert seats.match_status(meta) == seats.STATUS_STAGING


def test_ready_unready_clears_ready_to_start(client: TestClient) -> None:
    m = create_seated_match(client, {"scenario_id": "tiny_test", "player_ids": [0, 1]})
    mid = m["match_id"]
    token0 = _claim_token(client, mid, 0)
    token1 = _claim_token(client, mid, 1)
    _faction(client, mid, 0, token0, factions.FACTION_MALMO)
    _faction(client, mid, 1, token1, factions.FACTION_PARIS)
    _ready(client, mid, 0, token0, True)
    _ready(client, mid, 1, token1, True)
    r = _ready(client, mid, 0, token0, False)
    assert r.status_code == 200
    assert r.json()["ready_to_start"] is False
    seat0 = next(s for s in r.json()["seats"] if s["actor_id"] == 0)
    assert seat0["ready"] is False


def test_ready_host_token_rejected(client: TestClient) -> None:
    m = create_seated_match(client, {"scenario_id": "tiny_test", "player_ids": [0]})
    mid = m["match_id"]
    token0 = _claim_token(client, mid, 0)
    _faction(client, mid, 0, token0, factions.FACTION_MALMO)
    r = _ready(client, mid, 0, m["host_token"], True)
    assert r.status_code == 403
    assert r.json()["detail"] == "invalid_seat_token"


def test_ready_not_claimed_rejected(client: TestClient) -> None:
    m = create_seated_match(client, {"scenario_id": "tiny_test", "player_ids": [0]})
    mid = m["match_id"]
    meta = file_store.read_meta(mid)
    assert meta is not None
    token0 = meta["seats"][0]["token"]
    r = _ready(client, mid, 0, token0, True)
    assert r.status_code == 409
    assert r.json()["detail"] == "seat_not_claimed"
