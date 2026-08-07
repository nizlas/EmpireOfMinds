"""N7g.1: server-authoritative World Combat 0.1 on the world_map path.

Covers: additive snapshot combat fields (registry-derived current_hp,
has_attacked=false, no max_hp/movement/counters), the complete locked
attack_unit first-failure rejection order with exact-integer semantics,
smooth-edge legality plus missing-edge/cliff fail-closed rejections through
the SAME edge source movement uses, exact shared Local Combat 0.1 math
parity (BASE_DAMAGE 30, exp((atk-def)/25), clamp 1..100), retaliation and
eliminations with deterministic unit ordering, the has_attacked turn gate
(no second attack, no move after attack, move-before-attack stays free,
End Turn resets), revision/persistence/event/state-hash/readback and
no-write-on-rejection invariants, fail-closed map drift (HTTP 500, no
mutation), and unchanged legacy behavior.
"""

from __future__ import annotations

from fastapi.testclient import TestClient

from app.domain import world_actions
from app.domain.combat_rules import (
    BASE_DAMAGE,
    MAX_DAMAGE,
    MIN_DAMAGE,
    STRENGTH_DIVISOR,
    damage_for_strengths,
    resolve_combat,
)
from app.domain.content import unit_definitions
from app.domain.hex_coord import DIRECTIONS
from app.domain.map_content_loader import load_world_map
from app.domain.state_hash import state_hash
from app.domain.world_map import EDGE_CLIFF, EDGE_SMOOTH
from app.storage import file_store
from match_helpers import SEAT_TOKEN_HEADER
from test_world_map_actions_v3 import (
    MISMATCH_DETAIL,
    REFERENCE_MAP_ID,
    _assert_reject,
    _create_world,
    _end_turn,
    _make_drifted_content_root,
    _move,
    _post,
    _start_world_match,
    _tamper_content_hash,
    _teleport_unit,
)

WARRIOR_STRENGTH = unit_definitions.combat_strength_for_type("warrior")
WARRIOR_MAX_HP = unit_definitions.max_hp_for_type("warrior")

# The full legacy-shaped combat event (exact key parity with the legacy
# attack_unit event envelope).
EXPECTED_EVENT_KEYS = {
    "index", "revision", "schema_version", "action_type", "actor_id",
    "attacker_id", "defender_id", "attacker_position", "defender_position",
    "attacker_strength", "defender_strength",
    "attacker_damage_taken", "defender_damage_taken",
    "attacker_hp_before", "defender_hp_before",
    "attacker_hp_after", "defender_hp_after",
    "attacker_killed", "defender_killed", "retaliated",
    "result", "accepted_at",
}


def _attack(actor_id, attacker_id, defender_id, schema=1) -> dict:
    return {
        "schema_version": schema,
        "action_type": "attack_unit",
        "actor_id": actor_id,
        "attacker_id": attacker_id,
        "defender_id": defender_id,
    }


def _set_unit_hp(match_id: str, unit_id: int, hp: int) -> None:
    """Test fixture only: adjust a unit's current_hp in the persisted snapshot."""
    snap = file_store.read_snapshot(match_id)
    assert snap is not None
    for u in snap["units"]:
        if int(u["id"]) == unit_id:
            u["current_hp"] = hp
    file_store.write_snapshot(match_id, snap)


def _blocked_positions(match_id: str, moving_ids: set[int]) -> set[tuple[int, int]]:
    snap = file_store.read_snapshot(match_id)
    assert snap is not None
    return {
        (int(u["position"][0]), int(u["position"][1]))
        for u in snap["units"]
        if int(u["id"]) not in moving_ids
    }


