#!/usr/bin/env python3
"""Automated post-build server-image map-content check (N5 packaging).

Automates the manual probes documented in docs/DEPLOY_HETZNER.md
("Post-build content check"): builds server/Dockerfile, then runs disposable
containers (`docker run --rm`) to verify that the packaged server loader

- loads `handdrawn_test_map_full_01` with the pinned golden raw-byte hash and
  the expected tile / edge / cliff-edge counts (positive probe), and
- fails explicitly with `UnknownMapIdError` for an unknown map id
  (negative probe).

Exits non-zero with an actionable diagnostic on any mismatch or Docker
failure. Requires a working Docker installation; the unit tests under
tools/content/tests/ exercise parsing and validation without Docker.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable

REPO_ROOT = Path(__file__).resolve().parents[2]

DEFAULT_IMAGE_TAG = "empire-server"
DEFAULT_DOCKER_EXECUTABLE = "docker"
SERVER_BUILD_CONTEXT_REL = Path("server")
BUILD_TIMEOUT_SECONDS = 1800
RUN_TIMEOUT_SECONDS = 300

REFERENCE_MAP_ID = "handdrawn_test_map_full_01"
REFERENCE_HASH = "16cc82c3392c66f1e47273e7da94cf8a804ae9885a051fc81c4b0a9a4261d8c6"
EXPECTED_TILE_COUNT = 168
EXPECTED_EDGE_COUNT = 452
EXPECTED_CLIFF_EDGE_COUNT = 78
UNKNOWN_MAP_ID = "no_such_map"
UNKNOWN_MAP_ERROR_NAME = "UnknownMapIdError"

# Same probes as the raw commands in docs/DEPLOY_HETZNER.md.
POSITIVE_PROBE_SNIPPET = (
    "from app.domain.map_content_loader import load_world_map; "
    f"wm = load_world_map('{REFERENCE_MAP_ID}'); "
    "print(wm.identity.content_hash, wm.tile_count(), wm.edge_count(), "
    "wm.cliff_edge_count())"
)
NEGATIVE_PROBE_SNIPPET = (
    "from app.domain.map_content_loader import load_world_map; "
    f"load_world_map('{UNKNOWN_MAP_ID}')"
)

Runner = Callable[..., "subprocess.CompletedProcess[str]"]


class ImageCheckError(RuntimeError):
    """Controlled failure: Docker problem or packaged-content mismatch."""


@dataclass(frozen=True)
class PositiveProbeResult:
    content_hash: str
    tile_count: int
    edge_count: int
    cliff_edge_count: int


def _tail(text: str, max_lines: int = 20) -> str:
    lines = [line for line in text.splitlines() if line.strip()]
    return "\n".join(lines[-max_lines:])


def run_command(
    args: list[str],
    timeout_seconds: float,
    runner: Runner = subprocess.run,
) -> "subprocess.CompletedProcess[str]":
    """Run one Docker CLI command; typed failure instead of raw exceptions."""
    display = " ".join(args)
    try:
        return runner(args, capture_output=True, text=True, timeout=timeout_seconds)
    except FileNotFoundError as exc:
        raise ImageCheckError(
            f"Docker executable {args[0]!r} was not found. Install Docker (or "
            "pass --docker <executable>) and ensure it is on PATH, then rerun."
        ) from exc
    except subprocess.TimeoutExpired as exc:
        raise ImageCheckError(
            f"Command timed out after {timeout_seconds:.0f}s: {display}. "
            "Check that the Docker daemon is running and responsive, then rerun."
        ) from exc
    except OSError as exc:
        raise ImageCheckError(f"Failed to start command {display!r}: {exc}") from exc


def parse_positive_probe_output(stdout: str) -> PositiveProbeResult:
    """Parse `<hash> <tiles> <edges> <cliff_edges>` from the probe stdout.

    Uses the last non-empty line so incidental container noise before the
    probe's print does not break parsing.
    """
    lines = [line.strip() for line in stdout.splitlines() if line.strip()]
    if not lines:
        raise ImageCheckError(
            "Positive probe printed no output; expected "
            "'<content_hash> <tiles> <edges> <cliff_edges>' from the packaged "
            "loader. Inspect the container manually (see DEPLOY_HETZNER.md "
            "troubleshooting fallback)."
        )
    fields = lines[-1].split()
    if len(fields) != 4:
        raise ImageCheckError(
            "Positive probe output has unexpected shape; expected 4 fields "
            f"'<content_hash> <tiles> <edges> <cliff_edges>', got: {lines[-1]!r}"
        )
    counts: list[int] = []
    for label, field in zip(("tiles", "edges", "cliff_edges"), fields[1:]):
        try:
            counts.append(int(field))
        except ValueError as exc:
            raise ImageCheckError(
                f"Positive probe {label} count is not an integer: {field!r} "
                f"(full line: {lines[-1]!r})"
            ) from exc
    return PositiveProbeResult(
        content_hash=fields[0],
        tile_count=counts[0],
        edge_count=counts[1],
        cliff_edge_count=counts[2],
    )


def positive_probe_mismatches(result: PositiveProbeResult) -> list[str]:
    """Diagnostics for every expected-vs-actual mismatch (empty list == OK)."""
    mismatches: list[str] = []
    if result.content_hash != REFERENCE_HASH:
        mismatches.append(
            f"content_hash mismatch: expected {REFERENCE_HASH}, got "
            f"{result.content_hash} — the packaged copy is not byte-identical "
            "to canonical content/maps; run "
            "'python tools/content/sync_map_content.py check' and rebuild."
        )
    for label, expected, actual in (
        ("tile_count", EXPECTED_TILE_COUNT, result.tile_count),
        ("edge_count", EXPECTED_EDGE_COUNT, result.edge_count),
        ("cliff_edge_count", EXPECTED_CLIFF_EDGE_COUNT, result.cliff_edge_count),
    ):
        if actual != expected:
            mismatches.append(
                f"{label} mismatch: expected {expected}, got {actual} — the "
                f"packaged {REFERENCE_MAP_ID} does not match the pinned "
                "reference map."
            )
    return mismatches


def negative_probe_mismatches(returncode: int, stdout: str, stderr: str) -> list[str]:
    """The unknown-map probe must fail loudly with UnknownMapIdError."""
    combined = f"{stdout}\n{stderr}"
    if returncode == 0:
        return [
            f"negative probe unexpectedly succeeded: loading unknown map id "
            f"{UNKNOWN_MAP_ID!r} must fail with {UNKNOWN_MAP_ERROR_NAME} — the "
            "packaged loader is not rejecting unknown map ids."
        ]
    if UNKNOWN_MAP_ERROR_NAME not in combined:
        return [
            f"negative probe failed for the wrong reason: expected "
            f"{UNKNOWN_MAP_ERROR_NAME} for unknown map id {UNKNOWN_MAP_ID!r}, "
            f"got (exit {returncode}):\n{_tail(combined)}"
        ]
    return []


def check_server_image(
    repo_root: Path = REPO_ROOT,
    image_tag: str = DEFAULT_IMAGE_TAG,
    docker_executable: str = DEFAULT_DOCKER_EXECUTABLE,
    runner: Runner = subprocess.run,
    log: Callable[[str], Any] = print,
) -> PositiveProbeResult:
    """Build server/Dockerfile and verify packaged map content from containers."""
    build_context = repo_root / SERVER_BUILD_CONTEXT_REL
    if not (build_context / "Dockerfile").is_file():
        raise ImageCheckError(
            f"Missing {build_context / 'Dockerfile'}; run from the Empire of "
            "Minds repository (or pass --repo-root)."
        )

    log(f"Building server image {image_tag!r} from {build_context.as_posix()}/ ...")
    build = run_command(
        [docker_executable, "build", "-t", image_tag, str(build_context)],
        BUILD_TIMEOUT_SECONDS,
        runner,
    )
    if build.returncode != 0:
        raise ImageCheckError(
            f"docker build failed (exit {build.returncode}). Last output:\n"
            f"{_tail(build.stderr or build.stdout)}"
        )

    log(f"Positive probe: loading {REFERENCE_MAP_ID!r} in a disposable container ...")
    positive = run_command(
        [docker_executable, "run", "--rm", image_tag, "python", "-c", POSITIVE_PROBE_SNIPPET],
        RUN_TIMEOUT_SECONDS,
        runner,
    )
    if positive.returncode != 0:
        raise ImageCheckError(
            f"positive probe container failed (exit {positive.returncode}): the "
            f"packaged loader could not load {REFERENCE_MAP_ID!r}. Last output:\n"
            f"{_tail(positive.stderr or positive.stdout)}"
        )
    result = parse_positive_probe_output(positive.stdout)
    mismatches = positive_probe_mismatches(result)
    if mismatches:
        raise ImageCheckError("packaged map content mismatch:\n" + "\n".join(mismatches))

    log(f"Negative probe: unknown map id {UNKNOWN_MAP_ID!r} must fail loudly ...")
    negative = run_command(
        [docker_executable, "run", "--rm", image_tag, "python", "-c", NEGATIVE_PROBE_SNIPPET],
        RUN_TIMEOUT_SECONDS,
        runner,
    )
    mismatches = negative_probe_mismatches(
        negative.returncode, negative.stdout, negative.stderr
    )
    if mismatches:
        raise ImageCheckError("negative probe contract violated:\n" + "\n".join(mismatches))

    return result


def main(argv: list[str] | None = None, runner: Runner = subprocess.run) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Build server/Dockerfile and verify the packaged canonical map "
            "content from disposable containers (docs/DEPLOY_HETZNER.md "
            "post-build content check)."
        )
    )
    parser.add_argument(
        "--image-tag",
        default=DEFAULT_IMAGE_TAG,
        help=f"Docker image tag to build and probe (default: {DEFAULT_IMAGE_TAG})",
    )
    parser.add_argument(
        "--docker",
        default=DEFAULT_DOCKER_EXECUTABLE,
        help=f"Docker executable to invoke (default: {DEFAULT_DOCKER_EXECUTABLE})",
    )
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=None,
        help="Repository root override (defaults to script location)",
    )
    args = parser.parse_args(argv)
    repo_root = args.repo_root.resolve() if args.repo_root else REPO_ROOT

    try:
        result = check_server_image(
            repo_root=repo_root,
            image_tag=args.image_tag,
            docker_executable=args.docker,
            runner=runner,
        )
    except ImageCheckError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    print(
        f"OK: image {args.image_tag!r} serves {REFERENCE_MAP_ID!r} with "
        f"content_hash {result.content_hash}, {result.tile_count} tiles, "
        f"{result.edge_count} edges, {result.cliff_edge_count} cliff edges; "
        f"unknown map id fails with {UNKNOWN_MAP_ERROR_NAME}."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
