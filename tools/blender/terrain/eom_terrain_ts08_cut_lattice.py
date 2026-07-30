# Empire of Minds — TS-08 cut-lattice topology (Stage 0, no height solve).
# Builds and validates Ω_cut lattice topology per docs/TERRAIN_SURFACE_TARGET.md.

from __future__ import annotations

import json
import math
from dataclasses import dataclass, field
from typing import Any, Hashable, Iterable

from eom_terrain_math_core import (
    DEFAULT_HEX_RADIUS,
    DEFAULT_SURFACE_SUBDIVISIONS,
    NEIGHBOR_DIRS,
    canonical_center_world_z,
    handdrawn_corner_world_xy,
    handdrawn_to_baseline_axial,
    partition_smoothing_domains,
    pos_key,
    resolve_edge_transitions,
)

MAP_ID = "terrain_handdrawn_test_map_full_01"
MAP_JSON_ID = "handdrawn_test_map_full_01"
PROTOTYPE_ID = "TS-08-STAGE-0-CUT-LATTICE-TOPOLOGY-AUDIT"


@dataclass
class EdgeClassificationSummary:
    total_shared_edges: int
    smooth_edges: int
    cliff_edges: int
    delta_eq_0: int
    delta_eq_1: int
    delta_gt_1: int


@dataclass
class CornerRecord:
    world_xy_key: tuple[float, float]
    tiles: tuple[tuple[int, int], ...]
    neighbor_pairs: tuple[tuple[tuple[int, int], tuple[int, int]], ...]
    pair_deltas: tuple[int, ...]
    cliff_incident_count: int
    case: int
    is_interior: bool
    case1_cliff_delta: int | None = None


@dataclass
class ComponentReport:
    component_id: int
    node_count: int
    hex_count: int
    pin_rank: int
    fully_determined: bool
    gauge_method: str
    pin_hexes: tuple[tuple[int, int], ...]
    pin_world_z: tuple[float, ...]
    collinear_non_affine: bool = False


@dataclass
class CutLatticeTopologyReport:
    map_id: str
    hex_count: int
    uncut_logical_node_count: int
    cut_topological_node_count: int
    duplicated_cliff_line_nodes: int
    edge_summary: EdgeClassificationSummary
    corner_case_counts: dict[str, int]
    boundary_partial_corner_count: int
    interior_case1_delta2_violations: int
    corner_copy_violations: int
    connected_component_count: int
    component_reports: list[ComponentReport]
    deficient_component_count: int
    max_component_node_count: int
    min_component_node_count: int
    adjacency_cross_cliff_violations: int
    delta_eq_1_cut_violations: int
    failures: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)

    @property
    def passed(self) -> bool:
        return not self.failures


def _physical_edge_for_neighbor_direction(direction: int) -> int:
    return (5 - direction) % 6


def _neighbor_direction_between(tile_a: tuple[int, int], tile_b: tuple[int, int]) -> int:
    q_b_from, r_b_from = handdrawn_to_baseline_axial(*tile_a)
    q_b_to, r_b_to = handdrawn_to_baseline_axial(*tile_b)
    dq = q_b_to - q_b_from
    dr = r_b_to - r_b_from
    for index, direction in enumerate(NEIGHBOR_DIRS):
        if direction == (dq, dr):
            return index
    raise ValueError(f"{tile_b} is not a neighbor of {tile_a}")


def shared_hex_edge_endpoints(
    tile_a: tuple[int, int],
    tile_b: tuple[int, int],
    *,
    radius: float,
) -> tuple[tuple[float, float], tuple[float, float]]:
    direction = _neighbor_direction_between(tile_a, tile_b)
    edge_index = _physical_edge_for_neighbor_direction(direction)
    c0 = edge_index
    c1 = (edge_index + 1) % 6
    return (
        handdrawn_corner_world_xy(tile_a[0], tile_a[1], c0, radius),
        handdrawn_corner_world_xy(tile_a[0], tile_a[1], c1, radius),
    )


def classify_shared_edges(model: Any) -> EdgeClassificationSummary:
    smooth_edges, cliff_edges = resolve_edge_transitions(model.map)
    delta_eq_0 = 0
    delta_eq_1 = 0
    delta_gt_1 = 0
    for edge in smooth_edges + cliff_edges:
        if edge.delta == 0:
            delta_eq_0 += 1
        elif edge.delta == 1:
            delta_eq_1 += 1
        elif edge.delta > 1:
            delta_gt_1 += 1
    return EdgeClassificationSummary(
        total_shared_edges=len(smooth_edges) + len(cliff_edges),
        smooth_edges=len(smooth_edges),
        cliff_edges=len(cliff_edges),
        delta_eq_0=delta_eq_0,
        delta_eq_1=delta_eq_1,
        delta_gt_1=delta_gt_1,
    )


