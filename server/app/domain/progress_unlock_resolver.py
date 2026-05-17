"""Apply progress completion + unlocks. Parity: progress_unlock_resolver.gd."""

from __future__ import annotations

from typing import Any

from app.domain.content import progress_definitions as pd
from app.domain.progress_state import ProgressState


def complete_progress(
    progress_state: ProgressState | None,
    owner_id: int,
    progress_id: str,
) -> dict[str, Any]:
    if progress_state is None:
        return {
            "ok": False,
            "reason": "progress_state_null",
            "progress_state": progress_state,
            "unlocked_targets": [],
        }
    if not pd.has(progress_id):
        return {
            "ok": False,
            "reason": "unknown_progress_id",
            "progress_state": progress_state,
            "unlocked_targets": [],
        }
    if progress_state.has_completed_progress(owner_id, progress_id):
        return {
            "ok": True,
            "reason": "",
            "progress_state": progress_state,
            "unlocked_targets": [],
        }

    next_state = progress_state.with_progress_id_completed(owner_id, progress_id)
    newly_unlocked: list[dict[str, str]] = []
    source: list[dict[str, Any]] = []
    source.extend(pd.concrete_unlocks(progress_id))
    source.extend(pd.systemic_effects(progress_id))

    for row in source:
        target_type = str(row["target_type"])
        target_id = str(row["target_id"])
        if not next_state.has_unlocked_target(owner_id, target_type, target_id):
            newly_unlocked.append({"target_type": target_type, "target_id": target_id})
        next_state = next_state.with_target_unlocked(owner_id, target_type, target_id)

    return {
        "ok": True,
        "reason": "",
        "progress_state": next_state,
        "unlocked_targets": newly_unlocked,
    }
