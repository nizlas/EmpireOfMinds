"""N8R single-gameplay-core guards: canonical city rules, behavioral parity,
and dependency walls.

Four layers:

1. Pure-rule behavior: the canonical founding/production decision sequences,
   naming, project state, tick/completion, and delivery — exercised with
   plain facts, requiring NO Scenario, HexMap, WorldMap, presentation,
   transport, snapshot, or persistence.
2. Behavioral parity: equivalent gameplay facts fed through the deprecated
   Scenario adapter and the active WorldMap adapter produce the SAME
   decisions and the same semantic transitions — there is one algorithm, not
   two that happen to agree today.
3. Single-implementation guards (limited structural): patching the one
   canonical rule changes BOTH state adapters and the world legal-action
   generation, so no adapter carries a private copy of the rule.
4. Dependency walls (AST, no execution): the canonical rule modules stay
   map-/transport-/persistence-free, and the world domain modules never
   import deprecated Scenario/HexMap snapshot-v2 gameplay orchestration.
"""

from __future__ import annotations

import ast
from pathlib import Path

import pytest

from app.domain import (
    city_founding_rules as cfr,
    city_production_rules as cpr,
    world_actions,
    world_legal_actions,
)
from app.domain.actions import found_city as legacy_found_city
from app.domain.actions import set_city_production as legacy_scp
from app.domain.hex_coord import HexCoord
from app.domain.hex_map import HexMap, Terrain, make_tiny_test_map
from app.domain.progress_state import ProgressState
from app.domain.scenario import Scenario
from app.domain.unit import Unit

# --------------------------------------------------------- canonical naming


def test_default_city_name_sequence() -> None:
    assert cfr.default_city_name(0) == "Capital"
    assert cfr.default_city_name(1) == "Settlement 2"
    assert cfr.default_city_name(2) == "Settlement 3"
    assert cfr.default_city_name(9) == "Settlement 10"


# ------------------------------------------------- canonical founding rules


def _founder(owner=1, type_id="settler", pos=(1, 1)) -> cfr.FounderFacts:
    return cfr.FounderFacts(owner_id=owner, type_id=type_id, position=pos)


def _validate_found(**overrides):
    kwargs = dict(
        actor_id=1,
        current_player_id=1,
        founder=_founder(),
        position=(1, 1),
        tile_has_city=False,
    )
    kwargs.update(overrides)
    return cfr.validate_found_city(**kwargs)


def test_found_city_accepts_valid_settler() -> None:
    assert _validate_found() == {"ok": True, "reason": ""}


@pytest.mark.parametrize(
    ("overrides", "reason"),
    [
        ({"current_player_id": 2}, "not_current_player"),
        ({"founder": None}, "unknown_unit"),
        ({"founder": _founder(owner=2)}, "unit_not_owned_by_player"),
        ({"founder": _founder(type_id="warrior")}, "unit_cannot_found_city"),
        ({"founder": _founder(pos=(0, 1))}, "unit_not_at_position"),
        ({"tile_on_map": False}, "tile_not_on_map"),
        ({"tile_is_water": True}, "tile_is_water"),
        ({"tile_has_city": True}, "tile_already_has_city"),
        ({"tile_is_owned": True}, "tile_already_owned"),
    ],
)
def test_found_city_locked_rejections(overrides, reason) -> None:
    vr = _validate_found(**overrides)
    assert vr == {"ok": False, "reason": reason}


def test_found_city_locked_first_failure_order() -> None:
    # Every later defect present at once: the earliest reason wins, in the
    # locked chain order (unit checks, then map facts in legacy layer order).
    vr = _validate_found(
        current_player_id=2,
        founder=_founder(owner=2, type_id="warrior", pos=(9, 9)),
        tile_has_city=True,
        tile_on_map=False,
        tile_is_water=True,
        tile_is_owned=True,
    )
    assert vr["reason"] == "not_current_player"
    vr = _validate_found(
        founder=_founder(owner=2, type_id="warrior", pos=(9, 9)),
        tile_has_city=True,
    )
    assert vr["reason"] == "unit_not_owned_by_player"
    vr = _validate_found(
        founder=_founder(type_id="warrior", pos=(9, 9)), tile_has_city=True
    )
    assert vr["reason"] == "unit_cannot_found_city"
    vr = _validate_found(founder=_founder(pos=(9, 9)), tile_has_city=True)
    assert vr["reason"] == "unit_not_at_position"
    vr = _validate_found(tile_on_map=False, tile_is_water=True, tile_has_city=True)
    assert vr["reason"] == "tile_not_on_map"
    vr = _validate_found(tile_is_water=True, tile_has_city=True, tile_is_owned=True)
    assert vr["reason"] == "tile_is_water"
    vr = _validate_found(tile_has_city=True, tile_is_owned=True)
    assert vr["reason"] == "tile_already_has_city"


