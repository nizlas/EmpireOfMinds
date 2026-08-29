"""Synthetic rigged GLB, plus a stand-in for the Godot bake process.

WHAT THIS DOUBLE PROVES, AND WHAT IT CANNOT. It proves the Python half of the
static export: report parsing, the engine-to-glTF convention boundary,
deterministic serialisation, material and texture carriage, and — the point of
the sabotage suite — that the validator REFUSES a bake that is wrong in each of
the ways a wrong bake usually looks right. It cannot prove that Godot's
deformation agrees with the glTF specification, because the double evaluates the
rest pose with the same specification-level code the validator compares against.
That agreement is only ever established by running the real engine on a real
asset, which is a manual step recorded in the candidate's provenance.

The fixture is a closed box skinned to two joints whose rest pose differs from
their bind pose, so a bake that ignored the rest pose, applied it twice, or
sampled an animation frame produces visibly different geometry rather than the
same numbers.
"""

from __future__ import annotations

import hashlib
import json
import struct
import subprocess
from pathlib import Path

import numpy as np

from tools.assetgen import static_export_validation as validation
from tools.assetgen.glb_reader import load_glb

#: A tiny but real PNG, so texture carriage is tested on bytes rather than on a
#: placeholder the writer might treat specially.
PNG_BYTES = bytes.fromhex(
    "89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4"
    "890000000a49444154789c6360000002000100ffff03000006000557bfabd400"
    "00000049454e44ae426082"
)

BAKE_SCHEMA = "rest_pose_static_bake_v1"

#: Fixed section order in the arrays blob, matching the GDScript writer.
SECTION_ORDER = ("positions", "normals", "tangents", "uv", "uv2", "colors", "indices")


# --------------------------------------------------------------- geometry


def box_with_normals(
    center=(0.0, 0.5, 0.0), size=(0.4, 1.0, 0.3)
) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    """A closed box as four vertices per face: outward normals, glTF winding.

    Split per face on purpose. A shared-vertex box cannot carry correct face
    normals, and normal handling is one of the things under test.
    """
    cx, cy, cz = center
    hx, hy, hz = (s / 2.0 for s in size)
    faces = [
        ((0, 0, 1), [(-hx, -hy, hz), (hx, -hy, hz), (hx, hy, hz), (-hx, hy, hz)]),
        ((0, 0, -1), [(hx, -hy, -hz), (-hx, -hy, -hz), (-hx, hy, -hz), (hx, hy, -hz)]),
        ((1, 0, 0), [(hx, -hy, hz), (hx, -hy, -hz), (hx, hy, -hz), (hx, hy, hz)]),
        ((-1, 0, 0), [(-hx, -hy, -hz), (-hx, -hy, hz), (-hx, hy, hz), (-hx, hy, -hz)]),
        ((0, 1, 0), [(-hx, hy, hz), (hx, hy, hz), (hx, hy, -hz), (-hx, hy, -hz)]),
        ((0, -1, 0), [(-hx, -hy, -hz), (hx, -hy, -hz), (hx, -hy, hz), (-hx, -hy, hz)]),
    ]
    positions: list[tuple[float, float, float]] = []
    normals: list[tuple[float, float, float]] = []
    uvs: list[tuple[float, float]] = []
    triangles: list[tuple[int, int, int]] = []
    for normal, corners in faces:
        base = len(positions)
        for offset, corner in enumerate(corners):
            positions.append((corner[0] + cx, corner[1] + cy, corner[2] + cz))
            normals.append(normal)
            uvs.append([(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)][offset])
        triangles += [(base, base + 1, base + 2), (base, base + 2, base + 3)]
    return (
        np.array(positions, dtype=np.float64),
        np.array(normals, dtype=np.float64),
        np.array(uvs, dtype=np.float64),
        np.array(triangles, dtype=np.int64),
    )


def _rotation_y(degrees: float) -> np.ndarray:
    angle = np.radians(degrees)
    matrix = np.eye(4)
    matrix[0, 0] = matrix[2, 2] = np.cos(angle)
    matrix[0, 2] = np.sin(angle)
    matrix[2, 0] = -np.sin(angle)
    return matrix


