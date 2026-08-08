"""N7b/N7g.2: world legal-actions — credential gate, envelope parity, derivation.

Covers: removal of the final 409; host/matching-seat/missing/invalid/wrong-
seat credentials (403 detail strings); out-of-turn empty response with the
legacy envelope; deterministic summaries and DIRECTIONS-ordered move rows
pinned against canonical content; all selection errors; cliff and occupied
destinations excluded; map-content drift failing closed (HTTP 500, strictly
read-only); every advertised action accepted by the N7a POST path on an
isolated equivalent match; legacy legal-actions remaining token-free and
unchanged. N7g.2 served attack legality: smooth-edge adjacent enemy
warriors advertised in the exact submit-ready N7g.1 wire shape, all attacks
before all moves, multiple targets in canonical DIRECTIONS order,
friendly/settler/non-adjacent/cliff/missing-edge targets excluded, attacked
units advertising nothing, summary counts equal to selected-unit rows
(attacks + moves), the attack round trip against an equivalent isolated
match, and read-only behavior with attack rows present.
"""

from __future__ import annotations

from fastapi.testclient import TestClient

from app.domain import world_legal_actions
from app.domain.hex_coord import DIRECTIONS
from app.domain.map_content_loader import load_world_map
from app.domain.state_hash import state_hash
from app.domain.world_map import EDGE_CLIFF, EDGE_SMOOTH
from app.storage import file_store
from match_helpers import SEAT_TOKEN_HEADER, create_seated_match
from test_world_combat_v3 import (
    _attack,
    _blocked_positions,
    _place_adjacent_cliff,
    _place_adjacent_smooth,
)
from test_world_map_actions_v3 import (
    MISMATCH_DETAIL,
    REFERENCE_MAP_ID,
    _delete_meta,
    _end_turn,
    _make_drifted_content_root,
    _post,
    _start_world_match,
    _teleport_unit,
)

# Pinned against canonical handdrawn_test_map_full_01 content: each spawn
# unit has exactly 5 legal destinations (one neighbor occupied by its group
# partner). DIRECTIONS order is E, NE, NW, W, SW, SE.
UNIT_1_DESTINATIONS = [[2, 0], [1, 0], [0, 1], [0, 2], [1, 2]]
UNIT_2_DESTINATIONS = [[3, 1], [3, 0], [2, 0], [1, 2], [2, 2]]


def _get_legal(
    client: TestClient,
    match_id: str,
    actor_id: int,
    token: str | None,
    **params,
):
    headers = {SEAT_TOKEN_HEADER: token} if token else {}
    return client.get(
        f"/v1/matches/{match_id}/legal-actions",
        params={"actor_id": actor_id, **params},
        headers=headers,
    )


def _move_row(actor_id: int, unit_id: int, from_c, to_c) -> dict:
    return {
        "schema_version": 1,
        "action_type": "move_unit",
        "actor_id": actor_id,
        "unit_id": unit_id,
        "from": list(from_c),
        "to": list(to_c),
    }


# ------------------------------------------------------------- credentials


def test_missing_token_403(client: TestClient) -> None:
    match_id, _, _ = _start_world_match(client)
    r = _get_legal(client, match_id, 0, token=None)
    assert r.status_code == 403
    assert r.json()["detail"] == "missing_seat_token"


def test_invalid_token_403(client: TestClient) -> None:
    match_id, _, _ = _start_world_match(client)
    r = _get_legal(client, match_id, 0, token="st_bogus")
    assert r.status_code == 403
    assert r.json()["detail"] == "invalid_seat_token"


