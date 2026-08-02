#!/usr/bin/env python3
"""Generate test-only N3a topology parity manifest from the N2 golden dataset."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parents[2]
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from export_ts08_reference_dataset import (  # noqa: E402
    COMMITTED_DATASET_CONTENT_HASH,
    DATASET_FILENAME,
    DATASET_ID,
    DEST_ROOT,
    EXPECTED_DUPLICATED_CLIFF_LINE_NODES,
)

MANIFEST_SCHEMA_VERSION = 1
MANIFEST_ID = "handdrawn_test_map_full_01_ts08_n3a_topology_parity_v1"
MANIFEST_REL = Path("game") / "domain" / "tests" / "fixtures" / "world" / f"{MANIFEST_ID}.json"


def sha256_hex_lower(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def triangle_set(triangles: list[list[int]]) -> list[list[int]]:
    out: list[list[int]] = []
    for tri in triangles:
        sorted_tri = sorted(int(v) for v in tri)
        out.append(sorted_tri)
    out.sort(key=lambda tri: (tri[0], tri[1], tri[2]))
    return out


def build_manifest_from_n2(n2: dict[str, object], *, n2_content_hash: str) -> dict[str, object]:
    nodes = n2["nodes"]
    return {
        "schema_version": MANIFEST_SCHEMA_VERSION,
        "manifest_id": MANIFEST_ID,
        "source_n2_dataset_id": DATASET_ID,
        "source_n2_content_hash": n2_content_hash,
        "node_count": int(n2["node_count"]),
        "triangle_count": int(n2["triangle_count"]),
        "duplicated_cliff_line_nodes": EXPECTED_DUPLICATED_CLIFF_LINE_NODES,
        "cliff_edge_count": 78,
        "center_pin_count": 168,
        "nodes": {
            "node_keys": list(nodes["node_keys"]),
            "pos_keys": nodes["pos_keys"],
            "sheet_ids": nodes["sheet_ids"],
            "positions_xyz": nodes["positions_xyz"],
        },
        "triangles": triangle_set(n2["triangles"]),
        "center_pins": n2["center_pins"],
    }


def manifest_content_hash(manifest: dict[str, object]) -> str:
    payload = json.dumps(manifest, sort_keys=True, separators=(",", ":"))
    return sha256_hex_lower(payload.encode("utf-8"))


def load_n2_dataset(repo_root: Path) -> tuple[dict[str, object], str]:
    n2_path = repo_root / DEST_ROOT / DATASET_FILENAME
    raw = n2_path.read_bytes()
    n2 = json.loads(raw.decode("utf-8"))
    if not isinstance(n2, dict):
        raise RuntimeError("N2 dataset must be a JSON object.")
    content_hash = n2.get("content_hash")
    if not isinstance(content_hash, str) or not content_hash:
        raise RuntimeError("N2 dataset missing content_hash field.")
    if content_hash != COMMITTED_DATASET_CONTENT_HASH:
        raise RuntimeError(
            f"Unexpected embedded N2 content_hash {content_hash} "
            f"(expected {COMMITTED_DATASET_CONTENT_HASH})"
        )
    return n2, content_hash


def write_manifest(repo_root: Path, manifest: dict[str, object]) -> Path:
    out_path = repo_root / MANIFEST_REL
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    return out_path


def check_manifest(repo_root: Path) -> None:
    n2, n2_hash = load_n2_dataset(repo_root)
    expected = build_manifest_from_n2(n2, n2_content_hash=n2_hash)
    out_path = repo_root / MANIFEST_REL
    if not out_path.is_file():
        raise RuntimeError(f"Missing manifest: {out_path}")
    actual = json.loads(out_path.read_text(encoding="utf-8"))
    if actual != expected:
        raise RuntimeError(
            f"Manifest drift at {out_path}. Regenerate with: "
            "python tools/blender/terrain/generate_ts08_n3a_parity_manifest.py write"
        )
    print(f"OK manifest matches N2 golden ({out_path})")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "command",
        choices=("write", "check"),
        help="write manifest from N2, or verify committed manifest against N2",
    )
    args = parser.parse_args()
    if args.command == "write":
        n2, n2_hash = load_n2_dataset(REPO_ROOT)
        manifest = build_manifest_from_n2(n2, n2_content_hash=n2_hash)
        out_path = write_manifest(REPO_ROOT, manifest)
        print(f"WROTE {out_path}")
        print(f"manifest_content_hash={manifest_content_hash(manifest)}")
        print(f"node_count={manifest['node_count']} triangle_count={manifest['triangle_count']}")
    else:
        check_manifest(REPO_ROOT)


if __name__ == "__main__":
    main()
