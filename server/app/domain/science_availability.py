"""Derived science availability. Parity: science_availability.gd."""

from __future__ import annotations

from app.domain.content import progress_definitions as pd
from app.domain.progress_state import ProgressState


def _prerequisites_satisfied(ps: ProgressState, owner_id: int, science_id: str) -> bool:
    for req in pd.prerequisites(science_id):
        if not ps.has_completed_progress(owner_id, req):
            return False
    return True


def is_available(ps: ProgressState, owner_id: int, science_id: str) -> bool:
    if not pd.is_science(science_id):
        return False
    if ps.has_completed_progress(owner_id, science_id):
        return False
    return _prerequisites_satisfied(ps, owner_id, science_id)


def available_for(ps: ProgressState, owner_id: int) -> list[str]:
    out: list[str] = []
    for sid in pd.ids():
        if is_available(ps, owner_id, sid):
            out.append(sid)
    return sorted(out)


def locked_for(ps: ProgressState, owner_id: int) -> list[str]:
    out: list[str] = []
    for sid in pd.ids():
        if not pd.is_science(sid):
            continue
        if ps.has_completed_progress(owner_id, sid):
            continue
        if not _prerequisites_satisfied(ps, owner_id, sid):
            out.append(sid)
    return sorted(out)
