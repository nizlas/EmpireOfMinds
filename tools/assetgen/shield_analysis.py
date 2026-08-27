"""Automated structural validation of a shield candidate GLB.

What this module CAN decide: whether the mesh parses, how big it is, whether a
rear protrusion exists, whether that protrusion is bar-shaped, and how much empty
space sits between the bar and the shield body.

What it explicitly CANNOT decide, and never claims: whether the result looks
right. A painted-on handle that happens to be modelled as a shallow ridge can
pass every numeric test here while being useless in the hand, so every verdict
carries `NEEDS_USER_VISUAL_REVIEW` and the classification is never
"production approved".

Geometry is measured in GLB model units. Because a Meshy export has no reliable
real-world scale, hand-fit judgements are made on RATIOS against the shield's own
width, and absolute millimetres are reported only against an explicitly stated
assumed physical width.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import numpy as np

from .glb_reader import GlbDocument, GlbParseError, load_glb
from .manifest import VISUAL_PENDING
from .mesh_metrics import (
    Frame,
    component_report,
    connected_components,
    degenerate_triangle_mask,
    label_components,
    principal_frame,
    suggested_weld_epsilon,
    triangle_areas,
    weld_labels,
)

#: Classifications this validator may emit.
HANDHELD_CANDIDATE = "HANDHELD_CANDIDATE"
FOREARM_FALLBACK_ONLY = "FOREARM_FALLBACK_ONLY"
NO_READABLE_HANDLE = "NO_READABLE_HANDLE"
REMESH_DESTROYED_HANDLE = "REMESH_DESTROYED_HANDLE"
NEEDS_USER_VISUAL_REVIEW = "NEEDS_USER_VISUAL_REVIEW"
UNPARSEABLE = "UNPARSEABLE"

#: A typical round wooden shield is ~0.60 m across. Only used to translate the
#: dimensionless ratios into millimetres for human reading.
ASSUMED_SHIELD_WIDTH_M = 0.60

#: Anthropometric requirements, expressed as a fraction of shield width so they
#: survive any export scale. Derived from a ~0.60 m shield: >=30 mm of finger
#: clearance, >=100 mm of grip length, 25-50 mm grip diameter.
MIN_CLEARANCE_RATIO = 0.050
MIN_HANDLE_LENGTH_RATIO = 0.165
MIN_HANDLE_DIAMETER_RATIO = 0.035
MAX_HANDLE_DIAMETER_RATIO = 0.090
#: A grip bar must run across the shield face, not stick straight out of it.
MIN_BAR_IN_PLANE = 0.70
#: A bar is elongated; a boss or a strap pad is not.
MIN_BAR_ELONGATION = 2.0

#: Fraction of the in-plane span a slice must cover to count as shield body.
#: Used only for the informational plate-slab figure, never for classification.
PLATE_FOOTPRINT_FRACTION = 0.45
SLICE_COUNT = 48

#: In-plane grid resolution for the depth-gap search. One cell is the smallest
#: standoff footprint the scan can resolve, so it is reported as a detection limit.
GRID_RESOLUTION = 24
#: A standoff must occupy at least this many adjacent cells to be a candidate,
#: which suppresses isolated single-cell artifacts at the shield rim.
MIN_VOID_CLUSTER_CELLS = 3


@dataclass(frozen=True)
class HandleCandidate:
    """A region where geometry stands off the shield body with a hand-sized void.

    Found by looking for a DEPTH GAP: at a given point on the shield face, the
    sorted depths of nearby surface samples split into a body layer and a
    further-out layer with empty space between them. That void is the only thing
    a hand can actually occupy, which is why it - and not raw protrusion depth -
    decides the classification.
    """

    cluster_index: int
    cell_count: int
    sample_count: int
    centroid: np.ndarray
    bar_axis: np.ndarray
    handle_length: float
    handle_footprint_width: float
    handle_diameter: float
    thickness_along_normal: float
    protrusion_depth: float
    estimated_clearance: float
    in_plane_alignment: float
    elongation: float
    side: str

    def to_dict(self, width: float, assumed_width_m: float) -> dict:
        scale_mm = (assumed_width_m / width * 1000.0) if width > 0 else 0.0
        return {
            "cluster_index": self.cluster_index,
            "side": self.side,
            "cell_count": self.cell_count,
            "sample_count": self.sample_count,
            "centroid_model_units": [float(v) for v in self.centroid],
            "bar_axis_model_units": [float(v) for v in self.bar_axis],
            "handle_length_model_units": float(self.handle_length),
            "handle_footprint_width_model_units": float(self.handle_footprint_width),
            "handle_diameter_model_units": float(self.handle_diameter),
            "thickness_along_normal_model_units": float(self.thickness_along_normal),
            "protrusion_depth_model_units": float(self.protrusion_depth),
            "estimated_clearance_model_units": float(self.estimated_clearance),
            "handle_length_ratio": _ratio(self.handle_length, width),
            "handle_diameter_ratio": _ratio(self.handle_diameter, width),
            "clearance_ratio": _ratio(self.estimated_clearance, width),
            "in_plane_alignment": float(self.in_plane_alignment),
            "elongation": float(self.elongation),
            "estimated_mm_at_assumed_width": {
                "assumed_shield_width_m": assumed_width_m,
                "handle_length_mm": round(self.handle_length * scale_mm, 1),
                "handle_diameter_mm": round(self.handle_diameter * scale_mm, 1),
                "clearance_mm": round(self.estimated_clearance * scale_mm, 1),
            },
        }


def analyze_shield_file(
    path: Path, *, assumed_width_m: float = ASSUMED_SHIELD_WIDTH_M
) -> dict:
    """Full structural report for one candidate file. Never raises on bad input."""
    try:
        document = load_glb(path)
    except (GlbParseError, ValueError, OSError) as exc:
        return {
            "file": str(path),
            "parsed": False,
            "parse_error": str(exc),
            "classification": UNPARSEABLE,
            "required_follow_up": [NEEDS_USER_VISUAL_REVIEW],
            "visual_status": VISUAL_PENDING,
            "production_approved": False,
        }
    return analyze_shield_document(document, assumed_width_m=assumed_width_m)


def analyze_shield_document(
    document: GlbDocument, *, assumed_width_m: float = ASSUMED_SHIELD_WIDTH_M
) -> dict:
    vertices, triangles = document.merged_geometry()
    report: dict = {
        "file": str(document.path),
        "parsed": True,
        "file_size_bytes": document.file_size_bytes,
        "generator": document.generator,
        "gltf_version": document.gltf_version,
        "parse_warnings": list(document.parse_warnings),
        "mesh_count": len(document.gltf.get("meshes", [])),
        "surface_count": len(document.primitives),
        "node_names": document.node_names,
        "triangle_count": document.triangle_count,
        "vertex_count": document.vertex_count,
        "materials": document.material_summary(),
        "embedded_image_count": len(document.images),
        "has_skin": bool(document.skins),
        "animation_names": document.animation_names(),
        "required_follow_up": [NEEDS_USER_VISUAL_REVIEW],
        # Structural analysis can only ever produce a candidate. Both flags are
        # constants here so that no code path can quietly promote a mesh to
        # approved without a human looking at it.
        "visual_status": VISUAL_PENDING,
        "production_approved": False,
    }

    if triangles.shape[0] == 0:
        report["classification"] = UNPARSEABLE
        report["classification_reason"] = "no triangles were found in the document"
        return report

    low, high = vertices.min(axis=0), vertices.max(axis=0)
    report["bounds_min"] = [float(v) for v in low]
    report["bounds_max"] = [float(v) for v in high]
    report["aabb_extents"] = [float(v) for v in (high - low)]

    epsilon = suggested_weld_epsilon(vertices)
    labels = weld_labels(vertices, epsilon)
    label_count = int(labels.max()) + 1 if labels.size else 0
    components = connected_components(triangles, labels, label_count)
    report["weld_epsilon"] = float(epsilon)
    report["welded_vertex_count"] = label_count
    report["disconnected_component_count"] = int(np.unique(components).size)
    report["components"] = component_report(vertices, triangles, components)

    degenerate = degenerate_triangle_mask(vertices, triangles)
    areas = triangle_areas(vertices, triangles)
    report["degenerate_triangle_count"] = int(degenerate.sum())
    report["total_surface_area"] = float(areas.sum())
    report["thin_geometry"] = _thin_geometry_report(report["components"])

    body = _body_analysis(vertices, triangles, labels, label_count, components)
    report["shield_body"] = body["summary"]

    handle = _handle_analysis(body, assumed_width_m=assumed_width_m)
    report.update(handle)
    return report


# --------------------------------------------------------------------------- body


def _body_analysis(
    vertices: np.ndarray,
    triangles: np.ndarray,
    labels: np.ndarray,
    label_count: int,
    components: np.ndarray,
) -> dict:
    """Identify the plate, its normal, and the geometry sitting behind it."""
    areas = triangle_areas(vertices, triangles)
    largest_component = _largest_component_id(components, areas)
    body_mask = components == largest_component

    welded_points = _welded_positions(vertices, labels, label_count)

    # The frame comes from the WHOLE mesh, not the largest component. Exporters
    # split a shield face into several surfaces, and a single flat sub-surface
    # would otherwise define a near-zero-thickness "plate" that turns the
    # shield's own thickness into a fake protrusion.
    frame = principal_frame(welded_points)
    normal = frame.axes[2]
    in_plane_width = float(frame.extents[0])
    in_plane_height = float(frame.extents[1])

    local = frame.project(welded_points)
    along_normal = local[:, 2]

    slab = _plate_slab(local, along_normal)
    summary = {
        "body_component_id": int(largest_component),
        "body_triangle_count": int(body_mask.sum()),
        "body_surface_area": float(areas[body_mask].sum()),
        "plate_frame_center": [float(v) for v in frame.center],
        "plate_normal": [float(v) for v in normal],
        "in_plane_axis_major": [float(v) for v in frame.axes[0]],
        "in_plane_axis_minor": [float(v) for v in frame.axes[1]],
        "width_model_units": in_plane_width,
        "height_model_units": in_plane_height,
        "thickness_model_units": float(frame.extents[2]),
        "plate_slab_along_normal": [float(slab[0]), float(slab[1])],
        "plate_slab_thickness": float(slab[1] - slab[0]),
    }
    samples = surface_samples(
        vertices, triangles, target_spacing=in_plane_width / (2.0 * GRID_RESOLUTION)
    )
    summary["surface_sample_count"] = int(samples["centroids"].shape[0])
    summary["winding_was_inverted"] = bool(samples["winding_was_inverted"])
    summary["enclosed_volume_estimate"] = float(samples["signed_volume"])

    return {
        "summary": summary,
        "frame": frame,
        "welded_points": welded_points,
        "local": local,
        "slab": slab,
        "width": in_plane_width,
        "samples": samples,
    }


def _largest_component_id(components: np.ndarray, areas: np.ndarray) -> int:
    best_id, best_area = 0, -1.0
    for component in np.unique(components):
        area = float(areas[components == component].sum())
        if area > best_area:
            best_id, best_area = int(component), area
    return best_id


def _welded_positions(vertices: np.ndarray, labels: np.ndarray, label_count: int) -> np.ndarray:
    """One representative position per welded label."""
    if label_count == 0:
        return vertices
    representatives = np.zeros((label_count, 3))
    seen = np.zeros(label_count, dtype=bool)
    for index, label in enumerate(labels):
        if not seen[label]:
            representatives[label] = vertices[index]
            seen[label] = True
    return representatives[seen]


def _plate_slab(local: np.ndarray, along_normal: np.ndarray) -> tuple[float, float]:
    """Find the slab along the normal that carries the wide plate footprint.

    A slice belongs to the plate when it spans a large fraction of the shield's
    in-plane extent. A grip bar is narrow, so its slices fail that test - which is
    exactly how the bar becomes visible as a protrusion instead of being averaged
    into the plate.
    """
    lo, hi = float(along_normal.min()), float(along_normal.max())
    if hi - lo <= 0:
        return lo, hi

    span_major = float(local[:, 0].max() - local[:, 0].min()) or 1.0
    span_minor = float(local[:, 1].max() - local[:, 1].min()) or 1.0
    edges = np.linspace(lo, hi, SLICE_COUNT + 1)
    footprints = np.zeros(SLICE_COUNT)

    for index in range(SLICE_COUNT):
        in_slice = (along_normal >= edges[index]) & (along_normal <= edges[index + 1])
        if in_slice.sum() < 3:
            continue
        slice_points = local[in_slice]
        major = float(slice_points[:, 0].max() - slice_points[:, 0].min()) / span_major
        minor = float(slice_points[:, 1].max() - slice_points[:, 1].min()) / span_minor
        footprints[index] = min(major, minor)

    plate = footprints >= PLATE_FOOTPRINT_FRACTION
    if not plate.any():
        return lo, hi

    peak = int(np.argmax(footprints))
    start = peak
    while start - 1 >= 0 and plate[start - 1]:
        start -= 1
    end = peak
    while end + 1 < SLICE_COUNT and plate[end + 1]:
        end += 1
    return float(edges[start]), float(edges[end + 1])


# ------------------------------------------------------------------------- handle


def _handle_analysis(body: dict, *, assumed_width_m: float) -> dict:
    frame: Frame = body["frame"]
    local: np.ndarray = body["local"]
    slab_lo, slab_hi = body["slab"]
    width: float = body["width"]
    along_normal = local[:, 2]

    # Dense surface sampling puts samples exactly on the surfaces, so the detector
    # no longer needs a large noise margin. The threshold is kept well BELOW the
    # anthropometric limits on purpose: detection should surface a small void and
    # let the classifier reject it with a measured number, rather than hide it.
    # It must not be derived from the model's total depth, which already includes
    # the handle assembly and would scale itself out of finding a deep grip.
    gap_threshold = max(0.005 * width, 1e-9)

    gaps = _depth_gap_cells(
        frame=frame,
        samples=body["samples"],
        width=width,
        height=float(frame.extents[1]),
    )
    evaluated: dict[str, list[HandleCandidate]] = {
        side: _handle_candidates(
            gaps=gaps, side=side, gap_threshold=gap_threshold, frame=frame, width=width
        )
        for side in ("rear", "front")
    }

    chosen_side = _choose_side(evaluated, width)
    candidates = evaluated[chosen_side]
    side_sign = -1.0 if chosen_side == "rear" else 1.0
    best = _best_handle(candidates, width)

    result: dict = {
        "protrusion": {
            "detection_method": (
                "per-cell depth-gap search over dense surface samples: a void counts only when "
                "both bounding surfaces face into it, which separates an open channel from the "
                "shield's own solid interior"
            ),
            "side_label_meaning": (
                "'rear' and 'front' name the negative and positive directions of the fitted "
                "plate normal. The normal's sign is arbitrary geometry, NOT the shield's design "
                "front: use suggested_markers.shield_forward, which is oriented away from the "
                "grip side, and confirm it against the reference image visually."
            ),
            "minimum_detectable_footprint_model_units": [
                gaps["cell_size_u"] * MIN_VOID_CLUSTER_CELLS,
                gaps["cell_size_v"],
            ],
            "grid_cells_evaluated": gaps["cells_evaluated"],
            "grid_resolution": gaps["resolution"],
            "gap_threshold_model_units": gap_threshold,
            "rear_gap_cell_count": int(gaps["rear_cell_count"]),
            "front_gap_cell_count": int(gaps["front_cell_count"]),
            "max_rear_gap_model_units": float(gaps["max_rear_gap"]),
            "max_front_gap_model_units": float(gaps["max_front_gap"]),
            "plate_slab_along_normal": [float(slab_lo), float(slab_hi)],
            "selected_side": chosen_side,
            "selected_side_normal_sign": side_sign,
            "selected_side_reason": (
                "side carries the best grip-shaped standoff cluster"
                if _passes_grip_gates(best, width)
                else "no side passed the grip gates; the side with the larger depth gap is reported"
            ),
        }
    }

    result["handle_candidates"] = [c.to_dict(width, assumed_width_m) for c in candidates]
    result["handle_candidates_other_side"] = [
        c.to_dict(width, assumed_width_m)
        for c in evaluated["front" if chosen_side == "rear" else "rear"]
    ]
    protrusion_depth_total = best.protrusion_depth if best is not None else 0.0
    result["best_handle_candidate"] = (
        best.to_dict(width, assumed_width_m) if best is not None else None
    )
    result["plate_slab_note"] = (
        "The plate slab is the depth band whose in-plane footprint covers at least "
        f"{PLATE_FOOTPRINT_FRACTION:.0%} of the shield span. On a domed or curved shield this "
        "band is thinner than the total thickness, so protrusion depth alone never proves a "
        "rear structure - only measured standoff clearance does."
    )
    result["handle_thresholds"] = {
        "min_clearance_ratio": MIN_CLEARANCE_RATIO,
        "min_handle_length_ratio": MIN_HANDLE_LENGTH_RATIO,
        "handle_diameter_ratio_range": [MIN_HANDLE_DIAMETER_RATIO, MAX_HANDLE_DIAMETER_RATIO],
        "min_in_plane_alignment": MIN_BAR_IN_PLANE,
        "min_elongation": MIN_BAR_ELONGATION,
    }

    classification, reason, checks = _classify(
        best,
        width,
        protrusion_depth_total,
        void_cell_count=int(gaps[f"{chosen_side}_cell_count"]),
    )
    result["handle_checks"] = checks
    result["classification"] = classification
    result["classification_reason"] = reason
    result["suggested_markers"] = _suggested_markers(frame, best, side_sign, body)
    result["required_follow_up"] = [NEEDS_USER_VISUAL_REVIEW]
    return result


def surface_samples(
    vertices: np.ndarray, triangles: np.ndarray, *, target_spacing: float | None = None
) -> dict:
    """Dense surface point samples with outward normals.

    Sampling the SURFACE rather than the vertices is what makes void detection
    independent of how coarsely the provider tessellated the model: a 1000-triangle
    export and a 100 000-triangle export produce the same measurement density, so
    a small grip bar cannot be missed just because it has few vertices.

    The winding is normalised first, because which way a surface faces is the
    signal that separates an open channel from the shield's solid interior. For a
    closed mesh the signed volume must be positive; a negative value means the
    mesh is wound inside-out and every normal is flipped once, globally.
    """
    a = vertices[triangles[:, 0]]
    b = vertices[triangles[:, 1]]
    c = vertices[triangles[:, 2]]
    raw_normals = np.cross(b - a, c - a)
    lengths = np.linalg.norm(raw_normals, axis=1)
    safe = np.where(lengths > 0, lengths, 1.0)
    normals = raw_normals / safe[:, None]

    signed_volume = float(np.einsum("ij,ij->i", a, np.cross(b, c)).sum() / 6.0)
    flipped = signed_volume < 0.0
    if flipped:
        normals = -normals

    if target_spacing is None or target_spacing <= 0:
        points = (a + b + c) / 3.0
        point_normals = normals
        subdivisions_used = 1
    else:
        points, point_normals, subdivisions_used = _barycentric_samples(
            a, b, c, normals, target_spacing
        )

    return {
        "centroids": points,
        "normals": point_normals,
        "triangle_count": int(triangles.shape[0]),
        "sample_count": int(points.shape[0]),
        "max_subdivisions": subdivisions_used,
        "signed_volume": abs(signed_volume),
        "winding_was_inverted": flipped,
        "degenerate_normal_count": int((lengths <= 0).sum()),
    }


#: Cap on per-triangle barycentric subdivision, bounding total sample count.
MAX_TRIANGLE_SUBDIVISIONS = 6


def _barycentric_samples(
    a: np.ndarray, b: np.ndarray, c: np.ndarray, normals: np.ndarray, target_spacing: float
) -> tuple[np.ndarray, np.ndarray, int]:
    """Spread sample points across each triangle so no cell is starved."""
    edges = np.maximum.reduce(
        [
            np.linalg.norm(b - a, axis=1),
            np.linalg.norm(c - b, axis=1),
            np.linalg.norm(a - c, axis=1),
        ]
    )
    levels = np.clip(
        np.ceil(edges / target_spacing).astype(int), 1, MAX_TRIANGLE_SUBDIVISIONS
    )

    point_blocks: list[np.ndarray] = []
    normal_blocks: list[np.ndarray] = []
    for level in np.unique(levels):
        mask = levels == level
        weights = _barycentric_lattice(int(level))
        # (T, 1, 3) x (1, S, 1) broadcast into (T, S, 3) sample positions.
        block = (
            a[mask][:, None, :] * weights[None, :, 0:1]
            + b[mask][:, None, :] * weights[None, :, 1:2]
            + c[mask][:, None, :] * weights[None, :, 2:3]
        )
        point_blocks.append(block.reshape(-1, 3))
        normal_blocks.append(
            np.repeat(normals[mask], weights.shape[0], axis=0)
        )
    return (
        np.concatenate(point_blocks),
        np.concatenate(normal_blocks),
        int(levels.max()),
    )


def _barycentric_lattice(level: int) -> np.ndarray:
    """Barycentric weights of the centroids of a triangle split `level` ways."""
    if level <= 1:
        return np.array([[1 / 3, 1 / 3, 1 / 3]])
    weights = []
    step = 1.0 / level
    for i in range(level):
        for j in range(level - i):
            # Upright sub-triangle centroid.
            weights.append(
                [
                    (i + 1 / 3) * step,
                    (j + 1 / 3) * step,
                    1.0 - (i + 1 / 3) * step - (j + 1 / 3) * step,
                ]
            )
            if j < level - i - 1:
                # Inverted sub-triangle centroid.
                weights.append(
                    [
                        (i + 2 / 3) * step,
                        (j + 2 / 3) * step,
                        1.0 - (i + 2 / 3) * step - (j + 2 / 3) * step,
                    ]
                )
    return np.array(weights)


def _depth_gap_cells(
    *,
    frame: Frame,
    samples: dict,
    width: float,
    height: float,
) -> dict:
    """Search every in-plane cell for an OPEN empty span in depth.

    A gap between two surfaces is only reachable by a hand when both bounding
    surfaces FACE INTO it. When they face away from each other the gap is the
    solid interior of the shield itself, which is how a plain plate would
    otherwise be misread as having a grip channel behind it.
    """
    local = frame.project(samples["centroids"])
    facing = samples["normals"] @ frame.axes[2]
    count = local.shape[0]
    if count < 16:
        return _empty_gap_result(0)

    # Fixed resolution: surface sampling already guarantees occupancy, so the grid
    # no longer has to compensate for a coarse mesh.
    resolution = GRID_RESOLUTION
    u, v, w = local[:, 0], local[:, 1], local[:, 2]
    u_edges = np.linspace(u.min(), u.max(), resolution + 1)
    v_edges = np.linspace(v.min(), v.max(), resolution + 1)
    u_bin = np.clip(np.digitize(u, u_edges) - 1, 0, resolution - 1)
    v_bin = np.clip(np.digitize(v, v_edges) - 1, 0, resolution - 1)

    records: list[dict] = []
    cells_evaluated = 0
    enclosed_interior_cells = 0
    max_rear_gap = 0.0
    max_front_gap = 0.0

    for cell_u in range(resolution):
        for cell_v in range(resolution):
            in_cell = (u_bin == cell_u) & (v_bin == cell_v)
            sample_count = int(in_cell.sum())
            if sample_count < 3:
                continue
            cells_evaluated += 1

            depths = w[in_cell]
            cell_facing = facing[in_cell]
            order = np.argsort(depths)
            depths = depths[order]
            cell_facing = cell_facing[order]

            best_gap = 0.0
            best_pair: tuple[float, float] | None = None
            saw_enclosed = False
            for index in range(depths.size - 1):
                gap = float(depths[index + 1] - depths[index])
                if gap <= 0:
                    continue
                lower_faces_up = cell_facing[index] > 0
                upper_faces_down = cell_facing[index + 1] < 0
                if lower_faces_up and upper_faces_down:
                    if gap > best_gap:
                        best_gap = gap
                        best_pair = (float(depths[index]), float(depths[index + 1]))
                elif cell_facing[index] < 0 and cell_facing[index + 1] > 0:
                    saw_enclosed = True

            if saw_enclosed:
                enclosed_interior_cells += 1
            if best_pair is None:
                continue

            void_lo, void_hi = best_pair
            void_centre = (void_lo + void_hi) / 2.0
            side = "rear" if void_centre < 0 else "front"
            if side == "rear":
                # Standoff structure lies below the void; the body is above it.
                standoff_edge, body_edge = void_lo, void_hi
                standoff_extreme = float(depths.min())
                max_rear_gap = max(max_rear_gap, best_gap)
            else:
                standoff_edge, body_edge = void_hi, void_lo
                standoff_extreme = float(depths.max())
                max_front_gap = max(max_front_gap, best_gap)

            records.append(
                {
                    "cell_u": cell_u,
                    "cell_v": cell_v,
                    "u": float((u_edges[cell_u] + u_edges[cell_u + 1]) / 2.0),
                    "v": float((v_edges[cell_v] + v_edges[cell_v + 1]) / 2.0),
                    "gap": best_gap,
                    "side": side,
                    "body_edge": body_edge,
                    "standoff_edge": standoff_edge,
                    "standoff_extreme": standoff_extreme,
                    "sample_count": sample_count,
                }
            )

    return {
        "records": records,
        "resolution": resolution,
        "cells_evaluated": cells_evaluated,
        "enclosed_interior_cells": enclosed_interior_cells,
        "cell_size_u": float((u.max() - u.min()) / resolution) if resolution else 0.0,
        "cell_size_v": float((v.max() - v.min()) / resolution) if resolution else 0.0,
        "rear_cell_count": sum(1 for r in records if r["side"] == "rear"),
        "front_cell_count": sum(1 for r in records if r["side"] == "front"),
        "max_rear_gap": max_rear_gap,
        "max_front_gap": max_front_gap,
        "winding_was_inverted": bool(samples["winding_was_inverted"]),
        "width": width,
        "height": height,
    }


def _empty_gap_result(resolution: int) -> dict:
    return {
        "records": [],
        "resolution": resolution,
        "cells_evaluated": 0,
        "enclosed_interior_cells": 0,
        "cell_size_u": 0.0,
        "cell_size_v": 0.0,
        "rear_cell_count": 0,
        "front_cell_count": 0,
        "max_rear_gap": 0.0,
        "max_front_gap": 0.0,
        "winding_was_inverted": False,
        "width": 0.0,
        "height": 0.0,
    }


def _handle_candidates(
    *, gaps: dict, side: str, gap_threshold: float, frame: Frame, width: float
) -> list[HandleCandidate]:
    """Group qualifying void cells into grip-bar candidates."""
    records = [
        r for r in gaps["records"] if r["side"] == side and r["gap"] >= gap_threshold
    ]
    if not records:
        return []

    clusters = _cluster_cells(records)
    cell_u = gaps["cell_size_u"] or 1e-9
    cell_v = gaps["cell_size_v"] or 1e-9

    candidates: list[HandleCandidate] = []
    for index, cluster in enumerate(clusters):
        if len(cluster) < MIN_VOID_CLUSTER_CELLS:
            continue
        footprint = np.array([[r["u"], r["v"]] for r in cluster])
        gap_values = np.array([r["gap"] for r in cluster])
        standoff_edges = np.array([r["standoff_edge"] for r in cluster])
        standoff_extremes = np.array([r["standoff_extreme"] for r in cluster])
        body_edges = np.array([r["body_edge"] for r in cluster])

        centre_2d = footprint.mean(axis=0)
        centred = footprint - centre_2d
        if centred.shape[0] >= 2 and np.any(np.abs(centred) > 0):
            _u_svd, _s, vt = np.linalg.svd(centred, full_matrices=False)
            long_axis_2d = vt[0]
            short_axis_2d = vt[1] if vt.shape[0] > 1 else np.array([-vt[0][1], vt[0][0]])
        else:
            long_axis_2d = np.array([1.0, 0.0])
            short_axis_2d = np.array([0.0, 1.0])

        along = centred @ long_axis_2d
        across = centred @ short_axis_2d
        # Cell centres sample the footprint, so one cell width is added back to
        # avoid systematically underreporting a bar that spans few cells.
        cell_diagonal = float(np.hypot(cell_u, cell_v))
        handle_length = float(along.max() - along.min()) + cell_diagonal
        footprint_width = float(across.max() - across.min()) + cell_diagonal

        bar_thickness = float(np.abs(standoff_extremes - standoff_edges).max())
        clearance = float(np.median(gap_values))
        body_edge = float(np.median(body_edges))
        protrusion_depth = float(np.abs(standoff_extremes - body_edge).max())

        diameter = (footprint_width + bar_thickness) / 2.0
        elongation = handle_length / max(diameter, 1e-12)

        bar_axis_local = np.array([long_axis_2d[0], long_axis_2d[1], 0.0])
        bar_axis_world = bar_axis_local @ frame.axes
        centre_local = np.array(
            [
                float(centre_2d[0]),
                float(centre_2d[1]),
                float(np.median((standoff_edges + standoff_extremes) / 2.0)),
            ]
        )
        centroid_world = frame.center + centre_local @ frame.axes

        candidates.append(
            HandleCandidate(
                cluster_index=index,
                cell_count=len(cluster),
                sample_count=int(sum(r["sample_count"] for r in cluster)),
                centroid=centroid_world,
                bar_axis=bar_axis_world / (np.linalg.norm(bar_axis_world) or 1.0),
                handle_length=handle_length,
                handle_footprint_width=footprint_width,
                handle_diameter=diameter,
                thickness_along_normal=bar_thickness,
                protrusion_depth=protrusion_depth,
                estimated_clearance=clearance,
                # The axis is in-plane by construction; reported so the gate stays
                # visible rather than silently trivial.
                in_plane_alignment=1.0,
                elongation=elongation,
                side=side,
            )
        )
    candidates.sort(key=lambda c: -c.estimated_clearance)
    return candidates


def _cluster_cells(records: list[dict]) -> list[list[dict]]:
    """4-neighbour connected groups of void cells."""
    index_by_cell = {(r["cell_u"], r["cell_v"]): i for i, r in enumerate(records)}
    parent = list(range(len(records)))

    def find(item: int) -> int:
        while parent[item] != item:
            parent[item] = parent[parent[item]]
            item = parent[item]
        return item

    for (cell_u, cell_v), index in index_by_cell.items():
        for neighbour in ((cell_u + 1, cell_v), (cell_u, cell_v + 1)):
            other = index_by_cell.get(neighbour)
            if other is not None:
                a, b = find(index), find(other)
                if a != b:
                    parent[b] = a

    grouped: dict[int, list[dict]] = {}
    for index, record in enumerate(records):
        grouped.setdefault(find(index), []).append(record)
    return list(grouped.values())


def _passes_grip_gates(candidate: HandleCandidate | None, width: float) -> bool:
    if candidate is None:
        return False
    return (
        _ratio(candidate.estimated_clearance, width) >= MIN_CLEARANCE_RATIO
        and _ratio(candidate.handle_length, width) >= MIN_HANDLE_LENGTH_RATIO
        and candidate.in_plane_alignment >= MIN_BAR_IN_PLANE
        and candidate.elongation >= MIN_BAR_ELONGATION
    )


def _best_handle(candidates: list[HandleCandidate], width: float) -> HandleCandidate | None:
    """Pick the most grip-like candidate, not merely the biggest."""
    if not candidates:
        return None
    return max(
        candidates,
        key=lambda c: (1 if _passes_grip_gates(c, width) else 0, c.estimated_clearance),
    )


def _choose_side(evaluated: dict[str, list[HandleCandidate]], width: float) -> str:
    """Prefer the side with a real grip; otherwise the side with the larger void."""
    passing = [
        side
        for side, candidates in evaluated.items()
        if _passes_grip_gates(_best_handle(candidates, width), width)
    ]
    if len(passing) == 1:
        return passing[0]

    def best_clearance(side: str) -> float:
        best = _best_handle(evaluated[side], width)
        return best.estimated_clearance if best is not None else 0.0

    # Both sides grippable should never happen on a shield; report the roomier
    # one and let visual review settle it. Same tie-break when neither passes.
    pool = passing if passing else list(evaluated)
    return max(sorted(pool), key=best_clearance)


def _classify(
    best: HandleCandidate | None,
    width: float,
    protrusion_depth: float,
    *,
    void_cell_count: int,
) -> tuple[str, str, dict]:
    if best is None:
        return (
            NO_READABLE_HANDLE,
            (
                "No in-plane cell showed an empty depth span large enough to be a standoff, so "
                "nothing on this shield has space behind it for a hand."
                if void_cell_count == 0
                else (
                    f"{void_cell_count} cell(s) showed a depth gap but none grouped into an "
                    "analysable standoff cluster."
                )
            ),
            {},
        )

    clearance_ratio = _ratio(best.estimated_clearance, width)
    length_ratio = _ratio(best.handle_length, width)
    diameter_ratio = _ratio(best.handle_diameter, width)
    checks = {
        "clearance_ratio": {
            "value": clearance_ratio,
            "required_min": MIN_CLEARANCE_RATIO,
            "pass": clearance_ratio >= MIN_CLEARANCE_RATIO,
        },
        "handle_length_ratio": {
            "value": length_ratio,
            "required_min": MIN_HANDLE_LENGTH_RATIO,
            "pass": length_ratio >= MIN_HANDLE_LENGTH_RATIO,
        },
        "handle_diameter_ratio": {
            "value": diameter_ratio,
            "required_range": [MIN_HANDLE_DIAMETER_RATIO, MAX_HANDLE_DIAMETER_RATIO],
            "pass": MIN_HANDLE_DIAMETER_RATIO <= diameter_ratio <= MAX_HANDLE_DIAMETER_RATIO,
        },
        "in_plane_alignment": {
            "value": best.in_plane_alignment,
            "required_min": MIN_BAR_IN_PLANE,
            "pass": best.in_plane_alignment >= MIN_BAR_IN_PLANE,
        },
        "elongation": {
            "value": best.elongation,
            "required_min": MIN_BAR_ELONGATION,
            "pass": best.elongation >= MIN_BAR_ELONGATION,
        },
    }

    grip_gates = ("clearance_ratio", "handle_length_ratio", "in_plane_alignment", "elongation")
    if all(checks[name]["pass"] for name in grip_gates):
        return (
            HANDHELD_CANDIDATE,
            (
                f"A bar-shaped rear cluster stands off the plate with clearance ratio "
                f"{clearance_ratio:.3f} and length ratio {length_ratio:.3f}. Whether the bar is "
                "real rigid geometry rather than a shallow ridge still requires visual review."
            ),
            checks,
        )

    failed = [name for name in grip_gates if not checks[name]["pass"]]

    # A forearm fallback still needs a structure that genuinely stands OFF the
    # plate. Raw protrusion depth is not enough: on a domed shield the plate's own
    # curvature protrudes past any flat slab, and treating that as a strap region
    # would report a forearm fallback for a plain disc with nothing on the back.
    if clearance_ratio >= MIN_CLEARANCE_RATIO * 0.5:
        return (
            FOREARM_FALLBACK_ONLY,
            (
                f"Rear geometry stands off the plate (clearance ratio {clearance_ratio:.3f}) and "
                "could carry a forearm contact region, but it fails the hand-grip gates "
                f"({', '.join(failed)}), so it must not be classified as a full hand-held shield."
            ),
            checks,
        )
    return (
        NO_READABLE_HANDLE,
        (
            f"The best rear cluster has clearance ratio {clearance_ratio:.3f}, below the "
            f"{MIN_CLEARANCE_RATIO * 0.5:.3f} needed even for a forearm strap, so no hand or "
            f"forearm can pass behind it. Failed gates: {', '.join(failed)}. "
            f"Measured protrusion depth ratio {_ratio(protrusion_depth, width):.3f} is plate "
            "curvature, not standoff structure."
        ),
        checks,
    )


def _suggested_markers(
    frame: Frame, best: HandleCandidate | None, side_sign: float, body: dict
) -> dict:
    """Diagnostic marker proposals only.

    These are never written as runtime markers by this slice. Confidence is
    reported so a low-confidence proposal cannot be mistaken for a calibration.
    """
    normal = np.asarray(frame.axes[2], dtype=float)
    # shield_forward points away from the hand side, i.e. out of the front face.
    forward = -side_sign * normal
    markers: dict = {
        "shield_forward": {
            "direction_model_units": [float(v) for v in forward],
            "origin_model_units": [float(v) for v in frame.center],
            "confidence": "medium" if best is not None else "low",
            "basis": (
                "outward normal of the plate plane, oriented away from the side carrying "
                "the deeper protrusion"
            ),
        }
    }
    if best is None:
        markers["shield_grip"] = {
            "confidence": "none",
            "basis": "no bar-shaped rear cluster was found",
        }
        markers["forearm_contact"] = {
            "confidence": "none",
            "basis": "no rear grip geometry to anchor a forearm region against",
        }
        return markers

    grip_axis = np.asarray(best.bar_axis, dtype=float)
    markers["shield_grip"] = {
        "origin_model_units": [float(v) for v in best.centroid],
        "axis_model_units": [float(v) for v in grip_axis],
        "estimated_diameter_model_units": float(best.handle_diameter),
        "confidence": "medium",
        "basis": "centroid and principal axis of the bar-shaped rear cluster",
    }
    # Which way the elbow lies is not derivable from the mesh, so both directions
    # along the bar are offered and neither is chosen.
    offset = float(body["width"]) * 0.18
    markers["forearm_contact"] = {
        "candidate_a_model_units": [float(v) for v in (best.centroid + grip_axis * offset)],
        "candidate_b_model_units": [float(v) for v in (best.centroid - grip_axis * offset)],
        "confidence": "low",
        "basis": (
            "offset along the grip axis in both directions; the mesh does not reveal which "
            "side the forearm lies on, so this must not be committed without visual review"
        ),
    }
    return markers


def _thin_geometry_report(components: list[dict]) -> dict:
    """Components whose smallest oriented extent is a tiny fraction of the largest."""
    flagged = []
    for component in components:
        extents = component.get("obb_extents") or [0, 0, 0]
        longest = max(extents) or 1.0
        thinness = min(extents) / longest
        if thinness < 0.02:
            flagged.append(
                {
                    "component_id": component["component_id"],
                    "thinness": round(float(thinness), 6),
                    "obb_extents": extents,
                }
            )
    return {"thin_component_count": len(flagged), "thin_components": flagged}


def _ratio(value: float, width: float) -> float:
    return float(value / width) if width > 0 else 0.0


# ------------------------------------------------------------------ remesh compare


def compare_pre_and_post_remesh(pre_report: dict, post_report: dict) -> dict:
    """Decide whether decimation destroyed the grip the whole interaction needs."""
    pre_class = pre_report.get("classification")
    post_class = post_report.get("classification")
    pre_handle = _first_handle(pre_report)
    post_handle = _first_handle(post_report)

    handle_lost = pre_class == HANDHELD_CANDIDATE and post_class in (
        NO_READABLE_HANDLE,
        FOREARM_FALLBACK_ONLY,
    )
    clearance_pre = (pre_handle or {}).get("clearance_ratio", 0.0)
    clearance_post = (post_handle or {}).get("clearance_ratio", 0.0)
    clearance_collapsed = clearance_pre > 0 and clearance_post < clearance_pre * 0.5

    verdict = REMESH_DESTROYED_HANDLE if (handle_lost or clearance_collapsed) else post_class
    return {
        "pre_remeshed_classification": pre_class,
        "remeshed_classification": post_class,
        "pre_remeshed_triangle_count": pre_report.get("triangle_count"),
        "remeshed_triangle_count": post_report.get("triangle_count"),
        "pre_remeshed_component_count": pre_report.get("disconnected_component_count"),
        "remeshed_component_count": post_report.get("disconnected_component_count"),
        "clearance_ratio_pre": clearance_pre,
        "clearance_ratio_post": clearance_post,
        "handle_lost_by_remesh": bool(handle_lost),
        "clearance_collapsed_by_remesh": bool(clearance_collapsed),
        "verdict": verdict,
        "required_follow_up": [NEEDS_USER_VISUAL_REVIEW],
    }


def _first_handle(report: dict) -> dict | None:
    candidates = report.get("handle_candidates") or []
    return candidates[0] if candidates else None