def test_found_city_transition_is_the_complete_apply_result() -> None:
    """The pure canonical transition decides the COMPLETE map-independent
    founding apply: consumed founder, allocated city id, advanced counter,
    owner/position/name/capital/empty project — as one immutable value."""
    t = cfr.found_city_transition(
        owner_id=7,
        founder_unit_id=12,
        position=(3, 4),
        owned_city_count=0,
        next_city_id=5,
    )
    assert t == cfr.FoundCityTransition(
        consumed_unit_id=12,
        city_id=5,
        next_city_id=6,
        owner_id=7,
        position=(3, 4),
        name="Capital",
        is_capital=True,
        current_project=None,
    )
    with pytest.raises(Exception):
        t.city_id = 99  # immutable

    later = cfr.found_city_transition(
        owner_id=7,
        founder_unit_id=13,
        position=(3, 4),
        owned_city_count=2,
        next_city_id=6,
    )
    assert later.name == "Settlement 3"
    assert later.is_capital is False
    assert later.consumed_unit_id == 13
    assert later.city_id == 6 and later.next_city_id == 7


# ----------------------------------------------- canonical production rules


def _city(owner=1, active=None) -> cpr.CityProductionFacts:
    return cpr.CityProductionFacts(owner_id=owner, active_project_id=active)


def _validate_prod(**overrides):
    kwargs = dict(
        actor_id=1,
        current_player_id=1,
        city=_city(),
        project_id="produce_unit:warrior",
    )
    kwargs.update(overrides)
    return cpr.validate_set_city_production(**kwargs)


def test_set_production_accepts_registry_project_and_clear() -> None:
    assert _validate_prod() == {"ok": True, "reason": ""}
    assert _validate_prod(
        city=_city(active="produce_unit:warrior"), project_id="produce_unit:settler"
    )["ok"]
    assert _validate_prod(city=_city(active="produce_unit:warrior"), project_id="none")[
        "ok"
    ]


@pytest.mark.parametrize(
    ("overrides", "reason"),
    [
        ({"current_player_id": 2}, "not_current_player"),
        ({"city": None}, "unknown_city"),
        ({"city": _city(owner=2)}, "city_not_owned_by_player"),
        ({"project_id": "produce_unit:archer"}, "unknown_city_project"),
        (
            {"is_project_unlocked": lambda _pid: False},
            "city_project_not_unlocked",
        ),
        (
            {"city": _city(active="produce_unit:warrior")},
            "project_already_set",
        ),
        ({"project_id": "none"}, "project_already_set"),
    ],
)
def test_set_production_locked_rejections(overrides, reason) -> None:
    vr = _validate_prod(**overrides)
    assert vr == {"ok": False, "reason": reason}


def test_unlock_gate_is_a_policy_input_not_a_second_validator() -> None:
    """The unlock difference between the paths is an explicit policy input
    around the SAME rule: no policy (WorldMap) accepts, a denying policy
    (deprecated Scenario path) rejects, an allowing policy accepts, and
    clearing production is never gated."""
    assert _validate_prod()["ok"]
    assert _validate_prod(is_project_unlocked=lambda pid: True)["ok"]
    denied = _validate_prod(is_project_unlocked=lambda pid: False)
    assert denied == {"ok": False, "reason": "city_project_not_unlocked"}
    assert _validate_prod(
        city=_city(active="produce_unit:warrior"),
        project_id="none",
        is_project_unlocked=lambda pid: False,
    )["ok"]


def test_new_project_state_uses_registry_costs() -> None:
    assert cpr.new_project_state("none") is None
    assert cpr.new_project_state("produce_unit:warrior") == {
        "project_id": "produce_unit:warrior",
        "progress": 0,
        "cost": 2,
    }
    assert cpr.new_project_state("produce_unit:settler")["cost"] == 2


def test_project_progress_for_event_representation() -> None:
    assert cpr.project_progress_for_event(None) is None
    assert cpr.project_progress_for_event("bogus") is None
    assert cpr.project_progress_for_event({}) is None
    assert (
        cpr.project_progress_for_event(
            {"project_id": "produce_unit:warrior", "progress": 1, "cost": 2}
        )
        == 1
    )
    assert cpr.active_project_id(None) is None
    assert cpr.active_project_id({"project_id": "produce_unit:settler"}) == (
        "produce_unit:settler"
    )


def test_flat_production_constant_is_canonical() -> None:
    assert cpr.FLAT_PRODUCTION_PER_CITY == 1


