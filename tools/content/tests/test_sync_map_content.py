from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[3]
SYNC_SCRIPT = REPO_ROOT / "tools" / "content" / "sync_map_content.py"
SOURCE_MAP = REPO_ROOT / "content/maps/reference/handdrawn_test_map_full_01.json"
DEST_MAP = REPO_ROOT / "game/content/maps/reference/handdrawn_test_map_full_01.json"
MANIFEST = REPO_ROOT / "game/content/maps/manifest.json"
FIXTURES = REPO_ROOT / "game/domain/tests/fixtures/world"

REFERENCE_HASH = "16cc82c3392c66f1e47273e7da94cf8a804ae9885a051fc81c4b0a9a4261d8c6"


def _sha256(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def _run_sync(command: str, cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(SYNC_SCRIPT), command],
        cwd=str(cwd or REPO_ROOT),
        check=True,
        capture_output=True,
        text=True,
    )


def test_sync_is_clean_on_second_run() -> None:
    _run_sync("sync")
    second = _run_sync("sync")
    assert "Synced" in second.stdout


def test_source_and_dest_bytes_match() -> None:
    _run_sync("sync")
    source_raw = SOURCE_MAP.read_bytes()
    dest_raw = DEST_MAP.read_bytes()
    assert source_raw == dest_raw
    assert _sha256(source_raw) == REFERENCE_HASH


def test_manifest_hash_agreement() -> None:
    _run_sync("sync")
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    entry = manifest["maps"][0]
    assert entry["content_hash"] == REFERENCE_HASH
    assert entry["map_id"] == "handdrawn_test_map_full_01"
    assert entry["schema_version"] == 1
    assert entry["source_path"] == "content/maps/reference/handdrawn_test_map_full_01.json"


def test_check_passes() -> None:
    _run_sync("sync")
    _run_sync("check")


def test_check_from_non_repo_cwd() -> None:
    _run_sync("sync")
    _run_sync("check", cwd=Path(os.environ.get("TEMP", REPO_ROOT)))


def test_invalid_fixture_rejected_by_parser() -> None:
    sys.path.insert(0, str(REPO_ROOT / "tools" / "blender" / "terrain"))
    from eom_terrain_math_core import parse_terrain_map_ir  # noqa: WPS433

    bad = json.loads(
        (FIXTURES / "envelope_invalid_missing_schema.json").read_text(encoding="utf-8")
    )
    with pytest.raises(RuntimeError):
        if bad.get("schema_version") != 1:
            raise RuntimeError("unsupported schema")
        parse_terrain_map_ir(bad["logical_map"])

    invalid_origin = json.loads(
        (FIXTURES / "envelope_invalid_bad_origin.json").read_text(encoding="utf-8")
    )
    assert invalid_origin["origin"] not in {"reference", "authored", "generated"}


def test_stale_copy_detected() -> None:
    _run_sync("sync")
    dest_raw = DEST_MAP.read_bytes()
    DEST_MAP.write_bytes(dest_raw + b"\n")
    try:
        with pytest.raises(subprocess.CalledProcessError):
            _run_sync("check")
    finally:
        DEST_MAP.write_bytes(dest_raw)
