# Empire of Minds — read-only audit for TS-08 Stage 1 no-cut thin-plate CG output.
# Run: blender --background --python tools/blender/terrain/audit_ts08_stage1_no_cut_thin_plate_cg_blend.py
#
# STRICTLY READ-ONLY: never saves or modifies any blend file.

from __future__ import annotations

import importlib.util
import sys
from collections import Counter
from pathlib import Path
from typing import Any

import bmesh
import bpy

TERRAIN_OBJECT_NAME = "EOM_Terrain_TerrainMapFull01"
OUTPUT_BLEND_FILENAME = (
    "terrain_handdrawn_test_map_full_01_ts08_stage1_no_cut_thin_plate_cg.blend"
)
TS03_BASELINE_FILENAME = (
    "terrain_handdrawn_test_map_full_01_ts03_global_continuous_baseline.blend"
)
MAP_ID = "terrain_handdrawn_test_map_full_01"
CENTER_HEIGHT_TOL = 1e-4
Z_MIN_GATE = -0.90
Z_MAX_GATE = 2.60
Z_TS07C_FAIL_MIN = -2.84
Z_TS07C_FAIL_MAX = 4.85
_FULL01_MODULE_NAME = "generate_terrain_terrainmap_handdrawn_full_01.py"


def _resolve_blend_path(filename: str) -> Path:
    starts: list[Path] = []
    try:
        script_path = bpy.path.abspath(__file__)
        if script_path:
            starts.append(Path(script_path).resolve().parent)
    except (NameError, TypeError):
        pass
    try:
        starts.append(Path(__file__).resolve().parent)
    except NameError:
        pass

    seen: set[str] = set()
    for start in starts:
        key = str(start.resolve())
        if key in seen:
            continue
        seen.add(key)
        for root in (start, *start.parents):
            candidate = (
                root
                / "game"
                / "assets"
                / "prototype"
                / "3d"
                / "terrain"
                / "prototype_3d_terrain"
                / "generated"
                / filename
            )
            if candidate.is_file():
                return candidate
    raise FileNotFoundError(f"Blend not found: {filename}")


