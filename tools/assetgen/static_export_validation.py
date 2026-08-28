"""Does the static export really carry the source's rest-pose surface, unrigged?

Three independent questions, answered separately so a pass cannot be borrowed
from another:

1. **Is the file unrigged?** Read from the output's own glTF JSON: skins,
   animations, joint attributes, node skin references, external dependencies and
   accessor bounds.
2. **Is the geometry the source's rest pose?** The engine's evaluation is
   compared against an INDEPENDENT Python evaluation of the source skin — joint
   world transforms composed with inverse bind matrices, blended by the source's
   own weights. If the bake captured an animation frame, a double-applied node
   transform or a reflected basis, this comparison moves; a self-comparison
   inside the engine would not.
3. **Does the engine see a static mesh when it re-imports the file?** A renamed
   or hidden skeleton is not an unrigged export.

TOLERANCES ARE DERIVED, NOT FITTED. Every number below comes from the float32
representation the data is stored in, not from an observed error. Vertex data
makes an exact round trip (float32 in, float32 out), so serialisation
comparisons are required to be EXACT; the independent evaluation is allowed one
representable step per accumulated term and nothing more.
"""

from __future__ import annotations

import hashlib

import numpy as np

from .glb_reader import GlbDocument, _node_local_matrix, _read_accessor

CHECK_PASS = "PASS"
CHECK_FAIL = "FAIL"
CHECK_UNVERIFIABLE = "UNVERIFIABLE"

#: One float32 mantissa step, relative. 2⁻²³ is the gap between consecutive
#: float32 values at a given exponent.
FLOAT32_RELATIVE_STEP = 2.0**-23

#: Linear blend skinning accumulates four weighted 4×4 products per vertex. Ten
#: representable steps is a generous but still representation-derived bound on
#: that arithmetic; it is not a fitted value and does not depend on this asset.
SKINNING_STEP_BUDGET = 10

#: Normals are unit vectors, so their error budget is absolute, not relative to
#: model size: the same ten steps at magnitude one.
NORMAL_ABSOLUTE_TOLERANCE = SKINNING_STEP_BUDGET * FLOAT32_RELATIVE_STEP


def _check(name: str, verdict: str, detail: str, measured: dict | None = None) -> dict:
    row = {"name": name, "verdict": verdict, "detail": detail}
    if measured is not None:
        row["measured"] = measured
    return row


def _verdict(checks: list[dict]) -> dict:
    failed = [c["name"] for c in checks if c["verdict"] == CHECK_FAIL]
    unverifiable = [c["name"] for c in checks if c["verdict"] == CHECK_UNVERIFIABLE]
    return {
        "passed": not failed and not unverifiable,
        "failed_checks": failed,
        "unverifiable_checks": unverifiable,
        "checks": checks,
    }


# ------------------------------------------------------- 1. is it unrigged?


def assert_unrigged(output: GlbDocument) -> dict:
    """Structural proof, from the output's own JSON."""
    gltf = output.gltf
    checks: list[dict] = []

    checks.append(
        _check(
            "no_skins",
            CHECK_PASS if not gltf.get("skins") else CHECK_FAIL,
            f"{len(gltf.get('skins') or [])} skin(s)",
        )
    )
    checks.append(
        _check(
            "no_animations",
            CHECK_PASS if not gltf.get("animations") else CHECK_FAIL,
            f"{len(gltf.get('animations') or [])} animation(s)",
        )
    )

    skinned_nodes = [
        str(node.get("name", ""))
        for node in gltf.get("nodes", [])
        if "skin" in node
    ]
    checks.append(
        _check(
            "no_node_references_a_skin",
            CHECK_PASS if not skinned_nodes else CHECK_FAIL,
            f"nodes carrying a skin: {skinned_nodes}",
        )
    )

    joint_attributes: list[str] = []
    for mesh in gltf.get("meshes", []):
        for primitive in mesh.get("primitives", []):
            for attribute in (primitive.get("attributes") or {}):
                if attribute.startswith(("JOINTS_", "WEIGHTS_")):
                    joint_attributes.append(attribute)
    checks.append(
        _check(
            "no_joint_or_weight_attributes",
            CHECK_PASS if not joint_attributes else CHECK_FAIL,
            f"skin attributes found: {sorted(set(joint_attributes))}",
        )
    )

    external: list[str] = []
    for buffer in gltf.get("buffers", []):
        uri = buffer.get("uri")
        if isinstance(uri, str) and not uri.startswith("data:"):
            external.append(f"buffer:{uri}")
    for image in gltf.get("images", []):
        uri = image.get("uri")
        if isinstance(uri, str) and not uri.startswith("data:"):
            external.append(f"image:{uri}")
    checks.append(
        _check(
            "self_contained",
            CHECK_PASS if not external else CHECK_FAIL,
            f"external references: {external}",
        )
    )

    bounds = _accessor_bounds_report(output)
    checks.append(
        _check(
            "accessor_and_buffer_bounds_valid",
            CHECK_PASS if not bounds["problems"] else CHECK_FAIL,
            "; ".join(bounds["problems"]) or "every accessor lies inside its buffer view",
            bounds["measured"],
        )
    )

    identity_nodes = [
        str(node.get("name", ""))
        for node in gltf.get("nodes", [])
        if any(key in node for key in ("matrix", "translation", "rotation", "scale"))
    ]
    checks.append(
        _check(
            "output_nodes_carry_no_transform",
            CHECK_PASS if not identity_nodes else CHECK_FAIL,
            f"nodes with a transform: {identity_nodes} "
            "(the bake is baked once, into vertex data)",
        )
    )

    return _verdict(checks)