def build_cliff_neighbor_pairs(model: Any) -> set[frozenset[tuple[int, int]]]:
    threshold = model.map.cliff_threshold
    pairs: set[frozenset[tuple[int, int]]] = set()
    for cliff in model.cliff_edge_graph:
        if cliff.delta > threshold:
            pairs.add(frozenset((cliff.tile_a, cliff.tile_b)))
    return pairs


def build_cliff_physical_edges_by_tile(
    cliff_pairs: set[frozenset[tuple[int, int]]],
) -> dict[tuple[int, int], frozenset[int]]:
    by_tile: dict[tuple[int, int], set[int]] = {}
    for pair in cliff_pairs:
        tiles = tuple(pair)
        tile_a, tile_b = tiles[0], tiles[1]
        edge_a = _physical_edge_for_neighbor_direction(
            _neighbor_direction_between(tile_a, tile_b)
        )
        edge_b = _physical_edge_for_neighbor_direction(
            _neighbor_direction_between(tile_b, tile_a)
        )
        by_tile.setdefault(tile_a, set()).add(edge_a)
        by_tile.setdefault(tile_b, set()).add(edge_b)
    return {tile: frozenset(edges) for tile, edges in by_tile.items()}


def build_sheet_lookup(model: Any) -> dict[tuple[int, int], int]:
    domains = partition_smoothing_domains(model.map)
    lookup: dict[tuple[int, int], int] = {}
    for domain in domains:
        for coord in domain.tiles:
            lookup[coord] = domain.domain_id
    return lookup


def _neighbor_pairs_at_corner(
    tiles: Iterable[tuple[int, int]],
    corner_xy_key: tuple[float, float],
    *,
    radius: float,
) -> list[tuple[tuple[int, int], tuple[int, int]]]:
    tile_set = set(tiles)
    pairs: list[tuple[tuple[int, int], tuple[int, int]]] = []
    seen: set[tuple[tuple[int, int], tuple[int, int]]] = set()
    for tile_a in sorted(tile_set):
        for tile_b in sorted(tile_set):
            if tile_a >= tile_b:
                continue
            if tile_b not in {
                (tile_a[0] + dq, tile_a[1] + dr) for dq, dr in NEIGHBOR_DIRS
            }:
                continue
            p0, p1 = shared_hex_edge_endpoints(tile_a, tile_b, radius=radius)
            if corner_xy_key in (pos_key(p0[0], p0[1]), pos_key(p1[0], p1[1])):
                pair = (tile_a, tile_b)
                if pair not in seen:
                    seen.add(pair)
                    pairs.append(pair)
    return pairs


def build_corner_registry(
    model: Any,
    cliff_pairs: set[frozenset[tuple[int, int]]],
    *,
    radius: float = DEFAULT_HEX_RADIUS,
) -> list[CornerRecord]:
    threshold = model.map.cliff_threshold
    corner_tiles: dict[tuple[float, float], set[tuple[int, int]]] = {}
    for q, r in model.map.tiles:
        for corner_index in range(6):
            wx, wy = handdrawn_corner_world_xy(q, r, corner_index, radius)
            key = pos_key(wx, wy)
            corner_tiles.setdefault(key, set()).add((q, r))

    records: list[CornerRecord] = []
    for world_xy_key in sorted(corner_tiles):
        tiles = tuple(sorted(corner_tiles[world_xy_key]))
        neighbor_pairs = tuple(
            _neighbor_pairs_at_corner(tiles, world_xy_key, radius=radius)
        )
        pair_deltas: list[int] = []
        cliff_count = 0
        case1_cliff_delta: int | None = None
        for tile_a, tile_b in neighbor_pairs:
            ea = model.map.tiles[tile_a]
            eb = model.map.tiles[tile_b]
            delta = abs(ea - eb)
            pair_deltas.append(delta)
            if delta > threshold:
                cliff_count += 1
                case1_cliff_delta = delta
        is_interior = len(tiles) == 3 and len(neighbor_pairs) == 3
        if is_interior:
            case = cliff_count
        else:
            case = -1
        records.append(
            CornerRecord(
                world_xy_key=world_xy_key,
                tiles=tiles,
                neighbor_pairs=neighbor_pairs,
                pair_deltas=tuple(pair_deltas),
                cliff_incident_count=cliff_count,
                case=case,
                is_interior=is_interior,
                case1_cliff_delta=case1_cliff_delta if cliff_count == 1 else None,
            )
        )
    return records


