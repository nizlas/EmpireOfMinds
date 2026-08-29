"""Rigged humanoid GLB in, static unrigged GLB out — entirely offline.

WHY THIS OPERATION EXISTS. Uthana's auto-rig takes an UNRIGGED mesh. Every local
humanoid delivery in this repository is already skinned and animated, so the
humanoid gate refuses all of them and no provider plan can become executable.
Baking an existing skin at its own rest pose yields a static candidate without
redesigning, decimating or re-authoring the mesh.

WHY THE WORK IS SPLIT. Godot owns the deformation, because the only defensible
rest-pose geometry is the one the renderer would draw — a Python re-implement-
ation of linear blend skinning would be a second, unverified deformation
implementation. This module owns everything else: process invocation, reading the
evaluated arrays, deterministic serialisation with the SOURCE's own materials and
texture bytes, structural and geometric validation, and the provenance record.

WHAT THIS IS NOT. Not a production asset pipeline, not a certification, not a
decimation step, and not a provider call. The output is a local candidate for a
possible morphological calibration probe, and it says so in its own provenance.
"""

from __future__ import annotations

import hashlib
import json
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path

import numpy as np

from . import static_export_validation as validation
from .artifact_paths import trusted_artifact_name, write_bytes_within
from .glb_reader import GlbParseError, load_glb
from .glb_writer import GENERATOR, GlbWriteError, SurfaceData, write_static_glb
from .hand_fixture_ingest import GodotNotAvailable, resolve_godot_executable

EXPORT_SCHEMA = "static_unrigged_export_v1"
BAKE_SCRIPT = "res://presentation/assetgen/tools/bake_static_unrigged_headless.gd"
DEFAULT_TIMEOUT_SECONDS = 900

#: Where a candidate may be written. Ignored by git: it is generated output, and
#: a committed copy would compete with the source asset for authority.
DEFAULT_CANDIDATE_ROOT = Path("artifacts/assetgen/provider_candidates")

#: Staging inside the Godot project, needed only because Godot can re-import a
#: file only from `res://`. Git-ignored and emptied afterwards. Deliberately not
#: a dot-directory: Godot's resource scanner skips those, so a candidate staged
#: there would never be imported and the re-import check would silently degrade
#: into "the engine could not see the file".
REIMPORT_STAGING = Path("game/artifacts/static_export/staging")

## What the output space is, stated once and carried into every report.
COORDINATE_SPACE_CONTRACT = {
    "space": "asset_root_local",
    "definition": (
        "Vertices are expressed in the space of the node the asset is instanced "
        "under, composed from the local transforms between that node and each "
        "mesh or skeleton. The asset's own internal root transform is therefore "
        "preserved and the caller's placement is excluded by construction."
    ),
    "handedness": "unchanged (Godot right-handed Y-up, matching the source glTF)",
    "up_axis": "+Y",
    "front_axis": "unchanged; no yaw is introduced",
    "ground_relation": "preserved; the lowest vertex keeps its source height",
    "scale": "preserved exactly; no height or unit normalisation is applied",
    "node_transforms": "baked exactly once into vertex data; the output node is identity",
    "caller_independence": (
        "translated, rotated, uniformly and non-uniformly scaled ancestors all "
        "produce byte-identical output"
    ),
}


class StaticExportError(RuntimeError):
    """A classified refusal. Nothing partial is written."""

    def __init__(self, code: str, detail: str) -> None:
        self.code = code
        self.detail = detail
        super().__init__(f"[{code}] {detail}")


@dataclass
class BakeRun:
    """One Godot bake invocation: its report and the evaluated arrays."""

    report: dict
    arrays: bytes
    exit_code: int

    @property
    def surfaces(self) -> list[dict]:
        return list(self.report.get("surfaces") or [])


