"""Server-owned canonical map-content loader (N5).

Parity: game/domain/world/map_content_loader.gd — identical strict schema v1
validation, integer semantics and edge derivation. The loader COMPUTES
MapIdentity (map_id, schema_version, raw-byte SHA-256 content_hash); it never
compares against an expected identity — identity comparison is the N6 Godot
bootstrap (docs/MAP_CONTENT.md).

Content-root resolution (deterministic, no silent fallback):
1. EMPIRE_MAP_CONTENT_DIR — authoritative when set; an invalid override raises
   InvalidContentRootError and never falls back to packaged/repo content.
2. <server_root>/content/maps — packaged layout (/app/content/maps in the
   container, server/content/maps in a checkout).
3. <repo_root>/content/maps — dev-checkout fallback.
"""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
from typing import Any

from app.domain.hex_coord import DIRECTIONS
from app.domain.world_map import (
    EDGE_CLIFF,
    EDGE_SMOOTH,
    MapIdentity,
    WorldEdge,
    WorldMap,
    WorldTile,
    normalized_edge_key,
    parse_edge_key,
)

SCHEMA_VERSION_V1 = 1
VALID_ORIGINS = ("authored", "generated", "reference")
SUPPORTED_ORIENTATION = "pointy_top_custom_axes"
EDGE_RULE_DEFAULT = "smooth"
DEFAULT_ELEVATION_BASE = 1
DEFAULT_ELEVATION_STEP = 0.4

_ENV_CONTENT_DIR = "EMPIRE_MAP_CONTENT_DIR"
_MANIFEST_NAME = "manifest.json"


class MapContentError(Exception):
    """Base for all canonical map-content loading failures."""


class InvalidContentRootError(MapContentError):
    """Content root missing or unusable (including an invalid env override)."""


class UnknownMapIdError(MapContentError):
    """Requested map_id is not present under the resolved content root."""


class DuplicateMapIdError(MapContentError):
    """The same logical_map.id appears in more than one content file."""


class InvalidMapContentError(MapContentError):
    """A content file violates the canonical schema v1 contract."""


def _server_root() -> Path:
    # server/app/domain/map_content_loader.py -> server/
    return Path(__file__).resolve().parent.parent.parent


def resolve_content_root() -> Path:
    env = os.environ.get(_ENV_CONTENT_DIR)
    if env:
        override = Path(env)
        if not override.is_dir():
            raise InvalidContentRootError(
                f"{_ENV_CONTENT_DIR} is set but is not an existing directory: {override}"
            )
        return override

    packaged = _server_root() / "content" / "maps"
    if packaged.is_dir():
        return packaged

    repo_fallback = _server_root().parent / "content" / "maps"
    if repo_fallback.is_dir():
        return repo_fallback

    raise InvalidContentRootError(
        "No canonical map content root found "
        f"(checked {packaged} and {repo_fallback}; {_ENV_CONTENT_DIR} unset)"
    )


def _index_map_files(content_root: Path) -> dict[str, Path]:
    """Deterministic map_id -> file index with canonical-contract enforcement."""
    index: dict[str, Path] = {}
    for category in VALID_ORIGINS:
        category_dir = content_root / category
        if not category_dir.is_dir():
            continue
        for path in sorted(category_dir.rglob("*.json")):
            if path.name == _MANIFEST_NAME:
                continue
            envelope = _read_envelope_object(path)
            _require_origin_matches_category(envelope, category, path)
            map_id = _read_map_id(envelope, path)
            if map_id in index:
                first, second = sorted((index[map_id], path))
                raise DuplicateMapIdError(
                    f"Duplicate logical_map.id {map_id!r} in {first} and {second}"
                )
            index[map_id] = path
    return index


def _read_envelope_object(path: Path) -> dict[str, Any]:
    raw = path.read_bytes()
    return _parse_envelope_bytes(raw, path)


def _parse_envelope_bytes(raw: bytes, source: Path) -> dict[str, Any]:
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise InvalidMapContentError(f"Map file is not valid UTF-8: {source}") from exc
    try:
        parsed = json.loads(text)
    except json.JSONDecodeError as exc:
        raise InvalidMapContentError(f"Invalid JSON in map file {source}: {exc.msg}") from exc
    if not isinstance(parsed, dict):
        raise InvalidMapContentError(f"Map file must contain a JSON object: {source}")
    return parsed


def _require_origin_matches_category(
    envelope: dict[str, Any], category: str, source: Path
) -> None:
    origin = envelope.get("origin")
    if origin != category:
        raise InvalidMapContentError(
            f"Origin {origin!r} does not match category folder {category!r} for {source}"
        )


