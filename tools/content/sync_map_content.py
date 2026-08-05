#!/usr/bin/env python3
"""Deterministic sync of repo-root content/maps into the committed derived copies.

Destinations (both byte-identical to the canonical source, each with its own
manifest.json): game/content/maps for Godot and server/content/maps for the
server Docker build context (N5 packaging; docs/MAP_CONTENT.md).
"""

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
)

SCHEMA_VERSION_V1 = 1
VALID_ORIGINS = {"reference", "authored", "generated"}
SUPPORTED_ORIENTATION = "pointy_top_custom_axes"
EDGE_RULE_DEFAULT = "smooth"
SOURCE_ROOT = Path("content") / "maps"
DEST_ROOT = Path("game") / "content" / "maps"
SERVER_DEST_ROOT = Path("server") / "content" / "maps"
DEST_ROOTS = (DEST_ROOT, SERVER_DEST_ROOT)
MANIFEST_NAME = "manifest.json"


class MapContentValidationError(RuntimeError):
    """Controlled failure for malformed canonical map content."""


def _load_envelope(raw: bytes, source: Path) -> dict[str, Any]:
    try:
        parsed = json.loads(raw.decode("utf-8"))
    except json.JSONDecodeError as exc:
        raise MapContentValidationError(f"Invalid JSON in {source}: {exc.msg}") from exc
    if not isinstance(parsed, dict):
        raise MapContentValidationError(f"Map file must contain a JSON object: {source}")
    return parsed


def validate_origin_folder(source_path: Path, repo_root: Path, envelope: dict[str, Any]) -> None:
    rel = source_path.relative_to(repo_root / SOURCE_ROOT)
    if not rel.parts:
        raise MapContentValidationError(f"Invalid source map path: {source_path}")
    category = rel.parts[0]
    origin = envelope.get("origin")
    if category not in VALID_ORIGINS:
        raise MapContentValidationError(
            f"Unsupported source category folder {category!r} for {source_path} "
            f"(declared origin {origin!r})"
        )
    if origin != category:
        raise MapContentValidationError(
            f"Origin {origin!r} does not match source category folder {category!r} for {source_path}"
        )


@dataclass(frozen=True)
class SyncPlan:
    entries: list[dict[str, Any]]
    # (source_path, path relative to a destination root, raw source bytes)
    copies: list[tuple[Path, Path, bytes]]
    # absolute destination root -> full set of files owned by the sync there
    expected_dest_files: dict[Path, set[Path]]
    manifest_bytes: bytes


