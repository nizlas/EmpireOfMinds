"""WorldMap match kind (N6/N7): snapshot v3 with MapIdentity + minimal state.

Snapshot v3 carries the canonical map identity (map_id, schema_version,
content_hash via MapIdentity.to_dict) plus only the mutable match state:
revision, turn_state, and - since N7 - the deterministic starting units
(auto-start later adds player_factions). It never embeds tiles, edges,
solved terrain or geometry - clients load canonical content by map_id and
verify the raw-byte hash (docs/MAP_CONTENT.md, docs/MAP_MODEL.md). Legacy
snapshot v2 is untouched.
"""

from __future__ import annotations

from typing import Any

from app.domain.map_content_loader import MapContentError, load_world_map
from app.domain.turn_state import turn_state_from_players
from app.domain.world_map import WorldMap
from app.domain.world_scenario import build_starting_units

MATCH_KIND_WORLD_MAP = "world_map"
SNAPSHOT_SCHEMA_V3 = 3
DEFAULT_WORLD_MAP_ID = "handdrawn_test_map_full_01"


class WorldMapResolutionError(Exception):
    """Canonical content for an existing match is missing or no longer matches
    the identity stored in its snapshot (server content/deployment drift)."""


def build_initial_world_snapshot(
    match_id: str,
    player_ids: list[int],
    map_id: str,
) -> dict[str, Any]:
    """Load + validate canonical content by map_id; raises MapContentError on
    load failure and WorldScenarioError on spawn/content divergence - both
    before the caller writes anything (never a partial match)."""
    world_map = load_world_map(map_id)
    return {
        "match_id": match_id,
        "schema_version": SNAPSHOT_SCHEMA_V3,
        "match_kind": MATCH_KIND_WORLD_MAP,
        "map": world_map.identity.to_dict(),
        "revision": 0,
        "turn_state": turn_state_from_players(player_ids),
        "units": build_starting_units(world_map, player_ids),
    }


def is_world_map_snapshot(snap: dict[str, Any]) -> bool:
    return snap.get("match_kind") == MATCH_KIND_WORLD_MAP


def resolve_world_map_for_snapshot(snap: dict[str, Any]) -> WorldMap:
    """Load the canonical WorldMap for a v3 snapshot and verify the stored
    MapIdentity exactly (map_id, schema_version, content_hash).

    N7 runs this for every supported world action before any mutation. No
    caching: the load recomputes the raw-byte hash, so drifted or missing
    content always fails closed (WorldMapResolutionError -> HTTP 500 at the
    API layer) instead of mutating a match against the wrong map.
    """
    stored = snap.get("map")
    map_id = str(stored.get("map_id", "")) if isinstance(stored, dict) else ""
    try:
        world_map = load_world_map(map_id)
    except MapContentError as exc:
        raise WorldMapResolutionError(
            f"world map content unavailable or mismatched for map_id {map_id}"
        ) from exc
    if world_map.identity.to_dict() != stored:
        raise WorldMapResolutionError(
            f"world map content unavailable or mismatched for map_id {map_id}"
        )
    return world_map
