#!/usr/bin/env python3
"""Deterministic sync of repo-root content/maps into game/content/maps for Godot."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tools.blender.terrain.eom_terrain_math_core import (  # noqa: E402
    parse_terrain_map_ir,
    sorted_edge_key,
)

SCHEMA_VERSION_V1 = 1
VALID_ORIGINS = {"reference", "authored", "generated"}
SUPPORTED_ORIENTATION = "pointy_top_custom_axes"
EDGE_RULE_DEFAULT = "smooth"
SUPPORTED_TRANSITIONS = {"smooth", "cliff"}
CANONICAL_NEIGHBOR_DELTAS = {
    (1, 0),
    (1, -1),
    (0, -1),
    (-1, 0),
    (-1, 1),
    (0, 1),
}
SOURCE_ROOT = Path("content") / "maps"
DEST_ROOT = Path("game") / "content" / "maps"
MANIFEST_NAME = "manifest.json"


@dataclass(frozen=True)
class SyncPlan:
    entries: list[dict[str, Any]]
    copies: list[tuple[Path, Path, bytes]]
    expected_dest_files: set[Path]
    manifest_bytes: bytes


def sha256_hex_lower(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def discover_source_maps(repo_root: Path) -> list[Path]:
    source_dir = repo_root / SOURCE_ROOT
    if not source_dir.is_dir():
        raise RuntimeError(f"Missing source maps directory: {source_dir}")
    paths = sorted(source_dir.rglob("*.json"))
    return [p for p in paths if p.name != MANIFEST_NAME]


def _require_json_int(value: Any, field_path: str) -> int:
    if isinstance(value, bool):
        raise RuntimeError(f"{field_path} must be an integer, got boolean")
    if isinstance(value, str):
        raise RuntimeError(f"{field_path} must be an integer, got string")
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        if not value.is_integer():
            raise RuntimeError(f"{field_path} must be an integer, got fractional number")
        return int(value)
    raise RuntimeError(f"{field_path} must be an integer")


def _require_json_string(value: Any, field_path: str, *, allow_empty: bool = False) -> str:
    if not isinstance(value, str):
        raise RuntimeError(f"{field_path} must be a string")
    if not allow_empty and not value.strip():
        raise RuntimeError(f"{field_path} must be a non-empty string")
    return value


def _require_json_finite_number(value: Any, field_path: str) -> float:
    if isinstance(value, bool):
        raise RuntimeError(f"{field_path} must be a number, got boolean")
    if isinstance(value, str):
        raise RuntimeError(f"{field_path} must be a number, got string")
    if isinstance(value, int):
        return float(value)
    if isinstance(value, float):
        if value != value or value in (float("inf"), float("-inf")):
            raise RuntimeError(f"{field_path} must be a finite number")
        return value
    raise RuntimeError(f"{field_path} must be a number")


def _are_adjacent(a: tuple[int, int], b: tuple[int, int]) -> bool:
    dq = b[0] - a[0]
    dr = b[1] - a[1]
    return (dq, dr) in CANONICAL_NEIGHBOR_DELTAS


def _parse_tile_coord(raw: Any, field_path: str) -> tuple[int, int]:
    if isinstance(raw, dict):
        q = _require_json_int(raw["q"], f"{field_path}.q")
        r = _require_json_int(raw["r"], f"{field_path}.r")
        return (q, r)
    if isinstance(raw, list) and len(raw) == 2:
        q = _require_json_int(raw[0], f"{field_path}[0]")
        r = _require_json_int(raw[1], f"{field_path}[1]")
        return (q, r)
    raise RuntimeError(f"Invalid tile coordinate at {field_path}")


def _parse_override_key_component(raw: str, field_path: str) -> int:
    stripped = raw.strip()
    if not stripped.lstrip("-").isdigit():
        raise RuntimeError(f"{field_path} must be an integer, got non-numeric string")
    return int(stripped)


def _normalize_transition(raw: Any, field_path: str, source: Path) -> str:
    transition = _require_json_string(raw, field_path)
    if transition not in SUPPORTED_TRANSITIONS:
        raise RuntimeError(
            f"Unsupported edge transition {transition!r} at {field_path} in {source}"
        )
    return transition


def _store_override(
    overrides: dict[tuple[tuple[int, int], tuple[int, int]], str],
    a: tuple[int, int],
    b: tuple[int, int],
    transition: str,
    field_path: str,
    source: Path,
    tiles: dict[tuple[int, int], int],
) -> None:
    if a == b:
        raise RuntimeError(f"{field_path} endpoints must be distinct in {source}")
    if a not in tiles:
        raise RuntimeError(f"{field_path} references missing tile {a} in {source}")
    if b not in tiles:
        raise RuntimeError(f"{field_path} references missing tile {b} in {source}")
    if not _are_adjacent(a, b):
        raise RuntimeError(
            f"{field_path} references non-adjacent tiles {a}-{b} in {source}"
        )
    edge_key = sorted_edge_key(a, b)
    if edge_key in overrides:
        raise RuntimeError(f"{field_path} duplicates override for edge {edge_key} in {source}")
    overrides[edge_key] = transition


def _validate_tiles_strict(logical_map: dict[str, Any], source: Path) -> dict[tuple[int, int], int]:
    tiles_raw = logical_map.get("tiles")
    if not isinstance(tiles_raw, list) or not tiles_raw:
        raise RuntimeError(f"Missing logical_map.tiles array in {source}")
    tiles: dict[tuple[int, int], int] = {}
    for index, tile in enumerate(tiles_raw):
        field_prefix = f"logical_map.tiles[{index}]"
        if not isinstance(tile, dict):
            raise RuntimeError(f"{field_prefix} must be an object in {source}")
        for key in ("q", "r", "elevation"):
            if key not in tile:
                raise RuntimeError(f"Missing {field_prefix}.{key} in {source}")
        q = _require_json_int(tile["q"], f"{field_prefix}.q")
        r = _require_json_int(tile["r"], f"{field_prefix}.r")
        elevation = _require_json_int(tile["elevation"], f"{field_prefix}.elevation")
        coord = (q, r)
        if coord in tiles:
            raise RuntimeError(f"Duplicate tile {coord} in {source}")
        tiles[coord] = elevation
    return tiles


def _validate_edge_overrides_strict(
    raw: Any, tiles: dict[tuple[int, int], int], source: Path
) -> None:
    if raw is None:
        return
    overrides: dict[tuple[tuple[int, int], tuple[int, int]], str] = {}
    if isinstance(raw, dict):
        for key, value in raw.items():
            key_str = str(key)
            parts = key_str.split(",")
            if len(parts) != 4:
                raise RuntimeError(f"Invalid edge override key {key_str!r} in {source}")
            a = (
                _parse_override_key_component(parts[0], f"edge_overrides[{key_str!r}].q1"),
                _parse_override_key_component(parts[1], f"edge_overrides[{key_str!r}].r1"),
            )
            b = (
                _parse_override_key_component(parts[2], f"edge_overrides[{key_str!r}].q2"),
                _parse_override_key_component(parts[3], f"edge_overrides[{key_str!r}].r2"),
            )
            transition = _normalize_transition(value, f"edge_overrides[{key_str!r}]", source)
            _store_override(overrides, a, b, transition, f"edge_overrides[{key_str!r}]", source, tiles)
        return
    if isinstance(raw, list):
        for index, entry in enumerate(raw):
            field_path = f"logical_map.edge_overrides[{index}]"
            if not isinstance(entry, dict):
                raise RuntimeError(f"{field_path} must be an object in {source}")
            if "edge" not in entry or "transition" not in entry:
                raise RuntimeError(f"{field_path} missing edge/transition in {source}")
            edge_raw = entry["edge"]
            if not isinstance(edge_raw, list) or len(edge_raw) != 2:
                raise RuntimeError(f"{field_path}.edge must be a pair of coordinates in {source}")
            a = _parse_tile_coord(edge_raw[0], f"{field_path}.edge[0]")
            b = _parse_tile_coord(edge_raw[1], f"{field_path}.edge[1]")
            transition = _normalize_transition(entry["transition"], f"{field_path}.transition", source)
            _store_override(overrides, a, b, transition, field_path, source, tiles)
        return
    raise RuntimeError(f"Unsupported edge_overrides format in {source}")


def validate_envelope(envelope: dict[str, Any], source: Path) -> None:
    if "schema_version" not in envelope:
        raise RuntimeError(f"Missing schema_version in {source}")
    schema_version = _require_json_int(envelope["schema_version"], "schema_version")
    if schema_version != SCHEMA_VERSION_V1:
        raise RuntimeError(f"Unsupported schema_version in {source}: {schema_version!r}")

    if "origin" not in envelope:
        raise RuntimeError(f"Missing origin in {source}")
    origin = _require_json_string(envelope["origin"], "origin")
    if origin not in VALID_ORIGINS:
        raise RuntimeError(f"Invalid origin {origin!r} in {source}")

    if "provenance" not in envelope:
        raise RuntimeError(f"Missing provenance in {source}")
    _require_json_string(envelope["provenance"], "provenance")

    logical_map = envelope.get("logical_map")
    if not isinstance(logical_map, dict):
        raise RuntimeError(f"Missing logical_map object in {source}")

    _require_json_string(logical_map["id"], "logical_map.id")
    orientation = _require_json_string(logical_map["orientation"], "logical_map.orientation")
    if orientation != SUPPORTED_ORIENTATION:
        raise RuntimeError(
            f"Unsupported logical_map.orientation {orientation!r} in {source}"
        )

    if "elevation_step" in logical_map:
        elevation_step = _require_json_finite_number(
            logical_map["elevation_step"], "logical_map.elevation_step"
        )
        if elevation_step <= 0.0:
            raise RuntimeError(f"logical_map.elevation_step must be > 0 in {source}")

    if "elevation_base" in logical_map:
        _require_json_int(logical_map["elevation_base"], "logical_map.elevation_base")

    edge_rule = logical_map.get("edge_rule")
    if not isinstance(edge_rule, dict):
        raise RuntimeError(f"Missing logical_map.edge_rule object in {source}")
    if "default" not in edge_rule:
        raise RuntimeError(f"Missing logical_map.edge_rule.default in {source}")
    default = _require_json_string(edge_rule["default"], "logical_map.edge_rule.default")
    if default != EDGE_RULE_DEFAULT:
        raise RuntimeError(
            f"Unsupported logical_map.edge_rule.default {default!r} in {source}"
        )
    if "cliff_if_abs_delta_greater_than" not in edge_rule:
        raise RuntimeError(
            f"Missing logical_map.edge_rule.cliff_if_abs_delta_greater_than in {source}"
        )
    _require_json_int(
        edge_rule["cliff_if_abs_delta_greater_than"],
        "logical_map.edge_rule.cliff_if_abs_delta_greater_than",
    )

    tiles = _validate_tiles_strict(logical_map, source)
    edge_overrides = logical_map.get("edge_overrides")
    if edge_overrides is not None and not isinstance(edge_overrides, (list, dict)):
        raise RuntimeError(f"logical_map.edge_overrides must be array or object in {source}")
    _validate_edge_overrides_strict(edge_overrides, tiles, source)

    try:
        parse_terrain_map_ir(logical_map)
    except ValueError as exc:
        raise RuntimeError(f"{source}: {exc}") from exc


def build_manifest_entry(
    source_path: Path, repo_root: Path, raw: bytes, envelope: dict[str, Any]
) -> dict[str, Any]:
    logical_map = envelope["logical_map"]
    rel_map_path = source_path.relative_to(repo_root / SOURCE_ROOT).as_posix()
    return {
        "path": rel_map_path,
        "map_id": str(logical_map["id"]),
        "schema_version": _require_json_int(envelope["schema_version"], "schema_version"),
        "content_hash": sha256_hex_lower(raw),
        "source_path": (SOURCE_ROOT / rel_map_path).as_posix(),
    }


def manifest_bytes_for_entries(entries: list[dict[str, Any]]) -> bytes:
    payload = {"maps": entries}
    text = json.dumps(payload, indent=2, sort_keys=False) + "\n"
    return text.encode("utf-8")


def plan_sync(repo_root: Path) -> SyncPlan:
    """Phase A: discover, read, validate all sources; compute desired derived state."""
    source_maps = discover_source_maps(repo_root)
    if not source_maps:
        raise RuntimeError(f"No map JSON files found under {repo_root / SOURCE_ROOT}")

    dest_root = repo_root / DEST_ROOT
    entries: list[dict[str, Any]] = []
    copies: list[tuple[Path, Path, bytes]] = []
    expected_dest_files: set[Path] = {dest_root / MANIFEST_NAME}

    for source_path in source_maps:
        raw = source_path.read_bytes()
        envelope = json.loads(raw.decode("utf-8"))
        validate_envelope(envelope, source_path)
        rel = source_path.relative_to(repo_root / SOURCE_ROOT)
        dest_path = dest_root / rel
        copies.append((source_path, dest_path, raw))
        expected_dest_files.add(dest_path)
        entries.append(build_manifest_entry(source_path, repo_root, raw, envelope))

    entries.sort(key=lambda e: e["path"])
    manifest_bytes = manifest_bytes_for_entries(entries)
    return SyncPlan(
        entries=entries,
        copies=copies,
        expected_dest_files=expected_dest_files,
        manifest_bytes=manifest_bytes,
    )


def apply_sync_plan(repo_root: Path, plan: SyncPlan) -> None:
    """Phase B: write validated copies, manifest, and reconcile owned extras."""
    dest_root = repo_root / DEST_ROOT
    dest_root.mkdir(parents=True, exist_ok=True)

    for _source_path, dest_path, raw in plan.copies:
        dest_path.parent.mkdir(parents=True, exist_ok=True)
        dest_path.write_bytes(raw)

    manifest_path = dest_root / MANIFEST_NAME
    manifest_path.write_bytes(plan.manifest_bytes)

    for existing in sorted(dest_root.rglob("*")):
        if existing.is_file() and existing not in plan.expected_dest_files:
            existing.unlink()

    for existing_dir in sorted(dest_root.rglob("*"), reverse=True):
        if existing_dir.is_dir() and not any(existing_dir.iterdir()):
            existing_dir.rmdir()


def sync_maps(repo_root: Path) -> list[dict[str, Any]]:
    plan = plan_sync(repo_root)
    apply_sync_plan(repo_root, plan)
    return plan.entries


def check_maps(repo_root: Path) -> None:
    plan = plan_sync(repo_root)

    manifest_path = repo_root / DEST_ROOT / MANIFEST_NAME
    if not manifest_path.is_file():
        raise RuntimeError(f"Missing manifest: {manifest_path}")

    existing_manifest = manifest_path.read_bytes()
    if existing_manifest != plan.manifest_bytes:
        raise RuntimeError("Manifest is stale or does not match canonical source maps")

    dest_root = repo_root / DEST_ROOT
    for _source_path, dest_path, raw in plan.copies:
        if not dest_path.is_file():
            raise RuntimeError(f"Missing derived map copy: {dest_path}")
        dest_raw = dest_path.read_bytes()
        if dest_raw != raw:
            raise RuntimeError(f"Derived map bytes differ from source: {dest_path}")
        if sha256_hex_lower(dest_raw) != sha256_hex_lower(raw):
            raise RuntimeError(f"Derived map hash mismatch: {dest_path}")

    for existing in dest_root.rglob("*"):
        if existing.is_file() and existing not in plan.expected_dest_files:
            raise RuntimeError(f"Unexpected extra derived file: {existing}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Sync or check canonical map content package")
    parser.add_argument(
        "command",
        choices=("sync", "check"),
        help="sync: copy maps and rewrite manifest; check: verify derived package freshness",
    )
    args = parser.parse_args(argv)

    repo_root = REPO_ROOT
    try:
        if args.command == "sync":
            entries = sync_maps(repo_root)
            print(f"Synced {len(entries)} map(s) to {DEST_ROOT.as_posix()}/")
            for entry in entries:
                print(f"  {entry['path']}  {entry['content_hash']}")
            return 0

        check_maps(repo_root)
        print(f"OK: derived package under {DEST_ROOT.as_posix()}/ matches canonical source")
        return 0
    except RuntimeError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
