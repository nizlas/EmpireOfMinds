"""Command line entry point for the asset-generation tooling.

    python -m tools.assetgen <command> [options]

Every command that can spend money or reach a provider requires `--live`.
Without it the command still runs, validates and reports, but refuses at the
network boundary. That way the default path — and the whole test suite — cannot
create a paid task by accident.

Free / read-only:  auth-smoke (needs --live but creates nothing), dry-run,
                   status, inspect, list, shield-plan, validate-shield,
                   humanoid-gate
Paid:              submit, poll (only when it downloads a finished paid task),
                   resume
Destructive:       cancel (explicit, never triggered by retry logic)
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from .artifact_paths import UnsafeOutputPath
from .capability import CapabilityRefused
from .command_risk import UnclassifiedCommand, risk_for
from .errors import ProviderError
from .human_confirmations import DEFAULT_LEDGER, ConfirmationRefused, load_ledger
from .human_confirmations import record as record_human_confirmation
from .humanoid_gate import evaluate_candidates, evaluate_humanoid_candidate
from .live_gate import (
    OPT_IN_ENV_VAR,
    OPT_IN_REQUIRED_VALUE,
    LiveAuthorization,
    LiveGateRefusal,
)
from .manifest import JobStatus
from .orchestrator import JobOrchestrator, LiveCallNotAuthorized, provider_factory_for
from .paid_executor import PaidSubmission, execute_paid_submission
from .provider_plan import (
    PLAN_DIGEST_KEY,
    build_autorig_plan,
    build_meshy_multiview_plan,
    build_meshy_shield_3d_plan,
)
from .provider_plan import write_plan as write_provider_plan
from .providers import KNOWN_PROVIDERS, PROVIDER_MESHY, PROVIDER_UTHANA
from .providers.base import TaskType
from .rig_ingest import (
    CERTIFICATION_WEAPON,
    DEFAULT_POLICY_ID,
    ingest_rigged_humanoid,
)
from .secret_guard import scrub_obj
from .shield_analysis import analyze_shield_file, compare_pre_and_post_remesh
from .static_export import (
    DEFAULT_CANDIDATE_ROOT,
    GodotNotAvailable,
    StaticExportError,
    export_static_candidate,
)
from .shield_pipeline import (
    build_multiview_request,
    build_shield_3d_request,
    preflight_multiview,
    shield_plan,
    write_plan,
)
from .store import JobStore, repo_root_from_here
from .transport import RetryPolicy, UrllibTransport


def emit(payload: object) -> None:
    """Single output path, so every printed structure passes the secret scrubber."""
    print(json.dumps(scrub_obj(payload), indent=2, sort_keys=True, default=str))


def authorization_for(args) -> LiveAuthorization:
    """Collect the three barriers. Reads the opt-in variable, never a credential."""
    return LiveAuthorization.from_environment(
        live=bool(getattr(args, "live", False)),
        confirmed_plan_digest=str(getattr(args, "confirm_plan", "") or ""),
    )


def build_orchestrator(args) -> JobOrchestrator:
    store = JobStore.create(repo_root_from_here())
    factory = provider_factory_for(
        transport=UrllibTransport(),
        retry_policy=RetryPolicy(),
        require_credential=False,
    )
    return JobOrchestrator(
        store=store,
        provider_factory=factory,
        # The gate object itself, not a pair of booleans. It is the only thing
        # that can mint a capability, and it cannot mint a paid one.
        authorization=authorization_for(args),
    )


def assert_command_classified(command: str):
    """Every command declares its risk class centrally, or nothing runs.

    Called on the way into `main()` so the failure mode for a new unclassified
    command is a loud refusal rather than an unguarded provider call.
    """
    return risk_for(command)


# --------------------------------------------------------------------- commands


def cmd_auth_smoke(args) -> int:
    """A free, read-only credential probe - which is still real provider traffic.

    The review (BLOCKER 1) measured this command issuing a live request with only
    `--live`, because it checked its own flag instead of the central gate. It now
    mints a NETWORK_READ capability like every other network command, so both
    non-paid barriers apply and the refusal happens before the credential is read.
    """
    orchestrator = build_orchestrator(args)
    authorization = authorization_for(args)
    results = []
    for name in args.providers or list(KNOWN_PROVIDERS):
        provider = orchestrator.provider_factory(name)
        try:
            capability = authorization.mint_network_capability(
                provider=name,
                operation="auth_smoke",
                endpoint=provider.endpoint_identity(),
            )
        except LiveGateRefusal as exc:
            # Reported per provider rather than raised, so `auth-smoke` still
            # answers for every provider in one run. Nothing was sent.
            results.append(
                {
                    "provider": name,
                    "ok": False,
                    "status": "NOT_AUTHORIZED",
                    "credential_env_var": provider.credential_env_var,
                    "refused": exc.code,
                    "message": exc.message,
                }
            )
            continue
        if not provider.has_credential:
            results.append(
                {
                    "provider": name,
                    "ok": False,
                    "status": JobStatus.BLOCKED_MISSING_CREDENTIAL.value,
                    "credential_env_var": provider.credential_env_var,
                    "message": f"{provider.credential_env_var} is not set in the environment",
                }
            )
            continue
        try:
            outcome = provider.auth_smoke(capability)
            results.append(
                {
                    "provider": name,
                    "ok": outcome.ok,
                    "status": "OK" if outcome.ok else "FAILED",
                    "credential_env_var": provider.credential_env_var,
                    "message": outcome.message,
                    "detail": outcome.detail,
                }
            )
        except ProviderError as exc:
            results.append(
                {
                    "provider": name,
                    "ok": False,
                    "status": "FAILED",
                    "credential_env_var": provider.credential_env_var,
                    "error": exc.to_manifest_dict(),
                }
            )
    emit(
        {
            "command": "auth-smoke",
            "declared_risk": getattr(args, "declared_risk", ""),
            "live": authorization.live,
            "results": results,
        }
    )
    return 0


def cmd_provider_plan(args) -> int:
    """Produce the canonical plan for a paid operation. Fully offline.

    This is the only way to obtain the digest that barrier 3 accepts, and it
    deliberately cannot submit anything: the operator reads the plan, then passes
    its digest back on a separate authorized command.
    """
    repo_root = repo_root_from_here()
    path = Path(args.glb) if Path(args.glb).is_absolute() else repo_root / args.glb
    plan = build_autorig_plan(
        repo_root=repo_root,
        input_path=path,
        character_name=args.name or "",
    )
    if args.out:
        destination = repo_root / args.out
        plan["plan_path"] = (
            write_provider_plan(plan, destination).relative_to(repo_root).as_posix()
        )
    emit(
        {
            "command": "provider-plan",
            "network_used": False,
            "credential_read": False,
            "plan": plan,
            "confirm_with": f"--confirm-plan {plan[PLAN_DIGEST_KEY]}",
            "next_step": (
                "read the plan; if it is correct, run the paid command with --live, "
                f"{OPT_IN_ENV_VAR}={OPT_IN_REQUIRED_VALUE} and --confirm-plan "
                f"{plan[PLAN_DIGEST_KEY]}"
            ),
        }
    )
    # A plan whose own preflight refuses the input is a document, not permission.
    return 0 if plan["executable"] else 3


def run_paid_command(
    args,
    *,
    command: str,
    provider: str,
    build_plan,
    build_request,
) -> int:
    """The one way a CLI command may spend money.

    Every paid command hands over a plan builder and a request builder and gets the
    same ordering: recompute, verify executable, verify the confirmed digest, verify
    the endpoint, claim exclusively, mint the paid capability, submit exactly once.
    None of that lives in the command any more, which is what stopped the three
    paid commands from drifting apart.
    """
    orchestrator = build_orchestrator(args)
    result = execute_paid_submission(
        PaidSubmission(
            command=command,
            provider=provider,
            build_plan=build_plan,
            build_request=build_request,
        ),
        authorization=authorization_for(args),
        orchestrator=orchestrator,
        provider_factory=orchestrator.provider_factory,
    )
    report = orchestrator.inspect(result.manifest.job_id)
    report["approved_plan_sha256"] = result.digest
    emit(report)
    if result.manifest.status_enum is JobStatus.BLOCKED_MISSING_CREDENTIAL:
        return 3
    return 0


def cmd_shield_plan(args) -> int:
    orchestrator = build_orchestrator(args)
    provider = orchestrator.provider_factory(PROVIDER_MESHY)
    repo_root = orchestrator.store.repo_root
    plan = shield_plan(
        repo_root, provider=PROVIDER_MESHY, credential_present=provider.has_credential
    )
    plan["credential_env_var"] = provider.credential_env_var
    destination = repo_root / "artifacts" / "assetgen" / "shield" / "shield_plan.json"
    plan["plan_path"] = write_plan(repo_root, plan, destination).relative_to(repo_root).as_posix()
    emit(plan)
    return 0


def cmd_shield_multiview(args) -> int:
    """Dry-run or submit the image job that must show the rear grip."""
    orchestrator = build_orchestrator(args)
    repo_root = orchestrator.store.repo_root
    provider = orchestrator.provider_factory(PROVIDER_MESHY)
    plan = shield_plan(
        repo_root, provider=PROVIDER_MESHY, credential_present=provider.has_credential
    )
    front = args.front or plan["reference_resolution"]["canonical_front_reference"]
    if not front:
        emit(
            {
                "command": "shield-multiview",
                "blocked": plan["classified_reason"] or "BLOCKED_NO_CANONICAL_REFERENCE",
                "reason": plan["reference_resolution"]["reason"],
                "candidates": plan["reference_resolution"]["candidates"],
                "next_step": (
                    "nominate a canonical front reference with --front <path>, or produce one "
                    "as a separate authored asset; nothing was sent"
                ),
            }
        )
        return 3

    front_path = repo_root / front
    request = build_multiview_request(provider=PROVIDER_MESHY, front_reference=front_path)
    if args.submit:
        return run_paid_command(
            args,
            command="shield-multiview",
            provider=PROVIDER_MESHY,
            build_plan=lambda: build_meshy_multiview_plan(
                repo_root=repo_root, front_reference=front_path
            ),
            build_request=lambda: request,
        )
    plan = build_meshy_multiview_plan(repo_root=repo_root, front_reference=front_path)
    emit(
        {
            "command": "shield-multiview",
            "mode": "dry-run",
            "plan": orchestrator.dry_run(request),
            "provider_plan": plan,
            "confirm_with": f"--confirm-plan {plan[PLAN_DIGEST_KEY]}",
        }
    )
    return 0


def cmd_shield_3d(args) -> int:
    orchestrator = build_orchestrator(args)
    repo_root = orchestrator.store.repo_root
    views = [Path(v) if Path(v).is_absolute() else repo_root / v for v in (args.views or [])]

    if views:
        preflight = preflight_multiview(views).to_dict()
    else:
        preflight = {
            "view_count": 0,
            "mechanical_verdict": "FAIL",
            "detail": "no views supplied; the multiview image job has not produced any",
        }

    request = build_shield_3d_request(
        provider=PROVIDER_MESHY,
        ordered_views=tuple(views),
        input_task_id=args.input_task_id,
    )

    if not args.confirm_visual_review:
        emit(
            {
                "command": "shield-3d",
                "mode": "dry-run",
                "multiview_preflight": preflight,
                "plan": orchestrator.dry_run(request),
                "blocked": "AWAITING_HUMAN_VISUAL_CONFIRMATION",
                "reason": (
                    "The paid 3D job needs a human to confirm the visual checks first. "
                    "Re-run with --confirm-visual-review --submit --live once every visual "
                    "check in the preflight has actually been verified by eye."
                ),
            }
        )
        return 0

    if not args.submit:
        emit({"command": "shield-3d", "mode": "dry-run", "plan": orchestrator.dry_run(request)})
        return 0

    return run_paid_command(
        args,
        command="shield-3d",
        provider=PROVIDER_MESHY,
        build_plan=lambda: build_meshy_shield_3d_plan(
            repo_root=repo_root,
            ordered_views=tuple(views),
            input_task_id=args.input_task_id,
        ),
        build_request=lambda: request,
    )


def cmd_submit(args) -> int:
    raise SystemExit(
        "Generic submit is intentionally unavailable: a paid job must go through a "
        "task-specific command (shield-multiview, shield-3d, autorig) that carries its "
        "own preflight. Use dry-run to inspect a request."
    )


def cmd_poll(args) -> int:
    orchestrator = build_orchestrator(args)
    manifest = orchestrator.poll(
        args.job_id, timeout_s=args.timeout, interval_s=args.interval, download=not args.no_download
    )
    emit(orchestrator.inspect(manifest.job_id))
    return ingest_after_autorig(orchestrator, manifest, args)


def cmd_resume(args) -> int:
    orchestrator = build_orchestrator(args)
    manifest = orchestrator.resume(args.job_id, timeout_s=args.timeout, interval_s=args.interval)
    emit(orchestrator.inspect(manifest.job_id))
    return 0


def cmd_download(args) -> int:
    orchestrator = build_orchestrator(args)
    manifest = orchestrator.download(args.job_id)
    emit(orchestrator.inspect(manifest.job_id))
    return ingest_after_autorig(orchestrator, manifest, args)


def ingest_after_autorig(orchestrator, manifest, args) -> int:
    """Hand-fixture ingestion for a freshly downloaded auto-rigged humanoid.

    This is the wiring that makes the ingestion chain part of the provider path
    rather than a standalone tool. It only runs for auto-rig jobs, and it only
    runs on a rigged file that is already inside the Godot project, because the
    chain's first step is a headless import of that project. When the download
    landed outside the project the report says so and names the exact command
    to run — it never claims an ingestion that did not happen.
    """
    if getattr(args, "no_ingest_rig", False):
        return 0
    if str(manifest.task_type) != str(TaskType.CHARACTER_AUTORIG.value):
        return 0
    repo_root = orchestrator.store.repo_root
    project_path = repo_root / "game"
    rigged = _downloaded_rig_res_path(manifest, project_path)
    if rigged is None:
        emit(
            {
                "command": "ingest-rig",
                "verdict": "NOT_ATTEMPTED",
                "reason": "NO_RIGGED_GLB_INSIDE_THE_GODOT_PROJECT",
                "detail": (
                    "the auto-rig output is not (yet) a file under game/, so the headless "
                    "import step has nothing to import"
                ),
                "next_step": (
                    "copy the rigged glb under game/assets/... and run: "
                    "python -m tools.assetgen ingest-rig <res://path> --asset-id <id>"
                ),
            }
        )
        return 0
    result = ingest_rigged_humanoid(
        project_path=project_path,
        rigged_glb_res_path=rigged,
        asset_id=str(manifest.job_id),
        repo_root=repo_root,
        godot_executable=getattr(args, "godot", None),
    )
    emit(result.to_dict())
    return result.exit_code


def _downloaded_rig_res_path(manifest, project_path: Path) -> str | None:
    """The downloaded rigged mesh as a res:// path, when it lives in-project."""
    for artifact in getattr(manifest, "artifacts", ()) or ():
        raw = artifact.get("path") if isinstance(artifact, dict) else getattr(artifact, "path", "")
        if not raw or Path(str(raw)).suffix.lower() not in {".glb", ".gltf"}:
            continue
        candidate = Path(str(raw))
        try:
            relative = candidate.resolve().relative_to(project_path.resolve())
        except (ValueError, OSError):
            continue
        return "res://" + relative.as_posix()
    return None


