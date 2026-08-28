"""An independent reader for the GraphQL multipart-request specification.

WHY THIS EXISTS. The forensic review (HIGH 8) found the Uthana double routing
requests by asking `if b"create_character" in body`. That substring survives
almost any protocol mistake: renaming the `operations` part to `ops`, renaming
`map` to `m`, changing the mapped variable path, or moving the file to a different
field all leave `create_character` sitting in the body, so the double kept
answering `200 OK` and the tests kept passing. The double was confirming that the
adapter had produced SOME bytes containing a word, not that it had produced a
request the real endpoint would accept.

WHAT MAKES THIS AN ORACLE RATHER THAN AN ECHO. It is written from the published
`multipart/form-data` and graphql-multipart-request specifications, not from the
production encoder. It shares no constant, no boundary generator and no field name
with `providers/uthana.py`; the expectations below are typed out again on purpose,
because a test that imports the thing it is testing proves only self-consistency.
If the adapter renames a part, this reader says so and names the part.

It parses by hand rather than via `email` or `cgi` for the same reason: those
modules are lenient in ways a wire-format check must not be, and reading the
delimiters directly is what makes a malformed body detectable rather than
silently repaired.
"""

from __future__ import annotations

import json
from dataclasses import dataclass


class MultipartProtocolError(AssertionError):
    """The request does not satisfy the multipart GraphQL specification.

    An `AssertionError` on purpose: a protocol mistake made by the adapter is a
    test failure, and it must name the exact part that is wrong so the failure
    reads as a diagnosis rather than "the double said no".
    """


#: The specification's required part names. Typed out independently of the
#: production encoder - that is the whole point of this module.
REQUIRED_OPERATIONS_FIELD = "operations"
REQUIRED_MAP_FIELD = "map"


@dataclass(frozen=True)
class MultipartPart:
    name: str
    filename: str
    content_type: str
    data: bytes

    @property
    def text(self) -> str:
        return self.data.decode("utf-8", errors="replace")


@dataclass(frozen=True)
class GraphQLUpload:
    """A fully validated multipart GraphQL upload."""

    query: str
    variables: dict
    file_field: str
    file_bytes: bytes
    file_name: str

    def operation_contains(self, needle: str) -> bool:
        return needle in self.query


def parse_multipart(body: bytes, content_type: str) -> list[MultipartPart]:
    """Split a multipart body strictly, by its declared boundary."""
    if not content_type or "multipart/form-data" not in content_type.lower():
        raise MultipartProtocolError(
            f"Content-Type must declare multipart/form-data, got {content_type!r}"
        )
    marker = "boundary="
    if marker not in content_type:
        raise MultipartProtocolError(f"Content-Type declares no boundary: {content_type!r}")
    boundary = content_type.split(marker, 1)[1].split(";")[0].strip().strip('"')
    if not boundary:
        raise MultipartProtocolError("Content-Type declares an empty boundary")

    delimiter = b"--" + boundary.encode("ascii")
    if not body.startswith(delimiter):
        raise MultipartProtocolError("body does not begin with the declared boundary delimiter")
    if not body.rstrip(b"\r\n").endswith(delimiter + b"--"):
        raise MultipartProtocolError("body is not terminated by the closing boundary delimiter")

    parts: list[MultipartPart] = []
    for raw in body.split(delimiter)[1:]:
        stripped = raw.lstrip(b"\r\n")
        if stripped.startswith(b"--"):
            break
        if b"\r\n\r\n" not in stripped:
            raise MultipartProtocolError(
                "a multipart section has no blank line separating headers from data"
            )
        head, data = stripped.split(b"\r\n\r\n", 1)
        headers: dict[str, str] = {}
        for line in head.decode("utf-8", errors="replace").split("\r\n"):
            if not line.strip():
                continue
            if ":" not in line:
                raise MultipartProtocolError(f"malformed multipart header line: {line!r}")
            key, value = line.split(":", 1)
            headers[key.strip().lower()] = value.strip()
        disposition = headers.get("content-disposition", "")
        if "form-data" not in disposition:
            raise MultipartProtocolError(
                f"a section has no `Content-Disposition: form-data` header: {disposition!r}"
            )
        parts.append(
            MultipartPart(
                name=_disposition_value(disposition, "name"),
                filename=_disposition_value(disposition, "filename"),
                content_type=headers.get("content-type", ""),
                data=data.rstrip(b"\r\n"),
            )
        )
    if not parts:
        raise MultipartProtocolError("multipart body contains no sections")
    return parts


