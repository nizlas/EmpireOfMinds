"""The offline static-unrigged export, and the defects its validators must catch.

The interesting risk here is not a crash. It is an export that LOOKS right: a
file that re-imports into Godot, renders, has the same triangle count and the
same bounding box, and is nonetheless the wrong pose, mirrored, inside-out,
double-transformed or missing its texture. Every geometric claim the exporter
makes therefore has a sabotage below that breaks exactly that claim and must be
refused, and the claims are compared against a specification-level evaluation of
the source rather than against the bake that produced them.

No test here reaches a provider, reads a credential, opens a socket or starts
Godot: the engine is replaced by `FakeBakeProcess`, which emits what the real
adapter emits. What the double cannot prove is stated in its own docstring.
"""

from __future__ import annotations

import hashlib
import json
import subprocess
from pathlib import Path

import numpy as np
import pytest

from tools.assetgen import static_export_validation as validation
from tools.assetgen.artifact_paths import UnsafeOutputPath, write_bytes_within
from tools.assetgen.command_risk import COMMAND_RISK, OperationClass
from tools.assetgen.glb_reader import load_glb
from tools.assetgen.glb_writer import GlbWriteError, write_static_glb
from tools.assetgen.static_export import (
    COORDINATE_SPACE_CONTRACT,
    DETERMINISM_CONTEXTS,
    StaticExportError,
    bake_rest_pose,
    export_static_candidate,
    prove_context_independence,
    surfaces_from_bake,
)
from tools.assetgen.tests import static_bake_double as double

ROOT_ROTATION = 25.0

#: Any existing file stands in for the engine binary: the double never runs it.
GODOT_STAND_IN = str(Path(__file__))


# --------------------------------------------------------------- utilities


def _source(tmp_path: Path, **kwargs) -> Path:
    return double.write_rigged_glb(
        tmp_path / "game" / "assets" / "unit.glb", root_rotation_deg=ROOT_ROTATION, **kwargs
    )


def _binary_chunk(path: Path) -> bytes:
    from tools.assetgen.glb_reader import _read_glb_container

    _, binary = _read_glb_container(Path(path))
    return binary or b""


class _Exported:
    """One run of the whole Python pipeline, with hooks for each sabotage."""

    def __init__(
        self,
        tmp_path: Path,
        source: Path,
        *,
        distort=None,
        mutate_surfaces=None,
        patch_output=None,
        report_patch=None,
    ):
        self.source = source
        self.document = load_glb(source)
        self.process = double.FakeBakeProcess(
            source, distort=distort, report_patch=report_patch
        )
        self.run = bake_rest_pose(
            project_path=tmp_path / "game",
            scene_res_path="res://assets/unit.glb",
            report_path=tmp_path / "work" / "bake_report.json",
            arrays_path=tmp_path / "work" / "bake_arrays.bin",
            godot_executable=GODOT_STAND_IN,
            runner=self.process,
        )
        self.surfaces, self.correspondence = surfaces_from_bake(self.run, self.document)
        if mutate_surfaces is not None:
            self.surfaces = mutate_surfaces(self.surfaces)
        self.payload = write_static_glb(
            surfaces=self.surfaces,
            source_gltf=self.document.gltf,
            source_binary=_binary_chunk(source),
            mesh_name="unit_static",
            node_name="unit_static",
        )
        self.path = tmp_path / "out" / "unit_static.glb"
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.path.write_bytes(self.payload)
        if patch_output is not None:
            double.patch_glb_json(self.path, patch_output)
        self.output = load_glb(self.path)

    @property
    def structural(self) -> dict:
        return validation.assert_unrigged(self.output)

    @property
    def geometry(self) -> dict:
        return validation.compare_rest_pose_to_output(
            baked_surfaces=self.surfaces,
            baked_measurement=self.run.report.get("measurement") or {},
            output=self.output,
            source=self.document,
        )


def _failed(verdict: dict) -> list[str]:
    return list(verdict["failed_checks"]) + list(verdict["unverifiable_checks"])


# ------------------------------------------------------------ 1. inspection


def test_the_source_fixture_is_a_rigged_animated_humanoid_shaped_asset(tmp_path):
    document = load_glb(_source(tmp_path))
    assert len(document.skins) == 1
    assert document.animation_names() == ["idle"]
    assert len(document.joint_node_indices()) == 2
    assert document.triangle_count == 12
    assert document.vertex_count == 24
    assert len(document.images) == 1


