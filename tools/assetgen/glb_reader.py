"""Minimal, dependency-light glTF/GLB reader.

Only what asset validation needs: the glTF JSON, world-transformed triangle
geometry, materials, textures, skins and animations. numpy is already used by the
terrain tooling, so no new dependency is introduced.

This reader never writes and never repairs. It is a measuring instrument.
"""

from __future__ import annotations

import base64
import json
import struct
from dataclasses import dataclass, field
from pathlib import Path
from urllib.parse import unquote

import numpy as np

GLB_MAGIC = 0x46546C67  # 'glTF'
CHUNK_JSON = 0x4E4F534A  # 'JSON'
CHUNK_BIN = 0x004E4942  # 'BIN\0'
MODE_TRIANGLES = 4

COMPONENT_DTYPES: dict[int, str] = {
    5120: "<i1",
    5121: "<u1",
    5122: "<i2",
    5123: "<u2",
    5125: "<u4",
    5126: "<f4",
}

TYPE_COMPONENT_COUNT: dict[str, int] = {
    "SCALAR": 1,
    "VEC2": 2,
    "VEC3": 3,
    "VEC4": 4,
    "MAT4": 16,
}


class GlbParseError(ValueError):
    """The file is not a GLB/glTF we can measure."""


@dataclass
class Primitive:
    mesh_index: int
    mesh_name: str
    primitive_index: int
    node_name: str
    mode: int
    material_index: int | None
    positions: np.ndarray  # (V, 3) float64 world space
    triangles: np.ndarray  # (T, 3) int64 into positions
    has_normals: bool
    has_uvs: bool
    has_tangents: bool = False

    @property
    def triangle_count(self) -> int:
        return int(self.triangles.shape[0])

    @property
    def vertex_count(self) -> int:
        return int(self.positions.shape[0])


@dataclass
class GlbDocument:
    path: Path
    gltf: dict
    file_size_bytes: int
    primitives: list[Primitive] = field(default_factory=list)
    parse_warnings: list[str] = field(default_factory=list)

    @property
    def generator(self) -> str:
        return str((self.gltf.get("asset") or {}).get("generator", ""))

    @property
    def gltf_version(self) -> str:
        return str((self.gltf.get("asset") or {}).get("version", ""))

    @property
    def node_names(self) -> list[str]:
        return [str(n.get("name", "")) for n in self.gltf.get("nodes", [])]

    @property
    def skins(self) -> list[dict]:
        return list(self.gltf.get("skins", []))

    @property
    def animations(self) -> list[dict]:
        return list(self.gltf.get("animations", []))

    @property
    def materials(self) -> list[dict]:
        return list(self.gltf.get("materials", []))

    @property
    def images(self) -> list[dict]:
        return list(self.gltf.get("images", []))

    @property
    def triangle_count(self) -> int:
        return sum(p.triangle_count for p in self.primitives)

    @property
    def vertex_count(self) -> int:
        return sum(p.vertex_count for p in self.primitives)

    def joint_node_indices(self) -> set[int]:
        joints: set[int] = set()
        for skin in self.skins:
            for index in skin.get("joints", []) or []:
                joints.add(int(index))
        return joints

    def joint_names(self) -> list[str]:
        names = self.node_names
        return [names[i] if 0 <= i < len(names) else "" for i in sorted(self.joint_node_indices())]

    def animation_names(self) -> list[str]:
        return [str(a.get("name", "")) for a in self.animations]

    def material_summary(self) -> list[dict]:
        textures = self.gltf.get("textures", [])
        images = self.images
        summary: list[dict] = []
        for index, material in enumerate(self.materials):
            pbr = material.get("pbrMetallicRoughness") or {}
            maps: dict[str, str] = {}
            slots = (
                ("base_color", pbr.get("baseColorTexture")),
                ("metallic_roughness", pbr.get("metallicRoughnessTexture")),
                ("normal", material.get("normalTexture")),
                ("occlusion", material.get("occlusionTexture")),
                ("emissive", material.get("emissiveTexture")),
            )
            for slot, holder in slots:
                if not isinstance(holder, dict):
                    continue
                tex_index = holder.get("index")
                if not isinstance(tex_index, int) or not 0 <= tex_index < len(textures):
                    continue
                source = textures[tex_index].get("source")
                if isinstance(source, int) and 0 <= source < len(images):
                    image = images[source]
                    maps[slot] = str(image.get("uri") or f"<embedded:{image.get('mimeType', '?')}>")
                else:
                    maps[slot] = "<no image source>"
            summary.append(
                {
                    "index": index,
                    "name": str(material.get("name", "")),
                    "double_sided": bool(material.get("doubleSided", False)),
                    "alpha_mode": str(material.get("alphaMode", "OPAQUE")),
                    "metallic_factor": pbr.get("metallicFactor", 1.0),
                    "roughness_factor": pbr.get("roughnessFactor", 1.0),
                    "texture_maps": maps,
                }
            )
        return summary

    def merged_geometry(self) -> tuple[np.ndarray, np.ndarray]:
        """All primitives concatenated into one world-space vertex/triangle soup."""
        if not self.primitives:
            return np.zeros((0, 3)), np.zeros((0, 3), dtype=np.int64)
        vertex_blocks: list[np.ndarray] = []
        triangle_blocks: list[np.ndarray] = []
        offset = 0
        for primitive in self.primitives:
            vertex_blocks.append(primitive.positions)
            triangle_blocks.append(primitive.triangles + offset)
            offset += primitive.vertex_count
        return np.concatenate(vertex_blocks), np.concatenate(triangle_blocks)


