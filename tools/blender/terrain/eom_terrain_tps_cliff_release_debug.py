# Empire of Minds — TS-05 release-region debug export (visualization only; no solver changes).

from __future__ import annotations

import colorsys
import math
from dataclasses import dataclass, field
from typing import Any, Literal

from eom_terrain_math_core import (
    DEFAULT_HEX_RADIUS,
    DEFAULT_SURFACE_SUBDIVISIONS,
    canonical_center_world_z,
    corner_xy_local,
    handdrawn_center_world_xy,
    sector_barycentric_xy,
    tile_world_z,
)
from eom_terrain_tps_cliff_release import (
    BAND_DEPTH,
    TS05_MAX_BAND_TPS_ANCHORS,
    BandFallbackKind,
    BandSolveDiagnostics,
    CliffFront,
    SideBandRelease,
    TpsCliffReleaseTerrainSolver,
    VariationalSplineTerrainSolver,
    _build_cliff_physical_edges_by_tile,
    _cliff_edge_segment_world,
    _dedupe_band_anchors_with_meta,
    _expand_side_band,
    _min_dist_to_front,
    _upper_lower_tiles,
    _xy_anchor_tol,
    Z_ANCHOR_TOL,
    INTERIOR_MIN_DIST_FACTOR,
)

AnchorKind = Literal["center", "interior_pinned", "rim_free", "discarded_downsample", "used_tps"]
SideName = Literal["upper", "lower"]

SOLVE_MODE_LABELS: dict[BandFallbackKind, str] = {
    "tps": "TPS",
    "downsampled_tps": "downsampled TPS",
    "affine_plane": "affine fallback",
    "base_ts03": "base TS03 fallback",
    "skipped": "skipped",
}

TS05_DEBUG_COLLECTION_NAME = "TS05_Debug"
TS05_DEBUG_Z_CLIFF = 0.28
TS05_DEBUG_Z_UPPER = 0.22
TS05_DEBUG_Z_LOWER = 0.14
TS05_DEBUG_Z_ANCHOR = 0.32


@dataclass(frozen=True)
class DebugAnchor:
    wx: float
    wy: float
    wz: float
    kind: AnchorKind
    tile: tuple[int, int] | None = None


@dataclass
class Ts05SideBandDebug:
    side: SideName
    band_tiles: frozenset[tuple[int, int]]
    solve_mode: str
    raw_anchor_count: int
    unique_anchor_count: int
    used_anchor_count: int
    downsampled_discarded_count: int
    center_anchors: list[DebugAnchor] = field(default_factory=list)
    interior_anchors: list[DebugAnchor] = field(default_factory=list)
    rim_anchors: list[DebugAnchor] = field(default_factory=list)
    discarded_anchors: list[DebugAnchor] = field(default_factory=list)
    used_anchors: list[DebugAnchor] = field(default_factory=list)


@dataclass
class Ts05FrontDebug:
    front_id: int
    edge_count: int
    cliff_edges: tuple[Any, ...]
    cliff_edge_tiles: list[tuple[tuple[int, int], tuple[int, int]]]
    color_rgb: tuple[float, float, float]
    upper_color_rgb: tuple[float, float, float]
    lower_color_rgb: tuple[float, float, float]
    upper: Ts05SideBandDebug | None = None
    lower: Ts05SideBandDebug | None = None


@dataclass
class Ts05DebugExport:
    fronts: list[Ts05FrontDebug]


def _front_palette_color(front_id: int, *, value_scale: float = 1.0) -> tuple[float, float, float]:
    hue = (front_id * 0.61803398875) % 1.0
    r, g, b = colorsys.hsv_to_rgb(hue, 0.82, min(1.0, 0.92 * value_scale))
    return (r, g, b)


