"""Driver for the Godot-side hand-fixture certification step.

After the provider returns a finger-rigged humanoid, the equipment pipeline still
needs to know which triangles are that unit's thumb nail plate and volar pad.
Until A2.10 those were hand-authored per unit; they are now compiled from the
rigged mesh plus an injected skeleton-family profile.

The compiler itself lives in Godot, because it has to see exactly the geometry
the renderer sees: the same importer, the same skin bind poses and the same CPU
skinning the grip gates measure against. Re-implementing that here would be a
second, silently diverging notion of the mesh. So this module drives Godot as a
headless pipeline step and classifies its result. Blender is deliberately not
introduced as a dependency and is not shipped with the game.

This module owns ONE step. The canonical ingestion chain that calls it, decides
what may be published and owns the process exit code is `rig_ingest.py`.

Fail-closed: a step that cannot run, times out, or returns anything other than a
fully accepted chain for every required side is a refusal. There is no fallback
to another unit's fixture and no partial acceptance.

EXIT PROTOCOL (shared with the Godot step and the CLI)
    0  the whole chain was accepted
    2  expected, classified asset/fixture FAIL, with a named domain error class
    1  infrastructure / process / protocol / tooling error
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
from dataclasses import dataclass, field
from pathlib import Path

#: Verdicts. Mirrors humanoid_gate so ingestion reports read the same way.
INGEST_ACCEPTED = "ACCEPTED"
INGEST_CLASSIFIED = "CLASSIFIED"
INGEST_STEP_FAILED = "STEP_FAILED"

#: The Godot-side step and the marker line it prints.
CERTIFY_SCRIPT = "res://presentation/equipment/tools/certify_hand_fixture_headless.gd"
REPORT_MARKER = "HAND_FIXTURE_INGEST "

#: Exit codes, identical on the Godot step, this module and the CLI.
EXIT_ACCEPTED = 0
EXIT_STEP_FAILED = 1
EXIT_CLASSIFIED = 2

#: Verdict -> process exit code.
VERDICT_EXIT_CODES = {
    INGEST_ACCEPTED: EXIT_ACCEPTED,
    INGEST_CLASSIFIED: EXIT_CLASSIFIED,
    INGEST_STEP_FAILED: EXIT_STEP_FAILED,
}

#: A compile plus one grip certification is bounded work; longer means hung.
DEFAULT_TIMEOUT_SECONDS = 600

#: Certification stages. A single reference rig proves the compiler on that
#: rig only, which is not the same thing as a certified production profile.
STAGE_CALIBRATING = "CALIBRATING"
STAGE_BATCH_CERTIFICATION = "BATCH_CERTIFICATION"
STAGE_PRODUCTION_CERTIFIED = "PRODUCTION_CERTIFIED"


class GodotNotAvailable(RuntimeError):
    """The headless certification step cannot run because Godot was not found."""


@dataclass
class HandFixtureIngestResult:
    verdict: str
    detail: str
    #: Named domain error class for a classified rejection, e.g.
    #: HAND_SKELETON_INCOMPLETE or FIXTURE_MESH_HASH_MISMATCH.
    error_class: str | None = None
    #: Which link of the chain rejected the asset.
    stage: str | None = None
    #: Steps that completed, in order.
    chain: tuple[str, ...] = ()
    artifact_path: str | None = None
    #: Where the CERTIFIED runtime fixture was written, if the chain minted one.
    certified_artifact_path: str | None = None
    content_hash: str | None = None
    #: Two distinct source identities: static geometry, and the whole
    #: rig/deformation contract that actually binds the compiled markers.
    source_geometry_sha256: str | None = None
    source_rig_sha256: str | None = None
    #: The certification envelope's own hash. Present only when certified.
    certification_hash: str | None = None
    acceptance_report_digest: str | None = None
    #: A certificate exists. Strictly stronger than `compiler_pass`, and the
    #: only state in which anything may be published.
    certified: bool = False
    family_id: str | None = None
    family_version: str | None = None
    import_representation: str | None = None
    compiler_version: str | None = None
    calibration_id: str | None = None
    #: The compiler passed. NOT the same thing as an accepted asset.
    compiler_pass: bool = False
    grip_ground_truth: dict = field(default_factory=dict)
    sides: dict = field(default_factory=dict)
    exit_code: int | None = None
    #: Sides that compiled with certified confidence.
    certified_sides: tuple[str, ...] = ()
    #: Sides the compiler refused, mapped to the named error class.
    classified_sides: dict = field(default_factory=dict)
    skeleton_bone_count: int | None = None

    @property
    def accepted(self) -> bool:
        return self.verdict == INGEST_ACCEPTED

    @property
    def process_exit_code(self) -> int:
        return VERDICT_EXIT_CODES.get(self.verdict, EXIT_STEP_FAILED)

    def to_dict(self) -> dict:
        return {
            "verdict": self.verdict,
            "detail": self.detail,
            "error_class": self.error_class,
            "stage": self.stage,
            "chain": list(self.chain),
            "artifact_path": self.artifact_path,
            "certified_artifact_path": self.certified_artifact_path,
            "content_hash": self.content_hash,
            "source_geometry_sha256": self.source_geometry_sha256,
            "source_rig_sha256": self.source_rig_sha256,
            "certification_hash": self.certification_hash,
            "acceptance_report_digest": self.acceptance_report_digest,
            "certified": self.certified,
            "family_id": self.family_id,
            "family_version": self.family_version,
            "import_representation": self.import_representation,
            "compiler_version": self.compiler_version,
            "calibration_id": self.calibration_id,
            "compiler_pass": self.compiler_pass,
            "grip_ground_truth": self.grip_ground_truth,
            "sides": self.sides,
            "certified_sides": list(self.certified_sides),
            "classified_sides": self.classified_sides,
            "skeleton_bone_count": self.skeleton_bone_count,
            "exit_code": self.exit_code,
            "process_exit_code": self.process_exit_code,
            "accepted": self.accepted,
        }


def resolve_godot_executable(explicit: str | None = None) -> str:
    """Same resolution order as the test runner: explicit, GODOT_EXE, PATH."""
    for candidate in (explicit, os.environ.get("GODOT_EXE")):
        if candidate and Path(candidate).is_file():
            return str(Path(candidate))
    for name in ("godot", "godot4"):
        found = shutil.which(name)
        if found:
            return found
    raise GodotNotAvailable(
        "Godot executable not found. Set GODOT_EXE or put godot on PATH; the hand-fixture "
        "certification step runs inside Godot so the compiled patches match renderer skinning."
    )


def certify_hand_fixture(
    *,
    project_path: Path,
    rigged_glb_res_path: str,
    artifact_res_path: str,
    certified_artifact_res_path: str,
    policy_id: str,
    weapon_res_path: str,
    required_sides: tuple[str, ...] = ("right",),
    compile_sides: tuple[str, ...] = ("right", "left"),
    family_id: str | None = None,
    asset_id: str | None = None,
    godot_executable: str | None = None,
    timeout_seconds: int = DEFAULT_TIMEOUT_SECONDS,
    runner=subprocess.run,
) -> HandFixtureIngestResult:
    """Run the whole Godot-side chain for one rigged asset and classify it.

    The chain covers family resolution, compilation, artifact integrity, binding
    to the imported mesh, bind sanity and the selected grip policy's
    ground-truth gate. `required_sides` are the hands that must be accepted;
    other compiled sides are reported so a refused hand is visible, never lost.
    """
    executable = resolve_godot_executable(godot_executable)
    ordered_sides = tuple(dict.fromkeys(tuple(required_sides) + tuple(compile_sides)))
    argv = [
        executable,
        "--headless",
        "--path",
        str(project_path),
        "-s",
        CERTIFY_SCRIPT,
        "--",
        f"--glb={rigged_glb_res_path}",
        f"--out={artifact_res_path}",
        f"--certified-out={certified_artifact_res_path}",
        f"--policy={policy_id}",
        f"--weapon={weapon_res_path}",
        f"--sides={','.join(ordered_sides)}",
        f"--required={','.join(required_sides)}",
    ]
    if family_id:
        argv.append(f"--family={family_id}")
    if asset_id:
        argv.append(f"--asset_id={asset_id}")

    try:
        completed = runner(
            argv, capture_output=True, text=True, timeout=timeout_seconds, check=False
        )
    except subprocess.TimeoutExpired:
        return HandFixtureIngestResult(
            verdict=INGEST_STEP_FAILED,
            detail=f"certification step exceeded {timeout_seconds}s and was treated as hung",
            error_class="INGEST_TIMEOUT",
            stage="process",
        )
    except OSError as exc:
        return HandFixtureIngestResult(
            verdict=INGEST_STEP_FAILED,
            detail=f"could not start the certification step: {exc}",
            error_class="INGEST_GODOT_START_FAILED",
            stage="process",
        )

    report = _parse_report(f"{completed.stdout}\n{completed.stderr}")
    if report is None:
        return HandFixtureIngestResult(
            verdict=INGEST_STEP_FAILED,
            detail="certification step produced no machine-readable report",
            error_class="INGEST_REPORT_MISSING",
            stage="process",
            exit_code=completed.returncode,
        )

    sides = report.get("sides", {}) or {}
    certified = tuple(
        name for name in sorted(sides) if bool(sides[name].get("compiled", False))
    )
    classified = {
        name: str(sides[name].get("error_class") or "UNCLASSIFIED")
        for name in sorted(sides)
        if not bool(sides[name].get("compiled", False))
    }
    common = dict(
        error_class=report.get("error_class"),
        stage=report.get("stage_failed"),
        chain=tuple(str(step) for step in report.get("chain", []) or ()),
        artifact_path=report.get("artifact_path"),
        certified_artifact_path=report.get("certified_artifact_path"),
        content_hash=report.get("content_hash"),
        source_geometry_sha256=report.get("source_geometry_sha256"),
        source_rig_sha256=report.get("source_rig_sha256"),
        certification_hash=report.get("certification_hash"),
        acceptance_report_digest=report.get("acceptance_report_digest"),
        certified=bool(report.get("certified", False)),
        family_id=report.get("family_id"),
        family_version=report.get("family_version"),
        import_representation=report.get("import_representation"),
        compiler_version=report.get("compiler_version"),
        calibration_id=report.get("calibration_id"),
        compiler_pass=bool(report.get("compiler_pass", False)),
        grip_ground_truth=report.get("grip_ground_truth", {}) or {},
        sides=sides,
        exit_code=completed.returncode,
        certified_sides=certified,
        classified_sides=classified,
        skeleton_bone_count=report.get("skeleton_bone_count"),
    )

    if completed.returncode == EXIT_STEP_FAILED:
        return HandFixtureIngestResult(
            verdict=INGEST_STEP_FAILED,
            detail=str(report.get("detail") or "the step itself could not run"),
            **common,
        )
    if completed.returncode == EXIT_CLASSIFIED:
        return HandFixtureIngestResult(
            verdict=INGEST_CLASSIFIED,
            detail=str(report.get("detail") or "asset classified as fail-closed"),
            **common,
        )
    if completed.returncode != EXIT_ACCEPTED:
        return HandFixtureIngestResult(
            verdict=INGEST_STEP_FAILED,
            detail=f"unexpected exit code {completed.returncode} from the certification step",
            **common,
        )
    # Exit 0 means the Godot chain accepted the side it certified. The required
    # sides are re-checked here, so a caller asking for a hand the step never
    # certified cannot read the run as an acceptance.
    if not bool(report.get("accepted", False)):
        return HandFixtureIngestResult(
            verdict=INGEST_STEP_FAILED,
            detail="step exited 0 without declaring the chain accepted",
            **common,
        )
    # An accepted chain that minted no certificate is a protocol violation, not
    # an acceptance: nothing runtime-loadable exists, so there is nothing to
    # publish and the run must not read as a success (A2.12).
    if not bool(report.get("certified", False)):
        return HandFixtureIngestResult(
            verdict=INGEST_STEP_FAILED,
            detail="the chain reported acceptance without minting a certified fixture",
            **common,
        )
    missing = [side for side in required_sides if side not in certified]
    if missing:
        return HandFixtureIngestResult(
            verdict=INGEST_CLASSIFIED,
            detail="required side(s) not certified: "
            + ", ".join(f"{s}={classified.get(s, 'NOT_COMPILED')}" for s in missing),
            **common,
        )
    return HandFixtureIngestResult(
        verdict=INGEST_ACCEPTED,
        detail="import, family, compile, integrity, mesh binding, bind sanity and "
        "grip ground truth all passed",
        **common,
    )


def _parse_report(output: str) -> dict | None:
    """Last machine-readable report line wins; prose around it is ignored."""
    found: dict | None = None
    for line in output.splitlines():
        marker = line.find(REPORT_MARKER)
        if marker < 0:
            continue
        payload = line[marker + len(REPORT_MARKER):].strip()
        try:
            parsed = json.loads(payload)
        except json.JSONDecodeError:
            continue
        if isinstance(parsed, dict):
            found = parsed
    return found


def certification_stage(*, units_certified: int, batch_runs_green: int) -> str:
    """Where the profile actually stands.

    One reference rig compiling correctly is CALIBRATING, not a certified
    production profile. This exists so reports cannot quietly upgrade the claim.
    """
    if units_certified <= 1 or batch_runs_green <= 0:
        return STAGE_CALIBRATING
    if batch_runs_green < 3:
        return STAGE_BATCH_CERTIFICATION
    return STAGE_PRODUCTION_CERTIFIED
