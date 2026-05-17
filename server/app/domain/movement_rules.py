"""One-step legal movement. Parity: game/domain/movement_rules.gd (subset for Slice C1)."""

from __future__ import annotations

from app.domain.content import terrain_rule_definitions
from app.domain.hex_coord import HexCoord
from app.domain.scenario import Scenario
from app.domain.unit import Unit

MOVEMENT_COST_PER_STEP: int = 1


def legal_move_destinations(scenario: Scenario, unit_id: int) -> list[HexCoord]:
    """Returns passable, empty adjacent hexes if the unit exists and has movement; sorted by (q, r)."""
    u = scenario.unit_by_id(unit_id)
    if u is None:
        return []
    if u.remaining_movement < MOVEMENT_COST_PER_STEP:
        return []
    out: list[HexCoord] = []
    for n in u.position.neighbors():
        if not scenario.map.has(n):
            continue
        t = scenario.map.terrain_at(n)
        if not terrain_rule_definitions.is_passable_hex_map_value(int(t)):
            continue
        if len(scenario.units_at(n)) != 0:
            continue
        out.append(n)
    out.sort(key=lambda c: (c.q, c.r))
    return out


def refresh_movement_for_owner(scenario: Scenario, owner_id: int) -> Scenario:
    """Set remaining_movement to max for all units owned by owner_id; others unchanged."""
    new_units: list[Unit] = []
    for u in scenario.units():
        if u.owner_id != owner_id:
            new_units.append(u)
            continue
        new_units.append(
            Unit.make(
                u.id,
                u.owner_id,
                u.position,
                u.type_id,
                remaining_movement=-1,
                current_hp=u.current_hp,
            )
        )
    return scenario.with_units(tuple(new_units))
