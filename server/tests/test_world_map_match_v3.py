"""N6: opt-in world_map match kind + minimal snapshot v3 + endpoint gating.

Covers: MapIdentity.to_dict parity, snapshot v3 shape (identity plus minimal
mutable state — no embedded tiles/edges/terrain), create-match kind
branching, world-only meta and lobby fields (absent — not null — for legacy),
and staging/auto-start reuse.

Deliberate N7a updates: snapshot v3 gained a top-level "units" key
(test_world_map_actions_v3.py owns its contract), world creation now requires
exactly two distinct player_ids, and POST actions dispatches to the world
path instead of the 409 guard.

Deliberate N7b update: the final GET legal-actions 409 guard is gone — world
legal-actions is served behind a 403 credential gate
(test_world_legal_actions_v3.py owns its contract).
"""

from __future__ import annotations

from fastapi.testclient import TestClient

from app.domain import world_match
from app.domain.map_content_loader import load_world_map
from app.domain.world_map import MapIdentity
from app.storage import file_store
from match_helpers import SEAT_TOKEN_HEADER, _auto_start_via_staging_api

REFERENCE_MAP_ID = "handdrawn_test_map_full_01"
REFERENCE_HASH = "16cc82c3392c66f1e47273e7da94cf8a804ae9885a051fc81c4b0a9a4261d8c6"

SNAPSHOT_V3_KEYS = {
    "match_id",
    "schema_version",
    "match_kind",
    "map",
    "revision",
    "turn_state",
    "units",  # N7a: deterministic starting units (sorted by id)
}


def _create_world_match(client: TestClient, body: dict | None = None) -> dict:
    payload = {"match_kind": "world_map", **(body or {})}
    r = client.post("/v1/matches", json=payload)
    assert r.status_code == 200, r.text
    return r.json()


# ---------------------------------------------------------------- identity


def test_map_identity_to_dict_parity() -> None:
    """Exact key set + values of map_identity.gd to_dict()."""
    ident = MapIdentity(map_id="m", schema_version=1, content_hash="h")
    d = ident.to_dict()
    assert d == {"map_id": "m", "schema_version": 1, "content_hash": "h"}
    assert list(d.keys()) == ["map_id", "schema_version", "content_hash"]
    assert isinstance(d["schema_version"], int)


def test_reference_identity_matches_loader_goldens() -> None:
    ident = load_world_map(REFERENCE_MAP_ID).identity
    assert ident.to_dict() == {
        "map_id": REFERENCE_MAP_ID,
        "schema_version": 1,
        "content_hash": REFERENCE_HASH,
    }


# ---------------------------------------------------------- snapshot v3


def test_build_initial_world_snapshot_shape() -> None:
    snap = world_match.build_initial_world_snapshot("m_test", [0, 1], REFERENCE_MAP_ID)
    assert set(snap.keys()) == SNAPSHOT_V3_KEYS
    assert snap["schema_version"] == world_match.SNAPSHOT_SCHEMA_V3 == 3
    assert snap["match_kind"] == world_match.MATCH_KIND_WORLD_MAP == "world_map"
    assert snap["revision"] == 0
    assert snap["turn_state"] == {"players": [0, 1], "current_index": 0, "turn_number": 1}
    assert snap["map"] == {
        "map_id": REFERENCE_MAP_ID,
        "schema_version": 1,
        "content_hash": REFERENCE_HASH,
    }
    # v3 carries identity only: never embedded map content or legacy state.
    for forbidden in ("scenario", "scenario_id", "progress_state", "visibility_state", "tiles", "edges"):
        assert forbidden not in snap


def test_is_world_map_snapshot() -> None:
    assert world_match.is_world_map_snapshot({"match_kind": "world_map"})
    assert not world_match.is_world_map_snapshot({"match_kind": "other"})
    assert not world_match.is_world_map_snapshot({"schema_version": 2})


# --------------------------------------------------------------- creation