# --------------------------------------- canonical tick/delivery (pure facts)


def _prod_city(
    cid: int,
    owner: int = 0,
    pos: tuple[int, int] = (0, 0),
    project: dict | None = None,
) -> cpr.ProducingCityFacts:
    return cpr.ProducingCityFacts(
        city_id=cid, owner_id=owner, position=pos, current_project=project
    )


def _v3_project(progress: int = 0, cost: int = 2, pid: str = "produce_unit:warrior") -> dict:
    return {"project_id": pid, "progress": progress, "cost": cost}


def test_project_completion_is_derived_not_stored() -> None:
    assert cpr.project_is_complete(None) is False
    assert cpr.project_is_complete(_v3_project(progress=1, cost=2)) is False
    assert cpr.project_is_complete(_v3_project(progress=2, cost=2)) is True
    # Snapshot-v2 shape (stored project_type) resolves identically.
    assert (
        cpr.project_is_complete(
            {
                "project_type": "produce_unit",
                "project_id": "produce_unit:settler",
                "progress": 5,
                "cost": 2,
                "ready": True,
            }
        )
        is True
    )


def test_tick_accrues_in_city_id_order_and_builds_engine_events() -> None:
    cities = [
        _prod_city(5, pos=(1, -1), project=_v3_project(cost=50)),
        _prod_city(3, pos=(0, 0), project=_v3_project(cost=50)),
        _prod_city(9, owner=1, project=_v3_project(cost=50)),  # other owner
        _prod_city(11, project=None),  # no project
    ]
    new_projects, events = cpr.tick_production(cities, 0, {3: 1, 5: 2, 9: 7, 11: 4})
    assert sorted(new_projects.keys()) == [3, 5]
    assert new_projects[3]["progress"] == 1
    assert new_projects[5]["progress"] == 2
    assert [e["city_id"] for e in events] == [3, 5]
    e = events[0]
    assert e["action_type"] == "production_progress"
    assert e["actor_id"] == 0
    assert e["project_type"] == "produce_unit"
    assert e["progress_before"] == 0 and e["progress_after"] == 1
    assert e["cost"] == 50
    assert e["source"] == "engine" and e["result"] == "accepted"
    assert e["project_id"] == "produce_unit:warrior"


def test_tick_skips_complete_projects_and_zero_yield() -> None:
    cities = [
        _prod_city(1, project=_v3_project(progress=2, cost=2)),  # complete
        _prod_city(2, project=_v3_project()),  # zero yield
    ]
    new_projects, events = cpr.tick_production(cities, 0, {1: 1, 2: 0})
    assert new_projects == {} and events == []


def test_tick_keeps_stored_ready_key_synchronized() -> None:
    v2 = {
        "project_type": "produce_unit",
        "project_id": "produce_unit:warrior",
        "progress": 1,
        "cost": 2,
        "ready": False,
    }
    new_projects, _ = cpr.tick_production([_prod_city(1, project=v2)], 0, {1: 1})
    assert new_projects[1]["ready"] is True
    assert new_projects[1]["progress"] == 2
    # v3-shaped projects never grow a ready key: completion stays derived.
    new_projects, _ = cpr.tick_production(
        [_prod_city(2, project=_v3_project(progress=1))], 0, {2: 1}
    )
    assert "ready" not in new_projects[2]


def test_delivery_allocates_sequential_ids_clears_and_builds_events() -> None:
    cities = [
        _prod_city(4, pos=(2, 2), project=_v3_project(progress=2)),
        _prod_city(2, pos=(1, 1), project=_v3_project(progress=3, pid="produce_unit:settler")),
        _prod_city(6, owner=1, pos=(3, 3), project=_v3_project(progress=2)),  # other owner
        _prod_city(8, pos=(4, 4), project=_v3_project(progress=1)),  # incomplete
    ]
    spawns, events, next_uid = cpr.deliver_completed_production(cities, 0, 40)
    assert next_uid == 42
    assert [s["city_id"] for s in spawns] == [2, 4]
    assert [s["unit_id"] for s in spawns] == [40, 41]
    assert [s["owner_id"] for s in spawns] == [0, 0]
    assert spawns[0]["unit_type_id"] == "settler"
    assert spawns[0]["position"] == (1, 1)
    assert spawns[1]["unit_type_id"] == "warrior"
    ev = events[0]
    assert ev["action_type"] == "unit_produced"
    assert ev["unit_id"] == 40 and ev["city_id"] == 2
    assert ev["position"] == [1, 1]
    assert ev["project_type"] == "produce_unit"
    assert ev["unit_type_id"] == "settler"
    assert ev["source"] == "engine" and ev["result"] == "accepted"
    assert ev["project_id"] == "produce_unit:settler"