def _incident_physical_edges_at_sample(
    sector: int,
    *,
    at_corner: bool,
    si: int,
    sj: int,
    subdiv: int,
) -> tuple[int, ...]:
    if not at_corner:
        return ()
    if si == subdiv and sj == 0:
        return ((sector - 1) % 6, sector)
    return (sector, (sector + 1) % 6)


def sample_on_cliff_boundary(
    q: int,
    r: int,
    sector: int,
    *,
    at_sector_outer_edge: bool,
    at_corner: bool,
    si: int,
    sj: int,
    subdiv: int,
    cliff_physical_edges_by_tile: dict[tuple[int, int], frozenset[int]],
) -> bool:
    cliff_edges = cliff_physical_edges_by_tile.get((q, r), frozenset())
    if not cliff_edges:
        return False
    if at_sector_outer_edge and sector in cliff_edges:
        return True
    if at_corner:
        return any(
            edge in cliff_edges
            for edge in _incident_physical_edges_at_sample(
                sector,
                at_corner=True,
                si=si,
                sj=sj,
                subdiv=subdiv,
            )
        )
    return False


def _build_smooth_adjacency(
    model: Any,
) -> dict[tuple[int, int], set[tuple[int, int]]]:
    adjacency: dict[tuple[int, int], set[tuple[int, int]]] = {
        coord: set() for coord in model.map.tiles
    }
    for edge in model.smooth_edges:
        adjacency[edge.tile_a].add(edge.tile_b)
        adjacency[edge.tile_b].add(edge.tile_a)
    return adjacency


def _smooth_component_at_corner(
    start: tuple[int, int],
    corner_tiles: list[tuple[int, int]],
    smooth_adjacency: dict[tuple[int, int], set[tuple[int, int]]],
) -> list[tuple[int, int]]:
    allowed = set(corner_tiles)
    queue = [start]
    seen = {start}
    head = 0
    while head < len(queue):
        current = queue[head]
        head += 1
        for neighbor in smooth_adjacency.get(current, ()):
            if neighbor in allowed and neighbor not in seen:
                seen.add(neighbor)
                queue.append(neighbor)
    return sorted(seen)


def build_corner_smooth_component_lookup(
    corner_registry: list[CornerRecord],
    smooth_adjacency: dict[tuple[int, int], set[tuple[int, int]]],
) -> dict[tuple[float, float], dict[tuple[int, int], int]]:
    lookup: dict[tuple[float, float], dict[tuple[int, int], int]] = {}
    for corner in corner_registry:
        if not corner.is_interior or corner.case not in (2, 3):
            continue
        tiles = list(corner.tiles)
        tile_to_component: dict[tuple[int, int], int] = {}
        seen_tiles: set[tuple[int, int]] = set()
        component_index = 0
        for tile in tiles:
            if tile in seen_tiles:
                continue
            component = _smooth_component_at_corner(tile, tiles, smooth_adjacency)
            for member in component:
                tile_to_component[member] = component_index
                seen_tiles.add(member)
            component_index += 1
        lookup[corner.world_xy_key] = tile_to_component
    return lookup


def _corner_record_at(
    corner_registry: dict[tuple[float, float], CornerRecord],
    wx: float,
    wy: float,
) -> CornerRecord | None:
    return corner_registry.get(pos_key(wx, wy))


def _add_undirected_edge(adjacency: list[set[int]], a: int, b: int) -> None:
    if a == b:
        return
    adjacency[a].add(b)
    adjacency[b].add(a)


def build_uncut_lattice_node_count(
    model: Any,
    baseline: Any,
    *,
    subdiv: int = DEFAULT_SURFACE_SUBDIVISIONS,
    radius: float = DEFAULT_HEX_RADIUS,
) -> int:
    hex_coords = set(model.map.tiles.keys())
    merge_map: dict[tuple[float, float], int] = {}

    def node_id_for(wx: float, wy: float) -> int:
        key = pos_key(wx, wy)
        existing = merge_map.get(key)
        if existing is not None:
            return existing
        index = len(merge_map)
        merge_map[key] = index
        return index

    for q_h, r_h in sorted(hex_coords):
        q_b, r_b = handdrawn_to_baseline_axial(q_h, r_h)
        cx, cy = baseline.axial_to_world_xy(q_b, r_b, radius)
        for sector in range(6):
            for si in range(subdiv + 1):
                sj = 0
                while sj <= subdiv - si:
                    lx, ly = baseline.sector_barycentric_xy(sector, si, sj, subdiv)
                    node_id_for(cx + lx, cy + ly)
                    sj += 1
    return len(merge_map)


