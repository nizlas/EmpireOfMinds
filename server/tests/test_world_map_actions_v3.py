"""N7a: server-authoritative units + world actions on the world_map path.

Covers: the pinned spawn table for handdrawn_test_map_full_01 (content
cross-check included), arbitrary two-player-id ownership, the exact 2-player
creation narrowing, snapshot-v3 units determinism (sorted, minimal rows), the
locked world POST gate order (credential -> status -> dispatch -> validation),
every literal world rejection string incl. a real cliff edge and occupancy,
accepted multi-step movement and end-turn handoff with revision/state-hash/
event semantics, fail-closed map-identity verification (HTTP 500, no
mutation) for both supported actions, and unchanged legacy behavior.
"""

from __future__ import annotations

import shutil
from pathlib import Path

from fastapi.testclient import TestClient

from app.domain import world_actions, world_match, world_scenario
from app.domain.map_content_loader import _index_map_files, load_world_map, resolve_content_root
from app.domain.state_hash import state_hash
from app.domain.world_map import EDGE_CLIFF, EDGE_SMOOTH
from app.storage import file_store
from match_helpers import SEAT_TOKEN_HEADER, _match_seed_for_first_player_index

REFERENCE_MAP_ID = "handdrawn_test_map_full_01"
PLAYER_COUNT_DETAIL = "world_map supports exactly 2 players in N7"
MISMATCH_DETAIL = f"world map content unavailable or mismatched for map_id {REFERENCE_MAP_ID}"

EXPECTED_SPAWN_UNITS = [
    {"id": 1, "owner_id": 0, "position": [1, 1], "type_id": "settler", "current_hp": 100, "has_attacked": False},
    {"id": 2, "owner_id": 0, "position": [2, 1], "type_id": "warrior", "current_hp": 100, "has_attacked": False},
    {"id": 3, "owner_id": 1, "position": [2, 14], "type_id": "settler", "current_hp": 100, "has_attacked": False},
    {"id": 4, "owner_id": 1, "position": [2, 13], "type_id": "warrior", "current_hp": 100, "has_attacked": False},
]

_FACTIONS = ("malmo", "vastervik")


def _create_world(client: TestClient, body: dict | None = None) -> dict:
    r = client.post("/v1/matches", json={"match_kind": "world_map", **(body or {})})
    assert r.status_code == 200, r.text
    return r.json()


def _start_world_match(
    client: TestClient,
    player_ids: list[int] | None = None,
) -> tuple[str, dict[int, str], dict]:
    """Create + auto-start a world match with players[0] forced as first
    player (seed trick from match_helpers). Returns (match_id, seat tokens
    by actor_id, create response)."""
    pids = [0, 1] if player_ids is None else player_ids
    body: dict = {}
    if player_ids is not None:
        body["player_ids"] = pids
    data = _create_world(client, body)
    match_id = data["match_id"]
    meta = file_store.read_meta(match_id)
    assert meta is not None
    meta["match_seed"] = _match_seed_for_first_player_index(len(pids), 0)
    file_store.write_meta(match_id, meta)
    tokens: dict[int, str] = {}
    for i, actor_id in enumerate(sorted({int(p) for p in pids})):
        claim = client.post(f"/v1/matches/{match_id}/seats/{actor_id}/claim")
        assert claim.status_code == 200, claim.text
        tokens[actor_id] = str(claim.json()["seat_token"])
        headers = {SEAT_TOKEN_HEADER: tokens[actor_id]}
        fr = client.post(
            f"/v1/matches/{match_id}/seats/{actor_id}/faction",
            json={"faction_id": _FACTIONS[i % len(_FACTIONS)]},
            headers=headers,
        )
        assert fr.status_code == 200, fr.text
        rr = client.post(
            f"/v1/matches/{match_id}/seats/{actor_id}/ready",
            json={"ready": True},
            headers=headers,
        )
        assert rr.status_code == 200, rr.text
    return match_id, tokens, data


def _post(client: TestClient, match_id: str, action: dict, token: str | None):
    headers = {SEAT_TOKEN_HEADER: token} if token else {}
    return client.post(f"/v1/matches/{match_id}/actions", json=action, headers=headers)


def _move(actor_id: int, unit_id: int, from_c, to_c, schema: int = 1) -> dict:
    return {
        "schema_version": schema,
        "action_type": "move_unit",
        "actor_id": actor_id,
        "unit_id": unit_id,
        "from": list(from_c),
        "to": list(to_c),
    }