def _mirror_downsample_selected_indices(
    is_center: list[bool],
    front_dist: list[float],
    cap: int,
) -> frozenset[int]:
    n = len(is_center)
    if n <= cap:
        return frozenset(range(n))

    center_idx = sorted(i for i, center in enumerate(is_center) if center)
    interior_idx = sorted(
        (i for i, center in enumerate(is_center) if not center),
        key=lambda i: (-front_dist[i], i),
    )

    selected: list[int] = []
    for index in center_idx:
        if len(selected) >= cap:
            break
        selected.append(index)

    remaining = cap - len(selected)
    if remaining > 0 and interior_idx:
        if len(interior_idx) <= remaining:
            selected.extend(interior_idx)
        else:
            stride = max(1, len(interior_idx) // remaining)
            picked: list[int] = []
            for index in interior_idx[::stride]:
                if index not in picked:
                    picked.append(index)
                if len(picked) >= remaining:
                    break
            if len(picked) < remaining:
                for index in interior_idx:
                    if index in picked:
                        continue
                    picked.append(index)
                    if len(picked) >= remaining:
                        break
            selected.extend(picked[:remaining])

    return frozenset(selected)


def _band_seeds_for_side(front: CliffFront, side: SideName) -> set[tuple[int, int]]:
    seeds: set[tuple[int, int]] = set()
    for cliff in front.edges:
        upper, lower = _upper_lower_tiles(cliff)
        seeds.add(upper if side == "upper" else lower)
    return seeds


def _collect_band_debug_samples(
    band_tiles: frozenset[tuple[int, int]],
    front: CliffFront,
    model: Any,
    base: VariationalSplineTerrainSolver,
    *,
    radius: float,
    subdiv: int,
) -> tuple[
    list[tuple[float, float]],
    list[float],
    list[bool],
    list[float],
    list[DebugAnchor],
    list[DebugAnchor],
]:
    """Mirror constraint collection; also record rim samples excluded from TPS anchors."""
    xy: list[tuple[float, float]] = []
    zz: list[float] = []
    is_center: list[bool] = []
    front_dist: list[float] = []
    rim_anchors: list[DebugAnchor] = []

    cliff_phys = _build_cliff_physical_edges_by_tile(model)
    interior_min = INTERIOR_MIN_DIST_FACTOR * radius

    for q, r in sorted(band_tiles):
        cx, cy = handdrawn_center_world_xy(q, r, radius)
        tile = (q, r)
        dist_center = _min_dist_to_front(cx, cy, front, radius=radius)
        z_center = canonical_center_world_z(model.map, q, r)
        xy.append((cx, cy))
        zz.append(z_center)
        is_center.append(True)
        front_dist.append(dist_center)

        tile_cliff_edges = cliff_phys.get(tile, frozenset())
        for sector in range(6):
            si = 0
            while si <= subdiv:
                sj = 0
                while sj <= subdiv - si:
                    at_outer = si + sj == subdiv
                    lx, ly, _, _ = sector_barycentric_xy(sector, si, sj, subdiv, radius=radius)
                    wx = cx + lx
                    wy = cy + ly
                    dist_sample = _min_dist_to_front(wx, wy, front, radius=radius)
                    z_sample = base.sample_world(
                        wx,
                        wy,
                        q,
                        r,
                        sector=sector,
                        at_sector_outer_edge=at_outer,
                    )
                    if at_outer and sector in tile_cliff_edges:
                        rim_anchors.append(
                            DebugAnchor(
                                wx=wx,
                                wy=wy,
                                wz=z_sample,
                                kind="rim_free",
                                tile=tile,
                            )
                        )
                        sj += 1
                        continue
                    if dist_sample < interior_min:
                        sj += 1
                        continue
                    xy.append((wx, wy))
                    zz.append(z_sample)
                    is_center.append(False)
                    front_dist.append(dist_sample)
                    sj += 1
                si += 1

    return xy, zz, is_center, front_dist, rim_anchors, []


def _classify_deduped_anchors(
    deduped_xy: list[tuple[float, float]],
    deduped_zz: list[float],
    deduped_center: list[bool],
    selected_indices: frozenset[int],
) -> tuple[list[DebugAnchor], list[DebugAnchor], list[DebugAnchor], list[DebugAnchor]]:
    centers: list[DebugAnchor] = []
    interiors: list[DebugAnchor] = []
    used: list[DebugAnchor] = []
    discarded: list[DebugAnchor] = []

    for index, ((wx, wy), wz, center_flag) in enumerate(
        zip(deduped_xy, deduped_zz, deduped_center, strict=True)
    ):
        anchor = DebugAnchor(wx=wx, wy=wy, wz=wz, kind="center" if center_flag else "interior_pinned")
        if center_flag:
            centers.append(anchor)
        else:
            interiors.append(anchor)
        if index in selected_indices:
            used.append(DebugAnchor(wx=wx, wy=wy, wz=wz, kind="used_tps"))
        else:
            discarded.append(DebugAnchor(wx=wx, wy=wy, wz=wz, kind="discarded_downsample"))

    return centers, interiors, used, discarded


def _build_side_band_debug(
    front: CliffFront,
    side: SideName,
    model: Any,
    base: VariationalSplineTerrainSolver,
    release: SideBandRelease | None,
    diag: BandSolveDiagnostics | None,
    *,
    radius: float,
    subdiv: int,
) -> Ts05SideBandDebug | None:
    band = _expand_side_band(_band_seeds_for_side(front, side), model, depth=BAND_DEPTH)
    if len(band) < 2:
        return None

    xy, zz, is_center, front_dist, rim_anchors, _ = _collect_band_debug_samples(
        band,
        front,
        model,
        base,
        radius=radius,
        subdiv=subdiv,
    )
    raw_count = len(xy)
    xy_tol = _xy_anchor_tol(radius)
    (
        deduped_xy,
        deduped_zz,
        deduped_center,
        deduped_front_dist,
        _duplicate_xy,
        _conflicts,
    ) = _dedupe_band_anchors_with_meta(
        xy,
        zz,
        is_center,
        front_dist,
        xy_tol=xy_tol,
        z_tol=Z_ANCHOR_TOL,
    )
    unique_count = len(deduped_xy)
    selected = _mirror_downsample_selected_indices(
        deduped_center,
        deduped_front_dist,
        TS05_MAX_BAND_TPS_ANCHORS,
    )
    used_count = len(selected)
    centers, interiors, used, discarded = _classify_deduped_anchors(
        deduped_xy,
        deduped_zz,
        deduped_center,
        selected,
    )

    fallback: BandFallbackKind = release.fallback if release is not None else "skipped"
    if diag is not None and release is None:
        fallback = diag.fallback

    downsampled_discarded = unique_count - used_count if unique_count > used_count else 0

    return Ts05SideBandDebug(
        side=side,
        band_tiles=band,
        solve_mode=SOLVE_MODE_LABELS.get(fallback, fallback),
        raw_anchor_count=raw_count,
        unique_anchor_count=unique_count,
        used_anchor_count=used_count,
        downsampled_discarded_count=downsampled_discarded,
        center_anchors=centers,
        interior_anchors=interiors,
        rim_anchors=rim_anchors,
        discarded_anchors=discarded,
        used_anchors=used,
    )


def build_ts05_debug_export(
    solver: TpsCliffReleaseTerrainSolver,
    model: Any,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
    subdiv: int = DEFAULT_SURFACE_SUBDIVISIONS,
) -> Ts05DebugExport:
    release_by_key: dict[tuple[int, SideName], SideBandRelease] = {
        (release.front_id, release.side): release for release in solver._releases
    }
    diag_by_key: dict[tuple[int, SideName], BandSolveDiagnostics] = {}
    report = solver._release_report
    if report is not None:
        for diag in report.band_solve_diagnostics:
            diag_by_key[(diag.front_id, diag.side)] = diag

    fronts: list[Ts05FrontDebug] = []
    for front in solver._fronts:
        base_color = _front_palette_color(front.front_id)
        cliff_edges = [(edge.tile_a, edge.tile_b) for edge in front.edges]
        upper = _build_side_band_debug(
            front,
            "upper",
            model,
            solver._base,
            release_by_key.get((front.front_id, "upper")),
            diag_by_key.get((front.front_id, "upper")),
            radius=radius,
            subdiv=subdiv,
        )
        lower = _build_side_band_debug(
            front,
            "lower",
            model,
            solver._base,
            release_by_key.get((front.front_id, "lower")),
            diag_by_key.get((front.front_id, "lower")),
            radius=radius,
            subdiv=subdiv,
        )
        fronts.append(
            Ts05FrontDebug(
                front_id=front.front_id,
                edge_count=len(front.edges),
                cliff_edges=front.edges,
                cliff_edge_tiles=cliff_edges,
                color_rgb=base_color,
                upper_color_rgb=_front_palette_color(front.front_id, value_scale=1.18),
                lower_color_rgb=_front_palette_color(front.front_id, value_scale=0.72),
                upper=upper,
                lower=lower,
            )
        )
    return Ts05DebugExport(fronts=fronts)


def _format_tile_list(tiles: frozenset[tuple[int, int]]) -> str:
    lines = [f"({q},{r})" for q, r in sorted(tiles)]
    return "\n".join(lines) if lines else "(none)"


def print_ts05_front_diagnostics(export: Ts05DebugExport) -> None:
    for front in export.fronts:
        print(f"Front {front.front_id}")
        print(f"number of cliff edges: {front.edge_count}")
        upper_tiles = front.upper.band_tiles if front.upper else frozenset()
        lower_tiles = front.lower.band_tiles if front.lower else frozenset()
        print(f"number of upper tiles: {len(upper_tiles)}")
        print(f"number of lower tiles: {len(lower_tiles)}")
        upper_raw = front.upper.raw_anchor_count if front.upper else 0
        lower_raw = front.lower.raw_anchor_count if front.lower else 0
        print(f"upper anchor count (raw): {upper_raw}")
        print(f"lower anchor count (raw): {lower_raw}")
        upper_disc = front.upper.downsampled_discarded_count if front.upper else 0
        lower_disc = front.lower.downsampled_discarded_count if front.lower else 0
        print(f"upper downsampled anchor count (discarded): {upper_disc}")
        print(f"lower downsampled anchor count (discarded): {lower_disc}")
        print(f"upper solve mode: {front.upper.solve_mode if front.upper else 'n/a'}")
        print(f"lower solve mode: {front.lower.solve_mode if front.lower else 'n/a'}")
        print("Upper tiles:")
        print(_format_tile_list(upper_tiles))
        print("Lower tiles:")
        print(_format_tile_list(lower_tiles))
        if front.upper is not None:
            print(
                f"upper unique={front.upper.unique_anchor_count} "
                f"used={front.upper.used_anchor_count} "
                f"centers={len(front.upper.center_anchors)} "
                f"interior={len(front.upper.interior_anchors)} "
                f"rim={len(front.upper.rim_anchors)}"
            )
        if front.lower is not None:
            print(
                f"lower unique={front.lower.unique_anchor_count} "
                f"used={front.lower.used_anchor_count} "
                f"centers={len(front.lower.center_anchors)} "
                f"interior={len(front.lower.interior_anchors)} "
                f"rim={len(front.lower.rim_anchors)}"
            )
        print("Cliff edges:")
        for tile_a, tile_b in front.cliff_edge_tiles:
            print(f"  {tile_a} <-> {tile_b}")
        print("---")


def _make_emission_material(name: str, rgb: tuple[float, float, float], *, strength: float = 2.0) -> Any:
    import bpy

    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()
    emission = nodes.new(type="ShaderNodeEmission")
    emission.inputs["Color"].default_value = (rgb[0], rgb[1], rgb[2], 1.0)
    emission.inputs["Strength"].default_value = strength
    output = nodes.new(type="ShaderNodeOutputMaterial")
    links.new(emission.outputs["Emission"], output.inputs["Surface"])
    return mat


def _add_line_mesh_object(
    name: str,
    segments: list[tuple[tuple[float, float, float], tuple[float, float, float]]],
    material: Any,
    collection: Any,
) -> None:
    import bpy

    verts: list[tuple[float, float, float]] = []
    edges: list[tuple[int, int]] = []
    for a, b in segments:
        i0 = len(verts)
        verts.extend([a, b])
        edges.append((i0, i0 + 1))
    if not edges:
        return
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, edges, [])
    obj = bpy.data.objects.new(name, mesh)
    obj.data.materials.append(material)
    collection.objects.link(obj)