def cmd_ingest_rig(args) -> int:
    """Canonical entry point for the automatic rigged-humanoid ingestion chain."""
    repo_root = repo_root_from_here()
    result = ingest_rigged_humanoid(
        project_path=repo_root / "game",
        rigged_glb_res_path=args.glb,
        asset_id=args.asset_id or Path(args.glb).stem,
        published_artifact_res_path=args.publish,
        policy_id=args.policy,
        weapon_res_path=args.weapon,
        required_sides=tuple(args.required_sides),
        compile_sides=tuple(args.compile_sides),
        family_id=args.family,
        repo_root=repo_root,
        skip_import=args.skip_import,
        godot_executable=args.godot,
    )
    emit(result.to_dict())
    return result.exit_code


def cmd_status(args) -> int:
    orchestrator = build_orchestrator(args)
    manifest = orchestrator.status(args.job_id)
    emit(manifest.to_dict())
    return 0


def cmd_inspect(args) -> int:
    orchestrator = build_orchestrator(args)
    emit(orchestrator.inspect(args.job_id))
    return 0


def cmd_list(args) -> int:
    orchestrator = build_orchestrator(args)
    emit(
        {
            "command": "list",
            "jobs_dir": orchestrator.store.jobs_dir.as_posix(),
            "jobs": [
                {
                    "job_id": m.job_id,
                    "provider": m.provider,
                    "task_type": m.task_type,
                    "status": m.status,
                    "provider_task_id": m.provider_task_id,
                    "resumable": m.resumable,
                    "visual_status": m.visual_status,
                }
                for m in orchestrator.store.list_jobs()
            ],
        }
    )
    return 0