def test_inspection_reports_the_rig_before_anything_is_removed(tmp_path):
    exported = _Exported(tmp_path, _source(tmp_path))
    inspection = exported.run.report["inspection"]
    assert inspection["skeletons"], "a rigged source must report its skeleton"
    assert inspection["animation_players"][0]["animations"] == ["idle"]
    assert exported.run.report["post_bake_inspection_matches"] is True


# --------------------------------------------------------- 2. happy path


def test_a_clean_export_passes_every_structural_and_geometric_check(tmp_path):
    exported = _Exported(tmp_path, _source(tmp_path))
    assert _failed(exported.structural) == []
    assert _failed(exported.geometry) == []


def test_the_output_carries_no_rig_or_animation_data(tmp_path):
    exported = _Exported(tmp_path, _source(tmp_path))
    gltf = exported.output.gltf
    assert "skins" not in gltf and "animations" not in gltf
    assert not any("skin" in node for node in gltf["nodes"])
    attributes = {
        name
        for mesh in gltf["meshes"]
        for primitive in mesh["primitives"]
        for name in primitive["attributes"]
    }
    assert not {a for a in attributes if a.startswith(("JOINTS_", "WEIGHTS_"))}
    assert attributes == {"POSITION", "NORMAL", "TEXCOORD_0"}


def test_materials_and_texture_bytes_are_carried_verbatim(tmp_path):
    exported = _Exported(tmp_path, _source(tmp_path))
    gltf = exported.output.gltf
    assert [m["name"] for m in gltf["materials"]] == ["skin_material"]
    assert len(gltf["images"]) == 1
    digest = hashlib.sha256(double.PNG_BYTES).hexdigest()
    assert validation._image_digests(exported.output) == [digest]
    assert "uri" not in gltf["images"][0], "the texture must stay inside the container"


def test_the_output_is_self_contained_with_no_external_uri(tmp_path):
    exported = _Exported(tmp_path, _source(tmp_path))
    for collection in ("buffers", "images"):
        for entry in exported.output.gltf.get(collection, []):
            assert "uri" not in entry


def test_the_bake_is_the_rest_pose_not_the_mesh_as_authored(tmp_path):
    """The fixture's rest pose really does move the mesh.

    Without this, every "rest pose preserved" claim below could be satisfied by
    an exporter that ignored the skeleton entirely.
    """
    source = _source(tmp_path)
    exported = _Exported(tmp_path, source)
    authored = load_glb(source).primitives[0].positions
    baked = exported.surfaces[0].positions
    assert np.abs(authored - baked).max() > 0.01


def test_an_unrigged_source_is_exported_without_inventing_a_rig(tmp_path):
    exported = _Exported(tmp_path, _source(tmp_path, with_skin=False, with_animation=False))
    assert _failed(exported.structural) == []
    assert _failed(exported.geometry) == []
    assert exported.run.report["surfaces"][0]["was_skinned"] is False


def test_multiple_visible_meshes_become_multiple_surfaces_each_with_its_material(tmp_path):
    exported = _Exported(tmp_path, _source(tmp_path, second_mesh=True))
    assert len(exported.surfaces) == 2
    assert [m["name"] for m in exported.output.gltf["materials"]] == [
        "skin_material",
        "equipment_material",
    ]
    assert _failed(exported.geometry) == []


# ------------------------------------------------- 3. convention boundary


def test_the_written_winding_is_gltf_not_the_engines(tmp_path):
    """The defect that renders correctly in Godot and inside-out everywhere else."""
    exported = _Exported(tmp_path, _source(tmp_path))
    engine_indices = np.frombuffer(
        exported.run.arrays,
        dtype="<u4",
        offset=exported.run.report["arrays"][0]["sections"]["indices"]["offset"],
        count=exported.run.report["arrays"][0]["index_count"],
    )
    written = exported.output.primitives[0].triangles.ravel()
    assert not np.array_equal(engine_indices, written)
    assert np.array_equal(engine_indices.reshape(-1, 3)[:, ::-1].reshape(-1), written)