def _read_map_id(envelope: dict[str, Any], source: Path) -> str:
    logical_map = envelope.get("logical_map")
    if not isinstance(logical_map, dict):
        raise InvalidMapContentError(f"Missing or invalid logical_map in {source}")
    if "id" not in logical_map:
        raise InvalidMapContentError(f"Missing logical_map.id in {source}")
    map_id = logical_map["id"]
    if not isinstance(map_id, str) or not map_id.strip():
        raise InvalidMapContentError(f"logical_map.id must be a non-empty string in {source}")
    return map_id


def load_world_map(map_id: str) -> WorldMap:
    """Load, validate and derive the WorldMap for a canonical map_id."""
    content_root = resolve_content_root()
    index = _index_map_files(content_root)
    if map_id not in index:
        raise UnknownMapIdError(
            f"Unknown map_id {map_id!r} under content root {content_root}"
        )
    return load_world_map_from_file(index[map_id])


def load_world_map_from_file(path: Path) -> WorldMap:
    if not path.is_file():
        raise InvalidMapContentError(f"Map file not found: {path}")
    raw = path.read_bytes()
    content_hash = hashlib.sha256(raw).hexdigest()

    envelope = _parse_envelope_bytes(raw, path)
    _validate_envelope(envelope, path)
    parsed = _parse_logical_map(envelope["logical_map"], path)

    identity = MapIdentity(parsed["map_id"], SCHEMA_VERSION_V1, content_hash)
    edges = _derive_edges(parsed["tiles"], parsed["cliff_threshold"])
    return WorldMap(
        identity=identity,
        elevation_step=parsed["elevation_step"],
        elevation_base=parsed["elevation_base"],
        cliff_threshold=parsed["cliff_threshold"],
        tiles=parsed["tiles"],
        edges=edges,
    )


def _require_json_int(value: Any, field_path: str) -> int:
    if isinstance(value, bool):
        raise InvalidMapContentError(f"{field_path} must be an integer, got boolean")
    if isinstance(value, str):
        raise InvalidMapContentError(f"{field_path} must be an integer, got string")
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        if value != value or value in (float("inf"), float("-inf")):
            raise InvalidMapContentError(
                f"{field_path} must be an integer, got non-finite number"
            )
        if not value.is_integer():
            raise InvalidMapContentError(
                f"{field_path} must be an integer, got fractional number"
            )
        return int(value)
    raise InvalidMapContentError(f"{field_path} must be an integer")


def _require_json_finite_number(value: Any, field_path: str) -> float:
    if isinstance(value, bool):
        raise InvalidMapContentError(f"{field_path} must be a number, got boolean")
    if isinstance(value, str):
        raise InvalidMapContentError(f"{field_path} must be a number, got string")
    if isinstance(value, int):
        return float(value)
    if isinstance(value, float):
        if value != value or value in (float("inf"), float("-inf")):
            raise InvalidMapContentError(f"{field_path} must be a finite number")
        return value
    raise InvalidMapContentError(f"{field_path} must be a number")


def _require_json_string(value: Any, field_path: str, *, allow_empty: bool = False) -> str:
    if not isinstance(value, str):
        raise InvalidMapContentError(f"{field_path} must be a string")
    if not allow_empty and not value.strip():
        raise InvalidMapContentError(f"{field_path} must be a non-empty string")
    return value


def _validate_envelope(envelope: dict[str, Any], source: Path) -> None:
    if "schema_version" not in envelope:
        raise InvalidMapContentError(f"Missing schema_version in {source}")
    schema_version = _require_json_int(envelope["schema_version"], "schema_version")
    if schema_version != SCHEMA_VERSION_V1:
        raise InvalidMapContentError(f"Unsupported schema_version {schema_version} in {source}")

    if "origin" not in envelope:
        raise InvalidMapContentError(f"Missing origin in {source}")
    origin = _require_json_string(envelope["origin"], "origin")
    if origin not in VALID_ORIGINS:
        raise InvalidMapContentError(f"Invalid origin {origin} in {source}")

    if "provenance" not in envelope:
        raise InvalidMapContentError(f"Missing provenance in {source}")
    _require_json_string(envelope["provenance"], "provenance")

    if "logical_map" not in envelope or not isinstance(envelope["logical_map"], dict):
        raise InvalidMapContentError(f"Missing or invalid logical_map in {source}")


