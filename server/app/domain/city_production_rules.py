"""Canonical city-production rules (N8R) — the ONE gameplay implementation.

Map-neutral pure module: the production-selection decision sequence, the
canonical project-state semantics, the production tick/completion decisions,
delivery eligibility (project clearing, unit-id allocation, engine-event
construction), the event progress representation, and the flat production
yield constant are independent of presentation, transport, snapshot format,
and map rendering. This module never imports Scenario, HexMap, WorldMap,
snapshot, storage, or API code — callers pass plain facts and materialize the
returned project/spawn semantics into their own storage. The only allowed
dependency is the shared canonical city-project registry.

There is exactly ONE selection validator and ONE tick/delivery loop.
State-specific callers are fact adapters, never separate algorithms:

- the active WorldMap path (world_actions.py) passes no unlock policy —
  every registry project is always selectable (locked N8b) — and N8c ticks
  with FLAT_PRODUCTION_PER_CITY plus a spawn-position resolver that may
  defer a ready city (no id allocation / clear / unit_produced) until a
  legal unit-unoccupied tile exists;
- the deprecated Scenario/HexMap adapter (actions/set_city_production.py,
  production_rules.py) passes its progress-unlock policy and its worked-tile
  yields as explicit inputs around the same rules.

Locked selection decision chain and literal rejection reasons (after the
caller's wire/envelope checks): not_current_player -> unknown_city ->
city_not_owned_by_player -> unknown_city_project -> city_project_not_unlocked
(only when the caller supplies an unlock policy) -> project_already_set.
Selecting the already-active project or clearing an already-empty project
rejects project_already_set with no mutation.

Canonical project state: {"project_id", "progress" (starts 0 on set/switch),
"cost" (registry)} — or None when production is cleared ("none").
Completion is DERIVED (progress >= cost for a produce_unit project), never a
separate stored truth; the legacy snapshot-v2 "ready" flag is that predicate
materialized by the Scenario adapter, and tick keeps a stored "ready" key
synchronized when the caller's project mapping carries one.

Production processing (extracted from the proven legacy loop): on the
owner's accepted end_turn each eligible city (owner's, project set, not yet
complete, positive yield) accrues its caller-supplied yield in ascending
city-id order, emitting one production_progress engine event per city. When
that owner next becomes current, every complete produce_unit project
delivers: one unit of the registry-produced type spawns at the caller-
supplied spawn position (city center), unit ids are allocated sequentially
from the caller's next_unit_id, the project clears, and one unit_produced
engine event is emitted per city — again in ascending city-id order. Event
stamping (index/revision/accepted_at) stays in the caller's authority layer.

Flat yields v2 (locked 2026-08-06, docs/PHASE_PLAN.md N8b): production is a
constant FLAT_PRODUCTION_PER_CITY per city on each accepted owner end_turn
on the WorldMap path (explicitly a balance placeholder, not final balance).
The deprecated Scenario path's worked-tile yield math (city_yields.py) is a
different, frozen yield POLICY feeding the same tick loop — never a second
loop.
"""

from __future__ import annotations

import copy
from dataclasses import dataclass
from typing import Any, Callable, Mapping, Sequence

from app.domain.content import city_project_definitions as cpd

PROJECT_TYPE_PRODUCE_UNIT = "produce_unit"
ENGINE_EVENT_SCHEMA_VERSION = 1

# Flat production yield applied per city on each accepted owner end_turn (N8c).
FLAT_PRODUCTION_PER_CITY: int = 1


@dataclass(frozen=True)
class CityProductionFacts:
    """Minimal facts about the selection-target city, independent of state shape."""

    owner_id: int
    active_project_id: str | None


@dataclass(frozen=True)
class ProducingCityFacts:
    """Minimal facts about a city for tick/delivery, independent of state shape."""

    city_id: int
    owner_id: int
    position: tuple[int, int]
    current_project: Mapping[str, Any] | None


def active_project_id(current_project: Any) -> str | None:
    """The active project_id of a canonical project-state mapping, else None."""
    if current_project is None or not isinstance(current_project, Mapping):
        return None
    pid = current_project.get("project_id", None)
    if pid is None:
        return None
    return str(pid)


def project_type_of(current_project: Any) -> str:
    """Canonical project type: the stored project_type (snapshot v2 keeps
    one) or the registry's type for the project_id; "" when unresolvable."""
    if current_project is None or not isinstance(current_project, Mapping):
        return ""
    stored = current_project.get("project_type", None)
    if stored is not None:
        return str(stored)
    pid = active_project_id(current_project)
    if pid is not None and cpd.has(pid):
        defn = cpd.get_definition(pid)
        assert defn is not None
        return str(defn["project_type"])
    return ""


