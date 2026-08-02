"""Tests for the N3a topology parity digest manifest generator.

Verifies that the committed digest manifest matches a regeneration from the
N2 golden, and that a one-element mutation in each protected data category
changes the relevant stream digest (and only that digest).
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

SCRIPT_DIR = Path(__file__).resolve().parent.parent
REPO_ROOT = SCRIPT_DIR.parents[2]
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import generate_ts08_n3a_parity_manifest as gen  # noqa: E402


@pytest.fixture(scope="module")
def n2_dataset() -> dict:
    n2, _content_hash = gen.load_n2_dataset(REPO_ROOT)
    return n2


@pytest.fixture(scope="module")
def baseline_digests(n2_dataset: dict) -> dict[str, str]:
    return gen.stream_digests(n2_dataset)


def _clone_for_mutation(n2: dict) -> dict:
    """Shallow clone deep enough that single-element mutations don't leak."""
    clone = dict(n2)
    clone["nodes"] = {
        name: [list(entry) if isinstance(entry, list) else entry for entry in values]
        for name, values in n2["nodes"].items()
    }
    clone["triangles"] = [list(tri) for tri in n2["triangles"]]
    clone["center_pins"] = [dict(pin) for pin in n2["center_pins"]]
    return clone


def _assert_only_changed(
    baseline: dict[str, str], mutated: dict[str, str], changed_key: str
) -> None:
    for key in baseline:
        if key == changed_key:
            assert mutated[key] != baseline[key], f"{key} should change"
        else:
            assert mutated[key] == baseline[key], f"{key} should be unaffected"


def test_committed_manifest_matches_n2() -> None:
    gen.check_manifest(REPO_ROOT)


def test_manifest_stores_no_raw_topology_arrays() -> None:
    import json

    manifest = json.loads((REPO_ROOT / gen.MANIFEST_REL).read_text(encoding="utf-8"))
    assert set(manifest) == {
        "schema_version",
        "manifest_id",
        "source_n2_dataset_id",
        "source_n2_content_hash",
        "canonical_encoding",
        "counts",
        "digests",
    }
    assert (REPO_ROOT / gen.MANIFEST_REL).stat().st_size < 16_384


def test_mutation_node_identity_changes_digest(
    n2_dataset: dict, baseline_digests: dict[str, str]
) -> None:
    mutated = _clone_for_mutation(n2_dataset)
    key = [
        list(part) if isinstance(part, list) else part
        for part in mutated["nodes"]["node_keys"][0]
    ]
    pk_slot = 1 if isinstance(key[0], str) else 0
    key[pk_slot][0] = float(key[pk_slot][0]) + 0.001
    mutated["nodes"]["node_keys"][0] = key
    _assert_only_changed(
        baseline_digests, gen.stream_digests(mutated), "node_identities_sha256"
    )


def test_mutation_pos_key_changes_digest(
    n2_dataset: dict, baseline_digests: dict[str, str]
) -> None:
    mutated = _clone_for_mutation(n2_dataset)
    mutated["nodes"]["pos_keys"][0][0] = float(mutated["nodes"]["pos_keys"][0][0]) + 0.001
    _assert_only_changed(baseline_digests, gen.stream_digests(mutated), "pos_keys_sha256")


def test_mutation_sheet_id_changes_digest(
    n2_dataset: dict, baseline_digests: dict[str, str]
) -> None:
    mutated = _clone_for_mutation(n2_dataset)
    mutated["nodes"]["sheet_ids"][0] = int(mutated["nodes"]["sheet_ids"][0]) + 1
    _assert_only_changed(baseline_digests, gen.stream_digests(mutated), "sheet_ids_sha256")


def test_mutation_godot_position_changes_digest(
    n2_dataset: dict, baseline_digests: dict[str, str]
) -> None:
    mutated = _clone_for_mutation(n2_dataset)
    mutated["nodes"]["positions_xyz"][0][0] = (
        float(mutated["nodes"]["positions_xyz"][0][0]) + 0.001
    )
    _assert_only_changed(baseline_digests, gen.stream_digests(mutated), "godot_xz_sha256")


def test_mutation_triangle_changes_digest(
    n2_dataset: dict, baseline_digests: dict[str, str]
) -> None:
    mutated = _clone_for_mutation(n2_dataset)
    mutated["triangles"][0][0] = int(mutated["triangles"][0][0]) + 1
    _assert_only_changed(baseline_digests, gen.stream_digests(mutated), "triangles_sha256")


def test_mutation_center_pin_changes_digest(
    n2_dataset: dict, baseline_digests: dict[str, str]
) -> None:
    mutated = _clone_for_mutation(n2_dataset)
    mutated["center_pins"][0]["pinned_world_y"] = (
        float(mutated["center_pins"][0]["pinned_world_y"]) + 0.001
    )
    _assert_only_changed(baseline_digests, gen.stream_digests(mutated), "center_pins_sha256")
