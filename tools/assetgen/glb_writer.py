"""Deterministic GLB assembly.

The counterpart to `glb_reader.py`: that module measures, this one writes, and
neither repairs. Two properties are load-bearing.

**Byte determinism.** The same surfaces and the same carried-over material
always produce the same file, because there is nothing in here that could vary:
no timestamps, no host names, no random ids, no dictionary-order dependence
(every object is emitted through `json.dumps(..., sort_keys=True)`), and no
floating-point work — vertex data arrives as float32 and is stored as float32.
A candidate whose digest changes between runs cannot be approved by a plan
digest, so this is a correctness property rather than a nicety.

**Material and texture identity.** Materials, textures, samplers and images are
copied from the source document verbatim, including the exact embedded image
bytes. The alternative — letting the engine re-serialise its imported
`StandardMaterial3D` and re-encode the texture — would silently produce a
different, usually re-compressed, image and the output could no longer be said
to carry the source's texture at all.
"""

from __future__ import annotations

import copy
import json
import struct
from dataclasses import dataclass, field

import numpy as np

GLB_MAGIC = 0x46546C67
CHUNK_JSON = 0x4E4F534A
CHUNK_BIN = 0x004E4942

COMPONENT_FLOAT = 5126
COMPONENT_UNSIGNED_INT = 5125
MODE_TRIANGLES = 4

## Fixed, version-bearing and date-free: it identifies the operation, and it must
## never become a source of digest churn.
GENERATOR = "EmpireOfMinds rest-pose static bake (glb_writer v1)"


class GlbWriteError(ValueError):
    """The output cannot be assembled, and no partial file is produced."""


@dataclass
class SurfaceData:
    """One triangle surface, already evaluated in the output space."""

    positions: np.ndarray  # (V, 3) float32
    indices: np.ndarray  # (I,) uint32
    normals: np.ndarray | None = None  # (V, 3) float32
    uv: np.ndarray | None = None  # (V, 2) float32
    uv2: np.ndarray | None = None  # (V, 2) float32
    colors: np.ndarray | None = None  # (V, 4) float32
    tangents: np.ndarray | None = None  # (V, 4) float32
    source_material_index: int | None = None
    name: str = ""

    def validate(self) -> None:
        if self.positions.ndim != 2 or self.positions.shape[1] != 3:
            raise GlbWriteError("positions must be (V, 3)")
        count = int(self.positions.shape[0])
        if count == 0:
            raise GlbWriteError("a surface with no vertices cannot be written")
        if self.indices.ndim != 1 or self.indices.shape[0] % 3 != 0:
            raise GlbWriteError("indices must be a flat multiple of three")
        if self.indices.size and int(self.indices.max()) >= count:
            raise GlbWriteError("an index points past the end of the vertex array")
        for label, array, width in (
            ("normals", self.normals, 3),
            ("uv", self.uv, 2),
            ("uv2", self.uv2, 2),
            ("colors", self.colors, 4),
            ("tangents", self.tangents, 4),
        ):
            if array is None:
                continue
            if array.shape != (count, width):
                raise GlbWriteError(
                    f"{label} must be ({count}, {width}), got {tuple(array.shape)}"
                )


@dataclass
class _BufferBuilder:
    """Append-only 4-byte-aligned blob. Offsets are handed out as it grows."""

    payload: bytearray = field(default_factory=bytearray)

    def add(self, raw: bytes) -> tuple[int, int]:
        while len(self.payload) % 4:
            self.payload.append(0)
        offset = len(self.payload)
        self.payload.extend(raw)
        return offset, len(raw)


