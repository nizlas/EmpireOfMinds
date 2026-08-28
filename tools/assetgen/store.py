"""On-disk job store.

Layout under the artifact root (default `artifacts/assetgen/`):

    jobs/<job_id>/manifest.json
    jobs/<job_id>/outputs/<artifact files>
    jobs/<job_id>/response/<provider response snapshots>

The store is the idempotency index: `find_resumable()` is what stops a rerun
from paying twice for the same work.
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass
from pathlib import Path

from .manifest import (
    JobManifest,
    MANIFEST_FILENAME,
    read_manifest,
    write_manifest,
)

DEFAULT_ARTIFACT_SUBDIR = Path("artifacts") / "assetgen"


class LedgerUnavailable(RuntimeError):
    """The submission ledger could not be written durably, so nothing may spend.

    Disk full, a permission failure or an unsyncable directory all land here. The
    direction is deliberate: if the record of an approval cannot be trusted to
    survive, the approval is not usable, because the record is the only thing
    that stops a second charge.
    """

    code = "PROVIDER_SUBMISSION_LEDGER_UNAVAILABLE"


def _sync_directory(directory: Path) -> None:
    """fsync a directory so a rename or create is durable, where supported.

    Windows has no directory-fsync equivalent and raises; that is not a failure of
    the caller, so it is swallowed here and documented as a real limitation rather
    than reported as success.
    """
    try:
        fd = os.open(directory, getattr(os, "O_DIRECTORY", os.O_RDONLY))
    except (OSError, AttributeError):
        return
    try:
        os.fsync(fd)
    except OSError:
        pass
    finally:
        os.close(fd)


def repo_root_from_here() -> Path:
    # tools/assetgen/store.py -> repo root is two levels up.
    return Path(__file__).resolve().parents[2]


@dataclass
class JobStore:
    repo_root: Path
    artifact_root: Path

    @classmethod
    def create(cls, repo_root: Path | None = None, artifact_root: Path | None = None) -> "JobStore":
        root = (repo_root or repo_root_from_here()).resolve()
        artifacts = (artifact_root or (root / DEFAULT_ARTIFACT_SUBDIR)).resolve()
        return cls(repo_root=root, artifact_root=artifacts)

    @property
    def jobs_dir(self) -> Path:
        return self.artifact_root / "jobs"

    def job_dir(self, job_id: str) -> Path:
        return self.jobs_dir / job_id

    def outputs_dir(self, job_id: str) -> Path:
        return self.job_dir(job_id) / "outputs"

    def response_dir(self, job_id: str) -> Path:
        return self.job_dir(job_id) / "response"

    def exists(self, job_id: str) -> bool:
        return (self.job_dir(job_id) / MANIFEST_FILENAME).is_file()

    def save(self, manifest: JobManifest) -> Path:
        return write_manifest(self.job_dir(manifest.job_id), manifest)

    def load(self, job_id: str) -> JobManifest:
        directory = self.job_dir(job_id)
        if not (directory / MANIFEST_FILENAME).is_file():
            raise FileNotFoundError(f"No job manifest for job_id {job_id!r} under {self.jobs_dir}")
        return read_manifest(directory)

    def list_jobs(self) -> list[JobManifest]:
        if not self.jobs_dir.is_dir():
            return []
        found: list[JobManifest] = []
        for child in sorted(self.jobs_dir.iterdir()):
            if (child / MANIFEST_FILENAME).is_file():
                found.append(read_manifest(child))
        return found

    def find_by_idempotency_key(self, key: str) -> JobManifest | None:
        for manifest in self.list_jobs():
            if manifest.idempotency_key == key:
                return manifest
        return None

    def find_resumable(self, key: str) -> JobManifest | None:
        """Existing job with this identity that already holds a provider task id."""
        existing = self.find_by_idempotency_key(key)
        if existing is not None and existing.resumable:
            return existing
        return None

    # ------------------------------------------------------- submission ledger

    @property
    def submissions_dir(self) -> Path:
        return self.artifact_root / "submissions"

    def submission_record_path(self, plan_digest: str) -> Path:
        return self.submissions_dir / f"{plan_digest}.json"

    def claim_submission(self, plan_digest: str, payload: dict) -> Path:
        """Claim the right to submit this plan exactly once.

        The claim is an `O_CREAT | O_EXCL` file create, which the OS guarantees
        succeeds for exactly one caller. That single primitive gives three
        properties at once: a rerun of an approved plan cannot pay twice, two
        concurrent runs cannot both submit, and the claim reaches the disk BEFORE
        the request goes out - so a crash mid-submission leaves evidence that an
        attempt happened rather than a clean slate that invites a retry.

        DURABILITY. The review (MEDIUM 11) noted that `os.write` alone leaves the
        record in the page cache: durable across process death, not across power
        loss. The data and then the containing directory are now fsynced, so the
        claim survives an OS crash on filesystems that honour it. Directory sync
        is best-effort - it is not available on every platform - and that
        limitation is stated rather than assumed away.

        Raises `FileExistsError` when the plan was already claimed, and
        `LedgerUnavailable` when the claim cannot be made durable, because a
        claim that might not survive is not a claim.
        """
        try:
            self.submissions_dir.mkdir(parents=True, exist_ok=True)
        except OSError as exc:
            raise LedgerUnavailable(
                f"cannot create the submission ledger directory {self.submissions_dir}: {exc}"
            ) from exc
        target = self.submission_record_path(plan_digest)
        handle = os.open(target, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
        try:
            os.write(handle, (json.dumps(payload, indent=2, sort_keys=True) + "\n").encode("utf-8"))
            os.fsync(handle)
        except OSError as exc:
            os.close(handle)
            # A half-written claim is worse than none: remove it and fail closed
            # so nothing believes the approval was safely recorded.
            target.unlink(missing_ok=True)
            raise LedgerUnavailable(
                f"the submission claim for {plan_digest} could not be made durable: {exc}. "
                "Nothing was submitted."
            ) from exc
        else:
            os.close(handle)
        _sync_directory(self.submissions_dir)
        return target

    def read_submission(self, plan_digest: str) -> dict | None:
        target = self.submission_record_path(plan_digest)
        if not target.is_file():
            return None
        try:
            record = json.loads(target.read_text(encoding="utf-8"))
        except ValueError:
            return {"plan_sha256": plan_digest, "unreadable": True}
        return record if isinstance(record, dict) else None

    def update_submission(self, plan_digest: str, **fields) -> Path:
        """Record the outcome of a claimed submission atomically and durably.

        Written write-fsync-replace so the provider task id, once known, cannot be
        lost to an interrupted write or reordered behind the rename. This record is
        what lets a restart resume the SAME paid job instead of creating a second
        one, so losing it is a double-charge risk rather than a cosmetic one.
        """
        target = self.submission_record_path(plan_digest)
        record = self.read_submission(plan_digest) or {"plan_sha256": plan_digest}
        record.update(fields)
        temp = target.with_suffix(".json.tmp")
        payload = (json.dumps(record, indent=2, sort_keys=True) + "\n").encode("utf-8")
        handle = os.open(temp, os.O_CREAT | os.O_TRUNC | os.O_WRONLY)
        try:
            os.write(handle, payload)
            os.fsync(handle)
        finally:
            os.close(handle)
        os.replace(temp, target)
        _sync_directory(self.submissions_dir)
        return target

    def submission_states(self) -> dict[str, dict]:
        """Every ledger record, so a paid identity can be checked before spending."""
        found: dict[str, dict] = {}
        if not self.submissions_dir.is_dir():
            return found
        for child in sorted(self.submissions_dir.glob("*.json")):
            digest = child.stem
            record = self.read_submission(digest)
            if record is not None:
                found[digest] = record
        return found

    def find_unknown_outcome(self, idempotency_key: str) -> JobManifest | None:
        """An earlier attempt at this identity whose outcome is genuinely unknown.

        This is the check that closes review HIGH 5. An ambiguous create leaves no
        provider task id, so `find_resumable` sees nothing and the old code
        submitted again - measured going from one create call to two. The
        ambiguity WAS recorded; nothing consulted it. Now something does.
        """
        for manifest in self.list_jobs():
            if manifest.idempotency_key != idempotency_key:
                continue
            if str(getattr(manifest, "submission_outcome", "") or "") == "UNKNOWN":
                return manifest
        return None
