"""Staging faction/civ registry (C14d-1). Metadata only — no gameplay effects."""

from __future__ import annotations

from typing import Any

FACTION_MALMO = "malmo"
FACTION_VASTERVIK = "vastervik"
FACTION_PARIS = "paris"

_FACTIONS: dict[str, str] = {
    FACTION_MALMO: "Malmö",
    FACTION_VASTERVIK: "Västervik",
    FACTION_PARIS: "Paris",
}


def is_known_faction_id(faction_id: str) -> bool:
    return str(faction_id).strip() in _FACTIONS


def display_name_for_faction(faction_id: str) -> str:
    return _FACTIONS[str(faction_id).strip()]


def available_factions_public() -> list[dict[str, str]]:
    return [{"id": fid, "display_name": dn} for fid, dn in _FACTIONS.items()]
