"""Tests for the canonical rigged-humanoid ingestion owner (A2.11).

These cover what the ingestion entry point owns beyond the single Godot step:
the exit protocol, that the pipeline establishes the import representation
itself, that publishing is gated on full acceptance rather than on compiler
success, and that reruns are idempotent.
"""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

from tools.assetgen.hand_fixture_ingest import (
    EXIT_ACCEPTED,
    EXIT_CLASSIFIED,
    EXIT_STEP_FAILED,
    INGEST_ACCEPTED,
    INGEST_CLASSIFIED,
    INGEST_STEP_FAILED,
)
from tools.assetgen.rig_ingest import (
    STAGING_DIR_RES,
    ingest_rigged_humanoid,
)

GLB = "res://assets/prototype/3d/units/generated_warrior/uthana_a1/import_sources/a1_uthana_target.glb"
PUBLISHED = "res://assets/prototype/3d/units/generated_warrior/uthana_a2/uthana_a2_hand_fixture.tres"
ASSET_ID = "uthana_a2_7"

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


def _report(**overrides) -> str:
    payload = {
        "accepted": True,
        "chain": list(ACCEPTED_CHAIN),
        "compiler_pass": True,
        "content_hash": "A" * 64,
        "certified": True,
        "certification_hash": "D" * 64,
        "source_geometry_sha256": "B" * 64,
        "source_rig_sha256": "C" * 64,
        "family_id": "mixamo_52_humanoid",
        "family_version": "3",
        "compiler_version": "hand_fixture_compiler_v3",
        "sides": {
            "right": {"compiled": True, "nail_tris": 4, "pad_tris": 10},
            "left": {"compiled": False, "error_class": "PAD_PATCH_AMBIGUOUS"},
        },
    }
    payload.update(overrides)
    return "HAND_FIXTURE_INGEST " + json.dumps(payload) + "\n"


class FakeGodot:
    """Stands in for both Godot invocations: `--import` and the certify step.

    The certify step writes the staged evidence and — only for an accepted
    chain — the staged CERTIFICATE, because publishing must be driven by files
    the step actually produced, and only the certificate may be published.
    """

    def __init__(self, project: Path, stdout: str, returncode: int, *, import_code: int = 0):
        self.project = project
        self.stdout = stdout
        self.returncode = returncode
        self.import_code = import_code
        self.calls: list[list[str]] = []

    def __call__(self, argv, **kwargs):
        self.calls.append(list(argv))
        if "--import" in argv:
            return subprocess.CompletedProcess(argv, self.import_code, stdout="", stderr="")
        self._write("--out=", "[gd_resource] evidence\n", always=True)
        self._write("--certified-out=", self.certified_bytes, always=False)
        return subprocess.CompletedProcess(argv, self.returncode, stdout=self.stdout, stderr="")

    #: What an accepted run leaves in staging as the certificate.
    certified_bytes = "[gd_resource] certificate\n"

    def _write(self, prefix: str, text: str, *, always: bool) -> None:
        argv = self.calls[-1]
        match = next((a for a in argv if a.startswith(prefix)), None)
        if match is None:
            return
        if not always and self.returncode != EXIT_ACCEPTED:
            return
        staged = self.project / match.removeprefix(prefix).removeprefix("res://")
        staged.parent.mkdir(parents=True, exist_ok=True)
        staged.write_text(text, encoding="utf-8")

    @property
    def certify_argv(self) -> list[str]:
        return next(c for c in self.calls if "--import" not in c)


def _ingest(tmp_path: Path, godot: FakeGodot, **kwargs):
    return ingest_rigged_humanoid(
        project_path=tmp_path,
        rigged_glb_res_path=GLB,
        asset_id=ASSET_ID,
        published_artifact_res_path=PUBLISHED,
        repo_root=tmp_path,
        godot_executable=str(Path(__file__)),
        runner=godot,
        **kwargs,
    )


def _accepted(tmp_path: Path) -> FakeGodot:
    return FakeGodot(tmp_path, _report(), EXIT_ACCEPTED)


# ------------------------------------------------------------- exit protocol


def test_a_full_acceptance_exits_zero_and_publishes(tmp_path):
    godot = _accepted(tmp_path)
    result = _ingest(tmp_path, godot)
    assert result.verdict == INGEST_ACCEPTED
    assert result.exit_code == EXIT_ACCEPTED
    assert result.published
    published = tmp_path / PUBLISHED.removeprefix("res://")
    assert published.is_file()
    # The CERTIFICATE is what got published, never the compiled evidence.
    assert published.read_text(encoding="utf-8") == godot.certified_bytes
    assert result.staged_certified_artifact.endswith("_certified.tres")


