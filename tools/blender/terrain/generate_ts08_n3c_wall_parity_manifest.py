#!/usr/bin/env python3
"""Generate the test-only N3c.1 cliff-wall parity digest manifest.

Runs the accepted Python Stage-3a helper (eom_terrain_ts08_cliff_walls.
build_cliff_wall_faces) on the canonical reference map's Python cut lattice
with the accepted N2 solved heights, then stores only counts, wall-height
stats, and a SHA-256 digest over the canonical wall-face/topology stream.
No raw geometry arrays are stored. The Godot N3c.1 test rebuilds the same
stream from its own wall build and compares digests.

Canonical encoding (shared with the Godot N3c.1 test):
- One UTF-8 text line per emitted wall face, in deterministic emit order
  (cliff pairs sorted by (min_tile, max_tile) lexicographic (q, r); seam
  segments in chain order; deduped faces omitted). Each line is terminated
  by a single "\\n":
      QA;RA;QB;RB;SEG;V0;V1;V2[;V3]
  where (QA,RA) < (QB,RB) are the cliff pair tiles, SEG is the seam segment
  index, and V* are the oriented face node indices (N3a node-index space,
  accepted Python orientation toward the lower tile).
- Digest = SHA-256 over the concatenated line bytes, lowercase hex.
- Wall-height stats are informational floats (12 significant digits); the
  Godot test compares them with a 1e-6 tolerance because Godot heights come
  from its own solver, not from N2.

`check` regenerates the expected manifest and compares it with the
committed fixture. Heights are taken from the N2 golden dataset
(nodes.positions_xyz[*][1]) in N3a node-index order; N2 stays the sole
derived test authority.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parents[2]
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from eom_map_content import load_reference_logical_map  # noqa: E402
from eom_terrain_math_core import build_terrain_model, parse_terrain_map_ir  # noqa: E402
from eom_terrain_ts08_cliff_walls import CliffWallBuild, build_cliff_wall_faces  # noqa: E402
from eom_terrain_ts08_cut_lattice import (  # noqa: E402
    MAP_JSON_ID,
    build_cut_lattice_for_model,
)
from export_ts08_reference_dataset import (  # noqa: E402
    BaselineGeometryShim,
    DATASET_ID,
    _json_float,
    _source_map_identity,
)
from generate_ts08_n3b_height_golden import (  # noqa: E402
    heights_from_n2,
    load_n2_dataset,
)

MANIFEST_SCHEMA_VERSION = 1
MANIFEST_ID = "handdrawn_test_map_full_01_ts08_n3c_wall_parity_v1"
MANIFEST_REL = Path("game") / "domain" / "tests" / "fixtures" / "world" / f"{MANIFEST_ID}.json"

CANONICAL_ENCODING: dict[str, Any] = {
    "text": "UTF-8 lines terminated by '\\n'; integer fields joined by ';'",
    "digest": "sha256 lowercase hex over concatenated line bytes; all wall faces hashed",
    "wall_faces": (
        "per emitted wall face, deterministic emit order (cliff pairs sorted by "
        "(min_tile, max_tile) lexicographic (q, r), segments in chain order, deduped "
        "faces omitted): QA;RA;QB;RB;SEG;V0;V1;V2[;V3] with oriented N3a node indices"
    ),
    "wall_height_stats": (
        "informational floats (12 significant digits); Godot compares with 1e-6 "
        "tolerance against its own solver heights"
    ),
}


def sha256_hex_lower(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def wall_face_lines(wall_build: CliffWallBuild) -> list[str]:
    lines: list[str] = []
    for record in wall_build.wall_face_records:
        tile_a, tile_b = sorted(record.cliff_pair)
        fields = [
            str(int(tile_a[0])),
            str(int(tile_a[1])),
            str(int(tile_b[0])),
            str(int(tile_b[1])),
            str(int(record.segment_index)),
        ] + [str(int(v)) for v in record.vertex_indices]
        lines.append(";".join(fields))
    return lines


def wall_faces_digest(wall_build: CliffWallBuild) -> str:
    hasher = hashlib.sha256()
    for line in wall_face_lines(wall_build):
        hasher.update(line.encode("utf-8"))
        hasher.update(b"\n")
    return hasher.hexdigest()


def build_wall_parity_data(repo_root: Path) -> tuple[CliffWallBuild, dict[str, Any]]:
    map_identity = _source_map_identity(repo_root)
    n2, n2_hash = load_n2_dataset(repo_root)
    heights = heights_from_n2(n2)

    logical_map = load_reference_logical_map(repo_root=repo_root)
    terrain_map = parse_terrain_map_ir(logical_map)
    if terrain_map.map_id != MAP_JSON_ID:
        raise RuntimeError(f"Unexpected map id {terrain_map.map_id!r}")
    model = build_terrain_model(terrain_map)
    baseline = BaselineGeometryShim()
    lattice = build_cut_lattice_for_model(model, baseline)
    if lattice.node_count != len(heights):
        raise RuntimeError(
            f"Lattice node count {lattice.node_count} != N2 height count {len(heights)}"
        )

    wall_build = build_cliff_wall_faces(lattice, model, baseline, heights)

    heights_list = wall_build.wall_heights
    if not heights_list:
        raise RuntimeError("Reference map produced no wall faces")
    manifest = {
        "schema_version": MANIFEST_SCHEMA_VERSION,
        "manifest_id": MANIFEST_ID,
        "source_map_content_hash": map_identity["content_hash"],
        "source_n2_dataset_id": DATASET_ID,
        "source_n2_content_hash": n2_hash,
        "canonical_encoding": CANONICAL_ENCODING,
        "counts": {
            "top_vertex_count": int(lattice.node_count),
            "top_triangle_count": len(lattice.triangles),
            "wall_face_count": len(wall_build.wall_faces),
            "wall_segment_count": int(wall_build.segment_count),
            "wall_skipped_segment_count": int(wall_build.skipped_segment_count),
            "wall_quad_count": int(wall_build.quad_count),
            "wall_triangle_count": int(wall_build.triangle_count),
        },
        "wall_height_stats": {
            "min": _json_float(min(heights_list)),
            "mean": _json_float(sum(heights_list) / float(len(heights_list))),
            "max": _json_float(max(heights_list)),
        },
        "digests": {
            "wall_faces_sha256": wall_faces_digest(wall_build),
        },
    }
    return wall_build, manifest


def write_manifest(repo_root: Path) -> None:
    _, manifest = build_wall_parity_data(repo_root)
    out_path = repo_root / MANIFEST_REL
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"WROTE {out_path} ({out_path.stat().st_size} bytes)")
    counts = manifest["counts"]
    print(
        "wall_face_count=%d segments=%d skipped=%d quads=%d triangles=%d"
        % (
            counts["wall_face_count"],
            counts["wall_segment_count"],
            counts["wall_skipped_segment_count"],
            counts["wall_quad_count"],
            counts["wall_triangle_count"],
        )
    )
    print(f"wall_faces_sha256={manifest['digests']['wall_faces_sha256']}")
    stats = manifest["wall_height_stats"]
    print(f"wall_height min={stats['min']} mean={stats['mean']} max={stats['max']}")


def check_manifest(repo_root: Path) -> None:
    _, expected = build_wall_parity_data(repo_root)
    out_path = repo_root / MANIFEST_REL
    if not out_path.is_file():
        raise RuntimeError(f"Missing manifest: {out_path}")
    actual = json.loads(out_path.read_text(encoding="utf-8"))
    if actual != expected:
        raise RuntimeError(
            f"Manifest drift at {out_path}. Regenerate with: "
            "python tools/blender/terrain/generate_ts08_n3c_wall_parity_manifest.py write"
        )
    print(f"OK wall parity manifest matches Python Stage-3a helper ({out_path})")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "command",
        choices=("write", "check"),
        help="write wall parity manifest from the Python Stage-3a helper, or verify it",
    )
    args = parser.parse_args()
    if args.command == "write":
        write_manifest(REPO_ROOT)
    else:
        check_manifest(REPO_ROOT)


if __name__ == "__main__":
    main()