def test_an_unconverted_engine_winding_is_refused(tmp_path):
    exported = _Exported(
        tmp_path, _source(tmp_path), distort=double.engine_winding_not_converted
    )
    assert "triangle_winding_and_handedness_preserved" in _failed(exported.geometry)


def test_uvs_are_neither_recomputed_nor_v_flipped(tmp_path):
    exported = _Exported(tmp_path, _source(tmp_path))
    check = next(c for c in exported.geometry["checks"] if c["name"] == "uv_set_identical")
    assert check["verdict"] == validation.CHECK_PASS
    assert check["measured"]["exact"] is True


# ----------------------------------------------------- 4. sabotage matrix


@pytest.mark.parametrize(
    ("name", "distort", "expected_check"),
    [
        ("active_animation_frame", double.animation_frame, "vertex_sets_agree_with_the_independent_evaluation"),
        ("doubled_node_transform", double.doubled_transform(ROOT_ROTATION), "vertex_sets_agree_with_the_independent_evaluation"),
        ("altered_scale", double.scaled(1.02), "vertex_sets_agree_with_the_independent_evaluation"),
        ("changed_yaw", double.yawed(5.0), "vertex_sets_agree_with_the_independent_evaluation"),
        ("reflected_handedness", double.reflected, "triangle_winding_and_handedness_preserved"),
        ("inverted_normals", double.inverted_normals, "normals_agree_with_their_own_winding"),
        ("missing_uv", double.without_uv, "uv_set_identical"),
        ("helper_geometry_included", double.with_helper_geometry, "identical_triangle_count"),
    ],
)
def test_a_sabotaged_bake_is_refused(tmp_path, name, distort, expected_check):
    exported = _Exported(tmp_path, _source(tmp_path), distort=distort)
    failed = _failed(exported.geometry)
    assert not exported.geometry["passed"], f"{name} was accepted"
    assert expected_check in failed, f"{name} failed {failed}, expected {expected_check}"


def test_a_dropped_surface_is_refused(tmp_path):
    exported = _Exported(
        tmp_path, _source(tmp_path, second_mesh=True), distort=double.drop_last_surface
    )
    failed = _failed(exported.geometry)
    assert "identical_surface_count" in failed
    assert "identical_triangle_count" in failed


def test_a_lost_material_is_refused(tmp_path):
    def forget_material(surfaces):
        return [
            type(surfaces[0])(**{**surfaces[0].__dict__, "source_material_index": None})
        ]

    exported = _Exported(tmp_path, _source(tmp_path), mutate_surfaces=forget_material)
    assert "material_slots_agree" in _failed(exported.geometry)


def test_a_lost_texture_is_refused(tmp_path):
    exported = _Exported(
        tmp_path,
        _source(tmp_path),
        patch_output=lambda gltf: gltf.pop("images", None),
    )
    assert "embedded_texture_bytes_identical" in _failed(exported.geometry)


def test_residual_skin_data_in_the_file_is_refused(tmp_path):
    """A renamed or hidden rig is not an unrigged export."""

    def smuggle_rig(gltf):
        gltf["skins"] = [{"name": "not_a_skeleton_honestly", "joints": [0]}]
        gltf["nodes"][0]["skin"] = 0

    exported = _Exported(tmp_path, _source(tmp_path), patch_output=smuggle_rig)
    failed = _failed(exported.structural)
    assert "no_skins" in failed
    assert "no_node_references_a_skin" in failed


def test_residual_joint_attributes_are_refused(tmp_path):
    def smuggle_attributes(gltf):
        primitive = gltf["meshes"][0]["primitives"][0]
        primitive["attributes"]["JOINTS_0"] = 0
        primitive["attributes"]["WEIGHTS_0"] = 0

    exported = _Exported(tmp_path, _source(tmp_path), patch_output=smuggle_attributes)
    assert "no_joint_or_weight_attributes" in _failed(exported.structural)


def test_a_residual_animation_is_refused(tmp_path):
    exported = _Exported(
        tmp_path,
        _source(tmp_path),
        patch_output=lambda gltf: gltf.update({"animations": [{"name": "idle"}]}),
    )
    assert "no_animations" in _failed(exported.structural)


def test_an_external_texture_reference_is_refused(tmp_path):
    def externalise(gltf):
        gltf["images"][0].pop("bufferView", None)
        gltf["images"][0]["uri"] = "textures/skin.png"

    exported = _Exported(tmp_path, _source(tmp_path), patch_output=externalise)
    assert "self_contained" in _failed(exported.structural)


