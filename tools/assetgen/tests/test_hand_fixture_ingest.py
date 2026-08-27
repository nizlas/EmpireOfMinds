"""Tests for the Godot-side hand-fixture certification step (A2.10 / A2.11).

The Godot side of the compiler and the grip gates are covered by the Godot slice
tests. These tests cover the contract around that step: a fully accepted chain
is accepted without any human step, every other outcome is a named refusal, the
exit protocol is unambiguous (0 accepted / 2 classified / 1 infrastructure), and
a single reference rig is never reported as a certified production profile.
"""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

import pytest

from tools.assetgen.hand_fixture_ingest import (
    EXIT_ACCEPTED,
    EXIT_CLASSIFIED,
    EXIT_STEP_FAILED,
    INGEST_ACCEPTED,
    INGEST_CLASSIFIED,
    INGEST_STEP_FAILED,
    STAGE_BATCH_CERTIFICATION,
    STAGE_CALIBRATING,
    STAGE_PRODUCTION_CERTIFIED,
    GodotNotAvailable,
    certification_stage,
    certify_hand_fixture,
    resolve_godot_executable,
)

PROJECT = Path("game")
GLB = "res://assets/prototype/3d/units/generated_warrior/uthana_a1/import_sources/a1_uthana_target.glb"
OUT = "res://artifacts/fixtures/staging/uthana_a2_hand_fixture.tres"
CERTIFIED_OUT = "res://artifacts/fixtures/staging/uthana_a2_hand_fixture_certified.tres"
WEAPON = "res://assets/prototype/3d/equipment/wooden_club/wooden_club.glb"
POLICY = "power_grip_1h_v1"

ACCEPTED_CHAIN = [
    "import",
    "family_resolution",
    "humanoid_normalization",
    "fixture_compilation",
    "artifact_integrity",
    "rig_binding",
    "assemble_and_measure",
    "certification",
]

RIGHT_OK = {
    "right": {"compiled": True, "error_class": "", "nail_tris": 4, "pad_tris": 10},
    "left": {"compiled": False, "error_class": "PAD_PATCH_AMBIGUOUS"},
}


def _report(sides: dict, **overrides) -> str:
    payload = {
        "accepted": True,
        "chain": list(ACCEPTED_CHAIN),
        "compiler_pass": True,
        "artifact_path": OUT,
        "content_hash": "A" * 64,
        "source_geometry_sha256": "B" * 64,
        "source_rig_sha256": "C" * 64,
        "expected_source_geometry_sha256": "B" * 64,
        "expected_source_rig_sha256": "C" * 64,
        "certified": True,
        "certified_artifact_path": CERTIFIED_OUT,
        "certification_hash": "D" * 64,
        "acceptance_report_digest": "E" * 64,
        "family_id": "mixamo_52_humanoid",
        "family_version": "3",
        "import_representation": "godot_humanoid_retarget",
        "compiler_version": "hand_fixture_compiler_v3",
        "calibration_id": "hand_fixture_compiler_calibration_uthana_a2_7",
        "schema": "hand_fixture_evidence_v3",
        "grip_ground_truth": {"pass": True, "closest_patch": "pad"},
        "assembler": {"ok": True, "mesh_binding": {"verified": True}},
        "skeleton_bone_count": 52,
        "sides": sides,
    }
    payload.update(overrides)
    return "Godot Engine v4.6.2\nHAND_FIXTURE_INGEST " + json.dumps(payload) + "\n"


def _rejected(error_class: str, stage: str, **overrides) -> str:
    return _report(
        overrides.pop("sides", RIGHT_OK),
        accepted=False,
        certified=False,
        certification_hash=None,
        error_class=error_class,
        stage_failed=stage,
        failure_kind="classified_asset_failure",
        detail=f"{error_class} at {stage}",
        chain=ACCEPTED_CHAIN[: ACCEPTED_CHAIN.index(stage)] if stage in ACCEPTED_CHAIN else [],
        **overrides,
    )


def _runner(stdout: str, returncode: int):
    def run(argv, **kwargs):
        run.argv = argv
        return subprocess.CompletedProcess(argv, returncode, stdout=stdout, stderr="")

    return run


def _certify(runner, **kwargs):
    return certify_hand_fixture(
        project_path=PROJECT,
        rigged_glb_res_path=GLB,
        artifact_res_path=OUT,
        certified_artifact_res_path=CERTIFIED_OUT,
        policy_id=POLICY,
        weapon_res_path=WEAPON,
        godot_executable=str(Path(__file__)),  # any existing file stands in for Godot
        runner=runner,
        **kwargs,
    )


# ------------------------------------------------------------------ acceptance