def test_delivery_no_complete_projects_is_a_no_op() -> None:
    spawns, events, next_uid = cpr.deliver_completed_production(
        [_prod_city(1, project=_v3_project(progress=1))], 0, 7
    )
    assert spawns == [] and events == [] and next_uid == 7


def test_delivery_resolver_can_defer_without_allocating_or_clearing() -> None:
    """N8c placement deferral lives in the ONE delivery loop via resolver."""
    cities = [
        _prod_city(1, pos=(0, 0), project=_v3_project(progress=2)),
        _prod_city(2, pos=(1, 0), project=_v3_project(progress=2, pid="produce_unit:settler")),
    ]
    occupied: set[tuple[int, int]] = {(0, 0)}

    def resolve(city: cpr.ProducingCityFacts, occ: set[tuple[int, int]]):
        # City 1 blocked; city 2 places on its center when free.
        if city.position in occ:
            return None
        return city.position

    spawns, events, next_uid = cpr.deliver_completed_production(
        cities,
        0,
        10,
        occupied_positions=occupied,
        resolve_spawn_position=resolve,
    )
    assert [s["city_id"] for s in spawns] == [2]
    assert spawns[0]["unit_id"] == 10
    assert next_uid == 11
    assert events[0]["city_id"] == 2
    # Deferred city 1 never consumed an id.


def test_delivery_resolver_updates_occupancy_across_ready_cities() -> None:
    cities = [
        _prod_city(1, pos=(0, 0), project=_v3_project(progress=2)),
        _prod_city(2, pos=(0, 0), project=_v3_project(progress=2, pid="produce_unit:settler")),
    ]
    # Both cities share the same preferred tile; the second must fall back.

    def resolve(city: cpr.ProducingCityFacts, occ: set[tuple[int, int]]):
        first = city.position
        if first not in occ:
            return first
        alt = (1, 0)
        if alt not in occ:
            return alt
        return None

    spawns, _, next_uid = cpr.deliver_completed_production(
        cities,
        0,
        5,
        occupied_positions=set(),
        resolve_spawn_position=resolve,
    )
    assert [s["position"] for s in spawns] == [(0, 0), (1, 0)]
    assert [s["unit_id"] for s in spawns] == [5, 6]
    assert next_uid == 7


def test_n8c_can_tick_and_deliver_from_flat_yields_without_scenario() -> None:
    """N8c readiness: the SAME canonical loop runs from snapshot-v3-shaped
    facts and the flat yield constant — no Scenario, HexMap, snapshot
    persistence, or new loop required."""
    cities = [
        _prod_city(1, pos=(0, 0), project=_v3_project(progress=1, cost=2)),
        _prod_city(2, pos=(1, 0), project=_v3_project(cost=2, pid="produce_unit:settler")),
    ]
    yields = {c.city_id: cpr.FLAT_PRODUCTION_PER_CITY for c in cities}
    new_projects, tick_events = cpr.tick_production(cities, 0, yields)
    assert new_projects[1]["progress"] == 2 and new_projects[2]["progress"] == 1
    assert len(tick_events) == 2

    after_tick = [
        _prod_city(1, pos=(0, 0), project=new_projects[1]),
        _prod_city(2, pos=(1, 0), project=new_projects[2]),
    ]
    spawns, up_events, next_uid = cpr.deliver_completed_production(after_tick, 0, 10)
    assert [s["city_id"] for s in spawns] == [1]
    assert spawns[0]["unit_type_id"] == "warrior"
    assert next_uid == 11
    assert up_events[0]["action_type"] == "unit_produced"


# ------------------------------------- behavioral parity: one algorithm, two
# state adapters (deprecated Scenario vs active snapshot v3)


def _parity_scenario(with_city_at_origin: bool = False) -> Scenario:
    m = make_tiny_test_map()
    units = (
        Unit.make(1, 0, HexCoord(0, 0), "settler", 2, 100),
        Unit.make(2, 0, HexCoord(1, 0), "warrior", 2, 100),
        Unit.make(3, 1, HexCoord(0, -1), "settler", 2, 100),
    )
    cities = ()
    next_city_id = 1
    sc = Scenario(m, units, cities, 4, next_city_id, None)
    if with_city_at_origin:
        sc = legacy_found_city.apply_found_city(
            sc,
            {
                "schema_version": 1,
                "action_type": "found_city",
                "actor_id": 0,
                "unit_id": 1,
                "position": [0, 0],
            },
        )
    return sc


