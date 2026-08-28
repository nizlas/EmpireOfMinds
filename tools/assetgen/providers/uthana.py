"""Uthana adapter (character upload + auto-rig).

Verified against the official documentation on 2026-08-25:
  https://uthana.com/docs/api/graphql
  https://uthana.com/docs/api/capabilities/auto-rig-and-add-character
  https://uthana.com/docs/api/capabilities/asset-management

Contract facts this adapter depends on:
  * Single GraphQL endpoint `POST https://uthana.com/graphql`.
  * Auth is HTTP Basic with the API key as the username and an EMPTY password,
    i.e. `Authorization: Basic base64("<key>:")`.
  * `create_character` is a GraphQL multipart upload (`operations` / `map` /
    file part) returning `character { id name }` and `auto_rig_confidence`.
  * Auto-rig flags: `auto_rig`, `auto_rig_front_facing`, `include_fingers` -
    all default true, and `include_fingers` is mandatory for this project.
  * A rigged character is fetched from the documented bundle endpoint
    `GET /motion/bundle/<character-id>/character.glb`, never by driving a browser.
  * GraphQL answers HTTP 200 with an `errors` array, so status alone is not
    enough to decide success.
"""

from __future__ import annotations

import base64
import json
import os
import secrets as _stdlib_secrets
from dataclasses import dataclass, field
from pathlib import Path

