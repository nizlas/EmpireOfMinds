# Empire of Minds — TS-03 one-shot VariationalSpline blend regeneration helper.
# Run: blender --background --python tools/blender/terrain/run_ts_variational_spline_blend_regen.py
# Leaves generate_terrain_terrainmap_handdrawn_full_01.py toggle at False.

from __future__ import annotations

import importlib.util
from pathlib import Path

_GENERATOR_NAME = "generate_terrain_terrainmap_handdrawn_full_01.py"


def _resolve_terrain_tools_dir() -> Path:
    """Locate tools/blender/terrain; never infer generator path from blend CWD alone."""
    starts: list[Path] = []

    try:
        import bpy

        script_path = bpy.path.abspath(__file__)
        if script_path:
            starts.append(Path(script_path).resolve().parent)
        for text in bpy.data.texts:
            if text.filepath and Path(text.filepath).name == "run_ts_variational_spline_blend_regen.py":
                starts.append(Path(bpy.path.abspath(text.filepath)).resolve().parent)
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


SCRIPT_DIR = _resolve_terrain_tools_dir()
GENERATOR = SCRIPT_DIR / _GENERATOR_NAME

spec = importlib.util.spec_from_file_location("eom_gen_full01", GENERATOR)
if spec is None or spec.loader is None:
    raise RuntimeError(f"Could not load {GENERATOR}")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

module.USE_VARIATIONAL_SPLINE_SURFACE = True
print("[TS-03] USE_VARIATIONAL_SPLINE_SURFACE=True (variational spline regeneration)")
module.main()