def cmd_cancel(args) -> int:
    orchestrator = build_orchestrator(args)
    manifest = orchestrator.cancel(args.job_id)
    emit(orchestrator.inspect(manifest.job_id))
    return 0


def cmd_validate_shield(args) -> int:
    repo_root = repo_root_from_here()
    path = Path(args.glb) if Path(args.glb).is_absolute() else repo_root / args.glb
    report = analyze_shield_file(path)
    if args.compare_pre_remesh:
        other = (
            Path(args.compare_pre_remesh)
            if Path(args.compare_pre_remesh).is_absolute()
            else repo_root / args.compare_pre_remesh
        )
        report["remesh_comparison"] = compare_pre_and_post_remesh(
            analyze_shield_file(other), report
        )
    if args.out:
        destination = repo_root / args.out
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(
            json.dumps(report, indent=2, sort_keys=True, default=str) + "\n", encoding="utf-8"
        )
        report["report_path"] = destination.relative_to(repo_root).as_posix()
    emit(report)
    return 0


def cmd_humanoid_gate(args) -> int:
    repo_root = repo_root_from_here()
    if args.paths:
        candidates = [
            Path(p) if Path(p).is_absolute() else repo_root / p for p in args.paths
        ]
    else:
        search = repo_root / "game" / "assets" / "prototype" / "3d" / "units"
        candidates = sorted(
            p for p in search.rglob("*") if p.suffix.lower() in {".glb", ".gltf", ".fbx"}
        )
    report = evaluate_candidates(candidates, load_ledger(repo_root / DEFAULT_LEDGER))
    if args.out:
        destination = repo_root / args.out
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(
            json.dumps(report, indent=2, sort_keys=True, default=str) + "\n", encoding="utf-8"
        )
        report["report_path"] = destination.relative_to(repo_root).as_posix()
    emit(report)
    return 0 if report["conclusion"] == "SAFE_INPUT_AVAILABLE" else 3


