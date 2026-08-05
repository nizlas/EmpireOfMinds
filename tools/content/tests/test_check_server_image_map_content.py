"""Unit tests for the automated server-image map-content check.

Covers result parsing, subprocess failure handling, and positive/negative
probe validation with a scripted fake runner — no Docker required.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tools.content.check_server_image_map_content import (  # noqa: E402
    BUILD_TIMEOUT_SECONDS,
    DEFAULT_IMAGE_TAG,
    EXPECTED_CLIFF_EDGE_COUNT,
    EXPECTED_EDGE_COUNT,
    EXPECTED_TILE_COUNT,
    NEGATIVE_PROBE_SNIPPET,
    POSITIVE_PROBE_SNIPPET,
    REFERENCE_HASH,
    REFERENCE_MAP_ID,
    UNKNOWN_MAP_ERROR_NAME,
    UNKNOWN_MAP_ID,
    ImageCheckError,
    PositiveProbeResult,
    check_server_image,
    main,
    negative_probe_mismatches,
    parse_positive_probe_output,
    positive_probe_mismatches,
    run_command,
)

GOLDEN_LINE = (
    f"{REFERENCE_HASH} {EXPECTED_TILE_COUNT} {EXPECTED_EDGE_COUNT} "
    f"{EXPECTED_CLIFF_EDGE_COUNT}"
)
GOLDEN_RESULT = PositiveProbeResult(
    content_hash=REFERENCE_HASH,
    tile_count=EXPECTED_TILE_COUNT,
    edge_count=EXPECTED_EDGE_COUNT,
    cliff_edge_count=EXPECTED_CLIFF_EDGE_COUNT,
)
UNKNOWN_MAP_TRACEBACK = (
    "Traceback (most recent call last):\n"
    '  File "<string>", line 1, in <module>\n'
    "app.domain.map_content_loader.UnknownMapIdError: Unknown map id "
    f"'{UNKNOWN_MAP_ID}'\n"
)


def _completed(
    returncode: int, stdout: str = "", stderr: str = ""
) -> subprocess.CompletedProcess:
    return subprocess.CompletedProcess(
        args=["docker"], returncode=returncode, stdout=stdout, stderr=stderr
    )


class FakeRunner:
    """Scripted subprocess.run stand-in; records every call it receives."""

    def __init__(self, results: list[object]) -> None:
        self._results = list(results)
        self.calls: list[tuple[list[str], dict[str, object]]] = []

    def __call__(self, args, **kwargs):
        self.calls.append((list(args), dict(kwargs)))
        assert self._results, f"unexpected extra command: {args}"
        result = self._results.pop(0)
        if isinstance(result, BaseException):
            raise result
        return result


def _happy_path_runner() -> FakeRunner:
    return FakeRunner(
        [
            _completed(0),  # docker build
            _completed(0, stdout=GOLDEN_LINE + "\n"),  # positive probe
            _completed(1, stderr=UNKNOWN_MAP_TRACEBACK),  # negative probe
        ]
    )


# --- expectation constants (guard against silent drift from the docs) ---


def test_pinned_expectations_match_deploy_doc() -> None:
    assert REFERENCE_HASH == (
        "16cc82c3392c66f1e47273e7da94cf8a804ae9885a051fc81c4b0a9a4261d8c6"
    )
    assert (EXPECTED_TILE_COUNT, EXPECTED_EDGE_COUNT, EXPECTED_CLIFF_EDGE_COUNT) == (
        168,
        452,
        78,
    )
    assert REFERENCE_MAP_ID == "handdrawn_test_map_full_01"
    assert f"load_world_map('{REFERENCE_MAP_ID}')" in POSITIVE_PROBE_SNIPPET
    assert f"load_world_map('{UNKNOWN_MAP_ID}')" in NEGATIVE_PROBE_SNIPPET


# --- positive probe result parsing ---


def test_parse_valid_output() -> None:
    assert parse_positive_probe_output(GOLDEN_LINE + "\n") == GOLDEN_RESULT


def test_parse_uses_last_non_empty_line() -> None:
    noisy = "some startup noise\n\n" + GOLDEN_LINE + "\n\n"
    assert parse_positive_probe_output(noisy) == GOLDEN_RESULT


def test_parse_empty_output_rejected() -> None:
    with pytest.raises(ImageCheckError, match="no output"):
        parse_positive_probe_output("\n  \n")


def test_parse_wrong_field_count_rejected() -> None:
    with pytest.raises(ImageCheckError, match="unexpected shape"):
        parse_positive_probe_output(f"{REFERENCE_HASH} 168 452\n")


@pytest.mark.parametrize("bad_line", [
    f"{REFERENCE_HASH} abc 452 78",
    f"{REFERENCE_HASH} 168 452 7.5",
])
def test_parse_non_integer_count_rejected(bad_line: str) -> None:
    with pytest.raises(ImageCheckError, match="not an integer"):
        parse_positive_probe_output(bad_line + "\n")


# --- positive probe validation ---


def test_positive_probe_golden_values_pass() -> None:
    assert positive_probe_mismatches(GOLDEN_RESULT) == []


@pytest.mark.parametrize(
    ("field", "wrong_value", "needle"),
    [
        ("content_hash", "0" * 64, "content_hash mismatch"),
        ("tile_count", 167, "tile_count mismatch"),
        ("edge_count", 451, "edge_count mismatch"),
        ("cliff_edge_count", 0, "cliff_edge_count mismatch"),
    ],
)
def test_positive_probe_mismatch_reported(field: str, wrong_value, needle: str) -> None:
    values = {
        "content_hash": REFERENCE_HASH,
        "tile_count": EXPECTED_TILE_COUNT,
        "edge_count": EXPECTED_EDGE_COUNT,
        "cliff_edge_count": EXPECTED_CLIFF_EDGE_COUNT,
    }
    values[field] = wrong_value
    mismatches = positive_probe_mismatches(PositiveProbeResult(**values))
    assert len(mismatches) == 1
    assert needle in mismatches[0]
    assert str(wrong_value) in mismatches[0]


def test_positive_probe_reports_every_mismatch() -> None:
    result = PositiveProbeResult(
        content_hash="0" * 64, tile_count=1, edge_count=2, cliff_edge_count=3
    )
    mismatches = positive_probe_mismatches(result)
    assert len(mismatches) == 4


# --- negative probe validation ---


def test_negative_probe_unknown_map_error_accepted() -> None:
    assert negative_probe_mismatches(1, "", UNKNOWN_MAP_TRACEBACK) == []


def test_negative_probe_success_rejected() -> None:
    mismatches = negative_probe_mismatches(0, "", "")
    assert len(mismatches) == 1
    assert "unexpectedly succeeded" in mismatches[0]
    assert UNKNOWN_MAP_ERROR_NAME in mismatches[0]


def test_negative_probe_wrong_error_rejected() -> None:
    mismatches = negative_probe_mismatches(1, "", "ModuleNotFoundError: no module")
    assert len(mismatches) == 1
    assert "wrong reason" in mismatches[0]
    assert "ModuleNotFoundError" in mismatches[0]


# --- subprocess failure handling ---


def test_missing_docker_executable_is_actionable() -> None:
    runner = FakeRunner([FileNotFoundError("docker")])
    with pytest.raises(ImageCheckError, match="not found"):
        run_command(["docker", "build"], 10.0, runner)


def test_command_timeout_is_actionable() -> None:
    runner = FakeRunner([subprocess.TimeoutExpired(cmd=["docker"], timeout=10.0)])
    with pytest.raises(ImageCheckError, match="timed out"):
        run_command(["docker", "build"], 10.0, runner)


def test_build_failure_reports_stderr() -> None:
    runner = FakeRunner([_completed(1, stderr="ERROR: failed to solve: base image")])
    with pytest.raises(ImageCheckError, match="docker build failed") as exc_info:
        check_server_image(runner=runner)
    assert "failed to solve" in str(exc_info.value)


def test_positive_probe_container_failure_reports_output() -> None:
    runner = FakeRunner(
        [
            _completed(0),
            _completed(2, stderr="ImportError: cannot import name"),
        ]
    )
    with pytest.raises(ImageCheckError, match="positive probe container failed") as exc_info:
        check_server_image(runner=runner)
    assert "ImportError" in str(exc_info.value)


def test_missing_dockerfile_rejected(tmp_path: Path) -> None:
    runner = FakeRunner([])
    with pytest.raises(ImageCheckError, match="Dockerfile"):
        check_server_image(repo_root=tmp_path, runner=runner)
    assert runner.calls == []


# --- end-to-end orchestration with the fake runner ---


def test_check_server_image_happy_path_commands() -> None:
    runner = _happy_path_runner()
    result = check_server_image(runner=runner, log=lambda _line: None)
    assert result == GOLDEN_RESULT

    assert len(runner.calls) == 3
    build_args, build_kwargs = runner.calls[0]
    assert build_args[:4] == ["docker", "build", "-t", DEFAULT_IMAGE_TAG]
    assert Path(build_args[4]) == REPO_ROOT / "server"
    assert build_kwargs["timeout"] == BUILD_TIMEOUT_SECONDS

    positive_args, _ = runner.calls[1]
    assert positive_args[:4] == ["docker", "run", "--rm", DEFAULT_IMAGE_TAG]
    assert positive_args[4:6] == ["python", "-c"]
    assert positive_args[6] == POSITIVE_PROBE_SNIPPET

    negative_args, _ = runner.calls[2]
    assert negative_args[:4] == ["docker", "run", "--rm", DEFAULT_IMAGE_TAG]
    assert negative_args[6] == NEGATIVE_PROBE_SNIPPET


def test_check_server_image_honours_tag_and_docker_override() -> None:
    runner = _happy_path_runner()
    check_server_image(
        image_tag="empire-server-ci",
        docker_executable="podman",
        runner=runner,
        log=lambda _line: None,
    )
    for args, _kwargs in runner.calls:
        assert args[0] == "podman"
        assert "empire-server-ci" in args


def test_main_success_exit_zero(capsys: pytest.CaptureFixture[str]) -> None:
    assert main([], runner=_happy_path_runner()) == 0
    captured = capsys.readouterr()
    assert "OK:" in captured.out
    assert REFERENCE_HASH in captured.out


def test_main_mismatch_exit_nonzero(capsys: pytest.CaptureFixture[str]) -> None:
    wrong_hash_line = GOLDEN_LINE.replace(REFERENCE_HASH, "0" * 64)
    runner = FakeRunner(
        [
            _completed(0),
            _completed(0, stdout=wrong_hash_line + "\n"),
        ]
    )
    assert main([], runner=runner) == 1
    captured = capsys.readouterr()
    assert "ERROR:" in captured.err
    assert "content_hash mismatch" in captured.err


def test_main_negative_probe_violation_exit_nonzero(
    capsys: pytest.CaptureFixture[str],
) -> None:
    runner = FakeRunner(
        [
            _completed(0),
            _completed(0, stdout=GOLDEN_LINE + "\n"),
            _completed(0),  # unknown map id loads without error
        ]
    )
    assert main([], runner=runner) == 1
    captured = capsys.readouterr()
    assert "ERROR:" in captured.err
    assert "unexpectedly succeeded" in captured.err


def test_main_docker_missing_exit_nonzero(capsys: pytest.CaptureFixture[str]) -> None:
    runner = FakeRunner([FileNotFoundError("docker")])
    assert main([], runner=runner) == 1
    captured = capsys.readouterr()
    assert "ERROR:" in captured.err
    assert "not found" in captured.err