def _parity_snapshot(with_city_at_origin: bool = False) -> dict:
    units = [
        {"id": 1, "owner_id": 0, "position": [0, 0], "type_id": "settler", "current_hp": 70, "has_attacked": False},
        {"id": 2, "owner_id": 0, "position": [1, 0], "type_id": "warrior", "current_hp": 100, "has_attacked": False},
        {"id": 3, "owner_id": 1, "position": [0, -1], "type_id": "settler", "current_hp": 70, "has_attacked": False},
    ]
    snap = {
        "match_id": "m_parity",
        "revision": 0,
        "turn_state": {"players": [0, 1], "current_index": 0, "turn_number": 1},
        "units": units,
        "cities": [],
        "next_city_id": 1,
        "next_unit_id": 4,
    }
    if with_city_at_origin:
        snap = world_actions.apply_found_city(
            snap,
            {
                "schema_version": 1,
                "action_type": "found_city",
                "actor_id": 0,
                "unit_id": 1,
                "position": [0, 0],
            },
        )
    return snap


def _found_action(unit_id: int = 1, position: list | None = None, actor_id: int = 0) -> dict:
    return {
        "schema_version": 1,
        "action_type": "found_city",
        "actor_id": actor_id,
        "unit_id": unit_id,
        "position": position if position is not None else [0, 0],
    }


@pytest.mark.parametrize(
    ("action_kwargs", "with_city", "expected_reason"),
    [
        ({}, False, ""),  # accept
        ({"unit_id": 99}, False, "unknown_unit"),
        ({"unit_id": 3, "position": [0, -1]}, False, "unit_not_owned_by_player"),
        ({"unit_id": 2, "position": [1, 0]}, False, "unit_cannot_found_city"),
        ({"position": [1, 0]}, False, "unit_not_at_position"),
        ({"unit_id": 2, "position": [0, 0]}, True, "unit_cannot_found_city"),
    ],
)
def test_founding_decision_parity_between_state_adapters(
    action_kwargs, with_city, expected_reason
) -> None:
    """Equivalent founder/tile facts through BOTH state adapters produce the
    identical canonical decision (legacy actor==current: the API owns that
    gate on the deprecated path)."""
    act = _found_action(**action_kwargs)
    legacy_vr = legacy_found_city.validate(_parity_scenario(with_city), act)
    world_vr = world_actions.validate_found_city(_parity_snapshot(with_city), act)
    assert legacy_vr == world_vr
    assert legacy_vr["reason"] == expected_reason


def test_founding_tile_occupied_parity() -> None:
    # After player 0 founded at the origin, a second founding attempt on the
    # same tile rejects identically on both paths (settler 3 moved onto it).
    sc = _parity_scenario(with_city_at_origin=True)
    snap = _parity_snapshot(with_city_at_origin=True)
    # Teleport the enemy settler onto the city tile in both states, then let
    # its owner attempt to found there.
    sc = Scenario(
        sc.map,
        tuple(
            Unit.make(u.id, u.owner_id, HexCoord(0, 0), u.type_id, 2, 100)
            if u.id == 3
            else u
            for u in sc.units()
        ),
        sc.cities(),
        4,
        sc.peek_next_city_id(),
        None,
    )
    snap = {
        **snap,
        "turn_state": {"players": [0, 1], "current_index": 1, "turn_number": 1},
        "units": [
            {**u, "position": [0, 0]} if int(u["id"]) == 3 else u
            for u in snap["units"]
        ],
    }
    act = _found_action(unit_id=3, position=[0, 0], actor_id=1)
    legacy_vr = legacy_found_city.validate(sc, act)
    world_vr = world_actions.validate_found_city(snap, act)
    assert legacy_vr == world_vr == {"ok": False, "reason": "tile_already_has_city"}


def test_founding_transition_parity_between_state_adapters() -> None:
    """The accepted founding transition is semantically identical on both
    paths: founder consumed, one city appended with the canonical name at the
    founder's tile, owner's next founding named by the same sequence."""
    sc2 = legacy_found_city.apply_found_city(_parity_scenario(), _found_action())
    snap2 = world_actions.apply_found_city(_parity_snapshot(), _found_action())

    legacy_city = sc2.city_by_id(1)
    world_city = next(c for c in snap2["cities"] if int(c["id"]) == 1)
    assert legacy_city is not None
    assert str(legacy_city.city_name) == str(world_city["name"]) == "Capital"
    assert [legacy_city.position.q, legacy_city.position.r] == world_city["position"]
    assert legacy_city.current_project is None
    assert world_city["current_project"] is None
    assert sc2.unit_by_id(1) is None
    assert all(int(u["id"]) != 1 for u in snap2["units"])
    assert sc2.peek_next_city_id() == int(snap2["next_city_id"]) == 2
    # Same canonical naming sequence for the owner's next city.
    assert legacy_found_city.default_city_name_for_owner(sc2, 0) == "Settlement 2"
    t = cfr.found_city_transition(
        owner_id=0,
        founder_unit_id=2,
        position=(1, 0),
        owned_city_count=1,
        next_city_id=2,
    )
    assert t.name == "Settlement 2" and t.is_capital is False