def _accessor_bounds_report(output: GlbDocument) -> dict:
    gltf = output.gltf
    problems: list[str] = []
    buffers = gltf.get("buffers", [])
    views = gltf.get("bufferViews", [])
    for index, view in enumerate(views):
        buffer_index = int(view.get("buffer", 0))
        if not 0 <= buffer_index < len(buffers):
            problems.append(f"bufferView {index} points at missing buffer {buffer_index}")
            continue
        end = int(view.get("byteOffset", 0)) + int(view.get("byteLength", 0))
        if end > int(buffers[buffer_index].get("byteLength", 0)):
            problems.append(f"bufferView {index} ends past the buffer")
    for index, accessor in enumerate(gltf.get("accessors", [])):
        view_index = accessor.get("bufferView")
        if view_index is None:
            continue
        if not 0 <= int(view_index) < len(views):
            problems.append(f"accessor {index} points at missing bufferView {view_index}")

    for mesh_index, mesh in enumerate(gltf.get("meshes", [])):
        for primitive_index, primitive in enumerate(mesh.get("primitives", [])):
            position = (primitive.get("attributes") or {}).get("POSITION")
            indices = primitive.get("indices")
            if position is None or indices is None:
                continue
            vertex_count = int(gltf["accessors"][int(position)]["count"])
            for attribute, accessor_index in (primitive.get("attributes") or {}).items():
                count = int(gltf["accessors"][int(accessor_index)]["count"])
                if count != vertex_count:
                    problems.append(
                        f"mesh {mesh_index} primitive {primitive_index}: {attribute} "
                        f"has {count} elements for {vertex_count} vertices"
                    )
    return {
        "problems": problems,
        "measured": {
            "buffer_count": len(buffers),
            "buffer_view_count": len(views),
            "accessor_count": len(gltf.get("accessors", [])),
        },
    }


# --------------------------------------- 2. is it the source's rest pose?


def evaluate_source_rest_pose(source: GlbDocument) -> list[dict]:
    """Independently skin the source at its authored rest pose, in Python.

    Deliberately does not reuse the engine's arithmetic: positions are blended
    through `world(joint) · inverseBindMatrix` exactly as the glTF specification
    defines skinning, so agreement with the engine is evidence rather than
    tautology. An unskinned primitive is evaluated through its node chain.
    """
    gltf = source.gltf
    buffers = _source_buffers(source)
    nodes = gltf.get("nodes", [])
    world = _world_transforms(gltf)

    evaluated: list[dict] = []
    for node_index, node in enumerate(nodes):
        mesh_index = node.get("mesh")
        if not isinstance(mesh_index, int):
            continue
        mesh = gltf["meshes"][mesh_index]
        skin_index = node.get("skin")
        for primitive_index, primitive in enumerate(mesh.get("primitives", [])):
            attributes = primitive.get("attributes") or {}
            if "POSITION" not in attributes:
                continue
            positions = _read_accessor(gltf, buffers, int(attributes["POSITION"])).astype(
                np.float64
            )
            normals = (
                _read_accessor(gltf, buffers, int(attributes["NORMAL"])).astype(np.float64)
                if "NORMAL" in attributes
                else None
            )
            if isinstance(skin_index, int):
                matrices = _skinning_matrices(gltf, buffers, skin_index, world)
                joints = _read_accessor(gltf, buffers, int(attributes["JOINTS_0"])).astype(
                    np.int64
                )
                weights = _read_accessor(
                    gltf, buffers, int(attributes["WEIGHTS_0"])
                ).astype(np.float64)
                skinned, skinned_normals = _blend(positions, normals, joints, weights, matrices)
            else:
                transform = world.get(node_index, np.eye(4))
                homogeneous = np.hstack([positions, np.ones((positions.shape[0], 1))])
                skinned = (homogeneous @ transform.T)[:, :3]
                skinned_normals = None
                if normals is not None:
                    inverse_transpose = np.linalg.inv(transform[:3, :3]).T
                    skinned_normals = _normalise(normals @ inverse_transpose.T)

            indices = (
                _read_accessor(gltf, buffers, int(primitive["indices"]))
                .astype(np.int64)
                .ravel()
                if "indices" in primitive
                else np.arange(positions.shape[0], dtype=np.int64)
            )
            evaluated.append(
                {
                    "node_index": node_index,
                    "mesh_index": mesh_index,
                    "primitive_index": primitive_index,
                    "skinned": isinstance(skin_index, int),
                    "positions": skinned,
                    "normals": skinned_normals,
                    "indices": indices,
                    "material_index": primitive.get("material"),
                }
            )
    return evaluated


def _source_buffers(source: GlbDocument) -> list[bytes | None]:
    from .glb_reader import _read_glb_container, _resolve_buffers

    if source.path.suffix.lower() == ".glb":
        gltf, binary = _read_glb_container(source.path)
        return _resolve_buffers(gltf, binary, source.path.parent, [])
    return _resolve_buffers(source.gltf, None, source.path.parent, [])


