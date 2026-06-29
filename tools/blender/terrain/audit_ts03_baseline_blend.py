# Empire of Minds — read-only headless audit for the frozen TS-03 baseline blend.
# Run: blender --background --python tools/blender/terrain/audit_ts03_baseline_blend.py
#
# STRICTLY READ-ONLY: opens the baseline blend for inspection only.
# This script must NEVER call save, save_as, or any operator that writes the file.

from __future__ import annotations

import sys
from collections import Counter
from pathlib import Path

import bpy
import bmesh

TERRAIN_OBJECT_NAME = "EOM_Terrain_TerrainMapFull01"
CLIFF_ISO_NAME = "EOM_Terrain_TerrainMapFull01_CliffPlaceholder"
OVERLAY_OBJECT_NAME = "EOM_Terrain_TerrainMapFull01_Overlay"
FROZEN_BASELINE_FILENAME = (
    "terrain_handdrawn_test_map_full_01_variational_spline_BASELINE_2026-06-27.blend"
)


def _resolve_baseline_blend_path() -> Path:
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
                / FROZEN_BASELINE_FILENAME
            )
            if candidate.is_file():
                return candidate
    raise FileNotFoundError(
        f"Frozen baseline blend not found: {FROZEN_BASELINE_FILENAME}; "
        f"searched from: {[str(s) for s in starts]}"
    )


def _edge_key(v0: int, v1: int) -> tuple[int, int]:
    return (v0, v1) if v0 < v1 else (v1, v0)


def _count_face_islands(mesh: bpy.types.Mesh) -> int:
    if not mesh.polygons:
        return 0
    poly_count = len(mesh.polygons)
    visited = [False] * poly_count
    islands = 0
    edge_to_polys: dict[tuple[int, int], list[int]] = {}
    for poly_index, polygon in enumerate(mesh.polygons):
        verts = polygon.vertices
        vert_count = len(verts)
        for i in range(vert_count):
            key = _edge_key(verts[i], verts[(i + 1) % vert_count])
            edge_to_polys.setdefault(key, []).append(poly_index)

    for start in range(poly_count):
        if visited[start]:
            continue
        islands += 1
        stack = [start]
        visited[start] = True
        while stack:
            current = stack.pop()
            polygon = mesh.polygons[current]
            verts = polygon.vertices
            vert_count = len(verts)
            for i in range(vert_count):
                key = _edge_key(verts[i], verts[(i + 1) % vert_count])
                for neighbor in edge_to_polys.get(key, ()):
                    if not visited[neighbor]:
                        visited[neighbor] = True
                        stack.append(neighbor)
    return islands


def _audit_mesh(mesh: bpy.types.Mesh) -> dict[str, object]:
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.verts.ensure_lookup_table()
    bm.edges.ensure_lookup_table()
    bm.faces.ensure_lookup_table()

    loose_verts = sum(1 for vert in bm.verts if not vert.link_edges)
    loose_edges = sum(1 for edge in bm.edges if not edge.link_faces)

    edge_counts: Counter[tuple[int, int]] = Counter()
    for face in bm.faces:
        verts = face.verts
        vert_count = len(verts)
        for i in range(vert_count):
            v0 = verts[i].index
            v1 = verts[(i + 1) % vert_count].index
            edge_counts[_edge_key(v0, v1)] += 1
    open_edges = [edge for edge, count in edge_counts.items() if count == 1]

    material_slots = [mat.name if mat else None for mat in mesh.materials]
    slot_poly_counts = Counter(polygon.material_index for polygon in mesh.polygons)
    face_islands = _count_face_islands(mesh)

    bm.free()

    return {
        "vertices": len(mesh.vertices),
        "edges": len(mesh.edges),
        "polygons": len(mesh.polygons),
        "loose_verts": loose_verts,
        "loose_edges": loose_edges,
        "open_edges": len(open_edges),
        "face_islands": face_islands,
        "material_slots": material_slots,
        "slot_poly_counts": dict(slot_poly_counts),
    }


