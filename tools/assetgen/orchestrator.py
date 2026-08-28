"""Job orchestration: submit, status, poll, resume, download, inspect, cancel, dry-run.

The orchestrator is provider-agnostic. It owns three guarantees:

1. **No double spend.** A job's identity is its idempotency key. If a manifest
   with that key already holds a provider task id, `submit` resumes it instead of
   creating a second paid task. A genuinely new attempt requires an explicit
   `force_new_attempt`, which changes the key.
2. **No lost artifact.** Provider output URLs are signed and short-lived, so a
   successful poll downloads immediately and records local paths plus SHA-256.
3. **No silent visual claim.** `visual_status` stays `PENDING_USER_REVIEW`;
   nothing in this module may set it to anything else.
"""

from __future__ import annotations

import time
from dataclasses import dataclass
from pathlib import Path
from typing import Callable
from urllib.parse import urlsplit

from . import CONTRACT_VERSION
from .artifact_paths import resolve_within, trusted_artifact_name
from .capability import OperationClass
from .capability import require as require_capability
from .errors import ErrorKind, ProviderError
from .manifest import (
    JobManifest,
    JobStatus,
    OutputRef,
    compute_idempotency_key,
    describe_input,
    prompt_hash,
    relative_to_repo,
    sha256_file,
    utc_now_iso,
)
from .live_gate import (
    LIVE_PROVIDER_MODE_REQUIRED,
    PROVIDER_SUBMISSION_OUTCOME_UNKNOWN,
    LiveGateRefusal,
)
from .providers.base import AssetProvider, JobRequest, ProviderTaskState, TaskStatus, TaskType
from .secret_guard import MissingCredentialError
from .store import JobStore

DEFAULT_POLL_INTERVAL_S = 10.0
DEFAULT_POLL_TIMEOUT_S = 1800.0
#: Attempt cap for polling, on top of the wall-clock deadline. Mirrors the value
#: the provider plan declares, so what was approved is what runs.
DEFAULT_MAX_POLL_ATTEMPTS = 60

STATUS_FROM_PROVIDER: dict[TaskStatus, JobStatus] = {
    TaskStatus.PENDING: JobStatus.SUBMITTED,
    TaskStatus.IN_PROGRESS: JobStatus.IN_PROGRESS,
    TaskStatus.SUCCEEDED: JobStatus.SUCCEEDED,
    TaskStatus.FAILED: JobStatus.FAILED,
    TaskStatus.CANCELED: JobStatus.CANCELED,
}


class LiveCallNotAuthorized(RuntimeError):
    """Raised when a network operation is attempted without full authorization."""

    def __init__(self, message: str, *, code: str = LIVE_PROVIDER_MODE_REQUIRED) -> None:
        self.code = code
        super().__init__(message)