def _world_transforms(gltf: dict) -> dict[int, np.ndarray]:
    nodes = gltf.get("nodes", [])
    scenes = gltf.get("scenes", [])
    roots = (
        list(scenes[int(gltf.get("scene", 0))].get("nodes", []))
        if scenes
        else list(range(len(nodes)))
    )
    world: dict[int, np.ndarray] = {}
    stack: list[tuple[int, np.ndarray]] = [(int(r), np.eye(4)) for r in roots]
    while stack:
        index, parent = stack.pop()
        if index in world or not 0 <= index < len(nodes):
            continue
        matrix = parent @ _node_local_matrix(nodes[index])
        world[index] = matrix
        for child in nodes[index].get("children", []) or []:
            stack.append((int(child), matrix))
    return world


def _skinning_matrices(
    gltf: dict, buffers: list[bytes | None], skin_index: int, world: dict[int, np.ndarray]
) -> np.ndarray:
    skin = gltf["skins"][skin_index]
    joints = [int(j) for j in skin.get("joints", [])]
    if "inverseBindMatrices" in skin:
        raw = _read_accessor(gltf, buffers, int(skin["inverseBindMatrices"])).astype(
            np.float64
        )
        inverse_bind = raw.reshape(-1, 4, 4).transpose(0, 2, 1)
    else:
        inverse_bind = np.stack([np.eye(4)] * len(joints))
    return np.stack(
        [world.get(joint, np.eye(4)) @ inverse_bind[k] for k, joint in enumerate(joints)]
    )


def _blend(
    positions: np.ndarray,
    normals: np.ndarray | None,
    joints: np.ndarray,
    weights: np.ndarray,
    matrices: np.ndarray,
) -> tuple[np.ndarray, np.ndarray | None]:
    count = positions.shape[0]
    influences = weights.shape[1]
    blended = np.zeros((count, 4, 4))
    total = weights.sum(axis=1)
    for slot in range(influences):
        weight = weights[:, slot]
        index = np.clip(joints[:, slot], 0, matrices.shape[0] - 1)
        blended += weight[:, None, None] * matrices[index]
    # An unweighted vertex stays where the mesh put it, matching the engine.
    unweighted = total <= 1e-8
    blended[~unweighted] /= total[~unweighted][:, None, None]
    blended[unweighted] = np.eye(4)

    homogeneous = np.hstack([positions, np.ones((count, 1))])
    skinned = np.einsum("nij,nj->ni", blended, homogeneous)[:, :3]

    skinned_normals = None
    if normals is not None:
        bases = blended[:, :3, :3]
        determinants = np.linalg.det(bases)
        inverse_transpose = np.transpose(np.linalg.inv(bases), (0, 2, 1))
        carried = np.einsum("nij,nj->ni", inverse_transpose, normals)
        carried *= np.sign(determinants)[:, None]
        skinned_normals = _normalise(carried)
    return skinned, skinned_normals


def _normalise(vectors: np.ndarray) -> np.ndarray:
    lengths = np.linalg.norm(vectors, axis=1, keepdims=True)
    lengths[lengths == 0.0] = 1.0
    return vectors / lengths


