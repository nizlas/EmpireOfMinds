# Empire of Minds — read-only audit for regenerated TS-03 global continuous baseline output.
# Run: blender --background --python tools/blender/terrain/audit_ts03_global_continuous_baseline_blend.py
#
# STRICTLY READ-ONLY: never saves or modifies any blend file.

from __future__ import annotations

import sys
from collections import Counter
from pathlib import Path

import bmesh
import bpy

TERRAIN_OBJECT_NAME = "EOM_Terrain_TerrainMapFull01"
OUTPUT_BLEND_FILENAME = (
    "terrain_handdrawn_test_map_full_01_ts03_global_continuous_baseline.blend"
)
FROZEN_BASELINE_FILENAME = (
    "terrain_handdrawn_test_map_full_01_variational_spline_BASELINE_2026-06-27.blend"
)
EXPECTED = {
    "vertices": 77675,
    "polygons": 150768,
    "top_faces": 145152,
    "side_faces": 5616,
    "top_face_islands": 1,
    "z_min": -0.587,
    "z_max": 2.304,
}


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


def _edge_key(v0: int, v1: int) -> tuple[int, int]:
    return (v0, v1) if v0 < v1 else (v1, v0)


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


def main() -> None:
    output_path = _resolve_blend_path(OUTPUT_BLEND_FILENAME)
    reference_path = _resolve_blend_path(FROZEN_BASELINE_FILENAME)

    print("=== TS03_GLOBAL_CONTINUOUS_BASELINE_AUDIT (read-only) ===")
    print(f"AUDIT_OUTPUT_BLEND_PATH={output_path.resolve()}")
    print(f"AUDIT_REFERENCE_BLEND_PATH={reference_path.resolve()}")
    print("AUDIT_MODE=read_only_no_save")

    bpy.ops.wm.open_mainfile(filepath=str(output_path))
    terrain_obj = bpy.data.objects.get(TERRAIN_OBJECT_NAME)
    failures: list[str] = []
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
    print(f"MESH_Z_MIN={report['z_min']:.4f}")
    print(f"MESH_Z_MAX={report['z_max']:.4f}")
    print(f"MESH_LOOSE_VERTS={report['loose_verts']}")
    print(f"MESH_LOOSE_EDGES={report['loose_edges']}")

    for key, expected in EXPECTED.items():
        if key == "z_min":
            actual = report["z_min"]
        elif key == "z_max":
            actual = report["z_max"]
        else:
            actual = report[key]
        if key in ("z_min", "z_max"):
            if abs(float(actual) - expected) > 0.02:
                failures.append(f"{key}: got {actual:.4f}, expected ~{expected}")
        elif actual != expected:
            failures.append(f"{key}: got {actual}, expected {expected}")

    if failures:
        print("=== RESULT: FAIL ===")
        for failure in failures:
            print(f"FAIL: {failure}")
        sys.exit(1)

    print("=== RESULT: PASS ===")
    print("TS03_GLOBAL_CONTINUOUS_BASELINE_AUDIT_PASS=True")


if __name__ == "__main__":
    main()