@dataclass
class _CutLatticeBuild:
    node_count: int
    adjacency: list[list[int]]
    node_keys: list[Hashable]
    node_sheet_ids: list[int]
    node_pos_keys: list[tuple[float, float]]
    pinned: dict[int, float]
    pin_hex_by_node: dict[int, tuple[int, int]]
    component_ids: list[int]
    corner_sample_nodes: dict[tuple[float, float], set[int]]


def build_cut_lattice_topology(
    model: Any,
    baseline: Any,
    corner_registry: list[CornerRecord],
    cliff_physical_edges_by_tile: dict[tuple[int, int], frozenset[int]],
    sheet_lookup: dict[tuple[int, int], int],
    cliff_neighbor_pairs: set[frozenset[tuple[int, int]]],
    *,
    subdiv: int = DEFAULT_SURFACE_SUBDIVISIONS,
    radius: float = DEFAULT_HEX_RADIUS,
) -> _CutLatticeBuild:
    hex_coords = set(model.map.tiles.keys())
    corner_by_pos = {record.world_xy_key: record for record in corner_registry}
    smooth_adjacency = _build_smooth_adjacency(model)
    corner_smooth_components = build_corner_smooth_component_lookup(
        corner_registry,
        smooth_adjacency,
    )

    merge_map: dict[Hashable, int] = {}
    merge_owner: dict[tuple[tuple[float, float], int], tuple[int, int]] = {}
    node_keys: list[Hashable] = []
    node_sheet_ids: list[int] = []
    node_pos_keys: list[tuple[float, float]] = []
    pinned: dict[int, float] = {}
    pin_hex_by_node: dict[int, tuple[int, int]] = {}
    adjacency_sets: list[set[int]] = []
    corner_sample_nodes: dict[tuple[float, float], set[int]] = {}

    def tiles_are_cliff_neighbors(
        tile_a: tuple[int, int],
        tile_b: tuple[int, int],
    ) -> bool:
        if tile_a == tile_b:
            return False
        return frozenset((tile_a, tile_b)) in cliff_neighbor_pairs

    def _create_node(key: Hashable, pk: tuple[float, float], sheet_id: int) -> int:
        index = len(adjacency_sets)
        merge_map[key] = index
        node_keys.append(key)
        node_sheet_ids.append(sheet_id)
        node_pos_keys.append(pk)
        adjacency_sets.append(set())
        return index

    def node_id_for(
        wx: float,
        wy: float,
        q: int,
        r: int,
        sector: int,
        *,
        at_corner: bool,
        on_cliff_boundary: bool,
        si: int,
        sj: int,
    ) -> int:
        sheet_id = sheet_lookup[(q, r)]
        pk = pos_key(wx, wy)
        corner = _corner_record_at(corner_by_pos, wx, wy)

        if at_corner and corner is not None and corner.is_interior and corner.case == 1:
            key: Hashable = ("crack_tip", pk)
            existing = merge_map.get(key)
            if existing is not None:
                corner_sample_nodes.setdefault(pk, set()).add(existing)
                return existing
            index = _create_node(key, pk, sheet_id)
            corner_sample_nodes.setdefault(pk, set()).add(index)
            return index

        if (
            at_corner
            and corner is not None
            and corner.is_interior
            and corner.case in (2, 3)
        ):
            component_id = corner_smooth_components[corner.world_xy_key][(q, r)]
            key = ("corner_split", pk, component_id)
            existing = merge_map.get(key)
            if existing is not None:
                corner_sample_nodes.setdefault(pk, set()).add(existing)
                return existing
            index = _create_node(key, pk, sheet_id)
            corner_sample_nodes.setdefault(pk, set()).add(index)
            return index

        if on_cliff_boundary:
            key = ("cliff_line", pk, sheet_id, q, r)
            existing = merge_map.get(key)
            if existing is not None:
                return existing
            return _create_node(key, pk, sheet_id)

        merge_key: Hashable = (pk, sheet_id)
        if at_corner:
            tile_key: Hashable = (pk, sheet_id, q, r, sector)
        else:
            tile_key = (pk, sheet_id, q, r)

        cached_tile = merge_map.get(tile_key)
        if cached_tile is not None:
            if at_corner:
                corner_sample_nodes.setdefault(pk, set()).add(cached_tile)
            return cached_tile

        cached_merge = merge_map.get(merge_key)
        if cached_merge is not None:
            owner = merge_owner.get((pk, sheet_id))
            allow_merge = owner is None or not tiles_are_cliff_neighbors((q, r), owner)
            if allow_merge:
                merge_map[tile_key] = cached_merge
                if at_corner:
                    corner_sample_nodes.setdefault(pk, set()).add(cached_merge)
                return cached_merge

        index = len(adjacency_sets)
        merge_map[tile_key] = index
        node_keys.append(tile_key)
        node_sheet_ids.append(sheet_id)
        node_pos_keys.append(pk)
        adjacency_sets.append(set())
        if cached_merge is None:
            merge_map[merge_key] = index
            merge_owner[(pk, sheet_id)] = (q, r)
        if at_corner:
            corner_sample_nodes.setdefault(pk, set()).add(index)
        return index

    for q_h, r_h in sorted(hex_coords):
        q_b, r_b = handdrawn_to_baseline_axial(q_h, r_h)
        cx, cy = baseline.axial_to_world_xy(q_b, r_b, radius)
        for sector in range(6):
            grid: dict[tuple[int, int], int] = {}
            for si in range(subdiv + 1):
                sj = 0
                while sj <= subdiv - si:
                    lx, ly = baseline.sector_barycentric_xy(sector, si, sj, subdiv)
                    wx = cx + lx
                    wy = cy + ly
                    at_corner = (si == subdiv and sj == 0) or (si == 0 and sj == subdiv)
                    at_outer = si + sj == subdiv
                    on_cliff = sample_on_cliff_boundary(
                        q_h,
                        r_h,
                        sector,
                        at_sector_outer_edge=at_outer,
                        at_corner=at_corner,
                        si=si,
                        sj=sj,
                        subdiv=subdiv,
                        cliff_physical_edges_by_tile=cliff_physical_edges_by_tile,
                    )
                    nid = node_id_for(
                        wx,
                        wy,
                        q_h,
                        r_h,
                        sector,
                        at_corner=at_corner,
                        on_cliff_boundary=on_cliff,
                        si=si,
                        sj=sj,
                    )
                    grid[(si, sj)] = nid
                    if si == 0 and sj == 0:
                        pinned[nid] = canonical_center_world_z(model.map, q_h, r_h)
                        pin_hex_by_node[nid] = (q_h, r_h)
                    sj += 1

            for si in range(subdiv):
                sj = 0
                while sj <= subdiv - si - 1:
                    v00 = grid[(si, sj)]
                    v10 = grid[(si + 1, sj)]
                    v01 = grid[(si, sj + 1)]
                    _add_undirected_edge(adjacency_sets, v00, v10)
                    _add_undirected_edge(adjacency_sets, v10, v01)
                    _add_undirected_edge(adjacency_sets, v00, v01)
                    if sj + 1 <= subdiv - (si + 1):
                        v11 = grid[(si + 1, sj + 1)]
                        _add_undirected_edge(adjacency_sets, v10, v11)
                        _add_undirected_edge(adjacency_sets, v01, v11)
                    sj += 1

    adjacency = [sorted(neighbors) for neighbors in adjacency_sets]
    component_ids, _ = _connected_components(adjacency)
    return _CutLatticeBuild(
        node_count=len(adjacency),
        adjacency=adjacency,
        node_keys=node_keys,
        node_sheet_ids=node_sheet_ids,
        node_pos_keys=node_pos_keys,
        pinned=pinned,
        pin_hex_by_node=pin_hex_by_node,
        component_ids=component_ids,
        corner_sample_nodes=corner_sample_nodes,
    )