def test_create_world_match_default_map(client: TestClient) -> None:
    data = _create_world_match(client)
    snap = data["snapshot"]
    assert snap["schema_version"] == 3
    assert snap["match_kind"] == "world_map"
    assert snap["map"]["map_id"] == world_match.DEFAULT_WORLD_MAP_ID == REFERENCE_MAP_ID
    assert snap["map"]["content_hash"] == REFERENCE_HASH
    assert data["revision"] == 0
    assert data["host_token"].startswith("ht_")
    assert len(data["seats"]) == 2


def test_create_world_match_explicit_map_id(client: TestClient) -> None:
    # N7a: world creation supports exactly two players (arbitrary ids).
    data = _create_world_match(client, {"map_id": REFERENCE_MAP_ID, "player_ids": [4, 9]})
    snap = data["snapshot"]
    assert snap["map"]["map_id"] == REFERENCE_MAP_ID
    assert snap["turn_state"]["players"] == [4, 9]


def test_create_world_match_unknown_map_id_400(client: TestClient) -> None:
    r = client.post("/v1/matches", json={"match_kind": "world_map", "map_id": "no_such_map"})
    assert r.status_code == 400
    assert "invalid map_id" in r.json()["detail"]


def test_create_world_match_blank_map_id_400(client: TestClient) -> None:
    r = client.post("/v1/matches", json={"match_kind": "world_map", "map_id": "  "})
    assert r.status_code == 400


def test_create_unknown_match_kind_400(client: TestClient) -> None:
    r = client.post("/v1/matches", json={"match_kind": "hexmap_legacy"})
    assert r.status_code == 400
    assert r.json()["detail"] == "unknown match_kind"


def test_world_meta_has_kind_and_map_id(client: TestClient) -> None:
    data = _create_world_match(client)
    meta = file_store.read_meta(data["match_id"])
    assert meta is not None
    assert meta["match_kind"] == "world_map"
    assert meta["map_id"] == REFERENCE_MAP_ID
    assert meta["scenario_id"] == REFERENCE_MAP_ID


# ----------------------------------------------------- legacy unchanged


def test_legacy_create_has_no_world_keys(client: TestClient) -> None:
    r = client.post("/v1/matches", json={})
    assert r.status_code == 200
    snap = r.json()["snapshot"]
    assert snap["schema_version"] == 2
    assert "match_kind" not in snap
    assert "map_id" not in snap
    meta = file_store.read_meta(r.json()["match_id"])
    assert meta is not None
    assert "match_kind" not in meta
    assert "map_id" not in meta


def test_legacy_lobby_row_has_no_world_keys(client: TestClient) -> None:
    client.post("/v1/matches", json={})
    rows = client.get("/v1/matches").json()["matches"]
    assert len(rows) == 1
    assert "match_kind" not in rows[0]
    assert "map_id" not in rows[0]


# ------------------------------------------------------------------ lobby


def test_world_lobby_row_carries_kind_and_map_id(client: TestClient) -> None:
    data = _create_world_match(client)
    rows = client.get("/v1/matches").json()["matches"]
    row = next(r for r in rows if r["match_id"] == data["match_id"])
    assert row["match_kind"] == "world_map"
    assert row["map_id"] == REFERENCE_MAP_ID
    assert row["status"] == "staging"
    # Token-free contract preserved.
    assert "host_token" not in row and "token" not in row


# ---------------------------------------------------- staging / auto-start


def test_world_match_staging_and_auto_start(client: TestClient) -> None:
    data = _create_world_match(client)
    match_id = data["match_id"]
    _auto_start_via_staging_api(client, match_id, [0, 1])
    rows = client.get("/v1/matches").json()["matches"]
    row = next(r for r in rows if r["match_id"] == match_id)
    assert row["status"] == "ongoing"
    assert row["match_kind"] == "world_map"
    snap = client.get(f"/v1/matches/{match_id}").json()["snapshot"]
    assert snap["schema_version"] == 3
    assert snap["match_kind"] == "world_map"
    assert snap["map"]["content_hash"] == REFERENCE_HASH
    assert "player_factions" in snap