from ..artifact_paths import write_verified_bytes
from ..capability import OperationClass
from ..capability import require as require_capability
from ..endpoint import parse_endpoint
from ..errors import ErrorKind, ProviderError, classify_http_status
from ..live_gate import credential_state
from ..secret_guard import Credential, load_credential
from ..transport import (
    NO_RETRY,
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

PROVIDER_NAME = "uthana"
CREDENTIAL_ENV_VAR = "UTHANA_API_KEY"
DEFAULT_BASE_URL = "https://uthana.com"
BASE_URL_ENV_VAR = "UTHANA_API_BASE"
GRAPHQL_PATH = "/graphql"

#: The single paid operation this adapter can perform. Shared with the plan
#: builder so the plan's `operation` and the capability's scope cannot drift.
PAID_OPERATION = "character_autorig"

#: Documented character-upload formats.
SUPPORTED_MODEL_SUFFIXES = frozenset({".glb", ".gltf", ".fbx"})
#: Project-level upload ceiling required by the C1 contract.
MAX_UPLOAD_BYTES = 30 * 1024 * 1024

CREATE_CHARACTER_MUTATION = (
    "mutation ("
    "$file: Upload!, $name: String!, $auto_rig: Boolean, "
    "$auto_rig_front_facing: Boolean, $rerig_target: String, $include_fingers: Boolean"
    ") { create_character("
    "file: $file, name: $name, auto_rig: $auto_rig, "
    "auto_rig_front_facing: $auto_rig_front_facing, rerig_target: $rerig_target, "
    "include_fingers: $include_fingers"
    ") { character { id name } auto_rig_confidence } }"
)

ORG_QUERY = (
    "query { org { id name characters_allowed characters_allowed_remaining } }"
)

CHARACTERS_QUERY = (
    "query { characters { id name created updated deleted "
    "assets { id filename mimetype type sha256 size } } }"
)

CHARACTER_QUERY = (
    "query Character($id: String) { character(id: $id) { id name created updated deleted "
    "assets { id filename mimetype type sha256 size } } }"
)

#: GraphQL `extensions.code` values mapped onto the neutral taxonomy.
ERROR_CODE_MAP: dict[str, ErrorKind] = {
    "INVALID_MODEL_FORMAT": ErrorKind.INVALID_REQUEST,
    "UNAUTHENTICATED": ErrorKind.AUTH,
    "UNAUTHORIZED": ErrorKind.AUTH,
    "FORBIDDEN": ErrorKind.AUTH,
    "RATE_LIMITED": ErrorKind.RATE_LIMIT,
    "QUOTA_EXCEEDED": ErrorKind.PAYMENT,
    "NOT_FOUND": ErrorKind.NOT_FOUND,
    "INTERNAL_SERVER_ERROR": ErrorKind.TRANSIENT,
}


@dataclass
class UthanaProvider:
    transport: HttpTransport
    retry_policy: RetryPolicy = field(default_factory=RetryPolicy)
    require_credential: bool = True
    base_url: str = ""
    name: str = PROVIDER_NAME

    def __post_init__(self) -> None:
        self.base_url = (
            self.base_url or os.environ.get(BASE_URL_ENV_VAR, "") or DEFAULT_BASE_URL
        ).rstrip("/")
        self._credential: Credential | None = None
        # Constructing an adapter must not read a key. Building the adapter is
        # what every offline command does - dry-run, plan, list, inspect - and a
        # run that is going to be refused at a barrier should never have touched
        # a credential at all. The value is loaded lazily in `_headers()`, which
        # only runs on the authorized live path.
        if self.require_credential:
            load_credential(CREDENTIAL_ENV_VAR, required=True)

    # ------------------------------------------------------------------ identity

    @property
    def credential_env_var(self) -> str:
        return CREDENTIAL_ENV_VAR

    @property
    def has_credential(self) -> bool:
        """`present`/`missing` only: the value is never materialised here."""
        return credential_state(CREDENTIAL_ENV_VAR) == "present"

    def supports(self, task_type: TaskType) -> bool:
        return task_type is TaskType.CHARACTER_AUTORIG

    def paid_operation_name(self, request: JobRequest) -> str:
        """The operation name a plan and a capability must both use."""
        return PAID_OPERATION

    def endpoint_for(self, task_type: TaskType) -> str:
        self._require_supported(task_type)
        return f"{GRAPHQL_PATH}#create_character"

    def model_version_for(self, request: JobRequest) -> str:
        """Uthana does not version auto-rig publicly; record the rig contract instead."""
        rerig = request.parameters.get("rerig_target") or "native"
        fingers = bool(request.parameters.get("include_fingers", True))
        return f"auto_rig:{rerig}:fingers={'on' if fingers else 'off'}"

    # ---------------------------------------------------------------- validation

    def validate_request(self, request: JobRequest) -> None:
        self._require_supported(request.task_type)
        if len(request.inputs) != 1:
            self._invalid(
                f"character_autorig takes exactly one model file, got {len(request.inputs)}"
            )
        model_path = request.inputs[0].path
        if not model_path.is_file():
            self._invalid(f"model file not found: {model_path}")
        suffix = model_path.suffix.lower()
        if suffix not in SUPPORTED_MODEL_SUFFIXES:
            self._invalid(
                f"{model_path.name}: unsupported format {suffix!r}; "
                f"Uthana accepts {', '.join(sorted(SUPPORTED_MODEL_SUFFIXES))}"
            )
        size = model_path.stat().st_size
        if size > MAX_UPLOAD_BYTES:
            self._invalid(
                f"{model_path.name} is {size} bytes, above the {MAX_UPLOAD_BYTES}-byte upload gate"
            )
        if not str(request.parameters.get("name", "")).strip():
            self._invalid("character_autorig requires a non-empty 'name' parameter")
        if request.parameters.get("include_fingers") is False:
            self._invalid(
                "include_fingers=false is not allowed: the hand/equipment pipeline requires finger joints"
            )
        rerig = request.parameters.get("rerig_target")
        if rerig not in (None, "", "r15", "ue5"):
            self._invalid(f"rerig_target {rerig!r} invalid; documented values are r15 and ue5")

    def describe_submission(self, request: JobRequest) -> dict:
        model_path = request.inputs[0].path if request.inputs else None
        return {
            "method": "POST",
            "url": f"{self.base_url}{GRAPHQL_PATH}",
            "auth": f"Basic base64(<{CREDENTIAL_ENV_VAR}>:)",
            "graphql_operation": "create_character",
            "multipart_parts": ["operations", "map", "0"],
            "variables": self._variables(request),
            "file": model_path.name if model_path else None,
            "file_size_bytes": model_path.stat().st_size if model_path else None,
            "consumes_character_slot": True,
            "paid": True,
        }

    # --------------------------------------------------------------- operations

    def auth_smoke(self, capability=None) -> AuthSmokeResult:
        """`org` query - read-only, consumes no character slot.

        The capability check precedes even the presence check, because the review
        (BLOCKER 1) measured `auth-smoke --live` reaching this method and issuing a
        real request with the machine opt-in absent. Whether a key happens to be
        configured is not permission to use it.
        """
        self._authorize(capability, "auth_smoke", OperationClass.NETWORK_READ)
        if not self.has_credential:
            return AuthSmokeResult(
                provider=self.name,
                ok=False,
                message=f"{CREDENTIAL_ENV_VAR} is not set",
                detail={"blocked": "BLOCKED_MISSING_CREDENTIAL"},
            )
        payload = self._graphql(ORG_QUERY, capability=capability)
        org = (payload.get("data") or {}).get("org") or {}
        return AuthSmokeResult(
            provider=self.name,
            ok=True,
            detail={
                "org_id": org.get("id"),
                "characters_allowed": org.get("characters_allowed"),
                "characters_allowed_remaining": org.get("characters_allowed_remaining"),
            },
            message="org query reachable",
        )

    def list_characters(self, capability=None) -> list[dict]:
        """Read-only inventory; used to avoid re-rigging something already present."""
        self._authorize(capability, "list_characters", OperationClass.NETWORK_READ)
        payload = self._graphql(CHARACTERS_QUERY, capability=capability)
        characters = (payload.get("data") or {}).get("characters") or []
        return [c for c in characters if isinstance(c, dict)]

    def submit(self, request: JobRequest, capability=None) -> tuple[str, dict]:
        # Authorization first, validation second, credential third. The order is
        # the point: a refusal here has read no key and built no multipart body.
        self._authorize(capability, PAID_OPERATION, OperationClass.PAID_CREATE)
        self.validate_request(request)
        model_path = request.inputs[0].path
        variables = self._variables(request)
        body, content_type = _build_multipart(
            operations={
                "query": CREATE_CHARACTER_MUTATION,
                "variables": {**variables, "file": None},
            },
            file_field="variables.file",
            file_path=model_path,
        )
        response = self._send(
            HttpRequest(
                method="POST",
                url=f"{self.base_url}{GRAPHQL_PATH}",
                headers={**self._headers(), "Content-Type": content_type},
                body=body,
                timeout_s=600.0,
                capability=capability,
            ),
            retry=False,
        )
        payload = self._require_graphql_ok(response)
        result = (payload.get("data") or {}).get("create_character") or {}
        character = result.get("character") or {}
        character_id = character.get("id")
        if not isinstance(character_id, str) or not character_id:
            raise ProviderError(
                ErrorKind.CONTRACT,
                "create_character returned no character id",
                provider=self.name,
                status=response.status,
            )
        return character_id, {
            "http_status": response.status,
            "character_id": character_id,
            "character_name": character.get("name"),
            "auto_rig_confidence": result.get("auto_rig_confidence"),
        }

    def fetch(
        self, task_type: TaskType, provider_task_id: str, capability=None
    ) -> ProviderTaskState:
        """Poll the character until a downloadable bundle asset exists."""
        self._authorize(capability, "poll", OperationClass.NETWORK_READ)
        self._require_supported(task_type)
        payload = self._graphql(
            CHARACTER_QUERY, variables={"id": provider_task_id}, capability=capability
        )
        character = (payload.get("data") or {}).get("character")
        if not isinstance(character, dict) or not character.get("id"):
            raise ProviderError(
                ErrorKind.NOT_FOUND,
                f"No character {provider_task_id} visible to this credential",
                provider=self.name,
            )
        if character.get("deleted"):
            return ProviderTaskState(
                provider_task_id=provider_task_id,
                status=TaskStatus.CANCELED,
                error_message="character was deleted",
                raw=_character_summary(character),
            )

        assets = [a for a in (character.get("assets") or []) if isinstance(a, dict)]
        has_bundle = any(str(a.get("type", "")).lower() == "bundle" for a in assets)
        if not has_bundle:
            # Auto-rig typically adds 30-60 s; no bundle yet means still working.
            return ProviderTaskState(
                provider_task_id=provider_task_id,
                status=TaskStatus.IN_PROGRESS,
                progress=50,
                raw=_character_summary(character),
            )

        return ProviderTaskState(
            provider_task_id=provider_task_id,
            status=TaskStatus.SUCCEEDED,
            progress=100,
            outputs=(
                OutputUrl(
                    kind="rigged_character_glb",
                    url=self.character_bundle_url(provider_task_id, "glb"),
                    # ADVISORY ONLY. This string is provider-controlled and is
                    # never used as a path: the review turned exactly this field
                    # into an arbitrary write. The local filename is derived from
                    # the job id and the neutral `kind` instead.
                    suggested_filename=f"{provider_task_id}_rigged.glb",
                ),
            ),
            raw=_character_summary(character),
        )

    def character_bundle_url(self, character_id: str, file_format: str = "glb") -> str:
        if file_format not in ("glb", "fbx"):
            self._invalid(f"character bundle format {file_format!r} invalid; expected glb or fbx")
        return f"{self.base_url}/motion/bundle/{character_id}/character.{file_format}"

    def cancel(self, task_type: TaskType, provider_task_id: str, capability=None) -> dict:
        """Uthana exposes no documented character-cancel mutation."""
        self._authorize(capability, "cancel", OperationClass.REMOTE_MUTATION)
        self._require_supported(task_type)
        raise ProviderError(
            ErrorKind.INVALID_REQUEST,
            "Uthana has no documented cancel for an in-flight character upload; "
            "delete the character in the web UI if it must be removed",
            provider=self.name,
        )

    def download(self, url: str, destination: Path, capability=None) -> int:
        """Bundle downloads are authenticated, unlike Meshy's signed URLs.

        Because the credential travels with this request, the capability's endpoint
        is what keeps it from travelling to somewhere else.
        """
        self._authorize(capability, "download", OperationClass.NETWORK_READ)
        response = self.transport.send(
            HttpRequest(
                method="GET",
                url=url,
                headers=self._headers(),
                timeout_s=600.0,
                capability=capability,
            )
        )
        error = self._classify(response)
        if error is not None:
            raise error
        write_verified_bytes(destination, response.body)
        return len(response.body)

    # ------------------------------------------------------------------ internals

    def _authorize(self, capability, operation: str, operation_class: OperationClass):
        """Refuse before anything is read, built or sent."""
        return require_capability(
            capability,
            provider=self.name,
            operation=operation,
            operation_class=operation_class,
            endpoint=self.endpoint_identity(),
        )

    def endpoint_identity(self):
        """The normalised destination this adapter will actually use.

        Recomputed from the adapter's own `base_url`, so a capability minted for a
        different endpoint cannot be spent here even if it is otherwise valid.
        """
        return parse_endpoint(self.name, self.base_url, require_https=False)

    def _require_supported(self, task_type: TaskType) -> None:
        if not self.supports(task_type):
            raise ProviderError(
                ErrorKind.INVALID_REQUEST,
                f"{self.name} does not implement task type {task_type.value}",
                provider=self.name,
            )

    def _invalid(self, message: str) -> None:
        raise ProviderError(ErrorKind.INVALID_REQUEST, message, provider=self.name)

    def _variables(self, request: JobRequest) -> dict:
        params = request.parameters
        return {
            "name": str(params.get("name", "")),
            "auto_rig": bool(params.get("auto_rig", True)),
            "auto_rig_front_facing": bool(params.get("auto_rig_front_facing", True)),
            "include_fingers": bool(params.get("include_fingers", True)),
            "rerig_target": params.get("rerig_target") or None,
        }

    def _headers(self) -> dict[str, str]:
        """The one place a credential value is read. Only reached on a live call."""
        if self._credential is None:
            self._credential = load_credential(CREDENTIAL_ENV_VAR, required=False)
        if self._credential is None:
            raise ProviderError(
                ErrorKind.AUTH, f"{CREDENTIAL_ENV_VAR} is not set", provider=self.name
            )
        token = base64.b64encode(f"{self._credential.value}:".encode("utf-8")).decode("ascii")
        return {"Authorization": f"Basic {token}"}

    def _classify(self, response: HttpResponse) -> ProviderError | None:
        if 200 <= response.status < 300:
            return None
        error = classify_http_status(response.status, provider=self.name, body_text=response.text()[:500])
        if error.kind is ErrorKind.RATE_LIMIT:
            error.retry_after_s = parse_retry_after(response)
        return error

    def _send(self, request: HttpRequest, *, retry: bool = True) -> HttpResponse:
        """Send a request. `retry=False` is mandatory for anything that creates.

        A timeout or a dropped connection on a create is AMBIGUOUS: the character
        may well have been accepted and be rigging right now. Retrying would then
        buy a second one. Uthana publishes no idempotency key for
        `create_character`, so there is no safe retry to make and the ambiguity is
        surfaced instead of being papered over.
        """
        response, _retries = send_with_retry(
            self.transport,
            request,
            policy=self.retry_policy if retry else NO_RETRY,
            provider=self.name,
            classify=self._classify,
        )
        return response

    def _graphql(self, query: str, variables: dict | None = None, capability=None) -> dict:
        body = {"query": query}
        if variables is not None:
            body["variables"] = variables
        response = self._send(
            HttpRequest(
                method="POST",
                url=f"{self.base_url}{GRAPHQL_PATH}",
                headers={**self._headers(), "Content-Type": "application/json"},
                body=json.dumps(body).encode("utf-8"),
                capability=capability,
            )
        )
        return self._require_graphql_ok(response)

    def _require_graphql_ok(self, response: HttpResponse) -> dict:
        """GraphQL reports failures inside a 200 body; classify those explicitly."""
        payload = response.json()
        errors = payload.get("errors")
        if errors:
            first = errors[0] if isinstance(errors, list) and errors else {}
            extensions = first.get("extensions") or {} if isinstance(first, dict) else {}
            code = str(extensions.get("code", "")).upper()
            kind = ERROR_CODE_MAP.get(code, ErrorKind.PROVIDER_FAILURE)
            message = str(first.get("message", "GraphQL error")) if isinstance(first, dict) else "GraphQL error"
            raise ProviderError(
                kind,
                f"{message} (code={code or 'none'})",
                provider=self.name,
                status=response.status,
                detail={"error_count": len(errors) if isinstance(errors, list) else 1},
            )
        return payload


def _build_multipart(*, operations: dict, file_field: str, file_path: Path) -> tuple[bytes, str]:
    """Encode a GraphQL multipart request (multipart-request-spec)."""
    boundary = f"----assetgen{_stdlib_secrets.token_hex(16)}"
    filename = file_path.name
    mime = "model/gltf-binary" if file_path.suffix.lower() == ".glb" else "application/octet-stream"

    parts: list[bytes] = []

    def add_field(name: str, value: str) -> None:
        parts.append(
            (
                f"--{boundary}\r\n"
                f'Content-Disposition: form-data; name="{name}"\r\n\r\n'
                f"{value}\r\n"
            ).encode("utf-8")
        )

    add_field("operations", json.dumps(operations))
    add_field("map", json.dumps({"0": [file_field]}))
    parts.append(
        (
            f"--{boundary}\r\n"
            f'Content-Disposition: form-data; name="0"; filename="{filename}"\r\n'
            f"Content-Type: {mime}\r\n\r\n"
        ).encode("utf-8")
    )
    parts.append(file_path.read_bytes())
    parts.append(f"\r\n--{boundary}--\r\n".encode("utf-8"))
    return b"".join(parts), f"multipart/form-data; boundary={boundary}"


def _character_summary(character: dict) -> dict:
    assets = [a for a in (character.get("assets") or []) if isinstance(a, dict)]
    return {
        "id": character.get("id"),
        "name": character.get("name"),
        "created": character.get("created"),
        "updated": character.get("updated"),
        "asset_count": len(assets),
        "asset_types": sorted({str(a.get("type", "")) for a in assets}),
        "asset_filenames": sorted(str(a.get("filename", "")) for a in assets),
    }
