# Empire of Minds — TS-06 TPS rim-constraints prototype blend regeneration.
# Run: blender --background --python tools/blender/terrain/run_ts06_tps_rim_constraints_blend_regen.py
# Leaves generate_terrain_terrainmap_handdrawn_full_01.py toggles at default False.

from __future__ import annotations

import importlib
import importlib.util
import os
import sys
from pathlib import Path

_GENERATOR_NAME = "generate_terrain_terrainmap_handdrawn_full_01.py"
_TS06_MODULE_NAME = "eom_terrain_tps_rim_constraints"
_TS06_VERSION = "ts06_rim_constraints_2026_06_28"
_TERRAIN_MODULES_TO_EVICT = (
    "eom_gen_full01",
    _TS06_MODULE_NAME,
    "eom_terrain_tps_cliff_release",
    "eom_terrain_tps_cliff_release_debug",
    "eom_terrain_variational_spline",
    "eom_terrain_solver",
    "eom_terrain_math_core",
    "eom_terrain_fem_thin_plate",
    "eom_terrain_global_biharmonic",
    "eom_hexpatch_surface",
    "eom_hexpatch_v1_graph",
)


def _resolve_terrain_tools_dir() -> Path:
    try:
        here = Path(__file__).resolve()
        if (here.parent / _GENERATOR_NAME).is_file():
            return here.parent
    except NameError:
        pass

    starts: list[Path] = []
    try:
        import bpy

        script_path = bpy.path.abspath(__file__)
        if script_path:
            starts.append(Path(script_path).resolve().parent)
    except (ImportError, NameError, TypeError):
        pass

    try:
        here = Path(__file__)
        if here.is_absolute():
            starts.append(here.resolve().parent)
    except NameError:
        pass

    seen: set[str] = set()
    for start in starts:
        key = str(start.resolve())
        if key in seen:
            continue
        seen.add(key)
        for candidate in (start, *start.parents):
            if (candidate / _GENERATOR_NAME).is_file():
                return candidate
            terrain = candidate / "tools" / "blender" / "terrain"
            if (terrain / _GENERATOR_NAME).is_file():
                return terrain

    raise FileNotFoundError(
        f"Could not locate tools/blender/terrain/{_GENERATOR_NAME}; "
        f"searched from: {[str(s) for s in starts]}"
    )


def _evict_stale_terrain_modules() -> list[str]:
    evicted: list[str] = []
    for name in _TERRAIN_MODULES_TO_EVICT:
        if name in sys.modules:
            evicted.append(name)
            del sys.modules[name]
    return evicted


def _insert_terrain_tools_dir_first(script_dir: Path) -> None:
    script_dir_str = str(script_dir.resolve())
    while script_dir_str in sys.path:
        sys.path.remove(script_dir_str)
    sys.path.insert(0, script_dir_str)


def _verify_ts06_on_disk(script_dir: Path) -> Path:
    ts06_path = script_dir / f"{_TS06_MODULE_NAME}.py"
    if not ts06_path.is_file():
        raise FileNotFoundError(f"Missing TS-06 module on disk: {ts06_path}")
    text = ts06_path.read_text(encoding="utf-8")
    has_version = _TS06_VERSION in text
    print("[TS-06 bootstrap] cwd:", os.getcwd())
    print("[TS-06 bootstrap] terrain tools dir:", script_dir)
    print("[TS-06 bootstrap] ts06 file:", ts06_path)
    print(f"[TS-06 bootstrap] has version stamp {_TS06_VERSION!r}: {has_version}")
    if not has_version:
        raise RuntimeError(f"Stale or wrong {_TS06_MODULE_NAME}.py at {ts06_path}")
    return ts06_path


def _bootstrap_terrain_imports(script_dir: Path) -> None:
    _insert_terrain_tools_dir_first(script_dir)
    evicted = _evict_stale_terrain_modules()
    if evicted:
        print("[TS-06 bootstrap] evicted stale sys.modules:", evicted)
    ts06_mod = importlib.import_module(_TS06_MODULE_NAME)
    ts06_file = getattr(ts06_mod, "__file__", None)
    ts06_version = getattr(ts06_mod, "TS06_MODULE_VERSION", None)
    print("[TS-06 bootstrap] imported module file:", ts06_file)
    print("[TS-06 bootstrap] imported module version:", ts06_version)
    expected = script_dir / f"{_TS06_MODULE_NAME}.py"
    if ts06_file is None or Path(ts06_file).resolve() != expected.resolve():
        raise RuntimeError(
            f"Wrong {_TS06_MODULE_NAME} imported: {ts06_file!r}; expected {expected!r}"
        )
    if ts06_version != _TS06_VERSION:
        raise RuntimeError(
            f"Wrong TS-06 module version: {ts06_version!r}; expected {_TS06_VERSION!r}"
        )


SCRIPT_DIR = _resolve_terrain_tools_dir()
_verify_ts06_on_disk(SCRIPT_DIR)
_bootstrap_terrain_imports(SCRIPT_DIR)

GENERATOR = SCRIPT_DIR / _GENERATOR_NAME

spec = importlib.util.spec_from_file_location("eom_gen_full01", GENERATOR)
if spec is None or spec.loader is None:
    raise RuntimeError(f"Could not load {GENERATOR}")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

module.USE_VARIATIONAL_SPLINE_SURFACE = True
module.USE_TPS_RIM_CONSTRAINTS = True
module.USE_TPS_CLIFF_RELEASE = False
module.USE_TS05_DEBUG_OVERLAY = False
print(
    "[TS-06] USE_VARIATIONAL_SPLINE_SURFACE=True + USE_TPS_RIM_CONSTRAINTS=True "
    "(TPS cliff-front rim constraint prototype)"
)
print(
    f"[TS-06] generator flags: USE_TPS_RIM_CONSTRAINTS={module.USE_TPS_RIM_CONSTRAINTS} "
    f"USE_TPS_CLIFF_RELEASE={module.USE_TPS_CLIFF_RELEASE}"
)
module.main()
