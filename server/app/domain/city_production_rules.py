"""Canonical city-production rules (N8R) — the ONE gameplay implementation.

Map-neutral pure module: production-selection decisions, the canonical
project-state representation, the event progress representation, and the
flat production yield constant are independent of presentation, transport,
snapshot format, and map rendering. This module never imports Scenario,
HexMap, WorldMap, snapshot, storage, or API code — callers pass plain facts
and materialize the returned project state into their own storage. The only
allowed dependency is the shared canonical city-project registry.

Locked N8b decision chain and literal rejection reasons (after the caller's
wire/envelope checks): not_current_player -> unknown_city ->
city_not_owned_by_player -> unknown_city_project -> project_already_set.
No unlock / progress_state gating on the WorldMap path — every registry
project is always selectable. Selecting the already-active project or
clearing an already-empty project rejects project_already_set with no
mutation.

Canonical project state: {"project_id", "progress" (starts 0 on set/switch),
"cost" (registry)} — or None when production is cleared ("none").

Flat yields v2 (locked 2026-08-06, docs/PHASE_PLAN.md N8b): production is a
constant 1 per city on each accepted owner end_turn. Established here so
N8c can tick from canonical rules data without reading tile or elevation
properties (explicitly a balance placeholder, not final balance). N8b does
not accrue progress — processing is N8c. The deprecated Scenario path's
worked-tile yield math (production_rules.py) is a different, frozen design,
not a duplicate of this constant.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Mapping

from app.domain.content import city_project_definitions as cpd

# Flat production yield applied per city on each accepted owner end_turn (N8c).
FLAT_PRODUCTION_PER_CITY: int = 1


@dataclass(frozen=True)
class CityProductionFacts:
    """Minimal facts about the target city, independent of state shape."""

    owner_id: int
    active_project_id: str | None


def active_project_id(current_project: Any) -> str | None:
    """The active project_id of a canonical project-state mapping, else None."""
    if current_project is None or not isinstance(current_project, Mapping):
        return None
    pid = current_project.get("project_id", None)
    if pid is None:
        return None
    return str(pid)


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
) -> dict[str, Any]:
    """Canonical selection decision in the locked N8b first-failure order.

    ``city`` is None when the city id does not resolve.
    """
    if actor_id != current_player_id:
        return _fail("not_current_player")
    if city is None:
        return _fail("unknown_city")
    if city.owner_id != actor_id:
        return _fail("city_not_owned_by_player")
    if project_id != cpd.PROJECT_ID_NONE and not cpd.has(project_id):
        return _fail("unknown_city_project")
    if project_id != cpd.PROJECT_ID_NONE and city.active_project_id == project_id:
        return _fail("project_already_set")
    if project_id == cpd.PROJECT_ID_NONE and city.active_project_id is None:
        return _fail("project_already_set")
    return _ok()


def new_project_state(project_id: str) -> dict[str, Any] | None:
    """Canonical project state after an accepted selection.

    Only call after validate_set_city_production returned ok. "none" clears
    (None); a registry project starts at progress 0 with its registry cost.
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