def test_wrong_seat_token_403(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    r = _get_legal(client, match_id, 0, token=tokens[1])
    assert r.status_code == 403
    assert r.json()["detail"] == "seat_not_allowed"


def test_host_token_any_actor_200(client: TestClient) -> None:
    match_id, _, data = _start_world_match(client)
    for actor in (0, 1):
        r = _get_legal(client, match_id, actor, token=data["host_token"])
        assert r.status_code == 200, r.text


def test_matching_seat_token_200(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    r = _get_legal(client, match_id, 0, token=tokens[0])
    assert r.status_code == 200


def test_missing_meta_fails_closed(client: TestClient) -> None:
    """No metadata-free mode for world_map: with meta.json absent, a blank
    token is 403 missing_seat_token and any supplied token (even a previously
    valid seat token) is 403 invalid_seat_token — the request stops at the
    credential gate and stays read-only."""
    match_id, tokens, _ = _start_world_match(client)
    snap_before = file_store.read_snapshot(match_id)
    events_before = file_store.read_events(match_id)
    _delete_meta(match_id)

    r = _get_legal(client, match_id, 0, token=None)
    assert r.status_code == 403
    assert r.json()["detail"] == "missing_seat_token"
    r = _get_legal(client, match_id, 0, token=tokens[0])
    assert r.status_code == 403
    assert r.json()["detail"] == "invalid_seat_token"

    assert file_store.read_snapshot(match_id) == snap_before
    assert file_store.read_events(match_id) == events_before


# ------------------------------------------------------- envelope / summary


def test_out_of_turn_empty_response(client: TestClient) -> None:
    """Authenticated out-of-turn actor: 200 with is_current_player false and
    empty actions — no status gate, no current-player rejection."""
    match_id, tokens, _ = _start_world_match(client)
    r = _get_legal(client, match_id, 1, token=tokens[1])
    assert r.status_code == 200
    body = r.json()
    assert body["is_current_player"] is False
    assert body["actions"] == []
    assert body["selection_error"] is None
    # Legacy envelope parity: summaries are absent for out-of-turn actors.
    assert "unit_summaries" not in body and "city_summaries" not in body


def test_summary_mode_deterministic(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    r = _get_legal(client, match_id, 0, token=tokens[0])
    body = r.json()
    assert body["match_id"] == match_id
    assert body["revision"] == 0
    assert body["schema_version"] == 1
    assert body["actor_id"] == 0
    assert body["is_current_player"] is True
    assert body["selected_unit_id"] is None and body["selected_city_id"] is None
    assert body["selection_error"] is None
    assert body["actions"] == [
        {"schema_version": 1, "action_type": "end_turn", "actor_id": 0}
    ]
    assert body["unit_summaries"] == [
        {"unit_id": 1, "legal_action_count": 6},  # 5 moves + found_city (N8a)
        {"unit_id": 2, "legal_action_count": 5},
    ]
    assert body["city_summaries"] == []


# ------------------------------------------------- selected-unit move rows


def _found_city_row(actor_id: int, unit_id: int, pos) -> dict:
    return {
        "schema_version": 1,
        "action_type": "found_city",
        "actor_id": actor_id,
        "unit_id": unit_id,
        "position": list(pos),
    }


def test_selected_unit_rows_direction_order(client: TestClient) -> None:
    """Settler rows: found_city then moves in canonical DIRECTIONS order;
    the occupied partner tile (2,1) is excluded for unit 1."""
    match_id, tokens, _ = _start_world_match(client)
    r = _get_legal(client, match_id, 0, token=tokens[0], selected_unit_id=1)
    body = r.json()
    assert body["selected_unit_id"] == 1
    assert body["selection_error"] is None
    assert body["actions"] == [
        _found_city_row(0, 1, [1, 1]),
        *[_move_row(0, 1, [1, 1], to) for to in UNIT_1_DESTINATIONS],
    ]
    assert [2, 1] not in [a["to"] for a in body["actions"] if a["action_type"] == "move_unit"]


def test_summary_count_equals_selected_rows(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    summary = _get_legal(client, match_id, 0, token=tokens[0]).json()
    for row in summary["unit_summaries"]:
        sel = _get_legal(
            client, match_id, 0, token=tokens[0], selected_unit_id=row["unit_id"]
        ).json()
        assert row["legal_action_count"] == len(sel["actions"])
    sel2 = _get_legal(client, match_id, 0, token=tokens[0], selected_unit_id=2).json()
    assert sel2["actions"] == [_move_row(0, 2, [2, 1], to) for to in UNIT_2_DESTINATIONS]


def test_cliff_destination_excluded(client: TestClient) -> None:
    """A real canonical cliff edge never appears as an advertised move."""
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
    body = _get_legal(client, match_id, 0, token=tokens[0], selected_unit_id=2).json()
    destinations = [tuple(a["to"]) for a in body["actions"]]
    assert cliff.tile_b not in destinations
    # And every returned destination is a smooth-edge neighbor.
    for dest in destinations:
        assert wm.edge_between(cliff.tile_a, dest).transition == "smooth"


# --------------------------------------------------------- selection errors


def test_selection_unknown_unit(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    body = _get_legal(client, match_id, 0, token=tokens[0], selected_unit_id=99).json()
    assert body["selection_error"] == "unknown_unit"
    assert body["actions"] == []


def test_selection_not_owned(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    body = _get_legal(client, match_id, 0, token=tokens[0], selected_unit_id=3).json()
    assert body["selection_error"] == "selection_not_owned"
    assert body["actions"] == []


def test_selection_unknown_city(client: TestClient) -> None:
    """Absent city ids stay unknown_city (N8a cities start empty), including
    beside a valid owned unit selection (legacy precedence preserved)."""
    match_id, tokens, _ = _start_world_match(client)
    body = _get_legal(client, match_id, 0, token=tokens[0], selected_city_id=1).json()
    assert body["selection_error"] == "unknown_city"
    assert body["actions"] == []
    both = _get_legal(
        client, match_id, 0, token=tokens[0], selected_unit_id=1, selected_city_id=1
    ).json()
    assert both["selection_error"] == "unknown_city"
    assert both["actions"] == []


# ------------------------------------------------- drift + read-only checks


def test_content_drift_500_read_only(client: TestClient, tmp_path, monkeypatch) -> None:
    match_id, tokens, _ = _start_world_match(client)
    snap_before = file_store.read_snapshot(match_id)
    events_before = file_store.read_events(match_id)
    drift_root = _make_drifted_content_root(tmp_path)
    monkeypatch.setenv("EMPIRE_MAP_CONTENT_DIR", str(drift_root))
    r = _get_legal(client, match_id, 0, token=tokens[0])
    assert r.status_code == 500
    assert r.json()["detail"] == MISMATCH_DETAIL
    assert file_store.read_snapshot(match_id) == snap_before
    assert file_store.read_events(match_id) == events_before


def test_success_is_read_only(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    snap_before = file_store.read_snapshot(match_id)
    events_before = file_store.read_events(match_id)
    hash_before = state_hash(snap_before)
    for params in ({}, {"selected_unit_id": 1}, {"selected_unit_id": 99}):
        r = _get_legal(client, match_id, 0, token=tokens[0], **params)
        assert r.status_code == 200
    snap_after = file_store.read_snapshot(match_id)
    assert snap_after == snap_before
    assert state_hash(snap_after) == hash_before
    assert file_store.read_events(match_id) == events_before


# ---------------------------------------------------- submit-ready round trip


def test_every_advertised_action_accepted_by_n7a(client: TestClient) -> None:
    """Each advertised action, submitted against an isolated equivalent match
    (identical create + auto-start), is accepted by the N7a POST path."""
    match_id, tokens, _ = _start_world_match(client)
    summary = _get_legal(client, match_id, 0, token=tokens[0]).json()
    advertised: list[dict] = list(summary["actions"])  # end_turn
    for row in summary["unit_summaries"]:
        sel = _get_legal(
            client, match_id, 0, token=tokens[0], selected_unit_id=row["unit_id"]
        ).json()
        advertised.extend(sel["actions"])
    # end_turn + settler (5 moves + found_city) + warrior (5 moves)
    assert len(advertised) == 1 + 6 + 5
    for action in advertised:
        fresh_id, fresh_tokens, _ = _start_world_match(client)
        r = _post(client, fresh_id, action, fresh_tokens[0])
        assert r.status_code == 200, r.text
        assert r.json()["accepted"] is True, (action, r.text)


# ------------------------------------------- N7g.2 served attack legality


def _attack_row(actor_id: int, attacker_id: int, defender_id: int) -> dict:
    return {
        "schema_version": 1,
        "action_type": "attack_unit",
        "actor_id": actor_id,
        "attacker_id": attacker_id,
        "defender_id": defender_id,
    }


def _spawn_extra_enemy_warrior(match_id: str, unit_id: int, pos: tuple[int, int]) -> None:
    """Test fixture only: add a well-formed enemy warrior row to the
    persisted snapshot (ascending id order kept)."""
    snap = file_store.read_snapshot(match_id)
    assert snap is not None
    snap["units"].append(
        {
            "id": unit_id,
            "owner_id": 1,
            "position": [pos[0], pos[1]],
            "type_id": "warrior",
            "current_hp": 100,
            "has_attacked": False,
        }
    )
    snap["units"].sort(key=lambda u: int(u["id"]))
    file_store.write_snapshot(match_id, snap)


def test_adjacent_enemy_warrior_advertised_attacks_before_moves(client: TestClient) -> None:
    """A smooth-edge adjacent enemy warrior yields exactly one attack row in
    the exact N7g.1 submit-ready shape, ordered BEFORE every move row; the
    occupied defender tile is excluded from the moves."""
    match_id, tokens, _ = _start_world_match(client)
    a_pos, d_pos = _place_adjacent_smooth(match_id)
    body = _get_legal(client, match_id, 0, token=tokens[0], selected_unit_id=2).json()
    assert body["selection_error"] is None
    attacks = [a for a in body["actions"] if a["action_type"] == "attack_unit"]
    moves = [a for a in body["actions"] if a["action_type"] == "move_unit"]
    assert attacks == [_attack_row(0, 2, 4)]
    assert set(attacks[0].keys()) == {
        "schema_version", "action_type", "actor_id", "attacker_id", "defender_id",
    }
    # Deterministic ordering: ALL attacks first, then all moves.
    assert body["actions"] == attacks + moves
    assert len(moves) >= 1
    assert list(d_pos) not in [a["to"] for a in moves]
    # Moves keep DIRECTIONS order of the destination tile.
    dirs = [
        (a["to"][0] - a_pos[0], a["to"][1] - a_pos[1]) for a in moves
    ]
    order = [DIRECTIONS.index(d) for d in dirs]
    assert order == sorted(order)


def test_multiple_targets_in_canonical_direction_order(client: TestClient) -> None:
    """Two adjacent enemy warriors are advertised in canonical DIRECTIONS
    order of the DEFENDER tile."""
    match_id, tokens, _ = _start_world_match(client)
    wm = load_world_map(REFERENCE_MAP_ID)
    blocked = _blocked_positions(match_id, {2, 4})
    placed = None
    for e in wm.all_edges():
        if e.transition != EDGE_SMOOTH:
            continue
        a, b = e.tile_a, e.tile_b
        if a in blocked or b in blocked:
            continue
        for d in DIRECTIONS:
            c = (b[0] + d[0], b[1] + d[1])
            if c == a or c in blocked or not wm.has_tile_coord(c):
                continue
            if (
                wm.has_edge_between(b, c)
                and wm.edge_between(b, c).transition == EDGE_SMOOTH
            ):
                placed = (a, b, c)
                break
        if placed:
            break
    assert placed is not None, "no smooth two-neighbor tile found"
    a, b, c = placed
    _teleport_unit(match_id, 2, b)  # own warrior in the middle
    _teleport_unit(match_id, 4, a)  # enemy warrior on one side
    _spawn_extra_enemy_warrior(match_id, 5, c)  # enemy warrior on the other
    body = _get_legal(client, match_id, 0, token=tokens[0], selected_unit_id=2).json()
    attacks = [x for x in body["actions"] if x["action_type"] == "attack_unit"]
    dir_of = {
        4: DIRECTIONS.index((a[0] - b[0], a[1] - b[1])),
        5: DIRECTIONS.index((c[0] - b[0], c[1] - b[1])),
    }
    expected_ids = sorted([4, 5], key=lambda uid: dir_of[uid])
    assert [x["defender_id"] for x in attacks] == expected_ids
    assert attacks == [_attack_row(0, 2, uid) for uid in expected_ids]
    # Ordering invariant holds with multiple attacks too.
    moves = [x for x in body["actions"] if x["action_type"] == "move_unit"]
    assert body["actions"] == attacks + moves


def test_friendly_settler_and_nonadjacent_targets_excluded(client: TestClient) -> None:
    """Friendly adjacent units and adjacent enemy SETTLERS never produce
    attack rows; the default far-apart spawns produce none either."""
    match_id, tokens, _ = _start_world_match(client)
    # Default spawns: enemy warrior far away, own settler adjacent.
    body = _get_legal(client, match_id, 0, token=tokens[0], selected_unit_id=2).json()
    assert [x for x in body["actions"] if x["action_type"] == "attack_unit"] == []
    # Adjacent enemy SETTLER: still no attack rows (defender_not_warrior).
    wm = load_world_map(REFERENCE_MAP_ID)
    blocked = _blocked_positions(match_id, {2, 3})
    edge = next(
        e
        for e in wm.all_edges()
        if e.transition == EDGE_SMOOTH
        and e.tile_a not in blocked
        and e.tile_b not in blocked
    )
    _teleport_unit(match_id, 2, edge.tile_a)
    _teleport_unit(match_id, 3, edge.tile_b)
    body = _get_legal(client, match_id, 0, token=tokens[0], selected_unit_id=2).json()
    assert [x for x in body["actions"] if x["action_type"] == "attack_unit"] == []
    # A selected own SETTLER adjacent to an enemy warrior stays move-only.
    match_id2, tokens2, _ = _start_world_match(client)
    blocked2 = _blocked_positions(match_id2, {1, 4})
    edge2 = next(
        e
        for e in wm.all_edges()
        if e.transition == EDGE_SMOOTH
        and e.tile_a not in blocked2
        and e.tile_b not in blocked2
    )
    _teleport_unit(match_id2, 1, edge2.tile_a)
    _teleport_unit(match_id2, 4, edge2.tile_b)
    body2 = _get_legal(client, match_id2, 0, token=tokens2[0], selected_unit_id=1).json()
    # Settler stays non-attacking; N8a may also advertise found_city.
    assert all(x["action_type"] in ("move_unit", "found_city") for x in body2["actions"])
    assert not any(x["action_type"] == "attack_unit" for x in body2["actions"])


def test_cliff_and_missing_edge_targets_excluded(client: TestClient) -> None:
    """An adjacent enemy warrior across a real cliff edge is never advertised;
    a missing edge record excludes the target fail-closed (domain-level)."""
    match_id, tokens, _ = _start_world_match(client)
    _place_adjacent_cliff(match_id)
    body = _get_legal(client, match_id, 0, token=tokens[0], selected_unit_id=2).json()
    assert [x for x in body["actions"] if x["action_type"] == "attack_unit"] == []

    class _StubMap:
        def has_tile_coord(self, coord):
            return True

        def has_edge_between(self, a, b):
            return False

    snap = {
        "match_id": "m_stub",
        "revision": 0,
        "turn_state": {"players": [0, 1], "current_index": 0, "turn_number": 1},
        "units": [
            {"id": 2, "owner_id": 0, "position": [2, 1], "type_id": "warrior", "current_hp": 100, "has_attacked": False},
            {"id": 4, "owner_id": 1, "position": [3, 1], "type_id": "warrior", "current_hp": 100, "has_attacked": False},
        ],
    }
    payload = world_legal_actions.compute_world_legal_actions_payload(
        snap, _StubMap(), 0, 2, None
    )
    assert payload["actions"] == []


def test_attacked_unit_advertises_nothing(client: TestClient) -> None:
    """After an accepted attack the attacker advertises zero attacks AND zero
    moves; the summary count is 0; End Turn re-arms it."""
    match_id, tokens, _ = _start_world_match(client)
    _place_adjacent_smooth(match_id)
    r = _post(client, match_id, _attack(0, 2, 4), tokens[0])
    assert r.json()["accepted"] is True, r.text
    sel = _get_legal(client, match_id, 0, token=tokens[0], selected_unit_id=2).json()
    assert sel["actions"] == []
    summary = _get_legal(client, match_id, 0, token=tokens[0]).json()
    row = next(s for s in summary["unit_summaries"] if s["unit_id"] == 2)
    assert row["legal_action_count"] == 0
    # End Turn x2 back to player 0: attacks and moves are advertised again.
    assert _post(client, match_id, _end_turn(0), tokens[0]).json()["accepted"] is True
    assert _post(client, match_id, _end_turn(1), tokens[1]).json()["accepted"] is True
    sel2 = _get_legal(client, match_id, 0, token=tokens[0], selected_unit_id=2).json()
    kinds = [x["action_type"] for x in sel2["actions"]]
    assert "attack_unit" in kinds and "move_unit" in kinds


def test_summary_counts_include_attacks(client: TestClient) -> None:
    """unit_summaries count attacks + found_city + moves and equal the
    selected-unit row count exactly; the settler stays non-attacking."""
    match_id, tokens, _ = _start_world_match(client)
    _place_adjacent_smooth(match_id)
    summary = _get_legal(client, match_id, 0, token=tokens[0]).json()
    for row in summary["unit_summaries"]:
        sel = _get_legal(
            client, match_id, 0, token=tokens[0], selected_unit_id=row["unit_id"]
        ).json()
        assert row["legal_action_count"] == len(sel["actions"])
    warrior_sel = _get_legal(client, match_id, 0, token=tokens[0], selected_unit_id=2).json()
    warrior_attacks = [x for x in warrior_sel["actions"] if x["action_type"] == "attack_unit"]
    assert len(warrior_attacks) == 1
    warrior_row = next(s for s in summary["unit_summaries"] if s["unit_id"] == 2)
    assert warrior_row["legal_action_count"] == len(warrior_sel["actions"])
    settler_sel = _get_legal(client, match_id, 0, token=tokens[0], selected_unit_id=1).json()
    assert all(x["action_type"] in ("move_unit", "found_city") for x in settler_sel["actions"])
    assert not any(x["action_type"] == "attack_unit" for x in settler_sel["actions"])


def test_advertised_attack_accepted_by_n7g1(client: TestClient) -> None:
    """Every advertised action of the adjacent-warriors state — attack rows
    included — is accepted by the POST path on an equivalent isolated match
    (same deterministic placement)."""
    match_id, tokens, _ = _start_world_match(client)
    _place_adjacent_smooth(match_id)
    advertised: list[dict] = []
    summary = _get_legal(client, match_id, 0, token=tokens[0]).json()
    for row in summary["unit_summaries"]:
        sel = _get_legal(
            client, match_id, 0, token=tokens[0], selected_unit_id=row["unit_id"]
        ).json()
        advertised.extend(sel["actions"])
    assert any(a["action_type"] == "attack_unit" for a in advertised)
    for action in advertised:
        fresh_id, fresh_tokens, _ = _start_world_match(client)
        _place_adjacent_smooth(fresh_id)  # deterministic: same edge scan
        r = _post(client, fresh_id, action, fresh_tokens[0])
        assert r.status_code == 200, r.text
        assert r.json()["accepted"] is True, (action, r.text)


def test_attack_rows_read_only(client: TestClient) -> None:
    """Serving attack rows (success AND selection-error rejection) never
    writes: snapshot, hash, and events stay identical."""
    match_id, tokens, _ = _start_world_match(client)
    _place_adjacent_smooth(match_id)
    snap_before = file_store.read_snapshot(match_id)
    events_before = file_store.read_events(match_id)
    hash_before = state_hash(snap_before)
    for params in ({}, {"selected_unit_id": 2}, {"selected_unit_id": 99}):
        r = _get_legal(client, match_id, 0, token=tokens[0], **params)
        assert r.status_code == 200
    snap_after = file_store.read_snapshot(match_id)
    assert snap_after == snap_before
    assert state_hash(snap_after) == hash_before
    assert file_store.read_events(match_id) == events_before


# ----------------------------------------------------------- legacy intact


def test_legacy_legal_actions_token_free_unchanged(client: TestClient) -> None:
    seated = create_seated_match(client, {"player_ids": [0, 1]})
    match_id = seated["match_id"]
    r = client.get(f"/v1/matches/{match_id}/legal-actions", params={"actor_id": 0})
    assert r.status_code == 200
    body = r.json()
    assert body["schema_version"] == 1
    assert body["is_current_player"] is True
    assert any(a["action_type"] == "end_turn" for a in body["actions"])
    assert "unit_summaries" in body and "city_summaries" in body