def _add_hex_tile_outlines(
    name: str,
    tiles: frozenset[tuple[int, int]],
    model: Any,
    rgb: tuple[float, float, float],
    z_offset: float,
    collection: Any,
) -> None:
    import bpy

    mat = _make_emission_material(f"{name}_mat", rgb)
    segments: list[tuple[tuple[float, float, float], tuple[float, float, float]]] = []
    radius = DEFAULT_HEX_RADIUS
    for q, r in sorted(tiles):
        cx, cy = handdrawn_center_world_xy(q, r, radius)
        z = tile_world_z(model.map, q, r) + z_offset
        corners: list[tuple[float, float, float]] = []
        for corner_index in range(6):
            lx, ly = corner_xy_local(corner_index, radius)
            corners.append((cx + lx, cy + ly, z))
        corners.append(corners[0])
        for i in range(6):
            segments.append((corners[i], corners[i + 1]))
    _add_line_mesh_object(name, segments, mat, collection)


def _add_anchor_points(
    name: str,
    anchors: list[DebugAnchor],
    rgb: tuple[float, float, float],
    collection: Any,
    *,
    size: float = 0.04,
) -> None:
    import bpy

    if not anchors:
        return
    mat = _make_emission_material(f"{name}_mat", rgb, strength=3.0)
    segments: list[tuple[tuple[float, float, float], tuple[float, float, float]]] = []
    for anchor in anchors:
        wx, wy = anchor.wx, anchor.wy
        wz = anchor.wz + TS05_DEBUG_Z_ANCHOR
        segments.append(((wx - size, wy, wz), (wx + size, wy, wz)))
        segments.append(((wx, wy - size, wz), (wx, wy + size, wz)))
    _add_line_mesh_object(name, segments, mat, collection)