def _connected_components(adjacency: list[list[int]]) -> tuple[list[int], int]:
    node_count = len(adjacency)
    component_ids = [-1] * node_count
    component_index = 0
    for start in range(node_count):
        if component_ids[start] >= 0:
            continue
        queue = [start]
        component_ids[start] = component_index
        head = 0
        while head < len(queue):
            current = queue[head]
            head += 1
            for neighbor in adjacency[current]:
                if component_ids[neighbor] >= 0:
                    continue
                component_ids[neighbor] = component_index
                queue.append(neighbor)
        component_index += 1
    return component_ids, component_index


def _axial_cross(a: tuple[int, int], b: tuple[int, int], c: tuple[int, int]) -> int:
    return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])


def _pin_rank(hexes: list[tuple[int, int]], world_z: list[float]) -> tuple[int, bool]:
    if len(hexes) <= 1:
        return 1, False
    if len(hexes) == 2:
        return 2, False
    non_collinear = False
    for index in range(2, len(hexes)):
        if _axial_cross(hexes[0], hexes[1], hexes[index]) != 0:
            non_collinear = True
            break
    if non_collinear:
        return 3, False
    if len(hexes) == 2:
        return 2, False
    direction = (hexes[1][0] - hexes[0][0], hexes[1][1] - hexes[0][1])
    if direction == (0, 0):
        return 1, False
    t_values = []
    z_values = []
    for hex_coord, z in zip(hexes, world_z):
        t = (hex_coord[0] - hexes[0][0]) * direction[0] + (hex_coord[1] - hexes[0][1]) * direction[1]
        t_values.append(t)
        z_values.append(z)
    if len(set(t_values)) <= 1:
        return 1, False
    t_mean = sum(t_values) / float(len(t_values))
    z_mean = sum(z_values) / float(len(z_values))
    num = sum((t - t_mean) * (z - z_mean) for t, z in zip(t_values, z_values))
    den = sum((t - t_mean) ** 2 for t in t_values)
    slope = num / den if den != 0.0 else 0.0
    max_err = max(abs(z - (z_mean + slope * (t - t_mean))) for t, z in zip(t_values, z_values))
    return 2, max_err > 1e-9


