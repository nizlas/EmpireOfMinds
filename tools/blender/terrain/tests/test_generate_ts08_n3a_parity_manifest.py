"""Tests for N3a compact parity manifest generator."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent.parent
REPO_ROOT = SCRIPT_DIR.parents[2]
GENERATOR = SCRIPT_DIR / "generate_ts08_n3a_parity_manifest.py"


def test_n3a_parity_manifest_matches_n2() -> None:
    result = subprocess.run(
        [sys.executable, str(GENERATOR), "check"],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr or result.stdout