def read_graphql_upload(body: bytes, content_type: str) -> GraphQLUpload:
    """Validate a graphql-multipart-request upload end to end.

    Checks, in order, the things a renamed field would break: the two required
    part names, that both are valid JSON, that the map points at a part that
    exists, and that the variable path the map names is actually `null` in the
    operations document - which is what tells the server where to inject the file.
    """
    parts = parse_multipart(body, content_type)
    by_name = {part.name: part for part in parts}

    if REQUIRED_OPERATIONS_FIELD not in by_name:
        raise MultipartProtocolError(
            f"required part {REQUIRED_OPERATIONS_FIELD!r} is missing; parts present: "
            f"{sorted(by_name)}. The GraphQL multipart specification names this field exactly."
        )
    if REQUIRED_MAP_FIELD not in by_name:
        raise MultipartProtocolError(
            f"required part {REQUIRED_MAP_FIELD!r} is missing; parts present: {sorted(by_name)}"
        )

    try:
        operations = json.loads(by_name[REQUIRED_OPERATIONS_FIELD].text)
    except json.JSONDecodeError as exc:
        raise MultipartProtocolError(f"the {REQUIRED_OPERATIONS_FIELD!r} part is not JSON: {exc}")
    try:
        mapping = json.loads(by_name[REQUIRED_MAP_FIELD].text)
    except json.JSONDecodeError as exc:
        raise MultipartProtocolError(f"the {REQUIRED_MAP_FIELD!r} part is not JSON: {exc}")

    if not isinstance(operations, dict) or "query" not in operations:
        raise MultipartProtocolError("the operations part must be an object containing 'query'")
    if not isinstance(mapping, dict) or not mapping:
        raise MultipartProtocolError("the map part must be a non-empty object")

    file_field, paths = next(iter(mapping.items()))
    if file_field not in by_name:
        raise MultipartProtocolError(
            f"the map points at part {file_field!r}, which is not in the request; parts present: "
            f"{sorted(by_name)}"
        )
    if not isinstance(paths, list) or not paths:
        raise MultipartProtocolError(
            f"the map entry for {file_field!r} must be a non-empty list of variable paths"
        )
    variable_path = str(paths[0])
    variables = operations.get("variables")
    if not isinstance(variables, dict):
        raise MultipartProtocolError("the operations part declares no 'variables' object")
    _assert_null_at(variables, variable_path)

    upload = by_name[file_field]
    if not upload.filename:
        raise MultipartProtocolError(
            f"the file part {file_field!r} has no filename in its Content-Disposition"
        )
    return GraphQLUpload(
        query=str(operations["query"]),
        variables=variables,
        file_field=file_field,
        file_bytes=upload.data,
        file_name=upload.filename,
    )


def _assert_null_at(variables: dict, dotted_path: str) -> None:
    """The mapped variable must exist and be `null` in the operations document."""
    parts = dotted_path.split(".")
    if parts and parts[0] == "variables":
        parts = parts[1:]
    if not parts:
        raise MultipartProtocolError(f"map path {dotted_path!r} names no variable")
    cursor: object = variables
    walked: list[str] = []
    for key in parts:
        walked.append(key)
        if not isinstance(cursor, dict) or key not in cursor:
            raise MultipartProtocolError(
                f"map path {dotted_path!r} points at variables.{'.'.join(walked)}, which does "
                "not exist in the operations document. The server would have nowhere to inject "
                "the file."
            )
        cursor = cursor[key]
    if cursor is not None:
        raise MultipartProtocolError(
            f"variables.{dotted_path.removeprefix('variables.')} must be null so the server "
            f"knows to substitute the uploaded file; it is {cursor!r}"
        )


def _disposition_value(disposition: str, key: str) -> str:
    for chunk in disposition.split(";"):
        chunk = chunk.strip()
        if chunk.lower().startswith(f"{key}="):
            return chunk.split("=", 1)[1].strip().strip('"')
    return ""