def compare_rest_pose_to_output(
    *,
    baked_surfaces: list,
    baked_measurement: dict,
    output: GlbDocument,
    source: GlbDocument,
) -> dict:
    """Compare the engine's rest-pose evaluation, the written file, and Python's
    independent evaluation of the same source skin."""
    checks: list[dict] = []

    reference = evaluate_source_rest_pose(source)
    baked_positions = [np.asarray(s.positions, dtype=np.float64) for s in baked_surfaces]
    baked_indices = [np.asarray(s.indices, dtype=np.int64) for s in baked_surfaces]
    output_positions = [np.asarray(p.positions, dtype=np.float64) for p in output.primitives]
    output_indices = [np.asarray(p.triangles, dtype=np.int64).ravel() for p in output.primitives]

    checks.append(
        _check(
            "identical_triangle_count",
            CHECK_PASS if source.triangle_count == output.triangle_count else CHECK_FAIL,
            f"source {source.triangle_count} vs output {output.triangle_count}",
            {"source": source.triangle_count, "output": output.triangle_count},
        )
    )
    checks.append(
        _check(
            "identical_surface_count",
            CHECK_PASS if len(source.primitives) == len(output.primitives) else CHECK_FAIL,
            f"source {len(source.primitives)} vs output {len(output.primitives)} primitive(s)",
        )
    )
    checks.append(
        _check(
            "identical_vertex_count",
            CHECK_PASS if source.vertex_count == output.vertex_count else CHECK_FAIL,
            f"source {source.vertex_count} vs output {output.vertex_count}",
        )
    )

    checks.append(
        _check(
            "distinct_position_count_agrees",
            CHECK_PASS
            if _distinct_count(reference, "positions") == _distinct_count_arrays(output_positions)
            else CHECK_FAIL,
            f"{_distinct_count(reference, 'positions')} distinct source positions against "
            f"{_distinct_count_arrays(output_positions)} in the output; UV and normal seams "
            "split vertices, so this is the count that must survive",
        )
    )

    # --- serialisation fidelity: float32 in, float32 out, so EXACT or broken.
    serialisation = _max_difference(baked_positions, output_positions)
    checks.append(
        _check(
            "written_file_matches_the_evaluated_arrays_exactly",
            CHECK_PASS if serialisation["max_abs"] == 0.0 else CHECK_FAIL,
            "vertex data makes an exact float32 round trip; any difference is a "
            f"serialisation defect (max {serialisation['max_abs']:.3e})",
            serialisation,
        )
    )
    index_equal = len(baked_indices) == len(output_indices) and all(
        a.shape == b.shape and bool(np.array_equal(a, b))
        for a, b in zip(baked_indices, output_indices, strict=False)
    )
    checks.append(
        _check(
            "indices_survive_unchanged",
            CHECK_PASS if index_equal else CHECK_FAIL,
            "triangle topology is preserved index for index",
        )
    )

    # --- independent evaluation of the same source skin, compared without
    #     assuming a shared vertex order.
    reference_vertices = _stack(reference, "positions")
    output_all = np.concatenate(output_positions) if output_positions else np.zeros((0, 3))
    magnitude = max(float(np.abs(reference_vertices).max()) if reference_vertices.size else 1.0, 1.0)
    tolerance = SKINNING_STEP_BUDGET * FLOAT32_RELATIVE_STEP * magnitude

    hausdorff = _hausdorff(reference_vertices, output_all, tolerance)
    hausdorff["tolerance"] = tolerance
    hausdorff["tolerance_derivation"] = (
        f"{SKINNING_STEP_BUDGET} float32 mantissa steps (2^-23) at coordinate "
        f"magnitude {magnitude:.6g}"
    )
    checks.append(
        _check(
            "vertex_sets_agree_with_the_independent_evaluation",
            CHECK_PASS if hausdorff["max_distance"] <= tolerance else CHECK_FAIL,
            "every output vertex coincides with a vertex of a specification-level "
            f"Python evaluation of the source skin, within {tolerance:.3e}. An "
            "animation frame, a doubled transform or an altered scale moves this.",
            hausdorff,
        )
    )

    areas = _triangle_area_distribution(reference, output)
    checks.append(
        _check(
            "triangle_area_distribution_agrees",
            CHECK_PASS if areas["within"] else CHECK_FAIL,
            areas["detail"],
            {k: v for k, v in areas.items() if k not in ("within", "detail")},
        )
    )

    normals = _normal_consistency(reference, output, baked_surfaces)
    for row in normals:
        checks.append(row)

    # --- aggregate geometry.
    aggregate = _aggregate_comparison(reference, output)
    for name, row in aggregate.items():
        checks.append(
            _check(
                name,
                CHECK_PASS if row["within"] else CHECK_FAIL,
                row["detail"],
                {k: v for k, v in row.items() if k not in ("within", "detail")},
            )
        )

    # --- winding / handedness.
    handedness = _handedness(reference, output)
    checks.append(
        _check(
            "triangle_winding_and_handedness_preserved",
            CHECK_PASS if handedness["preserved"] else CHECK_FAIL,
            handedness["detail"],
            handedness,
        )
    )

    # --- materials, UVs, textures.
    checks.extend(_material_checks(source, output))
    checks.append(_uv_check(reference, source, output))

    verdict = _verdict(checks)
    verdict["baked_measurement"] = baked_measurement
    verdict["tolerances"] = {
        "float32_relative_step": FLOAT32_RELATIVE_STEP,
        "skinning_step_budget": SKINNING_STEP_BUDGET,
        "normal_absolute_tolerance": NORMAL_ABSOLUTE_TOLERANCE,
        "serialisation": "exact (0.0); float32 data is not re-quantised",
        "derivation": (
            "Every tolerance is the float32 representation step multiplied by the "
            "number of accumulated terms, not a value chosen from observed error."
        ),
    }
    return verdict


def _max_difference(left: list[np.ndarray], right: list[np.ndarray]) -> dict:
    if len(left) != len(right):
        return {"max_abs": float("inf"), "detail": "different surface counts"}
    worst = 0.0
    for a, b in zip(left, right, strict=False):
        if a.shape != b.shape:
            return {"max_abs": float("inf"), "detail": f"{a.shape} vs {b.shape}"}
        if a.size:
            worst = max(worst, float(np.abs(a - b).max()))
    return {"max_abs": worst}


def _stack(reference: list[dict], key: str) -> np.ndarray:
    blocks = [np.asarray(r[key]) for r in reference if r.get(key) is not None]
    return np.concatenate(blocks) if blocks else np.zeros((0, 3))


def _distinct_count(reference: list[dict], key: str) -> int:
    return _distinct_count_arrays([_stack(reference, key)])


def _distinct_count_arrays(arrays: list[np.ndarray]) -> int:
    """How many geometrically distinct positions there are.

    Quantised to a grid far coarser than the float32 noise floor and far finer
    than any real vertex spacing, so the count is stable without being blind.
    """
    if not arrays:
        return 0
    stacked = np.concatenate([np.asarray(a) for a in arrays if np.asarray(a).size])
    if stacked.size == 0:
        return 0
    quantised = np.round(stacked / 1e-5).astype(np.int64)
    return int(np.unique(quantised, axis=0).shape[0])


def _hausdorff(left: np.ndarray, right: np.ndarray, cell: float) -> dict:
    """Worst distance from a point of one set to the nearest point of the other.

    Order-independent by construction, which is what is needed here: the engine
    rebuilds vertex order on import, so a positional diff would compare unrelated
    vertices and report the model's diameter.
    """
    if left.size == 0 or right.size == 0:
        return {"max_distance": float("inf"), "detail": "one side has no vertices"}
    spacing = max(cell * 100.0, 1e-4)
    forward = _nearest_worst(left, right, spacing)
    backward = _nearest_worst(right, left, spacing)
    return {
        "max_distance": max(forward, backward),
        "max_output_to_source": forward,
        "max_source_to_output": backward,
        "compared_points": int(left.shape[0]),
    }


