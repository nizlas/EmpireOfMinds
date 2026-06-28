# Inspect cliff wall geometry in a saved terrain .blend (read-only).
from __future__ import annotations

import sys
from pathlib import Path

import bpy
from mathutils import Vector

BLEND = Path(
    r"c:\Users\nicla\development\EmpireOfMinds\game\assets\prototype\3d\terrain"
    r"\prototype_3d_terrain\generated\terrain_handdrawn_test_map_full_01_variational_spline_cliff_debug.blend"
)
TERRAIN_NAME = "EOM_Terrain_TerrainMapFull01"
CLIFF_ISO_NAME = "EOM_Terrain_TerrainMapFull01_CliffPlaceholder"


def main() -> None:
    if not BLEND.is_file():
        print(f"blend not found: {BLEND}")
        sys.exit(1)
    bpy.ops.wm.open_mainfile(filepath=str(BLEND))

    obj = bpy.data.objects.get(TERRAIN_NAME)
    if obj is None:
        print(f"object missing: {TERRAIN_NAME}")
        print("objects:", [o.name for o in bpy.data.objects if o.type == "MESH"])
        sys.exit(1)

    mesh = obj.data
    print("=== OBJECT ===")
    print(f"name: {obj.name}")
    print(f"collection: {[c.name for c in obj.users_collection]}")
    print(f"hide_viewport: {obj.hide_viewport}")
    print(f"hide_render: {obj.hide_render}")
    print(f"visible_get(viewport): {obj.visible_get()}")

    print("\n=== MESH ===")
    print(f"vertices: {len(mesh.vertices)}")
    print(f"edges: {len(mesh.edges)}")
    print(f"polygons: {len(mesh.polygons)}")
    print(f"materials: {[m.name if m else None for m in mesh.materials]}")

    mat_slots = {i: (mesh.materials[i].name if mesh.materials[i] else None) for i in range(len(mesh.materials))}
    slot_counts: dict[int, int] = {}
    ngon4 = ngon_other = 0
    for poly in mesh.polygons:
        slot_counts[poly.material_index] = slot_counts.get(poly.material_index, 0) + 1
        if len(poly.vertices) == 4:
            ngon4 += 1
        else:
            ngon_other += 1

    print(f"faces by material slot: {slot_counts}")
    print(f"quad (4-vert) faces: {ngon4}, other: {ngon_other}")

    # Heuristic: top faces use slot 0; side slot 1 — cliff walls are slot 1 subset.
    # Without stored indices, estimate from face order if we know top count from log: 145152
    top_count = 145152
    side_start = top_count
    side_polys = [p for p in mesh.polygons if p.index >= side_start]
    print(f"\n=== SIDE FACES (index >= {top_count}) ===")
    print(f"side+cliff+bottom count: {len(side_polys)}")

    z_vals = [mesh.vertices[v].co.z for p in side_polys for v in p.vertices]
    if z_vals:
        print(f"side/cliff/bottom Z range: {min(z_vals):.4f} .. {max(z_vals):.4f}")

    # Vertical faces: normal Z near 0
    vertical: list[int] = []
    for poly in side_polys:
        if len(poly.vertices) != 4:
            continue
        v0 = mesh.vertices[poly.vertices[0]].co
        v1 = mesh.vertices[poly.vertices[1]].co
        v2 = mesh.vertices[poly.vertices[2]].co
        n = (v1 - v0).cross(v2 - v0)
        if n.length > 1e-12:
            n.normalize()
            if abs(n.z) < 0.15:
                vertical.append(poly.index)

    print(f"heuristic vertical quads in side region: {len(vertical)}")

    if vertical:
        sample_idx = vertical[:10]
        print("\nfirst 10 vertical wall face indices:", sample_idx)
        for fi in sample_idx[:3]:
            poly = mesh.polygons[fi]
            verts = [tuple(mesh.vertices[v].co) for v in poly.vertices]
            print(f"  face {fi} verts z:", [round(v[2], 4) for v in verts])

    # Bounding box of vertical quads
    if vertical:
        coords = []
        for fi in vertical:
            for v in mesh.polygons[fi].vertices:
                coords.append(mesh.vertices[v].co.copy())
        xs = [c.x for c in coords]
        ys = [c.y for c in coords]
        zs = [c.z for c in coords]
        print(f"\nvertical wall bbox X: {min(xs):.2f}..{max(xs):.2f}")
        print(f"vertical wall bbox Y: {min(ys):.2f}..{max(ys):.2f}")
        print(f"vertical wall bbox Z: {min(zs):.4f}..{max(zs):.4f}")

    # Backface / double-sided
    for i, mat in enumerate(mesh.materials):
        if mat is None:
            continue
        print(f"\nmaterial[{i}] {mat.name}: blend_method={getattr(mat, 'blend_method', '?')}")
        if mat.use_nodes and mat.node_tree:
            for node in mat.node_tree.nodes:
                if node.type == "BSDF_PRINCIPLED":
                    bc = node.inputs.get("Base Color")
                    if bc:
                        print(f"  base color: {tuple(round(x, 3) for x in bc.default_value)}")

    cliff_obj = bpy.data.objects.get(CLIFF_ISO_NAME)
    if cliff_obj is not None:
        print(f"\n=== ISOLATED CLIFF OBJECT {CLIFF_ISO_NAME} ===")
        print(f"visible: hide_viewport={cliff_obj.hide_viewport}")
        cm = cliff_obj.data
        print(f"verts={len(cm.vertices)} polys={len(cm.polygons)}")
        print(f"materials: {[m.name if m else None for m in cm.materials]}")


if __name__ == "__main__":
    main()