def write_static_glb(
    *,
    surfaces: list[SurfaceData],
    source_gltf: dict | None,
    source_binary: bytes | None,
    mesh_name: str,
    node_name: str,
    scene_name: str = "Scene",
) -> bytes:
    """Assemble a self-contained static GLB.

    `source_gltf` / `source_binary` supply the materials to carry over. Passing
    `None` writes untextured surfaces, which is what a synthetic test wants and
    never what a real candidate wants.
    """
    if not surfaces:
        raise GlbWriteError("at least one surface is required")
    for surface in surfaces:
        surface.validate()

    buffer = _BufferBuilder()
    buffer_views: list[dict] = []
    accessors: list[dict] = []

    def add_accessor(
        raw: bytes, *, component_type: int, type_name: str, count: int, extra: dict | None = None
    ) -> int:
        offset, length = buffer.add(raw)
        buffer_views.append({"buffer": 0, "byteOffset": offset, "byteLength": length})
        accessor = {
            "bufferView": len(buffer_views) - 1,
            "componentType": component_type,
            "count": count,
            "type": type_name,
        }
        if extra:
            accessor.update(extra)
        accessors.append(accessor)
        return len(accessors) - 1

    materials, textures, samplers, images, extensions_used = _carry_materials(
        surfaces, source_gltf, source_binary, buffer, buffer_views
    )

    primitives: list[dict] = []
    for surface in surfaces:
        count = int(surface.positions.shape[0])
        positions = np.ascontiguousarray(surface.positions, dtype="<f4")
        attributes = {
            "POSITION": add_accessor(
                positions.tobytes(),
                component_type=COMPONENT_FLOAT,
                type_name="VEC3",
                count=count,
                # POSITION min/max is required by the specification, and it is
                # what a consumer uses to size the model without decoding it.
                extra={
                    "min": [float(v) for v in positions.min(axis=0)],
                    "max": [float(v) for v in positions.max(axis=0)],
                },
            )
        }
        for name, array, type_name in (
            ("NORMAL", surface.normals, "VEC3"),
            ("TANGENT", surface.tangents, "VEC4"),
            ("TEXCOORD_0", surface.uv, "VEC2"),
            ("TEXCOORD_1", surface.uv2, "VEC2"),
            ("COLOR_0", surface.colors, "VEC4"),
        ):
            if array is None:
                continue
            attributes[name] = add_accessor(
                np.ascontiguousarray(array, dtype="<f4").tobytes(),
                component_type=COMPONENT_FLOAT,
                type_name=type_name,
                count=count,
            )

        indices = np.ascontiguousarray(surface.indices, dtype="<u4")
        primitive = {
            "attributes": attributes,
            "indices": add_accessor(
                indices.tobytes(),
                component_type=COMPONENT_UNSIGNED_INT,
                type_name="SCALAR",
                count=int(indices.shape[0]),
            ),
            "mode": MODE_TRIANGLES,
        }
        if surface.source_material_index is not None:
            remapped = _remapped_material_index(surface, materials)
            if remapped is not None:
                primitive["material"] = remapped
        primitives.append(primitive)

    gltf: dict = {
        "asset": {"version": "2.0", "generator": GENERATOR},
        "scene": 0,
        "scenes": [{"name": scene_name, "nodes": [0]}],
        "nodes": [{"name": node_name, "mesh": 0}],
        "meshes": [{"name": mesh_name, "primitives": primitives}],
        "accessors": accessors,
        "bufferViews": buffer_views,
        "buffers": [{"byteLength": len(buffer.payload)}],
    }
    if materials:
        gltf["materials"] = materials
    if textures:
        gltf["textures"] = textures
    if samplers:
        gltf["samplers"] = samplers
    if images:
        gltf["images"] = images
    if extensions_used:
        gltf["extensionsUsed"] = sorted(extensions_used)

    return _pack_glb(gltf, bytes(buffer.payload))


def _remapped_material_index(surface: SurfaceData, materials: list[dict]) -> int | None:
    """Materials are carried over in first-use order, so the map is positional."""
    key = surface.source_material_index
    if key is None:
        return None
    for index, material in enumerate(materials):
        if material.get("_source_index") == key:
            return index
    return None