def _load_full01_module() -> Any:
    script_dir = Path(__file__).resolve().parent
    generator_path = script_dir / _FULL01_MODULE_NAME
    spec = importlib.util.spec_from_file_location("eom_gen_full01_ts08s1_audit", generator_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load {generator_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _count_top_face_islands(mesh: bpy.types.Mesh) -> int:
    top_faces = [poly for poly in mesh.polygons if poly.material_index == 0]
    if not top_faces:
        return 0
    parent: dict[int, int] = {}

    def find(x: int) -> int:
        parent.setdefault(x, x)
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    for poly in top_faces:
        verts = poly.vertices
        root = find(verts[0])
        for index in verts[1:]:
            ri = find(index)
            if ri != root:
                parent[ri] = root
    top_verts = {v for poly in top_faces for v in poly.vertices}
    return len({find(v) for v in top_verts})


def _audit_mesh(mesh: bpy.types.Mesh) -> dict[str, object]:
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.verts.ensure_lookup_table()
    bm.edges.ensure_lookup_table()
    loose_verts = sum(1 for vert in bm.verts if not vert.link_edges)
    loose_edges = sum(1 for edge in bm.edges if not edge.link_faces)
    slot_poly_counts = Counter(polygon.material_index for polygon in mesh.polygons)
    top_face_islands = _count_top_face_islands(mesh)
    zs = [v.co.z for v in mesh.vertices]
    bm.free()
    return {
        "vertices": len(mesh.vertices),
        "polygons": len(mesh.polygons),
        "loose_verts": loose_verts,
        "loose_edges": loose_edges,
        "slot_poly_counts": dict(slot_poly_counts),
        "top_faces": slot_poly_counts.get(0, 0),
        "side_faces": slot_poly_counts.get(1, 0),
        "top_face_islands": top_face_islands,
        "z_min": min(zs) if zs else 0.0,
        "z_max": max(zs) if zs else 0.0,
    }


def _build_top_surface_vertex_z_lookup(mesh: bpy.types.Mesh) -> dict[tuple[float, float], float]:
    from eom_terrain_math_core import pos_key

    top_vert_indices: set[int] = set()
    for poly in mesh.polygons:
        if poly.material_index != 0:
            continue
        for vert_index in poly.vertices:
            top_vert_indices.add(vert_index)

    lookup: dict[tuple[float, float], float] = {}
    for vert_index in top_vert_indices:
        vert = mesh.vertices[vert_index]
        key = pos_key(vert.co.x, vert.co.y)
        z = vert.co.z
        existing = lookup.get(key)
        if existing is None or z > existing:
            lookup[key] = z
    return lookup


def _sample_top_z_near_xy(
    mesh: bpy.types.Mesh,
    top_vert_indices: set[int],
    x: float,
    y: float,
    *,
    tol: float = 1e-3,
) -> float | None:
    from eom_terrain_math_core import pos_key

    key = pos_key(x, y)
    lookup = _build_top_surface_vertex_z_lookup(mesh)
    direct = lookup.get(key)
    if direct is not None:
        return direct

    best_z: float | None = None
    best_dist_sq = tol * tol
    for vert_index in top_vert_indices:
        vert = mesh.vertices[vert_index]
        dx = float(vert.co.x) - x
        dy = float(vert.co.y) - y
        dist_sq = dx * dx + dy * dy
        if dist_sq <= best_dist_sq:
            best_dist_sq = dist_sq
            best_z = float(vert.co.z)
    return best_z


def _audit_center_heights(
    mesh: bpy.types.Mesh,
    model: Any,
    baseline: Any,
    *,
    radius: float,
) -> tuple[float, int]:
    from eom_terrain_math_core import (
        canonical_center_world_z,
        handdrawn_to_baseline_axial,
    )

    top_vert_indices: set[int] = set()
    for poly in mesh.polygons:
        if poly.material_index != 0:
            continue
        for vert_index in poly.vertices:
            top_vert_indices.add(vert_index)

    max_error = 0.0
    violations = 0
    for q, r in sorted(model.map.tiles):
        q_b, r_b = handdrawn_to_baseline_axial(q, r)
        cx, cy = baseline.axial_to_world_xy(q_b, r_b, radius)
        actual = _sample_top_z_near_xy(mesh, top_vert_indices, cx, cy)
        expected = canonical_center_world_z(model.map, q, r)
        if actual is None:
            violations += 1
            max_error = max(max_error, float("inf"))
            continue
        error = abs(float(actual) - expected)
        if error > max_error:
            max_error = error
        if error > CENTER_HEIGHT_TOL:
            violations += 1
    return max_error, violations


def _audit_tent_poles(mesh: bpy.types.Mesh, model: Any, baseline: Any, *, radius: float) -> float:
    from eom_terrain_math_core import handdrawn_to_baseline_axial, pos_key

    top_vert_indices: set[int] = set()
    for poly in mesh.polygons:
        if poly.material_index != 0:
            continue
        for vert_index in poly.vertices:
            top_vert_indices.add(vert_index)

    center_vert_indices: list[int] = []
    for q, r in sorted(model.map.tiles):
        q_b, r_b = handdrawn_to_baseline_axial(q, r)
        cx, cy = baseline.axial_to_world_xy(q_b, r_b, radius)
        center_key = pos_key(cx, cy)
        for vert_index in top_vert_indices:
            vert = mesh.vertices[vert_index]
            if pos_key(vert.co.x, vert.co.y) == center_key:
                center_vert_indices.append(vert_index)
                break

    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.verts.ensure_lookup_table()
    bm.edges.ensure_lookup_table()
    max_delta = 0.0
    for center_index in center_vert_indices:
        center_vert = bm.verts[center_index]
        center_z = center_vert.co.z
        for edge in center_vert.link_edges:
            other = edge.other_vert(center_vert)
            if other.index not in top_vert_indices:
                continue
            delta = abs(float(center_z) - float(other.co.z))
            if delta > max_delta:
                max_delta = delta
    bm.free()
    return max_delta



def main() -> None:
    if "BASELINE" in OUTPUT_BLEND_FILENAME.upper():
        print("FAIL: audit target filename looks like a BASELINE path")
        sys.exit(1)

    output_path = _resolve_blend_path(OUTPUT_BLEND_FILENAME)
    full01 = _load_full01_module()
    terrain_map = full01.parse_terrain_map_json(full01.TERRAIN_MAP_JSON)
    model = full01.build_terrain_model(terrain_map)
    repo_root, examined_starts = full01._resolve_repo_root()
    baseline = full01._load_baseline_module(repo_root, examined_starts=examined_starts)
    radius = full01.DEFAULT_HEX_RADIUS

    ts03_z_lookup: dict[tuple[float, float], float] | None = None
    try:
        ts03_path = _resolve_blend_path(TS03_BASELINE_FILENAME)
        print(f"AUDIT_TS03_BASELINE_REFERENCE={ts03_path.resolve()}")
        bpy.ops.wm.open_mainfile(filepath=str(ts03_path))
        ts03_obj = bpy.data.objects.get(TERRAIN_OBJECT_NAME)
        if ts03_obj is not None and ts03_obj.type == "MESH":
            ts03_z_lookup = _build_top_surface_vertex_z_lookup(ts03_obj.data)
    except FileNotFoundError:
        pass

    print("=== TS08_STAGE1_NO_CUT_THIN_PLATE_CG_AUDIT (read-only) ===")
    print(f"AUDIT_OUTPUT_BLEND_PATH={output_path.resolve()}")
    print(f"MAP_ID={MAP_ID}")
    print("AUDIT_MODE=read_only_no_save")
    print("GAMMA_EMPTY=ON")
    print("CUTS=OFF")

    bpy.ops.wm.open_mainfile(filepath=str(output_path))
    terrain_obj = bpy.data.objects.get(TERRAIN_OBJECT_NAME)
    failures: list[str] = []
    warnings: list[str] = []

    if terrain_obj is None or terrain_obj.type != "MESH":
        failures.append(f"missing terrain mesh object {TERRAIN_OBJECT_NAME!r}")
        print("=== RESULT: FAIL ===")
        for failure in failures:
            print(f"FAIL: {failure}")
        sys.exit(1)

    report = _audit_mesh(terrain_obj.data)
    print(f"MESH_VERTICES={report['vertices']}")
    print(f"MESH_POLYGONS={report['polygons']}")
    print(f"MESH_TOP_FACES={report['top_faces']}")
    print(f"MESH_SIDE_FACES={report['side_faces']}")
    print(f"MESH_TOP_FACE_ISLANDS={report['top_face_islands']}")
    print(f"MESH_Z_MIN={report['z_min']:.6f}")
    print(f"MESH_Z_MAX={report['z_max']:.6f}")
    print(f"MESH_LOOSE_VERTS={report['loose_verts']}")
    print(f"MESH_LOOSE_EDGES={report['loose_edges']}")

    if report["top_face_islands"] != 1:
        failures.append(f"top_face_islands: got {report['top_face_islands']}, expected 1")
    if report["loose_verts"] != 0:
        failures.append(f"loose_verts: got {report['loose_verts']}, expected 0")
    if report["loose_edges"] != 0:
        failures.append(f"loose_edges: got {report['loose_edges']}, expected 0")

    if report["top_face_islands"] >= 10:
        failures.append(
            f"top_face_islands fragmentation regression: {report['top_face_islands']}"
        )

    z_min = float(report["z_min"])
    z_max = float(report["z_max"])
    if z_min < Z_MIN_GATE:
        failures.append(f"z_min outside TS-03-like gate: {z_min:.6f} < {Z_MIN_GATE}")
    if z_max > Z_MAX_GATE:
        failures.append(f"z_max outside TS-03-like gate: {z_max:.6f} > {Z_MAX_GATE}")
    if z_min <= Z_TS07C_FAIL_MIN or z_max >= Z_TS07C_FAIL_MAX:
        failures.append(
            f"z-range approaches TS-07c failure scale: [{z_min:.4f}, {z_max:.4f}]"
        )

    max_center_error, center_violations = _audit_center_heights(
        terrain_obj.data,
        model,
        baseline,
        radius=radius,
    )
    print(f"MAX_CENTER_INTERPOLATION_ERROR={max_center_error:.6e}")
    print(f"CENTER_HEIGHT_VIOLATIONS={center_violations}")
    if center_violations > 0:
        failures.append(
            f"center height violations: {center_violations} "
            f"(max error {max_center_error:.6e}, tol {CENTER_HEIGHT_TOL:.6e})"
        )

    max_tent_pole = _audit_tent_poles(terrain_obj.data, model, baseline, radius=radius)
    print(f"MAX_TENT_POLE_DELTA={max_tent_pole:.6f}")
    if max_tent_pole > 1.0:
        warnings.append(
            f"tent-pole delta is high ({max_tent_pole:.6f}); review visually before hard-gating"
        )

    side_faces = int(report["side_faces"])
    if side_faces > 7000:
        warnings.append(
            f"side_faces={side_faces} may indicate presentation cliff walls; expected base skirt only"
        )

    if ts03_z_lookup is not None:
        from eom_terrain_math_core import pos_key

        diffs_sq: list[float] = []
        for vert in terrain_obj.data.vertices:
            key = pos_key(vert.co.x, vert.co.y)
            ref = ts03_z_lookup.get(key)
            if ref is None:
                continue
            diff = float(vert.co.z) - float(ref)
            diffs_sq.append(diff * diff)
        if diffs_sq:
            rms = float(sum(diffs_sq) / len(diffs_sq)) ** 0.5
            print(f"WARN_TS03_RMS_Z_DIFF={rms:.6f}")
            warnings.append(f"TS-03 RMS z difference (warn-only): {rms:.6f}")
    else:
        warnings.append("TS-03 baseline blend not found for optional comparison")

    if warnings:
        print("--- warnings ---")
        for warning in warnings:
            print(f"WARNING: {warning}")

    if failures:
        print("=== RESULT: FAIL ===")
        for failure in failures:
            print(f"FAIL: {failure}")
        sys.exit(1)

    print("=== RESULT: PASS ===")
    print("TS08_STAGE1_NO_CUT_THIN_PLATE_CG_AUDIT_PASS=True")


if __name__ == "__main__":
    main()
