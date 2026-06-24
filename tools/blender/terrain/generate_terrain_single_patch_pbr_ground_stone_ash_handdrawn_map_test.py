# Empire of Minds — hand-drawn axial map terrain test on approved PBR baseline.
# Run from Blender Scripting workspace: Open → Run Script.
# Requires bpy (not available outside Blender).
#
# Builds terrain from inline JSON tile elevations using the locked material baseline.
# Does not modify the approved 7-hex prototype script, Niclas demo, or Godot gameplay.

from __future__ import annotations

import importlib.util
import inspect
import json
import math
import sys
import textwrap
from pathlib import Path
from typing import Any

import bpy
from mathutils import Vector

# ---------------------------------------------------------------------------
# Inline hand-authored map (valid JSON)
# ---------------------------------------------------------------------------

HANDDRAWN_MAP_JSON = """
{
  "id": "handdrawn_test_map_01",
  "orientation": "pointy_top_custom_axes",
  "elevation_step": 0.4,
  "edge_rule": {
    "default": "smooth",
    "cliff_if_abs_delta_greater_than": 1
  },
  "tiles": [
    {"q":0,"r":0,"elevation":1},
    {"q":1,"r":0,"elevation":1},
    {"q":2,"r":0,"elevation":1},
    {"q":3,"r":0,"elevation":1},
    {"q":4,"r":0,"elevation":1},
    {"q":5,"r":0,"elevation":3},
    {"q":6,"r":0,"elevation":3},
    {"q":7,"r":0,"elevation":4},
    {"q":8,"r":0,"elevation":1},
    {"q":9,"r":0,"elevation":1},
    {"q":10,"r":0,"elevation":1},

    {"q":0,"r":1,"elevation":1},
    {"q":1,"r":1,"elevation":1},
    {"q":2,"r":1,"elevation":2},
    {"q":3,"r":1,"elevation":1},
    {"q":4,"r":1,"elevation":3},
    {"q":5,"r":1,"elevation":2},
    {"q":6,"r":1,"elevation":2},
    {"q":7,"r":1,"elevation":4},
    {"q":8,"r":1,"elevation":1},
    {"q":9,"r":1,"elevation":1},

    {"q":-1,"r":2,"elevation":1},
    {"q":0,"r":2,"elevation":1},
    {"q":1,"r":2,"elevation":2},
    {"q":2,"r":2,"elevation":1},
    {"q":3,"r":2,"elevation":2},
    {"q":4,"r":2,"elevation":3},
    {"q":5,"r":2,"elevation":3},
    {"q":6,"r":2,"elevation":3},
    {"q":7,"r":2,"elevation":2},
    {"q":8,"r":2,"elevation":1},
    {"q":9,"r":2,"elevation":1},

    {"q":-1,"r":3,"elevation":1},
    {"q":0,"r":3,"elevation":3},
    {"q":1,"r":3,"elevation":1},
    {"q":2,"r":3,"elevation":2},
    {"q":3,"r":3,"elevation":2},
    {"q":4,"r":3,"elevation":3},
    {"q":5,"r":3,"elevation":3},
    {"q":6,"r":3,"elevation":1},
    {"q":7,"r":3,"elevation":1},
    {"q":8,"r":3,"elevation":1},

    {"q":-2,"r":4,"elevation":1},
    {"q":-1,"r":4,"elevation":3},
    {"q":0,"r":4,"elevation":3},
    {"q":1,"r":4,"elevation":1},
    {"q":2,"r":4,"elevation":1},
    {"q":3,"r":4,"elevation":1},
    {"q":4,"r":4,"elevation":2},
    {"q":5,"r":4,"elevation":1},
    {"q":6,"r":4,"elevation":1},
    {"q":7,"r":4,"elevation":1},
    {"q":8,"r":4,"elevation":1},

    {"q":-2,"r":5,"elevation":1},
    {"q":-1,"r":5,"elevation":1},
    {"q":0,"r":5,"elevation":1},
    {"q":1,"r":5,"elevation":1},
    {"q":2,"r":5,"elevation":1},
    {"q":3,"r":5,"elevation":1},
    {"q":4,"r":5,"elevation":1},
    {"q":5,"r":5,"elevation":1},
    {"q":6,"r":5,"elevation":2},
    {"q":7,"r":5,"elevation":1}
  ]
}
"""

