"""Pytest fixtures: isolated data directory per test module."""

from __future__ import annotations

import sys
from pathlib import Path

_tests_dir = Path(__file__).resolve().parent
if str(_tests_dir) not in sys.path:
    sys.path.insert(0, str(_tests_dir))

import pytest
from fastapi.testclient import TestClient


@pytest.fixture
def client(tmp_path, monkeypatch) -> TestClient:
    data = tmp_path / "data"
    data.mkdir()
    monkeypatch.setenv("EMPIRE_SERVER_DATA_DIR", str(data))
    from app.main import app

    with TestClient(app) as c:
        yield c
