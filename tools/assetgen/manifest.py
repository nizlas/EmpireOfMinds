"""Local job manifests, hashing and the idempotency contract.

A manifest is the durable record of one external job. Signed provider URLs are
short-lived (Meshy retains assets for 3 days), so a manifest stores the
*relative local path* of every artifact plus its SHA-256, and the URL only as
provenance. Re-reading a manifest must be enough to resume, verify or audit a
job without any provider call.
"""

from __future__ import annotations

import hashlib
import json
import time
from dataclasses import asdict, dataclass, field
from enum import Enum
from pathlib import Path

from . import CONTRACT_VERSION
from .secret_guard import scrub_obj

MANIFEST_SCHEMA_VERSION = 1
MANIFEST_FILENAME = "manifest.json"


class JobStatus(str, Enum):
    CREATED = "CREATED"                # manifest written, nothing submitted
    DRY_RUN = "DRY_RUN"                # plan only; no provider contact ever
    SUBMITTED = "SUBMITTED"            # provider task id obtained
    IN_PROGRESS = "IN_PROGRESS"
    SUCCEEDED = "SUCCEEDED"            # provider finished; outputs not yet local
    DOWNLOADED = "DOWNLOADED"          # outputs stored locally and hashed
    FAILED = "FAILED"
    CANCELED = "CANCELED"
    BLOCKED_MISSING_CREDENTIAL = "BLOCKED_MISSING_CREDENTIAL"
    BLOCKED_AMBIGUOUS_REFERENCE = "BLOCKED_AMBIGUOUS_REFERENCE"
    BLOCKED_PREFLIGHT = "BLOCKED_PREFLIGHT"


#: Statuses from which `resume` can make progress without a new paid job.
RESUMABLE_STATUSES: frozenset[JobStatus] = frozenset(
    {JobStatus.SUBMITTED, JobStatus.IN_PROGRESS, JobStatus.SUCCEEDED}
)

#: The visual verdict is never set by tooling. Only a human sets it, and this
#: slice always leaves it pending.
VISUAL_PENDING = "PENDING_USER_REVIEW"


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def canonical_json(value: object) -> str:
    """Stable serialisation used for every hash so keys cannot reorder a digest."""
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)


def prompt_hash(prompt_text: str) -> str:
    """Hash of the exact prompt bytes, whitespace-normalised at line level.

    Trailing whitespace and line-ending differences must not count as a
    different prompt, otherwise every editor round-trip would look like a new
    paid job.
    """
    normalised = "\n".join(line.rstrip() for line in prompt_text.strip().splitlines())
    return sha256_bytes(normalised.encode("utf-8"))


@dataclass(frozen=True)
class InputRef:
    """One ordered input file. Order matters: it is part of the idempotency key."""

    order: int
    role: str
    relative_path: str
    sha256: str
    size_bytes: int


@dataclass(frozen=True)
class OutputRef:
    """One downloaded artifact, stored locally rather than trusted to a URL."""

    kind: str
    relative_path: str
    sha256: str
    size_bytes: int
    source_url_host: str = ""


def compute_idempotency_key(
    *,
    provider: str,
    task_type: str,
    provider_model_version: str,
    contract_version: str,
    prompt_hash_value: str,
    ordered_input_hashes: list[str],
    generation_parameters: dict,
    attempt_id: str,
) -> str:
    """The identity of a job.

    Two jobs with the same key are the same paid work. `attempt_id` is included
    so that an explicit `--force-new-attempt` produces a genuinely different
    key rather than silently resuming or silently double-paying.
    """
    payload = {
        "provider": provider,
        "task_type": task_type,
        "provider_model_version": provider_model_version,
        "contract_version": contract_version,
        "prompt_hash": prompt_hash_value,
        "input_hashes": list(ordered_input_hashes),
        "generation_parameters": generation_parameters,
        "attempt_id": attempt_id,
    }
    return sha256_bytes(canonical_json(payload).encode("utf-8"))