def sha256_hex_lower(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def discover_source_maps(repo_root: Path) -> list[Path]:
    source_dir = repo_root / SOURCE_ROOT
    if not source_dir.is_dir():
        raise MapContentValidationError(f"Missing source maps directory: {source_dir}")
    paths = sorted(source_dir.rglob("*.json"))
    return [p for p in paths if p.name != MANIFEST_NAME]


def _require_json_int(value: Any, field_path: str) -> int:
    if isinstance(value, bool):
        raise MapContentValidationError(f"{field_path} must be an integer, got boolean")
    if isinstance(value, str):
        raise MapContentValidationError(f"{field_path} must be an integer, got string")
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        if value != value or value in (float("inf"), float("-inf")):
            raise MapContentValidationError(f"{field_path} must be an integer, got non-finite number")
        if not value.is_integer():
            raise MapContentValidationError(f"{field_path} must be an integer, got fractional number")
        return int(value)
    raise MapContentValidationError(f"{field_path} must be an integer")


def _require_json_string(value: Any, field_path: str, *, allow_empty: bool = False) -> str:
    if not isinstance(value, str):
        raise MapContentValidationError(f"{field_path} must be a string")
    if not allow_empty and not value.strip():
        raise MapContentValidationError(f"{field_path} must be a non-empty string")
    return value


def _require_json_finite_number(value: Any, field_path: str) -> float:
    if isinstance(value, bool):
        raise MapContentValidationError(f"{field_path} must be a number, got boolean")
    if isinstance(value, str):
        raise MapContentValidationError(f"{field_path} must be a number, got string")
    if isinstance(value, int):
        return float(value)
    if isinstance(value, float):
        if value != value or value in (float("inf"), float("-inf")):
            raise MapContentValidationError(f"{field_path} must be a finite number")
        return value
    raise MapContentValidationError(f"{field_path} must be a number")


def _validate_tiles_strict(logical_map: dict[str, Any], source: Path) -> dict[tuple[int, int], int]:
    tiles_raw = logical_map.get("tiles")
    if not isinstance(tiles_raw, list) or not tiles_raw:
        raise MapContentValidationError(f"Missing logical_map.tiles array in {source}")
    tiles: dict[tuple[int, int], int] = {}
    for index, tile in enumerate(tiles_raw):
        field_prefix = f"logical_map.tiles[{index}]"
        if not isinstance(tile, dict):
            raise MapContentValidationError(f"{field_prefix} must be an object in {source}")
        for key in ("q", "r", "elevation"):
            if key not in tile:
                raise MapContentValidationError(f"Missing {field_prefix}.{key} in {source}")
        q = _require_json_int(tile["q"], f"{field_prefix}.q")
        r = _require_json_int(tile["r"], f"{field_prefix}.r")
        elevation = _require_json_int(tile["elevation"], f"{field_prefix}.elevation")
        coord = (q, r)
        if coord in tiles:
            raise MapContentValidationError(f"Duplicate tile {coord} in {source}")
        tiles[coord] = elevation
    return tiles


def validate_envelope(envelope: dict[str, Any], source: Path) -> None:
    if "schema_version" not in envelope:
        raise MapContentValidationError(f"Missing schema_version in {source}")
    schema_version = _require_json_int(envelope["schema_version"], "schema_version")
    if schema_version != SCHEMA_VERSION_V1:
        raise MapContentValidationError(f"Unsupported schema_version in {source}: {schema_version!r}")

    if "origin" not in envelope:
        raise MapContentValidationError(f"Missing origin in {source}")
    origin = _require_json_string(envelope["origin"], "origin")
    if origin not in VALID_ORIGINS:
        raise MapContentValidationError(f"Invalid origin {origin!r} in {source}")

    if "provenance" not in envelope:
        raise MapContentValidationError(f"Missing provenance in {source}")
    _require_json_string(envelope["provenance"], "provenance")

    logical_map = envelope.get("logical_map")
    if not isinstance(logical_map, dict):
        raise MapContentValidationError(f"Missing logical_map object in {source}")

    if "id" not in logical_map:
        raise MapContentValidationError(f"Missing logical_map.id in {source}")
    _require_json_string(logical_map["id"], "logical_map.id")

    if "orientation" not in logical_map:
        raise MapContentValidationError(f"Missing logical_map.orientation in {source}")
    orientation = _require_json_string(logical_map["orientation"], "logical_map.orientation")
    if orientation != SUPPORTED_ORIENTATION:
        raise MapContentValidationError(
            f"Unsupported logical_map.orientation {orientation!r} in {source}"
        )

    if "elevation_step" in logical_map:
        elevation_step = _require_json_finite_number(
            logical_map["elevation_step"], "logical_map.elevation_step"
        )
        if elevation_step <= 0.0:
            raise MapContentValidationError(f"logical_map.elevation_step must be > 0 in {source}")

    if "elevation_base" in logical_map:
        _require_json_int(logical_map["elevation_base"], "logical_map.elevation_base")

    edge_rule = logical_map.get("edge_rule")
    if not isinstance(edge_rule, dict):
        raise MapContentValidationError(f"Missing logical_map.edge_rule object in {source}")
    if "default" not in edge_rule:
        raise MapContentValidationError(f"Missing logical_map.edge_rule.default in {source}")
    default = _require_json_string(edge_rule["default"], "logical_map.edge_rule.default")
    if default != EDGE_RULE_DEFAULT:
        raise MapContentValidationError(
            f"Unsupported logical_map.edge_rule.default {default!r} in {source}"
        )
    if "cliff_if_abs_delta_greater_than" not in edge_rule:
        raise MapContentValidationError(
            f"Missing logical_map.edge_rule.cliff_if_abs_delta_greater_than in {source}"
        )
    cliff_threshold = _require_json_int(
        edge_rule["cliff_if_abs_delta_greater_than"],
        "logical_map.edge_rule.cliff_if_abs_delta_greater_than",
    )
    if cliff_threshold < 0:
        raise MapContentValidationError(
            f"logical_map.edge_rule.cliff_if_abs_delta_greater_than must be >= 0 in {source}"
        )

    _validate_tiles_strict(logical_map, source)
    # edge_overrides is reserved: schema v1 requires it to be absent or an
    # empty array (same rule as the Godot and server loaders).
    if "edge_overrides" in logical_map:
        edge_overrides = logical_map["edge_overrides"]
        if edge_overrides is None:
            raise MapContentValidationError(
                f"logical_map.edge_overrides must be an array, got null in {source}"
            )
        if not isinstance(edge_overrides, list):
            raise MapContentValidationError(
                f"logical_map.edge_overrides must be an array in {source}"
            )
        if edge_overrides:
            raise MapContentValidationError(
                "logical_map.edge_overrides is reserved and must be empty in "
                f"schema v1 (functional overrides are unsupported) in {source}"
            )

    try:
        parse_terrain_map_ir(logical_map)
    except ValueError as exc:
        raise MapContentValidationError(f"{source}: {exc}") from exc


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
        raise MapContentValidationError(f"No map JSON files found under {repo_root / SOURCE_ROOT}")

    entries: list[dict[str, Any]] = []
    copies: list[tuple[Path, Path, bytes]] = []
    rel_paths: list[Path] = []

    for source_path in source_maps:
        raw = source_path.read_bytes()
        envelope = _load_envelope(raw, source_path)
        validate_envelope(envelope, source_path)
        validate_origin_folder(source_path, repo_root, envelope)
        rel = source_path.relative_to(repo_root / SOURCE_ROOT)
        copies.append((source_path, rel, raw))
        rel_paths.append(rel)
        entries.append(build_manifest_entry(source_path, repo_root, raw, envelope))

    expected_dest_files: dict[Path, set[Path]] = {}
    for dest_root_rel in DEST_ROOTS:
        dest_root = repo_root / dest_root_rel
        expected = {dest_root / MANIFEST_NAME}
        expected.update(dest_root / rel for rel in rel_paths)
        expected_dest_files[dest_root] = expected

    entries.sort(key=lambda e: e["path"])
    manifest_bytes = manifest_bytes_for_entries(entries)
    return SyncPlan(
        entries=entries,
        copies=copies,
        expected_dest_files=expected_dest_files,
        manifest_bytes=manifest_bytes,
    )


def apply_sync_plan(repo_root: Path, plan: SyncPlan) -> None:
    """Phase B: write validated copies, manifests, and reconcile owned extras."""
    for dest_root_rel in DEST_ROOTS:
        dest_root = repo_root / dest_root_rel
        dest_root.mkdir(parents=True, exist_ok=True)

        for _source_path, rel, raw in plan.copies:
            dest_path = dest_root / rel
            dest_path.parent.mkdir(parents=True, exist_ok=True)
            dest_path.write_bytes(raw)

        manifest_path = dest_root / MANIFEST_NAME
        manifest_path.write_bytes(plan.manifest_bytes)

        expected = plan.expected_dest_files[dest_root]
        for existing in sorted(dest_root.rglob("*")):
            if existing.is_file() and existing not in expected:
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

    for dest_root_rel in DEST_ROOTS:
        dest_root = repo_root / dest_root_rel

        manifest_path = dest_root / MANIFEST_NAME
        if not manifest_path.is_file():
            raise MapContentValidationError(f"Missing manifest: {manifest_path}")

        existing_manifest = manifest_path.read_bytes()
        if existing_manifest != plan.manifest_bytes:
            raise MapContentValidationError(
                f"Manifest is stale or does not match canonical source maps: {manifest_path}"
            )

        for _source_path, rel, raw in plan.copies:
            dest_path = dest_root / rel
            if not dest_path.is_file():
                raise MapContentValidationError(f"Missing derived map copy: {dest_path}")
            dest_raw = dest_path.read_bytes()
            if dest_raw != raw:
                raise MapContentValidationError(
                    f"Derived map bytes differ from source: {dest_path}"
                )
            if sha256_hex_lower(dest_raw) != sha256_hex_lower(raw):
                raise MapContentValidationError(f"Derived map hash mismatch: {dest_path}")

        expected = plan.expected_dest_files[dest_root]
        for existing in dest_root.rglob("*"):
            if existing.is_file() and existing not in expected:
                raise MapContentValidationError(f"Unexpected extra derived file: {existing}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Sync or check canonical map content package")
    parser.add_argument(
        "command",
        choices=("sync", "check"),
        help="sync: copy maps and rewrite manifest; check: verify derived package freshness",
    )
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=None,
        help="Repository root override (defaults to script location)",
    )
    args = parser.parse_args(argv)

    repo_root = args.repo_root.resolve() if args.repo_root else REPO_ROOT
    try:
        dest_labels = ", ".join(f"{root.as_posix()}/" for root in DEST_ROOTS)
        if args.command == "sync":
            entries = sync_maps(repo_root)
            print(f"Synced {len(entries)} map(s) to {dest_labels}")
            for entry in entries:
                print(f"  {entry['path']}  {entry['content_hash']}")
            return 0

        check_maps(repo_root)
        print(f"OK: derived packages under {dest_labels} match canonical source")
        return 0
    except MapContentValidationError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
