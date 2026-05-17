"""Append-only accepted action log (future slices). Parity: game/domain/action_log.gd."""

from __future__ import annotations

import copy
from typing import Any


class ActionLog:
    def __init__(self) -> None:
        self._entries: list[dict[str, Any]] = []

    def append(self, entry: dict[str, Any]) -> int:
        idx = len(self._entries)
        ent = copy.deepcopy(entry)
        ent["index"] = idx
        self._entries.append(ent)
        return idx

    def size(self) -> int:
        return len(self._entries)

    def entries(self) -> list[dict[str, Any]]:
        return [copy.deepcopy(e) for e in self._entries]