def _end_turn(actor_id: int, schema: int = 1) -> dict:
    return {"schema_version": schema, "action_type": "end_turn", "actor_id": actor_id}


def _teleport_unit(match_id: str, unit_id: int, pos: tuple[int, int]) -> None:
    """Test fixture only: reposition a unit directly in the persisted snapshot."""
    snap = file_store.read_snapshot(match_id)
    assert snap is not None
    for u in snap["units"]:
        if int(u["id"]) == unit_id:
            u["position"] = [pos[0], pos[1]]
    file_store.write_snapshot(match_id, snap)


def _delete_meta(match_id: str) -> None:
    """Test fixture only: simulate a world match whose meta.json is missing."""
    file_store.meta_path(match_id).unlink()


def _assert_reject(resp, reason: str) -> None:
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["accepted"] is False
    assert body["reason"] == reason
    assert body["index"] == -1
    assert "snapshot" not in body and "event" not in body and "state_hash" not in body


# ------------------------------------------------------------- spawn table


def test_spawn_table_golden(client: TestClient) -> None:
    data = _create_world(client)
    units = data["snapshot"]["units"]
    assert units == EXPECTED_SPAWN_UNITS
    assert [u["id"] for u in units] == [1, 2, 3, 4]
    for u in units:
        # N7g.1 additive combat fields only — still no max_hp, movement
        # points, moved flags, or id counters in snapshot state.
        assert set(u.keys()) == {
            "id", "owner_id", "position", "type_id", "current_hp", "has_attacked",
        }


def test_spawn_arbitrary_player_ids_ownership(client: TestClient) -> None:
    """First player_ids entry owns units 1-2, second owns 3-4 (ids arbitrary)."""
    data = _create_world(client, {"player_ids": [7, 3]})
    units = data["snapshot"]["units"]
    assert [u["owner_id"] for u in units] == [7, 7, 3, 3]
    assert data["snapshot"]["turn_state"]["players"] == [7, 3]


def test_create_world_match_one_player_400(client: TestClient) -> None:
    r = client.post("/v1/matches", json={"match_kind": "world_map", "player_ids": [0]})
    assert r.status_code == 400
    assert r.json()["detail"] == PLAYER_COUNT_DETAIL


def test_create_world_match_three_players_400(client: TestClient) -> None:
    r = client.post(
        "/v1/matches", json={"match_kind": "world_map", "player_ids": [0, 1, 2]}
    )
    assert r.status_code == 400
    assert r.json()["detail"] == PLAYER_COUNT_DETAIL
    # No partial match was created.
    assert client.get("/v1/matches").json()["matches"] == []


def test_create_world_match_duplicate_player_ids_400(client: TestClient) -> None:
    r = client.post(
        "/v1/matches", json={"match_kind": "world_map", "player_ids": [5, 5]}
    )
    assert r.status_code == 400
    assert r.json()["detail"] == PLAYER_COUNT_DETAIL
    assert client.get("/v1/matches").json()["matches"] == []


def test_create_world_match_boolean_player_ids_400(client: TestClient) -> None:
    """Booleans are ints in Python; the world path rejects them explicitly."""
    for pids in ([True, 1], [0, False], [True, False]):
        r = client.post(
            "/v1/matches", json={"match_kind": "world_map", "player_ids": pids}
        )
        assert r.status_code == 400, pids
        assert r.json()["detail"] == "player_ids must be integers"
    assert client.get("/v1/matches").json()["matches"] == []


def test_legacy_create_keeps_arbitrary_player_counts(client: TestClient) -> None:
    r = client.post("/v1/matches", json={"player_ids": [0, 1, 2]})
    assert r.status_code == 200
    assert r.json()["snapshot"]["schema_version"] == 2