def _place_adjacent_smooth(match_id: str) -> tuple[tuple[int, int], tuple[int, int]]:
    """Teleport warrior 2 and enemy warrior 4 onto a real SMOOTH canonical
    edge (both tiles free of the other units)."""
    wm = load_world_map(REFERENCE_MAP_ID)
    blocked = _blocked_positions(match_id, {2, 4})
    edge = next(
        e
        for e in wm.all_edges()
        if e.transition == EDGE_SMOOTH
        and e.tile_a not in blocked
        and e.tile_b not in blocked
    )
    _teleport_unit(match_id, 2, edge.tile_a)
    _teleport_unit(match_id, 4, edge.tile_b)
    return edge.tile_a, edge.tile_b


def _place_adjacent_cliff(match_id: str) -> None:
    """Teleport the two warriors onto a real CLIFF canonical edge."""
    wm = load_world_map(REFERENCE_MAP_ID)
    blocked = _blocked_positions(match_id, {2, 4})
    edge = next(
        e
        for e in wm.all_edges()
        if e.transition == EDGE_CLIFF
        and e.tile_a not in blocked
        and e.tile_b not in blocked
    )
    _teleport_unit(match_id, 2, edge.tile_a)
    _teleport_unit(match_id, 4, edge.tile_b)


def _place_smooth_chain(match_id: str) -> tuple[tuple[int, int], tuple[int, int], tuple[int, int]]:
    """Find tiles a-b-c with smooth a-b and b-c edges; put warrior 2 on a and
    enemy warrior 4 on c (move a->b then attack b->c)."""
    wm = load_world_map(REFERENCE_MAP_ID)
    blocked = _blocked_positions(match_id, {2, 4})
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
                _teleport_unit(match_id, 2, a)
                _teleport_unit(match_id, 4, c)
                return a, b, c
    raise AssertionError("no smooth a-b-c chain found on the reference map")


# ------------------------------------------------- snapshot combat fields


def test_initial_snapshot_combat_fields_from_registry(client: TestClient) -> None:
    data = _create_world(client)
    units = data["snapshot"]["units"]
    assert [u["id"] for u in units] == [1, 2, 3, 4]
    for u in units:
        assert u["current_hp"] == unit_definitions.max_hp_for_type(str(u["type_id"]))
        assert u["has_attacked"] is False
        # Additive only: still no max_hp, movement, moved flags, counters.
        assert set(u.keys()) == {
            "id", "owner_id", "position", "type_id", "current_hp", "has_attacked",
        }
    assert data["snapshot"]["schema_version"] == 3
    assert "next_unit_id" not in data["snapshot"]
    assert "cities" not in data["snapshot"]


# --------------------------------------------------------- rejection order


def test_attack_wrong_action_type_domain_level() -> None:
    snap = {"turn_state": {"players": [0, 1], "current_index": 0, "turn_number": 1}, "units": []}
    vr = world_actions.validate_attack_unit_pre_map(snap, _move(0, 2, (0, 0), (1, 0)))
    assert vr == {"ok": False, "reason": "wrong_action_type"}


