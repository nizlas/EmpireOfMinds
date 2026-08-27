"""Canonical local ingestion entry point for a rigged humanoid.

This is the owner of the automatic chain from "a rigged humanoid GLB exists" to
"the asset is ACCEPTED or classified as rejected". It is reachable from the CLI
(`python -m tools.assetgen ingest-rig ...`) and is called by the autorig
download path, so it is not a tool that only its own test invokes.

    1. import              - `godot --headless --import`, so the import
                             representation the skeleton family needs is
                             established by the pipeline, never by an editor visit
    2. family resolution   - the skeleton family identifies itself on the rig
    3. fixture compilation - automatic, from the rigged mesh
    4. artifact integrity  - written, re-read and re-verified
    5. mesh binding        - the artifact is bound to the imported mesh
    6. bind sanity         - through the real assembler and grip engine
    7. grip ground truth   - the selected policy's gate
    8. machine-readable result
    9. ACCEPTED, or a classified rejection with a named domain error class

Steps 2-7 run inside Godot (`hand_fixture_ingest.certify_hand_fixture`).

WHAT IS NOT CLAIMED. No external provider callback calls this automatically:
the provider round trip is `autorig` + `poll`/`download`, and the ingestion step
runs on the downloaded file from the CLI. Whether that happens automatically for
a given job is visible in the emitted report, never assumed.

PUBLISHING (A2.12). Two files are staged, and they are not the same kind of
thing: the compiler's EVIDENCE, and — only for a fully accepted chain — a
CERTIFIED runtime fixture. Only the certificate is ever published, and the
publish is ATOMIC (write a temporary file beside the destination, then rename
it over the destination), so an interrupted publish can leave a leftover
temporary file but never a half-written artifact at the path the game loads.

File placement is no longer what keeps a rejected asset out of the game: a
staged evidence file copied or renamed onto the published path is refused by
the runtime loader, because it is the wrong resource type and carries no
certification envelope.

EXIT PROTOCOL: 0 accepted, 2 classified asset/fixture FAIL, 1 infrastructure.
"""

from __future__ import annotations

import json
import os
import subprocess
from dataclasses import dataclass, field
from pathlib import Path

from .hand_fixture_ingest import (
    DEFAULT_TIMEOUT_SECONDS,
    EXIT_ACCEPTED,
    EXIT_CLASSIFIED,
    EXIT_STEP_FAILED,
    INGEST_ACCEPTED,
    INGEST_STEP_FAILED,
    GodotNotAvailable,
    HandFixtureIngestResult,
    certify_hand_fixture,
    resolve_godot_executable,
)

#: The grip policy every rigged humanoid must satisfy to be usable as a unit
#: that can hold a one-handed weapon, and the weapon used to certify it.
#: Ingestion-owner configuration, not generic-core data.
DEFAULT_POLICY_ID = "power_grip_1h_v1"
CERTIFICATION_WEAPON = "res://assets/prototype/3d/equipment/wooden_club/wooden_club.glb"

#: Where staged (possibly rejected) artifacts and machine reports are written.
STAGING_DIR_RES = "res://artifacts/fixtures/staging/"
REPORT_DIR = Path("artifacts") / "assetgen" / "rig_ingest"


@dataclass
class RigIngestResult:
    verdict: str
    detail: str
    asset: str
    exit_code: int
    certification: dict = field(default_factory=dict)
    staged_artifact: str | None = None
    #: Staged CERTIFIED fixture. Only this may ever be published.
    staged_certified_artifact: str | None = None
    published_artifact: str | None = None
    published: bool = False
    report_path: str | None = None
    import_step: dict = field(default_factory=dict)

    @property
    def accepted(self) -> bool:
        return self.verdict == INGEST_ACCEPTED

    def to_dict(self) -> dict:
        return {
            "command": "ingest-rig",
            "verdict": self.verdict,
            "detail": self.detail,
            "asset": self.asset,
            "exit_code": self.exit_code,
            "accepted": self.accepted,
            "staged_artifact": self.staged_artifact,
            "staged_certified_artifact": self.staged_certified_artifact,
            "published_artifact": self.published_artifact,
            "published": self.published,
            "report_path": self.report_path,
            "import_step": self.import_step,
            "certification": self.certification,
        }


def _res_to_path(project_path: Path, res_path: str) -> Path:
    return project_path / res_path.removeprefix("res://")


def publish_atomically(source: Path, destination: Path) -> dict:
    """Replace `destination` with `source`'s bytes, or leave it untouched.

    `os.replace` is atomic on the same filesystem, so a reader either sees the
    previous artifact or the new one. Writing straight into the destination —
    which is what A2.11 did — leaves a truncated resource at the path the game
    loads if the process dies mid-write. The temporary file is created beside
    the destination so the rename never crosses a filesystem boundary.
    """
    if not source.is_file():
        return {"ok": False, "error_class": "INGEST_STAGED_ARTIFACT_MISSING"}
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_name(destination.name + ".publishing")
    try:
        temporary.write_bytes(source.read_bytes())
        os.replace(temporary, destination)
    except OSError as exc:
        # A failed publish must not leave the half-written temporary behind and
        # must not have touched the destination at all.
        temporary.unlink(missing_ok=True)
        return {"ok": False, "error_class": "INGEST_PUBLISH_FAILED", "detail": str(exc)}
    return {"ok": True, "published": destination.as_posix()}