def _nearest_worst(query: np.ndarray, target: np.ndarray, spacing: float) -> float:
    buckets: dict[tuple[int, int, int], list[int]] = {}
    keys = np.floor(target / spacing).astype(np.int64)
    for index, key in enumerate(map(tuple, keys)):
        buckets.setdefault(key, []).append(index)
    worst = 0.0
    query_keys = np.floor(query / spacing).astype(np.int64)
    neighbourhood = [(x, y, z) for x in (-1, 0, 1) for y in (-1, 0, 1) for z in (-1, 0, 1)]
    for point, key in zip(query, map(tuple, query_keys), strict=False):
        best = float("inf")
        for offset in neighbourhood:
            for index in buckets.get(
                (key[0] + offset[0], key[1] + offset[1], key[2] + offset[2]), ()
            ):
                distance = float(np.linalg.norm(target[index] - point))
                if distance < best:
                    best = distance
                    if best == 0.0:
                        break
            if best == 0.0:
                break
        if best > worst:
            worst = best
    return worst


def _triangle_area_distribution(reference: list[dict], output: GlbDocument) -> dict:
    """Sorted per-triangle areas: a dropped, merged or distorted surface moves it.

    Sorted rather than paired, because there is no shared triangle order; a
    dropped surface changes the length of the distribution, and a distortion
    changes its values.
    """
    reference_vertices = _stack(reference, "positions")
    reference_areas = np.sort(
        _triangle_areas(reference_vertices, _merged_indices(reference))
    )
    output_vertices, output_triangles = output.merged_geometry()
    output_areas = np.sort(_triangle_areas(output_vertices, output_triangles))
    if reference_areas.shape != output_areas.shape:
        return {
            "within": False,
            "detail": (
                f"{reference_areas.shape[0]} source triangles against "
                f"{output_areas.shape[0]} in the output"
            ),
        }
    if reference_areas.size == 0:
        return {"within": False, "detail": "no triangles"}
    largest = float(reference_areas.max())
    tolerance = SKINNING_STEP_BUDGET * FLOAT32_RELATIVE_STEP * max(largest, 1.0)
    worst = float(np.abs(reference_areas - output_areas).max())
    return {
        "within": worst <= tolerance,
        "detail": (
            f"worst per-triangle area difference {worst:.3e} against {tolerance:.3e} "
            f"over {reference_areas.size} triangles"
        ),
        "max_abs": worst,
        "tolerance": tolerance,
        "triangle_count": int(reference_areas.size),
    }


def _triangle_areas(vertices: np.ndarray, triangles: np.ndarray) -> np.ndarray:
    if triangles.size == 0:
        return np.zeros(0)
    a = vertices[triangles[:, 0]]
    b = vertices[triangles[:, 1]]
    c = vertices[triangles[:, 2]]
    return 0.5 * np.linalg.norm(np.cross(b - a, c - a), axis=1)


def _normal_consistency(
    reference: list[dict], output: GlbDocument, baked_surfaces: list
) -> list[dict]:
    """Do stored normals agree with the geometry they belong to, on both sides?

    Comparing normals per vertex across the two files is impossible without a
    shared order, so the invariant checked instead is the one that actually
    matters: a stored normal must agree with the face normal implied by its own
    triangle winding. Inverted normals or a rewound export break it on exactly
    one side.
    """
    rows: list[dict] = []
    reference_agreement = _normal_face_agreement(
        _stack(reference, "positions"), _merged_indices(reference), _stack(reference, "normals")
    )
    output_normals = _read_normals(output)
    output_vertices, output_triangles = output.merged_geometry()
    output_agreement = _normal_face_agreement(
        output_vertices,
        output_triangles,
        np.concatenate(output_normals) if output_normals else np.zeros((0, 3)),
    )
    if reference_agreement is None or output_agreement is None:
        rows.append(
            _check(
                "normals_agree_with_their_own_winding",
                CHECK_UNVERIFIABLE,
                "one side declares no normals",
            )
        )
        return rows

    rows.append(
        _check(
            "normals_agree_with_their_own_winding",
            CHECK_PASS if output_agreement > 0.9 else CHECK_FAIL,
            f"mean agreement between stored normals and face winding: source "
            f"{reference_agreement:.6f}, output {output_agreement:.6f}. Inverted "
            "normals or a reversed winding drive this negative.",
            {"source": reference_agreement, "output": output_agreement},
        )
    )
    rows.append(
        _check(
            "normal_orientation_convention_matches_the_source",
            CHECK_PASS
            if (reference_agreement >= 0) == (output_agreement >= 0)
            else CHECK_FAIL,
            "both files agree on which side of a face its normals point to",
        )
    )
    # Not "are the tangents equal": a fabricated tangent set is the failure mode
    # here. Godot generates tangents on import, so writing them would put derived
    # data into a file whose source declared none.
    carried = [s for s in baked_surfaces if getattr(s, "tangents", None) is not None]
    written = bool(_read_tangents(output))
    rows.append(
        _check(
            "tangents_not_fabricated",
            CHECK_PASS if bool(carried) == written else CHECK_FAIL,
            (
                "tangents are carried from the source and their handedness sign rides "
                "the bake basis"
                if written
                else "neither the source nor the output declares TANGENT; the "
                "engine-generated tangents are not written into the candidate"
            ),
            {"source_declared": bool(carried), "output_contains": written},
        )
    )
    return rows


def _normal_face_agreement(
    vertices: np.ndarray, triangles: np.ndarray, normals: np.ndarray
) -> float | None:
    if normals.size == 0 or triangles.size == 0 or vertices.shape[0] != normals.shape[0]:
        return None
    a = vertices[triangles[:, 0]]
    b = vertices[triangles[:, 1]]
    c = vertices[triangles[:, 2]]
    face = np.cross(b - a, c - a)
    face = _normalise(face)
    stored = _normalise(normals[triangles].mean(axis=1))
    return float(np.sum(face * stored, axis=1).mean())