def _scp_action(city_id: int = 1, project_id: str = "produce_unit:warrior", actor_id: int = 0) -> dict:
    return {
        "schema_version": 2,
        "action_type": "set_city_production",
        "actor_id": actor_id,
        "city_id": city_id,
        "project_id": project_id,
    }


def _default_progress() -> ProgressState:
    return ProgressState.with_default_unlocks_for_players([0, 1])


@pytest.mark.parametrize(
    ("action_kwargs", "expected_reason"),
    [
        ({}, ""),  # accept
        ({"city_id": 99}, "unknown_city"),
        ({"project_id": "produce_unit:archer"}, "unknown_city_project"),
        ({"project_id": "none"}, "project_already_set"),  # nothing to clear
    ],
)
def test_production_decision_parity_between_state_adapters(
    action_kwargs, expected_reason
) -> None:
    sc = _parity_scenario(with_city_at_origin=True)
    snap = _parity_snapshot(with_city_at_origin=True)
    act = _scp_action(**action_kwargs)
    legacy_vr = legacy_scp.validate(sc, _default_progress(), act)
    world_vr = world_actions.validate_set_city_production(snap, act)
    assert legacy_vr == world_vr
    assert legacy_vr["reason"] == expected_reason


def test_production_already_set_parity() -> None:
    sc = legacy_scp.apply_set_city_production(
        _parity_scenario(with_city_at_origin=True), _scp_action()
    )
    snap = world_actions.apply_set_city_production(
        _parity_snapshot(with_city_at_origin=True), _scp_action()
    )
    act = _scp_action()  # same project again
    legacy_vr = legacy_scp.validate(sc, _default_progress(), act)
    world_vr = world_actions.validate_set_city_production(snap, act)
    assert legacy_vr == world_vr == {"ok": False, "reason": "project_already_set"}


def test_production_transition_parity_core_state() -> None:
    """Both adapters materialize the SAME canonical project core; the
    deprecated snapshot-v2 shape only adds its storage keys around it."""
    sc = legacy_scp.apply_set_city_production(
        _parity_scenario(with_city_at_origin=True), _scp_action()
    )
    snap = world_actions.apply_set_city_production(
        _parity_snapshot(with_city_at_origin=True), _scp_action()
    )
    legacy_project = sc.city_by_id(1).current_project
    world_project = next(c for c in snap["cities"] if int(c["id"]) == 1)[
        "current_project"
    ]
    core_keys = ("project_id", "progress", "cost")
    assert {k: legacy_project[k] for k in core_keys} == world_project
    assert set(legacy_project.keys()) - set(core_keys) == {"project_type", "ready"}
    # Clearing parity.
    clear = _scp_action(project_id="none")
    sc2 = legacy_scp.apply_set_city_production(sc, clear)
    snap2 = world_actions.apply_set_city_production(snap, clear)
    assert sc2.city_by_id(1).current_project is None
    assert next(c for c in snap2["cities"] if int(c["id"]) == 1)["current_project"] is None


# ------------------------------ single-implementation guards (limited patch)


def test_both_state_adapters_route_founding_through_one_rule(monkeypatch) -> None:
    """Patching the ONE canonical founding validator changes BOTH the
    deprecated Scenario adapter and the active WorldMap adapter: neither
    carries a private algorithm."""
    monkeypatch.setattr(
        cfr, "validate_found_city", lambda **_: {"ok": False, "reason": "one_core"}
    )
    assert legacy_found_city.validate(_parity_scenario(), _found_action()) == {
        "ok": False,
        "reason": "one_core",
    }
    assert world_actions.validate_found_city(_parity_snapshot(), _found_action()) == {
        "ok": False,
        "reason": "one_core",
    }