def test_spawn_table_matches_canonical_content() -> None:
    """Pins the table <-> content contract: tiles exist, unique, spawn groups
    smooth-connected, and every unit keeps a free smooth destination."""
    wm = load_world_map(REFERENCE_MAP_ID)
    units = world_scenario.build_starting_units(wm, [0, 1])
    assert units == EXPECTED_SPAWN_UNITS
    positions = [tuple(u["position"]) for u in units]
    assert len(set(positions)) == 4
    for pos in positions:
        assert wm.has_tile_coord(pos)
    # Spawn groups (settler+warrior per player) connected by smooth edges.
    assert wm.edge_between((1, 1), (2, 1)).transition == EDGE_SMOOTH
    assert wm.edge_between((2, 14), (2, 13)).transition == EDGE_SMOOTH
    occupied = set(positions)
    for pos in positions:
        free_smooth = [
            (pos[0] + dq, pos[1] + dr)
            for dq, dr in world_actions.DIRECTIONS
            if (pos[0] + dq, pos[1] + dr) not in occupied
            and wm.has_tile_coord((pos[0] + dq, pos[1] + dr))
            and wm.edge_between(pos, (pos[0] + dq, pos[1] + dr)).transition == EDGE_SMOOTH
        ]
        assert free_smooth, f"spawn {pos} has no free smooth destination"


def test_units_carry_no_forbidden_state(client: TestClient) -> None:
    """N7g.1 added ONLY current_hp + has_attacked on units; N8a adds empty
    cities + next_city_id. Movement points, moved flags, max_hp, and
    next_unit_id stay out of snapshot state until their slices."""
    snap = _create_world(client)["snapshot"]
    assert "next_unit_id" not in snap
    assert snap["cities"] == []
    assert snap["next_city_id"] == 1
    for u in snap["units"]:
        for forbidden in ("remaining_movement", "hp", "max_hp", "moved", "max_movement"):
            assert forbidden not in u
    # Map stays MapIdentity only.
    assert set(snap["map"].keys()) == {"map_id", "schema_version", "content_hash"}


def test_world_scenario_rejects_wrong_player_count() -> None:
    wm = load_world_map(REFERENCE_MAP_ID)
    try:
        world_scenario.build_starting_units(wm, [0])
        raise AssertionError("expected WorldScenarioError")
    except world_scenario.WorldScenarioError as exc:
        assert "exactly 2" in str(exc)


def test_world_scenario_rejects_boolean_and_duplicate_player_ids() -> None:
    """Defensive mirror of the API creation contract in the domain module."""
    wm = load_world_map(REFERENCE_MAP_ID)
    try:
        world_scenario.build_starting_units(wm, [True, 1])  # type: ignore[list-item]
        raise AssertionError("expected WorldScenarioError")
    except world_scenario.WorldScenarioError as exc:
        assert "exact integers" in str(exc)
    try:
        world_scenario.build_starting_units(wm, [5, 5])
        raise AssertionError("expected WorldScenarioError")
    except world_scenario.WorldScenarioError as exc:
        assert "distinct" in str(exc)


def test_world_scenario_rejects_unknown_map() -> None:
    class _StubIdentity:
        map_id = "no_such_map"

    class _StubMap:
        identity = _StubIdentity()

    try:
        world_scenario.build_starting_units(_StubMap(), [0, 1])  # type: ignore[arg-type]
        raise AssertionError("expected WorldScenarioError")
    except world_scenario.WorldScenarioError as exc:
        assert "no world spawn table" in str(exc)


# ---------------------------------------------------- gate order (world POST)


def test_world_actions_credential_gate_first(client: TestClient) -> None:
    """Staging + nonsense body + missing token: credential gate fires first
    (the N6 409 guard is gone from POST actions)."""
    data = _create_world(client)
    r = _post(client, data["match_id"], {"nonsense": True}, token=None)
    _assert_reject(r, "missing_seat_token")


def test_world_actions_invalid_token(client: TestClient) -> None:
    data = _create_world(client)
    r = _post(client, data["match_id"], _end_turn(0), token="st_bogus")
    _assert_reject(r, "invalid_seat_token")


