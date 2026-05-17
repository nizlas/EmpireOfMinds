"""Domain city. Parity: game/domain/city.gd (snapshot-oriented fields)."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from app.domain.hex_coord import HexCoord

WORKED_TILES_MODE_AUTO = "auto"
WORKED_TILES_MODE_MANUAL = "manual"


@dataclass(frozen=True, slots=True)
class City:
    id: int
    owner_id: int
    position: HexCoord
    current_project: dict[str, Any] | None
    city_name: str = ""
    is_capital: bool = False
    building_ids: tuple[str, ...] = ()
    owned_tiles: tuple[HexCoord, ...] = ()
    population: int = 1
    manual_worked_tiles: tuple[HexCoord, ...] = ()
    food_stored: int = 0
    worked_tiles_mode: str = WORKED_TILES_MODE_AUTO