def test_both_state_adapters_materialize_the_one_founding_transition(
    monkeypatch,
) -> None:
    """Patching the ONE canonical founding transition changes the APPLY
    result of BOTH state adapters — neither independently decides founder
    consumption, city-id allocation, or next-city-id advancement."""
    sentinel = cfr.FoundCityTransition(
        consumed_unit_id=2,  # not the unit named in the action
        city_id=77,
        next_city_id=99,
        owner_id=0,
        position=(0, 0),
        name="One Core",
        is_capital=False,
    )
    monkeypatch.setattr(cfr, "found_city_transition", lambda **_: sentinel)

    sc2 = legacy_found_city.apply_found_city(_parity_scenario(), _found_action())
    assert sc2.unit_by_id(2) is None  # consumed the transition's founder
    assert sc2.unit_by_id(1) is not None  # not the action's unit_id
    legacy_city = sc2.city_by_id(77)
    assert legacy_city is not None
    assert str(legacy_city.city_name) == "One Core"
    assert legacy_city.is_capital is False and legacy_city.building_ids == ()
    assert sc2.peek_next_city_id() == 99

    snap2 = world_actions.apply_found_city(_parity_snapshot(), _found_action())
    assert all(int(u["id"]) != 2 for u in snap2["units"])
    assert any(int(u["id"]) == 1 for u in snap2["units"])
    world_city = next(c for c in snap2["cities"] if int(c["id"]) == 77)
    assert world_city["name"] == "One Core"
    assert world_city["current_project"] is None
    assert int(snap2["next_city_id"]) == 99


def test_both_state_adapters_route_production_through_one_rule(monkeypatch) -> None:
    monkeypatch.setattr(
        cpr,
        "validate_set_city_production",
        lambda **_: {"ok": False, "reason": "one_core"},
    )
    assert legacy_scp.validate(
        _parity_scenario(with_city_at_origin=True), _default_progress(), _scp_action()
    ) == {"ok": False, "reason": "one_core"}
    assert world_actions.validate_set_city_production(
        _parity_snapshot(with_city_at_origin=True), _scp_action()
    ) == {"ok": False, "reason": "one_core"}


def test_scenario_tick_and_delivery_route_through_one_loop(monkeypatch) -> None:
    """The deprecated Scenario tick/delivery adapter materializes the ONE
    canonical loop's outputs — patching the loop changes the Scenario
    results, so no private tick or delivery algorithm remains."""
    from app.domain import production_rules as legacy_production

    sc = legacy_scp.apply_set_city_production(
        _parity_scenario(with_city_at_origin=True), _scp_action()
    )
    sentinel_project = {"project_id": "produce_unit:warrior", "progress": 9, "cost": 9}
    monkeypatch.setattr(
        cpr,
        "tick_production",
        lambda cities, owner, yields: ({1: dict(sentinel_project)}, [{"marker": 1}]),
    )
    sc_ticked, events = legacy_production.apply_production_tick_for_player(sc, 0)
    assert sc_ticked.city_by_id(1).current_project == sentinel_project
    assert events == [{"marker": 1}]

    monkeypatch.setattr(
        cpr,
        "deliver_completed_production",
        lambda cities, owner, nuid: (
            [
                {
                    "city_id": 1,
                    "unit_id": nuid,
                    "unit_type_id": "warrior",
                    "position": (0, 0),
                }
            ],
            [{"marker": 2}],
            nuid + 1,
        ),
    )
    sc_delivered, events = legacy_production.deliver_pending_for_player(sc_ticked, 0)
    assert events == [{"marker": 2}]
    spawned = sc_delivered.unit_by_id(sc_ticked.peek_next_unit_id())
    assert spawned is not None and str(spawned.type_id) == "warrior"
    assert sc_delivered.city_by_id(1).current_project is None


def test_world_legal_actions_derive_from_the_same_canonical_rules(monkeypatch) -> None:
    """World legal-action generation and POST validation share the canonical
    validators: canonically rejecting everything empties the served rows."""

    class _NoTileMap:
        def has_tile_coord(self, _c):
            return False

    snap = _parity_snapshot(with_city_at_origin=True)
    payload = world_legal_actions.compute_world_legal_actions_payload(
        snap, _NoTileMap(), 0, None, 1
    )
    # Active project None: "none" is excluded by project_already_set, both
    # registry projects are offered (sorted) — and every served row passes
    # the POST validator it was derived from.
    assert [a["project_id"] for a in payload["actions"]] == [
        "produce_unit:settler",
        "produce_unit:warrior",
    ]
    for row in payload["actions"]:
        assert world_actions.validate_set_city_production(snap, row)["ok"]

    monkeypatch.setattr(
        cpr,
        "validate_set_city_production",
        lambda **_: {"ok": False, "reason": "one_core"},
    )
    payload = world_legal_actions.compute_world_legal_actions_payload(
        snap, _NoTileMap(), 0, None, 1
    )
    assert payload["actions"] == []

    snap_units = _parity_snapshot()
    payload = world_legal_actions.compute_world_legal_actions_payload(
        snap_units, _NoTileMap(), 0, 1, None
    )
    assert [a["action_type"] for a in payload["actions"]] == ["found_city"]
    for row in payload["actions"]:
        assert world_actions.validate_found_city(snap_units, row)["ok"]
    monkeypatch.setattr(
        cfr, "validate_found_city", lambda **_: {"ok": False, "reason": "one_core"}
    )
    payload = world_legal_actions.compute_world_legal_actions_payload(
        snap_units, _NoTileMap(), 0, 1, None
    )
    assert payload["actions"] == []