def project_is_complete(current_project: Any) -> bool:
    """Derived completion: a produce_unit project whose progress reached cost."""
    if current_project is None or not isinstance(current_project, Mapping):
        return False
    if project_type_of(current_project) != PROJECT_TYPE_PRODUCE_UNIT:
        return False
    return int(current_project.get("progress", 0)) >= int(current_project["cost"])


def _ok() -> dict[str, Any]:
    return {"ok": True, "reason": ""}


def _fail(reason: str) -> dict[str, Any]:
    return {"ok": False, "reason": reason}


def validate_set_city_production(
    *,
    actor_id: int,
    current_player_id: int,
    city: CityProductionFacts | None,
    project_id: str,
    is_project_unlocked: Callable[[str], bool] | None = None,
) -> dict[str, Any]:
    """The canonical selection decision in the locked first-failure order.

    ``city`` is None when the city id does not resolve. ``is_project_unlocked``
    is an explicit policy input: None means the caller's path has no unlock
    gating (the WorldMap path — every registry project always selectable);
    the deprecated Scenario adapter passes its progress-state policy here.
    """
    if actor_id != current_player_id:
        return _fail("not_current_player")
    if city is None:
        return _fail("unknown_city")
    if city.owner_id != actor_id:
        return _fail("city_not_owned_by_player")
    if project_id != cpd.PROJECT_ID_NONE and not cpd.has(project_id):
        return _fail("unknown_city_project")
    if (
        project_id != cpd.PROJECT_ID_NONE
        and is_project_unlocked is not None
        and not is_project_unlocked(project_id)
    ):
        return _fail("city_project_not_unlocked")
    if project_id != cpd.PROJECT_ID_NONE and city.active_project_id == project_id:
        return _fail("project_already_set")
    if project_id == cpd.PROJECT_ID_NONE and city.active_project_id is None:
        return _fail("project_already_set")
    return _ok()


def new_project_state(project_id: str) -> dict[str, Any] | None:
    """Canonical project state after an accepted selection.

    Only call after validate_set_city_production returned ok. "none" clears
    (None); a registry project starts at progress 0 with its registry cost.
    Adapters may append storage-specific bookkeeping keys (snapshot v2 keeps
    project_type and a materialized ready flag) but never change these.
    """
    if project_id == cpd.PROJECT_ID_NONE:
        return None
    defn = cpd.get_definition(project_id)
    assert defn is not None
    return {
        "project_id": project_id,
        "progress": 0,
        "cost": int(defn["cost"]),
    }


def project_progress_for_event(current_project: Any) -> int | None:
    """Event project_progress representation: 0+ when set, null when cleared."""
    if current_project is None or not isinstance(current_project, Mapping):
        return None
    if "progress" not in current_project:
        return None
    return int(current_project["progress"])


# ------------------------------------------------------------------ tick


def _eligible_for_tick(city: ProducingCityFacts, owner_id: int) -> bool:
    if city.owner_id != owner_id:
        return False
    if city.current_project is None or not isinstance(city.current_project, Mapping):
        return False
    if project_is_complete(city.current_project):
        return False
    return True


def tick_production(
    cities: Sequence[ProducingCityFacts],
    owner_id: int,
    production_yield_by_city_id: Mapping[int, int],
) -> tuple[dict[int, dict[str, Any]], list[dict[str, Any]]]:
    """The canonical production tick (extracted from the proven legacy loop).

    Accrues the caller-supplied yield for each of the ending owner's eligible
    cities in ascending city-id order. Returns the updated project mapping
    per ticked city id plus the unstamped production_progress engine events.
    The updated mapping preserves the caller's stored keys (a snapshot-v2
    "ready" key is kept synchronized with the derived completion predicate);
    materializing it into City/snapshot rows is the adapter's concern.
    """
    by_id = {c.city_id: c for c in cities}
    ids_to_tick = sorted(
        c.city_id
        for c in cities
        if _eligible_for_tick(c, owner_id)
        and int(production_yield_by_city_id.get(c.city_id, 0)) > 0
    )
    if not ids_to_tick:
        return {}, []

    events: list[dict[str, Any]] = []
    new_project_by_id: dict[int, dict[str, Any]] = {}

    for cid in ids_to_tick:
        proj_src = by_id[cid].current_project
        assert isinstance(proj_src, Mapping)
        project: dict[str, Any] = copy.deepcopy(dict(proj_src))
        old_progress = int(project["progress"])
        new_progress = old_progress + int(production_yield_by_city_id[cid])
        project["progress"] = new_progress
        if "ready" in project:
            project["ready"] = project_is_complete(project)
        new_project_by_id[cid] = project

        ev_prog: dict[str, Any] = {
            "schema_version": ENGINE_EVENT_SCHEMA_VERSION,
            "action_type": "production_progress",
            "actor_id": owner_id,
            "city_id": cid,
            "project_type": project_type_of(proj_src),
            "progress_before": old_progress,
            "progress_after": new_progress,
            "cost": int(project["cost"]),
            "source": "engine",
            "result": "accepted",
        }
        if "project_id" in proj_src:
            ev_prog["project_id"] = str(proj_src["project_id"])
        events.append(ev_prog)

    return new_project_by_id, events


