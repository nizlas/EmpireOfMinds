#!/usr/bin/env python3
"""Deterministic sync of repo-root content/maps into game/content/maps for Godot."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tools.blender.terrain.eom_terrain_math_core import parse_terrain_map_ir  # noqa: E402

SCHEMA_VERSION_V1 = 1
VALID_ORIGINS = {"reference", "authored", "generated"}
SOURCE_ROOT = Path("content") / "maps"
DEST_ROOT = Path("game") / "content" / "maps"
MANIFEST_NAME = "manifest.json"


def sha256_hex_lower(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def discover_source_maps(repo_root: Path) -> list[Path]:
    source_dir = repo_root / SOURCE_ROOT
    if not source_dir.is_dir():
        raise RuntimeError(f"Missing source maps directory: {source_dir}")
    paths = sorted(source_dir.rglob("*.json"))
    return [p for p in paths if p.name != MANIFEST_NAME]


def validate_envelope(envelope: dict[str, Any], source: Path) -> None:
    if envelope.get("schema_version") != SCHEMA_VERSION_V1:
        raise RuntimeError(
            f"Unsupported schema_version in {source}: {envelope.get('schema_version')!r}"
        )
    origin = envelope.get("origin")
    if origin not in VALID_ORIGINS:
        raise RuntimeError(f"Invalid origin {origin!r} in {source}")
    provenance = envelope.get("provenance")
    if not isinstance(provenance, str) or not provenance.strip():
        raise RuntimeError(f"Invalid provenance in {source}")
    logical_map = envelope.get("logical_map")
    if not isinstance(logical_map, dict):
        raise RuntimeError(f"Missing logical_map object in {source}")
    parse_terrain_map_ir(logical_map)


def build_manifest_entry(source_path: Path, repo_root: Path) -> dict[str, Any]:
    raw = source_path.read_bytes()
    envelope = json.loads(raw.decode("utf-8"))
    validate_envelope(envelope, source_path)
    logical_map = envelope["logical_map"]
    rel_map_path = source_path.relative_to(repo_root / SOURCE_ROOT).as_posix()
    return {
        "path": rel_map_path,
        "map_id": str(logical_map["id"]),
        "schema_version": int(envelope["schema_version"]),
        "content_hash": sha256_hex_lower(raw),
        "source_path": (SOURCE_ROOT / rel_map_path).as_posix(),
    }


def write_manifest(repo_root: Path, entries: list[dict[str, Any]]) -> Path:
    manifest_path = repo_root / DEST_ROOT / MANIFEST_NAME
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    payload = {"maps": entries}
    text = json.dumps(payload, indent=2, sort_keys=False) + "\n"
    manifest_path.write_text(text, encoding="utf-8", newline="\n")
    return manifest_path


def sync_maps(repo_root: Path) -> list[dict[str, Any]]:
    source_maps = discover_source_maps(repo_root)
    if not source_maps:
        raise RuntimeError(f"No map JSON files found under {repo_root / SOURCE_ROOT}")

    entries: list[dict[str, Any]] = []
    dest_root = repo_root / DEST_ROOT
    dest_root.mkdir(parents=True, exist_ok=True)

    expected_dest_files: set[Path] = {dest_root / MANIFEST_NAME}
    for source_path in source_maps:
        rel = source_path.relative_to(repo_root / SOURCE_ROOT)
        dest_path = dest_root / rel
        dest_path.parent.mkdir(parents=True, exist_ok=True)
        raw = source_path.read_bytes()
        validate_envelope(json.loads(raw.decode("utf-8")), source_path)
        if dest_path.exists():
            existing = dest_path.read_bytes()
            if existing != raw:
                dest_path.write_bytes(raw)
        else:
            shutil.copyfile(source_path, dest_path)
        expected_dest_files.add(dest_path)
        entries.append(build_manifest_entry(source_path, repo_root))

    entries.sort(key=lambda e: e["path"])
    write_manifest(repo_root, entries)

    for existing in sorted(dest_root.rglob("*")):
        if existing.is_file() and existing not in expected_dest_files:
            existing.unlink()

    for existing_dir in sorted(dest_root.rglob("*"), reverse=True):
        if existing_dir.is_dir() and not any(existing_dir.iterdir()):
            existing_dir.rmdir()

    return entries


def check_maps(repo_root: Path) -> None:
    source_maps = discover_source_maps(repo_root)
    entries = [build_manifest_entry(p, repo_root) for p in source_maps]
    entries.sort(key=lambda e: e["path"])

    manifest_path = repo_root / DEST_ROOT / MANIFEST_NAME
    if not manifest_path.is_file():
        raise RuntimeError(f"Missing manifest: {manifest_path}")

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("maps") != entries:
        raise RuntimeError("Manifest is stale or does not match canonical source maps")

    dest_root = repo_root / DEST_ROOT
    expected_dest_files = {dest_root / MANIFEST_NAME}
    for source_path in source_maps:
        rel = source_path.relative_to(repo_root / SOURCE_ROOT)
        dest_path = dest_root / rel
        expected_dest_files.add(dest_path)
        if not dest_path.is_file():
            raise RuntimeError(f"Missing derived map copy: {dest_path}")
        source_raw = source_path.read_bytes()
        dest_raw = dest_path.read_bytes()
        if source_raw != dest_raw:
            raise RuntimeError(f"Derived map bytes differ from source: {dest_path}")
        if sha256_hex_lower(dest_raw) != sha256_hex_lower(source_raw):
            raise RuntimeError(f"Derived map hash mismatch: {dest_path}")

    for existing in dest_root.rglob("*"):
        if existing.is_file() and existing not in expected_dest_files:
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
    if args.command == "sync":
        entries = sync_maps(repo_root)
        print(f"Synced {len(entries)} map(s) to {DEST_ROOT.as_posix()}/")
        for entry in entries:
            print(f"  {entry['path']}  {entry['content_hash']}")
        return 0

    check_maps(repo_root)
    print(f"OK: derived package under {DEST_ROOT.as_posix()}/ matches canonical source")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