def _gauge_method_for_rank(rank: int, collinear_non_affine: bool) -> str:
    if rank >= 3:
        return "cg_plain"
    if rank == 1:
        return "analytic_constant"
    if collinear_non_affine:
        return "cg_deflated"
    return "analytic_plane"


def _topological_copy_count_at_corner(
    build: _CutLatticeBuild,
    corner_xy_key: tuple[float, float],
) -> int:
    return len(build.corner_sample_nodes.get(corner_xy_key, set()))


def _count_duplicated_cliff_line_nodes(
    node_keys: list[Hashable],
    node_pos_keys: list[tuple[float, float]],
) -> int:
    cliff_nodes_by_pos: dict[tuple[float, float], set[int]] = {}
    for index, key in enumerate(node_keys):
        if isinstance(key, tuple) and key and key[0] == "cliff_line":
            cliff_nodes_by_pos.setdefault(node_pos_keys[index], set()).add(index)
    duplicated = 0
    for indices in cliff_nodes_by_pos.values():
        if len(indices) > 1:
            duplicated += len(indices) - 1
    return duplicated


def _expected_corner_copies(corner: CornerRecord) -> int:
    if not corner.is_interior:
        return 1
    if corner.case == 0:
        return 1
    if corner.case == 1:
        return 1
    if corner.case == 2:
        return 2
    if corner.case == 3:
        return 3
    return 1


def audit_adjacency_cross_cliff(
    build: _CutLatticeBuild,
    cliff_pairs: set[frozenset[tuple[int, int]]],
) -> tuple[int, list[str]]:
    violations = 0
    messages: list[str] = []
    for node_index, neighbors in enumerate(build.adjacency):
        sheet_a = build.node_sheet_ids[node_index]
        pos_a = build.node_pos_keys[node_index]
        key_a = build.node_keys[node_index]
        for neighbor in neighbors:
            if neighbor <= node_index:
                continue
            sheet_b = build.node_sheet_ids[neighbor]
            pos_b = build.node_pos_keys[neighbor]
            if sheet_a == sheet_b:
                continue
            if pos_a != pos_b:
                continue
            violations += 1
            if len(messages) < 8:
                messages.append(
                    f"adjacency crosses cliff at pos={pos_a} sheets=({sheet_a},{sheet_b}) "
                    f"keys=({key_a!r},{build.node_keys[neighbor]!r})"
                )
    return violations, messages


def build_component_reports(
    build: _CutLatticeBuild,
    model: Any,
) -> list[ComponentReport]:
    component_count = max(build.component_ids) + 1 if build.component_ids else 0
    reports: list[ComponentReport] = []
    for component_id in range(component_count):
        node_count = sum(1 for cid in build.component_ids if cid == component_id)
        pin_hexes = sorted(
            {
                build.pin_hex_by_node[node_index]
                for node_index in build.pinned
                if build.component_ids[node_index] == component_id
                and node_index in build.pin_hex_by_node
            }
        )
        pin_z = [canonical_center_world_z(model.map, q, r) for q, r in pin_hexes]
        rank, collinear_non_affine = _pin_rank(list(pin_hexes), pin_z)
        reports.append(
            ComponentReport(
                component_id=component_id,
                node_count=node_count,
                hex_count=len(pin_hexes),
                pin_rank=rank,
                fully_determined=rank >= 3,
                gauge_method=_gauge_method_for_rank(rank, collinear_non_affine),
                pin_hexes=tuple(pin_hexes),
                pin_world_z=tuple(pin_z),
                collinear_non_affine=collinear_non_affine,
            )
        )
    return reports


