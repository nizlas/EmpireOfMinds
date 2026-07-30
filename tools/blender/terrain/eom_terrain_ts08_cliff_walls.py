# Empire of Minds — TS-08 basic cliff-wall geometry helper (Stage 3a, bpy-free).
# Builds presentation wall faces between cut-domain top sheets along Γ (delta > 1).

from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Any, Iterable

from eom_terrain_math_core import (
    DEFAULT_HEX_RADIUS,
    DEFAULT_SURFACE_SUBDIVISIONS,
    handdrawn_to_baseline_axial,
    pos_key,
)
from eom_terrain_ts08_cut_lattice import (
    CutLatticeBuild,
    _neighbor_direction_between,
    _physical_edge_for_neighbor_direction,
    build_cliff_neighbor_pairs,
)

WALL_MATERIAL_INDEX = 1
TOP_MATERIAL_INDEX = 0


@dataclass
class CliffSeamSample:
    position_key: tuple[float, float]
    node_a: int
    node_b: int


@dataclass
class CliffSeamChain:
    tile_a: tuple[int, int]
    tile_b: tuple[int, int]
    samples: list[CliffSeamSample]


@dataclass
class CliffWallFace:
    cliff_pair: frozenset[tuple[int, int]]
    segment_index: int
    vertex_indices: tuple[int, ...]
    height_delta: float


@dataclass
class CliffWallBuild:
    wall_faces: list[tuple[int, ...]]
    wall_face_records: list[CliffWallFace]
    seam_chains: list[CliffSeamChain]
    segment_count: int
    skipped_segment_count: int
    triangle_count: int
    quad_count: int
    wall_heights: list[float] = field(default_factory=list)
    expected_wall_face_keys: set[tuple[int, ...]] = field(default_factory=set)


def _lookup_tile_node(
    lattice: CutLatticeBuild,
    pk: tuple[float, float],
    tile: tuple[int, int],
) -> int:
    key = (pk, tile)
    node = lattice.tile_pos_to_node.get(key)
    if node is None:
        raise RuntimeError(
            f"tile_pos_to_node miss at pos={pk} tile={tile}"
        )
    return node


def extract_cliff_seam_chain(
    lattice: CutLatticeBuild,
    baseline: Any,
    tile_a: tuple[int, int],
    tile_b: tuple[int, int],
    *,
    subdiv: int = DEFAULT_SURFACE_SUBDIVISIONS,
    radius: float = DEFAULT_HEX_RADIUS,
) -> CliffSeamChain:
    direction_a = _neighbor_direction_between(tile_a, tile_b)
    edge_a = _physical_edge_for_neighbor_direction(direction_a)
    direction_b = _neighbor_direction_between(tile_b, tile_a)
    edge_b = _physical_edge_for_neighbor_direction(direction_b)

    qa, ra = tile_a
    qb, rb = tile_b
    cx_a, cy_a = baseline.axial_to_world_xy(
        *handdrawn_to_baseline_axial(qa, ra),
        radius,
    )
    cx_b, cy_b = baseline.axial_to_world_xy(
        *handdrawn_to_baseline_axial(qb, rb),
        radius,
    )

    samples: list[CliffSeamSample] = []
    for k in range(subdiv + 1):
        si_a, sj_a = subdiv - k, k
        lx_a, ly_a = baseline.sector_barycentric_xy(edge_a, si_a, sj_a, subdiv)
        pk = pos_key(cx_a + lx_a, cy_a + ly_a)

        step_k_b = subdiv - k
        si_b, sj_b = subdiv - step_k_b, step_k_b
        lx_b, ly_b = baseline.sector_barycentric_xy(edge_b, si_b, sj_b, subdiv)
        pk_b = pos_key(cx_b + lx_b, cy_b + ly_b)
        if pk_b != pk:
            raise RuntimeError(
                f"cliff seam position mismatch between {tile_a} and {tile_b} "
                f"at k={k}: {pk} vs {pk_b}"
            )

        node_a = _lookup_tile_node(lattice, pk, tile_a)
        node_b = _lookup_tile_node(lattice, pk, tile_b)
        samples.append(CliffSeamSample(position_key=pk, node_a=node_a, node_b=node_b))

    return CliffSeamChain(tile_a=tile_a, tile_b=tile_b, samples=samples)


def _dedupe_face_indices(indices: Iterable[int]) -> tuple[int, ...]:
    ordered: list[int] = []
    for index in indices:
        if not ordered or ordered[-1] != index:
            ordered.append(index)
    return tuple(ordered)


def _newell_normal(
    verts: list[tuple[float, float, float]],
    indices: tuple[int, ...],
) -> tuple[float, float, float]:
    nx = 0.0
    ny = 0.0
    nz = 0.0
    count = len(indices)
    for i in range(count):
        x0, y0, z0 = verts[indices[i]]
        x1, y1, z1 = verts[indices[(i + 1) % count]]
        nx += (y0 - y1) * (z0 + z1)
        ny += (z0 - z1) * (x0 + x1)
        nz += (x0 - x1) * (y0 + y1)
    return nx, ny, nz


def _face_area(
    verts: list[tuple[float, float, float]],
    indices: tuple[int, ...],
) -> float:
    if len(indices) < 3:
        return 0.0
    nx, ny, nz = _newell_normal(verts, indices)
    return 0.5 * math.sqrt(nx * nx + ny * ny + nz * nz)


