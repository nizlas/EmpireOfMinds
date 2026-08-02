from __future__ import annotations

import hashlib
import json
import subprocess
import sys
import tempfile
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tools.content.sync_map_content import (  # noqa: E402
    DEST_ROOT,
    SOURCE_ROOT,
    check_maps,
    plan_sync,
    sync_maps,
    validate_envelope,
)

SYNC_SCRIPT = REPO_ROOT / "tools" / "content" / "sync_map_content.py"
SOURCE_MAP = REPO_ROOT / "content/maps/reference/handdrawn_test_map_full_01.json"
DEST_ROOT_PATH = REPO_ROOT / DEST_ROOT
DEST_MAP = DEST_ROOT_PATH / "reference/handdrawn_test_map_full_01.json"
MANIFEST = DEST_ROOT_PATH / "manifest.json"
FIXTURES = REPO_ROOT / "game/domain/tests/fixtures/world"
VALID_MINIMAL = FIXTURES / "envelope_valid_minimal.json"

REFERENCE_HASH = "16cc82c3392c66f1e47273e7da94cf8a804ae9885a051fc81c4b0a9a4261d8c6"

INVALID_FIXTURES = [
    "envelope_invalid_missing_schema.json",
    "envelope_invalid_bad_origin.json",
    "envelope_invalid_string_schema_version.json",
    "envelope_invalid_fractional_tile_q.json",
    "envelope_invalid_orientation.json",
    "envelope_invalid_edge_rule_default.json",
    "envelope_invalid_threshold_string.json",
    "envelope_invalid_string_elevation.json",
    "envelope_invalid_override_missing_tile.json",
    "envelope_invalid_override_non_adjacent.json",
    "envelope_invalid_override_malformed_edge.json",
    "envelope_invalid_duplicate_override.json",
]


def _sha256(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def _run_sync_subprocess(command: str, cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(SYNC_SCRIPT), command],
        cwd=str(cwd),
        capture_output=True,
        text=True,
    )


def _capture_derived_tree(root: Path) -> dict[str, bytes]:
    if not root.is_dir():
        return {}
    captured: dict[str, bytes] = {}
    for path in sorted(root.rglob("*")):
        if path.is_file():
            captured[path.relative_to(root).as_posix()] = path.read_bytes()
    return captured


def _write_temp_repo(repo_root: Path) -> None:
    (repo_root / SOURCE_ROOT / "reference").mkdir(parents=True, exist_ok=True)
    (repo_root / DEST_ROOT / "reference").mkdir(parents=True, exist_ok=True)


def test_sync_is_clean_on_second_run() -> None:
    assert _run_sync_subprocess("sync", REPO_ROOT).returncode == 0
    first = _capture_derived_tree(DEST_ROOT_PATH)
    assert first, "expected derived package after first sync"
    assert _run_sync_subprocess("sync", REPO_ROOT).returncode == 0
    second = _capture_derived_tree(DEST_ROOT_PATH)
    assert first == second


def test_source_and_dest_bytes_match() -> None:
    assert _run_sync_subprocess("sync", REPO_ROOT).returncode == 0
    source_raw = SOURCE_MAP.read_bytes()
    dest_raw = DEST_MAP.read_bytes()
    assert source_raw == dest_raw
    assert _sha256(source_raw) == REFERENCE_HASH
    assert len(source_raw) == 12680


def test_manifest_hash_agreement() -> None:
    assert _run_sync_subprocess("sync", REPO_ROOT).returncode == 0
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    entry = manifest["maps"][0]
    assert entry["content_hash"] == REFERENCE_HASH
    assert entry["map_id"] == "handdrawn_test_map_full_01"
    assert entry["schema_version"] == 1
    assert entry["source_path"] == "content/maps/reference/handdrawn_test_map_full_01.json"


def test_check_passes() -> None:
    assert _run_sync_subprocess("sync", REPO_ROOT).returncode == 0
    assert _run_sync_subprocess("check", REPO_ROOT).returncode == 0


def test_check_from_non_repo_cwd() -> None:
    assert _run_sync_subprocess("sync", REPO_ROOT).returncode == 0
    with tempfile.TemporaryDirectory() as tmp:
        cwd = Path(tmp).resolve()
        assert cwd != REPO_ROOT.resolve()
        result = _run_sync_subprocess("check", cwd)
        assert result.returncode == 0, result.stderr