def _parse_logical_map(logical_map: dict[str, Any], source: Path) -> dict[str, Any]:
    if "id" not in logical_map:
        raise InvalidMapContentError(f"Missing logical_map.id in {source}")
    map_id = _require_json_string(logical_map["id"], "logical_map.id")

    if "orientation" not in logical_map:
        raise InvalidMapContentError(f"Missing logical_map.orientation in {source}")
    orientation = _require_json_string(logical_map["orientation"], "logical_map.orientation")
    if orientation != SUPPORTED_ORIENTATION:
        raise InvalidMapContentError(
            f"Unsupported logical_map.orientation {orientation} in {source}"
        )

    if "tiles" not in logical_map or not isinstance(logical_map["tiles"], list):
        raise InvalidMapContentError(f"Missing logical_map.tiles array in {source}")
    if not logical_map["tiles"]:
        raise InvalidMapContentError(f"logical_map.tiles must not be empty in {source}")

    elevation_step = DEFAULT_ELEVATION_STEP
    if "elevation_step" in logical_map:
        elevation_step = _require_json_finite_number(
            logical_map["elevation_step"], "logical_map.elevation_step"
        )
    if elevation_step <= 0.0:
        raise InvalidMapContentError(f"logical_map.elevation_step must be > 0 in {source}")

    elevation_base = DEFAULT_ELEVATION_BASE
    if "elevation_base" in logical_map:
        elevation_base = _require_json_int(
            logical_map["elevation_base"], "logical_map.elevation_base"
        )

    if "edge_rule" not in logical_map or not isinstance(logical_map["edge_rule"], dict):
        raise InvalidMapContentError(f"Missing logical_map.edge_rule object in {source}")
    edge_rule = logical_map["edge_rule"]
    if "default" not in edge_rule:
        raise InvalidMapContentError(f"Missing logical_map.edge_rule.default in {source}")
    default = _require_json_string(edge_rule["default"], "logical_map.edge_rule.default")
    if default != EDGE_RULE_DEFAULT:
        raise InvalidMapContentError(
            f"Unsupported logical_map.edge_rule.default {default} in {source}"
        )
    if "cliff_if_abs_delta_greater_than" not in edge_rule:
        raise InvalidMapContentError(
            f"Missing logical_map.edge_rule.cliff_if_abs_delta_greater_than in {source}"
        )
    cliff_threshold = _require_json_int(
        edge_rule["cliff_if_abs_delta_greater_than"],
        "logical_map.edge_rule.cliff_if_abs_delta_greater_than",
    )
    if cliff_threshold < 0:
        raise InvalidMapContentError(
            f"logical_map.edge_rule.cliff_if_abs_delta_greater_than must be >= 0 in {source}"
        )

    tiles: dict[tuple[int, int], WorldTile] = {}
    for tile_index, tile_entry in enumerate(logical_map["tiles"]):
        tile_path = f"logical_map.tiles[{tile_index}]"
        if not isinstance(tile_entry, dict):
            raise InvalidMapContentError(f"{tile_path} must be an object in {source}")
        for key in ("q", "r", "elevation"):
            if key not in tile_entry:
                raise InvalidMapContentError(f"Missing {tile_path}.{key} in {source}")
        q = _require_json_int(tile_entry["q"], f"{tile_path}.q")
        r = _require_json_int(tile_entry["r"], f"{tile_path}.r")
        elevation = _require_json_int(tile_entry["elevation"], f"{tile_path}.elevation")
        coord = (q, r)
        if coord in tiles:
            raise InvalidMapContentError(f"Duplicate tile ({q},{r}) in {source}")
        tiles[coord] = WorldTile(q, r, elevation)

    # edge_overrides is reserved: schema v1 requires it to be absent or an
    # empty array (same rule as the Godot loader and the sync tool).
    if "edge_overrides" in logical_map:
        raw_overrides = logical_map["edge_overrides"]
        if raw_overrides is None:
            raise InvalidMapContentError(
                f"logical_map.edge_overrides must be an array, got null in {source}"
            )
        if not isinstance(raw_overrides, list):
            raise InvalidMapContentError(
                f"logical_map.edge_overrides must be an array in {source}"
            )
        if raw_overrides:
            raise InvalidMapContentError(
                "logical_map.edge_overrides is reserved and must be empty in "
                f"schema v1 (functional overrides are unsupported) in {source}"
            )

    return {
        "map_id": map_id,
        "elevation_step": elevation_step,
        "elevation_base": elevation_base,
        "cliff_threshold": cliff_threshold,
        "tiles": tiles,
    }


def _derive_edges(
    tiles: dict[tuple[int, int], WorldTile], cliff_threshold: int
) -> dict[str, WorldEdge]:
    """Every edge classification derived from the height grid + threshold rule."""
    edges: dict[str, WorldEdge] = {}
    for coord, tile in tiles.items():
        for dq, dr in DIRECTIONS:
            neighbor = (coord[0] + dq, coord[1] + dr)
            if neighbor not in tiles:
                continue
            edge_key = normalized_edge_key(coord, neighbor)
            if edge_key in edges:
                continue
            transition = EDGE_SMOOTH
            if abs(tile.elevation - tiles[neighbor].elevation) > cliff_threshold:
                transition = EDGE_CLIFF
            tile_a, tile_b = parse_edge_key(edge_key)
            edges[edge_key] = WorldEdge(tile_a, tile_b, transition)
    return edges
