"""Meshy adapter.

Verified against the official documentation on 2026-08-25:
  https://docs.meshy.ai/en/api/image-to-image
  https://docs.meshy.ai/en/api/multi-image-to-3d
  https://docs.meshy.ai/en/api/changelog

Contract facts this adapter depends on:
  * Base URL `https://api.meshy.ai`; `Authorization: Bearer <key>`.
  * Task creation is asynchronous and answers `{"result": "<task_id>"}`.
  * Lifecycle `PENDING -> IN_PROGRESS -> SUCCEEDED | FAILED | CANCELED`.
  * Image endpoints take a CONCRETE `ai_model` (the nano-banana family or
    gpt-image-2). `latest` is a 3D-only alias and currently resolves to Meshy 7.
  * `generate_multi_view` cannot be combined with `aspect_ratio`.
  * Generated assets are retained for 3 days, and output URLs are signed, so
    everything must be downloaded immediately.
  * Every GET carries `consumed_credits`, which is the only honest credit figure.
"""

from __future__ import annotations

import base64
import json
import mimetypes
from dataclasses import dataclass, field
from pathlib import Path

from ..errors import ErrorKind, ProviderError, classify_http_status
from ..secret_guard import Credential, load_credential
from ..transport import (
    HttpRequest,
    HttpResponse,
    HttpTransport,
    RetryPolicy,
    parse_retry_after,
    send_with_retry,
)
from .base import (
    AuthSmokeResult,
    JobRequest,
    OutputUrl,
    ProviderTaskState,
    TaskStatus,
    TaskType,
)

PROVIDER_NAME = "meshy"
CREDENTIAL_ENV_VAR = "MESHY_API_KEY"
DEFAULT_BASE_URL = "https://api.meshy.ai"
BASE_URL_ENV_VAR = "MESHY_API_BASE"

#: Neutral task type -> documented endpoint path.
ENDPOINTS: dict[TaskType, str] = {
    TaskType.TEXT_TO_IMAGE: "/openapi/v1/text-to-image",
    TaskType.IMAGE_TO_IMAGE: "/openapi/v1/image-to-image",
    TaskType.IMAGE_TO_3D: "/openapi/v1/image-to-3d",
    TaskType.IMAGES_TO_3D: "/openapi/v1/multi-image-to-3d",
}

IMAGE_TASK_TYPES = frozenset({TaskType.TEXT_TO_IMAGE, TaskType.IMAGE_TO_IMAGE})
MODEL_3D_TASK_TYPES = frozenset({TaskType.IMAGE_TO_3D, TaskType.IMAGES_TO_3D})

IMAGE_MODELS = ("nano-banana", "nano-banana-2", "nano-banana-pro", "gpt-image-2")
MODEL_3D_MODELS = ("meshy-5", "meshy-6", "meshy-7", "latest")
#: Models that accept image_enhancement / remove_lighting / 4k+ textures.
MODERN_3D_MODELS = frozenset({"meshy-6", "meshy-7", "latest"})
TEXTURE_RESOLUTIONS = ("2k", "4k", "8k")
TOPOLOGIES = ("quad", "triangle")
SUPPORTED_IMAGE_SUFFIXES = frozenset({".jpg", ".jpeg", ".png"})

STATUS_MAP: dict[str, TaskStatus] = {
    "PENDING": TaskStatus.PENDING,
    "IN_PROGRESS": TaskStatus.IN_PROGRESS,
    "SUCCEEDED": TaskStatus.SUCCEEDED,
    "FAILED": TaskStatus.FAILED,
    "CANCELED": TaskStatus.CANCELED,
    "CANCELLED": TaskStatus.CANCELED,
}

#: Documented credit cost, used only for dry-run estimates. The authoritative
#: figure is `consumed_credits` on the task GET.
CREDIT_ESTIMATES: dict[tuple[TaskType, str], int] = {
    (TaskType.TEXT_TO_IMAGE, "nano-banana"): 3,
    (TaskType.TEXT_TO_IMAGE, "nano-banana-2"): 6,
    (TaskType.TEXT_TO_IMAGE, "nano-banana-pro"): 9,
    (TaskType.TEXT_TO_IMAGE, "gpt-image-2"): 9,
    (TaskType.IMAGE_TO_IMAGE, "nano-banana"): 3,
    (TaskType.IMAGE_TO_IMAGE, "nano-banana-2"): 6,
    (TaskType.IMAGE_TO_IMAGE, "nano-banana-pro"): 9,
    (TaskType.IMAGE_TO_IMAGE, "gpt-image-2"): 12,
}
#: Multi-image / image to 3D with texturing on a current model.
CREDIT_ESTIMATE_3D_TEXTURED = 30
CREDIT_ESTIMATE_3D_UNTEXTURED = 20