# ---------------------------------------------------------------------------
# Test script parameters
# ---------------------------------------------------------------------------

TERRAIN_BASELINE_SCRIPT = "generate_terrain_single_patch_pbr_ground_stone_ash_prototype.py"

COLLECTION_NAME = "EOM_Terrain_Handdrawn_Test"
TERRAIN_OBJECT_NAME = "EOM_Terrain_HanddrawnTestMap01"
OVERLAY_OBJECT_NAME = "EOM_Terrain_HanddrawnTestMap01_Overlay"

OUTPUT_BLEND_FILENAME = "terrain_handdrawn_test_map_01.blend"
OUTPUT_GLB_FILENAME = "terrain_handdrawn_test_map_01.glb"

SAVE_BLEND = True
EXPORT_GLB = False

OUTPUT_BLEND_PATH: Path | None = None


def _log(message: str) -> None:
    print(f"[EOM handdrawn map test] {message}")


def _candidate_start_paths() -> list[Path]:
    candidates: list[Path] = []
    seen: set[str] = set()

    def add(path: Path) -> None:
        resolved = path.resolve()
        key = str(resolved)
        if key in seen:
            return
        seen.add(key)
        candidates.append(resolved)

    try:
        space = bpy.context.space_data
        if space is not None and getattr(space, "text", None) is not None:
            text = space.text
            if text is not None and text.filepath:
                add(Path(bpy.path.abspath(text.filepath)))
    except Exception:
        pass

    for text in bpy.data.texts:
        if text.filepath:
            add(Path(bpy.path.abspath(text.filepath)))

    try:
        script_file = Path(__file__)
        if script_file.suffix == ".py" and script_file.exists():
            add(script_file)
    except Exception:
        pass

    if bpy.data.filepath:
        add(Path(bpy.path.abspath(bpy.data.filepath)).parent)

    add(Path.cwd())
    return candidates


def find_repo_root(start: Path) -> Path:
    start = start.resolve()
    if start.is_file():
        start = start.parent
    for candidate in [start, *start.parents]:
        if (candidate / "game").is_dir() and (candidate / "tools").is_dir():
            return candidate
    raise RuntimeError(f"Could not locate Empire of Minds repo root from: {start}")


def _resolve_repo_root() -> tuple[Path, list[Path]]:
    examined_starts = _candidate_start_paths()
    if not examined_starts:
        raise RuntimeError(
            "No start path candidates for repo root resolution. "
            "Open the external .py file in Blender or save the .blend inside the repo."
        )

    last_error: RuntimeError | None = None
    repo_root: Path | None = None
    for start in examined_starts:
        try:
            repo_root = find_repo_root(start)
            break
        except RuntimeError as exc:
            last_error = exc

    if repo_root is None:
        starts_text = "\n".join(f"- {path}" for path in examined_starts)
        raise RuntimeError(
            "Could not locate Empire of Minds repo root.\n\n"
            f"Examined starts:\n{starts_text}\n\n"
            f"Last error: {last_error}"
        )
    return repo_root, examined_starts


def _terrain_baseline_script_path(repo_root: Path) -> Path:
    return repo_root / "tools" / "blender" / "terrain" / TERRAIN_BASELINE_SCRIPT