def _count_collection_objects(collection: Any) -> int:
    count = len(collection.objects)
    for child in collection.children:
        count += _count_collection_objects(child)
    return count


def _collection_linked_under(parent: Any, collection: Any) -> bool:
    return any(
        child == collection or child.name == collection.name for child in parent.children
    )


def _link_collection_under_parent(parent: Any, collection: Any) -> None:
    if _collection_linked_under(parent, collection):
        return
    try:
        parent.children.link(collection)
    except RuntimeError:
        # Already linked under this parent (identity mismatch on reload).
        pass


def _unlink_collection_from_parent(parent: Any, collection: Any) -> None:
    for child in list(parent.children):
        if child == collection or child.name == collection.name:
            parent.children.unlink(child)
            return


def _link_collection_to_scene_root(collection: Any) -> None:
    import bpy

    _link_collection_under_parent(bpy.context.scene.collection, collection)


def _remove_existing_debug_collection(parent_collection: Any) -> None:
    import bpy

    if TS05_DEBUG_COLLECTION_NAME not in bpy.data.collections:
        return
    old = bpy.data.collections[TS05_DEBUG_COLLECTION_NAME]
    for child in list(old.children):
        for obj in list(child.objects):
            bpy.data.objects.remove(obj, do_unlink=True)
        try:
            old.children.unlink(child)
        except RuntimeError:
            pass
        bpy.data.collections.remove(child)
    for obj in list(old.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    _unlink_collection_from_parent(bpy.context.scene.collection, old)
    _unlink_collection_from_parent(parent_collection, old)
    bpy.data.collections.remove(old)


def build_ts05_debug_blender_overlays(
    export: Ts05DebugExport,
    model: Any,
    *,
    parent_collection: Any,
) -> dict[str, int]:
    import bpy

    empty_reasons: list[str] = []
    if not export.fronts:
        empty_reasons.append("no_cliff_fronts_in_export")

    _remove_existing_debug_collection(parent_collection)

    root = bpy.data.collections.new(TS05_DEBUG_COLLECTION_NAME)
    _link_collection_under_parent(parent_collection, root)
    _link_collection_to_scene_root(root)

    cliff_coll = bpy.data.collections.new("TS05_CliffFronts")
    upper_coll = bpy.data.collections.new("TS05_UpperBands")
    lower_coll = bpy.data.collections.new("TS05_LowerBands")
    anchor_coll = bpy.data.collections.new("TS05_Anchors")
    for child in (cliff_coll, upper_coll, lower_coll, anchor_coll):
        root.children.link(child)

    cliff_segments = 0
    radius = DEFAULT_HEX_RADIUS
    objects_before = len(bpy.data.objects)

    for front in export.fronts:
        cliff_mat = _make_emission_material(
            f"TS05_front{front.front_id}_cliff_mat",
            front.color_rgb,
        )
        segments: list[tuple[tuple[float, float, float], tuple[float, float, float]]] = []
        for edge in front.cliff_edges:
            (ax, ay), (bx, by) = _cliff_edge_segment_world(edge, radius=radius)
            za = tile_world_z(model.map, *edge.tile_a) + TS05_DEBUG_Z_CLIFF
            zb = tile_world_z(model.map, *edge.tile_b) + TS05_DEBUG_Z_CLIFF
            segments.append(((ax, ay, za), (bx, by, zb)))
            cliff_segments += 1
        _add_line_mesh_object(
            f"TS05_front{front.front_id}_cliff_edges",
            segments,
            cliff_mat,
            cliff_coll,
        )

        if front.upper is not None:
            _add_hex_tile_outlines(
                f"TS05_front{front.front_id}_upper_tiles",
                front.upper.band_tiles,
                model,
                front.upper_color_rgb,
                TS05_DEBUG_Z_UPPER,
                upper_coll,
            )
            side = front.upper
            _add_anchor_points(
                f"TS05_front{front.front_id}_upper_centers",
                side.center_anchors,
                (1.0, 1.0, 0.2),
                anchor_coll,
            )
            _add_anchor_points(
                f"TS05_front{front.front_id}_upper_interior",
                side.interior_anchors,
                (0.2, 0.95, 1.0),
                anchor_coll,
            )
            _add_anchor_points(
                f"TS05_front{front.front_id}_upper_rim",
                side.rim_anchors,
                (1.0, 0.2, 1.0),
                anchor_coll,
                size=0.05,
            )
            _add_anchor_points(
                f"TS05_front{front.front_id}_upper_discarded",
                side.discarded_anchors,
                (1.0, 0.25, 0.15),
                anchor_coll,
                size=0.025,
            )
            _add_anchor_points(
                f"TS05_front{front.front_id}_upper_used_tps",
                side.used_anchors,
                (0.3, 1.0, 0.35),
                anchor_coll,
                size=0.035,
            )

        if front.lower is not None:
            _add_hex_tile_outlines(
                f"TS05_front{front.front_id}_lower_tiles",
                front.lower.band_tiles,
                model,
                front.lower_color_rgb,
                TS05_DEBUG_Z_LOWER,
                lower_coll,
            )
            side = front.lower
            _add_anchor_points(
                f"TS05_front{front.front_id}_lower_centers",
                side.center_anchors,
                (1.0, 1.0, 0.2),
                anchor_coll,
            )
            _add_anchor_points(
                f"TS05_front{front.front_id}_lower_interior",
                side.interior_anchors,
                (0.2, 0.95, 1.0),
                anchor_coll,
            )
            _add_anchor_points(
                f"TS05_front{front.front_id}_lower_rim",
                side.rim_anchors,
                (1.0, 0.2, 1.0),
                anchor_coll,
                size=0.05,
            )
            _add_anchor_points(
                f"TS05_front{front.front_id}_lower_discarded",
                side.discarded_anchors,
                (1.0, 0.25, 0.15),
                anchor_coll,
                size=0.025,
            )
            _add_anchor_points(
                f"TS05_front{front.front_id}_lower_used_tps",
                side.used_anchors,
                (0.3, 1.0, 0.35),
                anchor_coll,
                size=0.035,
            )

    object_count = _count_collection_objects(root)
    objects_created = len(bpy.data.objects) - objects_before
    if object_count == 0 and export.fronts:
        if cliff_segments == 0:
            empty_reasons.append("no_cliff_edge_segments")
        else:
            empty_reasons.append("mesh_objects_not_created")

    print(
        "[TS05 debug overlay] collection="
        f"{TS05_DEBUG_COLLECTION_NAME} fronts={len(export.fronts)} "
        f"objects={object_count} scene_root_linked=True "
        "anchor colors: yellow=centers cyan=interior magenta=rim "
        "orange=discarded green=used_tps"
    )
    return {
        "front_count": len(export.fronts),
        "cliff_edge_segments": cliff_segments,
        "object_count": object_count,
        "objects_created": objects_created,
        "empty_reason": ";".join(empty_reasons) if empty_reasons else "",
    }