def _carry_materials(
    surfaces: list[SurfaceData],
    source_gltf: dict | None,
    source_binary: bytes | None,
    buffer: _BufferBuilder,
    buffer_views: list[dict],
) -> tuple[list[dict], list[dict], list[dict], list[dict], set[str]]:
    """Copy exactly the materials the surfaces use, and everything they reach.

    Deterministic order: materials in first-use order, then textures, samplers
    and images in the order those materials reference them.
    """
    if source_gltf is None:
        return [], [], [], [], set()

    source_materials = source_gltf.get("materials") or []
    source_textures = source_gltf.get("textures") or []
    source_samplers = source_gltf.get("samplers") or []
    source_images = source_gltf.get("images") or []

    wanted: list[int] = []
    for surface in surfaces:
        index = surface.source_material_index
        if index is None:
            continue
        if not 0 <= index < len(source_materials):
            raise GlbWriteError(f"source material {index} does not exist")
        if index not in wanted:
            wanted.append(index)

    materials: list[dict] = []
    textures: list[dict] = []
    samplers: list[dict] = []
    images: list[dict] = []
    texture_map: dict[int, int] = {}
    sampler_map: dict[int, int] = {}
    image_map: dict[int, int] = {}
    extensions_used: set[str] = set()

    def carry_image(source_index: int) -> int:
        if source_index in image_map:
            return image_map[source_index]
        if not 0 <= source_index < len(source_images):
            raise GlbWriteError(f"source image {source_index} does not exist")
        image = dict(source_images[source_index])
        uri = image.get("uri")
        if isinstance(uri, str) and not uri.startswith("data:"):
            # A candidate that depends on a sibling file is not self-contained,
            # and a provider upload would silently lose the texture.
            raise GlbWriteError(
                f"image {source_index} references the external file {uri!r}; "
                "the static candidate must be self-contained"
            )
        raw = _image_bytes(source_gltf, source_binary, source_images[source_index])
        offset, length = buffer.add(raw)
        buffer_views.append({"buffer": 0, "byteOffset": offset, "byteLength": length})
        carried = {
            "bufferView": len(buffer_views) - 1,
            "mimeType": str(image.get("mimeType") or "image/png"),
        }
        if image.get("name"):
            carried["name"] = str(image["name"])
        images.append(carried)
        image_map[source_index] = len(images) - 1
        return image_map[source_index]

    def carry_sampler(source_index: int) -> int:
        if source_index in sampler_map:
            return sampler_map[source_index]
        if not 0 <= source_index < len(source_samplers):
            raise GlbWriteError(f"source sampler {source_index} does not exist")
        samplers.append(copy.deepcopy(source_samplers[source_index]))
        sampler_map[source_index] = len(samplers) - 1
        return sampler_map[source_index]

    def carry_texture(source_index: int) -> int:
        if source_index in texture_map:
            return texture_map[source_index]
        if not 0 <= source_index < len(source_textures):
            raise GlbWriteError(f"source texture {source_index} does not exist")
        source_texture = source_textures[source_index]
        carried: dict = {}
        if source_texture.get("name"):
            carried["name"] = str(source_texture["name"])
        if isinstance(source_texture.get("source"), int):
            carried["source"] = carry_image(int(source_texture["source"]))
        if isinstance(source_texture.get("sampler"), int):
            carried["sampler"] = carry_sampler(int(source_texture["sampler"]))
        textures.append(carried)
        texture_map[source_index] = len(textures) - 1
        return texture_map[source_index]

    for source_index in wanted:
        material = copy.deepcopy(source_materials[source_index])
        _remap_texture_references(material, carry_texture)
        for name in (material.get("extensions") or {}):
            extensions_used.add(str(name))
        # Bookkeeping only: stripped again in `_pack_glb`, so it never reaches
        # the file, and the surface → material map stays positional.
        material["_source_index"] = source_index
        materials.append(material)

    return materials, textures, samplers, images, extensions_used


def _remap_texture_references(node, carry_texture, parent_key: str = "") -> None:
    """Rewrite every texture reference in place, at any depth.

    glTF spells a texture reference as `{"index": n, "texCoord": t}` under a key
    ending in `Texture`, and extensions such as `KHR_materials_specular` use the
    same shape, so recursing on the shape rather than on a fixed key list keeps
    carried-over extensions intact.
    """
    if isinstance(node, dict):
        if parent_key.endswith("Texture") and isinstance(node.get("index"), int):
            node["index"] = carry_texture(int(node["index"]))
        for key, value in node.items():
            _remap_texture_references(value, carry_texture, str(key))
    elif isinstance(node, list):
        for item in node:
            _remap_texture_references(item, carry_texture, parent_key)


def _image_bytes(gltf: dict, binary: bytes | None, image: dict) -> bytes:
    """The image's exact bytes, from the GLB buffer or its data URI."""
    if isinstance(image.get("bufferView"), int):
        view = (gltf.get("bufferViews") or [])[int(image["bufferView"])]
        if binary is None:
            raise GlbWriteError("image lives in a binary chunk that was not supplied")
        start = int(view.get("byteOffset", 0))
        return bytes(binary[start : start + int(view["byteLength"])])
    uri = image.get("uri")
    if isinstance(uri, str) and uri.startswith("data:"):
        import base64

        _, _, encoded = uri.partition(",")
        return base64.b64decode(encoded)
    raise GlbWriteError("image has neither a bufferView nor a data URI")


def _pack_glb(gltf: dict, binary: bytes) -> bytes:
    for material in gltf.get("materials", []):
        material.pop("_source_index", None)
    json_bytes = json.dumps(
        gltf, sort_keys=True, separators=(",", ":"), ensure_ascii=False
    ).encode("utf-8")
    json_bytes += b" " * (-len(json_bytes) % 4)
    binary_padded = binary + b"\x00" * (-len(binary) % 4)

    total = 12 + 8 + len(json_bytes) + (8 + len(binary_padded) if binary_padded else 0)
    out = bytearray()
    out += struct.pack("<III", GLB_MAGIC, 2, total)
    out += struct.pack("<II", len(json_bytes), CHUNK_JSON)
    out += json_bytes
    if binary_padded:
        out += struct.pack("<II", len(binary_padded), CHUNK_BIN)
        out += binary_padded
    return bytes(out)
