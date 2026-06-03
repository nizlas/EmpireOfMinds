"""Staging faction/civ registry (C14d-1). Metadata only — no gameplay effects.

Player-facing term is civilization/civ; API field names remain faction_id (C14d-4e).
Display names align with docs/FACTION_IDENTITY.md non-canonical debug profiles.
"""

from __future__ import annotations

from typing import Any

FACTION_MALMO = "malmo"
FACTION_VASTERVIK = "vastervik"
FACTION_PARIS = "paris"

# Canonical player-facing civilization names (stable ids unchanged).
DISPLAY_MALMO = "Malmöfubikkarna"
DISPLAY_VASTERVIK = "Västerviksjävlarna"
DISPLAY_PARIS = "Pajasarna från Paris"

_FACTIONS: dict[str, str] = {
    FACTION_MALMO: DISPLAY_MALMO,
    FACTION_VASTERVIK: DISPLAY_VASTERVIK,
    FACTION_PARIS: DISPLAY_PARIS,
}


def is_known_faction_id(faction_id: str) -> bool:
    return str(faction_id).strip() in _FACTIONS


def display_name_for_faction(faction_id: str) -> str:
    return _FACTIONS[str(faction_id).strip()]


def available_factions_public() -> list[dict[str, str]]:
    return [{"id": fid, "display_name": dn} for fid, dn in _FACTIONS.items()]
