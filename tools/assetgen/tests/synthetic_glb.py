"""Synthetic GLB builders for tests.

Real provider output cannot be committed, and testing the shield validator
against the one existing asset would only ever prove the negative case. These
builders produce geometry with known ground truth so both the pass and fail paths
are exercised.
"""

from __future__ import annotations

import json
import struct
from pathlib import Path

import numpy as np


def write_glb(
    path: Path,
    vertices: np.ndarray,
    triangles: np.ndarray,
    *,
    generator: str = "empire-of-minds-test",
    material_name: str = "material",
    node_name: str = "mesh_node",
) -> Path:
    """Write a minimal, valid GLB with one mesh, one primitive and one material."""
    positions = np.asarray(vertices, dtype="<f4")
    indices = np.asarray(triangles, dtype="<u4").ravel()

    position_bytes = positions.tobytes()
    index_bytes = indices.tobytes()
    position_padding = (-len(position_bytes)) % 4
    binary = position_bytes + b"\x00" * position_padding + index_bytes
    binary += b"\x00" * ((-len(binary)) % 4)

    gltf = {
        "asset": {"version": "2.0", "generator": generator},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"name": node_name, "mesh": 0}],
        "meshes": [
            {
                "name": "mesh",
                "primitives": [
                    {"attributes": {"POSITION": 0}, "indices": 1, "mode": 4, "material": 0}
                ],
            }
        ],
        "materials": [{"name": material_name, "pbrMetallicRoughness": {}}],
        "buffers": [{"byteLength": len(binary)}],
        "bufferViews": [
            {"buffer": 0, "byteOffset": 0, "byteLength": len(position_bytes)},
            {
                "buffer": 0,
                "byteOffset": len(position_bytes) + position_padding,
                "byteLength": len(index_bytes),
            },
        ],
        "accessors": [
            {
                "bufferView": 0,
                "componentType": 5126,
                "count": int(positions.shape[0]),
                "type": "VEC3",
                "min": [float(v) for v in positions.min(axis=0)],
                "max": [float(v) for v in positions.max(axis=0)],
            },
            {
                "bufferView": 1,
                "componentType": 5125,
                "count": int(indices.size),
                "type": "SCALAR",
            },
        ],
    }

    json_bytes = json.dumps(gltf).encode("utf-8")
    json_bytes += b" " * ((-len(json_bytes)) % 4)

    total = 12 + 8 + len(json_bytes) + 8 + len(binary)
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "wb") as handle:
        handle.write(struct.pack("<III", 0x46546C67, 2, total))
        handle.write(struct.pack("<II", len(json_bytes), 0x4E4F534A))
        handle.write(json_bytes)
        handle.write(struct.pack("<II", len(binary), 0x004E4942))
        handle.write(binary)
    return path


def box(center: tuple[float, float, float], size: tuple[float, float, float]):
    """Axis-aligned closed box as (vertices, triangles)."""
    cx, cy, cz = center
    hx, hy, hz = (s / 2.0 for s in size)
    vertices = np.array(
        [
            [cx - hx, cy - hy, cz - hz],
            [cx + hx, cy - hy, cz - hz],
            [cx + hx, cy + hy, cz - hz],
            [cx - hx, cy + hy, cz - hz],
            [cx - hx, cy - hy, cz + hz],
            [cx + hx, cy - hy, cz + hz],
            [cx + hx, cy + hy, cz + hz],
            [cx - hx, cy + hy, cz + hz],
        ],
        dtype=np.float64,
    )
    triangles = np.array(
        [
            [0, 2, 1], [0, 3, 2],
            [4, 5, 6], [4, 6, 7],
            [0, 1, 5], [0, 5, 4],
            [1, 2, 6], [1, 6, 5],
            [2, 3, 7], [2, 7, 6],
            [3, 0, 4], [3, 4, 7],
        ],
        dtype=np.int64,
    )
    return vertices, triangles


def subdivided_box(center, size, *, splits: int = 6):
    """A box whose faces are subdivided, so welded clustering has enough vertices."""
    vertices, triangles = box(center, size)
    for _ in range(splits):
        vertices, triangles = _subdivide_once(vertices, triangles)
    return vertices, triangles


def _subdivide_once(vertices: np.ndarray, triangles: np.ndarray):
    new_vertices = list(vertices)
    new_triangles: list[list[int]] = []
    midpoints: dict[tuple[int, int], int] = {}

    def midpoint(a: int, b: int) -> int:
        key = (min(a, b), max(a, b))
        if key not in midpoints:
            midpoints[key] = len(new_vertices)
            new_vertices.append((vertices[a] + vertices[b]) / 2.0)
        return midpoints[key]

    for tri in triangles:
        a, b, c = (int(v) for v in tri)
        ab, bc, ca = midpoint(a, b), midpoint(b, c), midpoint(c, a)
        new_triangles += [[a, ab, ca], [ab, b, bc], [ca, bc, c], [ab, bc, ca]]
    return np.array(new_vertices, dtype=np.float64), np.array(new_triangles, dtype=np.int64)


def combine(*parts):
    """Merge (vertices, triangles) pairs into one soup."""
    vertex_blocks: list[np.ndarray] = []
    triangle_blocks: list[np.ndarray] = []
    offset = 0
    for vertices, triangles in parts:
        vertex_blocks.append(vertices)
        triangle_blocks.append(triangles + offset)
        offset += vertices.shape[0]
    return np.concatenate(vertex_blocks), np.concatenate(triangle_blocks)


def shield_with_handle(
    *,
    width: float = 1.0,
    thickness: float = 0.08,
    grip_clearance: float = 0.09,
    grip_diameter: float = 0.05,
    grip_length: float = 0.30,
):
    """Plate plus a rear grip bar standing off on two posts.

    Ground truth: the empty channel between plate rear face and bar equals
    `grip_clearance`, i.e. a clearance ratio of `grip_clearance / width`.
    """
    plate = subdivided_box((0.0, 0.0, 0.0), (width, width * 0.78, thickness), splits=4)

    rear_face = -thickness / 2.0
    bar_center_z = rear_face - grip_clearance - grip_diameter / 2.0
    bar = subdivided_box(
        (0.0, 0.0, bar_center_z), (grip_length, grip_diameter, grip_diameter), splits=3
    )

    post_size = (grip_diameter * 0.8, grip_diameter * 0.8, grip_clearance + grip_diameter)
    post_z = rear_face - post_size[2] / 2.0
    left_post = subdivided_box((-grip_length / 2.0, 0.0, post_z), post_size, splits=2)
    right_post = subdivided_box((grip_length / 2.0, 0.0, post_z), post_size, splits=2)

    return combine(plate, bar, left_post, right_post)


def flat_shield_no_handle(*, width: float = 1.0, thickness: float = 0.08):
    """A plain plate. Ground truth: no grip geometry of any kind."""
    return subdivided_box((0.0, 0.0, 0.0), (width, width * 0.78, thickness), splits=4)


def shield_with_painted_ridge(*, width: float = 1.0, thickness: float = 0.08):
    """Plate with a shallow rear ridge - the classic false-positive handle.

    Ground truth: the ridge is fused to the plate with no channel, so it must
    never classify as hand-held.
    """
    plate = subdivided_box((0.0, 0.0, 0.0), (width, width * 0.78, thickness), splits=4)
    ridge_depth = 0.008
    ridge = subdivided_box(
        (0.0, 0.0, -thickness / 2.0 - ridge_depth / 2.0),
        (width * 0.3, 0.04, ridge_depth),
        splits=3,
    )
    return combine(plate, ridge)
