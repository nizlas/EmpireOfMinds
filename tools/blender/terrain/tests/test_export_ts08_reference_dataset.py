from __future__ import annotations

import copy
import hashlib
import json
import subprocess
import sys
import tempfile
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[4]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tools.blender.terrain.export_ts08_reference_dataset import (  # noqa: E402
    ACCEPTED_STAGE2_Z_MAX,
    ACCEPTED_STAGE2_Z_MIN,
    COMMITTED_DATASET_CONTENT_HASH,
    DATASET_FILENAME,
    DATASET_ID,
    DEST_ROOT,
    EXPECTED_DUPLICATED_CLIFF_LINE_NODES,
    REFERENCE_MAP_HASH,
    STAGE2_HEIGHT_RANGE_ABS_TOL,
    audit_reference_dataset,
    build_reference_dataset,
    canonical_dataset_bytes,
    finalize_dataset_payload,
    finalized_dataset_file_bytes,
    regenerate_finalized_file_bytes,
)
from tools.blender.terrain.eom_terrain_ts08_cut_lattice import (  # noqa: E402
    EXPECTED_CENTER_PIN_COUNT,
    EXPECTED_CLIFF_EDGE_COUNT,
    EXPECTED_CUT_TOPOLOGICAL_NODE_COUNT,
    EXPECTED_HEX_COUNT,
    EXPECTED_TRIANGLE_COUNT,
    MAP_JSON_ID,
)

EXPORT_SCRIPT = REPO_ROOT / "tools/blender/terrain/export_ts08_reference_dataset.py"
DATASET_PATH = REPO_ROOT / DEST_ROOT / DATASET_FILENAME
REFERENCE_MAP = REPO_ROOT / "content/maps/reference/handdrawn_test_map_full_01.json"


def _regenerate_canonical_bytes() -> bytes:
    payload = finalize_dataset_payload(build_reference_dataset(REPO_ROOT))
    return canonical_dataset_bytes(payload)


@pytest.fixture(scope="module")
def canonical_bytes_once() -> bytes:
    return _regenerate_canonical_bytes()


def test_two_byte_identical_regenerations(canonical_bytes_once: bytes) -> None:
    second = _regenerate_canonical_bytes()
    assert canonical_bytes_once == second
    assert hashlib.sha256(canonical_bytes_once).hexdigest() == COMMITTED_DATASET_CONTENT_HASH


def test_committed_file_byte_identical_to_regeneration() -> None:
    assert DATASET_PATH.read_bytes() == regenerate_finalized_file_bytes(REPO_ROOT)


def test_source_map_identity(canonical_bytes_once: bytes) -> None:
    payload = json.loads(canonical_bytes_once.decode("utf-8"))
    identity = payload["source_map_identity"]
    assert identity["map_id"] == MAP_JSON_ID
    assert identity["content_hash"] == REFERENCE_MAP_HASH
    assert identity["schema_version"] == 1
    assert REFERENCE_MAP.read_bytes()
    assert hashlib.sha256(REFERENCE_MAP.read_bytes()).hexdigest() == REFERENCE_MAP_HASH


def test_ts08_golden_counts(canonical_bytes_once: bytes) -> None:
    payload = json.loads(canonical_bytes_once.decode("utf-8"))
    assert payload["dataset_id"] == DATASET_ID
    assert payload["node_count"] == EXPECTED_CUT_TOPOLOGICAL_NODE_COUNT
    assert payload["triangle_count"] == EXPECTED_TRIANGLE_COUNT
    assert len(payload["center_pins"]) == EXPECTED_CENTER_PIN_COUNT
    assert len(payload["cliff_edges"]) == EXPECTED_CLIFF_EDGE_COUNT

    topology = payload["topology_summary"]
    assert topology["hex_count"] == EXPECTED_HEX_COUNT
    assert topology["adjacency_cross_cliff_violations"] == 0
    assert topology["duplicated_cliff_line_nodes"] == EXPECTED_DUPLICATED_CLIFF_LINE_NODES

    solver = payload["solver_summary"]
    assert solver["converged"] is True
    assert solver["pinned_center_count"] == EXPECTED_CENTER_PIN_COUNT