def _translation(vector) -> np.ndarray:
    matrix = np.eye(4)
    matrix[:3, 3] = vector
    return matrix


# ------------------------------------------------------------ GLB writing


class _Builder:
    """Minimal buffer packer: every accessor lands 4-byte aligned."""

    def __init__(self) -> None:
        self.binary = bytearray()
        self.views: list[dict] = []
        self.accessors: list[dict] = []

    def raw_view(self, payload: bytes) -> int:
        while len(self.binary) % 4:
            self.binary.append(0)
        offset = len(self.binary)
        self.binary += payload
        self.views.append({"buffer": 0, "byteOffset": offset, "byteLength": len(payload)})
        return len(self.views) - 1

    def accessor(self, values: np.ndarray, kind: str, component: int, *, bounds=False) -> int:
        dtype = {5126: "<f4", 5125: "<u4", 5123: "<u2"}[component]
        flat = np.asarray(values).astype(dtype)
        view = self.raw_view(flat.tobytes())
        count = flat.shape[0] if flat.ndim > 1 else flat.size
        accessor: dict = {
            "bufferView": view,
            "componentType": component,
            "count": int(count),
            "type": kind,
        }
        if bounds:
            accessor["min"] = [float(v) for v in np.asarray(values).min(axis=0)]
            accessor["max"] = [float(v) for v in np.asarray(values).max(axis=0)]
        self.accessors.append(accessor)
        return len(self.accessors) - 1


