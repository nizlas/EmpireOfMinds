# Empire of Minds — repo-root map content loader (bpy-free).
#
# Reads canonical logical-map JSON envelopes under content/maps/.
# Schema authority: docs/MAP_CONTENT.md and the JSON files themselves.

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

SCHEMA_VERSION_V1 = 1
REFERENCE_ORIGIN = "reference"

DEFAULT_REFERENCE_MAP_FILENAME = "handdrawn_test_map_full_01.json"
REFERENCE_MAPS_DIR = Path("content") / "maps" / "reference"


def find_repo_root(start: Path) -> Path:
    start = start.resolve()
    if start.is_file():
        start = start.parent
    for candidate in [start, *start.parents]:
        if (candidate / "game").is_dir() and (candidate / "tools").is_dir():
            return candidate
    raise RuntimeError(f"Could not locate Empire of Minds repo root from: {start}")


def _is_real_file(path: Path) -> bool:
    try:
        return path.is_file()
    except OSError:
        return False


def _collect_candidate_starts(*, extra_starts: tuple[Path, ...] = ()) -> list[Path]:
    starts: list[Path] = []
    seen: set[str] = set()

    def add(path: Path) -> None:
        resolved = path.resolve()
        key = str(resolved)
        if key in seen:
            return
        seen.add(key)
        starts.append(resolved)

    for start in extra_starts:
        add(start)

    try:
        here = Path(__file__)
        if here.is_absolute() and _is_real_file(here):
            add(here)
    except NameError:
        pass

    env_root = os.environ.get("EOM_REPO_ROOT")
    if env_root:
        add(Path(env_root))

    add(Path.cwd())
    return starts


def resolve_repo_root(*, extra_starts: tuple[Path, ...] = ()) -> Path:
    examined = _collect_candidate_starts(extra_starts=extra_starts)
    last_error: RuntimeError | None = None
    for start in examined:
        try:
            return find_repo_root(start)
        except RuntimeError as exc:
            last_error = exc
    raise RuntimeError(
        "Could not locate Empire of Minds repo root.\n"
        f"Candidate start paths: {[str(s) for s in examined]}\n"
        f"EOM_REPO_ROOT: {os.environ.get('EOM_REPO_ROOT')!r}\n"
        f"Last error: {last_error}\n"
        "Fix: run from the repo, set EOM_REPO_ROOT, or open scripts from disk in Blender."
    )


def reference_map_path(
    filename: str = DEFAULT_REFERENCE_MAP_FILENAME,
    *,
    repo_root: Path | None = None,
    extra_starts: tuple[Path, ...] = (),
) -> Path:
    root = repo_root or resolve_repo_root(extra_starts=extra_starts)
    path = root / REFERENCE_MAPS_DIR / filename
    if not path.is_file():
        raise FileNotFoundError(
            f"Reference map not found: {path}\n"
            f"Repo root resolved to: {root}\n"
            f"Expected under: {REFERENCE_MAPS_DIR / filename}"
        )
    return path


def _parse_envelope(raw_text: str, *, source: str) -> dict[str, Any]:
    try:
        envelope = json.loads(raw_text)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"Invalid JSON in map content file {source}: {exc}") from exc
    if not isinstance(envelope, dict):
        raise RuntimeError(f"Map content file {source} must contain a JSON object.")
    return envelope


def _validate_reference_envelope(envelope: dict[str, Any], *, source: str) -> dict[str, Any]:
    schema_version = envelope.get("schema_version")
    if schema_version != SCHEMA_VERSION_V1:
        raise RuntimeError(
            f"Unsupported schema_version in {source}: {schema_version!r} "
            f"(expected {SCHEMA_VERSION_V1})"
        )
    origin = envelope.get("origin")
    if origin != REFERENCE_ORIGIN:
        raise RuntimeError(
            f"Reference map loader expected origin={REFERENCE_ORIGIN!r} in {source}, "
            f"got {origin!r}"
        )
    logical_map = envelope.get("logical_map")
    if not isinstance(logical_map, dict):
        raise RuntimeError(f"Missing or invalid logical_map object in {source}.")
    return envelope


def load_reference_map_envelope(
    filename: str = DEFAULT_REFERENCE_MAP_FILENAME,
    *,
    repo_root: Path | None = None,
    extra_starts: tuple[Path, ...] = (),
) -> dict[str, Any]:
    path = reference_map_path(
        filename, repo_root=repo_root, extra_starts=extra_starts
    )
    raw_text = path.read_text(encoding="utf-8")
    envelope = _parse_envelope(raw_text, source=str(path))
    return _validate_reference_envelope(envelope, source=str(path))


def load_reference_logical_map(
    filename: str = DEFAULT_REFERENCE_MAP_FILENAME,
    *,
    repo_root: Path | None = None,
    extra_starts: tuple[Path, ...] = (),
) -> dict[str, Any]:
    envelope = load_reference_map_envelope(
        filename, repo_root=repo_root, extra_starts=extra_starts
    )
    logical_map = envelope["logical_map"]
    if not isinstance(logical_map, dict):
        raise RuntimeError("logical_map must be a JSON object.")
    return logical_map


def load_reference_map_json_text(
    filename: str = DEFAULT_REFERENCE_MAP_FILENAME,
    *,
    repo_root: Path | None = None,
    extra_starts: tuple[Path, ...] = (),
) -> str:
    logical_map = load_reference_logical_map(
        filename, repo_root=repo_root, extra_starts=extra_starts
    )
    return json.dumps(logical_map, indent=2)