def cmd_record_human_confirmation(args) -> int:
    """OFFLINE: record one human observation against a candidate's exact bytes.

    The gate refuses to guess whether a mesh is a biped, whether its limbs are
    separated, or whether a derived candidate still reads as its source. This is
    how the answer of a person who looked enters the pipeline. It resolves only a
    check that is currently asking, it is bound to the digest it was given for, and
    it is never rewritten into a measurement.
    """
    repo_root = repo_root_from_here()
    candidate = Path(args.glb) if Path(args.glb).is_absolute() else repo_root / args.glb
    ledger_path = repo_root / (args.ledger or DEFAULT_LEDGER)
    try:
        before = evaluate_humanoid_candidate(candidate, load_ledger(ledger_path))
        entry = record_human_confirmation(
            ledger_path=ledger_path,
            candidate=candidate,
            check=args.check,
            observer=args.observer,
            method=args.method,
            statement=args.statement,
            observed_on=args.observed_on or "",
            # Already-confirmed checks stay answerable so a second look can
            # supersede a first without hand-editing the ledger.
            answerable_checks=[
                *(before.get("waivable_checks") or []),
                *(before.get("human_confirmed_checks") or []),
            ],
        )
    except ConfirmationRefused as exc:
        emit(
            {
                "command": "record-human-confirmation",
                "refused": exc.code,
                "detail": exc.detail,
            }
        )
        return 3
    after = evaluate_humanoid_candidate(candidate, load_ledger(ledger_path))
    emit(
        {
            "command": "record-human-confirmation",
            "network_used": False,
            "credential_read": False,
            "ledger_path": ledger_path.relative_to(repo_root).as_posix(),
            "recorded": entry.to_dict(),
            "gate_after": {
                "verdict": after["verdict"],
                "upload_allowed": after["upload_allowed"],
                "human_confirmed_checks": after["human_confirmed_checks"],
                "still_blocking": after["blocking_checks"],
            },
            "note": (
                "A recorded observation is reported as WAIVED, never as PASS: the "
                "tooling did not verify it and does not claim to have."
            ),
        }
    )
    return 0


