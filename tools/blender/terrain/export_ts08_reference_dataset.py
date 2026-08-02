#!/usr/bin/env python3
"""Export deterministic TS-08 Stage-2 reference dataset (N2, bpy-free)."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parents[2]
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from eom_map_content import load_reference_logical_map, reference_map_path, resolve_repo_root  # noqa: E402
from eom_terrain_math_core import (  # noqa: E402
    DEFAULT_HEX_RADIUS,
    DEFAULT_SURFACE_SUBDIVISIONS,
    axial_to_world_xy,
    build_terrain_model,
    parse_terrain_map_ir,
    sector_barycentric_xy,
)
from eom_terrain_ts08_cut_lattice import (  # noqa: E402
    EXPECTED_CENTER_PIN_COUNT,
    EXPECTED_CLIFF_EDGE_COUNT,
    EXPECTED_CUT_TOPOLOGICAL_NODE_COUNT,
    EXPECTED_HEX_COUNT,
    EXPECTED_TRIANGLE_COUNT,
    MAP_ID,
    MAP_JSON_ID,
    build_cliff_neighbor_pairs,
    build_cut_lattice_for_model,
    report_to_dict,
    run_cut_lattice_topology_audit,
)
from eom_terrain_ts08_stage2_cut_thin_plate_cg import (  # noqa: E402
    PROTOTYPE_ID,
    solve_cut_domain_thin_plate_cg,
)

DATASET_SCHEMA_VERSION = 1
DATASET_ID = "handdrawn_test_map_full_01_ts08_stage2_reference_v1"
DATASET_FILENAME = f"{DATASET_ID}.json"
DEST_ROOT = Path("content") / "terrain" / "reference"

REFERENCE_MAP_HASH = "16cc82c3392c66f1e47273e7da94cf8a804ae9885a051fc81c4b0a9a4261d8c6"
EXPECTED_DUPLICATED_CLIFF_LINE_NODES = 861
CENTER_HEIGHT_TOL = 1e-6
SMOOTH_EDGE_SPLIT_TOL = 1e-6


class BaselineGeometryShim:
    """Minimal baseline geometry surface (no bpy) for cut-lattice construction."""

    @staticmethod
    def axial_to_world_xy(q: int, r: int, radius: float) -> tuple[float, float]:
        return axial_to_world_xy(q, r, radius)

    @staticmethod
    def sector_barycentric_xy(sector: int, si: int, sj: int, subdiv: int) -> tuple[float, float]:
        lx, ly, _, _ = sector_barycentric_xy(
            sector, si, sj, subdiv, radius=DEFAULT_HEX_RADIUS
        )
        return lx, ly


class DatasetValidationError(RuntimeError):
    """Controlled failure for reference-dataset validation."""


def sha256_hex_lower(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def _blender_xyz_to_godot(x_b: float, y_b: float, z_b: float) -> tuple[float, float, float]:
    return (x_b, z_b, -y_b)


def _orient_upward_triangle_y_up(
    vertices: list[tuple[float, float, float]],
    a: int,
    b: int,
    c: int,
) -> tuple[int, int, int]:
    ax, ay, az = vertices[a]
    bx, by, bz = vertices[b]
    cx, cy, cz = vertices[c]
    ab = (bx - ax, by - ay, bz - az)
    ac = (cx - ax, cy - ay, cz - az)
    ny = ab[2] * ac[0] - ab[0] * ac[2]
    if abs(ny) < 1e-12:
        raise RuntimeError(f"Degenerate top triangle: {(a, b, c)}")
    if ny < 0.0:
        return (a, c, b)
    return (a, b, c)


def _encode_node_key(key: Any) -> list[Any]:
    if not isinstance(key, tuple):
        return [key]
    encoded: list[Any] = []
    for part in key:
        if isinstance(part, tuple) and len(part) == 2:
            encoded.append([part[0], part[1]])
        else:
            encoded.append(part)
    return encoded


def _json_float(value: float) -> float:
    if not math.isfinite(value):
        raise DatasetValidationError(f"Non-finite float value: {value!r}")
    return float(f"{value:.12g}")


def _source_map_identity(repo_root: Path) -> dict[str, Any]:
    source_path = reference_map_path(repo_root=repo_root)
    raw = source_path.read_bytes()
    content_hash = sha256_hex_lower(raw)
    if content_hash != REFERENCE_MAP_HASH:
        raise DatasetValidationError(
            f"Unexpected reference map hash {content_hash} (expected {REFERENCE_MAP_HASH})"
        )
    return {
        "map_id": MAP_JSON_ID,
        "schema_version": 1,
        "content_hash": content_hash,
        "source_path": source_path.relative_to(repo_root).as_posix(),
    }


def build_reference_dataset(repo_root: Path) -> dict[str, Any]:
    logical_map = load_reference_logical_map(repo_root=repo_root)
    terrain_map = parse_terrain_map_ir(logical_map)
    if terrain_map.map_id != MAP_JSON_ID:
        raise DatasetValidationError(
            f"Unexpected map id {terrain_map.map_id!r} (expected {MAP_JSON_ID})"
        )

    model = build_terrain_model(terrain_map)
    baseline = BaselineGeometryShim()
    topology_report = run_cut_lattice_topology_audit(model, baseline, map_id=MAP_ID)
    if not topology_report.passed:
        raise DatasetValidationError(
            f"Cut-lattice topology audit failed: {topology_report.failures}"
        )

    lattice = build_cut_lattice_for_model(model, baseline)
    heights, solve_report = solve_cut_domain_thin_plate_cg(lattice, model)

    godot_vertices: list[tuple[float, float, float]] = []
    for index, (x_b, y_b) in enumerate(lattice.node_xy):
        z_b = float(heights[index])
        godot_vertices.append(_blender_xyz_to_godot(x_b, y_b, z_b))

    top_triangles: list[list[int]] = []
    face_keys: set[tuple[int, int, int]] = set()
    for v0, v1, v2 in lattice.triangles:
        a, b, c = _orient_upward_triangle_y_up(godot_vertices, v0, v1, v2)
        key = tuple(sorted((a, b, c)))
        if key in face_keys:
            continue
        face_keys.add(key)
        top_triangles.append([a, b, c])

    cliff_pairs = build_cliff_neighbor_pairs(model)
    cliff_edges = sorted(
        [
            {"tile_a": [tile_a[0], tile_a[1]], "tile_b": [tile_b[0], tile_b[1]]}
            for tile_a, tile_b in sorted(
                (tuple(sorted(pair)) for pair in cliff_pairs),
                key=lambda pair: (pair[0], pair[1]),
            )
        ],
        key=lambda item: (item["tile_a"], item["tile_b"]),
    )

    center_pins = []
    for node_index in sorted(lattice.pin_hex_by_node.keys()):
        q, r = lattice.pin_hex_by_node[node_index]
        x_g, y_g, z_g = godot_vertices[node_index]
        target_y = _json_float(float(lattice.pinned[node_index]))
        center_pins.append(
            {
                "node_index": node_index,
                "q": q,
                "r": r,
                "world_position": [_json_float(x_g), _json_float(y_g), _json_float(z_g)],
                "pinned_world_y": target_y,
            }
        )

    pos_key_counts = Counter(lattice.node_pos_keys)
    duplicated_pos_keys = sum(count - 1 for count in pos_key_counts.values() if count > 1)

    payload: dict[str, Any] = {
        "schema_version": DATASET_SCHEMA_VERSION,
        "dataset_id": DATASET_ID,
        "origin": "reference",
        "provenance": (
            "Deterministic TS-08 Stage-2 cut-domain thin-plate CG reference dataset "
            "for Godot parity (slice N2)."
        ),
        "source_map_identity": _source_map_identity(repo_root),
        "ts08": {
            "prototype_id": PROTOTYPE_ID,
            "stage": 2,
            "hex_radius": DEFAULT_HEX_RADIUS,
            "surface_subdivisions": DEFAULT_SURFACE_SUBDIVISIONS,
            "coordinate_frame": "godot_y_up",
            "axis_conversion": "(x_g, y_g, z_g) = (x_b, z_b, -y_b)",
        },
        "topology_summary": report_to_dict(topology_report),
        "solver_summary": {
            "node_count": solve_report.node_count,
            "triangle_count": solve_report.triangle_count,
            "pinned_center_count": solve_report.pinned_center_count,
            "connected_component_count": solve_report.connected_component_count,
            "deficient_component_count": solve_report.deficient_component_count,
            "cg_iterations": solve_report.cg_iterations,
            "cg_final_abs_residual": _json_float(solve_report.cg_final_abs_residual),
            "cg_final_rel_residual": _json_float(solve_report.cg_final_rel_residual),
            "energy_initial": _json_float(solve_report.energy_initial),
            "energy_final": _json_float(solve_report.energy_final),
            "z_min_blender": _json_float(solve_report.z_min),
            "z_max_blender": _json_float(solve_report.z_max),
            "max_center_interpolation_error": _json_float(
                solve_report.max_center_interpolation_error
            ),
            "max_tent_pole_delta": _json_float(solve_report.max_tent_pole_delta),
            "converged": solve_report.converged,
        },
        "seam_duplication": {
            "duplicated_cliff_line_nodes": topology_report.duplicated_cliff_line_nodes,
            "duplicated_pos_key_instances": duplicated_pos_keys,
        },
        "node_count": lattice.node_count,
        "triangle_count": len(top_triangles),
        "nodes": {
            "positions_xyz": [
                [_json_float(x), _json_float(y), _json_float(z)] for x, y, z in godot_vertices
            ],
            "sheet_ids": list(lattice.node_sheet_ids),
            "node_keys": [_encode_node_key(key) for key in lattice.node_keys],
            "pos_keys": [[pk[0], pk[1]] for pk in lattice.node_pos_keys],
        },
        "center_pins": center_pins,
        "triangles": top_triangles,
        "cliff_edges": cliff_edges,
    }
    return payload


def canonical_dataset_bytes(payload: dict[str, Any]) -> bytes:
    body = {key: value for key, value in payload.items() if key != "content_hash"}
    text = json.dumps(body, indent=2, sort_keys=True, ensure_ascii=False) + "\n"
    return text.encode("utf-8")


def finalize_dataset_payload(payload: dict[str, Any]) -> dict[str, Any]:
    finalized = dict(payload)
    finalized.pop("content_hash", None)
    finalized["content_hash"] = sha256_hex_lower(canonical_dataset_bytes(finalized))
    return finalized


def export_reference_dataset(repo_root: Path, dest_path: Path | None = None) -> tuple[Path, str]:
    payload = finalize_dataset_payload(build_reference_dataset(repo_root))
    if dest_path is None:
        dest_path = repo_root / DEST_ROOT / DATASET_FILENAME
    dest_path.parent.mkdir(parents=True, exist_ok=True)
    dest_path.write_bytes(
        json.dumps(payload, indent=2, sort_keys=True, ensure_ascii=False).encode("utf-8")
        + b"\n"
    )
    return dest_path, payload["content_hash"]


@dataclass
class DatasetAuditReport:
    passed: bool
    failures: list[str]
    warnings: list[str]
    content_hash: str


def audit_reference_dataset(path: Path, *, repo_root: Path | None = None) -> DatasetAuditReport:
    repo_root = repo_root or resolve_repo_root(extra_starts=(SCRIPT_DIR,))
    raw = path.read_bytes()
    try:
        payload = json.loads(raw.decode("utf-8"))
    except json.JSONDecodeError as exc:
        raise DatasetValidationError(f"Invalid JSON in {path}: {exc}") from exc

    failures: list[str] = []
    warnings: list[str] = []

    stored_hash = payload.get("content_hash")
    body_hash = sha256_hex_lower(canonical_dataset_bytes(payload))
    if stored_hash != body_hash:
        failures.append(f"content_hash mismatch: stored={stored_hash!r} computed={body_hash!r}")

    identity = payload.get("source_map_identity") or {}
    if identity.get("map_id") != MAP_JSON_ID:
        failures.append(f"unexpected map_id: {identity.get('map_id')!r}")
    if identity.get("content_hash") != REFERENCE_MAP_HASH:
        failures.append(f"unexpected source map hash: {identity.get('content_hash')!r}")

    if payload.get("node_count") != EXPECTED_CUT_TOPOLOGICAL_NODE_COUNT:
        failures.append(
            f"node_count {payload.get('node_count')} != {EXPECTED_CUT_TOPOLOGICAL_NODE_COUNT}"
        )
    if payload.get("triangle_count") != EXPECTED_TRIANGLE_COUNT:
        failures.append(
            f"triangle_count {payload.get('triangle_count')} != {EXPECTED_TRIANGLE_COUNT}"
        )

    seam = payload.get("seam_duplication") or {}
    if seam.get("duplicated_cliff_line_nodes", 0) <= 0:
        failures.append("expected duplicated cliff-line seam nodes > 0")
    if seam.get("duplicated_cliff_line_nodes") != EXPECTED_DUPLICATED_CLIFF_LINE_NODES:
        failures.append(
            "duplicated_cliff_line_nodes "
            f"{seam.get('duplicated_cliff_line_nodes')} != {EXPECTED_DUPLICATED_CLIFF_LINE_NODES}"
        )

    topology = payload.get("topology_summary") or {}
    if topology.get("adjacency_cross_cliff_violations", -1) != 0:
        failures.append(
            "adjacency_cross_cliff_violations "
            f"{topology.get('adjacency_cross_cliff_violations')} != 0"
        )
    if topology.get("hex_count") != EXPECTED_HEX_COUNT:
        failures.append(f"hex_count {topology.get('hex_count')} != {EXPECTED_HEX_COUNT}")
    edge_summary = topology.get("edge_summary") or {}
    if edge_summary.get("cliff_edges") != EXPECTED_CLIFF_EDGE_COUNT:
        failures.append(
            f"cliff_edges {edge_summary.get('cliff_edges')} != {EXPECTED_CLIFF_EDGE_COUNT}"
        )

    solver = payload.get("solver_summary") or {}
    if not solver.get("converged"):
        failures.append("solver did not converge")
    if solver.get("pinned_center_count") != EXPECTED_CENTER_PIN_COUNT:
        failures.append(
            f"pinned_center_count {solver.get('pinned_center_count')} "
            f"!= {EXPECTED_CENTER_PIN_COUNT}"
        )

    nodes = payload.get("nodes") or {}
    positions = nodes.get("positions_xyz") or []
    triangles = payload.get("triangles") or []
    if len(positions) != payload.get("node_count"):
        failures.append("positions_xyz length does not match node_count")
    if len(triangles) != payload.get("triangle_count"):
        failures.append("triangles length does not match triangle_count")

    # Smooth-edge split: mid-edge samples on delta==1 edges must share one pos_key per tile side.
    fresh = build_reference_dataset(repo_root)
    fresh_lattice = build_cut_lattice_for_model(
        build_terrain_model(load_reference_logical_map(repo_root=repo_root)),
        BaselineGeometryShim(),
    )
    pos_to_nodes: dict[tuple[float, float], list[int]] = {}
    for index, pk in enumerate(fresh_lattice.node_pos_keys):
        pos_to_nodes.setdefault((pk[0], pk[1]), []).append(index)

    from eom_terrain_math_core import pos_key as pk_fn
    from eom_terrain_ts08_cut_lattice import shared_hex_edge_endpoints

    model = build_terrain_model(load_reference_logical_map(repo_root=repo_root))
    split_violations = 0
    max_split_mismatch = 0.0
    index_by_pos_tile = fresh_lattice.tile_pos_to_node
    for edge in model.smooth_edges:
        if edge.delta > 1:
            continue
        p0, p1 = shared_hex_edge_endpoints(edge.tile_a, edge.tile_b, radius=DEFAULT_HEX_RADIUS)
        mid_x = (p0[0] + p1[0]) * 0.5
        mid_y = (p0[1] + p1[1]) * 0.5
        pk = pk_fn(mid_x, mid_y)
        node_a = index_by_pos_tile.get((pk, edge.tile_a))
        node_b = index_by_pos_tile.get((pk, edge.tile_b))
        if node_a is None or node_b is None:
            continue
        if node_a != node_b:
            split_violations += 1
            ya = positions[node_a][1]
            yb = positions[node_b][1]
            max_split_mismatch = max(max_split_mismatch, abs(ya - yb))

    if split_violations != 0:
        failures.append(
            f"smooth-edge split violations={split_violations} max_mismatch={max_split_mismatch}"
        )
    elif max_split_mismatch > SMOOTH_EDGE_SPLIT_TOL:
        failures.append(f"smooth-edge height mismatch {max_split_mismatch} > {SMOOTH_EDGE_SPLIT_TOL}")

    for pin in payload.get("center_pins") or []:
        node_index = pin["node_index"]
        y_actual = positions[node_index][1]
        y_target = pin["pinned_world_y"]
        if abs(y_actual - y_target) > CENTER_HEIGHT_TOL:
            failures.append(
                f"center pin ({pin['q']},{pin['r']}) error "
                f"{abs(y_actual - y_target)} > {CENTER_HEIGHT_TOL}"
            )
            break

    if len(payload.get("cliff_edges") or []) != EXPECTED_CLIFF_EDGE_COUNT:
        failures.append(
            f"cliff_edges list length {len(payload.get('cliff_edges') or [])} "
            f"!= {EXPECTED_CLIFF_EDGE_COUNT}"
        )

    return DatasetAuditReport(
        passed=not failures,
        failures=failures,
        warnings=warnings,
        content_hash=str(stored_hash or body_hash),
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Export or audit TS-08 Stage-2 reference terrain dataset (N2)"
    )
    parser.add_argument(
        "command",
        choices=("export", "check"),
        help="export: write dataset; check: validate existing dataset",
    )
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=None,
        help="Repository root override (defaults to script location)",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=None,
        help="Output path for export (defaults to content/terrain/reference/)",
    )
    args = parser.parse_args(argv)
    repo_root = args.repo_root.resolve() if args.repo_root else REPO_ROOT

    try:
        if args.command == "export":
            dest_path, content_hash = export_reference_dataset(repo_root, args.output)
            print(f"Exported reference dataset to {dest_path}")
            print(f"CONTENT_HASH={content_hash}")
            return 0

        dataset_path = args.output or (repo_root / DEST_ROOT / DATASET_FILENAME)
        report = audit_reference_dataset(dataset_path, repo_root=repo_root)
        if report.failures:
            for failure in report.failures:
                print(f"FAIL: {failure}", file=sys.stderr)
            return 1
        print(f"OK: reference dataset {dataset_path} passed audit")
        print(f"CONTENT_HASH={report.content_hash}")
        return 0
    except DatasetValidationError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