def test_a_node_transform_left_in_the_output_is_refused(tmp_path):
    """The bake is baked once. A transform on the output node would apply it twice."""
    exported = _Exported(
        tmp_path,
        _source(tmp_path),
        patch_output=lambda gltf: gltf["nodes"][0].update({"scale": [2.0, 2.0, 2.0]}),
    )
    assert "output_nodes_carry_no_transform" in _failed(exported.structural)


def test_out_of_bounds_accessors_are_refused(tmp_path):
    exported = _Exported(
        tmp_path,
        _source(tmp_path),
        patch_output=lambda gltf: gltf["bufferViews"][0].update({"byteLength": 10**9}),
    )
    assert "accessor_and_buffer_bounds_valid" in _failed(exported.structural)


# ------------------------------------------------- 5. refusals and inputs


def test_a_missing_source_is_a_named_refusal(tmp_path):
    with pytest.raises(StaticExportError) as caught:
        export_static_candidate(
            source_glb=tmp_path / "game" / "nothing.glb",
            project_path=tmp_path / "game",
            candidate_root=tmp_path / "candidates",
            workspace=tmp_path / "work",
            godot_executable=GODOT_STAND_IN,
            verify_reimport=False,
            runner=double.FakeBakeProcess(tmp_path / "game" / "nothing.glb"),
        )
    assert caught.value.code == "STATIC_EXPORT_SOURCE_MISSING"


def test_a_malformed_glb_is_a_named_refusal_not_a_traceback(tmp_path):
    broken = tmp_path / "game" / "broken.glb"
    broken.parent.mkdir(parents=True, exist_ok=True)
    broken.write_bytes(b"glTF" + b"\x00" * 40)
    with pytest.raises(StaticExportError) as caught:
        export_static_candidate(
            source_glb=broken,
            project_path=tmp_path / "game",
            candidate_root=tmp_path / "candidates",
            workspace=tmp_path / "work",
            godot_executable=GODOT_STAND_IN,
            verify_reimport=False,
            runner=double.FakeBakeProcess(broken),
        )
    assert caught.value.code == "STATIC_EXPORT_SOURCE_UNPARSABLE"


def test_a_source_outside_the_godot_project_is_refused(tmp_path):
    outside = double.write_rigged_glb(tmp_path / "elsewhere" / "unit.glb")
    (tmp_path / "game").mkdir(parents=True, exist_ok=True)
    with pytest.raises(StaticExportError) as caught:
        export_static_candidate(
            source_glb=outside,
            project_path=tmp_path / "game",
            candidate_root=tmp_path / "candidates",
            workspace=tmp_path / "work",
            godot_executable=GODOT_STAND_IN,
            verify_reimport=False,
            runner=double.FakeBakeProcess(outside),
        )
    assert caught.value.code == "STATIC_EXPORT_SOURCE_OUTSIDE_PROJECT"


def test_a_refusing_bake_is_reported_by_its_own_error_class(tmp_path):
    source = _source(tmp_path)

    def refuse(report):
        report["ok"] = False
        report["error_class"] = "BAKE_NO_VISIBLE_GEOMETRY"
        report["detail"] = "every mesh instance is hidden"

    with pytest.raises(StaticExportError) as caught:
        _Exported(tmp_path, source, report_patch=refuse)
    assert caught.value.code == "BAKE_NO_VISIBLE_GEOMETRY"


def test_a_bake_whose_arrays_do_not_match_its_digest_is_refused(tmp_path):
    source = _source(tmp_path)
    with pytest.raises(StaticExportError) as caught:
        _Exported(
            tmp_path,
            source,
            report_patch=lambda report: report.update({"arrays_sha256": "0" * 64}),
        )
    assert caught.value.code == "STATIC_EXPORT_ARRAYS_CORRUPT"


def test_a_hung_bake_is_a_refusal_not_a_pass(tmp_path):
    def hang(argv, **kwargs):
        raise subprocess.TimeoutExpired(argv, kwargs.get("timeout", 1))

    with pytest.raises(StaticExportError) as caught:
        bake_rest_pose(
            project_path=tmp_path / "game",
            scene_res_path="res://assets/unit.glb",
            report_path=tmp_path / "r.json",
            arrays_path=tmp_path / "a.bin",
            godot_executable=GODOT_STAND_IN,
            runner=hang,
        )
    assert caught.value.code == "STATIC_EXPORT_BAKE_TIMEOUT"


