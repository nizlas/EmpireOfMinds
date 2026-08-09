"""N8c: authoritative world production tick + deterministic spawn.

Covers accrual/costs/completed-stop, delivery when the owner becomes current
(produced unit absent during the intervening opponent turn), city-tile and
smooth-neighbor placement with per-spawn occupancy updates, deferred
retention/retry, successful-only next_unit_id sequencing, Warrior/Settler
snapshot fields, locked event order with end_turn primary response, content
drift HTTP 500 with no mutation, and a two-seat-token produce→spawn→act round.
"""

from __future__ import annotations

from fastapi.testclient import TestClient

from app.domain import world_actions
from app.domain.city_production_rules import FLAT_PRODUCTION_PER_CITY
from app.domain.content import city_project_definitions as cpd
from app.domain.content import unit_definitions
from app.domain.hex_coord import DIRECTIONS
from app.domain.state_hash import state_hash
from app.domain.world_map import EDGE_SMOOTH
from app.storage import file_store
from test_world_found_city_v3 import _found, _seed_city
from test_world_map_actions_v3 import (
    MISMATCH_DETAIL,
    _make_drifted_content_root,
    _move,
    _post,
    _start_world_match,
)
from test_world_set_city_production_v3 import _found_capital, _set_prod


def _end_turn(actor_id: int, schema: int = 1) -> dict:
    return {
        "schema_version": schema,
        "action_type": "end_turn",
        "actor_id": actor_id,
    }


def _city_project(snap: dict, city_id: int = 1) -> dict | None:
    city = next(c for c in snap["cities"] if int(c["id"]) == city_id)
    return city.get("current_project")


def _unit_ids(snap: dict) -> list[int]:
    return sorted(int(u["id"]) for u in snap["units"])


def _seed_project(
    match_id: str,
    city_id: int,
    project_id: str,
    progress: int,
) -> None:
    snap = file_store.read_snapshot(match_id)
    assert snap is not None
    cost = int(cpd.cost(project_id))
    cities = []
    for row in snap["cities"]:
        if int(row["id"]) == city_id:
            cities.append(
                {
                    **row,
                    "current_project": {
                        "project_id": project_id,
                        "progress": progress,
                        "cost": cost,
                    },
                }
            )
        else:
            cities.append(row)
    snap["cities"] = cities
    file_store.write_snapshot(match_id, snap)


def _set_units(match_id: str, units: list[dict]) -> None:
    snap = file_store.read_snapshot(match_id)
    assert snap is not None
    units = sorted(units, key=lambda u: int(u["id"]))
    snap["units"] = units
    if units:
        snap["next_unit_id"] = max(int(u["id"]) for u in units) + 1
    file_store.write_snapshot(match_id, snap)


def _handoff_to(client: TestClient, match_id: str, tokens: dict[int, str], actor_id: int) -> dict:
    """End turns until actor_id is current; returns last accepted body."""
    body: dict = {}
    while True:
        snap = file_store.read_snapshot(match_id)
        assert snap is not None
        cur = int(snap["turn_state"]["players"][int(snap["turn_state"]["current_index"])])
        if cur == actor_id:
            return body
        r = _post(client, match_id, _end_turn(cur), tokens[cur])
        assert r.status_code == 200, r.text
        assert r.json()["accepted"] is True
        body = r.json()


# ----------------------------------------------------------- shape / constants


def test_create_snapshot_initializes_next_unit_id(client: TestClient) -> None:
    snap = _start_world_match(client)[2]["snapshot"]
    assert snap["next_unit_id"] == 5
    assert max(int(u["id"]) for u in snap["units"]) == 4


def test_flat_yield_constant_unchanged() -> None:
    assert FLAT_PRODUCTION_PER_CITY == 1


# ----------------------------------------------------------- accrual / stop