def test_a_classified_rejection_exits_two_and_never_publishes(tmp_path):
    out = _report(
        accepted=False,
        error_class="THUMB_SURFACE_TRUTH_GATE_FAILED",
        stage_failed="assemble_and_measure",
        detail="closest patch was nail",
    )
    result = _ingest(tmp_path, FakeGodot(tmp_path, out, EXIT_CLASSIFIED))
    assert result.verdict == INGEST_CLASSIFIED
    assert result.exit_code == EXIT_CLASSIFIED
    assert not result.published
    assert not (tmp_path / PUBLISHED.removeprefix("res://")).exists()


def test_an_infrastructure_error_exits_one(tmp_path):
    out = _report(accepted=False, error_class="INGEST_ASSET_MISSING", detail="no such scene")
    result = _ingest(tmp_path, FakeGodot(tmp_path, out, EXIT_STEP_FAILED))
    assert result.verdict == INGEST_STEP_FAILED
    assert result.exit_code == EXIT_STEP_FAILED
    assert not result.published


def test_a_fingerless_rig_is_a_named_domain_rejection_with_exit_two(tmp_path):
    out = _report(
        accepted=False,
        compiler_pass=False,
        error_class="HAND_SKELETON_INCOMPLETE",
        stage_failed="family_resolution",
        detail="RightHand resolved but no finger chain did",
        chain=["import"],
        sides={},
    )
    result = _ingest(tmp_path, FakeGodot(tmp_path, out, EXIT_CLASSIFIED))
    assert result.exit_code == EXIT_CLASSIFIED
    assert result.certification["error_class"] == "HAND_SKELETON_INCOMPLETE"
    assert not result.published


def test_a_failed_import_step_is_infrastructure_and_stops_the_chain(tmp_path):
    godot = FakeGodot(tmp_path, _report(), EXIT_ACCEPTED, import_code=1)
    result = _ingest(tmp_path, godot)
    assert result.exit_code == EXIT_STEP_FAILED
    assert result.certification == {}
    assert all("--import" in c for c in godot.calls)


# --------------------------------------------------- compiler PASS != ACCEPTED


def test_compiler_pass_with_a_failed_gate_does_not_publish(tmp_path):
    out = _report(
        accepted=False,
        compiler_pass=True,
        error_class="GRIP_PATCH_BIND_FAILED",
        stage_failed="assemble_and_measure",
    )
    result = _ingest(tmp_path, FakeGodot(tmp_path, out, EXIT_CLASSIFIED))
    assert result.certification["compiler_pass"] is True
    assert not result.accepted
    assert not result.published


def test_a_rejected_artifact_stays_in_staging_for_diagnostics(tmp_path):
    out = _report(accepted=False, error_class="PAD_PATCH_AMBIGUOUS", stage_failed="fixture_compilation")
    result = _ingest(tmp_path, FakeGodot(tmp_path, out, EXIT_CLASSIFIED))
    assert result.staged_artifact.startswith(STAGING_DIR_RES)
    assert result.published_artifact == PUBLISHED
    assert not result.published


# ----------------------------------------------------------- pipeline ownership


def test_the_pipeline_establishes_the_import_representation_itself(tmp_path):
    godot = _accepted(tmp_path)
    _ingest(tmp_path, godot)
    assert any("--import" in c for c in godot.calls)
    # And the import runs before certification, or the family could resolve
    # against a stale representation.
    assert "--import" in godot.calls[0]


def test_import_may_be_skipped_explicitly_only(tmp_path):
    godot = _accepted(tmp_path)
    result = _ingest(tmp_path, godot, skip_import=True)
    assert result.import_step == {"skipped": True}
    assert not any("--import" in c for c in godot.calls)


def test_certification_uses_a_staging_path_not_the_published_one(tmp_path):
    godot = _accepted(tmp_path)
    _ingest(tmp_path, godot)
    out = next(a for a in godot.certify_argv if a.startswith("--out="))
    assert STAGING_DIR_RES in out
    assert PUBLISHED not in out


def test_the_policy_and_certification_weapon_are_passed_explicitly(tmp_path):
    godot = _accepted(tmp_path)
    _ingest(tmp_path, godot)
    argv = godot.certify_argv
    assert "--policy=power_grip_1h_v1" in argv
    assert any(a.startswith("--weapon=") and a.endswith(".glb") for a in argv)


def test_every_run_writes_a_machine_readable_report(tmp_path):
    result = _ingest(tmp_path, _accepted(tmp_path))
    report = json.loads((tmp_path / result.report_path).read_text(encoding="utf-8"))
    assert report["command"] == "ingest-rig"
    assert report["verdict"] == INGEST_ACCEPTED
    assert report["report_path"] == result.report_path
    assert report["certification"]["chain"] == ACCEPTED_CHAIN


def test_a_rerun_is_idempotent(tmp_path):
    first = _ingest(tmp_path, _accepted(tmp_path))
    second = _ingest(tmp_path, _accepted(tmp_path))
    assert first.to_dict() == second.to_dict()
    assert second.published