def bake_rest_pose(
    *,
    project_path: Path,
    scene_res_path: str,
    report_path: Path,
    arrays_path: Path,
    holder_translation: str | None = None,
    holder_rotation_deg: str | None = None,
    holder_scale: str | None = None,
    play_animation: str | None = None,
    godot_executable: str | None = None,
    timeout_seconds: int = DEFAULT_TIMEOUT_SECONDS,
    runner=subprocess.run,
) -> BakeRun:
    """Evaluate the scene at its rest pose inside Godot headless.

    `holder_*` and `play_animation` exist so a caller can prove the bake is
    independent of scene placement and of an active animation. They are test
    instruments, not tuning knobs: they cannot change what is baked, only what
    the bake must survive.
    """
    executable = resolve_godot_executable(godot_executable)
    argv = [
        executable,
        "--headless",
        "--path",
        str(project_path),
        "-s",
        BAKE_SCRIPT,
        "--",
        f"--scene={scene_res_path}",
        "--mode=bake",
        f"--report={report_path}",
        f"--arrays={arrays_path}",
    ]
    for flag, value in (
        ("holder-translation", holder_translation),
        ("holder-rotation-deg", holder_rotation_deg),
        ("holder-scale", holder_scale),
        ("play-animation", play_animation),
    ):
        if value:
            argv.append(f"--{flag}={value}")

    try:
        completed = runner(
            argv, capture_output=True, text=True, timeout=timeout_seconds, check=False
        )
    except subprocess.TimeoutExpired as exc:
        raise StaticExportError(
            "STATIC_EXPORT_BAKE_TIMEOUT", f"the bake exceeded {timeout_seconds}s"
        ) from exc
    except OSError as exc:
        raise StaticExportError(
            "STATIC_EXPORT_GODOT_START_FAILED", f"could not start the bake: {exc}"
        ) from exc

    report = _parse_report(f"{completed.stdout}\n{completed.stderr}", report_path)
    if report is None:
        raise StaticExportError(
            "STATIC_EXPORT_REPORT_MISSING",
            "the bake produced no machine-readable report "
            f"(exit {completed.returncode})",
        )
    if not bool(report.get("ok", False)):
        raise StaticExportError(
            str(report.get("error_class", "STATIC_EXPORT_BAKE_FAILED")),
            str(report.get("detail", "the bake refused")),
        )
    if not Path(arrays_path).is_file():
        raise StaticExportError(
            "STATIC_EXPORT_ARRAYS_MISSING", f"{arrays_path} was not written"
        )
    arrays = Path(arrays_path).read_bytes()
    recorded = str(report.get("arrays_sha256", ""))
    if recorded and hashlib.sha256(arrays).hexdigest() != recorded:
        raise StaticExportError(
            "STATIC_EXPORT_ARRAYS_CORRUPT",
            "the evaluated arrays do not match the digest the bake recorded",
        )
    return BakeRun(report=report, arrays=arrays, exit_code=completed.returncode)


def _parse_report(text: str, report_path: Path) -> dict | None:
    """Prefer the file; fall back to the stdout marker so a report is not lost."""
    path = Path(report_path)
    if path.is_file():
        try:
            return json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            pass
    marker = "STATIC_BAKE "
    for line in reversed(text.splitlines()):
        position = line.find(marker)
        if position < 0:
            continue
        try:
            return json.loads(line[position + len(marker) :])
        except json.JSONDecodeError:
            continue
    return None


# ------------------------------------------------------- arrays -> surfaces