def run_import(
    *,
    project_path: Path,
    godot_executable: str | None = None,
    timeout_seconds: int = DEFAULT_TIMEOUT_SECONDS,
    runner=subprocess.run,
) -> dict:
    """Establish the canonical import representation without an editor visit."""
    executable = resolve_godot_executable(godot_executable)
    argv = [executable, "--headless", "--path", str(project_path), "--import"]
    try:
        completed = runner(
            argv, capture_output=True, text=True, timeout=timeout_seconds, check=False
        )
    except subprocess.TimeoutExpired:
        return {"ok": False, "error_class": "INGEST_IMPORT_TIMEOUT"}
    except OSError as exc:
        return {"ok": False, "error_class": "INGEST_GODOT_START_FAILED", "detail": str(exc)}
    return {"ok": completed.returncode == 0, "exit_code": completed.returncode}


def ingest_rigged_humanoid(
    *,
    project_path: Path,
    rigged_glb_res_path: str,
    asset_id: str,
    published_artifact_res_path: str | None = None,
    staged_artifact_res_path: str | None = None,
    staged_certified_artifact_res_path: str | None = None,
    policy_id: str = DEFAULT_POLICY_ID,
    weapon_res_path: str = CERTIFICATION_WEAPON,
    required_sides: tuple[str, ...] = ("right",),
    compile_sides: tuple[str, ...] = ("right", "left"),
    family_id: str | None = None,
    repo_root: Path | None = None,
    skip_import: bool = False,
    godot_executable: str | None = None,
    timeout_seconds: int = DEFAULT_TIMEOUT_SECONDS,
    runner=subprocess.run,
) -> RigIngestResult:
    """Run the canonical chain and decide whether this asset may be published."""
    staged = staged_artifact_res_path or f"{STAGING_DIR_RES}{asset_id}_hand_fixture.tres"
    staged_certified = (
        staged_certified_artifact_res_path
        or f"{STAGING_DIR_RES}{asset_id}_hand_fixture_certified.tres"
    )
    _res_to_path(project_path, staged).parent.mkdir(parents=True, exist_ok=True)
    _res_to_path(project_path, staged_certified).parent.mkdir(parents=True, exist_ok=True)

    # A missing toolchain is an infrastructure error with a machine-readable
    # report and exit 1, never a traceback and never a silent asset verdict.
    try:
        resolve_godot_executable(godot_executable)
    except GodotNotAvailable as exc:
        return _finish(
            RigIngestResult(
                verdict=INGEST_STEP_FAILED,
                detail=str(exc),
                asset=rigged_glb_res_path,
                    exit_code=EXIT_STEP_FAILED,
                    staged_artifact=staged,
                    staged_certified_artifact=staged_certified,
                    published_artifact=published_artifact_res_path,
                    import_step={"ok": False, "error_class": "INGEST_GODOT_NOT_AVAILABLE"},
            ),
            repo_root,
            asset_id,
        )

    import_step: dict = {"skipped": True}
    if not skip_import:
        import_step = run_import(
            project_path=project_path,
            godot_executable=godot_executable,
            timeout_seconds=timeout_seconds,
            runner=runner,
        )
        if not import_step.get("ok", False):
            return _finish(
                RigIngestResult(
                    verdict=INGEST_STEP_FAILED,
                    detail="the headless import step failed, so no import "
                    "representation could be established",
                    asset=rigged_glb_res_path,
                    exit_code=EXIT_STEP_FAILED,
                    staged_artifact=staged,
                    staged_certified_artifact=staged_certified,
                    published_artifact=published_artifact_res_path,
                    import_step=import_step,
                ),
                repo_root,
                asset_id,
            )

    certification: HandFixtureIngestResult = certify_hand_fixture(
        project_path=project_path,
        rigged_glb_res_path=rigged_glb_res_path,
        artifact_res_path=staged,
        certified_artifact_res_path=staged_certified,
        policy_id=policy_id,
        weapon_res_path=weapon_res_path,
        required_sides=required_sides,
        compile_sides=compile_sides,
        family_id=family_id,
        asset_id=asset_id,
        godot_executable=godot_executable,
        timeout_seconds=timeout_seconds,
        runner=runner,
    )

    result = RigIngestResult(
        verdict=certification.verdict,
        detail=certification.detail,
        asset=rigged_glb_res_path,
        exit_code=certification.process_exit_code,
        certification=certification.to_dict(),
        staged_artifact=staged,
        staged_certified_artifact=staged_certified,
        published_artifact=published_artifact_res_path,
        import_step=import_step,
    )
    # Only an accepted chain that actually minted a CERTIFICATE may publish, and
    # only the certificate is published. A rejected asset's evidence stays in
    # staging, where it is a diagnostic and not a fixture.
    if certification.accepted and published_artifact_res_path:
        published = publish_atomically(
            _res_to_path(project_path, staged_certified),
            _res_to_path(project_path, published_artifact_res_path),
        )
        if not published.get("ok", False):
            result.verdict = INGEST_STEP_FAILED
            result.detail = (
                "accepted chain, but the certified fixture could not be published: "
                f"{published.get('error_class')}"
            )
            result.exit_code = EXIT_STEP_FAILED
        else:
            result.published = True
    return _finish(result, repo_root, asset_id)


def _finish(result: RigIngestResult, repo_root: Path | None, asset_id: str) -> RigIngestResult:
    """Write the machine-readable result so every run is auditable."""
    if repo_root is not None:
        destination = repo_root / REPORT_DIR / f"{asset_id}.json"
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(
            json.dumps(result.to_dict(), indent=2, sort_keys=True, default=str) + "\n",
            encoding="utf-8",
        )
        result.report_path = destination.relative_to(repo_root).as_posix()
        # Re-write once the path is known, so the file records its own location.
        destination.write_text(
            json.dumps(result.to_dict(), indent=2, sort_keys=True, default=str) + "\n",
            encoding="utf-8",
        )
    assert result.exit_code in (EXIT_ACCEPTED, EXIT_CLASSIFIED, EXIT_STEP_FAILED)
    return result
