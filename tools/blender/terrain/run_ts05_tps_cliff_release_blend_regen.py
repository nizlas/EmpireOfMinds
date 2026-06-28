# Empire of Minds — TS-05 TPS cliff-band release prototype blend regeneration.
# Run: blender --background --python tools/blender/terrain/run_ts05_tps_cliff_release_blend_regen.py
# Leaves generate_terrain_terrainmap_handdrawn_full_01.py toggles at default False.

from __future__ import annotations

import importlib
import importlib.util
import os
import re
import sys
from pathlib import Path

_GENERATOR_NAME = "generate_terrain_terrainmap_handdrawn_full_01.py"
_TS05_MODULE_NAME = "eom_terrain_tps_cliff_release"
_TS05_DEBUG_MODULE_NAME = "eom_terrain_tps_cliff_release_debug"
_TS05_VERSION = "ts05_guarded_2026_06_27"
_TERRAIN_MODULES_TO_EVICT = (
    "eom_gen_full01",
    _TS05_MODULE_NAME,
    _TS05_DEBUG_MODULE_NAME,
    "eom_terrain_variational_spline",
    "eom_terrain_solver",
    "eom_terrain_math_core",
    "eom_terrain_fem_thin_plate",
    "eom_terrain_global_biharmonic",
    "eom_hexpatch_surface",
    "eom_hexpatch_v1_graph",
)


def _resolve_terrain_tools_dir() -> Path:
    """Locate tools/blender/terrain; prefer this script's directory over blend CWD/text blocks."""
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

    # Do not prefer bpy.data.texts paths: embedded/stale text blocks can shadow repo scripts.
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


def _verify_ts05_on_disk(script_dir: Path) -> Path:
    ts05_path = script_dir / f"{_TS05_MODULE_NAME}.py"
    if not ts05_path.is_file():
        raise FileNotFoundError(f"Missing TS-05 module on disk: {ts05_path}")
    text = ts05_path.read_text(encoding="utf-8")
    call_count = len(re.findall(r"(?<!_)solve_component_field\(", text))
    has_guarded = "_guarded_solve_component_field" in text
    has_version = _TS05_VERSION in text
    print("[TS-05 bootstrap] cwd:", os.getcwd())
    print("[TS-05 bootstrap] sys.path[:10]:", sys.path[:10])
    print("[TS-05 bootstrap] terrain tools dir:", script_dir)
    print("[TS-05 bootstrap] ts05 file:", ts05_path)
    print(f"[TS-05 bootstrap] solve_component_field( count: {call_count}")
    print(f"[TS-05 bootstrap] has _guarded_solve_component_field: {has_guarded}")
    print(f"[TS-05 bootstrap] has version stamp {_TS05_VERSION!r}: {has_version}")
    if call_count != 1 or not has_guarded or not has_version:
        raise RuntimeError(
            f"Stale or wrong {_TS05_MODULE_NAME}.py at {ts05_path}; "
            f"call_count={call_count}, has_guarded={has_guarded}, has_version={has_version}"
        )
    debug_path = script_dir / f"{_TS05_DEBUG_MODULE_NAME}.py"
    print(f"[TS-05 bootstrap] ts05 debug file: {debug_path}")
    print(f"[TS-05 bootstrap] has debug overlay module: {debug_path.is_file()}")
    if not debug_path.is_file():
        raise FileNotFoundError(f"Missing TS-05 debug module on disk: {debug_path}")
    return ts05_path


def _bootstrap_terrain_imports(script_dir: Path) -> None:
    _insert_terrain_tools_dir_first(script_dir)
    evicted = _evict_stale_terrain_modules()
    if evicted:
        print("[TS-05 bootstrap] evicted stale sys.modules:", evicted)
    ts05_mod = importlib.import_module(_TS05_MODULE_NAME)
    ts05_file = getattr(ts05_mod, "__file__", None)
    ts05_version = getattr(ts05_mod, "TS05_MODULE_VERSION", None)
    print("[TS-05 bootstrap] imported module file:", ts05_file)
    print("[TS-05 bootstrap] imported module version:", ts05_version)
    expected = script_dir / f"{_TS05_MODULE_NAME}.py"
    if ts05_file is None or Path(ts05_file).resolve() != expected.resolve():
        raise RuntimeError(
            f"Wrong {_TS05_MODULE_NAME} imported: {ts05_file!r}; expected {expected!r}"
        )
    if ts05_version != _TS05_VERSION:
        raise RuntimeError(
            f"Wrong TS-05 module version: {ts05_version!r}; expected {_TS05_VERSION!r}"
        )


SCRIPT_DIR = _resolve_terrain_tools_dir()
_verify_ts05_on_disk(SCRIPT_DIR)
_bootstrap_terrain_imports(SCRIPT_DIR)

GENERATOR = SCRIPT_DIR / _GENERATOR_NAME

spec = importlib.util.spec_from_file_location("eom_gen_full01", GENERATOR)
if spec is None or spec.loader is None:
    raise RuntimeError(f"Could not load {GENERATOR}")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

module.PROTOTYPE_ID = "TS-05"
module.RUNNER_FILE = __file__
module.USE_VARIATIONAL_SPLINE_SURFACE = True
module.USE_TPS_CLIFF_RELEASE = True
module.USE_TS05_DEBUG_OVERLAY = True
print(
    "[TS-05] USE_VARIATIONAL_SPLINE_SURFACE=True + USE_TPS_CLIFF_RELEASE=True "
    "+ USE_TS05_DEBUG_OVERLAY=True (TPS cliff-band release prototype)"
)
print(
    f"[TS-05] generator flags: USE_TPS_CLIFF_RELEASE={module.USE_TPS_CLIFF_RELEASE} "
    f"USE_TS05_DEBUG_OVERLAY={getattr(module, 'USE_TS05_DEBUG_OVERLAY', None)}"
)
module.main()