def write_rigged_glb(
    path: Path,
    *,
    with_skin: bool = True,
    with_animation: bool = True,
    with_texture: bool = True,
    second_mesh: bool = False,
    root_rotation_deg: float = 25.0,
    material_name: str = "skin_material",
) -> Path:
    """One skinned mesh under a rotated root, with a rest pose of its own.

    `with_skin=False` produces the same geometry as a plain static mesh, which is
    the shape of an asset that was never rigged.
    """
    positions, normals, uvs, triangles = box_with_normals()
    builder = _Builder()

    gltf: dict = {
        "asset": {"version": "2.0", "generator": "empire-of-minds-test-rig"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [],
        "meshes": [],
        "materials": [{"name": material_name, "pbrMetallicRoughness": {}}],
    }

    if with_texture:
        image_view = builder.raw_view(PNG_BYTES)
        gltf["images"] = [{"name": "skin_texture", "bufferView": image_view, "mimeType": "image/png"}]
        gltf["samplers"] = [{"magFilter": 9729, "minFilter": 9987}]
        gltf["textures"] = [{"sampler": 0, "source": 0}]
        gltf["materials"][0]["pbrMetallicRoughness"]["baseColorTexture"] = {"index": 0}

    attributes = {
        "POSITION": builder.accessor(positions, "VEC3", 5126, bounds=True),
        "NORMAL": builder.accessor(normals, "VEC3", 5126),
        "TEXCOORD_0": builder.accessor(uvs, "VEC2", 5126),
    }
    index_accessor = builder.accessor(triangles.ravel(), "SCALAR", 5125)

    # Lower half to joint 0, upper half to joint 1, blended near the middle so
    # the rest pose is a real weighted deformation rather than two rigid halves.
    if with_skin:
        height = positions[:, 1]
        upper = np.clip((height - 0.35) / 0.3, 0.0, 1.0)
        weights = np.stack([1.0 - upper, upper], axis=1)
        joints = np.zeros((positions.shape[0], 4), dtype=np.uint16)
        joints[:, 1] = 1
        padded = np.zeros((positions.shape[0], 4))
        padded[:, :2] = weights
        attributes["JOINTS_0"] = builder.accessor(joints, "VEC4", 5123)
        attributes["WEIGHTS_0"] = builder.accessor(padded, "VEC4", 5126)

    gltf["meshes"].append(
        {
            "name": "body",
            "primitives": [
                {
                    "attributes": attributes,
                    "indices": index_accessor,
                    "mode": 4,
                    "material": 0,
                }
            ],
        }
    )

    root_matrix = _rotation_y(root_rotation_deg)
    gltf["nodes"].append(
        {
            "name": "asset_root",
            "matrix": [float(v) for v in root_matrix.T.ravel()],
            "children": [],
        }
    )
    gltf["nodes"].append({"name": "body_node", "mesh": 0})
    gltf["nodes"][0]["children"].append(1)

    if with_skin:
        # Bind pose: both joints at the origin of their own segment. Rest pose:
        # the upper joint is lifted and twisted, so rest != bind and a bake that
        # skipped the rest pose is a different shape.
        bind_lower = np.eye(4)
        bind_upper = _translation((0.0, 0.5, 0.0))
        rest_lower = np.eye(4)
        rest_upper = _translation((0.0, 0.56, 0.0)) @ _rotation_y(18.0)

        gltf["nodes"].append({"name": "joint_lower", "children": [3]})
        gltf["nodes"].append(
            {"name": "joint_upper", "matrix": [float(v) for v in rest_upper.T.ravel()]}
        )
        gltf["nodes"][2]["matrix"] = [float(v) for v in rest_lower.T.ravel()]
        gltf["nodes"][0]["children"].append(2)

        inverse_bind = np.stack([np.linalg.inv(bind_lower), np.linalg.inv(bind_upper)])
        # glTF stores matrices column-major.
        packed = inverse_bind.transpose(0, 2, 1).reshape(-1, 16)
        gltf["skins"] = [
            {
                "name": "body_skin",
                "joints": [2, 3],
                "inverseBindMatrices": builder.accessor(packed, "MAT4", 5126),
                "skeleton": 2,
            }
        ]
        gltf["nodes"][1]["skin"] = 0

    if second_mesh:
        second_positions, second_normals, second_uvs, second_triangles = box_with_normals(
            center=(0.9, 0.25, 0.0), size=(0.2, 0.5, 0.2)
        )
        gltf["materials"].append({"name": "equipment_material", "pbrMetallicRoughness": {}})
        gltf["meshes"].append(
            {
                "name": "equipment",
                "primitives": [
                    {
                        "attributes": {
                            "POSITION": builder.accessor(second_positions, "VEC3", 5126, bounds=True),
                            "NORMAL": builder.accessor(second_normals, "VEC3", 5126),
                            "TEXCOORD_0": builder.accessor(second_uvs, "VEC2", 5126),
                        },
                        "indices": builder.accessor(second_triangles.ravel(), "SCALAR", 5125),
                        "mode": 4,
                        "material": 1,
                    }
                ],
            }
        )
        gltf["nodes"].append({"name": "equipment_node", "mesh": 1})
        gltf["nodes"][0]["children"].append(len(gltf["nodes"]) - 1)

    if with_animation:
        times = builder.accessor(np.array([0.0, 1.0]), "SCALAR", 5126)
        rotations = builder.accessor(
            np.array([[0.0, 0.0, 0.0, 1.0], [0.0, 0.38, 0.0, 0.92]]), "VEC4", 5126
        )
        target = 3 if with_skin else 1
        gltf["animations"] = [
            {
                "name": "idle",
                "samplers": [{"input": times, "output": rotations, "interpolation": "LINEAR"}],
                "channels": [{"sampler": 0, "target": {"node": target, "path": "rotation"}}],
            }
        ]

    binary = bytes(builder.binary)
    binary += b"\x00" * ((-len(binary)) % 4)
    gltf["buffers"] = [{"byteLength": len(binary)}]
    gltf["bufferViews"] = builder.views
    gltf["accessors"] = builder.accessors

    _write_container(path, gltf, binary)
    return path


def _write_container(path: Path, gltf: dict, binary: bytes) -> None:
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


def patch_glb_binary(path: Path, mutate) -> None:
    """Rewrite a GLB's binary chunk in place, keeping its JSON.

    Lets a test forge a file whose vertex bytes differ from the arrays that were
    evaluated, which is the one thing the exporter's serialisation check exists
    to catch and which no amount of JSON editing can express.
    """
    from tools.assetgen.glb_reader import _read_glb_container

    gltf, binary = _read_glb_container(Path(path))
    payload = bytearray(binary or b"")
    mutate(gltf, payload)
    _write_container(Path(path), gltf, bytes(payload))


def patch_glb_json(path: Path, mutate) -> None:
    """Rewrite a GLB's JSON chunk in place, keeping its binary chunk.

    Used to forge defects that a correct writer cannot produce, so the
    structural validator is tested against the file it would actually receive.
    """
    from tools.assetgen.glb_reader import _read_glb_container

    gltf, binary = _read_glb_container(Path(path))
    mutate(gltf)
    _write_container(Path(path), gltf, binary or b"")


# ------------------------------------------------------- the bake stand-in


class FakeBakeProcess:
    """Emits what the Godot adapter emits, from a specification-level evaluation.

    `distort` receives the evaluated surfaces and may return altered ones; that
    is how a sabotaged bake is expressed. `report_patch` mutates the report, so
    a caller can also forge a malformed or refusing bake.
    """

    def __init__(self, source: Path, *, distort=None, report_patch=None, exit_code: int = 0):
        self.source = Path(source)
        self.distort = distort
        self.report_patch = report_patch
        self.exit_code = exit_code
        self.calls: list[list[str]] = []

    def __call__(self, argv, **kwargs):
        self.calls.append(list(argv))
        options = {
            a[2:].split("=", 1)[0]: a[2:].split("=", 1)[1]
            for a in argv
            if a.startswith("--") and "=" in a
        }
        report_path = Path(options["report"]) if "report" in options else None
        mode = options.get("mode", "inspect")

        document = load_glb(self.source)
        evaluated = validation.evaluate_source_rest_pose(document)
        surfaces = [
            {
                "positions": np.asarray(entry["positions"], dtype=np.float32),
                "normals": (
                    np.asarray(entry["normals"], dtype=np.float32)
                    if entry["normals"] is not None
                    else None
                ),
                "uv": _uv_for(document, index),
                # Godot winds the opposite way from glTF; the double emits the
                # engine's convention so the exporter's conversion is exercised.
                "indices": np.asarray(entry["indices"], dtype=np.uint32)
                .reshape(-1, 3)[:, ::-1]
                .reshape(-1),
                "material_name": _material_name(document, entry.get("material_index")),
                "mesh_name": document.gltf["meshes"][entry["mesh_index"]].get("name", ""),
                "was_skinned": bool(entry["skinned"]),
            }
            for index, entry in enumerate(evaluated)
        ]
        if self.distort is not None:
            surfaces = self.distort(surfaces)

        report = _build_report(self.source, document, surfaces, mode)
        arrays_path = options.get("arrays")
        if mode == "bake" and arrays_path:
            blob, index = _pack(surfaces)
            Path(arrays_path).parent.mkdir(parents=True, exist_ok=True)
            Path(arrays_path).write_bytes(blob)
            report["arrays"] = index
            report["arrays_sha256"] = hashlib.sha256(blob).hexdigest()
        if self.report_patch is not None:
            self.report_patch(report)
        if report_path is not None:
            report_path.parent.mkdir(parents=True, exist_ok=True)
            report_path.write_text(json.dumps(report), encoding="utf-8")
        return subprocess.CompletedProcess(
            argv, self.exit_code, stdout="STATIC_BAKE " + json.dumps(report), stderr=""
        )


def _uv_for(document, index: int) -> np.ndarray | None:
    uvs = validation._read_uvs(document)
    return np.asarray(uvs[index], dtype=np.float32) if index < len(uvs) else None


def _material_name(document, material_index) -> str:
    if material_index is None:
        return ""
    materials = document.materials
    if 0 <= int(material_index) < len(materials):
        return str(materials[int(material_index)].get("name", ""))
    return ""


def _build_report(source: Path, document, surfaces: list[dict], mode: str) -> dict:
    lows = [s["positions"].min(axis=0) for s in surfaces if s["positions"].size]
    highs = [s["positions"].max(axis=0) for s in surfaces if s["positions"].size]
    low = np.min(np.stack(lows), axis=0) if lows else np.zeros(3)
    high = np.max(np.stack(highs), axis=0) if highs else np.zeros(3)
    triangles = sum(int(s["indices"].size) // 3 for s in surfaces)
    vertices = sum(int(s["positions"].shape[0]) for s in surfaces)
    return {
        "schema": BAKE_SCHEMA,
        "mode": mode,
        "scene": str(source),
        "ok": True,
        "godot_version": {"string": "4.6.2.stable (test double)"},
        "holder_transform": {
            "translation": [0.0, 0.0, 0.0],
            "scale": [1.0, 1.0, 1.0],
            "rotation_deg": [0.0, 0.0, 0.0],
        },
        "inspection": {
            "schema": BAKE_SCHEMA,
            "node_count": len(document.gltf.get("nodes", [])),
            "skeletons": [{"path": "Skeleton3D", "bone_count": 2}] if document.skins else [],
            "animation_players": (
                [{"path": "AnimationPlayer", "animations": document.animation_names()}]
                if document.animation_names()
                else []
            ),
            "mesh_instances": [
                {
                    "path": s["mesh_name"],
                    "visible_in_tree": True,
                    "has_skin": s["was_skinned"],
                    "triangle_count": int(s["indices"].size) // 3,
                    "vertex_count": int(s["positions"].shape[0]),
                    "aabb": {
                        "position": [float(v) for v in s["positions"].min(axis=0)],
                        "size": [
                            float(v)
                            for v in s["positions"].max(axis=0) - s["positions"].min(axis=0)
                        ],
                    },
                    "surfaces": [{"active_material_name": s["material_name"]}],
                }
                for s in surfaces
            ],
            "camera_count": 0,
            "light_count": 0,
            "bone_attachment_count": 0,
        },
        "excluded_meshes": [],
        "post_bake_inspection_matches": True,
        "measurement": {
            "triangle_count": triangles,
            "vertex_count": vertices,
            "surface_count": len(surfaces),
            "aabb_min": [float(v) for v in low],
            "aabb_max": [float(v) for v in high],
            "aabb_size": [float(v) for v in (high - low)],
            "height_y": float(high[1] - low[1]),
            "ground_min_y": float(low[1]),
        },
        "surfaces": [
            {
                "source_node_path": s["mesh_name"],
                "source_mesh_name": s["mesh_name"],
                "source_surface": position,
                "was_skinned": s["was_skinned"],
                "bones_per_vertex": 4 if s["was_skinned"] else 0,
                "material_name": s["material_name"],
                "material_class": "StandardMaterial3D",
                "reflected_vertices": 0,
                "vertex_count": int(s["positions"].shape[0]),
                "index_count": int(s["indices"].size),
                "triangle_count": int(s["indices"].size) // 3,
                "has_normals": s["normals"] is not None,
                "has_tangents": False,
                "has_uv": s["uv"] is not None,
                "has_uv2": False,
                "has_colors": False,
            }
            for position, s in enumerate(surfaces)
        ],
    }


def _pack(surfaces: list[dict]) -> tuple[bytes, list[dict]]:
    blob = bytearray()
    index: list[dict] = []
    for surface in surfaces:
        sections: dict[str, dict] = {}
        for name in SECTION_ORDER:
            values = surface.get(name)
            if values is None:
                continue
            array = np.asarray(values)
            payload = (
                array.astype("<u4").tobytes()
                if name == "indices"
                else array.astype("<f4").tobytes()
            )
            sections[name] = {"offset": len(blob), "length": len(payload)}
            blob += payload
        index.append(
            {
                "sections": sections,
                "vertex_count": int(surface["positions"].shape[0]),
                "index_count": int(np.asarray(surface["indices"]).size),
            }
        )
    return bytes(blob), index


# --------------------------------------------------------------- sabotages


def animation_frame(surfaces: list[dict]) -> list[dict]:
    """The upper body twisted, as if a clip had been sampled instead of rest."""
    out = []
    for surface in surfaces:
        positions = surface["positions"].astype(np.float64).copy()
        upper = positions[:, 1] > 0.5
        rotation = _rotation_y(22.0)[:3, :3]
        positions[upper] = positions[upper] @ rotation.T
        out.append({**surface, "positions": positions.astype(np.float32)})
    return out


def doubled_transform(root_rotation_deg: float):
    """The asset root's rotation applied a second time."""
    rotation = _rotation_y(root_rotation_deg)[:3, :3]

    def distort(surfaces: list[dict]) -> list[dict]:
        return [
            {
                **s,
                "positions": (s["positions"].astype(np.float64) @ rotation.T).astype(np.float32),
            }
            for s in surfaces
        ]

    return distort


def scaled(factor: float):
    def distort(surfaces: list[dict]) -> list[dict]:
        return [{**s, "positions": (s["positions"] * factor).astype(np.float32)} for s in surfaces]

    return distort


def yawed(degrees: float):
    rotation = _rotation_y(degrees)[:3, :3]

    def distort(surfaces: list[dict]) -> list[dict]:
        return [
            {
                **s,
                "positions": (s["positions"].astype(np.float64) @ rotation.T).astype(np.float32),
                "normals": (
                    (s["normals"].astype(np.float64) @ rotation.T).astype(np.float32)
                    if s["normals"] is not None
                    else None
                ),
            }
            for s in surfaces
        ]

    return distort


def reflected(surfaces: list[dict]) -> list[dict]:
    """Mirrored on X: same area, same height, opposite handedness."""
    out = []
    for surface in surfaces:
        positions = surface["positions"].copy()
        positions[:, 0] *= -1.0
        normals = None
        if surface["normals"] is not None:
            normals = surface["normals"].copy()
            normals[:, 0] *= -1.0
        out.append({**surface, "positions": positions, "normals": normals})
    return out


def inverted_normals(surfaces: list[dict]) -> list[dict]:
    return [
        {**s, "normals": (-s["normals"] if s["normals"] is not None else None)}
        for s in surfaces
    ]


def engine_winding_not_converted(surfaces: list[dict]) -> list[dict]:
    """A bake whose indices are already glTF-wound, so the exporter's conversion
    inverts them. This is the defect that looks correct inside Godot."""
    return [
        {**s, "indices": np.asarray(s["indices"]).reshape(-1, 3)[:, ::-1].reshape(-1)}
        for s in surfaces
    ]


def without_uv(surfaces: list[dict]) -> list[dict]:
    return [{**s, "uv": None} for s in surfaces]


def drop_last_surface(surfaces: list[dict]) -> list[dict]:
    return surfaces[:-1]


def with_helper_geometry(surfaces: list[dict]) -> list[dict]:
    """An importer helper box carried into the output as if it were character
    geometry."""
    positions, normals, uvs, triangles = box_with_normals(
        center=(0.0, 1.4, 0.0), size=(0.05, 0.05, 0.05)
    )
    helper = {
        "positions": positions.astype(np.float32),
        "normals": normals.astype(np.float32),
        "uv": uvs.astype(np.float32),
        "indices": triangles.ravel().astype(np.uint32),
        "material_name": surfaces[0]["material_name"],
        "mesh_name": "AttachmentHelper",
        "was_skinned": False,
    }
    return [*surfaces, helper]


__all__ = [
    "BAKE_SCHEMA",
    "PNG_BYTES",
    "FakeBakeProcess",
    "animation_frame",
    "box_with_normals",
    "doubled_transform",
    "drop_last_surface",
    "engine_winding_not_converted",
    "inverted_normals",
    "patch_glb_binary",
    "patch_glb_json",
    "reflected",
    "scaled",
    "with_helper_geometry",
    "without_uv",
    "write_rigged_glb",
    "yawed",
]