def test_a_full_chain_is_accepted_without_a_human_step():
    result = _certify(_runner(_report(RIGHT_OK), EXIT_ACCEPTED))
    assert result.verdict == INGEST_ACCEPTED
    assert result.accepted
    assert result.process_exit_code == EXIT_ACCEPTED
    assert result.certified_sides == ("right",)
    assert result.compiler_version == "hand_fixture_compiler_v3"
    assert result.certified is True
    assert result.certification_hash == "D" * 64
    assert result.certified_artifact_path == CERTIFIED_OUT
    assert result.chain == tuple(ACCEPTED_CHAIN)
    assert result.grip_ground_truth["closest_patch"] == "pad"


def test_a_refused_side_is_reported_by_name_not_dropped():
    result = _certify(_runner(_report(RIGHT_OK), EXIT_ACCEPTED))
    assert result.classified_sides == {"left": "PAD_PATCH_AMBIGUOUS"}


def test_requiring_the_refused_side_fails_closed_with_its_error_class():
    result = _certify(
        _runner(_report(RIGHT_OK), EXIT_ACCEPTED), required_sides=("right", "left")
    )
    assert result.verdict == INGEST_CLASSIFIED
    assert result.process_exit_code == EXIT_CLASSIFIED
    assert "PAD_PATCH_AMBIGUOUS" in result.detail


def test_exit_zero_without_an_accepted_declaration_is_a_refusal():
    out = _report(RIGHT_OK, accepted=False)
    assert _certify(_runner(out, EXIT_ACCEPTED)).verdict == INGEST_STEP_FAILED


# --------------------------------------------------- compiler PASS != ACCEPTED


def test_a_compiler_pass_with_a_failed_grip_gate_is_rejected():
    out = _rejected("THUMB_SURFACE_TRUTH_GATE_FAILED", "assemble_and_measure")
    result = _certify(_runner(out, EXIT_CLASSIFIED))
    assert result.compiler_pass is True
    assert result.verdict == INGEST_CLASSIFIED
    assert result.error_class == "THUMB_SURFACE_TRUTH_GATE_FAILED"
    assert result.stage == "assemble_and_measure"
    assert result.process_exit_code == EXIT_CLASSIFIED
    assert not result.accepted


def test_a_compiler_pass_with_a_failed_bind_gate_is_rejected():
    out = _rejected("GRIP_PATCH_BIND_FAILED", "assemble_and_measure")
    result = _certify(_runner(out, EXIT_CLASSIFIED))
    assert result.verdict == INGEST_CLASSIFIED
    assert result.stage == "assemble_and_measure"


def test_a_rig_binding_failure_is_a_classified_rejection():
    out = _rejected("FIXTURE_RIG_HASH_MISMATCH", "rig_binding")
    result = _certify(_runner(out, EXIT_CLASSIFIED))
    assert result.verdict == INGEST_CLASSIFIED
    assert result.error_class == "FIXTURE_RIG_HASH_MISMATCH"


def test_unresolved_height_landmarks_are_not_a_degenerate_height():
    """The A2.12 blocker, at the contract level.

    A rig that spells its head bone differently must be rejected as
    "landmarks unresolved", never as "this humanoid has no height": the second
    class is a geometric claim and it was previously made falsely.
    """
    out = _rejected("HUMANOID_HEIGHT_LANDMARKS_UNRESOLVED", "humanoid_normalization")
    result = _certify(_runner(out, EXIT_CLASSIFIED))
    assert result.verdict == INGEST_CLASSIFIED
    assert result.error_class == "HUMANOID_HEIGHT_LANDMARKS_UNRESOLVED"
    assert result.stage == "humanoid_normalization"
    assert result.certified is False


def test_a_genuinely_degenerate_height_keeps_its_own_class():
    out = _rejected("DEGENERATE_HEIGHT", "humanoid_normalization")
    assert _certify(_runner(out, EXIT_CLASSIFIED)).error_class == "DEGENERATE_HEIGHT"


def test_acceptance_without_a_certificate_is_a_step_failure():
    """A compiler/chain PASS is not a runtime fixture.

    Exit 0 plus `accepted` used to be the whole contract. Now nothing
    runtime-loadable exists unless a certificate was minted, so a step that
    claims acceptance without one is a protocol violation and must not read as
    a success that something could be published from.
    """
    out = _report(RIGHT_OK, certified=False, certification_hash=None)
    result = _certify(_runner(out, EXIT_ACCEPTED))
    assert result.verdict == INGEST_STEP_FAILED
    assert "certified fixture" in result.detail
    assert not result.accepted