def test_legacy_water_and_territory_facts_stay_map_adapter_answers() -> None:
    """The legacy-only map facts flow through the same canonical chain as
    explicit adapter answers (the WorldMap path's schema has no such layers,
    so its defaults never fire)."""
    m = HexMap({(0, 0): Terrain.WATER})
    u = Unit.make(1, 0, HexCoord(0, 0), "settler", 2, 100)
    sc = Scenario(m, (u,), (), 4, 1, None)
    vr = legacy_found_city.validate(sc, _found_action())
    assert vr == {"ok": False, "reason": "tile_is_water"}


# --------------------------------------------------------- dependency walls

_DOMAIN_DIR = Path(__file__).resolve().parents[1] / "app" / "domain"

# Deprecated snapshot-v2 gameplay orchestration and state types: the active
# WorldMap path must never import these (frozen legacy, N9 removal).
_DEPRECATED_GAMEPLAY_MODULES = (
    "app.domain.scenario",
    "app.domain.hex_map",
    "app.domain.legal_actions",
    "app.domain.movement_rules",
    "app.domain.production_rules",
    "app.domain.city_yields",
    "app.domain.food_growth_rules",
    "app.domain.science_tick_rules",
    "app.domain.progress_state",
    "app.domain.progress_unlock_resolver",
    "app.domain.snapshot",
    "app.domain.prototype_maps",
    "app.domain.match_state",
    "app.domain.actions",
)

# Canonical pure rules: map-, transport-, and persistence-free. Only shared
# registries (app.domain.content.*) and the stdlib are allowed.
_PURE_RULE_FORBIDDEN = _DEPRECATED_GAMEPLAY_MODULES + (
    "app.domain.world_map",
    "app.domain.world_match",
    "app.domain.world_scenario",
    "app.storage",
    "app.api",
    "fastapi",
)


def _imports_of(module_path: Path) -> set[str]:
    tree = ast.parse(module_path.read_text(encoding="utf-8"))
    found: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            found.update(alias.name for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            found.add(node.module)
            found.update(f"{node.module}.{alias.name}" for alias in node.names)
    return found


@pytest.mark.parametrize(
    "module_filename", ["city_founding_rules.py", "city_production_rules.py"]
)
def test_canonical_rule_modules_are_pure(module_filename) -> None:
    imports = _imports_of(_DOMAIN_DIR / module_filename)
    for imp in imports:
        for forbidden in _PURE_RULE_FORBIDDEN:
            assert not imp.startswith(forbidden), (
                f"{module_filename} imports {imp}: canonical gameplay rules "
                "must stay map-, transport-, and persistence-free"
            )


@pytest.mark.parametrize(
    "module_filename",
    [
        "world_actions.py",
        "world_legal_actions.py",
        "world_match.py",
        "world_scenario.py",
    ],
)
def test_world_modules_never_import_deprecated_gameplay(module_filename) -> None:
    imports = _imports_of(_DOMAIN_DIR / module_filename)
    for imp in imports:
        for forbidden in _DEPRECATED_GAMEPLAY_MODULES:
            assert not imp.startswith(forbidden), (
                f"{module_filename} imports {imp}: the active WorldMap path "
                "must not depend on deprecated snapshot-v2 gameplay"
            )


@pytest.mark.parametrize(
    "module_path",
    [
        "actions/found_city.py",
        "actions/set_city_production.py",
        "production_rules.py",
    ],
)
def test_deprecated_adapters_import_the_canonical_rules(module_path) -> None:
    """The Scenario modules are fact adapters over the canonical core — they
    must import it (behavioral proof lives in the parity and patch tests)."""
    imports = _imports_of(_DOMAIN_DIR / module_path)
    assert any(
        imp.startswith("app.domain.city_founding_rules")
        or imp.startswith("app.domain.city_production_rules")
        for imp in imports
    ), f"{module_path} no longer delegates to the canonical rules"


def test_no_world_production_rules_duplicate_module_remains() -> None:
    """The N8b duplicate rules module was folded into the canonical core."""
    assert not (_DOMAIN_DIR / "world_production_rules.py").exists()
