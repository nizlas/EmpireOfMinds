"""Per-player unlock / science skeleton. Parity: ProgressState.with_default_unlocks_for_players."""

from __future__ import annotations

import copy
from dataclasses import dataclass, field
from typing import Any


def _sort_target_rows(targets: list[dict[str, str]]) -> None:
    targets.sort(key=lambda d: (str(d["target_type"]), str(d["target_id"])))


def _normalize_unlocked_targets(raw: list[dict[str, Any]]) -> list[dict[str, str]]:
    out: list[dict[str, str]] = []
    for item in raw:
        d = item
        row = {"target_type": str(d["target_type"]), "target_id": str(d["target_id"])}
        out.append(row)
    _sort_target_rows(out)
    dedup: list[dict[str, str]] = []
    for cur in out:
        if not dedup:
            dedup.append(dict(cur))
            continue
        prev = dedup[-1]
        if prev["target_type"] == cur["target_type"] and prev["target_id"] == cur["target_id"]:
            continue
        dedup.append(dict(cur))
    return dedup


def _normalize_completed_progress_ids(raw: list[Any]) -> list[str]:
    out = sorted(str(x) for x in raw)
    dedup: list[str] = []
    for x in out:
        if not dedup or dedup[-1] != x:
            dedup.append(x)
    return dedup


def _science_progress_from_raw(raw: dict[str, Any]) -> dict[str, int]:
    out: dict[str, int] = {}
    for k in sorted(raw.keys(), key=str):
        v = raw[k]
        out[str(k)] = int(v) if isinstance(v, int) else int(v)
    return out


def _observation_flags_from_raw(raw: dict[str, Any]) -> dict[str, bool]:
    out: dict[str, bool] = {}
    for k in sorted(raw.keys(), key=str):
        if bool(raw[k]):
            out[str(k)] = True
    return out


@dataclass(slots=True)
class ProgressState:
    _by_owner: dict[int, dict[str, Any]] = field(default_factory=dict)

    @staticmethod
    def with_default_unlocks_for_players(player_ids: list[int]) -> ProgressState:
        uniq_sorted = sorted({int(p) for p in player_ids})
        built: dict[int, dict[str, Any]] = {}
        for oid in uniq_sorted:
            raw_targets: list[dict[str, str]] = [
                {"target_type": "city_project", "target_id": "produce_unit:warrior"},
                {"target_type": "city_project", "target_id": "produce_unit:settler"},
            ]
            built[oid] = {
                "unlocked_targets": _normalize_unlocked_targets(raw_targets),
                "completed_progress_ids": [],
                "science_progress": {},
                "science_observation_flags": {},
                "current_research_id": "",
            }
        return ProgressState(_by_owner=built)

    def unlocked_targets_for(self, owner_id: int) -> list[dict[str, str]]:
        if owner_id not in self._by_owner:
            return []
        return copy.deepcopy(list(self._by_owner[owner_id]["unlocked_targets"]))

    def has_unlocked_target(self, owner_id: int, target_type: str, target_id: str) -> bool:
        for row in self.unlocked_targets_for(owner_id):
            if row["target_type"] == target_type and row["target_id"] == target_id:
                return True
        return False

    def current_research_for(self, owner_id: int) -> str:
        if owner_id not in self._by_owner:
            return ""
        return str(self._by_owner[owner_id].get("current_research_id", ""))
