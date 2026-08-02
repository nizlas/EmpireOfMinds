#!/usr/bin/env python3
"""Generate the test-only N3a topology parity digest manifest from the N2 golden dataset.

The manifest stores only counts and SHA-256 digests over complete canonical
streams derived from N2 (no raw topology arrays, no solved non-center Y
values). N2 remains the sole comparison golden: `check` regenerates the
expected manifest from N2 and compares it with the committed file.

Canonical encoding (shared with the Godot N3a test):
- Every stream is a sequence of UTF-8 text lines; each line is terminated by
  a single "\\n" and consists of base-10 integers (plus a fixed category tag
  for node identities) joined by ";".
- Coordinates are integer-quantized micro-units:
  q(v) = floor(v * 1e6 + 0.5) for v >= 0, else -floor(-v * 1e6 + 0.5)
  (round half away from zero). No locale- or float-format-dependent strings.
- Streams (all entries hashed, no sampling):
  * node_identities  - one line per node in node-index order:
      crack_tip;PKX;PKY
      corner_split;PKX;PKY;COMPONENT
      cliff_line;PKX;PKY;SHEET;Q;R
      tile_corner;PKX;PKY;SHEET;Q;R;SECTOR       (5-part positional key)
      tile_pos_sheet;PKX;PKY;SHEET;Q;R           (4-part positional key)
    where PKX/PKY are the quantized pos-key plane coordinates.
  * pos_keys         - one line per node in node-index order: PKX;PKY
  * sheet_ids        - one line per node in node-index order: SHEET
  * godot_xz         - one line per node in node-index order: XI;ZI where
    XI = q(godot_x) and ZI = q(godot_z). Generation asserts XI == PKX and
    ZI == -PKY for every node (pos keys are the plane coordinates rounded to
    the same 1e-6 grid; godot z = -plane y), so the stream is reproducible
    from float64 pos-key parts without float32 loss.
  * triangles        - canonical triangle set: each triangle's node indices
    sorted ascending, triangles sorted lexicographically; one line A;B;C.
  * center_pins      - sorted by node index: NODE;Q;R;YQ with
    YQ = q(pinned_world_y) (canonical center height; not a solved value).
- Digest = SHA-256 over the concatenated UTF-8 line bytes, lowercase hex.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
from pathlib import Path
from typing import Any, Iterable

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
)

MANIFEST_SCHEMA_VERSION = 2
MANIFEST_ID = "handdrawn_test_map_full_01_ts08_n3a_topology_parity_v1"
MANIFEST_REL = Path("game") / "domain" / "tests" / "fixtures" / "world" / f"{MANIFEST_ID}.json"

QUANT_SCALE = 1_000_000

CANONICAL_ENCODING: dict[str, Any] = {
    "text": "UTF-8 lines terminated by '\\n'; integer fields joined by ';'",
    "digest": "sha256 lowercase hex over concatenated line bytes; all entries hashed, no sampling",
    "coordinate_quantization": (
        "integer micro-units: q(v) = floor(v*1e6 + 0.5) for v >= 0, "
        "else -floor(-v*1e6 + 0.5) (round half away from zero)"
    ),
    "streams": {
        "node_identities": (
            "per node, index order: crack_tip;PKX;PKY | corner_split;PKX;PKY;COMPONENT | "
            "cliff_line;PKX;PKY;SHEET;Q;R | tile_corner;PKX;PKY;SHEET;Q;R;SECTOR | "
            "tile_pos_sheet;PKX;PKY;SHEET;Q;R (PKX/PKY = quantized pos-key plane coords)"
        ),
        "pos_keys": "per node, index order: PKX;PKY",
        "sheet_ids": "per node, index order: SHEET",
        "godot_xz": (
            "per node, index order: XI;ZI with XI = q(godot_x) == PKX and "
            "ZI = q(godot_z) == -PKY (equivalence asserted at generation)"
        ),
        "triangles": (
            "canonical set: per-triangle node indices sorted ascending, "
            "triangles sorted lexicographically; line A;B;C"
        ),
        "center_pins": "sorted by node index: NODE;Q;R;YQ with YQ = q(pinned_world_y)",
    },
}


def sha256_hex_lower(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def quantize_micro(value: float) -> int:
    if not math.isfinite(value):
        raise ValueError(f"Non-finite coordinate: {value!r}")
    scaled = value * QUANT_SCALE
    if scaled >= 0.0:
        return int(math.floor(scaled + 0.5))
    return -int(math.floor(-scaled + 0.5))


def stream_digest(lines: Iterable[str]) -> str:
    hasher = hashlib.sha256()
    for line in lines:
        hasher.update(line.encode("utf-8"))
        hasher.update(b"\n")
    return hasher.hexdigest()


def _pos_key_parts_from_node_key(key: list[Any]) -> list[float]:
    if isinstance(key[0], str):
        return [float(key[1][0]), float(key[1][1])]
    return [float(key[0][0]), float(key[0][1])]


def node_identity_line(key: list[Any]) -> str:
    pk = _pos_key_parts_from_node_key(key)
    pkx = quantize_micro(pk[0])
    pky = quantize_micro(pk[1])
    if isinstance(key[0], str):
        tag = key[0]
        if tag == "crack_tip":
            return f"crack_tip;{pkx};{pky}"
        if tag == "corner_split":
            return f"corner_split;{pkx};{pky};{int(key[2])}"
        if tag == "cliff_line":
            return f"cliff_line;{pkx};{pky};{int(key[2])};{int(key[3])};{int(key[4])}"
        raise ValueError(f"Unknown node key tag: {tag!r}")
    if len(key) == 5:
        return (
            f"tile_corner;{pkx};{pky};{int(key[1])};{int(key[2])};{int(key[3])};{int(key[4])}"
        )
    if len(key) == 4:
        return f"tile_pos_sheet;{pkx};{pky};{int(key[1])};{int(key[2])};{int(key[3])}"
    raise ValueError(f"Unknown node key shape: {key!r}")


def node_identity_lines(node_keys: list[list[Any]]) -> Iterable[str]:
    for key in node_keys:
        yield node_identity_line(key)


def pos_key_lines(pos_keys: list[list[float]]) -> Iterable[str]:
    for pk in pos_keys:
        yield f"{quantize_micro(float(pk[0]))};{quantize_micro(float(pk[1]))}"


def sheet_id_lines(sheet_ids: list[int]) -> Iterable[str]:
    for sheet_id in sheet_ids:
        yield f"{int(sheet_id)}"


def godot_xz_lines(positions_xyz: list[list[float]]) -> Iterable[str]:
    for position in positions_xyz:
        yield f"{quantize_micro(float(position[0]))};{quantize_micro(float(position[2]))}"


def canonical_triangle_set(triangles: list[list[int]]) -> list[tuple[int, int, int]]:
    out = [tuple(sorted(int(v) for v in tri)) for tri in triangles]
    out.sort()
    return out


def triangle_lines(triangles: list[list[int]]) -> Iterable[str]:
    for a, b, c in canonical_triangle_set(triangles):
        yield f"{a};{b};{c}"


def center_pin_lines(center_pins: list[dict[str, Any]]) -> Iterable[str]:
    ordered = sorted(center_pins, key=lambda pin: int(pin["node_index"]))
    for pin in ordered:
        yield (
            f"{int(pin['node_index'])};{int(pin['q'])};{int(pin['r'])};"
            f"{quantize_micro(float(pin['pinned_world_y']))}"
        )


def stream_digests(n2: dict[str, Any]) -> dict[str, str]:
    nodes = n2["nodes"]
    return {
        "node_identities_sha256": stream_digest(node_identity_lines(nodes["node_keys"])),
        "pos_keys_sha256": stream_digest(pos_key_lines(nodes["pos_keys"])),
        "sheet_ids_sha256": stream_digest(sheet_id_lines(nodes["sheet_ids"])),
        "godot_xz_sha256": stream_digest(godot_xz_lines(nodes["positions_xyz"])),
        "triangles_sha256": stream_digest(triangle_lines(n2["triangles"])),
        "center_pins_sha256": stream_digest(center_pin_lines(n2["center_pins"])),
    }


def duplicated_cliff_line_nodes(n2: dict[str, Any]) -> int:
    nodes = n2["nodes"]
    by_pos: dict[tuple[int, int], int] = {}
    for key, pk in zip(nodes["node_keys"], nodes["pos_keys"]):
        if not (isinstance(key[0], str) and key[0] == "cliff_line"):
            continue
        quantized = (quantize_micro(float(pk[0])), quantize_micro(float(pk[1])))
        by_pos[quantized] = by_pos.get(quantized, 0) + 1
    return sum(count - 1 for count in by_pos.values() if count > 1)


def validate_n2_consistency(n2: dict[str, Any]) -> None:
    nodes = n2["nodes"]
    node_count = int(n2["node_count"])
    for field in ("node_keys", "pos_keys", "sheet_ids", "positions_xyz"):
        if len(nodes[field]) != node_count:
            raise RuntimeError(f"N2 nodes.{field} length != node_count {node_count}")
    if len(n2["triangles"]) != int(n2["triangle_count"]):
        raise RuntimeError("N2 triangles length != triangle_count")
    for index in range(node_count):
        key_pk = _pos_key_parts_from_node_key(nodes["node_keys"][index])
        pk = nodes["pos_keys"][index]
        if quantize_micro(key_pk[0]) != quantize_micro(float(pk[0])) or quantize_micro(
            key_pk[1]
        ) != quantize_micro(float(pk[1])):
            raise RuntimeError(f"N2 node {index}: node_key pos differs from pos_keys entry")
        position = nodes["positions_xyz"][index]
        if quantize_micro(float(position[0])) != quantize_micro(float(pk[0])):
            raise RuntimeError(f"N2 node {index}: godot x != pos_key x on 1e-6 grid")
        if quantize_micro(float(position[2])) != -quantize_micro(float(pk[1])):
            raise RuntimeError(f"N2 node {index}: godot z != -pos_key y on 1e-6 grid")
    seam = n2.get("seam_duplication", {})
    computed = duplicated_cliff_line_nodes(n2)
    if computed != int(seam.get("duplicated_cliff_line_nodes", -1)):
        raise RuntimeError(
            f"Computed duplicated cliff-line nodes {computed} != N2 seam_duplication value"
        )


def build_manifest_from_n2(n2: dict[str, Any], *, n2_content_hash: str) -> dict[str, Any]:
    validate_n2_consistency(n2)
    return {
        "schema_version": MANIFEST_SCHEMA_VERSION,
        "manifest_id": MANIFEST_ID,
        "source_n2_dataset_id": DATASET_ID,
        "source_n2_content_hash": n2_content_hash,
        "canonical_encoding": CANONICAL_ENCODING,
        "counts": {
            "node_count": int(n2["node_count"]),
            "triangle_count": int(n2["triangle_count"]),
            "center_pin_count": len(n2["center_pins"]),
            "cliff_edge_count": len(n2["cliff_edges"]),
            "duplicated_cliff_line_nodes": duplicated_cliff_line_nodes(n2),
        },
        "digests": stream_digests(n2),
    }


def load_n2_dataset(repo_root: Path) -> tuple[dict[str, Any], str]:
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


def write_manifest(repo_root: Path, manifest: dict[str, Any]) -> Path:
    out_path = repo_root / MANIFEST_REL
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
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
    print(f"OK digest manifest matches N2 golden ({out_path})")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "command",
        choices=("write", "check"),
        help="write digest manifest from N2, or verify committed manifest against N2",
    )
    args = parser.parse_args()
    if args.command == "write":
        n2, n2_hash = load_n2_dataset(REPO_ROOT)
        manifest = build_manifest_from_n2(n2, n2_content_hash=n2_hash)
        out_path = write_manifest(REPO_ROOT, manifest)
        print(f"WROTE {out_path} ({out_path.stat().st_size} bytes)")
        for name, value in manifest["digests"].items():
            print(f"{name}={value}")
        counts = manifest["counts"]
        print(
            "node_count=%d triangle_count=%d center_pin_count=%d "
            "cliff_edge_count=%d duplicated_cliff_line_nodes=%d"
            % (
                counts["node_count"],
                counts["triangle_count"],
                counts["center_pin_count"],
                counts["cliff_edge_count"],
                counts["duplicated_cliff_line_nodes"],
            )
        )
    else:
        check_manifest(REPO_ROOT)


if __name__ == "__main__":
    main()