def _read_normals(document: GlbDocument) -> list[np.ndarray]:
    return _read_attribute(document, "NORMAL")


def _read_tangents(document: GlbDocument) -> list[np.ndarray]:
    return _read_attribute(document, "TANGENT")


def _read_attribute(document: GlbDocument, attribute: str) -> list[np.ndarray]:
    gltf = document.gltf
    buffers = _source_buffers(document)
    out: list[np.ndarray] = []
    for mesh in gltf.get("meshes", []):
        for primitive in mesh.get("primitives", []):
            accessor = (primitive.get("attributes") or {}).get(attribute)
            if accessor is None:
                continue
            out.append(_read_accessor(gltf, buffers, int(accessor)).astype(np.float64))
    return out


def _max_normal_angle(left: list, right: list) -> dict:
    worst = 0.0
    dots: list[float] = []
    for a, b in zip(left, right, strict=False):
        a = _normalise(np.asarray(a, dtype=np.float64))
        b = _normalise(np.asarray(b, dtype=np.float64))
        if a.shape != b.shape:
            return {"max_abs": float("inf"), "mean_dot": -1.0}
        worst = max(worst, float(np.abs(a - b).max()))
        dots.append(float(np.sum(a * b, axis=1).mean()))
    return {"max_abs": worst, "mean_dot": float(np.mean(dots)) if dots else -1.0}


def _aggregate_comparison(reference: list[dict], output: GlbDocument) -> dict:
    reference_vertices = (
        np.concatenate([np.asarray(r["positions"]) for r in reference])
        if reference
        else np.zeros((0, 3))
    )
    output_vertices, output_triangles = output.merged_geometry()
    if reference_vertices.size == 0 or output_vertices.size == 0:
        return {}

    magnitude = max(float(np.abs(reference_vertices).max()), 1.0)
    tolerance = SKINNING_STEP_BUDGET * FLOAT32_RELATIVE_STEP * magnitude

    reference_triangles = _merged_indices(reference)
    rows: dict[str, dict] = {}

    for label, index in (("aabb_min", 0), ("aabb_max", 1)):
        left = reference_vertices.min(axis=0) if index == 0 else reference_vertices.max(axis=0)
        right = output_vertices.min(axis=0) if index == 0 else output_vertices.max(axis=0)
        difference = float(np.abs(left - right).max())
        rows[f"{label}_agrees"] = {
            "within": difference <= tolerance,
            "detail": f"max component difference {difference:.3e} against {tolerance:.3e}",
            "source": [float(v) for v in left],
            "output": [float(v) for v in right],
            "tolerance": tolerance,
        }

    centroid_difference = float(
        np.abs(reference_vertices.mean(axis=0) - output_vertices.mean(axis=0)).max()
    )
    rows["centroid_agrees"] = {
        "within": centroid_difference <= tolerance,
        "detail": f"centroid differs by {centroid_difference:.3e} against {tolerance:.3e}",
        "tolerance": tolerance,
    }

    reference_area = _surface_area(reference_vertices, reference_triangles)
    output_area = _surface_area(output_vertices, output_triangles)
    relative = abs(reference_area - output_area) / max(reference_area, 1e-12)
    area_tolerance = SKINNING_STEP_BUDGET * FLOAT32_RELATIVE_STEP
    rows["surface_area_agrees"] = {
        "within": relative <= area_tolerance,
        "detail": f"relative area difference {relative:.3e} against {area_tolerance:.3e}",
        "source": reference_area,
        "output": output_area,
    }

    reference_height = float(reference_vertices[:, 1].max() - reference_vertices[:, 1].min())
    output_height = float(output_vertices[:, 1].max() - output_vertices[:, 1].min())
    rows["humanoid_height_agrees"] = {
        "within": abs(reference_height - output_height) <= tolerance,
        "detail": f"height {reference_height:.6f} vs {output_height:.6f}",
        "source": reference_height,
        "output": output_height,
    }
    reference_ground = float(reference_vertices[:, 1].min())
    output_ground = float(output_vertices[:, 1].min())
    rows["ground_height_agrees"] = {
        "within": abs(reference_ground - output_ground) <= tolerance,
        "detail": f"lowest vertex {reference_ground:.6e} vs {output_ground:.6e}",
        "source": reference_ground,
        "output": output_ground,
    }
    return rows


