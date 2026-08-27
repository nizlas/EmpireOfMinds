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
from .providers.base import AssetProvider, JobRequest, ProviderTaskState, TaskStatus, TaskType
from .secret_guard import MissingCredentialError
from .store import JobStore

DEFAULT_POLL_INTERVAL_S = 10.0
DEFAULT_POLL_TIMEOUT_S = 1800.0

STATUS_FROM_PROVIDER: dict[TaskStatus, JobStatus] = {
    TaskStatus.PENDING: JobStatus.SUBMITTED,
    TaskStatus.IN_PROGRESS: JobStatus.IN_PROGRESS,
    TaskStatus.SUCCEEDED: JobStatus.SUCCEEDED,
    TaskStatus.FAILED: JobStatus.FAILED,
    TaskStatus.CANCELED: JobStatus.CANCELED,
}


class LiveCallNotAuthorized(RuntimeError):
    """Raised when a network operation is attempted without the --live opt-in."""


@dataclass
class JobOrchestrator:
    store: JobStore
    provider_factory: Callable[[str], AssetProvider]
    #: Every network-touching operation refuses to run unless this is True.
    live: bool = False
    sleep: Callable[[float], None] = time.sleep
    monotonic: Callable[[], float] = time.monotonic

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
        force_new_attempt: bool = False,
        attempt_id: str | None = None,
    ) -> JobManifest:
        """Create the remote task, or resume an identical one that already exists."""
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

        self._require_live("submit")

        manifest.status = JobStatus.CREATED.value
        manifest.started_at = utc_now_iso()
        self.store.save(manifest)  # persist BEFORE spending, so a crash cannot orphan a paid task

        try:
            task_id, response = provider.submit(request)
        except ProviderError as exc:
            manifest.status = JobStatus.FAILED.value
            manifest.error = exc.to_manifest_dict()
            manifest.finished_at = utc_now_iso()
            manifest.note("submit failed; no provider task id was returned")
            self.store.save(manifest)
            return manifest

        manifest.provider_task_id = task_id
        manifest.status = JobStatus.SUBMITTED.value
        manifest.note(f"provider task created: {task_id}")
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
    ) -> JobManifest:
        """Poll an existing task until terminal, then download immediately."""
        manifest = self.store.load(job_id)
        if manifest.provider_task_id is None:
            raise ProviderError(
                ErrorKind.INVALID_REQUEST,
                f"Job {job_id} has no provider task id; submit it first",
                provider=manifest.provider,
            )
        self._require_live("poll")
        provider = self.provider_factory(manifest.provider)
        task_type = TaskType(manifest.task_type)
        deadline = self.monotonic() + timeout_s

        while True:
            try:
                state = provider.fetch(task_type, manifest.provider_task_id)
            except ProviderError as exc:
                manifest.retry_count += 1
                manifest.error = exc.to_manifest_dict()
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
        self._require_live("download")
        provider = self.provider_factory(manifest.provider)
        outputs_dir = self.store.outputs_dir(job_id)
        stored: list[OutputRef] = []

        for kind, entry in sorted(manifest.output_urls.items()):
            if only_kinds is not None and kind not in only_kinds:
                continue
            url = entry.get("url") if isinstance(entry, dict) else None
            filename = entry.get("filename") if isinstance(entry, dict) else None
            if not url or not filename:
                continue
            destination = outputs_dir / filename
            try:
                size = provider.download(url, destination)
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
        self._require_live("cancel")
        provider = self.provider_factory(manifest.provider)
        response = provider.cancel(TaskType(manifest.task_type), manifest.provider_task_id)
        manifest.status = JobStatus.CANCELED.value
        manifest.finished_at = utc_now_iso()
        manifest.note("cancelled explicitly by operator command")
        self._write_response_snapshot(manifest, "cancel", response)
        self.store.save(manifest)
        return manifest

    # ------------------------------------------------------------------ internals

    def _require_live(self, operation: str) -> None:
        if not self.live:
            raise LiveCallNotAuthorized(
                f"'{operation}' needs a real provider call. Re-run with --live to authorize it. "
                "The default test suite must never reach a provider."
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
                out.kind: {"url": out.url, "filename": out.suggested_filename}
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


def provider_factory_for(
    *,
    transport,
    retry_policy=None,
    require_credential: bool = False,
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
                )
            except MissingCredentialError:
                raise
        return cache[name]

    return factory
