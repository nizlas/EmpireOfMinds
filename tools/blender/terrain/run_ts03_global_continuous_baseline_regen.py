# Empire of Minds — TS-03 global continuous baseline regeneration runner.
# Run: blender --background --python tools/blender/terrain/run_ts03_global_continuous_baseline_regen.py
# Or:  Blender Text Editor → Text → Open this file from disk → Run Script

from __future__ import annotations

import importlib.util
import os
from pathlib import Path

_RUNNER_NAME = "run_ts03_global_continuous_baseline_regen.py"
_BASELINE_GENERATOR = "generate_ts03_global_continuous_baseline.py"


def _is_real_file(path: Path) -> bool:
    try:
        return path.is_file()
    except OSError:
        return False


def _collect_candidate_starts() -> tuple[list[Path], dict[str, object]]:
    starts: list[Path] = []
    debug: dict[str, object] = {
        "file_available": False,
        "file_path": None,
        "text_editor_filepath_available": False,
        "text_editor_filepath": None,
        "env_eom_repo_root": os.environ.get("EOM_REPO_ROOT"),
    }

    try:
        here = Path(__file__)
        if here.is_absolute() and _is_real_file(here):
            resolved = here.resolve()
            debug["file_available"] = True
            debug["file_path"] = str(resolved)
            starts.append(resolved.parent)
    except NameError:
        pass

    try:
        import bpy

        space = bpy.context.space_data
        if space is not None and getattr(space, "type", None) == "TEXT_EDITOR":
            text = getattr(space, "text", None)
            if text is not None and text.filepath:
                text_path = Path(bpy.path.abspath(text.filepath)).resolve()
                if _is_real_file(text_path):
                    debug["text_editor_filepath_available"] = True
                    debug["text_editor_filepath"] = str(text_path)
                    starts.append(text_path.parent)

        for text in bpy.data.texts:
            if not text.filepath:
                continue
            if Path(text.filepath).name not in {_RUNNER_NAME, _BASELINE_GENERATOR}:
                continue
            text_path = Path(bpy.path.abspath(text.filepath)).resolve()
            if _is_real_file(text_path):
                if Path(text.filepath).name == _RUNNER_NAME:
                    debug["text_editor_filepath_available"] = True
                    debug["text_editor_filepath"] = str(text_path)
                starts.append(text_path.parent)
    except (ImportError, AttributeError, TypeError):
        pass

    env_root = os.environ.get("EOM_REPO_ROOT")
    if env_root:
        starts.append(Path(env_root).resolve())

    starts.append(Path.cwd().resolve())

    seen: set[str] = set()
    deduped: list[Path] = []
    for start in starts:
        key = str(start.resolve())
        if key in seen:
            continue
        seen.add(key)
        deduped.append(start.resolve())

    return deduped, debug


def _find_tools_dir_from(starts: list[Path]) -> tuple[Path | None, list[str]]:
    searched_roots: list[str] = []
    for start in starts:
        for candidate in (start, *start.parents):
            root_key = str(candidate.resolve())
            if root_key not in searched_roots:
                searched_roots.append(root_key)
            if (candidate / _BASELINE_GENERATOR).is_file():
                return candidate, searched_roots
            terrain = candidate / "tools" / "blender" / "terrain"
            if (terrain / _BASELINE_GENERATOR).is_file():
                return terrain, searched_roots
    return None, searched_roots


def _resolve_terrain_tools_dir() -> tuple[Path, str]:
    starts, debug = _collect_candidate_starts()
    tools_dir, searched_roots = _find_tools_dir_from(starts)
    if tools_dir is not None:
        runner_file = (
            debug.get("file_path")
            or debug.get("text_editor_filepath")
            or str(tools_dir / _RUNNER_NAME)
        )
        return tools_dir, str(runner_file)

    raise FileNotFoundError(
        f"Could not locate tools/blender/terrain/{_BASELINE_GENERATOR}.\n"
        f"Candidate start paths: {[str(s) for s in starts]}\n"
        f"Roots searched upward ({len(searched_roots)}): {searched_roots}\n"
        f"__file__ available: {debug['file_available']} ({debug['file_path']})\n"
        f"Blender Text Editor filepath available: {debug['text_editor_filepath_available']} "
        f"({debug['text_editor_filepath']})\n"
        f"EOM_REPO_ROOT: {debug['env_eom_repo_root']}\n"
        "Fix: open this script from disk via Text → Open, run Blender with --python using "
        "an absolute path to this file, or set EOM_REPO_ROOT to the repo root."
    )


SCRIPT_DIR, RUNNER_FILE = _resolve_terrain_tools_dir()
GENERATOR = SCRIPT_DIR / _BASELINE_GENERATOR

spec = importlib.util.spec_from_file_location("eom_ts03_global_baseline", GENERATOR)
if spec is None or spec.loader is None:
    raise RuntimeError(f"Could not load {GENERATOR}")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

module.RUNNER_FILE = RUNNER_FILE
print(f"[{module.PROTOTYPE_ID}] dedicated global continuous TS-03 baseline regeneration")
module.main()
