"""The neutral provider interface.

Task types are OUR vocabulary, not any vendor's. An adapter translates a neutral
task type into whatever endpoint, verb and payload shape its provider needs, and
translates the provider's status vocabulary back into `TaskStatus`. The
orchestrator, the manifests and the CLI never learn a vendor noun, which is what
makes the providers interchangeable.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from typing import Protocol


class TaskType(str, Enum):
    #: Text prompt -> one or more images.
    TEXT_TO_IMAGE = "text_to_image"
    #: Reference image(s) + prompt -> edited image(s). `multi_view` requests
    #: several consistent camera angles of the same subject in one task.
    IMAGE_TO_IMAGE = "image_to_image"
    #: A single image -> textured 3D mesh.
    IMAGE_TO_3D = "image_to_3d"
    #: 1-4 ordered images of the same object -> textured 3D mesh.
    IMAGES_TO_3D = "images_to_3d"
    #: A static humanoid mesh -> skinned, rigged character.
    CHARACTER_AUTORIG = "character_autorig"


class TaskStatus(str, Enum):
    PENDING = "PENDING"
    IN_PROGRESS = "IN_PROGRESS"
    SUCCEEDED = "SUCCEEDED"
    FAILED = "FAILED"
    CANCELED = "CANCELED"


TERMINAL_STATUSES: frozenset[TaskStatus] = frozenset(
    {TaskStatus.SUCCEEDED, TaskStatus.FAILED, TaskStatus.CANCELED}
)


@dataclass(frozen=True)
class ImageInput:
    """One input image for an image or 3D job.

    `order` is significant for multi-image 3D reconstruction: the front view
    must be first. Local files are inlined as data URIs so the pipeline never
    needs a public bucket to hand a provider our reference art.
    """

    order: int
    role: str
    path: Path


@dataclass(frozen=True)
class JobRequest:
    """A provider-neutral request for one unit of external work."""

    provider: str
    task_type: TaskType
    model_version: str = "latest"
    prompt_text: str = ""
    prompt_version: str = ""
    inputs: tuple[ImageInput, ...] = ()
    #: Generation parameters, already validated against the provider contract.
    #: Part of the idempotency key, so it must never contain secrets or
    #: run-specific noise such as timestamps.
    parameters: dict = field(default_factory=dict)
    #: Free-form label used in the job id; keeps artifact folders readable.
    label: str = ""
    #: Optional provider task to chain from instead of re-uploading inputs.
    input_task_id: str | None = None


@dataclass(frozen=True)
class OutputUrl:
    """One artifact the provider is offering. `kind` is our neutral name."""

    kind: str
    url: str
    suggested_filename: str


@dataclass(frozen=True)
class ProviderTaskState:
    """Normalised view of a remote task."""

    provider_task_id: str
    status: TaskStatus
    progress: int = 0
    error_message: str = ""
    reported_credits: int | None = None
    outputs: tuple[OutputUrl, ...] = ()
    #: Secret-free provider response, stored for audit.
    raw: dict = field(default_factory=dict)

    @property
    def terminal(self) -> bool:
        return self.status in TERMINAL_STATUSES


@dataclass(frozen=True)
class AuthSmokeResult:
    """Outcome of a free, read-only credential check."""

    provider: str
    ok: bool
    detail: dict = field(default_factory=dict)
    message: str = ""


class AssetProvider(Protocol):
    """What every adapter must offer. No vendor nouns appear in the signatures."""

    name: str

    @property
    def credential_env_var(self) -> str: ...

    @property
    def has_credential(self) -> bool: ...

    def supports(self, task_type: TaskType) -> bool: ...

    def endpoint_for(self, task_type: TaskType) -> str:
        """Human-readable endpoint/task-type recorded in the manifest."""

    def model_version_for(self, request: JobRequest) -> str:
        """The concrete provider/model version that the request will run against."""

    def validate_request(self, request: JobRequest) -> None:
        """Raise `ProviderError(INVALID_REQUEST)` for anything the API rejects.

        Runs during dry-run too, so contract mistakes surface before any spend.
        """

    def describe_submission(self, request: JobRequest) -> dict:
        """Secret-free description of the exact call submit() would make."""

    def auth_smoke(self) -> AuthSmokeResult:
        """Free, read-only credential probe. Must never create a paid task."""

    def submit(self, request: JobRequest) -> tuple[str, dict]:
        """Create the remote task. Returns (provider_task_id, secret-free response)."""

    def fetch(self, task_type: TaskType, provider_task_id: str) -> ProviderTaskState: ...

    def cancel(self, task_type: TaskType, provider_task_id: str) -> dict:
        """Explicit cancellation. Never called as part of retry or cleanup."""

    def download(self, url: str, destination: Path) -> int:
        """Fetch one artifact to disk immediately. Returns bytes written."""