def test_a_surface_with_no_geometry_cannot_be_written(tmp_path):
    with pytest.raises(GlbWriteError):
        write_static_glb(
            surfaces=[],
            source_gltf={"asset": {"version": "2.0"}},
            source_binary=b"",
            mesh_name="empty",
            node_name="empty",
        )


# ----------------------------------------------- 6. output-path confinement


def test_the_candidate_is_written_only_inside_the_candidate_root(tmp_path):
    source = double.write_rigged_glb(tmp_path / "game" / "assets" / "unit.glb")
    provenance = export_static_candidate(
        source_glb=source,
        project_path=tmp_path / "game",
        candidate_root=tmp_path / "candidates",
        workspace=tmp_path / "work",
        godot_executable=GODOT_STAND_IN,
        verify_reimport=False,
        runner=double.FakeBakeProcess(source),
    )
    written = sorted(p.name for p in (tmp_path / "candidates").iterdir())
    assert written == [
        "unit__static_unrigged.glb",
        "unit__static_unrigged.provenance.json",
    ]
    assert provenance["output"]["path"].endswith("unit__static_unrigged.glb")
    assert provenance["candidate_classification"]["certified"] is False
    assert provenance["candidate_classification"][
        "production_representative_batch_evidence"
    ] is False


@pytest.mark.parametrize(
    "name", ["../escape.glb", "sub/dir.glb", "C:/absolute.glb", "..\\escape.glb", "con.glb"]
)
def test_a_traversing_output_name_is_refused(tmp_path, name):
    with pytest.raises(UnsafeOutputPath):
        write_bytes_within(tmp_path / "candidates", name, b"payload")


def test_the_provenance_makes_no_certification_claim(tmp_path):
    source = double.write_rigged_glb(tmp_path / "game" / "assets" / "unit.glb")
    provenance = export_static_candidate(
        source_glb=source,
        project_path=tmp_path / "game",
        candidate_root=tmp_path / "candidates",
        workspace=tmp_path / "work",
        godot_executable=GODOT_STAND_IN,
        verify_reimport=False,
        runner=double.FakeBakeProcess(source),
    )
    text = json.dumps(provenance).lower()
    assert "not a hand-fixture certification" in text
    assert provenance["removed"]["skins"] == 1
    assert provenance["removed"]["animations"] == 1
    assert provenance["retained"]["texture_bytes_copied_verbatim"] is True
    assert any("human confirmation" in limit for limit in provenance["known_limitations"])


# ------------------------------------------------------------- 7. determinism


def test_the_same_source_produces_byte_identical_output_every_time(tmp_path):
    source = _source(tmp_path)
    digests = {
        hashlib.sha256(_Exported(tmp_path, source).payload).hexdigest() for _ in range(3)
    }
    assert len(digests) == 1


def test_the_export_does_not_depend_on_caller_context(tmp_path):
    source = _source(tmp_path)
    proof = prove_context_independence(
        source_glb=source,
        project_path=tmp_path / "game",
        workspace=tmp_path / "determinism",
        godot_executable=GODOT_STAND_IN,
        runner=double.FakeBakeProcess(source),
    )
    assert proof["byte_identical"] is True
    assert proof["max_positional_deviation"] == 0.0
    assert proof["process_count"] == len(DETERMINISM_CONTEXTS)
    assert proof["scene_state_restored_every_run"] is True


def test_the_determinism_matrix_covers_placement_scale_and_an_active_animation():
    names = {context["name"] for context in DETERMINISM_CONTEXTS}
    assert {"identity", "identity_repeat", "animation_playing"} <= names
    assert any("translated" in name for name in names)
    assert any("non_uniform" in name for name in names)
    assert any(context.get("play_animation") for context in DETERMINISM_CONTEXTS)