def run_cut_lattice_topology_audit(
    model: Any,
    baseline: Any,
    *,
    map_id: str = MAP_ID,
    subdiv: int = DEFAULT_SURFACE_SUBDIVISIONS,
    radius: float = DEFAULT_HEX_RADIUS,
) -> CutLatticeTopologyReport:
    failures: list[str] = []
    warnings: list[str] = []

    edge_summary = classify_shared_edges(model)
    cliff_pairs = build_cliff_neighbor_pairs(model)
    if edge_summary.cliff_edges != len(cliff_pairs):
        failures.append(
            f"cliff edge count mismatch: graph={len(cliff_pairs)} resolved={edge_summary.cliff_edges}"
        )

    cliff_physical = build_cliff_physical_edges_by_tile(cliff_pairs)
    sheet_lookup = build_sheet_lookup(model)
    corner_registry = build_corner_registry(model, cliff_pairs, radius=radius)

    cut_build = build_cut_lattice_topology(
        model,
        baseline,
        corner_registry,
        cliff_physical,
        sheet_lookup,
        cliff_pairs,
        subdiv=subdiv,
        radius=radius,
    )
    uncut_count = build_uncut_lattice_node_count(
        model, baseline, subdiv=subdiv, radius=radius
    )

    case_counts = {"case_0": 0, "case_1": 0, "case_2": 0, "case_3": 0}
    boundary_partial = 0
    case1_delta2_violations = 0
    corner_copy_violations = 0

    for corner in corner_registry:
        if not corner.is_interior:
            boundary_partial += 1
            continue
        case_counts[f"case_{corner.case}"] += 1
        if corner.case == 1 and corner.case1_cliff_delta != 2:
            case1_delta2_violations += 1
            failures.append(
                f"interior Case-1 corner {corner.world_xy_key} cliff delta="
                f"{corner.case1_cliff_delta} (expected 2)"
            )
        if corner.is_interior:
            expected_copies = _expected_corner_copies(corner)
            actual_copies = _topological_copy_count_at_corner(cut_build, corner.world_xy_key)
            if actual_copies != expected_copies:
                corner_copy_violations += 1
                failures.append(
                    f"corner copy mismatch at {corner.world_xy_key}: "
                    f"case={corner.case} expected={expected_copies} actual={actual_copies}"
                )

    cross_violations, cross_messages = audit_adjacency_cross_cliff(cut_build, cliff_pairs)
    if cross_violations:
        failures.append(f"adjacency crosses cliff: {cross_violations} violation(s)")
        failures.extend(cross_messages[:5])

    delta_eq_1_cut_violations = 0
    smooth_pairs = set()
    _smooth, _cliff = resolve_edge_transitions(model.map)
    for edge in _smooth:
        if edge.delta == 1:
            smooth_pairs.add(frozenset((edge.tile_a, edge.tile_b)))
    for pair in smooth_pairs:
        if pair in cliff_pairs:
            delta_eq_1_cut_violations += 1
            failures.append(f"delta==1 edge incorrectly in cliff set: {pair}")

    component_reports = build_component_reports(cut_build, model)
    deficient_count = sum(1 for report in component_reports if not report.fully_determined)
    component_sizes = [report.node_count for report in component_reports]

    if cut_build.component_ids:
        component_count = max(cut_build.component_ids) + 1
    else:
        component_count = 0

    if component_count >= 10:
        warnings.append(
            f"connected component count is {component_count}; "
            "investigate whether real enclosed cut regions exist or topology bug"
        )

    duplicated = _count_duplicated_cliff_line_nodes(
        cut_build.node_keys,
        cut_build.node_pos_keys,
    )

    return CutLatticeTopologyReport(
        map_id=map_id,
        hex_count=len(model.map.tiles),
        uncut_logical_node_count=uncut_count,
        cut_topological_node_count=cut_build.node_count,
        duplicated_cliff_line_nodes=duplicated,
        edge_summary=edge_summary,
        corner_case_counts=case_counts,
        boundary_partial_corner_count=boundary_partial,
        interior_case1_delta2_violations=case1_delta2_violations,
        corner_copy_violations=corner_copy_violations,
        connected_component_count=component_count,
        component_reports=component_reports,
        deficient_component_count=deficient_count,
        max_component_node_count=max(component_sizes) if component_sizes else 0,
        min_component_node_count=min(component_sizes) if component_sizes else 0,
        adjacency_cross_cliff_violations=cross_violations,
        delta_eq_1_cut_violations=delta_eq_1_cut_violations,
        failures=failures,
        warnings=warnings,
    )


def report_to_dict(report: CutLatticeTopologyReport) -> dict[str, Any]:
    return {
        "prototype_id": PROTOTYPE_ID,
        "map_id": report.map_id,
        "passed": report.passed,
        "hex_count": report.hex_count,
        "uncut_logical_node_count": report.uncut_logical_node_count,
        "cut_topological_node_count": report.cut_topological_node_count,
        "duplicated_cliff_line_nodes": report.duplicated_cliff_line_nodes,
        "edge_summary": report.edge_summary.__dict__,
        "corner_case_counts": report.corner_case_counts,
        "boundary_partial_corner_count": report.boundary_partial_corner_count,
        "interior_case1_delta2_violations": report.interior_case1_delta2_violations,
        "corner_copy_violations": report.corner_copy_violations,
        "connected_component_count": report.connected_component_count,
        "deficient_component_count": report.deficient_component_count,
        "max_component_node_count": report.max_component_node_count,
        "min_component_node_count": report.min_component_node_count,
        "adjacency_cross_cliff_violations": report.adjacency_cross_cliff_violations,
        "delta_eq_1_cut_violations": report.delta_eq_1_cut_violations,
        "component_reports": [item.__dict__ for item in report.component_reports],
        "failures": report.failures,
        "warnings": report.warnings,
    }