def test_attack_rejection_order_via_api(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    snap_before = file_store.read_snapshot(match_id)
    events_before = file_store.read_events(match_id)

    # unsupported_schema_version: wrong int, boolean, and float (exact
    # non-boolean JSON integer semantics).
    _assert_reject(_post(client, match_id, _attack(0, 2, 4, schema=2), tokens[0]), "unsupported_schema_version")
    _assert_reject(_post(client, match_id, _attack(0, 2, 4, schema=True), tokens[0]), "unsupported_schema_version")
    _assert_reject(_post(client, match_id, _attack(0, 2, 4, schema=1.0), tokens[0]), "unsupported_schema_version")

    # malformed_action: missing key, boolean id, string id.
    incomplete = _attack(0, 2, 4)
    incomplete.pop("defender_id")
    _assert_reject(_post(client, match_id, incomplete, tokens[0]), "malformed_action")
    _assert_reject(_post(client, match_id, _attack(0, True, 4), tokens[0]), "malformed_action")
    _assert_reject(_post(client, match_id, _attack(0, 2, "4"), tokens[0]), "malformed_action")

    # not_current_player wins over every later unit check (unknown ids here).
    _assert_reject(_post(client, match_id, _attack(1, 99, 98), tokens[1]), "not_current_player")

    # unknown_attacker before unknown_defender (both unknown here).
    _assert_reject(_post(client, match_id, _attack(0, 99, 98), tokens[0]), "unknown_attacker")
    _assert_reject(_post(client, match_id, _attack(0, 2, 98), tokens[0]), "unknown_defender")

    # actor_not_owner: attacking WITH the enemy warrior.
    _assert_reject(_post(client, match_id, _attack(0, 4, 2), tokens[0]), "actor_not_owner")

    # warrior-vs-warrior only (locked): settler attacker / settler defender.
    _assert_reject(_post(client, match_id, _attack(0, 1, 4), tokens[0]), "attacker_not_warrior")
    _assert_reject(_post(client, match_id, _attack(0, 2, 3), tokens[0]), "defender_not_warrior")

    # cannot_attack_own_unit (attacker == defender is the same-owner case).
    _assert_reject(_post(client, match_id, _attack(0, 2, 2), tokens[0]), "cannot_attack_own_unit")

    # defender_not_adjacent: the spawn warriors are far apart.
    _assert_reject(_post(client, match_id, _attack(0, 2, 4), tokens[0]), "defender_not_adjacent")

    # No rejection wrote anything.
    assert file_store.read_snapshot(match_id) == snap_before
    assert file_store.read_events(match_id) == events_before


def test_attacker_already_attacked_precedes_adjacency(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    _place_adjacent_smooth(match_id)
    r = _post(client, match_id, _attack(0, 2, 4), tokens[0])
    assert r.json()["accepted"] is True, r.text
    # Immediate second attack: attacker_already_attacked.
    _assert_reject(_post(client, match_id, _attack(0, 2, 4), tokens[0]), "attacker_already_attacked")
    # Order proof: even against a now NON-adjacent defender the state check
    # fires first (already_attacked sits before adjacency in the pre-map
    # phase, which runs before map resolution).
    far = _blocked_positions(match_id, {4})  # occupied tiles to avoid
    wm = load_world_map(REFERENCE_MAP_ID)
    spot = next(
        t for t in [(2, 14), (3, 14), (1, 14)] if wm.has_tile_coord(t) and t not in far
    )
    _teleport_unit(match_id, 4, spot)
    _assert_reject(_post(client, match_id, _attack(0, 2, 4), tokens[0]), "attacker_already_attacked")


def test_attack_edge_missing_fail_closed() -> None:
    """Invariant guard (domain-level, like movement): adjacent existing tiles
    without an edge record reject fail-closed — never treated as attackable."""

    class _StubMap:
        def has_tile_coord(self, coord):
            return True

        def has_edge_between(self, a, b):
            return False

    snap = {
        "turn_state": {"players": [0, 1], "current_index": 0, "turn_number": 1},
        "units": [
            {"id": 2, "owner_id": 0, "position": [2, 1], "type_id": "warrior", "current_hp": 100, "has_attacked": False},
            {"id": 4, "owner_id": 1, "position": [3, 1], "type_id": "warrior", "current_hp": 100, "has_attacked": False},
        ],
    }
    vr = world_actions.validate_attack_unit_target(_StubMap(), snap, _attack(0, 2, 4))
    assert vr == {"ok": False, "reason": "attack_edge_missing"}


def test_attack_cliff_blocked_real_edge(client: TestClient) -> None:
    """A real canonical cliff edge blocks melee fail-closed — the SAME edge
    legality source movement uses."""
    match_id, tokens, _ = _start_world_match(client)
    _place_adjacent_cliff(match_id)
    snap_before = file_store.read_snapshot(match_id)
    events_before = file_store.read_events(match_id)
    _assert_reject(_post(client, match_id, _attack(0, 2, 4), tokens[0]), "attack_cliff_blocked")
    assert file_store.read_snapshot(match_id) == snap_before
    assert file_store.read_events(match_id) == events_before


# ------------------------------------------------------------ accepted flow


def test_accepted_attack_smooth_edge_full_invariants(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    a_pos, d_pos = _place_adjacent_smooth(match_id)
    before = file_store.read_snapshot(match_id)
    assert before is not None
    events_len_before = len(file_store.read_events(match_id))

    r = _post(client, match_id, _attack(0, 2, 4), tokens[0])
    body = r.json()
    assert body["accepted"] is True and body["reason"] == ""

    # Exact shared-core math parity (warrior 20 vs 20, 100 HP each).
    expected = resolve_combat(
        WARRIOR_STRENGTH, WARRIOR_STRENGTH, WARRIOR_MAX_HP, WARRIOR_MAX_HP
    )
    ev = body["event"]
    assert set(ev.keys()) == EXPECTED_EVENT_KEYS
    for key, want in expected.items():
        assert ev[key] == want, key
    assert ev["attacker_id"] == 2 and ev["defender_id"] == 4
    assert ev["actor_id"] == 0 and ev["action_type"] == "attack_unit"
    assert ev["attacker_position"] == [a_pos[0], a_pos[1]]
    assert ev["defender_position"] == [d_pos[0], d_pos[1]]
    assert ev["result"] == "accepted"
    # Equal strengths: BASE_DAMAGE both ways, retaliation, both survive.
    assert ev["defender_damage_taken"] == BASE_DAMAGE
    assert ev["attacker_damage_taken"] == BASE_DAMAGE
    assert ev["retaliated"] is True
    assert ev["attacker_killed"] is False and ev["defender_killed"] is False

    # Revision bumped exactly once; response event/index appended.
    assert body["revision"] == int(before["revision"]) + 1
    assert body["index"] == ev["index"] == events_len_before

    snap = body["snapshot"]
    assert snap["revision"] == body["revision"]
    unit2 = next(u for u in snap["units"] if u["id"] == 2)
    unit4 = next(u for u in snap["units"] if u["id"] == 4)
    # Surviving defender: attacker stays on its original tile (no capture).
    assert unit2["current_hp"] == WARRIOR_MAX_HP - BASE_DAMAGE
    assert unit2["has_attacked"] is True
    assert unit2["position"] == [a_pos[0], a_pos[1]]
    # Surviving defender: damaged only.
    assert unit4["current_hp"] == WARRIOR_MAX_HP - BASE_DAMAGE
    assert unit4["has_attacked"] is False
    assert unit4["position"] == [d_pos[0], d_pos[1]]
    assert [u["id"] for u in snap["units"]] == [1, 2, 3, 4]

    # Persistence + state hash + reconnect readback.
    assert file_store.read_snapshot(match_id) == snap
    assert body["state_hash"] == state_hash(snap)
    readback = client.get(f"/v1/matches/{match_id}").json()["snapshot"]
    assert readback == snap
    events = client.get(f"/v1/matches/{match_id}/events").json()["events"]
    assert len(events) == events_len_before + 1
    assert events[-1]["action_type"] == "attack_unit"
    assert events[-1]["index"] == ev["index"]


def test_defender_elimination_no_retaliation(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    a_pos, d_pos = _place_adjacent_smooth(match_id)
    _set_unit_hp(match_id, 4, BASE_DAMAGE)  # dies to one base hit
    r = _post(client, match_id, _attack(0, 2, 4), tokens[0])
    body = r.json()
    assert body["accepted"] is True
    ev = body["event"]
    assert ev["defender_killed"] is True and ev["defender_hp_after"] == 0
    assert ev["retaliated"] is False
    assert ev["attacker_damage_taken"] == 0 and ev["attacker_killed"] is False
    # Event positions remain the PRE-combat tiles (not presentation fields).
    assert ev["attacker_position"] == [a_pos[0], a_pos[1]]
    assert ev["defender_position"] == [d_pos[0], d_pos[1]]
    units = body["snapshot"]["units"]
    # Deterministic ascending ordering after elimination.
    assert [u["id"] for u in units] == [1, 2, 3]
    unit2 = next(u for u in units if u["id"] == 2)
    assert unit2["current_hp"] == WARRIOR_MAX_HP  # no retaliation damage
    assert unit2["has_attacked"] is True
    # Authoritative capture: surviving attacker occupies the defender's tile.
    assert unit2["position"] == [d_pos[0], d_pos[1]]
    assert all(u["id"] != 4 for u in units)
    # Reconnect/readback converges on the captured-tile position.
    readback = client.get(f"/v1/matches/{match_id}").json()["snapshot"]
    assert next(u for u in readback["units"] if u["id"] == 2)["position"] == [
        d_pos[0],
        d_pos[1],
    ]
    # Post-capture legality observes the new position + has_attacked gate.
    legal = client.get(
        f"/v1/matches/{match_id}/legal-actions",
        headers={SEAT_TOKEN_HEADER: tokens[0]},
        params={"actor_id": 0, "selected_unit_id": 2},
    ).json()
    assert legal["revision"] == body["revision"]
    assert legal["actions"] == []


def test_attacker_elimination_by_retaliation(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    a_pos, d_pos = _place_adjacent_smooth(match_id)
    _set_unit_hp(match_id, 2, BASE_DAMAGE)  # dies to the retaliation
    r = _post(client, match_id, _attack(0, 2, 4), tokens[0])
    body = r.json()
    assert body["accepted"] is True
    ev = body["event"]
    assert ev["defender_killed"] is False
    assert ev["retaliated"] is True
    assert ev["attacker_killed"] is True and ev["attacker_hp_after"] == 0
    units = body["snapshot"]["units"]
    assert [u["id"] for u in units] == [1, 3, 4]
    unit4 = next(u for u in units if u["id"] == 4)
    assert unit4["current_hp"] == WARRIOR_MAX_HP - BASE_DAMAGE
    assert unit4["has_attacked"] is False
    # Attacker killed by retaliation: no capture; defender stays put.
    assert unit4["position"] == [d_pos[0], d_pos[1]]
    assert all(u["id"] != 2 for u in units)
    # The defender's former tile is NOT occupied by a surviving attacker.
    assert all(u["position"] != [a_pos[0], a_pos[1]] or u["id"] != 2 for u in units)
    readback = client.get(f"/v1/matches/{match_id}").json()["snapshot"]
    assert [u["id"] for u in readback["units"]] == [1, 3, 4]
    assert next(u for u in readback["units"] if u["id"] == 4)["position"] == [
        d_pos[0],
        d_pos[1],
    ]


# ------------------------------------------------------- has_attacked gate


def test_move_before_attack_free_move_after_attack_gated(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    a, b, c = _place_smooth_chain(match_id)

    # Pre-attack movement stays budget-free.
    r = _post(client, match_id, _move(0, 2, a, b), tokens[0])
    assert r.json()["accepted"] is True, r.text

    # Move-then-attack in the same turn is legal.
    r = _post(client, match_id, _attack(0, 2, 4), tokens[0])
    assert r.json()["accepted"] is True, r.text

    # After attacking: no more movement, no second attack.
    _assert_reject(_post(client, match_id, _move(0, 2, b, a), tokens[0]), "unit_already_attacked")
    _assert_reject(_post(client, match_id, _attack(0, 2, 4), tokens[0]), "attacker_already_attacked")

    # Accepted end_turn clears has_attacked for ALL units while advancing.
    r = _post(client, match_id, _end_turn(0), tokens[0])
    body = r.json()
    assert body["accepted"] is True
    assert all(u["has_attacked"] is False for u in body["snapshot"]["units"])

    # The damaged defender can still act normally on its own turn.
    wm = load_world_map(REFERENCE_MAP_ID)
    blocked = _blocked_positions(match_id, {4})
    dest = next(
        (c[0] + d[0], c[1] + d[1])
        for d in DIRECTIONS
        if wm.has_tile_coord((c[0] + d[0], c[1] + d[1]))
        and (c[0] + d[0], c[1] + d[1]) not in blocked
        and wm.has_edge_between(c, (c[0] + d[0], c[1] + d[1]))
        and wm.edge_between(c, (c[0] + d[0], c[1] + d[1])).transition == EDGE_SMOOTH
    )
    r = _post(client, match_id, _move(1, 4, c, dest), tokens[1])
    assert r.json()["accepted"] is True, r.text
    r = _post(client, match_id, _end_turn(1), tokens[1])
    assert r.json()["accepted"] is True

    # Back at player 0: the reset re-arms both movement and attacking.
    r = _post(client, match_id, _move(0, 2, b, a), tokens[0])
    assert r.json()["accepted"] is True, r.text


def test_attack_reset_allows_next_turn_attack(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    _place_adjacent_smooth(match_id)
    assert _post(client, match_id, _attack(0, 2, 4), tokens[0]).json()["accepted"] is True
    assert _post(client, match_id, _end_turn(0), tokens[0]).json()["accepted"] is True
    assert _post(client, match_id, _end_turn(1), tokens[1]).json()["accepted"] is True
    r = _post(client, match_id, _attack(0, 2, 4), tokens[0])
    body = r.json()
    assert body["accepted"] is True, r.text
    # Second exchange continues from the persisted damaged HP.
    assert body["event"]["attacker_hp_before"] == WARRIOR_MAX_HP - BASE_DAMAGE
    assert body["event"]["defender_hp_before"] == WARRIOR_MAX_HP - BASE_DAMAGE


# ------------------------------------------------------------- math parity


def test_shared_combat_core_parity_and_clamps() -> None:
    # Locked constants.
    assert BASE_DAMAGE == 30 and STRENGTH_DIVISOR == 25.0
    assert MIN_DAMAGE == 1 and MAX_DAMAGE == 100
    # Equal strengths: exactly BASE_DAMAGE.
    assert damage_for_strengths(20, 20) == 30
    # Exponential scaling with divisor 25 and 1..100 clamping.
    assert damage_for_strengths(45, 20) == round(30 * 2.718281828459045)  # e^1
    assert damage_for_strengths(200, 0) == 100
    assert damage_for_strengths(0, 200) == 1
    # Retaliation only while the defender survives; elimination at 0.
    survives = resolve_combat(20, 20, 100, 100)
    assert survives["retaliated"] is True
    assert survives["attacker_hp_after"] == 70 and survives["defender_hp_after"] == 70
    kill = resolve_combat(20, 20, 100, 30)
    assert kill["defender_killed"] is True and kill["retaliated"] is False
    assert kill["attacker_hp_after"] == 100 and kill["attacker_damage_taken"] == 0


def test_world_resolver_uses_shared_core_and_registry() -> None:
    snap = {
        "turn_state": {"players": [0, 1], "current_index": 0, "turn_number": 1},
        "units": [
            {"id": 2, "owner_id": 0, "position": [2, 1], "type_id": "warrior", "current_hp": 55, "has_attacked": False},
            {"id": 4, "owner_id": 1, "position": [3, 1], "type_id": "warrior", "current_hp": 80, "has_attacked": False},
        ],
    }
    got = world_actions.resolve_attack_combat(snap, _attack(0, 2, 4))
    assert got == {
        "attacker_id": 2,
        "defender_id": 4,
        **resolve_combat(WARRIOR_STRENGTH, WARRIOR_STRENGTH, 55, 80),
    }


def test_apply_attack_unit_tile_occupation_branches() -> None:
    """Authoritative capture rule: survive → stay; kill → occupy; die → none."""
    base = {
        "revision": 3,
        "turn_state": {"players": [0, 1], "current_index": 0, "turn_number": 1},
        "units": [
            {"id": 2, "owner_id": 0, "position": [2, 1], "type_id": "warrior", "current_hp": 100, "has_attacked": False},
            {"id": 4, "owner_id": 1, "position": [3, 1], "type_id": "warrior", "current_hp": 100, "has_attacked": False},
        ],
    }
    # Defender survives: attacker stays put.
    both = world_actions.apply_attack_unit(
        base,
        _attack(0, 2, 4),
        {
            "attacker_hp_after": 70,
            "defender_hp_after": 70,
            "attacker_killed": False,
            "defender_killed": False,
        },
    )
    assert next(u for u in both["units"] if u["id"] == 2)["position"] == [2, 1]
    assert next(u for u in both["units"] if u["id"] == 2)["has_attacked"] is True
    assert next(u for u in both["units"] if u["id"] == 4)["position"] == [3, 1]

    # Defender dies, attacker survives: capture the defender's tile.
    kill = world_actions.apply_attack_unit(
        base,
        _attack(0, 2, 4),
        {
            "attacker_hp_after": 100,
            "defender_hp_after": 0,
            "attacker_killed": False,
            "defender_killed": True,
        },
    )
    assert [u["id"] for u in kill["units"]] == [2]
    unit2 = kill["units"][0]
    assert unit2["position"] == [3, 1]
    assert unit2["current_hp"] == 100 and unit2["has_attacked"] is True

    # Attacker dies to retaliation: no capture.
    atk_dies = world_actions.apply_attack_unit(
        base,
        _attack(0, 2, 4),
        {
            "attacker_hp_after": 0,
            "defender_hp_after": 70,
            "attacker_killed": True,
            "defender_killed": False,
        },
    )
    assert [u["id"] for u in atk_dies["units"]] == [4]
    assert atk_dies["units"][0]["position"] == [3, 1]


# --------------------------------------------- drift / no-write invariants


def test_attack_map_mismatch_500_no_mutation(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    _place_adjacent_smooth(match_id)
    tampered = _tamper_content_hash(match_id)
    events_before = file_store.read_events(match_id)
    r = _post(client, match_id, _attack(0, 2, 4), tokens[0])
    assert r.status_code == 500
    assert r.json()["detail"] == MISMATCH_DETAIL
    assert file_store.read_snapshot(match_id) == tampered
    assert file_store.read_events(match_id) == events_before


def test_attack_mismatch_runs_after_pre_map_validation(client: TestClient) -> None:
    """Map resolution sits after the unit/state phase: a pre-map-invalid
    attack on a tampered match rejects with the validation reason, not 500."""
    match_id, tokens, _ = _start_world_match(client)
    _tamper_content_hash(match_id)
    _assert_reject(_post(client, match_id, _attack(0, 99, 98), tokens[0]), "unknown_attacker")


def test_attack_real_content_drift_500_no_mutation(
    client: TestClient, tmp_path, monkeypatch
) -> None:
    match_id, tokens, _ = _start_world_match(client)
    _place_adjacent_smooth(match_id)
    snap_before = file_store.read_snapshot(match_id)
    events_before = file_store.read_events(match_id)
    drift_root = _make_drifted_content_root(tmp_path)
    monkeypatch.setenv("EMPIRE_MAP_CONTENT_DIR", str(drift_root))
    r = _post(client, match_id, _attack(0, 2, 4), tokens[0])
    assert r.status_code == 500
    assert r.json()["detail"] == MISMATCH_DETAIL
    assert file_store.read_snapshot(match_id) == snap_before
    assert file_store.read_events(match_id) == events_before


# ------------------------------------------------------------ legacy intact


def test_legacy_attack_and_snapshot_unchanged(client: TestClient) -> None:
    """The legacy path still resolves attack_unit through the Scenario module
    with snapshot v2 — no world fields leak in."""
    from match_helpers import create_seated_match

    seated = create_seated_match(client, {"player_ids": [0, 1]})
    match_id = seated["match_id"]
    snap = file_store.read_snapshot(match_id)
    assert snap is not None
    assert snap["schema_version"] == 2
    assert "units" not in snap and "match_kind" not in snap
    r = _post(client, match_id, _end_turn(0), seated["host_token"])
    assert r.json()["accepted"] is True
    assert r.json()["snapshot"]["schema_version"] == 2