def test_a_context_dependent_bake_fails_the_determinism_proof(tmp_path):
    """The proof must be capable of failing, or it proves nothing."""
    source = _source(tmp_path)
    state = {"calls": 0}

    def drift(surfaces):
        state["calls"] += 1
        if state["calls"] <= 1:
            return surfaces
        return double.scaled(1.001)(surfaces)

    proof = prove_context_independence(
        source_glb=source,
        project_path=tmp_path / "game",
        workspace=tmp_path / "determinism",
        godot_executable=GODOT_STAND_IN,
        runner=double.FakeBakeProcess(source, distort=drift),
    )
    assert proof["byte_identical"] is False
    assert proof["max_positional_deviation"] > 0.0


def test_each_determinism_run_is_its_own_process(tmp_path):
    source = _source(tmp_path)
    process = double.FakeBakeProcess(source)
    prove_context_independence(
        source_glb=source,
        project_path=tmp_path / "game",
        workspace=tmp_path / "determinism",
        godot_executable=GODOT_STAND_IN,
        runner=process,
    )
    assert len(process.calls) == len(DETERMINISM_CONTEXTS)
    for argv in process.calls:
        assert "--headless" in argv


# -------------------------------------------- 8. tolerances and honesty


def test_tolerances_are_derived_from_the_float32_representation(tmp_path):
    exported = _Exported(tmp_path, _source(tmp_path))
    tolerances = exported.geometry["tolerances"]
    assert tolerances["float32_relative_step"] == 2.0**-23
    assert tolerances["serialisation"].startswith("exact")
    assert "not a value chosen from observed error" in tolerances["derivation"]


def test_a_single_float_step_between_the_bake_and_the_file_is_refused(tmp_path):
    """Serialisation is exact or it is a defect.

    float32 goes in and float32 comes out, so there is no representable reason
    for the file to differ from the arrays that were evaluated. One mantissa step
    is the smallest possible difference, and it must still fail: a tolerance here
    would let a re-quantising or re-encoding writer through.
    """
    exported = _Exported(tmp_path, _source(tmp_path))
    before = _failed(exported.geometry)
    assert "written_file_matches_the_evaluated_arrays_exactly" not in before

    def nudge_first_position(gltf, payload):
        view = gltf["bufferViews"][gltf["accessors"][0]["bufferView"]]
        offset = int(view.get("byteOffset", 0))
        value = np.frombuffer(bytes(payload[offset : offset + 4]), dtype="<f4")[0]
        stepped = np.nextafter(value, np.float32(1e9)).astype("<f4")
        payload[offset : offset + 4] = stepped.tobytes()

    double.patch_glb_binary(exported.path, nudge_first_position)
    exported.output = load_glb(exported.path)
    assert "written_file_matches_the_evaluated_arrays_exactly" in _failed(exported.geometry)


def test_vertex_correspondence_is_not_claimed_from_counts_alone(tmp_path):
    exported = _Exported(tmp_path, _source(tmp_path))
    assert exported.correspondence["kind"] == "counts_only"
    assert "geometrically" in exported.correspondence["note"]


def test_tangents_are_not_fabricated_when_the_source_declares_none(tmp_path):
    exported = _Exported(tmp_path, _source(tmp_path))
    check = next(
        c for c in exported.geometry["checks"] if c["name"] == "tangents_not_fabricated"
    )
    assert check["verdict"] == validation.CHECK_PASS
    assert check["measured"]["output_contains"] is False


def test_the_coordinate_contract_promises_no_normalisation(tmp_path):
    assert "no height or unit normalisation" in COORDINATE_SPACE_CONTRACT["scale"]
    assert "no yaw is introduced" in COORDINATE_SPACE_CONTRACT["front_axis"]
    assert COORDINATE_SPACE_CONTRACT["up_axis"] == "+Y"


# ------------------------------- 9. the plan a candidate could feed, unexecuted


def _candidate_with_provenance(tmp_path: Path) -> Path:
    source = double.write_rigged_glb(tmp_path / "game" / "assets" / "unit.glb")
    export_static_candidate(
        source_glb=source,
        project_path=tmp_path / "game",
        candidate_root=tmp_path / "candidates",
        workspace=tmp_path / "work",
        godot_executable=GODOT_STAND_IN,
        verify_reimport=False,
        runner=double.FakeBakeProcess(source),
    )
    return tmp_path / "candidates" / "unit__static_unrigged.glb"


