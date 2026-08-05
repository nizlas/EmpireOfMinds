"""N5 packaging: committed derived copy under server/content/maps.

Byte-stability contract: canonical content/maps, Godot-derived
game/content/maps and server-derived server/content/maps must be raw-byte
identical, carry `text: unset` git attributes (no line-ending rewriting), and
hash to the pinned golden. The built container's check is the raw-byte hash
probe documented in docs/DEPLOY_HETZNER.md (no git inside the image).
"""

from __future__ import annotations

import hashlib
import json
import shutil
import subprocess
from pathlib import Path

import pytest

from app.domain.map_content_loader import load_world_map, resolve_content_root

SERVER_ROOT = Path(__file__).resolve().parent.parent
REPO_ROOT = SERVER_ROOT.parent

CANONICAL_ROOT = REPO_ROOT / "content" / "maps"
GODOT_ROOT = REPO_ROOT / "game" / "content" / "maps"
SERVER_CONTENT_ROOT = SERVER_ROOT / "content" / "maps"

REFERENCE_REL = "reference/handdrawn_test_map_full_01.json"
REFERENCE_HASH = "16cc82c3392c66f1e47273e7da94cf8a804ae9885a051fc81c4b0a9a4261d8c6"
REFERENCE_MAP_ID = "handdrawn_test_map_full_01"


def _map_files(root: Path) -> dict[str, bytes]:
    return {
        path.relative_to(root).as_posix(): path.read_bytes()
        for path in sorted(root.rglob("*.json"))
        if path.name != "manifest.json"
    }


def test_three_copies_are_byte_identical() -> None:
    canonical = _map_files(CANONICAL_ROOT)
    assert canonical, "expected canonical map content"
    assert _map_files(GODOT_ROOT) == canonical
    assert _map_files(SERVER_CONTENT_ROOT) == canonical


def test_reference_hash_matches_golden_in_all_copies() -> None:
    for root in (CANONICAL_ROOT, GODOT_ROOT, SERVER_CONTENT_ROOT):
        raw = (root / REFERENCE_REL).read_bytes()
        assert hashlib.sha256(raw).hexdigest() == REFERENCE_HASH, root


def test_manifests_match_recomputed_hashes() -> None:
    canonical = _map_files(CANONICAL_ROOT)
    for manifest_path in (GODOT_ROOT / "manifest.json", SERVER_CONTENT_ROOT / "manifest.json"):
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        entries = {entry["path"]: entry for entry in manifest["maps"]}
        assert set(entries) == set(canonical)
        for rel, raw in canonical.items():
            assert entries[rel]["content_hash"] == hashlib.sha256(raw).hexdigest()


def test_git_text_attribute_unset_for_all_copies() -> None:
    if shutil.which("git") is None:
        pytest.skip("git not available; byte-stability covered by hash assertions")
    files = [
        (REPO_ROOT / "content" / "maps" / REFERENCE_REL).relative_to(REPO_ROOT),
        (GODOT_ROOT / REFERENCE_REL).relative_to(REPO_ROOT),
        (GODOT_ROOT / "manifest.json").relative_to(REPO_ROOT),
        (SERVER_CONTENT_ROOT / REFERENCE_REL).relative_to(REPO_ROOT),
        (SERVER_CONTENT_ROOT / "manifest.json").relative_to(REPO_ROOT),
    ]
    result = subprocess.run(
        ["git", "check-attr", "text", "--"] + [f.as_posix() for f in files],
        cwd=str(REPO_ROOT),
        capture_output=True,
        text=True,
        check=True,
    )
    lines = [line for line in result.stdout.splitlines() if line.strip()]
    assert len(lines) == len(files)
    for line in lines:
        assert line.endswith(": text: unset"), line


def test_loader_resolves_packaged_server_content_root(monkeypatch) -> None:
    monkeypatch.delenv("EMPIRE_MAP_CONTENT_DIR", raising=False)
    assert resolve_content_root() == SERVER_CONTENT_ROOT
    world_map = load_world_map(REFERENCE_MAP_ID)
    assert world_map.identity.content_hash == REFERENCE_HASH
    assert world_map.tile_count() == 168
