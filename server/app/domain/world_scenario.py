"""N7 world scenario: deterministic starting units for world_map matches.

Server-owned spawn spec per canonical map_id (docs/MAP_CONTENT.md forbids a
map-content schema change for this). The first entry of the create request's
player_ids owns units 1-2, the second owns units 3-4; player ids stay
arbitrary integers. Every table is validated against the loaded WorldMap at
match creation, BEFORE anything is written: tiles must exist, positions must
be unique, the connecting spawn-group edges must be smooth, and after all
units are placed every unit must keep at least one unoccupied adjacent smooth
destination. Any divergence between this table and the canonical content is a
server failure (WorldScenarioError) - never a partial match, never a silent
adjustment.
"""

from __future__ import annotations

from typing import Any

from app.domain.hex_coord import DIRECTIONS
from app.domain.world_map import EDGE_SMOOTH, WorldMap

SUPPORTED_PLAYER_COUNT = 2

# Spawn rows per map: (unit_id, owner slot into player_ids, type_id, (q, r)).
# handdrawn_test_map_full_01 tiles chosen from the fully smooth interior
# regions nearest the r-extremes of the map (group distance 14); pinned by
# test_world_map_actions_v3.py against the canonical content.
_SPAWN_TABLES: dict[str, tuple[tuple[int, int, str, tuple[int, int]], ...]] = {
    "handdrawn_test_map_full_01": (
        (1, 0, "settler", (1, 1)),
        (2, 0, "warrior", (2, 1)),
        (3, 1, "settler", (2, 14)),
        (4, 1, "warrior", (2, 13)),
    ),
}


class WorldScenarioError(Exception):
    """Spawn table missing or diverged from canonical map content (server failure)."""


def supports_map(map_id: str) -> bool:
    return map_id in _SPAWN_TABLES


def build_starting_units(world_map: WorldMap, player_ids: list[int]) -> list[dict[str, Any]]:
    """Deterministic snapshot-v3 unit rows, sorted ascending by id.

    Raises WorldScenarioError on any spawn/content divergence; the caller must
    not have written any match state yet.
    """
    if len(player_ids) != SUPPORTED_PLAYER_COUNT:
        raise WorldScenarioError(
            "world scenario requires exactly %d player_ids, got %d"
            % (SUPPORTED_PLAYER_COUNT, len(player_ids))
        )
    map_id = world_map.identity.map_id
    table = _SPAWN_TABLES.get(map_id)
    if table is None:
        raise WorldScenarioError(f"no world spawn table for map_id {map_id}")

    units = [
        {
            "id": unit_id,
            "owner_id": int(player_ids[owner_slot]),
            "position": [pos[0], pos[1]],
            "type_id": type_id,
        }
        for unit_id, owner_slot, type_id, pos in table
    ]
    units.sort(key=lambda u: int(u["id"]))
    _validate_spawns(world_map, table)
    return units


def _validate_spawns(
    world_map: WorldMap,
    table: tuple[tuple[int, int, str, tuple[int, int]], ...],
) -> None:
    map_id = world_map.identity.map_id
    positions = [pos for _, _, _, pos in table]

    for pos in positions:
        if not world_map.has_tile_coord(pos):
            raise WorldScenarioError(f"spawn tile {pos} does not exist on map {map_id}")

    if len(set(positions)) != len(positions):
        raise WorldScenarioError(f"spawn positions are not unique on map {map_id}")

    # Each player's spawn group (settler + warrior) must be connected by a
    # smooth edge so the group is not split by a cliff.
    by_slot: dict[int, list[tuple[int, int]]] = {}
    for _, owner_slot, _, pos in table:
        by_slot.setdefault(owner_slot, []).append(pos)
    for owner_slot, group in by_slot.items():
        a, b = group[0], group[1]
        if not world_map.has_edge_between(a, b) or (
            world_map.edge_between(a, b).transition != EDGE_SMOOTH
        ):
            raise WorldScenarioError(
                f"spawn group for player slot {owner_slot} is not connected by a "
                f"smooth edge on map {map_id} ({a} - {b})"
            )

    occupied = set(positions)
    for _, _, type_id, pos in table:
        if not _has_free_smooth_neighbor(world_map, pos, occupied):
            raise WorldScenarioError(
                f"spawn {type_id} at {pos} has no unoccupied adjacent smooth "
                f"destination on map {map_id}"
            )


def _has_free_smooth_neighbor(
    world_map: WorldMap,
    pos: tuple[int, int],
    occupied: set[tuple[int, int]],
) -> bool:
    for dq, dr in DIRECTIONS:
        n = (pos[0] + dq, pos[1] + dr)
        if n in occupied or not world_map.has_tile_coord(n):
            continue
        if (
            world_map.has_edge_between(pos, n)
            and world_map.edge_between(pos, n).transition == EDGE_SMOOTH
        ):
            return True
    return False