def cmd_static_export(args) -> int:
    """OFFLINE: bake a rigged humanoid into a static unrigged candidate.

    Reaches no provider, reads no credential and constructs no request: the only
    subprocess is the local Godot binary, which evaluates the rest pose.
    """
    repo_root = repo_root_from_here()
    source = Path(args.glb) if Path(args.glb).is_absolute() else repo_root / args.glb
    candidate_root = (
        Path(args.candidate_root)
        if Path(args.candidate_root).is_absolute()
        else repo_root / args.candidate_root
    )
    workspace = candidate_root / "_work"
    try:
        provenance = export_static_candidate(
            source_glb=source,
            project_path=repo_root / "game",
            candidate_root=candidate_root,
            output_name=args.out_name,
            workspace=workspace,
            godot_executable=args.godot,
            verify_reimport=not args.no_verify_reimport,
            prove_determinism=args.prove_determinism,
        )
    except StaticExportError as exc:
        emit({"command": "static-export", "refused": exc.code, "detail": exc.detail})
        return 3
    except GodotNotAvailable as exc:
        emit({"command": "static-export", "refused": "GODOT_NOT_AVAILABLE", "detail": str(exc)})
        return 1
    finally:
        # Intermediates only, each removed by exact name inside the workspace. No
        # recursive deletion and no pattern that could expand past it.
        _remove_workspace_files(workspace / "determinism")
        _remove_workspace_files(workspace)

    emit({"command": "static-export", **provenance})
    structural = provenance.get("structural_validation") or {}
    geometry = provenance.get("geometry_comparison") or {}
    reimport = provenance.get("godot_reimport") or {}
    determinism = provenance.get("determinism") or {}
    accepted = (
        bool(structural.get("passed"))
        and bool(geometry.get("passed"))
        and (not reimport.get("performed") or bool(reimport.get("passed")))
        and (
            not determinism.get("performed")
            or (
                bool(determinism.get("byte_identical"))
                and bool(determinism.get("candidate_digest_reproduced"))
            )
        )
    )
    return 0 if accepted else 3


