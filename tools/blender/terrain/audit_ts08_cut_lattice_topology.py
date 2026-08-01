# Empire of Minds — TS-08 Stage 0 cut-lattice topology audit (read-only).
# Run: blender --background --python tools/blender/terrain/audit_ts08_cut_lattice_topology.py
#
# STRICTLY READ-ONLY: no height solve, no mesh output, no blend save.

from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

try:
    SCRIPT_DIR = Path(__file__).resolve().parent
except NameError:
    SCRIPT_DIR = Path.cwd()

if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

_FULL01_MODULE_NAME = "generate_terrain_terrainmap_handdrawn_full_01.py"
_REPORT_DIR = SCRIPT_DIR / "reports"
_REPORT_PATH = _REPORT_DIR / "ts08_cut_lattice_topology_audit.json"


def _load_full01_module():
    generator_path = SCRIPT_DIR / _FULL01_MODULE_NAME
    if not generator_path.is_file():
        raise FileNotFoundError(f"Missing shared generator: {generator_path}")
    spec = importlib.util.spec_from_file_location("eom_gen_full01_ts08", generator_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load {generator_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _resolve_runner_file() -> str:
    try:
        return str(Path(__file__).resolve())
    except NameError:
        return str(SCRIPT_DIR / "audit_ts08_cut_lattice_topology.py")


def main() -> None:
    from eom_terrain_ts08_cut_lattice import (
        MAP_ID,
        MAP_JSON_ID,
        print_audit_report,
        print_traceability_banner,
        report_to_dict,
        run_cut_lattice_topology_audit,
    )

    runner_file = _resolve_runner_file()
    print_traceability_banner(phase="START", runner_file=runner_file)

    full01 = _load_full01_module()
    from eom_map_content import load_reference_map_envelope

    envelope = load_reference_map_envelope()
    if envelope["logical_map"].get("id") != MAP_JSON_ID:
        print(
            f"WARNING: terrain json id={envelope['logical_map'].get('id')!r} "
            f"(expected {MAP_JSON_ID})"
        )
    terrain_map = full01.parse_terrain_map_json(full01.TERRAIN_MAP_JSON)
    if terrain_map.map_id != MAP_JSON_ID:
        print(
            f"WARNING: terrain json id={terrain_map.map_id!r} "
            f"(expected {MAP_JSON_ID})"
        )
    model = full01.build_terrain_model(terrain_map)
    repo_root, examined_starts = full01._resolve_repo_root()
    baseline = full01._load_baseline_module(repo_root, examined_starts=examined_starts)

    report = run_cut_lattice_topology_audit(model, baseline, map_id=MAP_ID)
    print_audit_report(report)

    _REPORT_DIR.mkdir(parents=True, exist_ok=True)
    with _REPORT_PATH.open("w", encoding="utf-8") as handle:
        json.dump(report_to_dict(report), handle, indent=2)
    print(f"JSON_REPORT_PATH={_REPORT_PATH.resolve()}")

    print_traceability_banner(phase="END", runner_file=runner_file)
    if not report.passed:
        sys.exit(1)


if __name__ == "__main__":
    main()