def test_world_match_resume_returns_v3(client: TestClient) -> None:
    data = _create_world_match(client)
    r = client.get(f"/v1/matches/{data['match_id']}")
    assert r.status_code == 200
    assert r.json()["snapshot"] == data["snapshot"]


# ---------------------------------------- gameplay endpoints (post-N7a)


def test_actions_on_world_match_reach_world_gates(client: TestClient) -> None:
    """N7a removed the POST-actions 409: a staging world match now rejects
    through the normal gate chain (credential passed via host token, status
    gate rejects) with the legacy HTTP-200 envelope."""
    data = _create_world_match(client)
    r = client.post(
        f"/v1/matches/{data['match_id']}/actions",
        json={"schema_version": 1, "action_type": "end_turn", "actor_id": 0},
        headers={SEAT_TOKEN_HEADER: data["host_token"]},
    )
    assert r.status_code == 200
    assert r.json() == {"accepted": False, "reason": "match_not_ongoing", "index": -1}


def test_actions_credential_gate_first_on_world_match(client: TestClient) -> None:
    """Missing token + staging + malformed body: the credential gate fires
    first on the world path (locked N7a gate order)."""
    data = _create_world_match(client)
    r = client.post(f"/v1/matches/{data['match_id']}/actions", json={"nonsense": True})
    assert r.status_code == 200
    assert r.json()["reason"] == "missing_seat_token"


def test_world_end_turn_accepted_after_auto_start(client: TestClient) -> None:
    """Guard removal smoke: a started world match accepts end_turn (full
    action matrix lives in test_world_map_actions_v3.py)."""
    data = _create_world_match(client)
    _auto_start_via_staging_api(client, data["match_id"], [0, 1])
    snap = client.get(f"/v1/matches/{data['match_id']}").json()["snapshot"]
    current = snap["turn_state"]["players"][snap["turn_state"]["current_index"]]
    r = client.post(
        f"/v1/matches/{data['match_id']}/actions",
        json={"schema_version": 1, "action_type": "end_turn", "actor_id": current},
        headers={SEAT_TOKEN_HEADER: data["host_token"]},
    )
    assert r.status_code == 200
    assert r.json()["accepted"] is True


def test_legal_actions_final_409_removed(client: TestClient) -> None:
    """N7b removed the last 409: an unauthenticated request now hits the
    world credential gate (403), and an authenticated one gets a real 200
    payload (full contract in test_world_legal_actions_v3.py)."""
    data = _create_world_match(client)
    r = client.get(f"/v1/matches/{data['match_id']}/legal-actions", params={"actor_id": 0})
    assert r.status_code == 403
    assert r.json()["detail"] == "missing_seat_token"
    r2 = client.get(
        f"/v1/matches/{data['match_id']}/legal-actions",
        params={"actor_id": 0},
        headers={SEAT_TOKEN_HEADER: data["host_token"]},
    )
    assert r2.status_code == 200
    assert r2.json()["schema_version"] == 1


def test_unknown_match_still_404_before_guard(client: TestClient) -> None:
    r = client.post("/v1/matches/m_missing/actions", json={"action_type": "end_turn"})
    assert r.status_code == 404
    r2 = client.get("/v1/matches/m_missing/legal-actions", params={"actor_id": 0})
    assert r2.status_code == 404


def test_legacy_gameplay_endpoints_unaffected(client: TestClient) -> None:
    r = client.post("/v1/matches", json={})
    match_id = r.json()["match_id"]
    _auto_start_via_staging_api(client, match_id, [0, 1])
    la = client.get(f"/v1/matches/{match_id}/legal-actions", params={"actor_id": 0})
    assert la.status_code == 200