def test_end_turn_accrues_flat_yield_and_stops_when_complete(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    _found_capital(client, match_id, tokens[0])
    r = _post(client, match_id, _set_prod(0, 1, "produce_unit:warrior"), tokens[0])
    assert r.json()["accepted"] is True
    assert _city_project(r.json()["snapshot"]) == {
        "project_id": "produce_unit:warrior",
        "progress": 0,
        "cost": 2,
    }

    r1 = _post(client, match_id, _end_turn(0), tokens[0])
    assert r1.json()["accepted"] is True
    # After P0 end_turn: tick for P0 then P1 becomes current — project at 1/2.
    assert _city_project(r1.json()["snapshot"])["progress"] == 1

    # P1 end_turn: no tick for P0's city; still 1/2; P0 becomes current (not ready).
    r2 = _post(client, match_id, _end_turn(1), tokens[1])
    assert r2.json()["accepted"] is True
    assert _city_project(r2.json()["snapshot"])["progress"] == 1
    assert 5 not in _unit_ids(r2.json()["snapshot"])

    # P0 end_turn: tick to 2/2 (complete). Delivery waits until P0 becomes current again.
    r3 = _post(client, match_id, _end_turn(0), tokens[0])
    assert r3.json()["accepted"] is True
    proj = _city_project(r3.json()["snapshot"])
    assert proj == {"project_id": "produce_unit:warrior", "progress": 2, "cost": 2}
    assert 5 not in _unit_ids(r3.json()["snapshot"])

    # Completed projects must not accrue further on a later P0 end_turn.
    # First deliver on P1→P0, then set a new project and prove stop-at-cost via
    # a seeded complete project that remains unchanged across an owner end_turn
    # that finds no eligible tick targets.
    r4 = _post(client, match_id, _end_turn(1), tokens[1])
    body = r4.json()
    assert body["accepted"] is True
    assert _city_project(body["snapshot"]) is None
    spawned = next(u for u in body["snapshot"]["units"] if int(u["id"]) == 5)
    assert spawned["type_id"] == "warrior"
    assert spawned["current_hp"] == unit_definitions.max_hp_for_type("warrior")
    assert spawned["has_attacked"] is False
    assert body["snapshot"]["next_unit_id"] == 6

    # Seed a completed project and end P0's turn: progress must stay at cost.
    _seed_project(match_id, 1, "produce_unit:settler", 2)
    r5 = _post(client, match_id, _end_turn(0), tokens[0])
    assert r5.json()["accepted"] is True
    assert _city_project(r5.json()["snapshot"]) == {
        "project_id": "produce_unit:settler",
        "progress": 2,
        "cost": 2,
    }


def test_produced_unit_absent_during_intervening_opponent_turn(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    _found_capital(client, match_id, tokens[0])
    _post(client, match_id, _set_prod(0, 1, "produce_unit:warrior"), tokens[0])
    _post(client, match_id, _end_turn(0), tokens[0])  # 1/2
    _post(client, match_id, _end_turn(1), tokens[1])
    r = _post(client, match_id, _end_turn(0), tokens[0])  # 2/2, P1 current
    snap = r.json()["snapshot"]
    assert _city_project(snap)["progress"] == 2
    assert 5 not in _unit_ids(snap)
    # Opponent cannot see/act with a unit that does not exist yet.
    assert all(int(u["owner_id"]) != 0 or int(u["id"]) in (2,) for u in snap["units"])


# ----------------------------------------------------------- placement


def test_delivery_prefers_unoccupied_city_tile(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    _found_capital(client, match_id, tokens[0])
    _seed_project(match_id, 1, "produce_unit:warrior", 2)
    # City tile (1,1) free (settler consumed); warrior remains at (2,1).
    r = _post(client, match_id, _end_turn(0), tokens[0])  # tick no-op (complete); P1
    r = _post(client, match_id, _end_turn(1), tokens[1])  # deliver for P0
    body = r.json()
    assert body["accepted"] is True
    spawned = next(u for u in body["snapshot"]["units"] if int(u["id"]) == 5)
    assert spawned["position"] == [1, 1]


def test_delivery_falls_back_to_first_smooth_neighbor(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    _found_capital(client, match_id, tokens[0])
    _seed_project(match_id, 1, "produce_unit:settler", 2)
    # Occupy city tile with the remaining warrior moved onto (1,1).
    snap = file_store.read_snapshot(match_id)
    assert snap is not None
    units = []
    for u in snap["units"]:
        if int(u["id"]) == 2:
            units.append({**u, "position": [1, 1]})
        else:
            units.append(u)
    _set_units(match_id, units)

    _post(client, match_id, _end_turn(0), tokens[0])
    body = _post(client, match_id, _end_turn(1), tokens[1]).json()
    spawned = next(u for u in body["snapshot"]["units"] if int(u["id"]) == 5)
    # First DIRECTIONS neighbor of (1,1) is (2,1) — free after warrior moved.
    assert spawned["position"] == [2, 1]
    assert spawned["type_id"] == "settler"
    assert spawned["current_hp"] == unit_definitions.max_hp_for_type("settler")


def test_occupancy_updates_across_multiple_ready_cities(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    _found_capital(client, match_id, tokens[0])
    # Second city for P0 at (2,0) — smooth neighbor of capital, free.
    _seed_city(
        match_id,
        {
            "id": 2,
            "owner_id": 0,
            "position": [2, 0],
            "name": "Settlement 2",
            "current_project": None,
        },
        next_city_id=3,
    )
    _seed_project(match_id, 1, "produce_unit:warrior", 2)
    _seed_project(match_id, 2, "produce_unit:warrior", 2)
    # Occupy both city tiles so each must take a neighbor; first city claims
    # (2,1) (first DIRECTIONS of (1,1) after city occupied — wait city occupied).
    snap = file_store.read_snapshot(match_id)
    assert snap is not None
    units = [
        {"id": 2, "owner_id": 0, "position": [1, 1], "type_id": "warrior", "current_hp": 100, "has_attacked": False},
        {"id": 3, "owner_id": 1, "position": [2, 14], "type_id": "settler", "current_hp": 100, "has_attacked": False},
        {"id": 4, "owner_id": 1, "position": [2, 13], "type_id": "warrior", "current_hp": 100, "has_attacked": False},
        {"id": 10, "owner_id": 0, "position": [2, 0], "type_id": "warrior", "current_hp": 100, "has_attacked": False},
    ]
    _set_units(match_id, units)

    _post(client, match_id, _end_turn(0), tokens[0])
    body = _post(client, match_id, _end_turn(1), tokens[1]).json()
    spawned = [u for u in body["snapshot"]["units"] if int(u["id"]) >= 11]
    assert len(spawned) == 2
    positions = sorted(tuple(u["position"]) for u in spawned)
    # City 1 (id=1) at (1,1) occupied → first free smooth neighbor (2,1).
    # City 2 (id=2) at (2,0) occupied → its first free smooth neighbor in
    # DIRECTIONS order, with (2,1) already taken by the earlier spawn.
    assert (2, 1) in positions
    assert positions[0] != positions[1]
    assert body["snapshot"]["next_unit_id"] == 13


def test_deferred_delivery_retains_project_and_retries(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    _found_capital(client, match_id, tokens[0])
    _seed_project(match_id, 1, "produce_unit:warrior", 2)
    city = (1, 1)
    neighbors = [(city[0] + dq, city[1] + dr) for dq, dr in DIRECTIONS]
    # Occupy city + all six smooth neighbors.
    units = [
        {
            "id": i + 1,
            "owner_id": 0 if i < 4 else 1,
            "position": [p[0], p[1]],
            "type_id": "warrior",
            "current_hp": 100,
            "has_attacked": False,
        }
        for i, p in enumerate([city, *neighbors])
    ]
    _set_units(match_id, units)
    next_before = file_store.read_snapshot(match_id)["next_unit_id"]

    _post(client, match_id, _end_turn(0), tokens[0])
    body = _post(client, match_id, _end_turn(1), tokens[1]).json()
    assert body["accepted"] is True
    assert _city_project(body["snapshot"]) == {
        "project_id": "produce_unit:warrior",
        "progress": 2,
        "cost": 2,
    }
    assert body["snapshot"]["next_unit_id"] == next_before
    assert next_before not in _unit_ids(body["snapshot"])

    # Free the city tile and retry on the next P0-becomes-current.
    snap = file_store.read_snapshot(match_id)
    assert snap is not None
    freed = [u for u in snap["units"] if tuple(u["position"]) != city]
    _set_units(match_id, freed)
    _handoff_to(client, match_id, tokens, 1)
    body = _post(client, match_id, _end_turn(1), tokens[1]).json()
    spawned = next(u for u in body["snapshot"]["units"] if int(u["id"]) == next_before)
    assert spawned["position"] == [1, 1]
    assert _city_project(body["snapshot"]) is None
    assert body["snapshot"]["next_unit_id"] == next_before + 1


# ----------------------------------------------------------- events / drift


def test_event_order_and_primary_response_is_end_turn(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    _found_capital(client, match_id, tokens[0])
    _post(client, match_id, _set_prod(0, 1, "produce_unit:warrior"), tokens[0])
    # First end_turn: one production_progress, then end_turn; no unit_produced.
    before = len(file_store.read_events(match_id))
    r = _post(client, match_id, _end_turn(0), tokens[0])
    body = r.json()
    assert body["accepted"] is True
    assert body["event"]["action_type"] == "end_turn"
    assert body["index"] == body["event"]["index"]
    events = file_store.read_events(match_id)[before:]
    types = [e["action_type"] for e in events]
    assert types == ["production_progress", "end_turn"]
    assert events[0]["progress_before"] == 0 and events[0]["progress_after"] == 1
    assert events[1]["index"] == body["index"]

    # Complete and deliver: progress* → end_turn → unit_produced*.
    _post(client, match_id, _end_turn(1), tokens[1])
    before = len(file_store.read_events(match_id))
    r = _post(client, match_id, _end_turn(0), tokens[0])  # tick to complete
    _post(client, match_id, _end_turn(1), tokens[1])  # deliver
    # Inspect the delivery end_turn (P1's).
    events = file_store.read_events(match_id)
    # Find the last end_turn followed by unit_produced.
    idxs = [i for i, e in enumerate(events) if e["action_type"] == "unit_produced"]
    assert idxs, "expected unit_produced"
    up_i = idxs[-1]
    assert events[up_i - 1]["action_type"] == "end_turn"
    # The tick that completed may be on the previous P0 end_turn.
    assert events[up_i]["unit_id"] == 5
    assert events[up_i]["position"] == [1, 1]


def test_content_drift_end_turn_is_http_500_without_mutation(
    client: TestClient, tmp_path, monkeypatch
) -> None:
    match_id, tokens, _ = _start_world_match(client)
    _found_capital(client, match_id, tokens[0])
    _post(client, match_id, _set_prod(0, 1, "produce_unit:warrior"), tokens[0])
    before = file_store.read_snapshot(match_id)
    assert before is not None
    before_hash = state_hash(before)
    before_events = file_store.read_events(match_id)

    monkeypatch.setenv(
        "EMPIRE_MAP_CONTENT_DIR", str(_make_drifted_content_root(tmp_path))
    )
    r = _post(client, match_id, _end_turn(0), tokens[0])
    assert r.status_code == 500
    assert r.json()["detail"] == MISMATCH_DETAIL
    after = file_store.read_snapshot(match_id)
    assert after is not None
    assert state_hash(after) == before_hash
    assert file_store.read_events(match_id) == before_events


# ----------------------------------------------------------- full round


def test_two_seat_produce_spawn_act_round(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    _found_capital(client, match_id, tokens[0])
    assert _post(
        client, match_id, _set_prod(0, 1, "produce_unit:warrior"), tokens[0]
    ).json()["accepted"]

    # Accrue across the intervening opponent turn, then deliver.
    assert _post(client, match_id, _end_turn(0), tokens[0]).json()["accepted"]
    assert _post(client, match_id, _end_turn(1), tokens[1]).json()["accepted"]
    assert _post(client, match_id, _end_turn(0), tokens[0]).json()["accepted"]
    body = _post(client, match_id, _end_turn(1), tokens[1]).json()
    assert body["accepted"] is True
    spawned = next(u for u in body["snapshot"]["units"] if int(u["id"]) == 5)
    assert spawned["owner_id"] == 0
    assert spawned["position"] == [1, 1]
    assert body["event"]["action_type"] == "end_turn"

    # New unit can act: move from city tile to a free smooth neighbor.
    # Warrior still at (2,1); move spawned unit to (1,0).
    move = _move(0, 5, (1, 1), (1, 0))
    r = _post(client, match_id, move, tokens[0])
    assert r.status_code == 200, r.text
    assert r.json()["accepted"] is True
    moved = next(u for u in r.json()["snapshot"]["units"] if int(u["id"]) == 5)
    assert moved["position"] == [1, 0]


def test_resolve_production_spawn_tile_helper_order() -> None:
    from app.domain.map_content_loader import load_world_map

    wm = load_world_map("handdrawn_test_map_full_01")
    city = (1, 1)
    assert world_actions.resolve_production_spawn_tile(wm, city, set()) == city
    occupied = {city}
    first = world_actions.resolve_production_spawn_tile(wm, city, occupied)
    assert first == (city[0] + DIRECTIONS[0][0], city[1] + DIRECTIONS[0][1])
    assert wm.edge_between(city, first).transition == EDGE_SMOOTH
    # Block everything → None.
    all_occ = {city} | {
        (city[0] + dq, city[1] + dr) for dq, dr in DIRECTIONS
    }
    assert world_actions.resolve_production_spawn_tile(wm, city, all_occ) is None