def _load_terrain_baseline_module(repo_root: Path, *, examined_starts: list[Path]) -> object:
    terrain_path = _terrain_baseline_script_path(repo_root)
    if not terrain_path.is_file():
        starts_text = "\n".join(f"- {path}" for path in examined_starts)
        raise RuntimeError(
            "Terrain baseline script not found.\n\n"
            f"Examined starts:\n{starts_text}\n\n"
            f"Resolved repo root:\n{repo_root}\n\n"
            f"Expected baseline:\n{terrain_path}"
        )

    _log(f"terrain baseline script: {terrain_path}")
    module_name = "eom_terrain_blender_porting_baseline_handdrawn_test"
    spec = importlib.util.spec_from_file_location(module_name, terrain_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load terrain baseline module from {terrain_path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


def _assert_terrain_baseline_unchanged(terrain: object) -> None:
    if getattr(terrain, "ALLOW_BLENDER_PORTING_BASELINE_RETUNE", True):
        raise RuntimeError(
            "Terrain baseline retune flag must be False "
            f"(got {getattr(terrain, 'ALLOW_BLENDER_PORTING_BASELINE_RETUNE', None)!r})"
        )


def _cube_round(q: float, r: float, s: float) -> tuple[int, int]:
    rq = round(q)
    rr = round(r)
    rs = round(s)
    q_diff = abs(rq - q)
    r_diff = abs(rr - r)
    s_diff = abs(rs - s)
    if q_diff > r_diff and q_diff > s_diff:
        rq = -rr - rs
    elif r_diff > s_diff:
        rr = -rq - rs
    else:
        rs = -rq - rr
    return int(rq), int(rr)


def handdrawn_to_baseline_axial(q: int, r: int) -> tuple[int, int]:
    """Map PowerPoint handdrawn (q,r) to baseline axial coords for world placement."""
    return q + r, -r


def baseline_to_handdrawn_axial(q_b: int, r_b: int) -> tuple[int, int]:
    return q_b + r_b, -r_b


def _baseline_world_xy_to_axial_round(
    wx: float,
    wy: float,
    radius: float,
) -> tuple[int, int]:
    q = (math.sqrt(3.0) / 3.0 * wx - 1.0 / 3.0 * wy) / radius
    r = (2.0 / 3.0 * wy) / radius
    return _cube_round(q, r, -q - r)


def handdrawn_world_xy_to_axial_round(wx: float, wy: float, radius: float) -> tuple[int, int]:
    q_b, r_b = _baseline_world_xy_to_axial_round(wx, wy, radius)
    return baseline_to_handdrawn_axial(q_b, r_b)


def _handdrawn_center_world_xy(terrain: object, q: int, r: int) -> tuple[float, float]:
    q_b, r_b = handdrawn_to_baseline_axial(q, r)
    return terrain.axial_to_world_xy(q_b, r_b, terrain.HEX_RADIUS)


def _point_sector(lx: float, ly: float) -> int:
    angle = math.degrees(math.atan2(ly, lx)) % 360.0
    for sector in range(6):
        a0 = (30.0 + 60.0 * float(sector)) % 360.0
        a1 = (30.0 + 60.0 * float((sector + 1) % 6)) % 360.0
        if a0 < a1:
            if a0 <= angle < a1:
                return sector
        elif angle >= a0 or angle < a1:
            return sector
    return 0


class HanddrawnMapState:
    def __init__(self, map_data: dict[str, Any], terrain: object) -> None:
        self.map_id = str(map_data["id"])
        self.orientation = str(map_data.get("orientation", ""))
        self.elevation_step = float(map_data["elevation_step"])
        edge_rule = map_data["edge_rule"]
        self.cliff_threshold = int(edge_rule["cliff_if_abs_delta_greater_than"])

        self.tiles: dict[tuple[int, int], int] = {}
        for tile in map_data["tiles"]:
            key = (int(tile["q"]), int(tile["r"]))
            if key in self.tiles:
                raise ValueError(f"duplicate tile in map: {key}")
            self.tiles[key] = int(tile["elevation"])

        self.hex_coords = set(self.tiles.keys())
        self.terrain = terrain
        self.smooth_edges: list[dict[str, Any]] = []
        self.cliff_edges: list[dict[str, Any]] = []
        self._classify_neighbor_edges()
        self.corner_heights = self._build_corner_heights()

    def elevation_to_world_z(self, elevation: int) -> float:
        return (elevation - 1) * self.elevation_step

    def tile_world_z(self, q: int, r: int) -> float:
        return self.elevation_to_world_z(self.tiles[(q, r)])

    def q_bounds(self) -> tuple[int, int]:
        qs = [q for q, _r in self.hex_coords]
        return min(qs), max(qs)

    def r_bounds(self) -> tuple[int, int]:
        rs = [r for _q, r in self.hex_coords]
        return min(rs), max(rs)

    def elevation_bounds(self) -> tuple[int, int]:
        elevations = list(self.tiles.values())
        return min(elevations), max(elevations)

    @staticmethod
    def _are_neighbors(
        t1: tuple[int, int],
        t2: tuple[int, int],
        neighbor_dirs: tuple[tuple[int, int], ...],
    ) -> bool:
        q1, r1 = t1
        q2, r2 = t2
        return (q2 - q1, r2 - r1) in neighbor_dirs

    def _classify_neighbor_edges(self) -> None:
        neighbor_dirs: tuple[tuple[int, int], ...] = self.terrain.NEIGHBOR_DIRS
        seen: set[tuple[tuple[int, int], tuple[int, int]]] = set()
        for q, r in sorted(self.hex_coords):
            for dq, dr in neighbor_dirs:
                nq, nr = q + dq, r + dr
                if (nq, nr) not in self.hex_coords:
                    continue
                edge_key = tuple(sorted(((q, r), (nq, nr))))
                if edge_key in seen:
                    continue
                seen.add(edge_key)
                e_a = self.tiles[(q, r)]
                e_b = self.tiles[(nq, nr)]
                delta = abs(e_a - e_b)
                record = {
                    "q": q,
                    "r": r,
                    "nq": nq,
                    "nr": nr,
                    "elevation_a": e_a,
                    "elevation_b": e_b,
                    "delta": delta,
                }
                if delta > self.cliff_threshold:
                    self.cliff_edges.append(record)
                else:
                    self.smooth_edges.append(record)

    def _tiles_sharing_corner(self, wx: float, wy: float) -> list[tuple[int, int]]:
        terrain = self.terrain
        target_key = terrain.pos_key(wx, wy)
        sharing: list[tuple[int, int]] = []
        for q, r in self.hex_coords:
            cx, cy = _handdrawn_center_world_xy(terrain, q, r)
            for corner_index in range(6):
                lx, ly = terrain.corner_xy_local(corner_index, terrain.HEX_RADIUS)
                if terrain.pos_key(cx + lx, cy + ly) == target_key:
                    sharing.append((q, r))
                    break
        if not sharing:
            raise RuntimeError(f"no tiles found for corner at ({wx:.6f}, {wy:.6f})")
        return sharing

    def _corner_height_from_tiles(self, sharing: list[tuple[int, int]]) -> float:
        zs = [self.tile_world_z(q, r) for q, r in sharing]
        neighbor_dirs: tuple[tuple[int, int], ...] = self.terrain.NEIGHBOR_DIRS
        has_cliff = False
        for i, t1 in enumerate(sharing):
            for t2 in sharing[i + 1 :]:
                if not self._are_neighbors(t1, t2, neighbor_dirs):
                    continue
                delta = abs(self.tiles[t1] - self.tiles[t2])
                if delta > self.cliff_threshold:
                    has_cliff = True
                    break
            if has_cliff:
                break
        if has_cliff:
            return max(zs)
        return sum(zs) / float(len(zs))

    def _build_corner_heights(self) -> dict[tuple[float, float], float]:
        terrain = self.terrain
        corner_heights: dict[tuple[float, float], float] = {}
        for q, r in self.hex_coords:
            cx, cy = _handdrawn_center_world_xy(terrain, q, r)
            for corner_index in range(6):
                lx, ly = terrain.corner_xy_local(corner_index, terrain.HEX_RADIUS)
                wx, wy = cx + lx, cy + ly
                key = terrain.pos_key(wx, wy)
                if key in corner_heights:
                    continue
                sharing = self._tiles_sharing_corner(wx, wy)
                corner_heights[key] = self._corner_height_from_tiles(sharing)
        return corner_heights

    def corner_height_at_hex(self, q: int, r: int, corner_index: int) -> float:
        terrain = self.terrain
        cx, cy = _handdrawn_center_world_xy(terrain, q, r)
        lx, ly = terrain.corner_xy_local(corner_index, terrain.HEX_RADIUS)
        key = terrain.pos_key(cx + lx, cy + ly)
        return self.corner_heights[key]

    def sample_height(self, wx: float, wy: float) -> float:
        terrain = self.terrain
        q, r = handdrawn_world_xy_to_axial_round(wx, wy, terrain.HEX_RADIUS)
        if (q, r) not in self.hex_coords:
            return terrain.BASE_HEIGHT

        q_b, r_b = handdrawn_to_baseline_axial(q, r)
        cx, cy = terrain.axial_to_world_xy(q_b, r_b, terrain.HEX_RADIUS)
        lx, ly = wx - cx, wy - cy
        if math.hypot(lx, ly) < 1e-9:
            return self.tile_world_z(q, r)

        sector = _point_sector(lx, ly)
        z_center = self.tile_world_z(q, r)
        ci = sector
        cj = (sector + 1) % 6
        z_i = self.corner_height_at_hex(q, r, ci)
        z_j = self.corner_height_at_hex(q, r, cj)

        bx, by = terrain.corner_xy_local(ci, terrain.HEX_RADIUS)
        cx_l, cy_l = terrain.corner_xy_local(cj, terrain.HEX_RADIUS)
        denom = bx * cy_l - cx_l * by
        if abs(denom) < 1e-12:
            return z_center
        wi = (lx * cy_l - ly * cx_l) / denom
        wj = (ly * bx - lx * by) / denom
        w0 = 1.0 - wi - wj
        return w0 * z_center + wi * z_i + wj * z_j


def _install_handdrawn_mesh_builder(terrain: object) -> None:
    """Reuse baseline mesh builder with correct patch-center averaging for N hexes."""
    source = inspect.getsource(terrain.build_single_patch_mesh)
    source = textwrap.dedent(source)
    source = source.replace("/ 7.0", "/ float(len(PROTOTYPE_HEXES))")
    local_ns = dict(vars(terrain))
    exec(compile(source, getattr(terrain, "__file__", "<terrain>"), "exec"), local_ns)
    terrain.build_single_patch_mesh = local_ns["build_single_patch_mesh"]


def _apply_handdrawn_patches(terrain: object, map_state: HanddrawnMapState) -> None:
    prototype_hexes = tuple(
        (
            *handdrawn_to_baseline_axial(q, r),
            elevation - 1,
            f"E{elevation}",
        )
        for (q, r), elevation in sorted(map_state.tiles.items())
    )
    terrain.PROTOTYPE_HEXES = prototype_hexes
    terrain.ELEVATION_STEP = map_state.elevation_step
    terrain.HILL_HEIGHT = map_state.elevation_step

    terrain.COLLECTION_NAME = COLLECTION_NAME
    terrain.TERRAIN_OBJECT_NAME = TERRAIN_OBJECT_NAME
    terrain.OVERLAY_OBJECT_NAME = OVERLAY_OBJECT_NAME
    terrain.OUTPUT_BLEND_FILENAME = OUTPUT_BLEND_FILENAME
    terrain.OUTPUT_GLB_FILENAME = OUTPUT_GLB_FILENAME
    terrain.SAVE_BLEND = SAVE_BLEND
    terrain.EXPORT_GLB = EXPORT_GLB
    terrain.CREATE_HEX_OVERLAY = True

    terrain.sample_radial_height = map_state.sample_height
    _install_handdrawn_mesh_builder(terrain)


def _resolve_output_blend_path(repo_root: Path) -> Path:
    global OUTPUT_BLEND_PATH
    output_dir = (
        repo_root
        / "game"
        / "assets"
        / "prototype"
        / "3d"
        / "terrain"
        / "prototype_3d_terrain"
        / "generated"
    )
    OUTPUT_BLEND_PATH = output_dir / OUTPUT_BLEND_FILENAME
    return OUTPUT_BLEND_PATH


def _adjust_camera_for_map(terrain: object, map_state: HanddrawnMapState) -> None:
    wx_values: list[float] = []
    wy_values: list[float] = []
    for q, r in map_state.hex_coords:
        cx, cy = _handdrawn_center_world_xy(terrain, q, r)
        for corner_index in range(6):
            lx, ly = terrain.corner_xy_local(corner_index, terrain.HEX_RADIUS)
            wx_values.append(cx + lx)
            wy_values.append(cy + ly)

    center_x = (min(wx_values) + max(wx_values)) * 0.5
    center_y = (min(wy_values) + max(wy_values)) * 0.5
    extent = max(max(wx_values) - min(wx_values), max(wy_values) - min(wy_values), 1.0)

    cam_obj = bpy.data.objects.get(terrain.CAMERA_NAME)
    if cam_obj is None:
        return
    cam_obj.location = Vector((center_x, center_y - extent * 1.15, extent * 0.75 + 2.5))
    cam_obj.rotation_euler = (math.radians(58.0), 0.0, 0.0)


def _print_coordinate_orientation_audit(terrain: object, map_state: HanddrawnMapState) -> None:
    radius = terrain.HEX_RADIUS
    anchors = ((0, 0), (1, 0), (0, 1))
    world_xy: dict[tuple[int, int], tuple[float, float]] = {}
    for q, r in anchors:
        world_xy[(q, r)] = _handdrawn_center_world_xy(terrain, q, r)

    x00, y00 = world_xy[(0, 0)]
    x10, y10 = world_xy[(1, 0)]
    x01, y01 = world_xy[(0, 1)]

    vec_right = (x10 - x00, y10 - y00)
    vec_down_right = (x01 - x00, y01 - y00)
    dist_00_10 = math.hypot(vec_right[0], vec_right[1])
    dist_00_01 = math.hypot(vec_down_right[0], vec_down_right[1])
    dist_10_01 = math.hypot(x01 - x10, y01 - y10)

    right_of_origin = vec_right[0] > 0.0 and abs(vec_right[1]) < 1e-6
    down_right_of_origin = vec_down_right[0] > 0.0 and vec_down_right[1] < 0.0

    _log("--- handdrawn coordinate orientation audit ---")
    _log(f"world XY (0,0): ({x00:.6f}, {y00:.6f})")
    _log(f"world XY (1,0): ({x10:.6f}, {y10:.6f})")
    _log(f"world XY (0,1): ({x01:.6f}, {y01:.6f})")
    _log(f"center distance (0,0)-(1,0): {dist_00_10:.6f}")
    _log(f"center distance (0,0)-(0,1): {dist_00_01:.6f}")
    _log(f"center distance (1,0)-(0,1): {dist_10_01:.6f}")
    _log(f"neighbor vector (0,0)->(1,0): ({vec_right[0]:.6f}, {vec_right[1]:.6f})")
    _log(f"neighbor vector (0,0)->(0,1): ({vec_down_right[0]:.6f}, {vec_down_right[1]:.6f})")
    _log(
        f"(1,0) right of (0,0): {right_of_origin} "
        f"(delta x={vec_right[0]:.6f}, delta y={vec_right[1]:.6f})"
    )
    _log(
        f"(0,1) down-right of (0,0): {down_right_of_origin} "
        f"(delta x={vec_down_right[0]:.6f}, delta y={vec_down_right[1]:.6f})"
    )

    expected_center_dist = radius * math.sqrt(3.0)
    if abs(dist_00_10 - expected_center_dist) > 1e-5:
        raise RuntimeError(
            f"unexpected (0,0)-(1,0) center distance: {dist_00_10:.6f}, "
            f"expected {expected_center_dist:.6f}"
        )
    if abs(dist_00_01 - expected_center_dist) > 1e-5:
        raise RuntimeError(
            f"unexpected (0,0)-(0,1) center distance: {dist_00_01:.6f}, "
            f"expected {expected_center_dist:.6f}"
        )

    center_keys: dict[tuple[float, float], tuple[int, int]] = {}
    for q, r in sorted(map_state.hex_coords):
        cx, cy = _handdrawn_center_world_xy(terrain, q, r)
        key = terrain.pos_key(cx, cy)
        existing = center_keys.get(key)
        if existing is not None:
            raise RuntimeError(
                f"duplicate pos_key for tile centers: {existing} and {(q, r)} "
                f"both map to {key}"
            )
        center_keys[key] = (q, r)

    min_center_separation = expected_center_dist
    near_duplicate_count = 0
    centers = [
        (_handdrawn_center_world_xy(terrain, q, r), (q, r)) for q, r in map_state.hex_coords
    ]
    for i, ((ax, ay), tile_a) in enumerate(centers):
        for (bx, by), tile_b in centers[i + 1 :]:
            separation = math.hypot(ax - bx, ay - by)
            if separation < min_center_separation:
                min_center_separation = separation
            if separation < expected_center_dist - 1e-4:
                near_duplicate_count += 1

    sample_world_points = (
        world_xy[(0, 0)],
        world_xy[(1, 0)],
        world_xy[(0, 1)],
        (x00 + 0.25, y00 - 0.1),
    )
    pos_keys = [terrain.pos_key(wx, wy) for wx, wy in sample_world_points]
    if len(set(pos_keys)) != len(pos_keys):
        raise RuntimeError(f"pos_key collision among sample world points: {pos_keys}")

    _log(f"unique tile center pos_keys: {len(center_keys)} / {len(map_state.hex_coords)}")
    _log(f"near-duplicate center pairs (< neighbor spacing): {near_duplicate_count}")
    _log(f"minimum center separation: {min_center_separation:.6f}")
    _log(f"pos_key precision: 6 decimals (baseline pos_key)")
    _log(f"sample pos_keys: {pos_keys}")

    if not (right_of_origin and down_right_of_origin):
        raise RuntimeError("handdrawn coordinate orientation audit failed")


def _print_map_audit(map_state: HanddrawnMapState, output_path: Path) -> None:
    q_min, q_max = map_state.q_bounds()
    r_min, r_max = map_state.r_bounds()
    e_min, e_max = map_state.elevation_bounds()
    _log("--- handdrawn map audit ---")
    _log(f"map id: {map_state.map_id}")
    _log(f"tile count: {len(map_state.hex_coords)}")
    _log(f"q bounds: [{q_min}, {q_max}]")
    _log(f"r bounds: [{r_min}, {r_max}]")
    _log(f"elevation min/max: [{e_min}, {e_max}]")
    _log(f"smooth neighbor edges: {len(map_state.smooth_edges)}")
    _log(f"cliff neighbor edges: {len(map_state.cliff_edges)}")
    _log(f"output path: {output_path}")
    for edge in map_state.cliff_edges:
        _log(
            "cliff edge: "
            f"({edge['q']},{edge['r']}) elevation {edge['elevation_a']} "
            f"<-> ({edge['nq']},{edge['nr']}) elevation {edge['elevation_b']} "
            f"(delta {edge['delta']})"
        )


def _save_blend(output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    scene = bpy.context.scene
    wm = bpy.context.window_manager
    override: dict[str, Any] = {"scene": scene}
    if wm is not None and wm.windows:
        window = wm.windows[0]
        screen = window.screen
        override["window"] = window
        override["screen"] = screen
        for area in screen.areas:
            if area.type in {"VIEW_3D", "TEXT_EDITOR", "PROPERTIES", "OUTLINER"}:
                region = next((r for r in area.regions if r.type == "WINDOW"), None)
                if region is not None:
                    override["area"] = area
                    override["region"] = region
                    break
    with bpy.context.temp_override(**override):
        bpy.ops.wm.save_as_mainfile(filepath=str(output_path))
    _log(f"saved blend: {output_path}")


def main() -> None:
    map_data = json.loads(HANDDRAWN_MAP_JSON)
    if map_data.get("orientation") != "pointy_top_custom_axes":
        raise ValueError(
            f"unsupported orientation {map_data.get('orientation')!r}; "
            "expected 'pointy_top_custom_axes'"
        )

    repo_root, examined_starts = _resolve_repo_root()
    _log(f"repo root: {repo_root}")

    terrain = _load_terrain_baseline_module(repo_root, examined_starts=examined_starts)
    _assert_terrain_baseline_unchanged(terrain)

    map_state = HanddrawnMapState(map_data, terrain)
    _apply_handdrawn_patches(terrain, map_state)

    output_path = _resolve_output_blend_path(repo_root)

    terrain.validate_params()
    terrain.validate_material_params()

    ground_albedo_path, ground_normal_path, ground_roughness_path = (
        terrain.resolve_ground_texture_paths(repo_root)
    )
    stone_albedo_path, stone_normal_path, stone_roughness_path = (
        terrain.resolve_stone_texture_paths(repo_root)
    )
    ash_albedo_path, ash_normal_path, ash_roughness_path = terrain.resolve_ash_texture_paths(
        repo_root
    )

    _log(f"generating handdrawn map terrain: {map_state.map_id}")
    _log(f"elevation step: {map_state.elevation_step}")
    _log(f"orientation: {map_state.orientation}")
    _print_coordinate_orientation_audit(terrain, map_state)

    terrain.clear_scene()
    coll = terrain.ensure_collection(terrain.COLLECTION_NAME)
    hex_coords = terrain.build_hex_coords_set()

    procedural_material = terrain.make_pbr_ground_stone_ash_terrain_material(
        ground_albedo_path,
        ground_normal_path,
        ground_roughness_path,
        ash_albedo_path,
        ash_normal_path,
        ash_roughness_path,
        stone_albedo_path,
        stone_normal_path,
        stone_roughness_path,
    )
    side_material = terrain.make_side_terrain_material()
    terrain._log_material_setup()

    terrain_mesh, stats = terrain.build_single_patch_mesh(hex_coords)
    terrain.assign_world_anchored_top_uv(terrain_mesh, stats["top_faces"])
    terrain.assign_patch_materials(
        terrain_mesh,
        stats["top_faces"],
        procedural_material,
        side_material,
    )
    terrain_obj = bpy.data.objects.new(terrain.TERRAIN_OBJECT_NAME, terrain_mesh)
    coll.objects.link(terrain_obj)
    _log("terrain mesh created")
    _log(f"top vertices: {stats['top_verts']}")
    _log(f"top faces: {stats['top_faces']}")
    _log(f"total vertices: {stats['total_verts']}")
    _log(f"total faces: {stats['total_faces']}")

    if terrain.CREATE_HEX_OVERLAY:
        overlay_material = terrain.make_overlay_material()
        overlay_mesh, overlay_stats = terrain.build_hex_overlay_mesh()
        overlay_obj = bpy.data.objects.new(terrain.OVERLAY_OBJECT_NAME, overlay_mesh)
        overlay_obj.data.materials.append(overlay_material)
        coll.objects.link(overlay_obj)
        _log("hex overlay created")
        _log(f"unique overlay edges: {overlay_stats['unique_edges']}")

    terrain.setup_camera_and_lights()
    _adjust_camera_for_map(terrain, map_state)
    terrain.setup_render_and_world()
    terrain._log_ash_brightness_audit(
        procedural_material,
        ground_albedo_path=ground_albedo_path,
        ground_normal_path=ground_normal_path,
        ground_roughness_path=ground_roughness_path,
        ash_albedo_path=ash_albedo_path,
        ash_normal_path=ash_normal_path,
        ash_roughness_path=ash_roughness_path,
        stone_albedo_path=stone_albedo_path,
        stone_normal_path=stone_normal_path,
        stone_roughness_path=stone_roughness_path,
    )

    if SAVE_BLEND:
        _save_blend(output_path)

    _print_map_audit(map_state, output_path)
    _log("done")


if __name__ == "__main__":
    main()
