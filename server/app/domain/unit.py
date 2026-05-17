"""Domain unit. Parity: game/domain/unit.gd."""

from __future__ import annotations

from dataclasses import dataclass

from app.domain.content import unit_definitions
from app.domain.hex_coord import HexCoord


@dataclass(frozen=True, slots=True)
class Unit:
    id: int
    owner_id: int
    position: HexCoord
    type_id: str
    remaining_movement: int
    current_hp: int

    @staticmethod
    def make(
        unit_id: int,
        owner_id: int,
        position: HexCoord,
        type_id: str = "warrior",
        remaining_movement: int = -1,
        current_hp: int = -1,
    ) -> Unit:
        max_mov = unit_definitions.max_movement_for_type(type_id)
        max_hp = unit_definitions.max_hp_for_type(type_id)
        rm = max_mov if remaining_movement < 0 else max(0, min(remaining_movement, max_mov))
        ch = max_hp if current_hp < 0 else max(0, min(current_hp, max_hp))
        return Unit(
            id=unit_id,
            owner_id=owner_id,
            position=position,
            type_id=type_id,
            remaining_movement=rm,
            current_hp=ch,
        )