def _orient_wall_face(
    indices: tuple[int, ...],
    verts: list[tuple[float, float, float]],
    tile_a: tuple[int, int],
    tile_b: tuple[int, int],
    model: Any,
    baseline: Any,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
) -> tuple[int, ...]:
    area = _face_area(verts, indices)
    if area <= 1e-15:
        return indices

    nx, ny, nz = _newell_normal(verts, indices)
    qa, ra = tile_a
    qb, rb = tile_b
    cx_a, cy_a = baseline.axial_to_world_xy(
        *handdrawn_to_baseline_axial(qa, ra),
        radius,
    )
    cx_b, cy_b = baseline.axial_to_world_xy(
        *handdrawn_to_baseline_axial(qb, rb),
        radius,
    )
    elev_a = model.map.tiles[tile_a]
    elev_b = model.map.tiles[tile_b]
    if elev_a >= elev_b:
        high_x, high_y = cx_a, cy_a
        low_x, low_y = cx_b, cy_b
    else:
        high_x, high_y = cx_b, cy_b
        low_x, low_y = cx_a, cy_a

    dir_x = low_x - high_x
    dir_y = low_y - high_y
    dir_len = math.hypot(dir_x, dir_y)
    if dir_len <= 1e-12:
        return indices

    dir_x /= dir_len
    dir_y /= dir_len
    normal_xy_len = math.hypot(nx, ny)
    if normal_xy_len <= 1e-12:
        return indices

    nx_xy = nx / normal_xy_len
    ny_xy = ny / normal_xy_len
    if nx_xy * dir_x + ny_xy * dir_y < 0.0:
        return tuple(reversed(indices))
    return indices


def _candidate_wall_face(
    a0: int,
    a1: int,
    b1: int,
    b0: int,
) -> tuple[int, ...] | None:
    deduped = _dedupe_face_indices((a0, a1, b1, b0))
    unique = tuple(dict.fromkeys(deduped))
    if len(unique) < 3:
        return None
    return unique


def build_cliff_wall_faces(
    lattice: CutLatticeBuild,
    model: Any,
    baseline: Any,
    heights: Any,
    *,
    subdiv: int = DEFAULT_SURFACE_SUBDIVISIONS,
    radius: float = DEFAULT_HEX_RADIUS,
) -> CliffWallBuild:
    cliff_pairs = build_cliff_neighbor_pairs(model)
    verts: list[tuple[float, float, float]] = [
        (xy[0], xy[1], float(heights[index]))
        for index, xy in enumerate(lattice.node_xy)
    ]

    wall_faces: list[tuple[int, ...]] = []
    wall_face_records: list[CliffWallFace] = []
    seam_chains: list[CliffSeamChain] = []
    wall_heights: list[float] = []
    expected_keys: set[tuple[int, ...]] = set()
    segment_count = 0
    skipped_segment_count = 0
    triangle_count = 0
    quad_count = 0

    for pair in sorted(cliff_pairs, key=lambda item: (min(item), max(item))):
        tile_a, tile_b = tuple(sorted(pair))
        chain = extract_cliff_seam_chain(
            lattice,
            baseline,
            tile_a,
            tile_b,
            subdiv=subdiv,
            radius=radius,
        )
        seam_chains.append(chain)

        for seg in range(len(chain.samples) - 1):
            segment_count += 1
            sample_a0 = chain.samples[seg]
            sample_a1 = chain.samples[seg + 1]
            candidate = _candidate_wall_face(
                sample_a0.node_a,
                sample_a1.node_a,
                sample_a1.node_b,
                sample_a0.node_b,
            )
            if candidate is None:
                skipped_segment_count += 1
                continue

            face = _orient_wall_face(
                candidate,
                verts,
                tile_a,
                tile_b,
                model,
                baseline,
                radius=radius,
            )
            key = tuple(sorted(face)) if len(face) == 4 else face
            if key in expected_keys:
                continue
            expected_keys.add(key)

            z_vals = [verts[index][2] for index in face]
            height_delta = max(z_vals) - min(z_vals)
            wall_heights.append(height_delta)

            wall_faces.append(face)
            wall_face_records.append(
                CliffWallFace(
                    cliff_pair=frozenset((tile_a, tile_b)),
                    segment_index=seg,
                    vertex_indices=face,
                    height_delta=height_delta,
                )
            )
            if len(face) == 3:
                triangle_count += 1
            else:
                quad_count += 1

    return CliffWallBuild(
        wall_faces=wall_faces,
        wall_face_records=wall_face_records,
        seam_chains=seam_chains,
        segment_count=segment_count,
        skipped_segment_count=skipped_segment_count,
        triangle_count=triangle_count,
        quad_count=quad_count,
        wall_heights=wall_heights,
        expected_wall_face_keys=expected_keys,
    )


def wall_height_stats(wall_build: CliffWallBuild) -> dict[str, float]:
    heights = wall_build.wall_heights
    if not heights:
        return {"min": 0.0, "mean": 0.0, "max": 0.0, "count": 0.0}
    return {
        "min": min(heights),
        "mean": sum(heights) / float(len(heights)),
        "max": max(heights),
        "count": float(len(heights)),
    }


def max_wall_face_xy_span(
    lattice: CutLatticeBuild,
    wall_faces: list[tuple[int, ...]],
) -> float:
    max_span = 0.0
    for face in wall_faces:
        xs = [lattice.node_xy[index][0] for index in face]
        ys = [lattice.node_xy[index][1] for index in face]
        span = max(max(xs) - min(xs), max(ys) - min(ys))
        if span > max_span:
            max_span = span
    return max_span


def expected_segment_length(
    *,
    subdiv: int = DEFAULT_SURFACE_SUBDIVISIONS,
    radius: float = DEFAULT_HEX_RADIUS,
) -> float:
    # Hex edge length at unit radius; one subdivision step along a cliff edge.
    edge_len = radius
    return edge_len / float(subdiv)