def load_glb(path: Path) -> GlbDocument:
    resolved = Path(path).resolve()
    if not resolved.is_file():
        raise GlbParseError(f"File not found: {resolved}")
    suffix = resolved.suffix.lower()
    if suffix == ".glb":
        gltf, binary_chunk = _read_glb_container(resolved)
    elif suffix == ".gltf":
        gltf = json.loads(resolved.read_text(encoding="utf-8"))
        binary_chunk = None
    else:
        raise GlbParseError(f"Unsupported extension {suffix!r}; expected .glb or .gltf")

    document = GlbDocument(
        path=resolved, gltf=gltf, file_size_bytes=resolved.stat().st_size
    )
    buffers = _resolve_buffers(gltf, binary_chunk, resolved.parent, document.parse_warnings)
    document.primitives = _extract_primitives(gltf, buffers, document.parse_warnings)
    return document


def _read_glb_container(path: Path) -> tuple[dict, bytes | None]:
    data = path.read_bytes()
    if len(data) < 12:
        raise GlbParseError("File is shorter than a GLB header")
    magic, version, _length = struct.unpack_from("<III", data, 0)
    if magic != GLB_MAGIC:
        raise GlbParseError("Missing 'glTF' magic; this is not a GLB file")
    if version != 2:
        raise GlbParseError(f"Unsupported GLB container version {version}; expected 2")

    json_chunk: dict | None = None
    binary_chunk: bytes | None = None
    offset = 12
    while offset + 8 <= len(data):
        chunk_length, chunk_type = struct.unpack_from("<II", data, offset)
        offset += 8
        payload = data[offset : offset + chunk_length]
        offset += chunk_length + (-chunk_length % 4)
        if chunk_type == CHUNK_JSON:
            json_chunk = json.loads(payload.decode("utf-8"))
        elif chunk_type == CHUNK_BIN:
            binary_chunk = payload
    if json_chunk is None:
        raise GlbParseError("GLB contained no JSON chunk")
    return json_chunk, binary_chunk


def _resolve_buffers(
    gltf: dict, binary_chunk: bytes | None, base_dir: Path, warnings: list[str]
) -> list[bytes | None]:
    resolved: list[bytes | None] = []
    for index, buffer in enumerate(gltf.get("buffers", [])):
        uri = buffer.get("uri")
        if uri is None:
            resolved.append(binary_chunk)
        elif isinstance(uri, str) and uri.startswith("data:"):
            _, _, encoded = uri.partition(",")
            resolved.append(base64.b64decode(encoded))
        else:
            candidate = base_dir / unquote(str(uri))
            if candidate.is_file():
                resolved.append(candidate.read_bytes())
            else:
                warnings.append(f"buffer {index} references missing external file {uri!r}")
                resolved.append(None)
    return resolved


def _read_accessor(gltf: dict, buffers: list[bytes | None], accessor_index: int) -> np.ndarray:
    accessor = gltf["accessors"][accessor_index]
    dtype_code = COMPONENT_DTYPES.get(int(accessor["componentType"]))
    if dtype_code is None:
        raise GlbParseError(f"Unsupported accessor componentType {accessor['componentType']}")
    components = TYPE_COMPONENT_COUNT.get(str(accessor["type"]))
    if components is None:
        raise GlbParseError(f"Unsupported accessor type {accessor['type']!r}")
    dtype = np.dtype(dtype_code)
    count = int(accessor["count"])

    view_index = accessor.get("bufferView")
    if view_index is None:
        return np.zeros((count, components), dtype=dtype)

    view = gltf["bufferViews"][int(view_index)]
    buffer = buffers[int(view.get("buffer", 0))]
    if buffer is None:
        raise GlbParseError("Accessor points at a buffer that could not be resolved")

    start = int(view.get("byteOffset", 0)) + int(accessor.get("byteOffset", 0))
    element_bytes = dtype.itemsize * components
    stride = int(view.get("byteStride", 0)) or element_bytes

    if stride == element_bytes:
        flat = np.frombuffer(buffer, dtype=dtype, count=count * components, offset=start)
        return flat.reshape(count, components)

    # Interleaved buffer view: gather each element at its own stride offset.
    raw = np.frombuffer(buffer, dtype=np.uint8, offset=start, count=stride * (count - 1) + element_bytes)
    windows = np.lib.stride_tricks.as_strided(
        raw, shape=(count, element_bytes), strides=(stride, 1)
    )
    return windows.copy().view(dtype).reshape(count, components)