@dataclass
class JobManifest:
    job_id: str
    provider: str
    task_type: str
    provider_endpoint: str
    idempotency_key: str
    attempt_id: str = "a1"
    schema_version: int = MANIFEST_SCHEMA_VERSION
    contract_version: str = CONTRACT_VERSION
    provider_task_id: str | None = None
    provider_model_version: str = ""
    prompt_version: str = ""
    prompt_hash: str = ""
    prompt_text: str = ""
    inputs: list[InputRef] = field(default_factory=list)
    request_parameters: dict = field(default_factory=dict)
    status: str = JobStatus.CREATED.value
    progress: int = 0
    retry_count: int = 0
    error: dict | None = None
    reported_credits: int | None = None
    output_urls: dict = field(default_factory=dict)
    outputs: list[OutputRef] = field(default_factory=list)
    structural_validation: dict = field(default_factory=dict)
    visual_status: str = VISUAL_PENDING
    created_at: str = ""
    started_at: str | None = None
    finished_at: str | None = None
    updated_at: str = ""
    notes: list[str] = field(default_factory=list)

    def __post_init__(self) -> None:
        stamp = utc_now_iso()
        if not self.created_at:
            self.created_at = stamp
        if not self.updated_at:
            self.updated_at = stamp

    @property
    def status_enum(self) -> JobStatus:
        return JobStatus(self.status)

    @property
    def resumable(self) -> bool:
        return self.provider_task_id is not None and self.status_enum in RESUMABLE_STATUSES

    def note(self, text: str) -> None:
        self.notes.append(f"{utc_now_iso()} {text}")

    def to_dict(self) -> dict:
        raw = asdict(self)
        # request_parameters and any provider text may echo user input; scrub the
        # whole document rather than trusting each call site.
        return scrub_obj(raw)  # type: ignore[return-value]

    @classmethod
    def from_dict(cls, data: dict) -> "JobManifest":
        known = {f for f in cls.__dataclass_fields__}  # noqa: SLF001 - dataclass API
        payload = {k: v for k, v in data.items() if k in known}
        payload["inputs"] = [InputRef(**item) for item in data.get("inputs", [])]
        payload["outputs"] = [OutputRef(**item) for item in data.get("outputs", [])]
        return cls(**payload)


def utc_now_iso() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def describe_input(repo_root: Path, path: Path, *, order: int, role: str) -> InputRef:
    resolved = path.resolve()
    return InputRef(
        order=order,
        role=role,
        relative_path=relative_to_repo(repo_root, resolved),
        sha256=sha256_file(resolved),
        size_bytes=resolved.stat().st_size,
    )


def relative_to_repo(repo_root: Path, path: Path) -> str:
    """Repo-relative POSIX path, or an absolute POSIX path when outside the repo."""
    try:
        return path.resolve().relative_to(repo_root.resolve()).as_posix()
    except ValueError:
        return path.resolve().as_posix()


def write_manifest(directory: Path, manifest: JobManifest) -> Path:
    directory.mkdir(parents=True, exist_ok=True)
    manifest.updated_at = utc_now_iso()
    target = directory / MANIFEST_FILENAME
    payload = json.dumps(manifest.to_dict(), indent=2, sort_keys=True) + "\n"
    # Write-then-replace so an interrupted run cannot leave a half manifest that
    # would lose a provider task id we have already paid for.
    temp = target.with_suffix(".json.tmp")
    temp.write_text(payload, encoding="utf-8")
    temp.replace(target)
    return target


def read_manifest(directory: Path) -> JobManifest:
    target = directory / MANIFEST_FILENAME
    data = json.loads(target.read_text(encoding="utf-8"))
    version = int(data.get("schema_version", 0))
    if version != MANIFEST_SCHEMA_VERSION:
        raise ValueError(
            f"{target} has manifest schema_version {version}; "
            f"this tool understands {MANIFEST_SCHEMA_VERSION}"
        )
    return JobManifest.from_dict(data)
