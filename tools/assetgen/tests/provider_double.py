"""An offline stand-in for the real Uthana endpoint.

WHY A PROTOCOL DOUBLE AND NOT A MOCKED ADAPTER. Mocking `UthanaProvider.submit`
would prove the orchestrator calls it, and nothing else. It would not exercise the
multipart encoding, the GraphQL-200-with-errors quirk, the "no bundle asset yet
means still rigging" polling rule, or the authenticated bundle download - the
places where a wrong assumption becomes a wasted paid character.

So this double speaks the real transport contract instead: it answers
`HttpRequest`s the way the documented endpoint does, and the production adapter
runs unmodified on top of it. Every failure mode the first live smoke could hit is
scriptable here, and every call is COUNTED, so a test can assert that exactly one
create happened rather than trusting a status field that says so.

It sends nothing. It is a pure function from request to response, which is why the
socket tripwire in `conftest.py` never fires for it.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field

from tools.assetgen.errors import ErrorKind, ProviderError
from tools.assetgen.transport import HttpRequest, HttpResponse

from .multipart_oracle import MultipartProtocolError, read_graphql_upload


def _header(headers: dict, name: str) -> str:
    """Case-insensitive lookup: HTTP header names are not case sensitive."""
    for key, value in (headers or {}).items():
        if str(key).lower() == name.lower():
            return str(value)
    return ""

#: A plausible but obviously synthetic GLB. Structurally a valid glTF container
#: header, which is all the download path inspects; the real structural checks
#: happen inside Godot, which this double does not stand in for.
def synthetic_glb_bytes(payload: bytes = b'{"asset":{"version":"2.0"}}') -> bytes:
    import struct

    padded = payload + b" " * ((4 - len(payload) % 4) % 4)
    chunk = struct.pack("<II", len(padded), 0x4E4F534A) + padded
    return b"glTF" + struct.pack("<II", 2, 12 + len(chunk)) + chunk


CORRUPT_GLB_BYTES = b"this is not a glTF container at all"


@dataclass
class UthanaDouble:
    """Scriptable offline Uthana. Counts every call it is asked to make."""

    character_id: str = "chr-double-0001"
    #: How many polls report "still rigging" before the bundle appears.
    pending_polls: int = 1
    #: Set to raise on the CREATE call, simulating an ambiguous transport fault.
    create_raises: ProviderError | None = None
    #: Set to answer the CREATE with a classified provider error instead.
    create_response: HttpResponse | None = None
    #: Terminal provider-side failure reported while polling.
    fail_after_polls: int | None = None
    #: Serve a download that is not a usable GLB.
    corrupt_download: bool = False
    #: Serve nothing at all for the bundle.
    missing_download: bool = False
    #: Number of download attempts that fail transiently before succeeding.
    download_transient_failures: int = 0
    glb_bytes: bytes = field(default_factory=synthetic_glb_bytes)

    create_calls: int = 0
    poll_calls: int = 0
    download_calls: int = 0
    seen_authorization: list[str] = field(default_factory=list)
    #: The last upload the protocol oracle accepted, so a test can assert on the
    #: parsed request rather than on the raw bytes.
    last_upload: object | None = None

    @property
    def total_calls(self) -> int:
        return self.create_calls + self.poll_calls + self.download_calls

    def send(self, request: HttpRequest) -> HttpResponse:
        # Recorded so a test can prove an auth header was formed on the live path
        # and, more importantly, that its value never reaches a report.
        if "Authorization" in request.headers:
            self.seen_authorization.append(request.headers["Authorization"])

        if request.method == "GET" and "/motion/bundle/" in request.url:
            return self._download()
        if request.method == "POST" and request.url.endswith("/graphql"):
            content_type = _header(request.headers, "content-type")
            if "multipart/form-data" in content_type.lower():
                # ROUTED BY PROTOCOL, NOT BY SUBSTRING. `read_graphql_upload`
                # raises if `operations` or `map` is renamed, if either is not
                # JSON, if the map points at a missing part, or if the mapped
                # variable is not null - each of which the old `b"create_character"
                # in body` check accepted. The upload is what a create IS; a body
                # that merely mentions the word is not one.
                upload = read_graphql_upload(request.body or b"", content_type)
                self.last_upload = upload
                if not upload.operation_contains("create_character"):
                    raise MultipartProtocolError(
                        "a multipart upload arrived whose GraphQL document is not "
                        f"create_character: {upload.query[:120]!r}"
                    )
                self._assert_create_variables(upload)
                return self._create()
            body = request.body or b""
            if b"create_character" in body:
                raise MultipartProtocolError(
                    "create_character was sent as a plain JSON body. The endpoint only accepts "
                    "it as a multipart upload, so this request would be rejected on the wire."
                )
            if b"Character(" in body or b"character(id" in body:
                return self._poll()
            if b"org {" in body:
                return _json(200, {"data": {"org": {"id": "org-double", "name": "double"}}})
        raise AssertionError(f"the double was asked something unscripted: {request.method} {request.url}")

    def _assert_create_variables(self, upload) -> None:
        """The variables the endpoint actually requires, listed independently.

        Written out here rather than imported from the adapter, so renaming a
        GraphQL parameter on the production side turns a test red instead of
        redefining what "correct" means.
        """
        variables = upload.variables
        for required in ("name", "auto_rig", "include_fingers", "file"):
            if required not in variables:
                raise MultipartProtocolError(
                    f"create_character variables are missing {required!r}; got "
                    f"{sorted(variables)}"
                )
        if not str(variables.get("name") or "").strip():
            raise MultipartProtocolError("create_character requires a non-empty 'name'")
        if variables.get("include_fingers") is not True:
            raise MultipartProtocolError(
                "this project's rig contract requires include_fingers=true; got "
                f"{variables.get('include_fingers')!r}"
            )
        if not upload.file_bytes:
            raise MultipartProtocolError("the uploaded file part is empty")

    # ------------------------------------------------------------------ handlers

    def _create(self) -> HttpResponse:
        self.create_calls += 1
        if self.create_raises is not None:
            raise self.create_raises
        if self.create_response is not None:
            return self.create_response
        return _json(
            200,
            {
                "data": {
                    "create_character": {
                        "character": {"id": self.character_id, "name": "double"},
                        "auto_rig_confidence": 0.91,
                    }
                }
            },
        )

    def _poll(self) -> HttpResponse:
        self.poll_calls += 1
        if self.fail_after_polls is not None and self.poll_calls > self.fail_after_polls:
            # GraphQL reports failures inside a 200 body; that is the quirk the
            # adapter must handle, so the double reproduces it faithfully.
            return _json(
                200,
                {
                    "errors": [
                        {
                            "message": "auto-rig could not find a humanoid skeleton",
                            "extensions": {"code": "INTERNAL_RIG_FAILURE"},
                        }
                    ]
                },
            )
        assets = []
        if self.poll_calls > self.pending_polls:
            assets = [
                {
                    "id": "asset-bundle",
                    "filename": "character.glb",
                    "mimetype": "model/gltf-binary",
                    "type": "bundle",
                    "sha256": "0" * 64,
                    "size": len(self.glb_bytes),
                }
            ]
        return _json(
            200,
            {
                "data": {
                    "character": {
                        "id": self.character_id,
                        "name": "double",
                        "created": "2026-08-28T00:00:00Z",
                        "updated": "2026-08-28T00:01:00Z",
                        "deleted": False,
                        "assets": assets,
                    }
                }
            },
        )

    def _download(self) -> HttpResponse:
        self.download_calls += 1
        if self.download_calls <= self.download_transient_failures:
            return HttpResponse(status=503, body=b"upstream busy")
        if self.missing_download:
            return HttpResponse(status=404, body=b"no such bundle")
        if self.corrupt_download:
            return HttpResponse(status=200, body=CORRUPT_GLB_BYTES)
        return HttpResponse(status=200, body=self.glb_bytes)


def transport_fault() -> ProviderError:
    """The ambiguous case: the create may or may not have been accepted."""
    return ProviderError(ErrorKind.TRANSPORT, "connection reset while uploading the character")


def _json(status: int, payload: dict) -> HttpResponse:
    return HttpResponse(
        status=status,
        headers={"Content-Type": "application/json"},
        body=json.dumps(payload).encode("utf-8"),
    )