def test_ts08_stage2_height_range_goldens(canonical_bytes_once: bytes) -> None:
    payload = json.loads(canonical_bytes_once.decode("utf-8"))
    solver = payload["solver_summary"]
    assert abs(solver["z_min_blender"] - ACCEPTED_STAGE2_Z_MIN) <= STAGE2_HEIGHT_RANGE_ABS_TOL
    assert abs(solver["z_max_blender"] - ACCEPTED_STAGE2_Z_MAX) <= STAGE2_HEIGHT_RANGE_ABS_TOL

    godot_y = [pos[1] for pos in payload["nodes"]["positions_xyz"]]
    assert abs(min(godot_y) - ACCEPTED_STAGE2_Z_MIN) <= STAGE2_HEIGHT_RANGE_ABS_TOL
    assert abs(max(godot_y) - ACCEPTED_STAGE2_Z_MAX) <= STAGE2_HEIGHT_RANGE_ABS_TOL


def test_seam_duplication_preserved(canonical_bytes_once: bytes) -> None:
    payload = json.loads(canonical_bytes_once.decode("utf-8"))
    seam = payload["seam_duplication"]
    assert seam["duplicated_cliff_line_nodes"] == EXPECTED_DUPLICATED_CLIFF_LINE_NODES
    assert seam["duplicated_pos_key_instances"] > 0


def test_committed_dataset_passes_audit() -> None:
    assert DATASET_PATH.is_file(), f"missing committed dataset: {DATASET_PATH}"
    report = audit_reference_dataset(DATASET_PATH, repo_root=REPO_ROOT)
    assert report.passed, report.failures


def test_export_cli_writes_byte_identical_file(canonical_bytes_once: bytes) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / DATASET_FILENAME
        result = subprocess.run(
            [
                sys.executable,
                str(EXPORT_SCRIPT),
                "export",
                "--repo-root",
                str(REPO_ROOT),
                "--output",
                str(out),
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        assert result.returncode == 0, result.stderr
        written_bytes = out.read_bytes()
        expected_bytes = regenerate_finalized_file_bytes(REPO_ROOT)
        assert written_bytes == expected_bytes
        written_payload = json.loads(written_bytes.decode("utf-8"))
        assert canonical_dataset_bytes(written_payload) == canonical_bytes_once
        assert written_payload["content_hash"] == COMMITTED_DATASET_CONTENT_HASH


def test_audit_fails_when_vertex_tampered_with_recomputed_hash() -> None:
    original = json.loads(DATASET_PATH.read_bytes().decode("utf-8"))
    tampered_body = copy.deepcopy({key: value for key, value in original.items() if key != "content_hash"})
    tampered_body["nodes"]["positions_xyz"][0][1] += 0.001
    tampered_bytes = finalized_dataset_file_bytes(tampered_body)
    tampered_payload = json.loads(tampered_bytes.decode("utf-8"))
    assert tampered_payload["content_hash"] == hashlib.sha256(
        canonical_dataset_bytes(tampered_payload)
    ).hexdigest()

    with tempfile.TemporaryDirectory() as tmp:
        tampered_path = Path(tmp) / DATASET_FILENAME
        tampered_path.write_bytes(tampered_bytes)
        report = audit_reference_dataset(tampered_path, repo_root=REPO_ROOT)
        assert not report.passed
        assert any("bytes differ" in failure for failure in report.failures)


def test_check_cli_ok_on_committed_dataset() -> None:
    result = subprocess.run(
        [
            sys.executable,
            str(EXPORT_SCRIPT),
            "check",
            "--repo-root",
            str(REPO_ROOT),
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    assert "CONTENT_HASH=" in result.stdout