def _remove_workspace_files(workspace: Path) -> None:
    """Delete the bake intermediates by exact name, then the directory if empty.

    Named files rather than a recursive delete: this runs in a `finally`, where a
    wrong or half-resolved path would be at its most dangerous.
    """
    if not workspace.is_dir():
        return
    for entry in sorted(workspace.iterdir()):
        if entry.is_file() and (
            entry.name.startswith("bake_") or entry.name == "reimport_report.json"
        ):
            entry.unlink()
    if not any(workspace.iterdir()):
        workspace.rmdir()


def cmd_autorig(args) -> int:
    """Auto-rig a humanoid. Gated on the pre-upload checks passing first."""
    orchestrator = build_orchestrator(args)
    repo_root = orchestrator.store.repo_root
    path = Path(args.glb) if Path(args.glb).is_absolute() else repo_root / args.glb
    # Same committed ledger the plan was built from, so the command that would
    # spend money and the document that approved it read one source of truth.
    gate = evaluate_candidates([path], load_ledger(repo_root / DEFAULT_LEDGER))
    candidate = gate["candidates"][0]
    if not candidate["upload_allowed"]:
        emit(
            {
                "command": "autorig",
                "blocked": "PRE_UPLOAD_GATE_FAILED",
                "gate": candidate,
                "reason": (
                    "Auto-rig input must be an unrigged, un-animated, textured static humanoid. "
                    "Nothing was uploaded."
                ),
            }
        )
        return 3

    from .providers.base import ImageInput, JobRequest

    request = JobRequest(
        provider=PROVIDER_UTHANA,
        task_type=TaskType.CHARACTER_AUTORIG,
        inputs=(ImageInput(order=0, role="humanoid_mesh", path=path),),
        parameters={
            "name": args.name or path.stem,
            "auto_rig": True,
            "auto_rig_front_facing": True,
            # Non-negotiable: the equipment pipeline grips with fingers, and a
            # rig without finger joints cannot express any grip pose.
            "include_fingers": True,
        },
        label="humanoid_autorig",
    )
    if not args.submit:
        emit({"command": "autorig", "mode": "dry-run", "gate": candidate, "plan": orchestrator.dry_run(request)})
        return 0

    # Paid from here on, through the same executor as the two shield commands.
    return run_paid_command(
        args,
        command="autorig",
        provider=PROVIDER_UTHANA,
        build_plan=lambda: build_autorig_plan(
            repo_root=repo_root, input_path=path, character_name=args.name or ""
        ),
        build_request=lambda: request,
    )


# ----------------------------------------------------------------------- parser


def _add_rig_ingest_flags(node) -> None:
    """Auto-rig downloads run the hand-fixture ingestion chain by default."""
    node.add_argument(
        "--no-ingest-rig",
        action="store_true",
        help="do not run the hand-fixture ingestion chain on a downloaded rig",
    )
    node.add_argument("--godot", help="explicit Godot executable for the ingestion chain")


