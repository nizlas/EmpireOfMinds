"""API tests for staging → ongoing auto-start on final ready (C14d-2)."""

from __future__ import annotations

import hashlib

from fastapi.testclient import TestClient

from app.domain import factions, match_lifecycle, match_state, seats
from app.storage import file_store
from match_helpers import SEAT_TOKEN_HEADER, create_staging_match


def _claim_token(client: TestClient, match_id: str, actor_id: int) -> str:
    r = client.post(f"/v1/matches/{match_id}/seats/{actor_id}/claim")
    assert r.status_code == 200, r.text
    return str(r.json()["seat_token"])


def _faction(client: TestClient, match_id: str, actor_id: int, token: str, faction_id: str) -> None:
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


def _set_match_seed(match_id: str, seed: str) -> None:
    meta = file_store.read_meta(match_id)
    assert meta is not None
    meta["match_seed"] = seed
    file_store.write_meta(match_id, meta)


def _expected_first_player(match_id: str, meta: dict, snap: dict) -> tuple[int, int]:
    players = [int(p) for p in snap["turn_state"]["players"]]
    idx = match_lifecycle.deterministic_first_player_index(meta, match_id, players)
    return idx, players[idx]


def test_new_match_starts_staging(client: TestClient) -> None:
    m = create_staging_match(client, {"scenario_id": "tiny_test", "player_ids": [0, 1]})
    meta = file_store.read_meta(m["match_id"])
    assert meta is not None
    assert seats.match_status(meta) == seats.STATUS_STAGING


def test_one_seat_ready_stays_staging(client: TestClient) -> None:
    m = create_staging_match(client, {"scenario_id": "tiny_test", "player_ids": [0, 1]})
    mid = m["match_id"]
    token0 = _claim_token(client, mid, 0)
    _claim_token(client, mid, 1)
    _faction(client, mid, 0, token0, factions.FACTION_MALMO)
    _faction(client, mid, 1, file_store.read_meta(mid)["seats"][1]["token"], factions.FACTION_VASTERVIK)
    token1 = file_store.read_meta(mid)["seats"][1]["token"]
    r = _ready(client, mid, 0, token0, True)
    assert r.status_code == 200
    assert r.json()["status"] == seats.STATUS_STAGING
    meta = file_store.read_meta(mid)
    assert meta is not None
    assert seats.match_status(meta) == seats.STATUS_STAGING
    assert "started_at" not in meta


def test_final_ready_auto_starts_match(client: TestClient) -> None:
    m = create_staging_match(client, {"scenario_id": "tiny_test", "player_ids": [0, 1]})
    mid = m["match_id"]
    fixed_seed = "c14d2deadbeefc14d2deadbeef12"
    _set_match_seed(mid, fixed_seed)
    token0 = _claim_token(client, mid, 0)
    token1 = _claim_token(client, mid, 1)
    _faction(client, mid, 0, token0, factions.FACTION_MALMO)
    _faction(client, mid, 1, token1, factions.FACTION_VASTERVIK)
    _ready(client, mid, 0, token0, True)
    r1 = _ready(client, mid, 1, token1, True)
    assert r1.status_code == 200
    body = r1.json()
    assert body["status"] == seats.STATUS_ONGOING
    assert body["ready_to_start"] is False
    assert "first_player_id" in body
    assert seats.summary_has_no_tokens(body)

    meta = file_store.read_meta(mid)
    snap = file_store.read_snapshot(mid)
    assert meta is not None and snap is not None
    assert meta.get("started_at")
    exp_idx, exp_pid = _expected_first_player(mid, meta, snap)
    assert meta["first_player_id"] == exp_pid
    assert int(snap["turn_state"]["current_index"]) == exp_idx
    assert match_state.current_player_id(snap) == exp_pid
    assert int(snap["revision"]) == 0

    events = file_store.read_events(mid)
    started = [e for e in events if e.get("action_type") == match_lifecycle.MATCH_STARTED_ACTION_TYPE]
    assert len(started) == 1
    assert started[0]["first_player_id"] == exp_pid
    assert "token" not in str(started[0])


def test_auto_start_idempotent_second_start_call(client: TestClient) -> None:
    m = create_staging_match(client, {"scenario_id": "tiny_test", "player_ids": [0, 1]})
    mid = m["match_id"]
    _set_match_seed(mid, "c14d2deadbeefc14d2deadbeef12")
    token0 = _claim_token(client, mid, 0)
    token1 = _claim_token(client, mid, 1)
    _faction(client, mid, 0, token0, factions.FACTION_MALMO)
    _faction(client, mid, 1, token1, factions.FACTION_VASTERVIK)
    _ready(client, mid, 0, token0, True)
    _ready(client, mid, 1, token1, True)
    meta = file_store.read_meta(mid)
    snap = file_store.read_snapshot(mid)
    assert meta is not None and snap is not None
    first_pid = meta["first_player_id"]
    started_at = meta["started_at"]
    again = match_lifecycle.try_start_match_if_ready(mid, meta, snap)
    assert again.started is False
    assert again.meta["first_player_id"] == first_pid
    assert again.meta["started_at"] == started_at
    assert int(again.snapshot["turn_state"]["current_index"]) == int(snap["turn_state"]["current_index"])


def test_deterministic_first_player_fixed_seed(client: TestClient) -> None:
    seed = "0123456789abcdef0123456789abcdef"
    m = create_staging_match(client, {"scenario_id": "tiny_test", "player_ids": [0, 1]})
    mid = m["match_id"]
    _set_match_seed(mid, seed)
    digest = hashlib.sha256(f"{seed}:first_player".encode()).hexdigest()
    expected_index = int(digest, 16) % 2
    token0 = _claim_token(client, mid, 0)
    token1 = _claim_token(client, mid, 1)
    _faction(client, mid, 0, token0, factions.FACTION_MALMO)
    _faction(client, mid, 1, token1, factions.FACTION_PARIS)
    _ready(client, mid, 0, token0, True)
    _ready(client, mid, 1, token1, True)
    snap = file_store.read_snapshot(mid)
    meta = file_store.read_meta(mid)
    assert snap is not None and meta is not None
    players = [int(p) for p in snap["turn_state"]["players"]]
    assert int(snap["turn_state"]["current_index"]) == expected_index
    assert meta["first_player_id"] == players[expected_index]


def test_first_player_can_differ_from_actor_zero(client: TestClient) -> None:
    """Pick a seed that selects player index 1 when players are [0, 1]."""
    players = [0, 1]
    seed = None
    for candidate in range(1000):
        s = f"{candidate:032x}"
        digest = hashlib.sha256(f"{s}:first_player".encode()).hexdigest()
        if int(digest, 16) % 2 == 1:
            seed = s
            break
    assert seed is not None
    m = create_staging_match(client, {"scenario_id": "tiny_test", "player_ids": players})
    mid = m["match_id"]
    _set_match_seed(mid, seed)
    token0 = _claim_token(client, mid, 0)
    token1 = _claim_token(client, mid, 1)
    _faction(client, mid, 0, token0, factions.FACTION_MALMO)
    _faction(client, mid, 1, token1, factions.FACTION_VASTERVIK)
    _ready(client, mid, 0, token0, True)
    body = _ready(client, mid, 1, token1, True).json()
    assert body["first_player_id"] == 1
