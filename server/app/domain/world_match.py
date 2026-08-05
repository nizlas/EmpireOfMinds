"""WorldMap match kind (N6): minimal snapshot v3 with MapIdentity only.

Snapshot v3 carries the canonical map identity (map_id, schema_version,
content_hash via MapIdentity.to_dict) plus only the mutable state an
otherwise empty match needs (revision, turn_state; auto-start later adds
player_factions). It never embeds tiles, edges, solved terrain or geometry —
clients load canonical content by map_id and verify the raw-byte hash
(docs/MAP_CONTENT.md, docs/MAP_MODEL.md). Legacy snapshot v2 is untouched.
"""

from __future__ import annotations

from typing import Any

from app.domain.map_content_loader import load_world_map
from app.domain.turn_state import turn_state_from_players

MATCH_KIND_WORLD_MAP = "world_map"
SNAPSHOT_SCHEMA_V3 = 3
DEFAULT_WORLD_MAP_ID = "handdrawn_test_map_full_01"


def build_initial_world_snapshot(
    match_id: str,
    player_ids: list[int],
    map_id: str,
) -> dict[str, Any]:
    """Load + validate canonical content by map_id; raises MapContentError on failure."""
    world_map = load_world_map(map_id)
    return {
        "match_id": match_id,
        "schema_version": SNAPSHOT_SCHEMA_V3,
        "match_kind": MATCH_KIND_WORLD_MAP,
        "map": world_map.identity.to_dict(),
        "revision": 0,
        "turn_state": turn_state_from_players(player_ids),
    }


def is_world_map_snapshot(snap: dict[str, Any]) -> bool:
    return snap.get("match_kind") == MATCH_KIND_WORLD_MAP