def surfaces_from_bake(run: BakeRun, source: object) -> tuple[list[SurfaceData], dict]:
    """Turn the evaluated blob into writer input, plus a correspondence record.

    `source` is the parsed source `GlbDocument`. Its materials are carried over
    verbatim, so each baked surface must be traceable to exactly one of them.

    THIS IS THE ENGINE → glTF CONVENTION BOUNDARY, and it is the one place a
    plausible-looking export goes wrong. Godot's front faces are wound the
    opposite way from glTF's, so writing the engine's index buffer unchanged
    produces a file whose every triangle faces inward: it still re-imports into
    Godot looking correct, because the same convention is applied on the way
    back, while every other glTF consumer — including the provider this
    candidate exists for — sees an inside-out model. The winding is therefore
    reversed here, and the geometry validator checks the signed volume against a
    specification-level evaluation of the source so a silent regression here
    cannot pass.

    Positions, normals and UVs need no conversion: Godot's glTF importer keeps
    them in the source's own axes and UV origin, which the validator confirms by
    comparing them against the raw accessors.
    """
    index = run.report.get("arrays") or []
    surfaces_meta = run.surfaces
    if len(index) != len(surfaces_meta):
        raise StaticExportError(
            "STATIC_EXPORT_ARRAYS_INCONSISTENT",
            f"{len(index)} array blocks for {len(surfaces_meta)} surfaces",
        )

    source_primitives = list(getattr(source, "primitives", []))
    source_materials = list(getattr(source, "materials", []))

    surfaces: list[SurfaceData] = []
    for position, (block, meta) in enumerate(zip(index, surfaces_meta, strict=True)):
        sections = block.get("sections") or {}
        vertex_count = int(block.get("vertex_count", 0))
        positions = _section(run.arrays, sections, "positions", vertex_count, 3)
        if positions is None:
            raise StaticExportError(
                "STATIC_EXPORT_POSITIONS_MISSING", f"surface {position} has no positions"
            )
        indices_raw = sections.get("indices")
        if not indices_raw:
            raise StaticExportError(
                "STATIC_EXPORT_INDICES_MISSING", f"surface {position} has no indices"
            )
        start = int(indices_raw["offset"])
        length = int(indices_raw["length"])
        engine_indices = np.frombuffer(run.arrays, dtype="<u4", count=length // 4, offset=start)
        if engine_indices.shape[0] % 3:
            raise StaticExportError(
                "STATIC_EXPORT_INDICES_NOT_TRIANGLES",
                f"surface {position} has {engine_indices.shape[0]} indices",
            )
        indices = engine_indices.reshape(-1, 3)[:, ::-1].reshape(-1)

        source_declares_tangent = _source_declares(
            source_primitives, position, "TANGENT"
        )
        surfaces.append(
            SurfaceData(
                positions=positions,
                indices=indices.astype("<u4"),
                normals=_section(run.arrays, sections, "normals", vertex_count, 3),
                uv=_section(run.arrays, sections, "uv", vertex_count, 2),
                uv2=_section(run.arrays, sections, "uv2", vertex_count, 2),
                colors=_section(run.arrays, sections, "colors", vertex_count, 4),
                # Godot generates tangents on import (`meshes/ensure_tangents`).
                # Writing them would add derived data the source never declared,
                # so they are carried only when the source itself had them.
                tangents=(
                    _section(run.arrays, sections, "tangents", vertex_count, 4)
                    if source_declares_tangent
                    else None
                ),
                source_material_index=_resolve_material_index(
                    source_materials, str(meta.get("material_name", "")), position
                ),
                name=str(meta.get("source_mesh_name", "")),
            )
        )

    return surfaces, _correspondence(surfaces, source_primitives)


def _section(
    blob: bytes, sections: dict, name: str, vertex_count: int, width: int
) -> np.ndarray | None:
    entry = sections.get(name)
    if not entry:
        return None
    start = int(entry["offset"])
    length = int(entry["length"])
    expected = vertex_count * width * 4
    if length != expected:
        raise StaticExportError(
            "STATIC_EXPORT_SECTION_SIZE_WRONG",
            f"{name} is {length} bytes, expected {expected}",
        )
    flat = np.frombuffer(blob, dtype="<f4", count=vertex_count * width, offset=start)
    return flat.reshape(vertex_count, width)


def _source_declares(source_primitives: list, position: int, attribute: str) -> bool:
    """Did the SOURCE primitive at this position declare the attribute itself?"""
    if not 0 <= position < len(source_primitives):
        return False
    primitive = source_primitives[position]
    return bool(
        {
            "TANGENT": getattr(primitive, "has_tangents", False),
            "NORMAL": getattr(primitive, "has_normals", False),
            "TEXCOORD_0": getattr(primitive, "has_uvs", False),
        }.get(attribute, False)
    )


def _resolve_material_index(
    source_materials: list[dict], material_name: str, position: int
) -> int | None:
    """Map an engine surface back to exactly one source material, or refuse.

    Matching is by name because the engine keeps glTF material names. When names
    are ambiguous the positional fallback is used only if it is unambiguous:
    guessing which material a surface used would silently retexture the model.
    """
    if not source_materials:
        return None
    names = [str(m.get("name", "")) for m in source_materials]
    if material_name:
        matches = [i for i, name in enumerate(names) if name == material_name]
        if len(matches) == 1:
            return matches[0]
        if len(matches) > 1:
            raise StaticExportError(
                "STATIC_EXPORT_MATERIAL_AMBIGUOUS",
                f"the source declares {len(matches)} materials named {material_name!r}",
            )
    if len(source_materials) == 1:
        return 0
    if 0 <= position < len(source_materials):
        raise StaticExportError(
            "STATIC_EXPORT_MATERIAL_UNRESOLVED",
            f"surface {position} reports material {material_name!r}, which the "
            "source does not declare; refusing to guess",
        )
    raise StaticExportError(
        "STATIC_EXPORT_MATERIAL_UNRESOLVED",
        f"surface {position} has no resolvable source material",
    )


def _correspondence(surfaces: list[SurfaceData], source_primitives: list) -> dict:
    """What can honestly be claimed about output-to-source vertex identity.

    Counts, and only counts, are decided here. Godot's importer rebuilds a
    surface's vertex order, so equal counts are NOT evidence of a shared order —
    the validator establishes the geometric correspondence separately, and it is
    that measurement, not this bookkeeping, that a claim may rest on.
    """
    baked = [(int(s.positions.shape[0]), int(s.indices.shape[0])) for s in surfaces]
    source = [(int(p.vertex_count), int(p.triangle_count * 3)) for p in source_primitives]
    return {
        "kind": "counts_only",
        "counts_match": baked == source,
        "baked_surfaces": baked,
        "source_primitives": source,
        "note": (
            "Vertex and index counts per surface. The engine re-orders vertices on "
            "import, so correspondence with the source is established geometrically "
            "in geometry_comparison, never from these numbers."
        ),
    }


# ------------------------------------------------------------------- export


def export_static_candidate(
    *,
    source_glb: Path,
    project_path: Path,
    candidate_root: Path = DEFAULT_CANDIDATE_ROOT,
    output_name: str | None = None,
    workspace: Path,
    godot_executable: str | None = None,
    verify_reimport: bool = True,
    prove_determinism: bool = False,
    runner=subprocess.run,
) -> dict:
    """Bake, write and validate one static candidate; return its provenance.

    `workspace` holds the bake's intermediate report and array blob and is the
    caller's to create and remove. Nothing is written outside `candidate_root`
    and `workspace`.
    """
    source = Path(source_glb).resolve()
    if not source.is_file():
        raise StaticExportError("STATIC_EXPORT_SOURCE_MISSING", str(source))
    try:
        document = load_glb(source)
    except GlbParseError as exc:
        raise StaticExportError("STATIC_EXPORT_SOURCE_UNPARSABLE", str(exc)) from exc

    scene_res_path = _res_path(source, Path(project_path))
    workspace = Path(workspace)
    workspace.mkdir(parents=True, exist_ok=True)

    run = bake_rest_pose(
        project_path=Path(project_path),
        scene_res_path=scene_res_path,
        report_path=workspace / "bake_report.json",
        arrays_path=workspace / "bake_arrays.bin",
        godot_executable=godot_executable,
        runner=runner,
    )
    surfaces, correspondence = surfaces_from_bake(run, document)

    name = output_name or trusted_artifact_name(
        run_id=source.stem, kind="static_unrigged", extension="glb"
    )
    try:
        payload = write_static_glb(
            surfaces=surfaces,
            source_gltf=document.gltf,
            source_binary=_binary_chunk(source),
            mesh_name=f"{source.stem}_static",
            node_name=f"{source.stem}_static",
        )
    except GlbWriteError as exc:
        raise StaticExportError("STATIC_EXPORT_WRITE_REFUSED", str(exc)) from exc

    destination = write_bytes_within(Path(candidate_root), name, payload)
    output = load_glb(destination)

    structural = validation.assert_unrigged(output)
    equivalence = validation.compare_rest_pose_to_output(
        baked_surfaces=surfaces,
        baked_measurement=run.report.get("measurement") or {},
        output=output,
        source=document,
    )

    reimport: dict = {"performed": False, "reason": "not requested"}
    if verify_reimport:
        reimport = verify_static_reimport(
            candidate=destination,
            project_path=Path(project_path),
            workspace=workspace,
            expected=run.report.get("measurement") or {},
            godot_executable=godot_executable,
            runner=runner,
        )

    determinism: dict = {"performed": False, "reason": "not requested"}
    if prove_determinism:
        determinism = prove_context_independence(
            source_glb=source,
            project_path=Path(project_path),
            workspace=workspace / "determinism",
            godot_executable=godot_executable,
            runner=runner,
        )
        determinism["performed"] = True
        # The digest a provider plan would bind must be the one the contexts
        # reproduce. Without this the proof could hold for a file nobody kept.
        digest = hashlib.sha256(payload).hexdigest()
        determinism["candidate_digest_reproduced"] = digest in set(
            determinism["distinct_digests"]
        )
        determinism["candidate_sha256"] = digest

    provenance = build_provenance(
        source=source,
        document=document,
        destination=destination,
        payload=payload,
        run=run,
        surfaces=surfaces,
        correspondence=correspondence,
        structural=structural,
        equivalence=equivalence,
        reimport=reimport,
        determinism=determinism,
    )
    provenance_name = name.rsplit(".", 1)[0] + ".provenance.json"
    provenance_path = write_bytes_within(
        Path(candidate_root),
        provenance_name,
        (json.dumps(provenance, indent=2, sort_keys=True) + "\n").encode("utf-8"),
    )
    provenance["provenance_path"] = _repo_relative(provenance_path)
    return provenance


def verify_static_reimport(
    *,
    candidate: Path,
    project_path: Path,
    workspace: Path,
    expected: dict | None = None,
    godot_executable: str | None = None,
    runner=subprocess.run,
) -> dict:
    """Re-import the written candidate in Godot and check what the engine sees.

    A renamed or hidden skeleton is not an unrigged export, so the check is what
    the engine builds from the file — not what the file's JSON claims.
    """
    staging = Path(project_path).parent / REIMPORT_STAGING
    staging.mkdir(parents=True, exist_ok=True)
    staged = staging / Path(candidate).name
    shutil.copyfile(candidate, staged)
    try:
        executable = resolve_godot_executable(godot_executable)
        imported = runner(
            [executable, "--headless", "--path", str(project_path), "--import"],
            capture_output=True,
            text=True,
            timeout=DEFAULT_TIMEOUT_SECONDS,
            check=False,
        )
        report_path = Path(workspace) / "reimport_report.json"
        inspect = runner(
            [
                executable,
                "--headless",
                "--path",
                str(project_path),
                "-s",
                BAKE_SCRIPT,
                "--",
                f"--scene={_res_path(staged, Path(project_path))}",
                "--mode=inspect",
                f"--report={report_path}",
            ],
            capture_output=True,
            text=True,
            timeout=DEFAULT_TIMEOUT_SECONDS,
            check=False,
        )
        report = _parse_report(f"{inspect.stdout}\n{inspect.stderr}", report_path)
        if report is None or not bool(report.get("ok", False)):
            return {
                "performed": True,
                "passed": False,
                "detail": "the re-imported candidate could not be inspected",
                "import_exit_code": imported.returncode,
                "inspect_exit_code": inspect.returncode,
            }
        return {"performed": True, **validation.judge_reimport(report, expected)}
    finally:
        # One known file, removed by exact path. No recursive deletion.
        if staged.is_file():
            staged.unlink()
        for leftover in staging.glob(staged.name + ".import"):
            leftover.unlink()


#: The caller contexts a candidate must survive unchanged. Each entry is baked in
#: its OWN fresh Godot process, so process-to-process stability and context
#: independence are proven by the same run. `identity_repeat` is not redundant: it
#: is the only entry that isolates per-process nondeterminism (hash ordering,
#: resource ids, timestamps) from the transform arithmetic.
DETERMINISM_CONTEXTS: tuple[dict, ...] = (
    {"name": "identity"},
    {"name": "identity_repeat"},
    {
        "name": "translated_and_rotated_ancestor",
        "holder_translation": "3.5,-1.25,7.0",
        "holder_rotation_deg": "0,37,0",
    },
    {"name": "uniform_ancestor_scale", "holder_scale": "2.5,2.5,2.5"},
    {"name": "non_uniform_ancestor_scale", "holder_scale": "1.7,0.6,2.3"},
    {
        "name": "rotated_scaled_translated_ancestor",
        "holder_translation": "-4.0,2.0,0.5",
        "holder_rotation_deg": "15,-100,8",
        "holder_scale": "0.25,0.25,0.25",
    },
    {"name": "animation_playing", "play_animation": "*"},
)


def prove_context_independence(
    *,
    source_glb: Path,
    project_path: Path,
    workspace: Path,
    contexts: tuple[dict, ...] = DETERMINISM_CONTEXTS,
    godot_executable: str | None = None,
    runner=subprocess.run,
) -> dict:
    """Bake the same asset under each caller context and compare the bytes.

    The candidate that a provider plan binds must be a property of the SOURCE, not
    of where the asset happened to sit in a scene or of what was playing at the
    time. Byte equality is the bar rather than approximate agreement, because an
    export that merely agreed to a tolerance would still produce a different
    SHA-256 in each run and no plan could bind it.

    Nothing is written outside `workspace`.
    """
    source = Path(source_glb).resolve()
    document = load_glb(source)
    binary = _binary_chunk(source)
    scene_res_path = _res_path(source, Path(project_path))
    workspace = Path(workspace)
    workspace.mkdir(parents=True, exist_ok=True)

    runs: list[dict] = []
    for context in contexts:
        name = str(context["name"])
        run = bake_rest_pose(
            project_path=Path(project_path),
            scene_res_path=scene_res_path,
            report_path=workspace / f"bake_{name}.json",
            arrays_path=workspace / f"bake_{name}.bin",
            holder_translation=context.get("holder_translation"),
            holder_rotation_deg=context.get("holder_rotation_deg"),
            holder_scale=context.get("holder_scale"),
            play_animation=context.get("play_animation"),
            godot_executable=godot_executable,
            runner=runner,
        )
        surfaces, _ = surfaces_from_bake(run, document)
        payload = write_static_glb(
            surfaces=surfaces,
            source_gltf=document.gltf,
            source_binary=binary,
            mesh_name=f"{source.stem}_static",
            node_name=f"{source.stem}_static",
        )
        runs.append(
            {
                "context": name,
                "holder": run.report.get("holder_transform"),
                "played_animation": run.report.get("played_animation"),
                "scene_state_restored": bool(
                    run.report.get("post_bake_inspection_matches", False)
                ),
                "arrays_sha256": hashlib.sha256(run.arrays).hexdigest(),
                "glb_sha256": hashlib.sha256(payload).hexdigest(),
                "size_bytes": len(payload),
                "positions": [surface.positions for surface in surfaces],
            }
        )

    digests = {row["glb_sha256"] for row in runs}
    reference = runs[0]["positions"]
    worst = 0.0
    for row in runs[1:]:
        worst = max(worst, _max_deviation(reference, row["positions"]))
    for row in runs:
        row.pop("positions")

    return {
        "contexts_run": [row["context"] for row in runs],
        "process_count": len(runs),
        "byte_identical": len(digests) == 1,
        "distinct_digests": sorted(digests),
        "max_positional_deviation": worst,
        "scene_state_restored_every_run": all(row["scene_state_restored"] for row in runs),
        "runs": runs,
    }


def _max_deviation(left: list[np.ndarray], right: list[np.ndarray]) -> float:
    if len(left) != len(right):
        return float("inf")
    worst = 0.0
    for a, b in zip(left, right, strict=True):
        if a.shape != b.shape:
            return float("inf")
        worst = max(worst, float(np.abs(a.astype(np.float64) - b.astype(np.float64)).max()))
    return worst


def build_provenance(
    *,
    source: Path,
    document,
    destination: Path,
    payload: bytes,
    run: BakeRun,
    surfaces: list[SurfaceData],
    correspondence: dict,
    structural: dict,
    equivalence: dict,
    reimport: dict,
    determinism: dict | None = None,
) -> dict:
    """The machine-readable record beside the candidate.

    Deliberately states what the candidate is NOT: no certification, no
    production-representative claim, no authorisation of a provider call.
    """
    inspection = run.report.get("inspection") or {}
    triangles = sum(int(s.indices.shape[0]) // 3 for s in surfaces)
    vertices = sum(int(s.positions.shape[0]) for s in surfaces)
    return {
        "schema": EXPORT_SCHEMA,
        "exporter": {
            "bake_schema": str(run.report.get("schema", "")),
            "bake_script": BAKE_SCRIPT,
            "writer": GENERATOR,
            "godot_version": (run.report.get("godot_version") or {}).get("string", ""),
        },
        "source": {
            "path": _repo_relative(source),
            "sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
            "size_bytes": source.stat().st_size,
            "generator": document.generator,
            "triangle_count": document.triangle_count,
            "vertex_count": document.vertex_count,
            "skin_count": len(document.skins),
            "joint_count": len(document.joint_node_indices()),
            "animation_names": document.animation_names(),
            "material_names": [str(m.get("name", "")) for m in document.materials],
            "image_count": len(document.images),
        },
        "output": {
            "path": _repo_relative(destination),
            "sha256": hashlib.sha256(payload).hexdigest(),
            "size_bytes": len(payload),
            "triangle_count": triangles,
            "vertex_count": vertices,
            "surface_count": len(surfaces),
            "attributes": sorted(
                {
                    name
                    for surface in surfaces
                    for name, array in (
                        ("POSITION", surface.positions),
                        ("NORMAL", surface.normals),
                        ("TANGENT", surface.tangents),
                        ("TEXCOORD_0", surface.uv),
                        ("TEXCOORD_1", surface.uv2),
                        ("COLOR_0", surface.colors),
                    )
                    if array is not None
                }
            ),
        },
        "coordinate_space": COORDINATE_SPACE_CONTRACT,
        "removed": {
            "skins": len(document.skins),
            "animations": len(document.animation_names()),
            "joint_nodes": len(document.joint_node_indices()),
            "joint_attributes": ["JOINTS_0", "WEIGHTS_0"],
            "animation_players": len(inspection.get("animation_players") or []),
            "skeletons": len(inspection.get("skeletons") or []),
            "cameras": int(inspection.get("camera_count", 0)),
            "lights": int(inspection.get("light_count", 0)),
            "bone_attachments": int(inspection.get("bone_attachment_count", 0)),
            "excluded_meshes": run.report.get("excluded_meshes") or [],
        },
        "retained": {
            "materials": [str(m.get("name", "")) for m in document.materials],
            "textures_embedded": len(document.images),
            "texture_bytes_copied_verbatim": True,
            "uv_channels": sum(
                1 for surface in surfaces if surface.uv is not None
            ),
            "normals": all(surface.normals is not None for surface in surfaces),
            "vertex_colors": any(surface.colors is not None for surface in surfaces),
        },
        "vertex_correspondence": correspondence,
        "structural_validation": structural,
        "geometry_comparison": equivalence,
        "godot_reimport": reimport,
        "determinism": determinism or {"performed": False, "reason": "not requested"},
        "bake_measurement": run.report.get("measurement") or {},
        "scene_state_restored": bool(run.report.get("post_bake_inspection_matches", False)),
        "candidate_classification": {
            "role": "possible morphological calibration probe",
            "production_representative_batch_evidence": False,
            "certified": False,
            "certification_note": (
                "This provenance is a record of a geometric operation. It is not "
                "a hand-fixture certification, not a grip acceptance and not a "
                "production asset approval."
            ),
        },
        "known_limitations": [
            "Triangle count is unchanged by design (a geometry-preserving bake), "
            "so this candidate is roughly five times the certified a0/a1 mesh and "
            "is not evidence of production-representative batch readiness.",
            "Tangents are not written: the source declares none and Godot's are "
            "generated on import, so persisting them would add derived data.",
            "bipedal_humanoid and hands_and_legs_separated remain human "
            "confirmations; no mechanical evidence for them is produced here.",
            "Visual equivalence is a human checkpoint. This record proves "
            "numerical agreement, not that the model looks right.",
        ],
    }


def _res_path(path: Path, project_path: Path) -> str:
    resolved = Path(path).resolve()
    project = Path(project_path).resolve()
    try:
        relative = resolved.relative_to(project)
    except ValueError as exc:
        raise StaticExportError(
            "STATIC_EXPORT_SOURCE_OUTSIDE_PROJECT",
            f"{resolved} is not inside the Godot project at {project}",
        ) from exc
    return "res://" + relative.as_posix()


def _binary_chunk(path: Path) -> bytes | None:
    from .glb_reader import _read_glb_container

    if Path(path).suffix.lower() != ".glb":
        return None
    _, binary = _read_glb_container(Path(path))
    return binary


def _repo_relative(path: Path) -> str:
    resolved = Path(path).resolve()
    repository = Path(__file__).resolve().parents[2]
    try:
        return resolved.relative_to(repository).as_posix()
    except ValueError:
        return resolved.as_posix()


__all__ = [
    "COORDINATE_SPACE_CONTRACT",
    "DEFAULT_CANDIDATE_ROOT",
    "EXPORT_SCHEMA",
    "BakeRun",
    "GodotNotAvailable",
    "StaticExportError",
    "bake_rest_pose",
    "build_provenance",
    "export_static_candidate",
    "surfaces_from_bake",
    "verify_static_reimport",
]