def _add_confirm_plan_flag(node) -> None:
    """Barrier 3, spelled identically on every paid command.

    It used to exist only on `autorig`, which is precisely why the two shield
    submits could not be asked to confirm anything.
    """
    node.add_argument(
        "--confirm-plan",
        default="",
        help=(
            "sha256 of the exact plan this command prints in dry-run mode; required for "
            "--submit. A stale, foreign or edited plan is refused"
        ),
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="python -m tools.assetgen", description=__doc__)
    parser.add_argument(
        "--live",
        action="store_true",
        help="authorize real provider calls; without it every network step refuses",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    smoke = sub.add_parser("auth-smoke", help="free read-only credential probe per provider")
    smoke.add_argument("--providers", nargs="*", choices=list(KNOWN_PROVIDERS))
    smoke.set_defaults(func=cmd_auth_smoke)

    plan = sub.add_parser("shield-plan", help="resolve the shield truth source and print the contract")
    plan.set_defaults(func=cmd_shield_plan)

    multiview = sub.add_parser("shield-multiview", help="image job for consistent shield views")
    multiview.add_argument("--front", help="canonical front reference, relative to the repo root")
    multiview.add_argument("--submit", action="store_true", help="PAID: create the image task")
    multiview.add_argument("--force-new-attempt", action="store_true")
    _add_confirm_plan_flag(multiview)
    multiview.set_defaults(func=cmd_shield_multiview)

    three_d = sub.add_parser("shield-3d", help="multi-image-to-3D job for the shield candidate")
    three_d.add_argument("--views", nargs="*", help="ordered view images, front first")
    three_d.add_argument("--input-task-id", help="chain from an existing image task instead")
    three_d.add_argument("--submit", action="store_true", help="PAID: create the 3D task")
    three_d.add_argument(
        "--confirm-visual-review",
        action="store_true",
        help="record that a human verified every visual check; required before submitting",
    )
    three_d.add_argument("--force-new-attempt", action="store_true")
    _add_confirm_plan_flag(three_d)
    three_d.set_defaults(func=cmd_shield_3d)

    provider_plan_cmd = sub.add_parser(
        "provider-plan",
        help=(
            "OFFLINE: produce the canonical plan and its sha256 for a paid operation. "
            "Exit 0 executable, 3 the plan's own preflight refuses the input"
        ),
    )
    provider_plan_cmd.add_argument("glb", help="local humanoid mesh the plan would upload")
    provider_plan_cmd.add_argument("--name", help="character name; defaults to the filename")
    provider_plan_cmd.add_argument("--out", help="also write the plan to this path")
    provider_plan_cmd.set_defaults(func=cmd_provider_plan)

    autorig = sub.add_parser("autorig", help="auto-rig a humanoid after the pre-upload gate")
    autorig.add_argument("glb")
    autorig.add_argument("--name", help="character name at the provider; defaults to the filename")
    autorig.add_argument("--submit", action="store_true", help="PAID: upload and rig")
    _add_confirm_plan_flag(autorig)
    autorig.add_argument("--force-new-attempt", action="store_true")
    autorig.set_defaults(func=cmd_autorig)

    for name, func, helptext in (
        ("poll", cmd_poll, "poll an existing task, then download immediately"),
        ("resume", cmd_resume, "continue an interrupted job from its stored task id"),
    ):
        node = sub.add_parser(name, help=helptext)
        node.add_argument("job_id")
        node.add_argument("--timeout", type=float, default=1800.0)
        node.add_argument("--interval", type=float, default=10.0)
        if name == "poll":
            node.add_argument("--no-download", action="store_true")
        _add_rig_ingest_flags(node)
        node.set_defaults(func=func)

    download = sub.add_parser("download", help="re-download recorded output urls")
    download.add_argument("job_id")
    _add_rig_ingest_flags(download)
    download.set_defaults(func=cmd_download)

    for name, func, helptext in (
        ("status", cmd_status, "offline manifest dump"),
        ("inspect", cmd_inspect, "offline report incl. artifact hash verification"),
    ):
        node = sub.add_parser(name, help=helptext)
        node.add_argument("job_id")
        node.set_defaults(func=func)

    listing = sub.add_parser("list", help="every local job and its resumability")
    listing.set_defaults(func=cmd_list)

    cancel = sub.add_parser("cancel", help="DESTRUCTIVE: cancel a provider task explicitly")
    cancel.add_argument("job_id")
    cancel.set_defaults(func=cmd_cancel)

    validate = sub.add_parser("validate-shield", help="structural analysis of a shield GLB")
    validate.add_argument("glb")
    validate.add_argument("--compare-pre-remesh", help="pre-remeshed GLB to compare against")
    validate.add_argument("--out", help="also write the report to this path")
    validate.set_defaults(func=cmd_validate_shield)

    ingest = sub.add_parser(
        "ingest-rig",
        help=(
            "canonical automatic chain for a rigged humanoid: import, family, compile, "
            "integrity, mesh binding, bind sanity, grip ground truth. "
            "Exit 0 accepted, 2 classified asset FAIL, 1 infrastructure error"
        ),
    )
    ingest.add_argument("glb", help="rigged humanoid as a res:// path inside game/")
    ingest.add_argument("--asset-id", help="stable id for staging and report names")
    ingest.add_argument(
        "--publish",
        help="res:// path to copy the artifact to; only an ACCEPTED chain publishes",
    )
    ingest.add_argument("--policy", default=DEFAULT_POLICY_ID)
    ingest.add_argument("--weapon", default=CERTIFICATION_WEAPON)
    ingest.add_argument("--required-sides", nargs="*", default=["right"])
    ingest.add_argument("--compile-sides", nargs="*", default=["right", "left"])
    ingest.add_argument("--family", help="skeleton family id; omitted means resolve it")
    ingest.add_argument(
        "--skip-import",
        action="store_true",
        help="the project is already imported (breadth runs over existing assets)",
    )
    ingest.add_argument("--godot", help="explicit Godot executable")
    ingest.set_defaults(func=cmd_ingest_rig)

    gate = sub.add_parser("humanoid-gate", help="pre-upload checks for auto-rig candidates")
    gate.add_argument("paths", nargs="*")
    gate.add_argument("--out", help="also write the report to this path")
    gate.set_defaults(func=cmd_humanoid_gate)

    confirm = sub.add_parser(
        "record-human-confirmation",
        help=(
            "OFFLINE: record one human observation that resolves a pre-upload check "
            "this tooling refuses to guess. Bound to the candidate's current bytes"
        ),
    )
    confirm.add_argument("glb", help="the exact candidate the observation was made on")
    confirm.add_argument(
        "--check",
        required=True,
        help="the waivable check being answered, e.g. visual_equivalence",
    )
    confirm.add_argument("--observer", required=True, help="who looked")
    confirm.add_argument(
        "--method", required=True, help="how it was reviewed, e.g. the preview scene and views"
    )
    confirm.add_argument("--statement", required=True, help="what was observed, in their words")
    confirm.add_argument(
        "--observed-on", help="ISO date of the review; defaults to today"
    )
    confirm.add_argument(
        "--ledger", help="alternative ledger path, relative to the repository root"
    )
    confirm.set_defaults(func=cmd_record_human_confirmation)

    static_export = sub.add_parser(
        "static-export",
        help=(
            "OFFLINE: bake a rigged humanoid's rest pose into a static, unrigged GLB "
            "candidate. Exit 0 validated, 3 the export or its validation refused"
        ),
    )
    static_export.add_argument("glb", help="rigged humanoid inside the Godot project")
    static_export.add_argument(
        "--out-name",
        help="output filename inside the candidate root; defaults to a trusted derived name",
    )
    static_export.add_argument(
        "--candidate-root",
        default=str(DEFAULT_CANDIDATE_ROOT),
        help="ignored local directory the candidate and its provenance are written to",
    )
    static_export.add_argument(
        "--no-verify-reimport",
        action="store_true",
        help="skip the Godot re-import check (only for a machine without the engine)",
    )
    static_export.add_argument(
        "--prove-determinism",
        action="store_true",
        help=(
            "additionally bake the asset in one fresh Godot process per caller "
            "context and require byte-identical output; slow, and required before a "
            "provider plan may bind the candidate's digest"
        ),
    )
    static_export.add_argument("--godot", help="explicit Godot executable")
    static_export.set_defaults(func=cmd_static_export)

    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        # Structural, not advisory: a command with no declared risk class does not
        # run at all, so the next command cannot arrive unguarded by omission.
        risk = assert_command_classified(str(args.command))
    except UnclassifiedCommand as exc:
        emit({"error": "COMMAND_RISK_UNDECLARED", "message": str(exc)})
        return 7
    try:
        args.declared_risk = risk.value
        return int(args.func(args) or 0)
    except LiveGateRefusal as exc:
        # A barrier refusal: nothing was sent, no credential was read.
        emit({"error": exc.code, **exc.to_dict()})
        return 4
    except CapabilityRefused as exc:
        # An outbound operation reached the boundary without authorization. Same
        # exit code as a barrier refusal: from an operator's view it is the same
        # answer - nothing was sent.
        emit({"error": exc.code, **exc.to_dict()})
        return 4
    except UnsafeOutputPath as exc:
        emit({"error": exc.code, "message": str(exc), "network_reached": False})
        return 4
    except LiveCallNotAuthorized as exc:
        emit({"error": exc.code, "message": str(exc), "network_reached": False})
        return 4
    except ProviderError as exc:
        emit({"error": "PROVIDER_ERROR", "detail": exc.to_manifest_dict()})
        return 5
    except FileNotFoundError as exc:
        emit({"error": "NOT_FOUND", "message": str(exc)})
        return 6


if __name__ == "__main__":
    sys.exit(main())
