"""On-disk job store.

Layout under the artifact root (default `artifacts/assetgen/`):

    jobs/<job_id>/manifest.json
    jobs/<job_id>/outputs/<artifact files>
    jobs/<job_id>/response/<provider response snapshots>

The store is the idempotency index: `find_resumable()` is what stops a rerun
from paying twice for the same work.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from .manifest import (
    JobManifest,
    MANIFEST_FILENAME,
    read_manifest,
    write_manifest,
)

DEFAULT_ARTIFACT_SUBDIR = Path("artifacts") / "assetgen"


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
