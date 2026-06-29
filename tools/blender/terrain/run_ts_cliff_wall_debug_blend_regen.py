# Empire of Minds — TS-03e cliff wall visibility debug blend regeneration.
# Run: blender --background --python tools/blender/terrain/run_ts_cliff_wall_debug_blend_regen.py

from __future__ import annotations

import importlib.util
from pathlib import Path

_GENERATOR_NAME = "generate_terrain_terrainmap_handdrawn_full_01.py"


def _resolve_terrain_tools_dir() -> Path:
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
    raise FileNotFoundError(f"Could not locate {_GENERATOR_NAME}")


SCRIPT_DIR = _resolve_terrain_tools_dir()
GENERATOR = SCRIPT_DIR / _GENERATOR_NAME

spec = importlib.util.spec_from_file_location("eom_gen_full01", GENERATOR)
if spec is None or spec.loader is None:
    raise RuntimeError(f"Could not load {GENERATOR}")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

module.PROTOTYPE_ID = "TS-03e"
module.RUNNER_FILE = __file__
module.USE_VARIATIONAL_SPLINE_SURFACE = True
module.DEBUG_SHOW_CLIFF_WALLS = True
module.DEBUG_HIDE_TOP_SURFACE = True
print("[TS-03e] cliff wall debug regen (variational spline + mid-grey walls + hidden top)")
module.main()