def test_a_plan_binds_the_candidate_classification_from_its_provenance(tmp_path):
    from tools.assetgen.provider_plan import DIGESTED_KEYS, build_autorig_plan

    plan = build_autorig_plan(
        repo_root=tmp_path, input_path=_candidate_with_provenance(tmp_path)
    )
    classification = plan["input_classification"]
    assert classification["role"] == "possible morphological calibration probe"
    assert classification["certified"] is False
    assert classification["production_representative_batch_evidence"] is False
    assert classification["derived_from"]["path"].endswith("unit.glb")
    assert "input_classification" in DIGESTED_KEYS, "an approval must bind what it approves"


def test_unresolved_human_confirmations_keep_the_plan_non_executable(tmp_path):
    from tools.assetgen.provider_plan import build_autorig_plan

    plan = build_autorig_plan(
        repo_root=tmp_path, input_path=_candidate_with_provenance(tmp_path)
    )
    assert plan["executable"] is False
    assert plan["input"]["sha256"] == hashlib.sha256(
        _candidate_with_provenance(tmp_path).read_bytes()
    ).hexdigest()
    assert plan["operation_parameters"]["include_fingers"] is True
    assert plan["limits"] == {
        "max_submissions": 1,
        "max_poll_attempts": 60,
        "max_download_attempts": 3,
        "create_retries_allowed": 0,
    }
    assert plan["cost"]["known"] is False


def test_a_classification_is_never_inherited_from_a_stale_provenance(tmp_path):
    """The record must describe THIS file, matched by digest rather than by name."""
    from tools.assetgen.provider_plan import build_autorig_plan

    candidate = _candidate_with_provenance(tmp_path)
    candidate.write_bytes(candidate.read_bytes() + b"\x00")
    plan = build_autorig_plan(repo_root=tmp_path, input_path=candidate)
    assert plan["input_classification"]["role"] == "unclassified_local_asset"


def test_an_asset_without_provenance_is_not_classified_as_production(tmp_path):
    from tools.assetgen.provider_plan import build_autorig_plan

    plain = double.write_rigged_glb(tmp_path / "game" / "assets" / "plain.glb")
    plan = build_autorig_plan(repo_root=tmp_path, input_path=plain)
    assert plan["input_classification"]["role"] == "unclassified_local_asset"
    assert plan["input_classification"]["production_representative_batch_evidence"] is False


def test_changing_the_classification_changes_the_digest(tmp_path):
    """Otherwise an approval for a probe would also authorise a production run."""
    from tools.assetgen.provider_plan import plan_digest

    plan = {
        "schema": "provider_plan_v2",
        "input_classification": {"role": "possible morphological calibration probe"},
    }
    other = {**plan, "input_classification": {"role": "production_asset"}}
    assert plan_digest(plan) != plan_digest(other)


# ------------------------------------------- 10. offline by construction


def test_the_operation_is_classified_offline():
    assert COMMAND_RISK["static-export"] is OperationClass.OFFLINE


def test_the_export_reads_no_credential_and_opens_no_socket(tmp_path, monkeypatch):
    """The socket tripwire in `conftest` covers the network; this covers the
    environment. A credential read would be a bug, not a policy question."""
    seen: list[str] = []
    import os

    original = os.environ.get

    def watched(key, default=None):
        seen.append(key)
        return original(key, default)

    monkeypatch.setattr(os.environ, "get", watched)
    source = double.write_rigged_glb(tmp_path / "game" / "assets" / "unit.glb")
    export_static_candidate(
        source_glb=source,
        project_path=tmp_path / "game",
        candidate_root=tmp_path / "candidates",
        workspace=tmp_path / "work",
        godot_executable=GODOT_STAND_IN,
        verify_reimport=False,
        runner=double.FakeBakeProcess(source),
    )
    assert not [
        key
        for key in seen
        if "KEY" in key.upper() or "TOKEN" in key.upper() or "SECRET" in key.upper()
    ]


def test_the_bake_invocation_names_no_editor_and_no_blender(tmp_path):
    source = _source(tmp_path)
    exported = _Exported(tmp_path, source)
    argv = exported.process.calls[0]
    assert "--headless" in argv
    assert "--editor" not in argv and "-e" not in argv
    assert not any("blender" in str(a).lower() for a in argv)
    assert not any("http" in str(a).lower() for a in argv)