def image_data_uri(path: Path) -> str:
    """Inline a local image as a base64 data URI.

    Documented as accepted anywhere an image URL is accepted, which keeps local
    reference art out of any public bucket.
    """
    suffix = path.suffix.lower()
    if suffix not in SUPPORTED_IMAGE_SUFFIXES:
        raise ProviderError(
            ErrorKind.INVALID_REQUEST,
            f"{path.name}: Meshy accepts only .jpg/.jpeg/.png images, got {suffix or 'no suffix'}",
            provider=PROVIDER_NAME,
        )
    mime = mimetypes.types_map.get(suffix, "image/png")
    payload = base64.b64encode(path.read_bytes()).decode("ascii")
    return f"data:{mime};base64,{payload}"


@dataclass
class MeshyProvider:
    transport: HttpTransport
    retry_policy: RetryPolicy = field(default_factory=RetryPolicy)
    require_credential: bool = True
    base_url: str = ""
    name: str = PROVIDER_NAME

    def __post_init__(self) -> None:
        import os

        self.base_url = (self.base_url or os.environ.get(BASE_URL_ENV_VAR, "") or DEFAULT_BASE_URL).rstrip("/")
        self._credential: Credential | None = load_credential(
            CREDENTIAL_ENV_VAR, required=self.require_credential
        )

    # ------------------------------------------------------------------ identity

    @property
    def credential_env_var(self) -> str:
        return CREDENTIAL_ENV_VAR

    @property
    def has_credential(self) -> bool:
        return self._credential is not None

    def supports(self, task_type: TaskType) -> bool:
        return task_type in ENDPOINTS

    def endpoint_for(self, task_type: TaskType) -> str:
        self._require_supported(task_type)
        return ENDPOINTS[task_type]

    def model_version_for(self, request: JobRequest) -> str:
        return self._effective_model(request)

    # ---------------------------------------------------------------- validation

    def validate_request(self, request: JobRequest) -> None:
        """Reject anything the documented contract would reject, before spending."""
        self._require_supported(request.task_type)
        model = self._effective_model(request)
        params = dict(request.parameters)

        if request.task_type in IMAGE_TASK_TYPES:
            if model not in IMAGE_MODELS:
                self._invalid(
                    f"ai_model {model!r} is not valid for {request.task_type.value}; "
                    f"expected one of {', '.join(IMAGE_MODELS)}"
                )
            if not request.prompt_text.strip():
                self._invalid(f"{request.task_type.value} requires a non-empty prompt")
            if params.get("generate_multi_view") and "aspect_ratio" in params:
                self._invalid("generate_multi_view cannot be combined with aspect_ratio")
            if request.task_type == TaskType.IMAGE_TO_IMAGE:
                if not 1 <= len(request.inputs) <= 5:
                    self._invalid(
                        f"image_to_image needs 1-5 reference images, got {len(request.inputs)}"
                    )
        else:
            if model not in MODEL_3D_MODELS:
                self._invalid(
                    f"ai_model {model!r} is not valid for {request.task_type.value}; "
                    f"expected one of {', '.join(MODEL_3D_MODELS)}"
                )
            if request.task_type == TaskType.IMAGES_TO_3D:
                if request.input_task_id is None and not 1 <= len(request.inputs) <= 4:
                    self._invalid(
                        "images_to_3d needs either input_task_id or 1-4 images, "
                        f"got {len(request.inputs)} images"
                    )
            elif request.input_task_id is None and len(request.inputs) != 1:
                self._invalid(f"image_to_3d needs exactly 1 image, got {len(request.inputs)}")

            resolution = params.get("texture_resolution")
            if resolution is not None:
                if resolution not in TEXTURE_RESOLUTIONS:
                    self._invalid(
                        f"texture_resolution {resolution!r} invalid; "
                        f"expected one of {', '.join(TEXTURE_RESOLUTIONS)}"
                    )
                if resolution in ("4k", "8k") and model not in MODERN_3D_MODELS:
                    self._invalid(
                        f"texture_resolution {resolution!r} requires ai_model meshy-6, meshy-7 or latest"
                    )
            topology = params.get("topology")
            if topology is not None and topology not in TOPOLOGIES:
                self._invalid(f"topology {topology!r} invalid; expected one of {', '.join(TOPOLOGIES)}")
            polycount = params.get("target_polycount")
            if polycount is not None and not 100 <= int(polycount) <= 300_000:
                self._invalid(f"target_polycount {polycount} outside the documented range 100-300000")
            if params.get("save_pre_remeshed_model") and not params.get("should_remesh"):
                self._invalid(
                    "save_pre_remeshed_model only returns pre_remeshed_glb when should_remesh is true"
                )
            if params.get("enable_pbr") and params.get("should_texture") is False:
                self._invalid("enable_pbr requires should_texture to stay true")
            for modern_only in ("image_enhancement", "remove_lighting"):
                if modern_only in params and model not in MODERN_3D_MODELS:
                    self._invalid(
                        f"{modern_only} is only supported for ai_model meshy-6, meshy-7 or latest"
                    )

        for image in request.inputs:
            if not image.path.is_file():
                self._invalid(f"input image not found: {image.path}")
            if image.path.suffix.lower() not in SUPPORTED_IMAGE_SUFFIXES:
                self._invalid(
                    f"{image.path.name}: unsupported image format {image.path.suffix!r}; "
                    "Meshy accepts .jpg/.jpeg/.png"
                )

    def estimate_credits(self, request: JobRequest) -> int | None:
        model = self._effective_model(request)
        if request.task_type in IMAGE_TASK_TYPES:
            return CREDIT_ESTIMATES.get((request.task_type, model))
        textured = request.parameters.get("should_texture", True)
        return CREDIT_ESTIMATE_3D_TEXTURED if textured else CREDIT_ESTIMATE_3D_UNTEXTURED

    def describe_submission(self, request: JobRequest) -> dict:
        """What submit() would send, with image payloads summarised not inlined."""
        body = self._build_body(request, inline_images=False)
        return {
            "method": "POST",
            "url": f"{self.base_url}{self.endpoint_for(request.task_type)}",
            "auth": f"Bearer <{CREDENTIAL_ENV_VAR}>",
            "body": body,
            "estimated_credits": self.estimate_credits(request),
            "paid": True,
        }

    # --------------------------------------------------------------- operations

    def auth_smoke(self) -> AuthSmokeResult:
        """GET /openapi/v1/balance - documented, read-only and free."""
        if self._credential is None:
            return AuthSmokeResult(
                provider=self.name,
                ok=False,
                message=f"{CREDENTIAL_ENV_VAR} is not set",
                detail={"blocked": "BLOCKED_MISSING_CREDENTIAL"},
            )
        response = self._send(
            HttpRequest(method="GET", url=f"{self.base_url}/openapi/v1/balance", headers=self._headers())
        )
        payload = response.json()
        return AuthSmokeResult(
            provider=self.name,
            ok=True,
            detail={"balance": payload.get("balance")},
            message="balance endpoint reachable",
        )

    def submit(self, request: JobRequest) -> tuple[str, dict]:
        self.validate_request(request)
        body = self._build_body(request, inline_images=True)
        response = self._send(
            HttpRequest(
                method="POST",
                url=f"{self.base_url}{self.endpoint_for(request.task_type)}",
                headers=self._headers(json_body=True),
                body=json.dumps(body).encode("utf-8"),
            )
        )
        payload = response.json()
        task_id = payload.get("result")
        if not isinstance(task_id, str) or not task_id:
            raise ProviderError(
                ErrorKind.CONTRACT,
                "Task creation response did not contain a string 'result' task id",
                provider=self.name,
                status=response.status,
            )
        return task_id, {"http_status": response.status, "result": task_id}

    def fetch(self, task_type: TaskType, provider_task_id: str) -> ProviderTaskState:
        endpoint = self.endpoint_for(task_type)
        response = self._send(
            HttpRequest(
                method="GET",
                url=f"{self.base_url}{endpoint}/{provider_task_id}",
                headers=self._headers(),
            )
        )
        return self._parse_task(task_type, provider_task_id, response.json())

    def cancel(self, task_type: TaskType, provider_task_id: str) -> dict:
        """DELETE removes the task and its data. Only ever an explicit command."""
        endpoint = self.endpoint_for(task_type)
        response = self._send(
            HttpRequest(
                method="DELETE",
                url=f"{self.base_url}{endpoint}/{provider_task_id}",
                headers=self._headers(),
            )
        )
        return {"http_status": response.status}

    def download(self, url: str, destination: Path) -> int:
        """Fetch a signed artifact URL. Signed URLs expire; classify that clearly."""
        response = self.transport.send(HttpRequest(method="GET", url=url, timeout_s=300.0))
        if response.status in (403, 404, 410):
            raise ProviderError(
                ErrorKind.EXPIRED_URL,
                f"Artifact URL is no longer valid (HTTP {response.status}); "
                "re-fetch the task to obtain a fresh signed URL",
                provider=self.name,
                status=response.status,
            )
        error = self._classify(response)
        if error is not None:
            raise error
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(response.body)
        return len(response.body)

    # ------------------------------------------------------------------ internals

    def _require_supported(self, task_type: TaskType) -> None:
        if task_type not in ENDPOINTS:
            raise ProviderError(
                ErrorKind.INVALID_REQUEST,
                f"{self.name} does not implement task type {task_type.value}",
                provider=self.name,
            )

    def _invalid(self, message: str) -> None:
        raise ProviderError(ErrorKind.INVALID_REQUEST, message, provider=self.name)

    def _effective_model(self, request: JobRequest) -> str:
        explicit = request.parameters.get("ai_model")
        if isinstance(explicit, str) and explicit:
            return explicit
        return request.model_version

    def _headers(self, *, json_body: bool = False) -> dict[str, str]:
        if self._credential is None:
            raise ProviderError(
                ErrorKind.AUTH,
                f"{CREDENTIAL_ENV_VAR} is not set",
                provider=self.name,
            )
        headers = {"Authorization": f"Bearer {self._credential.value}"}
        if json_body:
            headers["Content-Type"] = "application/json"
        return headers

    def _classify(self, response: HttpResponse) -> ProviderError | None:
        if 200 <= response.status < 300:
            return None
        message = ""
        try:
            message = str(response.json().get("message", ""))
        except ProviderError:
            message = response.text()[:500]
        error = classify_http_status(response.status, provider=self.name, body_text=message)
        if error.kind is ErrorKind.RATE_LIMIT:
            error.retry_after_s = parse_retry_after(response)
        return error

    def _send(self, request: HttpRequest) -> HttpResponse:
        response, _retries = send_with_retry(
            self.transport,
            request,
            policy=self.retry_policy,
            provider=self.name,
            classify=self._classify,
        )
        return response

    def _build_body(self, request: JobRequest, *, inline_images: bool) -> dict:
        params = dict(request.parameters)
        model = self._effective_model(request)
        body: dict = {"ai_model": model}
        body.update({k: v for k, v in params.items() if k != "ai_model"})

        ordered = sorted(request.inputs, key=lambda item: item.order)

        if request.task_type == TaskType.TEXT_TO_IMAGE:
            body["prompt"] = request.prompt_text
        elif request.task_type == TaskType.IMAGE_TO_IMAGE:
            body["prompt"] = request.prompt_text
            body["reference_image_urls"] = self._image_payload(ordered, inline_images)
        elif request.task_type == TaskType.IMAGE_TO_3D:
            if request.input_task_id:
                body["input_task_id"] = request.input_task_id
            else:
                body["image_url"] = self._image_payload(ordered, inline_images)[0]
        elif request.task_type == TaskType.IMAGES_TO_3D:
            if request.input_task_id:
                body["input_task_id"] = request.input_task_id
            else:
                body["image_urls"] = self._image_payload(ordered, inline_images)
        return body

    def _image_payload(self, ordered_inputs, inline_images: bool) -> list[str]:
        if inline_images:
            return [image_data_uri(item.path) for item in ordered_inputs]
        return [f"<data-uri:{item.role}:{item.path.name}>" for item in ordered_inputs]

    def _parse_task(self, task_type: TaskType, provider_task_id: str, payload: dict) -> ProviderTaskState:
        raw_status = str(payload.get("status", "")).upper()
        if raw_status not in STATUS_MAP:
            raise ProviderError(
                ErrorKind.CONTRACT,
                f"Unknown task status {raw_status!r} for task {provider_task_id}",
                provider=self.name,
            )
        status = STATUS_MAP[raw_status]
        task_error = payload.get("task_error") or {}
        error_message = str(task_error.get("message", "") or "")

        outputs: list[OutputUrl] = []
        if status is TaskStatus.SUCCEEDED:
            outputs = self._collect_outputs(task_type, payload)
            if not outputs:
                raise ProviderError(
                    ErrorKind.MISSING_OUTPUT,
                    f"Task {provider_task_id} reported SUCCEEDED but returned no downloadable output",
                    provider=self.name,
                )

        credits = payload.get("consumed_credits")
        return ProviderTaskState(
            provider_task_id=provider_task_id,
            status=status,
            progress=int(payload.get("progress") or 0),
            error_message=error_message,
            reported_credits=int(credits) if isinstance(credits, (int, float)) else None,
            outputs=tuple(outputs),
            raw=_response_summary(payload),
        )

    def _collect_outputs(self, task_type: TaskType, payload: dict) -> list[OutputUrl]:
        outputs: list[OutputUrl] = []

        if task_type in IMAGE_TASK_TYPES:
            for index, url in enumerate(payload.get("image_urls") or []):
                if isinstance(url, str) and url:
                    outputs.append(
                        OutputUrl(
                            kind=f"image_view_{index + 1}",
                            url=url,
                            suggested_filename=f"view_{index + 1}.png",
                        )
                    )
        else:
            model_urls = payload.get("model_urls") or {}
            for key, kind, filename in (
                ("glb", "model_glb", "model.glb"),
                ("pre_remeshed_glb", "model_pre_remeshed_glb", "model_pre_remeshed.glb"),
                ("fbx", "model_fbx", "model.fbx"),
                ("obj", "model_obj", "model.obj"),
            ):
                url = model_urls.get(key)
                if isinstance(url, str) and url:
                    outputs.append(OutputUrl(kind=kind, url=url, suggested_filename=filename))

            for index, texture in enumerate(payload.get("texture_urls") or []):
                if not isinstance(texture, dict):
                    continue
                for map_name, url in sorted(texture.items()):
                    if isinstance(url, str) and url:
                        outputs.append(
                            OutputUrl(
                                kind=f"texture_{map_name}_{index}",
                                url=url,
                                suggested_filename=f"texture_{index}_{map_name}.png",
                            )
                        )

        thumbnail = payload.get("thumbnail_url")
        if isinstance(thumbnail, str) and thumbnail:
            outputs.append(
                OutputUrl(kind="thumbnail", url=thumbnail, suggested_filename="thumbnail.png")
            )
        alpha = payload.get("alpha_thumbnail_url")
        if isinstance(alpha, str) and alpha:
            outputs.append(
                OutputUrl(
                    kind="thumbnail_alpha",
                    url=alpha,
                    suggested_filename="thumbnail_alpha.png",
                )
            )
        thumbnails = payload.get("thumbnail_urls") or {}
        if isinstance(thumbnails, dict):
            for view in ("front", "right", "back", "left"):
                url = thumbnails.get(view)
                if isinstance(url, str) and url:
                    outputs.append(
                        OutputUrl(
                            kind=f"thumbnail_{view}",
                            url=url,
                            suggested_filename=f"thumbnail_{view}.png",
                        )
                    )
        return outputs


def _response_summary(payload: dict) -> dict:
    """Keep the audit trail small: signed URLs are volatile, so store shapes."""
    return {
        "id": payload.get("id"),
        "type": payload.get("type"),
        "status": payload.get("status"),
        "progress": payload.get("progress"),
        "created_at": payload.get("created_at"),
        "started_at": payload.get("started_at"),
        "finished_at": payload.get("finished_at"),
        "consumed_credits": payload.get("consumed_credits"),
        "preceding_tasks": payload.get("preceding_tasks"),
        "task_error": payload.get("task_error"),
        "returned_output_keys": sorted(
            list((payload.get("model_urls") or {}).keys())
            + [f"image_urls[{len(payload.get('image_urls') or [])}]"]
            + sorted((payload.get("thumbnail_urls") or {}).keys())
        ),
    }