def main() -> None:
    blend_path = _resolve_baseline_blend_path()
    print("=== TS03_BASELINE_AUDIT (read-only) ===")
    print(f"AUDIT_BLEND_PATH={blend_path.resolve()}")
    print("AUDIT_MODE=read_only_no_save")

    bpy.ops.wm.open_mainfile(filepath=str(blend_path))

    failures: list[str] = []
    warnings: list[str] = []

    terrain_obj = bpy.data.objects.get(TERRAIN_OBJECT_NAME)
    if terrain_obj is None:
        failures.append(f"missing terrain object {TERRAIN_OBJECT_NAME!r}")
        terrain_mesh = None
    else:
        terrain_mesh = terrain_obj.data
        print(f"TERRAIN_OBJECT={terrain_obj.name}")
        print(f"TERRAIN_TYPE={terrain_obj.type}")
        print(f"TERRAIN_HIDE_VIEWPORT={terrain_obj.hide_viewport}")

    if terrain_mesh is None or terrain_obj.type != "MESH":
        failures.append("terrain object is not a mesh")
    else:
        mesh_report = _audit_mesh(terrain_mesh)
        print(f"MESH_VERTICES={mesh_report['vertices']}")
        print(f"MESH_EDGES={mesh_report['edges']}")
        print(f"MESH_POLYGONS={mesh_report['polygons']}")
        print(f"MESH_LOOSE_VERTS={mesh_report['loose_verts']}")
        print(f"MESH_LOOSE_EDGES={mesh_report['loose_edges']}")
        print(f"MESH_OPEN_EDGES={mesh_report['open_edges']}")
        print(f"MESH_FACE_ISLANDS={mesh_report['face_islands']}")
        print(f"MESH_MATERIAL_SLOTS={mesh_report['material_slots']}")
        print(f"MESH_SLOT_POLY_COUNTS={mesh_report['slot_poly_counts']}")

        if mesh_report["loose_verts"]:
            failures.append(f"loose vertices: {mesh_report['loose_verts']}")
        if mesh_report["loose_edges"]:
            failures.append(f"loose edges: {mesh_report['loose_edges']}")
        if mesh_report["face_islands"] != 1:
            failures.append(
                f"expected 1 connected face island, found {mesh_report['face_islands']}"
            )
        if len(mesh_report["material_slots"]) < 2:
            failures.append(
                f"expected at least 2 material slots (top + side), "
                f"found {len(mesh_report['material_slots'])}"
            )
        if mesh_report["open_edges"] == 0:
            warnings.append("no open boundary edges detected (unexpected for terrain solid)")

    cliff_obj = bpy.data.objects.get(CLIFF_ISO_NAME)
    if cliff_obj is None:
        print(f"CLIFF_ISO_OBJECT={CLIFF_ISO_NAME} present=False")
    else:
        print(f"CLIFF_ISO_OBJECT={cliff_obj.name} present=True")
        print(f"CLIFF_ISO_HIDE_VIEWPORT={cliff_obj.hide_viewport}")
        print(f"CLIFF_ISO_VERTS={len(cliff_obj.data.vertices)}")
        print(f"CLIFF_ISO_POLYS={len(cliff_obj.data.polygons)}")

    overlay_obj = bpy.data.objects.get(OVERLAY_OBJECT_NAME)
    print(
        f"OVERLAY_OBJECT={OVERLAY_OBJECT_NAME} present={overlay_obj is not None}"
    )

    if warnings:
        print("=== WARNINGS ===")
        for warning in warnings:
            print(f"WARNING: {warning}")

    if failures:
        print("=== RESULT: FAIL ===")
        for failure in failures:
            print(f"FAIL: {failure}")
        sys.exit(1)

    print("=== RESULT: PASS ===")
    print("TS03_BASELINE_AUDIT_PASS=True")


if __name__ == "__main__":
    main()