@dataclass
class JobOrchestrator:
    """Provider-agnostic job lifecycle.

    AUTHORITY IS NOT A BOOLEAN HERE ANY MORE. The review measured
    `JobOrchestrator(live=True, opt_in=True).submit(...)` building a paid request
    with no plan confirmation and no ledger claim, because those two flags carried
    the whole authority and barrier 3 lived above them in the CLI. The flags are
    gone. Non-paid network operations mint a capability from `authorization`, and
    paid creates must be HANDED a capability that already binds a confirmed plan
    digest and an acquired claim - which only `paid_executor` can produce.
    """

    store: JobStore
    provider_factory: Callable[[str], AssetProvider]
    #: The gate result for this run. Mints capabilities for poll, download and
    #: cancel. It cannot mint a paid capability, by construction.
    authorization: object | None = None
    sleep: Callable[[float], None] = time.sleep
    monotonic: Callable[[], float] = time.monotonic
    #: Which approved plan a paid task belongs to, for the ledger only. Never
    #: consulted to grant permission - the capability is the permission.
    plan_digest: str = ""

    # ------------------------------------------------------------------- identity

    def build_manifest(self, request: JobRequest, *, attempt_id: str = "a1") -> JobManifest:
        """Compute the durable identity of a request without contacting anyone."""
        provider = self.provider_factory(request.provider)
        inputs = [
            describe_input(self.store.repo_root, item.path, order=item.order, role=item.role)
            for item in sorted(request.inputs, key=lambda i: i.order)
        ]
        model_version = provider.model_version_for(request)
        prompt_digest = prompt_hash(request.prompt_text) if request.prompt_text else ""
        key = compute_idempotency_key(
            provider=request.provider,
            task_type=request.task_type.value,
            provider_model_version=model_version,
            contract_version=CONTRACT_VERSION,
            prompt_hash_value=prompt_digest,
            ordered_input_hashes=[item.sha256 for item in inputs],
            generation_parameters=dict(request.parameters),
            attempt_id=attempt_id,
        )
        label = request.label or request.task_type.value
        job_id = f"{request.provider}_{label}_{attempt_id}_{key[:12]}"
        return JobManifest(
            job_id=job_id,
            provider=request.provider,
            task_type=request.task_type.value,
            provider_endpoint=provider.endpoint_for(request.task_type),
            idempotency_key=key,
            attempt_id=attempt_id,
            provider_model_version=model_version,
            prompt_version=request.prompt_version,
            prompt_hash=prompt_digest,
            prompt_text=request.prompt_text,
            inputs=inputs,
            request_parameters=dict(request.parameters),
        )

    # -------------------------------------------------------------------- dry-run

    def dry_run(self, request: JobRequest, *, attempt_id: str = "a1") -> dict:
        """Full local validation and a plan. Never touches the network."""
        provider = self.provider_factory(request.provider)
        manifest = self.build_manifest(request, attempt_id=attempt_id)
        plan: dict = {
            "job_id": manifest.job_id,
            "provider": manifest.provider,
            "task_type": manifest.task_type,
            "provider_endpoint": manifest.provider_endpoint,
            "provider_model_version": manifest.provider_model_version,
            "contract_version": manifest.contract_version,
            "idempotency_key": manifest.idempotency_key,
            "prompt_hash": manifest.prompt_hash,
            "inputs": [
                {"order": i.order, "role": i.role, "path": i.relative_path, "sha256": i.sha256}
                for i in manifest.inputs
            ],
            "credential_env_var": provider.credential_env_var,
            "credential_present": provider.has_credential,
            "would_submit": False,
        }
        try:
            provider.validate_request(request)
            plan["validation"] = "OK"
        except ProviderError as exc:
            plan["validation"] = "REJECTED"
            plan["validation_error"] = exc.to_manifest_dict()
            return plan

        plan["submission"] = provider.describe_submission(request)
        existing = self.store.find_by_idempotency_key(manifest.idempotency_key)
        if existing is not None:
            plan["existing_job"] = {
                "job_id": existing.job_id,
                "status": existing.status,
                "provider_task_id": existing.provider_task_id,
                "resumable": existing.resumable,
            }
            plan["would_submit"] = not existing.resumable
        else:
            plan["would_submit"] = True
        if not provider.has_credential:
            plan["would_submit"] = False
            plan["blocked"] = JobStatus.BLOCKED_MISSING_CREDENTIAL.value
        return plan

    # --------------------------------------------------------------------- submit

    def submit(
        self,
        request: JobRequest,
        *,
        capability=None,
        force_new_attempt: bool = False,
        attempt_id: str | None = None,
    ) -> JobManifest:
        """Create the remote task, or resume an identical one that already exists.

        `capability` is mandatory in effect: without a paid capability nothing is
        sent. It defaults to `None` so the refusal is a classified
        `PROVIDER_CAPABILITY_REQUIRED` rather than a `TypeError`, which keeps the
        machine-readable error model intact for callers.
        """
        resolved_attempt = attempt_id or ("a1" if not force_new_attempt else self._next_attempt_id(request))
        manifest = self.build_manifest(request, attempt_id=resolved_attempt)

        resumable = self.store.find_resumable(manifest.idempotency_key)
        if resumable is not None and not force_new_attempt:
            resumable.note(
                "submit() found an identical job with a provider task id; resuming instead of paying again"
            )
            self.store.save(resumable)
            return self.resume(resumable.job_id)

        provider = self.provider_factory(request.provider)
        try:
            provider.validate_request(request)
        except ProviderError as exc:
            manifest.status = JobStatus.BLOCKED_PREFLIGHT.value
            manifest.error = exc.to_manifest_dict()
            manifest.note("request rejected by local provider-contract validation; nothing was sent")
            self.store.save(manifest)
            return manifest

        # Authorization comes BEFORE the credential probe. A run that is going to
        # be refused must never have looked at a key, so that a refusal has
        # nothing to leak and cannot depend on whether a key happens to be set.
        capability = require_capability(
            capability,
            provider=provider.name,
            operation=provider.paid_operation_name(request),
            operation_class=OperationClass.PAID_CREATE,
            endpoint=provider.endpoint_identity(),
        )

        # An earlier attempt at this exact identity whose outcome is UNKNOWN is a
        # hard stop. The review (HIGH 5) measured the old code going from one
        # create call to two here: the ambiguity was recorded in the manifest and
        # then nothing read it, and `find_resumable` saw no task id because there
        # was none. Resolving an UNKNOWN is a human act against the provider's own
        # records, not something a rerun may decide.
        unknown = self.store.find_unknown_outcome(manifest.idempotency_key)
        if unknown is not None and not force_new_attempt:
            raise LiveGateRefusal(
                PROVIDER_SUBMISSION_OUTCOME_UNKNOWN,
                f"job {unknown.job_id} already attempted this exact work and its outcome is "
                "UNKNOWN: the provider may hold a task that was paid for. Submitting again "
                "could pay twice. Check the provider's own task list, then reconcile that job "
                "by hand. Nothing was sent.",
                operation="submit",
                detail={
                    "existing_job_id": unknown.job_id,
                    "idempotency_key": manifest.idempotency_key,
                },
            )

        if not provider.has_credential:
            manifest.status = JobStatus.BLOCKED_MISSING_CREDENTIAL.value
            manifest.error = {
                "kind": JobStatus.BLOCKED_MISSING_CREDENTIAL.value,
                "provider": provider.name,
                "message": (
                    f"{provider.credential_env_var} is not set; adapter validated the request "
                    "but no provider call was made and no task id exists"
                ),
                "retryable": False,
            }
            manifest.note("no credential; job recorded as blocked without contacting the provider")
            self.store.save(manifest)
            return manifest

        manifest.status = JobStatus.CREATED.value
        manifest.started_at = utc_now_iso()
        self.store.save(manifest)  # persist BEFORE spending, so a crash cannot orphan a paid task
        if self.plan_digest:
            self.store.update_submission(
                self.plan_digest, job_id=manifest.job_id, state="CREATE_IN_FLIGHT"
            )

        # Reserve the ticket BEFORE the request goes out. If this process dies mid
        # flight the capability is already unusable, so a rerun in the same process
        # cannot reuse it, and the on-disk claim stops a rerun in a new one.
        capability.reserve()
        try:
            task_id, response = provider.submit(request, capability)
        except ProviderError as exc:
            capability.consume()
            manifest.status = JobStatus.FAILED.value
            manifest.error = exc.to_manifest_dict()
            manifest.finished_at = utc_now_iso()
            # A retryable kind on a CREATE means the outcome is unknown, not that
            # it failed: the provider may have accepted the task and lost the
            # response. Saying "failed" here would invite a rerun that pays
            # twice, so the ambiguity is recorded as its own state and the
            # operator resolves it by looking at the provider, not by retrying.
            ambiguous = exc.retryable
            manifest.submission_outcome = "UNKNOWN" if ambiguous else "NOT_CREATED"
            manifest.note(
                "submit failed with an ambiguous transport/5xx outcome; NO automatic retry was "
                "made because a second create could pay twice. Check the provider for a task "
                "before deciding anything."
                if ambiguous
                else "submit was rejected before any task was created; no provider task id exists"
            )
            self.store.save(manifest)
            if self.plan_digest:
                self.store.update_submission(
                    self.plan_digest,
                    job_id=manifest.job_id,
                    state="OUTCOME_UNKNOWN" if ambiguous else "NOT_CREATED",
                    error_kind=exc.kind.value,
                )
            return manifest

        capability.consume()
        manifest.provider_task_id = task_id
        manifest.status = JobStatus.SUBMITTED.value
        manifest.submission_outcome = "CREATED"
        manifest.note(f"provider task created: {task_id}")
        # The task id is durable BEFORE polling starts, so an interrupted run
        # resumes this exact paid task instead of creating another one.
        self.store.save(manifest)
        if self.plan_digest:
            self.store.update_submission(
                self.plan_digest,
                job_id=manifest.job_id,
                provider_task_id=task_id,
                state="CREATED",
            )
        self._write_response_snapshot(manifest, "submit", response)
        self.store.save(manifest)
        return manifest

    # --------------------------------------------------------------------- status

    def status(self, job_id: str) -> JobManifest:
        """Local view only. Free, offline, and never mutates the job."""
        return self.store.load(job_id)

    # ----------------------------------------------------------------------- poll

    def poll(
        self,
        job_id: str,
        *,
        timeout_s: float = DEFAULT_POLL_TIMEOUT_S,
        interval_s: float = DEFAULT_POLL_INTERVAL_S,
        download: bool = True,
        max_attempts: int = DEFAULT_MAX_POLL_ATTEMPTS,
    ) -> JobManifest:
        """Poll an existing task until terminal, then download immediately.

        Polling is free and creates nothing, so it may retry - but only a bounded
        number of times. Both a wall-clock deadline and an attempt cap apply, so
        neither a provider that answers instantly with a retryable error nor one
        that never answers can turn into an unbounded loop.
        """
        manifest = self.store.load(job_id)
        if manifest.provider_task_id is None:
            raise ProviderError(
                ErrorKind.INVALID_REQUEST,
                f"Job {job_id} has no provider task id; submit it first",
                provider=manifest.provider,
            )
        provider = self.provider_factory(manifest.provider)
        capability = self._mint("poll", provider, OperationClass.NETWORK_READ)
        task_type = TaskType(manifest.task_type)
        deadline = self.monotonic() + timeout_s
        attempts = 0

        while True:
            attempts += 1
            try:
                state = provider.fetch(task_type, manifest.provider_task_id, capability)
            except ProviderError as exc:
                manifest.retry_count += 1
                manifest.error = exc.to_manifest_dict()
                if attempts >= max(1, max_attempts):
                    manifest.note(
                        f"poll stopped after the {max_attempts}-attempt cap; the provider task id "
                        "is preserved so this exact job can be resumed without paying again"
                    )
                    self.store.save(manifest)
                    return manifest
                if not exc.retryable or self.monotonic() >= deadline:
                    manifest.note("poll stopped on a non-retryable error; task id preserved for resume")
                    self.store.save(manifest)
                    return manifest
                manifest.note("poll hit a retryable error; keeping the same task id")
                self.store.save(manifest)
                self.sleep(interval_s)
                continue

            self._apply_state(manifest, state)
            self.store.save(manifest)

            if state.terminal:
                break
            if attempts >= max(1, max_attempts):
                manifest.note(
                    f"poll reached the {max_attempts}-attempt cap while the task was still "
                    "running; the provider task id is preserved for resume"
                )
                self.store.save(manifest)
                return manifest
            if self.monotonic() >= deadline:
                manifest.note(
                    f"poll timed out locally after {timeout_s}s; the provider task is still live "
                    "and can be resumed with the stored task id"
                )
                self.store.save(manifest)
                return manifest
            self.sleep(interval_s)

        if manifest.status_enum is JobStatus.SUCCEEDED and download:
            return self.download(job_id)
        return manifest

    # --------------------------------------------------------------------- resume

    def resume(
        self,
        job_id: str,
        *,
        timeout_s: float = DEFAULT_POLL_TIMEOUT_S,
        interval_s: float = DEFAULT_POLL_INTERVAL_S,
    ) -> JobManifest:
        """Continue an interrupted job from the stored provider task id."""
        manifest = self.store.load(job_id)
        if manifest.provider_task_id is None:
            raise ProviderError(
                ErrorKind.INVALID_REQUEST,
                f"Job {job_id} was never submitted, so there is nothing to resume. "
                "Run submit (or dry-run first) instead.",
                provider=manifest.provider,
            )
        if manifest.status_enum is JobStatus.DOWNLOADED and self._outputs_intact(manifest):
            manifest.note("resume found all outputs already downloaded and verified; nothing to do")
            self.store.save(manifest)
            return manifest
        if manifest.status_enum is JobStatus.SUCCEEDED:
            # Signed URLs may have expired; re-poll to refresh them, then download.
            return self.poll(job_id, timeout_s=timeout_s, interval_s=interval_s, download=True)
        return self.poll(job_id, timeout_s=timeout_s, interval_s=interval_s, download=True)

    # ------------------------------------------------------------------- download

    def download(self, job_id: str, *, only_kinds: tuple[str, ...] | None = None) -> JobManifest:
        """Fetch every offered artifact to disk and hash it."""
        manifest = self.store.load(job_id)
        if not manifest.output_urls:
            raise ProviderError(
                ErrorKind.MISSING_OUTPUT,
                f"Job {job_id} has no recorded output URLs; poll it first",
                provider=manifest.provider,
            )
        provider = self.provider_factory(manifest.provider)
        capability = self._mint("download", provider, OperationClass.NETWORK_READ)
        outputs_dir = self.store.outputs_dir(job_id)
        stored: list[OutputRef] = []

        for kind, entry in sorted(manifest.output_urls.items()):
            if only_kinds is not None and kind not in only_kinds:
                continue
            url = entry.get("url") if isinstance(entry, dict) else None
            if not url:
                continue
            # The local name is built from the job id and our own neutral `kind`.
            # Whatever the provider suggested is metadata only: the review turned
            # that field into a write to C:\Windows\Temp, and no amount of
            # sanitising a hostile string is as safe as not using it.
            filename = trusted_artifact_name(
                run_id=manifest.job_id, kind=kind, extension=_extension_for(kind, url)
            )
            destination = resolve_within(outputs_dir, filename)
            try:
                size = provider.download(url, destination, capability)
            except ProviderError as exc:
                manifest.error = exc.to_manifest_dict()
                manifest.note(f"download of {kind} failed ({exc.kind.value}); other artifacts kept")
                self.store.save(manifest)
                if exc.kind is ErrorKind.EXPIRED_URL:
                    return manifest
                continue
            stored.append(
                OutputRef(
                    kind=kind,
                    relative_path=relative_to_repo(self.store.repo_root, destination),
                    sha256=sha256_file(destination),
                    size_bytes=size,
                    source_url_host=urlsplit(url).netloc,
                    provider_suggested_filename=str(
                        entry.get("provider_suggested_filename", "")
                        if isinstance(entry, dict)
                        else ""
                    ),
                )
            )

        by_kind = {ref.kind: ref for ref in manifest.outputs}
        for ref in stored:
            by_kind[ref.kind] = ref
        manifest.outputs = [by_kind[k] for k in sorted(by_kind)]

        if manifest.outputs:
            manifest.status = JobStatus.DOWNLOADED.value
            manifest.note(f"stored {len(stored)} artifact(s) locally with SHA-256 recorded")
        self.store.save(manifest)
        return manifest

    # -------------------------------------------------------------------- inspect

    def inspect(self, job_id: str) -> dict:
        """Offline report: identity, spend, artifacts on disk, integrity."""
        manifest = self.store.load(job_id)
        artifacts = []
        for ref in manifest.outputs:
            path = self.store.repo_root / ref.relative_path
            present = path.is_file()
            artifacts.append(
                {
                    "kind": ref.kind,
                    "relative_path": ref.relative_path,
                    "size_bytes": ref.size_bytes,
                    "sha256": ref.sha256,
                    "present_on_disk": present,
                    "hash_matches": (sha256_file(path) == ref.sha256) if present else False,
                }
            )
        return {
            "job_id": manifest.job_id,
            "provider": manifest.provider,
            "task_type": manifest.task_type,
            "provider_task_id": manifest.provider_task_id,
            "provider_model_version": manifest.provider_model_version,
            "contract_version": manifest.contract_version,
            "idempotency_key": manifest.idempotency_key,
            "status": manifest.status,
            "submission_outcome": manifest.submission_outcome,
            "progress": manifest.progress,
            "retry_count": manifest.retry_count,
            "error": manifest.error,
            "reported_credits": manifest.reported_credits,
            "visual_status": manifest.visual_status,
            "manifest_path": relative_to_repo(
                self.store.repo_root, self.store.job_dir(job_id) / "manifest.json"
            ),
            "artifacts": artifacts,
            "structural_validation": manifest.structural_validation,
            "resumable": manifest.resumable,
        }

    # --------------------------------------------------------------------- cancel

    def cancel(self, job_id: str) -> JobManifest:
        """Explicit, separate command. Never invoked by retry or error handling."""
        manifest = self.store.load(job_id)
        if manifest.provider_task_id is None:
            raise ProviderError(
                ErrorKind.INVALID_REQUEST,
                f"Job {job_id} has no provider task id to cancel",
                provider=manifest.provider,
            )
        provider = self.provider_factory(manifest.provider)
        capability = self._mint("cancel", provider, OperationClass.REMOTE_MUTATION)
        response = provider.cancel(
            TaskType(manifest.task_type), manifest.provider_task_id, capability
        )
        manifest.status = JobStatus.CANCELED.value
        manifest.finished_at = utc_now_iso()
        manifest.note("cancelled explicitly by operator command")
        self._write_response_snapshot(manifest, "cancel", response)
        self.store.save(manifest)
        return manifest

    # ------------------------------------------------------------------ internals

    def _mint(self, operation: str, provider, operation_class):
        """Mint the capability for one non-paid network operation.

        A run with no authorization at all is refused here, so an orchestrator
        constructed outside the CLI behaves identically to one inside it. The gate
        applies barriers 1 and 2 and the https/endpoint requirement; this method
        adds nothing of its own, which is the point - there is one policy.
        """
        if self.authorization is None:
            raise LiveGateRefusal(
                LIVE_PROVIDER_MODE_REQUIRED,
                f"'{operation}' would reach {provider.name} and this run holds no live "
                "authorization. Re-run through the CLI with --live and the machine opt-in. "
                "No credential was read.",
                operation=operation,
            )
        return self.authorization.mint_network_capability(
            provider=provider.name,
            operation=operation,
            endpoint=provider.endpoint_identity(),
            operation_class=operation_class,
        )

    def _next_attempt_id(self, request: JobRequest) -> str:
        """Pick the next unused attempt id so a forced retry is a distinct job."""
        for index in range(1, 100):
            candidate = f"a{index}"
            manifest = self.build_manifest(request, attempt_id=candidate)
            if self.store.find_by_idempotency_key(manifest.idempotency_key) is None:
                return candidate
        raise RuntimeError("Exhausted attempt ids a1..a99 for this request")

    def _apply_state(self, manifest: JobManifest, state: ProviderTaskState) -> None:
        manifest.status = STATUS_FROM_PROVIDER[state.status].value
        manifest.progress = state.progress
        if state.reported_credits is not None:
            manifest.reported_credits = state.reported_credits
        if state.status is TaskStatus.FAILED:
            manifest.error = {
                "kind": ErrorKind.PROVIDER_FAILURE.value,
                "provider": manifest.provider,
                "http_status": None,
                "message": state.error_message or "provider reported FAILED without a message",
                "retryable": False,
            }
        if state.terminal:
            manifest.finished_at = utc_now_iso()
        if state.outputs:
            manifest.output_urls = {
                out.kind: {
                    "url": out.url,
                    # Recorded for the audit trail and never joined to a path.
                    "provider_suggested_filename": out.suggested_filename,
                }
                for out in state.outputs
            }
        self._write_response_snapshot(manifest, f"fetch_{manifest.progress:03d}", state.raw)

    def _outputs_intact(self, manifest: JobManifest) -> bool:
        if not manifest.outputs:
            return False
        for ref in manifest.outputs:
            path = self.store.repo_root / ref.relative_path
            if not path.is_file() or sha256_file(path) != ref.sha256:
                return False
        return True

    def _write_response_snapshot(self, manifest: JobManifest, label: str, payload: dict) -> None:
        import json

        from .secret_guard import scrub_obj

        directory = self.store.response_dir(manifest.job_id)
        directory.mkdir(parents=True, exist_ok=True)
        target = directory / f"{label}.json"
        target.write_text(
            json.dumps(scrub_obj(payload), indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )


#: Neutral artifact kind -> the extension our local file gets. Derived from OUR
#: vocabulary, so a provider cannot choose the extension either.
KIND_EXTENSIONS: dict[str, str] = {
    "rigged_character_glb": "glb",
    "model_glb": "glb",
    "model_fbx": "fbx",
    "model_obj": "obj",
    "model_usdz": "usdz",
    "thumbnail": "png",
    "texture": "png",
}


def _extension_for(kind: str, url: str) -> str:
    """Pick an extension from our own kind table, falling back conservatively.

    The URL is consulted only as a last resort and only for a short alphanumeric
    suffix from a fixed allow-list, so a crafted URL cannot choose `.ps1`.
    """
    known = KIND_EXTENSIONS.get(str(kind))
    if known:
        return known
    allowed = {"glb", "gltf", "fbx", "obj", "usdz", "png", "jpg", "jpeg", "webp", "zip", "mp4"}
    suffix = Path(urlsplit(str(url)).path).suffix.lstrip(".").lower()
    return suffix if suffix in allowed else "bin"


def provider_factory_for(
    *,
    transport,
    retry_policy=None,
    require_credential: bool = False,
    base_url: str = "",
) -> Callable[[str], AssetProvider]:
    """Build a memoising factory so one CLI run reuses one adapter per provider."""
    from .providers import build_provider

    cache: dict[str, AssetProvider] = {}

    def factory(name: str) -> AssetProvider:
        if name not in cache:
            try:
                cache[name] = build_provider(
                    name,
                    transport=transport,
                    retry_policy=retry_policy,
                    require_credential=require_credential,
                    base_url=base_url,
                )
            except MissingCredentialError:
                raise
        return cache[name]

    return factory