@pytest.mark.parametrize("fixture_name", INVALID_FIXTURES)
def test_invalid_fixture_rejected_by_validate_envelope(fixture_name: str) -> None:
    envelope = json.loads((FIXTURES / fixture_name).read_text(encoding="utf-8"))
    with pytest.raises(RuntimeError):
        validate_envelope(envelope, Path(fixture_name))


def test_stale_copy_detected() -> None:
    assert _run_sync_subprocess("sync", REPO_ROOT).returncode == 0
    dest_raw = DEST_MAP.read_bytes()
    DEST_MAP.write_bytes(dest_raw + b"\n")
    try:
        result = _run_sync_subprocess("check", REPO_ROOT)
        assert result.returncode != 0
    finally:
        DEST_MAP.write_bytes(dest_raw)


def test_missing_derived_map_detected() -> None:
    assert _run_sync_subprocess("sync", REPO_ROOT).returncode == 0
    dest_raw = DEST_MAP.read_bytes()
    DEST_MAP.unlink()
    try:
        result = _run_sync_subprocess("check", REPO_ROOT)
        assert result.returncode != 0
    finally:
        DEST_MAP.parent.mkdir(parents=True, exist_ok=True)
        DEST_MAP.write_bytes(dest_raw)


def test_extra_derived_file_detected() -> None:
    assert _run_sync_subprocess("sync", REPO_ROOT).returncode == 0
    extra = DEST_ROOT_PATH / "extra_owned_file.txt"
    extra.write_bytes(b"unexpected")
    try:
        result = _run_sync_subprocess("check", REPO_ROOT)
        assert result.returncode != 0
    finally:
        extra.unlink()


def test_missing_manifest_detected() -> None:
    assert _run_sync_subprocess("sync", REPO_ROOT).returncode == 0
    manifest_raw = MANIFEST.read_bytes()
    MANIFEST.unlink()
    try:
        result = _run_sync_subprocess("check", REPO_ROOT)
        assert result.returncode != 0
    finally:
        MANIFEST.write_bytes(manifest_raw)


def test_validate_all_before_write_leaves_derived_tree_unchanged() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        repo_root = Path(tmp) / "mini_repo"
        _write_temp_repo(repo_root)

        valid_src = repo_root / SOURCE_ROOT / "reference" / "aaa_valid.json"
        valid_src.write_bytes(VALID_MINIMAL.read_bytes())

        derived_root = repo_root / DEST_ROOT
        preexisting = derived_root / "reference" / "preexisting.json"
        preexisting.parent.mkdir(parents=True, exist_ok=True)
        preexisting.write_bytes(b"PREEXISTING_DERIVED_BYTES")
        manifest = derived_root / "manifest.json"
        manifest.write_bytes(b'{"maps":[]}\n')

        before = _capture_derived_tree(derived_root)

        invalid_src = repo_root / SOURCE_ROOT / "reference" / "zzz_invalid.json"
        invalid_src.write_text(
            (FIXTURES / "envelope_invalid_orientation.json").read_text(encoding="utf-8"),
            encoding="utf-8",
        )

        with pytest.raises(RuntimeError):
            sync_maps(repo_root)

        after = _capture_derived_tree(derived_root)
        assert before == after


def test_plan_sync_validates_all_sources_before_apply() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        repo_root = Path(tmp) / "mini_repo"
        _write_temp_repo(repo_root)

        valid_src = repo_root / SOURCE_ROOT / "reference" / "aaa_valid.json"
        valid_src.write_bytes(VALID_MINIMAL.read_bytes())

        invalid_src = repo_root / SOURCE_ROOT / "reference" / "zzz_invalid.json"
        invalid_src.write_text(
            (FIXTURES / "envelope_invalid_string_schema_version.json").read_text(
                encoding="utf-8"
            ),
            encoding="utf-8",
        )

        with pytest.raises(RuntimeError):
            plan_sync(repo_root)

        derived_root = repo_root / DEST_ROOT
        assert _capture_derived_tree(derived_root) == {}


def test_check_mode_is_side_effect_free() -> None:
    assert _run_sync_subprocess("sync", REPO_ROOT).returncode == 0
    before = _capture_derived_tree(DEST_ROOT_PATH)
    assert _run_sync_subprocess("check", REPO_ROOT).returncode == 0
    after = _capture_derived_tree(DEST_ROOT_PATH)
    assert before == after


def test_sync_maps_direct_api_matches_repo() -> None:
    entries = sync_maps(REPO_ROOT)
    assert len(entries) >= 1
    check_maps(REPO_ROOT)