def test_world_actions_seat_not_allowed(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    r = _post(client, match_id, _end_turn(0), token=tokens[1])
    _assert_reject(r, "seat_not_allowed")


def test_world_actions_status_gate_after_credential(client: TestClient) -> None:
    """Host token on a staging world match: credential passes, status rejects."""
    data = _create_world(client)
    r = _post(client, data["match_id"], _end_turn(0), token=data["host_token"])
    _assert_reject(r, "match_not_ongoing")


def test_world_post_missing_meta_fails_closed(client: TestClient) -> None:
    """No metadata-free mode for world_map: with meta.json absent, a blank
    token rejects missing_seat_token and a supplied token rejects
    invalid_seat_token — stopping at the credential gate with no snapshot,
    hash, or event change."""
    match_id, tokens, _ = _start_world_match(client)
    snap_before = file_store.read_snapshot(match_id)
    events_before = file_store.read_events(match_id)
    hash_before = state_hash(snap_before)
    _delete_meta(match_id)

    r = _post(client, match_id, _move(0, 2, (2, 1), (3, 1)), token=None)
    _assert_reject(r, "missing_seat_token")
    r = _post(client, match_id, _move(0, 2, (2, 1), (3, 1)), tokens[0])
    _assert_reject(r, "invalid_seat_token")
    r = _post(client, match_id, _end_turn(0), "st_anything")
    _assert_reject(r, "invalid_seat_token")

    snap_after = file_store.read_snapshot(match_id)
    assert snap_after == snap_before
    assert state_hash(snap_after) == hash_before
    assert file_store.read_events(match_id) == events_before


def test_world_post_meta_race_single_read(client: TestClient, monkeypatch) -> None:
    """Regression for the credential double-read race: metadata valid on the
    initial read but unavailable on any subsequent read must still reject an
    invalid token with invalid_seat_token. The old implementation prechecked
    existence and then delegated to the shared legacy gate, whose second
    read returned None and permitted the request as legacy (fail-open)."""
    match_id, _, _ = _start_world_match(client)
    snap_before = file_store.read_snapshot(match_id)
    events_before = file_store.read_events(match_id)
    hash_before = state_hash(snap_before)

    real_read_meta = file_store.read_meta
    calls = {"n": 0}

    def read_meta_once_then_gone(mid: str):
        calls["n"] += 1
        return real_read_meta(mid) if calls["n"] == 1 else None

    monkeypatch.setattr(file_store, "read_meta", read_meta_once_then_gone)
    r = _post(client, match_id, _move(0, 2, (2, 1), (3, 1)), "st_arbitrary_invalid")
    monkeypatch.setattr(file_store, "read_meta", real_read_meta)

    _assert_reject(r, "invalid_seat_token")
    snap_after = file_store.read_snapshot(match_id)
    assert snap_after == snap_before
    assert state_hash(snap_after) == hash_before
    assert file_store.read_events(match_id) == events_before


def test_world_unknown_action_type(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    r = _post(
        client,
        match_id,
        {"schema_version": 1, "action_type": "warp_unit", "actor_id": 0},
        tokens[0],
    )
    _assert_reject(r, "unknown_action_type")


def test_world_legacy_only_list_empty_after_n8b(client: TestClient) -> None:
    """N8b emptied LEGACY_ONLY_ACTION_TYPES; incomplete set_city_production
    reaches world validation (malformed_action) instead of the deferred
    unsupported_action_for_match_kind reject. Truly unknown types stay
    unknown_action_type (covered above)."""
    from app.domain import world_actions

    assert world_actions.LEGACY_ONLY_ACTION_TYPES == ()
    match_id, tokens, _ = _start_world_match(client)
    r = _post(
        client,
        match_id,
        {"schema_version": 2, "action_type": "set_city_production", "actor_id": 0},
        tokens[0],
    )
    _assert_reject(r, "malformed_action")


# ------------------------------------------------------- move_unit rejects


def test_move_unsupported_schema_version(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    r = _post(client, match_id, _move(0, 2, (2, 1), (3, 1), schema=2), tokens[0])
    _assert_reject(r, "unsupported_schema_version")


def test_move_schema_version_must_be_exact_int(client: TestClient) -> None:
    """Boolean True and float 1.0 both equal 1 in Python; exact JSON integer
    semantics reject them as unsupported_schema_version."""
    match_id, tokens, _ = _start_world_match(client)
    for schema in (True, 1.0):
        action = _move(0, 2, (2, 1), (3, 1))
        action["schema_version"] = schema
        _assert_reject(_post(client, match_id, action, tokens[0]), "unsupported_schema_version")


def test_move_boolean_ids_malformed(client: TestClient) -> None:
    """actor_id/unit_id must be exact (non-boolean) integers."""
    match_id, tokens, _ = _start_world_match(client)
    bad_unit = _move(0, 2, (2, 1), (3, 1))
    bad_unit["unit_id"] = True
    _assert_reject(_post(client, match_id, bad_unit, tokens[0]), "malformed_action")
    # actor_id True passes the credential gate as int 1, so post with the
    # actor-1 token; the world validator still rejects the boolean itself.
    bad_actor = _move(1, 3, (2, 14), (3, 14))
    bad_actor["actor_id"] = True
    _assert_reject(_post(client, match_id, bad_actor, tokens[1]), "malformed_action")


def test_domain_wrong_action_type_both_validators() -> None:
    """Domain-level: each validator rejects the other action type first."""
    snap = {"turn_state": {"players": [0, 1], "current_index": 0, "turn_number": 1}, "units": []}
    vr = world_actions.validate_move_unit_pre_map(snap, _end_turn(0))
    assert vr == {"ok": False, "reason": "wrong_action_type"}
    vr = world_actions.validate_end_turn(snap, _move(0, 2, (2, 1), (3, 1)))
    assert vr == {"ok": False, "reason": "wrong_action_type"}


def test_end_turn_schema_version_must_be_exact_int(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    for schema in (True, 1.0):
        action = _end_turn(0)
        action["schema_version"] = schema
        _assert_reject(_post(client, match_id, action, tokens[0]), "unsupported_schema_version")


def test_move_malformed_action(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    missing_to = {
        "schema_version": 1,
        "action_type": "move_unit",
        "actor_id": 0,
        "unit_id": 2,
        "from": [2, 1],
    }
    _assert_reject(_post(client, match_id, missing_to, tokens[0]), "malformed_action")
    bad_from = _move(0, 2, (2, 1), (3, 1))
    bad_from["from"] = ["2", "1"]
    _assert_reject(_post(client, match_id, bad_from, tokens[0]), "malformed_action")


def test_move_schema_error_precedes_actor_error(client: TestClient) -> None:
    """Locked order: unsupported_schema_version before not_current_player."""
    match_id, tokens, _ = _start_world_match(client)
    r = _post(client, match_id, _move(1, 3, (2, 14), (3, 14), schema=9), tokens[1])
    _assert_reject(r, "unsupported_schema_version")


def test_move_not_current_player(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    r = _post(client, match_id, _move(1, 3, (2, 14), (3, 14)), tokens[1])
    _assert_reject(r, "not_current_player")


def test_move_unknown_unit(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    r = _post(client, match_id, _move(0, 99, (2, 1), (3, 1)), tokens[0])
    _assert_reject(r, "unknown_unit")


def test_move_unit_not_owned_by_player(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    r = _post(client, match_id, _move(0, 3, (2, 14), (3, 14)), tokens[0])
    _assert_reject(r, "unit_not_owned_by_player")


def test_move_ownership_precedes_from_mismatch(client: TestClient) -> None:
    """Locked order: unit_not_owned_by_player before from_does_not_match."""
    match_id, tokens, _ = _start_world_match(client)
    r = _post(client, match_id, _move(0, 3, (9, 9), (3, 14)), tokens[0])
    _assert_reject(r, "unit_not_owned_by_player")


def test_move_from_does_not_match_unit_position(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    r = _post(client, match_id, _move(0, 2, (3, 1), (3, 0)), tokens[0])
    _assert_reject(r, "from_does_not_match_unit_position")


def test_move_destination_not_on_map(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    r = _post(client, match_id, _move(0, 2, (2, 1), (50, 50)), tokens[0])
    _assert_reject(r, "destination_not_on_map")


def test_move_destination_not_adjacent(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    r = _post(client, match_id, _move(0, 2, (2, 1), (5, 1)), tokens[0])
    _assert_reject(r, "destination_not_adjacent")


def test_move_destination_cliff_blocked_real_edge(client: TestClient) -> None:
    """A real cliff edge of the canonical map blocks movement."""
    match_id, tokens, _ = _start_world_match(client)
    wm = load_world_map(REFERENCE_MAP_ID)
    snap = file_store.read_snapshot(match_id)
    assert snap is not None
    other_positions = {
        (int(u["position"][0]), int(u["position"][1]))
        for u in snap["units"]
        if int(u["id"]) != 2
    }
    cliff = next(
        e
        for e in wm.all_edges()
        if e.transition == EDGE_CLIFF
        and e.tile_a not in other_positions
        and e.tile_b not in other_positions
    )
    _teleport_unit(match_id, 2, cliff.tile_a)
    r = _post(client, match_id, _move(0, 2, cliff.tile_a, cliff.tile_b), tokens[0])
    _assert_reject(r, "destination_cliff_blocked")


def test_move_destination_edge_missing_fail_closed() -> None:
    """Invariant guard: adjacent existing tiles without an edge record reject
    fail-closed (domain-level; cannot occur with derived canonical content)."""

    class _StubMap:
        def has_tile_coord(self, coord):
            return True

        def has_edge_between(self, a, b):
            return False

    snap = {"units": [], "turn_state": {"players": [0, 1], "current_index": 0, "turn_number": 1}}
    vr = world_actions.validate_move_unit_destination(
        _StubMap(), snap, _move(0, 2, (2, 1), (3, 1))
    )
    assert vr == {"ok": False, "reason": "destination_edge_missing"}


def test_move_destination_occupied(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    r = _post(client, match_id, _move(0, 1, (1, 1), (2, 1)), tokens[0])
    _assert_reject(r, "destination_occupied")


def test_move_has_no_movement_point_rejections(client: TestClient) -> None:
    """No movement_exhausted on the world path: many steps in one turn."""
    match_id, tokens, _ = _start_world_match(client)
    steps = [((2, 1), (3, 1)), ((3, 1), (3, 0)), ((3, 0), (2, 0)), ((2, 0), (2, 1))]
    for from_c, to_c in steps:
        r = _post(client, match_id, _move(0, 2, from_c, to_c), tokens[0])
        assert r.json()["accepted"] is True, r.text


# ----------------------------------------------------------- accepted flows


def test_accepted_move_revision_hash_event(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    before = file_store.read_snapshot(match_id)
    assert before is not None
    hash_before = state_hash(before)
    r = _post(client, match_id, _move(0, 2, (2, 1), (3, 1)), tokens[0])
    body = r.json()
    assert body["accepted"] is True and body["reason"] == ""
    assert body["revision"] == int(before["revision"]) + 1
    snap = body["snapshot"]
    assert snap["revision"] == body["revision"]
    unit2 = next(u for u in snap["units"] if u["id"] == 2)
    assert unit2["position"] == [3, 1]
    assert [u["id"] for u in snap["units"]] == [1, 2, 3, 4]
    assert body["state_hash"] == state_hash(snap)
    assert body["state_hash"] != hash_before
    ev = body["event"]
    assert ev["action_type"] == "move_unit"
    assert ev["actor_id"] == 0 and ev["unit_id"] == 2
    assert ev["from"] == [2, 1] and ev["to"] == [3, 1]
    assert ev["result"] == "accepted"
    assert ev["revision"] == body["revision"]
    assert "remaining_movement" not in ev
    # Persisted state matches the response.
    assert file_store.read_snapshot(match_id) == snap
    events = client.get(f"/v1/matches/{match_id}/events").json()["events"]
    assert events[-1]["action_type"] == "move_unit"
    assert events[-1]["index"] == ev["index"]


def test_end_turn_handoff(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    r = _post(client, match_id, _end_turn(0), tokens[0])
    body = r.json()
    assert body["accepted"] is True
    ev = body["event"]
    assert ev["action_type"] == "end_turn"
    assert ev["turn_number_before"] == 1
    assert ev["next_player_id"] == 1
    ts = body["snapshot"]["turn_state"]
    assert ts["current_index"] == 1 and ts["turn_number"] == 1
    # Units untouched by end_turn (no refresh/economy on the world path).
    assert body["snapshot"]["units"] == EXPECTED_SPAWN_UNITS
    # Handoff: player 1 can now move; player 0 cannot.
    r1 = _post(client, match_id, _move(1, 3, (2, 14), (3, 14)), tokens[1])
    assert r1.json()["accepted"] is True, r1.text
    r0 = _post(client, match_id, _move(0, 2, (2, 1), (3, 1)), tokens[0])
    _assert_reject(r0, "not_current_player")


def test_end_turn_rejects(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    _assert_reject(
        _post(client, match_id, _end_turn(0, schema=2), tokens[0]),
        "unsupported_schema_version",
    )
    _assert_reject(
        _post(
            client,
            match_id,
            {"schema_version": 1, "action_type": "end_turn"},
            token=tokens[0],
        ),
        "malformed_action",
    )
    _assert_reject(_post(client, match_id, _end_turn(1), tokens[1]), "not_current_player")


# ------------------------------------------- map identity mismatch (500)


def _tamper_content_hash(match_id: str) -> dict:
    snap = file_store.read_snapshot(match_id)
    assert snap is not None
    snap["map"]["content_hash"] = "0" * 64
    file_store.write_snapshot(match_id, snap)
    return snap


def test_move_map_mismatch_500_no_mutation(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    tampered = _tamper_content_hash(match_id)
    events_before = file_store.read_events(match_id)
    r = _post(client, match_id, _move(0, 2, (2, 1), (3, 1)), tokens[0])
    assert r.status_code == 500
    assert r.json()["detail"] == MISMATCH_DETAIL
    assert file_store.read_snapshot(match_id) == tampered
    assert file_store.read_events(match_id) == events_before


def test_end_turn_map_mismatch_500_no_mutation(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    tampered = _tamper_content_hash(match_id)
    events_before = file_store.read_events(match_id)
    r = _post(client, match_id, _end_turn(0), tokens[0])
    assert r.status_code == 500
    assert r.json()["detail"] == MISMATCH_DETAIL
    assert file_store.read_snapshot(match_id) == tampered
    assert file_store.read_events(match_id) == events_before


def _make_drifted_content_root(tmp_path: Path) -> Path:
    """Copy the canonical content root and change the reference map's raw
    bytes (trailing newline: JSON-valid, schema-valid, different SHA-256)."""
    canonical_root = resolve_content_root()
    drift_root = tmp_path / "drifted_maps"
    shutil.copytree(canonical_root, drift_root)
    map_file = _index_map_files(drift_root)[REFERENCE_MAP_ID]
    map_file.write_bytes(map_file.read_bytes() + b"\n")
    return drift_root


def test_move_real_content_drift_500_no_mutation(
    client: TestClient, tmp_path, monkeypatch
) -> None:
    """Real drift: a byte-different canonical file behind EMPIRE_MAP_CONTENT_DIR
    fails the raw-byte hash comparison with HTTP 500 and no mutation."""
    match_id, tokens, _ = _start_world_match(client)
    snap_before = file_store.read_snapshot(match_id)
    events_before = file_store.read_events(match_id)
    drift_root = _make_drifted_content_root(tmp_path)
    monkeypatch.setenv("EMPIRE_MAP_CONTENT_DIR", str(drift_root))
    r = _post(client, match_id, _move(0, 2, (2, 1), (3, 1)), tokens[0])
    assert r.status_code == 500
    assert r.json()["detail"] == MISMATCH_DETAIL
    assert file_store.read_snapshot(match_id) == snap_before
    assert file_store.read_events(match_id) == events_before


def test_end_turn_real_content_drift_500_no_mutation(
    client: TestClient, tmp_path, monkeypatch
) -> None:
    match_id, tokens, _ = _start_world_match(client)
    snap_before = file_store.read_snapshot(match_id)
    events_before = file_store.read_events(match_id)
    drift_root = _make_drifted_content_root(tmp_path)
    monkeypatch.setenv("EMPIRE_MAP_CONTENT_DIR", str(drift_root))
    r = _post(client, match_id, _end_turn(0), tokens[0])
    assert r.status_code == 500
    assert r.json()["detail"] == MISMATCH_DETAIL
    assert file_store.read_snapshot(match_id) == snap_before
    assert file_store.read_events(match_id) == events_before


def test_mismatch_runs_after_pre_map_validation(client: TestClient) -> None:
    """Map resolution sits after unit/from validation: a malformed move on a
    tampered match still rejects with the validation reason, not HTTP 500."""
    match_id, tokens, _ = _start_world_match(client)
    _tamper_content_hash(match_id)
    r = _post(client, match_id, _move(0, 99, (2, 1), (3, 1)), tokens[0])
    _assert_reject(r, "unknown_unit")


# ----------------------------------------------------------- legacy intact


def test_legacy_gameplay_unchanged(client: TestClient) -> None:
    from match_helpers import create_seated_match

    seated = create_seated_match(client, {"player_ids": [0, 1]})
    match_id = seated["match_id"]
    snap = file_store.read_snapshot(match_id)
    assert snap is not None
    assert snap["schema_version"] == 2
    assert "units" not in snap  # v2 units live inside scenario, not top-level
    assert "match_kind" not in snap
    r = _post(client, match_id, _end_turn(0), seated["host_token"])
    body = r.json()
    assert body["accepted"] is True
    assert body["snapshot"]["schema_version"] == 2
