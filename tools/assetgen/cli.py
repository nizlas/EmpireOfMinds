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

from .errors import ProviderError
from .humanoid_gate import evaluate_candidates
from .manifest import JobStatus
from .orchestrator import JobOrchestrator, LiveCallNotAuthorized, provider_factory_for
from .providers import KNOWN_PROVIDERS, PROVIDER_MESHY, PROVIDER_UTHANA
from .providers.base import TaskType
from .rig_ingest import (
    CERTIFICATION_WEAPON,
    DEFAULT_POLICY_ID,
    ingest_rigged_humanoid,
)
from .secret_guard import scrub_obj
from .shield_analysis import analyze_shield_file, compare_pre_and_post_remesh
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


def build_orchestrator(args) -> JobOrchestrator:
    store = JobStore.create(repo_root_from_here())
    factory = provider_factory_for(
        transport=UrllibTransport(),
        retry_policy=RetryPolicy(),
        require_credential=False,
    )
    return JobOrchestrator(store=store, provider_factory=factory, live=bool(args.live))


# --------------------------------------------------------------------- commands


def cmd_auth_smoke(args) -> int:
    orchestrator = build_orchestrator(args)
    results = []
    for name in args.providers or list(KNOWN_PROVIDERS):
        provider = orchestrator.provider_factory(name)
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
        if not args.live:
            results.append(
                {
                    "provider": name,
                    "ok": False,
                    "status": "NOT_ATTEMPTED",
                    "credential_env_var": provider.credential_env_var,
                    "message": "credential present; re-run with --live to probe the provider",
                }
            )
            continue
        try:
            outcome = provider.auth_smoke()
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
    emit({"command": "auth-smoke", "live": bool(args.live), "results": results})
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

    request = build_multiview_request(provider=PROVIDER_MESHY, front_reference=repo_root / front)
    if args.submit:
        manifest = orchestrator.submit(request, force_new_attempt=args.force_new_attempt)
        emit(orchestrator.inspect(manifest.job_id))
        return 0 if manifest.status_enum is not JobStatus.BLOCKED_MISSING_CREDENTIAL else 3
    emit({"command": "shield-multiview", "mode": "dry-run", "plan": orchestrator.dry_run(request)})
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

    manifest = orchestrator.submit(request, force_new_attempt=args.force_new_attempt)
    emit(orchestrator.inspect(manifest.job_id))
    return 0


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
    report = evaluate_candidates(candidates)
    if args.out:
        destination = repo_root / args.out
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(
            json.dumps(report, indent=2, sort_keys=True, default=str) + "\n", encoding="utf-8"
        )
        report["report_path"] = destination.relative_to(repo_root).as_posix()
    emit(report)
    return 0 if report["conclusion"] == "SAFE_INPUT_AVAILABLE" else 3


def cmd_autorig(args) -> int:
    """Auto-rig a humanoid. Gated on the pre-upload checks passing first."""
    orchestrator = build_orchestrator(args)
    repo_root = orchestrator.store.repo_root
    path = Path(args.glb) if Path(args.glb).is_absolute() else repo_root / args.glb
    gate = evaluate_candidates([path])
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
    manifest = orchestrator.submit(request, force_new_attempt=args.force_new_attempt)
    emit(orchestrator.inspect(manifest.job_id))
    return 0


# ----------------------------------------------------------------------- parser


def _add_rig_ingest_flags(node) -> None:
    """Auto-rig downloads run the hand-fixture ingestion chain by default."""
    node.add_argument(
        "--no-ingest-rig",
        action="store_true",
        help="do not run the hand-fixture ingestion chain on a downloaded rig",
    )
    node.add_argument("--godot", help="explicit Godot executable for the ingestion chain")


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
    three_d.set_defaults(func=cmd_shield_3d)

    autorig = sub.add_parser("autorig", help="auto-rig a humanoid after the pre-upload gate")
    autorig.add_argument("glb")
    autorig.add_argument("--name", help="character name at the provider; defaults to the filename")
    autorig.add_argument("--submit", action="store_true", help="PAID: upload and rig")
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

    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return int(args.func(args) or 0)
    except LiveCallNotAuthorized as exc:
        emit({"error": "LIVE_NOT_AUTHORIZED", "message": str(exc)})
        return 4
    except ProviderError as exc:
        emit({"error": "PROVIDER_ERROR", "detail": exc.to_manifest_dict()})
        return 5
    except FileNotFoundError as exc:
        emit({"error": "NOT_FOUND", "message": str(exc)})
        return 6


if __name__ == "__main__":
    sys.exit(main())
