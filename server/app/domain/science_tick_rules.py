"""Per-turn science accumulation. Parity: science_tick.gd apply_for_player only."""

from __future__ import annotations

from typing import Any

from app.domain.city_yields import science_for_player
from app.domain.content import progress_definitions as pd
from app.domain.progress_state import ProgressState
from app.domain.progress_unlock_resolver import complete_progress
from app.domain.scenario import Scenario
from app.domain import science_availability

SCHEMA_VERSION = 1


def _resolve_tick_target(ps: ProgressState, owner_id: int) -> str:
    cur = ps.current_research_for(owner_id)
    if cur != "" and science_availability.is_available(ps, owner_id, cur):
        return cur
    avail = science_availability.available_for(ps, owner_id)
    if not avail:
        return ""
    return str(avail[0])


def _add_progress_and_maybe_complete(
    ps: ProgressState,
    owner_id: int,
    delta: int,
    target_progress_id: str,
) -> tuple[ProgressState, list[dict[str, Any]]]:
    if delta == 0:
        return ps, []
    if ps.has_completed_progress(owner_id, target_progress_id):
        return ps, []
    target_cost = pd.cost(target_progress_id)
    cur = ps.science_progress_for(owner_id, target_progress_id)
    new_total = cur + delta
    next_ps = ps.with_science_progress_added(owner_id, target_progress_id, delta)
    evp: dict[str, Any] = {
        "schema_version": SCHEMA_VERSION,
        "action_type": "science_progress",
        "source": "engine",
        "result": "accepted",
        "actor_id": owner_id,
        "progress_id": target_progress_id,
        "delta": delta,
        "total": new_total,
        "cost": target_cost,
    }
    events: list[dict[str, Any]] = [evp]
    if new_total < target_cost:
        return next_ps, events
    res = complete_progress(next_ps, owner_id, target_progress_id)
    if not bool(res["ok"]):
        return next_ps, events
    final_ps = res["progress_state"]
    unlocked_raw = res["unlocked_targets"]
    unlocked = [dict(row) for row in unlocked_raw]
    evc: dict[str, Any] = {
        "schema_version": SCHEMA_VERSION,
        "action_type": "science_completed",
        "source": "engine",
        "result": "accepted",
        "actor_id": owner_id,
        "progress_id": target_progress_id,
        "unlocked_targets": unlocked,
        "total": new_total,
        "cost": target_cost,
    }
    events.append(evc)
    return final_ps, events


def apply_science_tick_for_player(
    progress_state: ProgressState | None,
    scenario: Scenario | None,
    owner_id: int,
) -> tuple[ProgressState | None, list[dict[str, Any]]]:
    if progress_state is None or scenario is None:
        return progress_state, []
    target_id = _resolve_tick_target(progress_state, owner_id)
    if target_id == "":
        no_ev: dict[str, Any] = {
            "schema_version": SCHEMA_VERSION,
            "action_type": "science_no_target",
            "source": "engine",
            "result": "accepted",
            "actor_id": owner_id,
        }
        return progress_state, [no_ev]
    delta = science_for_player(scenario, owner_id)
    if delta == 0:
        return progress_state, []
    return _add_progress_and_maybe_complete(progress_state, owner_id, delta, target_id)