def _node_local_matrix(node: dict) -> np.ndarray:
    if "matrix" in node:
        # glTF stores column-major; transpose into row-major for row-vector math.
        return np.array(node["matrix"], dtype=np.float64).reshape(4, 4).T

    matrix = np.eye(4)
    if "scale" in node:
        matrix = np.diag([*[float(v) for v in node["scale"]], 1.0]) @ matrix
    if "rotation" in node:
        x, y, z, w = (float(v) for v in node["rotation"])
        rotation = np.array(
            [
                [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w), 0.0],
                [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w), 0.0],
                [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y), 0.0],
                [0.0, 0.0, 0.0, 1.0],
            ]
        )
        matrix = rotation @ matrix
    if "translation" in node:
        translation = np.eye(4)
        translation[:3, 3] = [float(v) for v in node["translation"]]
        matrix = translation @ matrix
    return matrix


def _extract_primitives(
    gltf: dict, buffers: list[bytes | None], warnings: list[str]
) -> list[Primitive]:
    nodes = gltf.get("nodes", [])
    meshes = gltf.get("meshes", [])
    scenes = gltf.get("scenes", [])
    scene_index = int(gltf.get("scene", 0)) if scenes else 0
    roots = list(scenes[scene_index].get("nodes", [])) if scenes else list(range(len(nodes)))

    primitives: list[Primitive] = []
    stack: list[tuple[int, np.ndarray]] = [(int(r), np.eye(4)) for r in reversed(roots)]
    visited: set[int] = set()

    while stack:
        node_index, parent_matrix = stack.pop()
        if node_index in visited or not 0 <= node_index < len(nodes):
            continue
        visited.add(node_index)
        node = nodes[node_index]
        world = parent_matrix @ _node_local_matrix(node)

        mesh_index = node.get("mesh")
        if isinstance(mesh_index, int) and 0 <= mesh_index < len(meshes):
            mesh = meshes[mesh_index]
            for primitive_index, primitive in enumerate(mesh.get("primitives", [])):
                parsed = _extract_one_primitive(
                    gltf=gltf,
                    buffers=buffers,
                    primitive=primitive,
                    world=world,
                    mesh_index=mesh_index,
                    mesh_name=str(mesh.get("name", "")),
                    primitive_index=primitive_index,
                    node_name=str(node.get("name", "")),
                    warnings=warnings,
                )
                if parsed is not None:
                    primitives.append(parsed)

        for child in node.get("children", []) or []:
            stack.append((int(child), world))

    return primitives


def _extract_one_primitive(
    *,
    gltf: dict,
    buffers: list[bytes | None],
    primitive: dict,
    world: np.ndarray,
    mesh_index: int,
    mesh_name: str,
    primitive_index: int,
    node_name: str,
    warnings: list[str],
) -> Primitive | None:
    mode = int(primitive.get("mode", MODE_TRIANGLES))
    attributes = primitive.get("attributes") or {}
    position_accessor = attributes.get("POSITION")
    if position_accessor is None:
        warnings.append(f"mesh {mesh_index} primitive {primitive_index} has no POSITION attribute")
        return None

    if mode != MODE_TRIANGLES:
        warnings.append(
            f"mesh {mesh_index} primitive {primitive_index} uses mode {mode}; "
            "only triangle lists are measured"
        )

    local = _read_accessor(gltf, buffers, int(position_accessor)).astype(np.float64)
    homogeneous = np.hstack([local, np.ones((local.shape[0], 1))])
    positions = (homogeneous @ world.T)[:, :3]

    index_accessor = primitive.get("indices")
    if index_accessor is None:
        indices = np.arange(positions.shape[0], dtype=np.int64)
    else:
        indices = _read_accessor(gltf, buffers, int(index_accessor)).astype(np.int64).ravel()

    usable = (indices.shape[0] // 3) * 3
    triangles = (
        indices[:usable].reshape(-1, 3)
        if mode == MODE_TRIANGLES
        else np.zeros((0, 3), dtype=np.int64)
    )

    return Primitive(
        mesh_index=mesh_index,
        mesh_name=mesh_name,
        primitive_index=primitive_index,
        node_name=node_name,
        mode=mode,
        material_index=primitive.get("material"),
        positions=positions,
        triangles=triangles,
        has_normals="NORMAL" in attributes,
        has_uvs="TEXCOORD_0" in attributes,
        has_tangents="TANGENT" in attributes,
    )