def _merged_indices(reference: list[dict]) -> np.ndarray:
    blocks: list[np.ndarray] = []
    offset = 0
    for entry in reference:
        indices = np.asarray(entry["indices"], dtype=np.int64)
        usable = (indices.shape[0] // 3) * 3
        blocks.append(indices[:usable].reshape(-1, 3) + offset)
        offset += int(np.asarray(entry["positions"]).shape[0])
    return np.concatenate(blocks) if blocks else np.zeros((0, 3), dtype=np.int64)


def _surface_area(vertices: np.ndarray, triangles: np.ndarray) -> float:
    if triangles.size == 0:
        return 0.0
    a = vertices[triangles[:, 0]]
    b = vertices[triangles[:, 1]]
    c = vertices[triangles[:, 2]]
    return float(0.5 * np.linalg.norm(np.cross(b - a, c - a), axis=1).sum())


def _handedness(reference: list[dict], output: GlbDocument) -> dict:
    """A reflected export keeps its area and its AABB but inverts its volume."""
    reference_vertices = (
        np.concatenate([np.asarray(r["positions"]) for r in reference])
        if reference
        else np.zeros((0, 3))
    )
    output_vertices, output_triangles = output.merged_geometry()
    if reference_vertices.size == 0 or output_vertices.size == 0:
        return {"preserved": False, "detail": "no geometry to compare"}
    reference_volume = _signed_volume(reference_vertices, _merged_indices(reference))
    output_volume = _signed_volume(output_vertices, output_triangles)
    same_sign = (reference_volume >= 0) == (output_volume >= 0)
    magnitude = abs(reference_volume)
    relative = abs(abs(reference_volume) - abs(output_volume)) / max(magnitude, 1e-15)
    return {
        "preserved": bool(same_sign and relative <= SKINNING_STEP_BUDGET * FLOAT32_RELATIVE_STEP),
        "detail": (
            f"signed volume {reference_volume:.6e} vs {output_volume:.6e}; a mirrored "
            "or rewound export changes the sign"
        ),
        "source_signed_volume": reference_volume,
        "output_signed_volume": output_volume,
        "relative_magnitude_difference": relative,
    }


def _signed_volume(vertices: np.ndarray, triangles: np.ndarray) -> float:
    if triangles.size == 0:
        return 0.0
    a = vertices[triangles[:, 0]]
    b = vertices[triangles[:, 1]]
    c = vertices[triangles[:, 2]]
    return float(np.einsum("ij,ij->i", a, np.cross(b, c)).sum() / 6.0)


def _material_checks(source: GlbDocument, output: GlbDocument) -> list[dict]:
    checks: list[dict] = []
    source_names = [str(m.get("name", "")) for m in source.materials]
    output_names = [str(m.get("name", "")) for m in output.materials]
    used_source = sorted(
        {p.material_index for p in source.primitives if p.material_index is not None}
    )
    expected = [source_names[i] for i in used_source if 0 <= i < len(source_names)]
    checks.append(
        _check(
            "material_slots_agree",
            CHECK_PASS if output_names == expected else CHECK_FAIL,
            f"expected {expected}, output has {output_names}",
        )
    )

    source_images = _image_digests(source)
    output_images = _image_digests(output)
    checks.append(
        _check(
            "embedded_texture_bytes_identical",
            CHECK_PASS
            if output_images and output_images == source_images[: len(output_images)]
            else (CHECK_UNVERIFIABLE if not source_images else CHECK_FAIL),
            f"{len(output_images)} carried image(s); digests "
            f"{'match' if output_images == source_images[: len(output_images)] else 'differ'}",
            {"source": source_images, "output": output_images},
        )
    )

    source_extensions = set(source.gltf.get("extensionsUsed") or [])
    output_extensions = set(output.gltf.get("extensionsUsed") or [])
    checks.append(
        _check(
            "material_extensions_carried",
            CHECK_PASS if output_extensions <= source_extensions else CHECK_FAIL,
            f"source {sorted(source_extensions)}, output {sorted(output_extensions)}",
        )
    )
    return checks


def _image_digests(document: GlbDocument) -> list[str]:
    from .glb_reader import _read_glb_container

    binary: bytes | None = None
    if document.path.suffix.lower() == ".glb":
        _, binary = _read_glb_container(document.path)
    digests: list[str] = []
    for image in document.images:
        raw: bytes | None = None
        if isinstance(image.get("bufferView"), int) and binary is not None:
            view = document.gltf["bufferViews"][int(image["bufferView"])]
            start = int(view.get("byteOffset", 0))
            raw = bytes(binary[start : start + int(view["byteLength"])])
        elif isinstance(image.get("uri"), str) and str(image["uri"]).startswith("data:"):
            import base64

            _, _, encoded = str(image["uri"]).partition(",")
            raw = base64.b64decode(encoded)
        if raw is not None:
            digests.append(hashlib.sha256(raw).hexdigest())
    return digests


def _uv_check(reference: list[dict], source: GlbDocument, output: GlbDocument) -> dict:
    """UVs are carried, never recomputed, so the UV SET must be bit-identical.

    Compared as a multiset because the engine re-orders vertices. Exact equality
    is the right bar: a UV that changed at all was recomputed, and a flipped V
    convention — the classic engine round-trip defect — changes every value.
    """
    source_uvs = _read_uvs(source)
    output_uvs = _read_uvs(output)
    if not source_uvs:
        return _check("uv_set_identical", CHECK_UNVERIFIABLE, "the source declares no UV channel")
    if not output_uvs:
        return _check("uv_set_identical", CHECK_FAIL, "the output declares no UV channel")
    left = _lexsorted(np.concatenate(source_uvs))
    right = _lexsorted(np.concatenate(output_uvs))
    if left.shape != right.shape:
        return _check(
            "uv_set_identical", CHECK_FAIL, f"UV counts {left.shape} against {right.shape}"
        )
    exact = bool(np.array_equal(left, right))
    flipped = _lexsorted(np.column_stack([left[:, 0], 1.0 - left[:, 1]]))
    v_flipped = bool(np.array_equal(flipped, right))
    return _check(
        "uv_set_identical",
        CHECK_PASS if exact else CHECK_FAIL,
        "the output's UV set is exactly the source's"
        if exact
        else (
            "the output's V coordinates are flipped relative to the source"
            if v_flipped
            else "the output's UV set differs from the source's"
        ),
        {"exact": exact, "v_flipped": v_flipped, "count": int(left.shape[0])},
    )


def _lexsorted(rows: np.ndarray) -> np.ndarray:
    """Rows in a canonical order, so a multiset can be compared exactly."""
    values = np.asarray(rows, dtype=np.float64)
    if values.size == 0:
        return values
    order = np.lexsort(tuple(values[:, i] for i in range(values.shape[1] - 1, -1, -1)))
    return values[order]


def _read_uvs(document: GlbDocument) -> list[np.ndarray]:
    gltf = document.gltf
    buffers = _source_buffers(document)
    out: list[np.ndarray] = []
    for mesh in gltf.get("meshes", []):
        for primitive in mesh.get("primitives", []):
            accessor = (primitive.get("attributes") or {}).get("TEXCOORD_0")
            if accessor is None:
                continue
            out.append(_read_accessor(gltf, buffers, int(accessor)).astype(np.float64))
    return out


# ------------------------------------------- 3. what does the engine see?


def judge_reimport(report: dict, expected: dict | None = None) -> dict:
    """Verdict on a re-imported candidate, from the engine's own scene tree.

    `expected` is the bake's own measurement. Comparing against it closes the
    round trip: the file the engine reads back must describe the same geometry
    the engine evaluated, at the same size and in the same place.
    """
    inspection = report.get("inspection") or {}
    checks: list[dict] = []

    skeletons = inspection.get("skeletons") or []
    checks.append(
        _check(
            "no_skeleton3d_after_reimport",
            CHECK_PASS if not skeletons else CHECK_FAIL,
            f"{len(skeletons)} Skeleton3D node(s)",
        )
    )

    meshes = inspection.get("mesh_instances") or []
    visible = [m for m in meshes if bool(m.get("visible_in_tree"))]
    checks.append(
        _check(
            "visible_mesh_instance_present",
            CHECK_PASS if visible else CHECK_FAIL,
            f"{len(visible)} visible MeshInstance3D of {len(meshes)}",
        )
    )
    checks.append(
        _check(
            "no_skin_after_reimport",
            CHECK_PASS if not any(bool(m.get("has_skin")) for m in meshes) else CHECK_FAIL,
            "no MeshInstance3D carries a Skin",
        )
    )

    players = inspection.get("animation_players") or []
    with_clips = [p for p in players if (p.get("animations") or [])]
    # Godot synthesises a `RESET` track holder for some imports; a player that
    # carries no clip is inert and is reported rather than treated as a rig.
    checks.append(
        _check(
            "no_animation_clips_after_reimport",
            CHECK_PASS if not with_clips else CHECK_FAIL,
            f"{len(with_clips)} AnimationPlayer(s) carrying clips of {len(players)}",
        )
    )

    materials = [
        surface.get("active_material_name", "")
        for mesh in visible
        for surface in (mesh.get("surfaces") or [])
    ]
    checks.append(
        _check(
            "materials_resolve_after_reimport",
            CHECK_PASS if materials and all(materials) else CHECK_FAIL,
            f"surface materials: {materials}",
        )
    )

    measured = {
        "triangle_count": sum(int(m.get("triangle_count", 0)) for m in visible),
        "vertex_count": sum(int(m.get("vertex_count", 0)) for m in visible),
        "aabb": visible[0].get("aabb") if visible else None,
        "node_count": inspection.get("node_count"),
    }

    if expected:
        checks.append(
            _check(
                "reimported_triangle_count_matches_the_bake",
                CHECK_PASS
                if measured["triangle_count"] == int(expected.get("triangle_count", -1))
                else CHECK_FAIL,
                f"{measured['triangle_count']} against {expected.get('triangle_count')}",
            )
        )
        box = measured.get("aabb") or {}
        position = [float(v) for v in (box.get("position") or [])]
        size = [float(v) for v in (box.get("size") or [])]
        expected_min = [float(v) for v in (expected.get("aabb_min") or [])]
        expected_size = [float(v) for v in (expected.get("aabb_size") or [])]
        if len(position) == 3 and len(expected_min) == 3:
            magnitude = max(max(abs(v) for v in expected_min + expected_size), 1.0)
            tolerance = SKINNING_STEP_BUDGET * FLOAT32_RELATIVE_STEP * magnitude
            worst = max(
                max(abs(a - b) for a, b in zip(position, expected_min, strict=True)),
                max(abs(a - b) for a, b in zip(size, expected_size, strict=True)),
            )
            checks.append(
                _check(
                    "reimported_bounds_match_the_bake",
                    CHECK_PASS if worst <= tolerance else CHECK_FAIL,
                    f"worst bound difference {worst:.3e} against {tolerance:.3e}; "
                    "a doubled transform, an altered scale or a new yaw moves this",
                    {"max_abs": worst, "tolerance": tolerance},
                )
            )
        else:
            checks.append(
                _check(
                    "reimported_bounds_match_the_bake",
                    CHECK_UNVERIFIABLE,
                    "the re-import reported no usable bounding box",
                )
            )

    verdict = _verdict(checks)
    verdict["measured"] = measured
    return verdict


__all__ = [
    "CHECK_FAIL",
    "CHECK_PASS",
    "CHECK_UNVERIFIABLE",
    "FLOAT32_RELATIVE_STEP",
    "NORMAL_ABSOLUTE_TOLERANCE",
    "SKINNING_STEP_BUDGET",
    "assert_unrigged",
    "compare_rest_pose_to_output",
    "evaluate_source_rest_pose",
    "judge_reimport",
]