def print_traceability_banner(*, phase: str, runner_file: str | None = None) -> None:
    print("=== EOM TERRAIN PROTOTYPE TRACEABILITY ===")
    print(f"TRACEABILITY_PHASE={phase}")
    print(f"PROTOTYPE_ID={PROTOTYPE_ID}")
    print("DOC_SOURCE=docs/TERRAIN_SURFACE_TARGET.md")
    print("STAGE=0")
    print(f"MAP_ID={MAP_ID}")
    print(f"MAP_JSON_ID={MAP_JSON_ID}")
    print("STANDARD_MAP_AUDIT=ON")
    print("TOPOLOGY_ONLY=ON")
    print("HEIGHT_SOLVE=OFF")
    print("CG_SOLVER=OFF")
    print("BLENDER_MESH_OUTPUT=OFF")
    print("BLEND_SAVE=OFF")
    print("WALLS=OFF")
    print("RAILS=OFF")
    print("FEM_SOLVER=OFF")
    print("TPS_SOLVER=OFF")
    print("TS03D_CLUSTERING=OFF")
    print("DELTA_GT_1_IS_CLIFF=confirmed")
    print("DELTA_EQ_1_IS_SMOOTH=confirmed")
    if runner_file:
        print(f"RUNNER_FILE={runner_file}")
    print("=== END TRACEABILITY ===")


def print_audit_report(report: CutLatticeTopologyReport) -> None:
    es = report.edge_summary
    print(f"HEX_COUNT={report.hex_count}")
    print(f"UNCUT_LOGICAL_NODE_COUNT={report.uncut_logical_node_count}")
    print(f"CUT_TOPOLOGICAL_NODE_COUNT={report.cut_topological_node_count}")
    print(f"DUPLICATED_CLIFF_LINE_NODES={report.duplicated_cliff_line_nodes}")
    print(f"TOTAL_SHARED_EDGES={es.total_shared_edges}")
    print(f"SMOOTH_EDGES={es.smooth_edges}")
    print(f"CLIFF_EDGES={es.cliff_edges}")
    print(f"DELTA_EQ_0={es.delta_eq_0}")
    print(f"DELTA_EQ_1={es.delta_eq_1}")
    print(f"DELTA_GT_1={es.delta_gt_1}")
    print(f"DELTA_EQ_1_NOT_CUT={report.delta_eq_1_cut_violations == 0}")
    for key, value in report.corner_case_counts.items():
        print(f"{key.upper()}={value}")
    print(f"BOUNDARY_PARTIAL_CORNERS={report.boundary_partial_corner_count}")
    print(f"INTERIOR_CASE1_DELTA2_VIOLATIONS={report.interior_case1_delta2_violations}")
    print(f"CORNER_COPY_VIOLATIONS={report.corner_copy_violations}")
    print(f"CONNECTED_COMPONENT_COUNT={report.connected_component_count}")
    print(f"DEFICIENT_COMPONENT_COUNT={report.deficient_component_count}")
    print(f"MAX_COMPONENT_NODE_COUNT={report.max_component_node_count}")
    print(f"MIN_COMPONENT_NODE_COUNT={report.min_component_node_count}")
    print(f"ADJACENCY_CROSS_CLIFF_VIOLATIONS={report.adjacency_cross_cliff_violations}")
    print("--- per-component summary ---")
    for item in report.component_reports:
        print(
            f"COMPONENT id={item.component_id} nodes={item.node_count} hexes={item.hex_count} "
            f"pin_rank={item.pin_rank} fully_determined={item.fully_determined} "
            f"gauge_method={item.gauge_method} collinear_non_affine={item.collinear_non_affine}"
        )
    if report.warnings:
        print("--- warnings ---")
        for warning in report.warnings:
            print(f"WARNING: {warning}")
    if report.failures:
        print("=== RESULT: FAIL ===")
        for failure in report.failures:
            print(f"FAIL: {failure}")
    else:
        print("=== RESULT: PASS ===")
        print("TS08_STAGE0_CUT_LATTICE_TOPOLOGY_AUDIT_PASS=True")
