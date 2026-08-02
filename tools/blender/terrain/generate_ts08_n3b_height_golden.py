#!/usr/bin/env python3
"""Generate the test-only N3b solved-height binary golden from the N2 golden dataset.

This is a TEST GOLDEN for numerical parity of the Godot-native N3b height
solver — not a persisted lattice cache and not a runtime terrain source.
Production code never reads it; only the headless Godot N3b parity test does.

Encoding:
- binary fixture: little-endian IEEE-754 float64 solved heights (Godot Y),
  one per cut-lattice node in N3a node-index order, taken from
  nodes.positions_xyz[*][1] in the N2 golden;
- JSON sidecar: schema/version, node count, source N2 dataset id and content
  hash, binary byte size and SHA-256, encoding description, and Y range.

`check` regenerates the expected bytes from N2 and compares them (and the
sidecar) with the committed fixture. N2 stays the sole comparison golden.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import struct
import sys
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parents[2]
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from export_ts08_reference_dataset import (  # noqa: E402
    COMMITTED_DATASET_CONTENT_HASH,
    DATASET_FILENAME,
    DATASET_ID,
    DEST_ROOT,
)

GOLDEN_SCHEMA_VERSION = 1
GOLDEN_ID = "handdrawn_test_map_full_01_ts08_n3b_heights_v1"
FIXTURE_DIR = Path("game") / "domain" / "tests" / "fixtures" / "world"
BIN_REL = FIXTURE_DIR / f"{GOLDEN_ID}.bin"
SIDECAR_REL = FIXTURE_DIR / f"{GOLDEN_ID}.json"

ENCODING_DESCRIPTION = (
    "little-endian IEEE-754 float64 solved heights (Godot Y), one per cut-lattice "
    "node in N3a node-index order, from N2 nodes.positions_xyz[*][1]"
)


def sha256_hex_lower(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def load_n2_dataset(repo_root: Path) -> tuple[dict[str, Any], str]:
    n2_path = repo_root / DEST_ROOT / DATASET_FILENAME
    n2 = json.loads(n2_path.read_bytes().decode("utf-8"))
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


def heights_from_n2(n2: dict[str, Any]) -> list[float]:
    positions = n2["nodes"]["positions_xyz"]
    node_count = int(n2["node_count"])
    if len(positions) != node_count:
        raise RuntimeError("N2 positions_xyz length != node_count")
    return [float(position[1]) for position in positions]


def golden_bytes(heights: list[float]) -> bytes:
    return struct.pack(f"<{len(heights)}d", *heights)


def build_sidecar(
    heights: list[float], bin_bytes: bytes, *, n2_content_hash: str
) -> dict[str, Any]:
    return {
        "schema_version": GOLDEN_SCHEMA_VERSION,
        "golden_id": GOLDEN_ID,
        "purpose": (
            "test-only numerical parity golden for the Godot-native N3b height solver; "
            "not a persisted lattice cache, not a runtime terrain source"
        ),
        "source_n2_dataset_id": DATASET_ID,
        "source_n2_content_hash": n2_content_hash,
        "encoding": ENCODING_DESCRIPTION,
        "node_count": len(heights),
        "binary_byte_size": len(bin_bytes),
        "binary_sha256": sha256_hex_lower(bin_bytes),
        "y_min": min(heights),
        "y_max": max(heights),
    }


def write_golden(repo_root: Path) -> None:
    n2, n2_hash = load_n2_dataset(repo_root)
    heights = heights_from_n2(n2)
    bin_bytes = golden_bytes(heights)
    sidecar = build_sidecar(heights, bin_bytes, n2_content_hash=n2_hash)
    bin_path = repo_root / BIN_REL
    sidecar_path = repo_root / SIDECAR_REL
    bin_path.parent.mkdir(parents=True, exist_ok=True)
    bin_path.write_bytes(bin_bytes)
    sidecar_path.write_text(json.dumps(sidecar, indent=2) + "\n", encoding="utf-8")
    print(f"WROTE {bin_path} ({len(bin_bytes)} bytes)")
    print(f"WROTE {sidecar_path}")
    print(f"binary_sha256={sidecar['binary_sha256']}")
    print(f"node_count={sidecar['node_count']} y_min={sidecar['y_min']} y_max={sidecar['y_max']}")


def check_golden(repo_root: Path) -> None:
    n2, n2_hash = load_n2_dataset(repo_root)
    heights = heights_from_n2(n2)
    expected_bin = golden_bytes(heights)
    expected_sidecar = build_sidecar(heights, expected_bin, n2_content_hash=n2_hash)
    bin_path = repo_root / BIN_REL
    sidecar_path = repo_root / SIDECAR_REL
    if not bin_path.is_file():
        raise RuntimeError(f"Missing binary golden: {bin_path}")
    if not sidecar_path.is_file():
        raise RuntimeError(f"Missing sidecar: {sidecar_path}")
    actual_bin = bin_path.read_bytes()
    if actual_bin != expected_bin:
        raise RuntimeError(
            f"Binary golden drift at {bin_path}. Regenerate with: "
            "python tools/blender/terrain/generate_ts08_n3b_height_golden.py write"
        )
    actual_sidecar = json.loads(sidecar_path.read_text(encoding="utf-8"))
    if actual_sidecar != expected_sidecar:
        raise RuntimeError(
            f"Sidecar drift at {sidecar_path}. Regenerate with: "
            "python tools/blender/terrain/generate_ts08_n3b_height_golden.py write"
        )
    print(f"OK height golden matches N2 ({bin_path}, {len(actual_bin)} bytes)")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "command",
        choices=("write", "check"),
        help="write height golden from N2, or verify committed golden against N2",
    )
    args = parser.parse_args()
    if args.command == "write":
        write_golden(REPO_ROOT)
    else:
        check_golden(REPO_ROOT)


if __name__ == "__main__":
    main()
