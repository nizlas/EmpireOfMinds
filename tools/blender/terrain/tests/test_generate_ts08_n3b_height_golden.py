"""Tests for the N3b test-only binary height golden generator.

The golden is little-endian float64 Godot-Y heights in N3a node-index order,
derived from the N2 dataset. N2 remains the sole comparison golden.
"""

from __future__ import annotations

import json
import struct
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[4]
SCRIPT_DIR = REPO_ROOT / "tools" / "blender" / "terrain"
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import generate_ts08_n3b_height_golden as gen  # noqa: E402


@pytest.fixture(scope="module")
def n2_dataset() -> dict:
    n2, _content_hash = gen.load_n2_dataset(REPO_ROOT)
    return n2


@pytest.fixture(scope="module")
def heights(n2_dataset: dict) -> list[float]:
    return gen.heights_from_n2(n2_dataset)


def test_committed_golden_matches_n2() -> None:
    gen.check_golden(REPO_ROOT)


def test_binary_encoding_is_little_endian_float64(heights: list[float]) -> None:
    committed = (REPO_ROOT / gen.BIN_REL).read_bytes()
    assert len(committed) == len(heights) * 8
    decoded = struct.unpack(f"<{len(heights)}d", committed)
    assert list(decoded) == heights


def test_sidecar_contract(heights: list[float]) -> None:
    sidecar = json.loads((REPO_ROOT / gen.SIDECAR_REL).read_text(encoding="utf-8"))
    assert sidecar["schema_version"] == gen.GOLDEN_SCHEMA_VERSION
    assert sidecar["golden_id"] == gen.GOLDEN_ID
    assert sidecar["node_count"] == len(heights) == 74129
    assert sidecar["source_n2_content_hash"] == gen.COMMITTED_DATASET_CONTENT_HASH
    assert sidecar["binary_sha256"] == gen.sha256_hex_lower((REPO_ROOT / gen.BIN_REL).read_bytes())
    assert "test-only" in sidecar["purpose"]
    assert "not a persisted lattice cache" in sidecar["purpose"]
    assert "little-endian" in sidecar["encoding"]


def test_single_height_mutation_changes_bytes_and_hash(heights: list[float]) -> None:
    mutated = list(heights)
    mutated[0] += 1e-9
    original_bytes = gen.golden_bytes(heights)
    mutated_bytes = gen.golden_bytes(mutated)
    assert original_bytes != mutated_bytes
    assert gen.sha256_hex_lower(original_bytes) != gen.sha256_hex_lower(mutated_bytes)


def test_tampered_binary_fails_check(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    # Copy fixture tree into a temp repo layout, flip one byte, expect failure.
    fixture_dir = tmp_path / gen.FIXTURE_DIR
    fixture_dir.mkdir(parents=True)
    original = (REPO_ROOT / gen.BIN_REL).read_bytes()
    tampered = bytearray(original)
    tampered[8] ^= 0x01
    (tmp_path / gen.BIN_REL).write_bytes(bytes(tampered))
    (tmp_path / gen.SIDECAR_REL).write_text(
        (REPO_ROOT / gen.SIDECAR_REL).read_text(encoding="utf-8"), encoding="utf-8"
    )
    # Point only fixture reads at the temp tree; N2 still loads from the repo.
    real_load = gen.load_n2_dataset
    monkeypatch.setattr(gen, "load_n2_dataset", lambda _root: real_load(REPO_ROOT))
    with pytest.raises(RuntimeError, match="drift"):
        gen.check_golden(tmp_path)