def test_a_fingerless_rig_is_a_named_domain_rejection_not_a_step_failure():
    out = _report(
        {},
        accepted=False,
        compiler_pass=False,
        error_class="HAND_SKELETON_INCOMPLETE",
        failure_kind="classified_asset_failure",
        detail="hand bone resolves but the finger chains do not",
        chain=["import"],
    )
    result = _certify(_runner(out, EXIT_CLASSIFIED))
    assert result.verdict == INGEST_CLASSIFIED
    assert result.error_class == "HAND_SKELETON_INCOMPLETE"
    assert result.process_exit_code == EXIT_CLASSIFIED
    assert result.certified_sides == ()


# ------------------------------------------------------- infrastructure errors


def test_step_failure_exit_code_is_infrastructure_not_a_classification():
    out = _report({}, accepted=False, error_class="INGEST_ARGS_MISSING", detail="bad invocation")
    result = _certify(_runner(out, EXIT_STEP_FAILED))
    assert result.verdict == INGEST_STEP_FAILED
    assert result.process_exit_code == EXIT_STEP_FAILED
    assert result.error_class == "INGEST_ARGS_MISSING"


def test_an_unknown_exit_code_is_infrastructure():
    assert _certify(_runner(_report(RIGHT_OK), 7)).verdict == INGEST_STEP_FAILED


def test_missing_report_is_a_refusal_even_on_exit_zero():
    result = _certify(_runner("Godot Engine v4.6.2\nnothing machine readable\n", EXIT_ACCEPTED))
    assert result.verdict == INGEST_STEP_FAILED
    assert result.error_class == "INGEST_REPORT_MISSING"


def test_unparseable_report_is_a_refusal():
    result = _certify(_runner("HAND_FIXTURE_INGEST {not json\n", EXIT_ACCEPTED))
    assert result.verdict == INGEST_STEP_FAILED
    assert result.error_class == "INGEST_REPORT_MISSING"


def test_a_hung_step_is_a_refusal_not_a_pass():
    def run(argv, **kwargs):
        raise subprocess.TimeoutExpired(argv, kwargs.get("timeout", 1))

    result = _certify(run)
    assert result.verdict == INGEST_STEP_FAILED
    assert result.error_class == "INGEST_TIMEOUT"
    assert "hung" in result.detail


def test_unstartable_step_is_a_refusal():
    def run(argv, **kwargs):
        raise OSError("no exec")

    result = _certify(run)
    assert result.verdict == INGEST_STEP_FAILED
    assert result.error_class == "INGEST_GODOT_START_FAILED"


# ------------------------------------------------------------------- invocation


def test_the_step_is_fully_automatic_and_names_no_editor_interaction():
    runner = _runner(_report(RIGHT_OK), EXIT_ACCEPTED)
    _certify(runner)
    argv = runner.argv
    assert "--headless" in argv
    assert "-s" in argv
    for prefix in (
        "--glb=", "--out=", "--certified-out=", "--policy=", "--weapon=",
        "--sides=", "--required=",
    ):
        assert any(a.startswith(prefix) for a in argv), prefix
    # No editor, no scene run, and Blender is not a dependency.
    assert "--editor" not in argv and "-e" not in argv
    assert not any("blender" in a.lower() for a in argv)


def test_required_sides_are_always_compiled():
    runner = _runner(_report(RIGHT_OK), EXIT_ACCEPTED)
    _certify(runner, required_sides=("left",), compile_sides=("right",))
    sides = next(a for a in runner.argv if a.startswith("--sides="))
    assert "left" in sides and "right" in sides
    assert "--required=left" in runner.argv


def test_family_may_be_pinned_but_is_not_required():
    runner = _runner(_report(RIGHT_OK), EXIT_ACCEPTED)
    _certify(runner)
    assert not any(a.startswith("--family=") for a in runner.argv)
    runner2 = _runner(_report(RIGHT_OK), EXIT_ACCEPTED)
    _certify(runner2, family_id="mixamo_52_humanoid")
    assert "--family=mixamo_52_humanoid" in runner2.argv


def test_missing_godot_is_an_explicit_error(monkeypatch):
    # Resolution must fail because nothing was found, not because this machine
    # happens to have no Godot: the ambient environment is removed first.
    monkeypatch.delenv("GODOT_EXE", raising=False)
    monkeypatch.setenv("PATH", "")
    with pytest.raises(GodotNotAvailable):
        resolve_godot_executable("C:/definitely/not/here/godot.exe")


def test_one_reference_rig_is_calibrating_not_certified():
    assert certification_stage(units_certified=1, batch_runs_green=0) == STAGE_CALIBRATING
    assert certification_stage(units_certified=1, batch_runs_green=5) == STAGE_CALIBRATING
    assert (
        certification_stage(units_certified=4, batch_runs_green=1)
        == STAGE_BATCH_CERTIFICATION
    )
    assert (
        certification_stage(units_certified=9, batch_runs_green=3)
        == STAGE_PRODUCTION_CERTIFIED
    )