# -------------------------------------------------------------- delivery


def deliver_completed_production(
    cities: Sequence[ProducingCityFacts],
    owner_id: int,
    next_unit_id: int,
    *,
    occupied_positions: set[tuple[int, int]] | None = None,
    resolve_spawn_position: Callable[
        [ProducingCityFacts, set[tuple[int, int]]], tuple[int, int] | None
    ]
    | None = None,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], int]:
    """The canonical delivery decision (extracted from the proven legacy loop).

    For every complete produce_unit project owned by the player who just
    became current, in ascending city-id order: resolve a spawn tile, then
    allocate the next sequential unit id, emit one unit_produced engine
    event, and clear that city's project. Returns (spawn effects, unstamped
    events, new next_unit_id); each spawn effect is
    {"city_id", "owner_id", "unit_id", "unit_type_id", "position"} and
    implies clearing that city's current_project.

    Placement:
    - default (resolve_spawn_position is None): city-center facts position
      (legacy Scenario path — no occupancy gate);
    - when a resolver is supplied (N8c WorldMap): it receives the ready city
      facts plus the running occupied-unit set and returns a tile or None.
      None defers that city — no id allocation, no clear, no event — so the
      completed project/progress retry the next time the owner becomes
      current. Successful spawns are added to the occupied set before the
      next ready city is considered.

    Materializing units/cities and stamping events are adapter/authority
    concerns. This is still ONE loop — never copied into an adapter.
    """
    by_id = {c.city_id: c for c in cities}
    ready_ids = sorted(
        c.city_id
        for c in cities
        if c.owner_id == owner_id and project_is_complete(c.current_project)
    )
    if not ready_ids:
        return [], [], next_unit_id

    occupied: set[tuple[int, int]] = set(occupied_positions or ())
    spawns: list[dict[str, Any]] = []
    events: list[dict[str, Any]] = []
    running_next_unit_id = int(next_unit_id)

    for rcid in ready_ids:
        cty = by_id[rcid]
        if resolve_spawn_position is None:
            pos: tuple[int, int] | None = (
                int(cty.position[0]),
                int(cty.position[1]),
            )
        else:
            pos = resolve_spawn_position(cty, occupied)
        if pos is None:
            continue
        unit_id = running_next_unit_id
        running_next_unit_id += 1
        proj_id = ""
        produced_type = "warrior"
        if isinstance(cty.current_project, Mapping):
            proj_id = str(cty.current_project.get("project_id", ""))
        if proj_id and cpd.has(proj_id):
            t = cpd.produces_unit_type(proj_id)
            if t:
                produced_type = t
        spawn_pos = (int(pos[0]), int(pos[1]))
        occupied.add(spawn_pos)
        spawns.append(
            {
                "city_id": rcid,
                "owner_id": int(cty.owner_id),
                "unit_id": unit_id,
                "unit_type_id": produced_type,
                "position": spawn_pos,
            }
        )
        up_ev: dict[str, Any] = {
            "schema_version": ENGINE_EVENT_SCHEMA_VERSION,
            "action_type": "unit_produced",
            "actor_id": owner_id,
            "city_id": rcid,
            "unit_id": unit_id,
            "position": [spawn_pos[0], spawn_pos[1]],
            "project_type": PROJECT_TYPE_PRODUCE_UNIT,
            "unit_type_id": produced_type,
            "source": "engine",
            "result": "accepted",
        }
        if proj_id:
            up_ev["project_id"] = proj_id
        events.append(up_ev)

    return spawns, events, running_next_unit_id
