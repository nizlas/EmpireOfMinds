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
    def from_snapshot_dict(d: dict[str, Any]) -> ProgressState:
        """Rebuild ProgressState from snapshot v2 `progress_state` object."""
        built: dict[int, dict[str, Any]] = {}
        for row in d.get("by_owner", []):
            oid = int(row["owner_id"])
            ut_raw = list(row.get("unlocked_targets", []))
            built[oid] = {
                "unlocked_targets": _normalize_unlocked_targets(ut_raw),
                "completed_progress_ids": _normalize_completed_progress_ids(
                    row.get("completed_progress_ids", [])
                ),
                "science_progress": _science_progress_from_raw(
                    row.get("science_progress") or {}
                ),
                "science_observation_flags": {
                    str(k): bool(v)
                    for k, v in (row.get("science_observation_flags") or {}).items()
                },
                "current_research_id": str(row.get("current_research_id", "")),
            }
        return ProgressState(_by_owner=built)

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

    def owner_ids(self) -> list[int]:
        return sorted(self._by_owner.keys())

    def completed_progress_ids_for(self, owner_id: int) -> list[str]:
        if owner_id not in self._by_owner:
            return []
        return list(self._by_owner[owner_id]["completed_progress_ids"])

    def has_completed_progress(self, owner_id: int, progress_id: str) -> bool:
        for pid in self.completed_progress_ids_for(owner_id):
            if str(pid) == str(progress_id):
                return True
        return False

    def science_progress_for(self, owner_id: int, progress_id: str) -> int:
        if owner_id not in self._by_owner:
            return 0
        sp = self._by_owner[owner_id].get("science_progress", {})
        if not isinstance(sp, dict):
            return 0
        return int(sp.get(progress_id, 0))

    def has_observation_bonus_granted(self, owner_id: int, progress_id: str) -> bool:
        if owner_id not in self._by_owner:
            return False
        fl = self._by_owner[owner_id].get("science_observation_flags", {})
        if not isinstance(fl, dict):
            return False
        return bool(fl.get(progress_id, False))

    def _inner_copy(self, owner_id: int) -> dict[str, Any]:
        inner0 = self._by_owner[owner_id]
        return {
            "unlocked_targets": copy.deepcopy(list(inner0["unlocked_targets"])),
            "completed_progress_ids": list(inner0["completed_progress_ids"]),
            "science_progress": _science_progress_from_raw(inner0.get("science_progress") or {}),
            "science_observation_flags": dict(inner0.get("science_observation_flags") or {}),
            "current_research_id": str(inner0.get("current_research_id", "")),
        }

    def with_current_research(self, owner_id: int, science_id: str) -> ProgressState:
        built: dict[int, dict[str, Any]] = {}
        found = False
        for oid in self.owner_ids():
            inner0 = self._by_owner[oid]
            if oid == owner_id:
                found = True
                built[oid] = {
                    "unlocked_targets": _normalize_unlocked_targets(inner0["unlocked_targets"]),
                    "completed_progress_ids": _normalize_completed_progress_ids(
                        inner0["completed_progress_ids"]
                    ),
                    "science_progress": _science_progress_from_raw(inner0.get("science_progress") or {}),
                    "science_observation_flags": _observation_flags_from_raw(
                        inner0.get("science_observation_flags") or {}
                    ),
                    "current_research_id": str(science_id),
                }
            else:
                built[oid] = {
                    "unlocked_targets": _normalize_unlocked_targets(inner0["unlocked_targets"]),
                    "completed_progress_ids": _normalize_completed_progress_ids(
                        inner0["completed_progress_ids"]
                    ),
                    "science_progress": _science_progress_from_raw(inner0.get("science_progress") or {}),
                    "science_observation_flags": _observation_flags_from_raw(
                        inner0.get("science_observation_flags") or {}
                    ),
                    "current_research_id": str(inner0.get("current_research_id", "")),
                }
        if not found:
            built[owner_id] = {
                "unlocked_targets": [],
                "completed_progress_ids": [],
                "science_progress": {},
                "science_observation_flags": {},
                "current_research_id": str(science_id),
            }
        return ProgressState(_by_owner=built)

    def with_science_progress_added(self, owner_id: int, progress_id: str, delta: int) -> ProgressState:
        built: dict[int, dict[str, Any]] = {}
        found = False
        for oid in self.owner_ids():
            inner0 = self._by_owner[oid]
            if oid == owner_id:
                found = True
                row = self._inner_copy(oid)
                sp = dict(row["science_progress"])
                sp[str(progress_id)] = int(sp.get(progress_id, 0)) + int(delta)
                built[oid] = {
                    "unlocked_targets": _normalize_unlocked_targets(inner0["unlocked_targets"]),
                    "completed_progress_ids": _normalize_completed_progress_ids(row["completed_progress_ids"]),
                    "science_progress": _science_progress_from_raw(sp),
                    "science_observation_flags": _observation_flags_from_raw(row["science_observation_flags"]),
                    "current_research_id": row["current_research_id"],
                }
            else:
                built[oid] = {
                    "unlocked_targets": _normalize_unlocked_targets(inner0["unlocked_targets"]),
                    "completed_progress_ids": _normalize_completed_progress_ids(
                        inner0["completed_progress_ids"]
                    ),
                    "science_progress": _science_progress_from_raw(inner0.get("science_progress") or {}),
                    "science_observation_flags": _observation_flags_from_raw(
                        inner0.get("science_observation_flags") or {}
                    ),
                    "current_research_id": str(inner0.get("current_research_id", "")),
                }
        if not found:
            sp_new = {str(progress_id): int(delta)}
            built[owner_id] = {
                "unlocked_targets": [],
                "completed_progress_ids": [],
                "science_progress": _science_progress_from_raw(sp_new),
                "science_observation_flags": {},
                "current_research_id": "",
            }
        return ProgressState(_by_owner=built)

    def with_observation_bonus_granted(self, owner_id: int, progress_id: str) -> ProgressState:
        built: dict[int, dict[str, Any]] = {}
        found = False
        for oid in self.owner_ids():
            inner0 = self._by_owner[oid]
            if oid == owner_id:
                found = True
                row = self._inner_copy(oid)
                obs = dict(row["science_observation_flags"])
                obs[str(progress_id)] = True
                built[oid] = {
                    "unlocked_targets": _normalize_unlocked_targets(inner0["unlocked_targets"]),
                    "completed_progress_ids": _normalize_completed_progress_ids(row["completed_progress_ids"]),
                    "science_progress": _science_progress_from_raw(row["science_progress"]),
                    "science_observation_flags": _observation_flags_from_raw(obs),
                    "current_research_id": row["current_research_id"],
                }
            else:
                built[oid] = {
                    "unlocked_targets": _normalize_unlocked_targets(inner0["unlocked_targets"]),
                    "completed_progress_ids": _normalize_completed_progress_ids(
                        inner0["completed_progress_ids"]
                    ),
                    "science_progress": _science_progress_from_raw(inner0.get("science_progress") or {}),
                    "science_observation_flags": _observation_flags_from_raw(
                        inner0.get("science_observation_flags") or {}
                    ),
                    "current_research_id": str(inner0.get("current_research_id", "")),
                }
        if not found:
            built[owner_id] = {
                "unlocked_targets": [],
                "completed_progress_ids": [],
                "science_progress": {},
                "science_observation_flags": _observation_flags_from_raw({progress_id: True}),
                "current_research_id": "",
            }
        return ProgressState(_by_owner=built)

    def with_progress_id_completed(self, owner_id: int, progress_id: str) -> ProgressState:
        built: dict[int, dict[str, Any]] = {}
        found = False
        for oid in self.owner_ids():
            inner0 = self._by_owner[oid]
            if oid == owner_id:
                found = True
                cp = list(inner0["completed_progress_ids"])
                if progress_id not in cp:
                    cp.append(str(progress_id))
                built[oid] = {
                    "unlocked_targets": _normalize_unlocked_targets(inner0["unlocked_targets"]),
                    "completed_progress_ids": _normalize_completed_progress_ids(cp),
                    "science_progress": _science_progress_from_raw(inner0.get("science_progress") or {}),
                    "science_observation_flags": _observation_flags_from_raw(
                        inner0.get("science_observation_flags") or {}
                    ),
                    "current_research_id": str(inner0.get("current_research_id", "")),
                }
            else:
                built[oid] = {
                    "unlocked_targets": _normalize_unlocked_targets(inner0["unlocked_targets"]),
                    "completed_progress_ids": _normalize_completed_progress_ids(
                        inner0["completed_progress_ids"]
                    ),
                    "science_progress": _science_progress_from_raw(inner0.get("science_progress") or {}),
                    "science_observation_flags": _observation_flags_from_raw(
                        inner0.get("science_observation_flags") or {}
                    ),
                    "current_research_id": str(inner0.get("current_research_id", "")),
                }
        if not found:
            built[owner_id] = {
                "unlocked_targets": [],
                "completed_progress_ids": _normalize_completed_progress_ids([progress_id]),
                "science_progress": {},
                "science_observation_flags": {},
                "current_research_id": "",
            }
        return ProgressState(_by_owner=built)

    def with_target_unlocked(self, owner_id: int, target_type: str, target_id: str) -> ProgressState:
        built: dict[int, dict[str, Any]] = {}
        found = False
        for oid in self.owner_ids():
            inner0 = self._by_owner[oid]
            if oid == owner_id:
                found = True
                raw = copy.deepcopy(list(inner0["unlocked_targets"]))
                raw.append({"target_type": str(target_type), "target_id": str(target_id)})
                built[oid] = {
                    "unlocked_targets": _normalize_unlocked_targets(raw),
                    "completed_progress_ids": _normalize_completed_progress_ids(
                        inner0["completed_progress_ids"]
                    ),
                    "science_progress": _science_progress_from_raw(inner0.get("science_progress") or {}),
                    "science_observation_flags": _observation_flags_from_raw(
                        inner0.get("science_observation_flags") or {}
                    ),
                    "current_research_id": str(inner0.get("current_research_id", "")),
                }
            else:
                built[oid] = {
                    "unlocked_targets": _normalize_unlocked_targets(inner0["unlocked_targets"]),
                    "completed_progress_ids": _normalize_completed_progress_ids(
                        inner0["completed_progress_ids"]
                    ),
                    "science_progress": _science_progress_from_raw(inner0.get("science_progress") or {}),
                    "science_observation_flags": _observation_flags_from_raw(
                        inner0.get("science_observation_flags") or {}
                    ),
                    "current_research_id": str(inner0.get("current_research_id", "")),
                }
        if not found:
            built[owner_id] = {
                "unlocked_targets": _normalize_unlocked_targets(
                    [{"target_type": str(target_type), "target_id": str(target_id)}]
                ),
                "completed_progress_ids": [],
                "science_progress": {},
                "science_observation_flags": {},
                "current_research_id": "",
            }
        return ProgressState(_by_owner=built)
