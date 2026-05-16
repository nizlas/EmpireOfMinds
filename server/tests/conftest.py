"""Pytest fixtures: isolated data directory per test module."""

from __future__ import annotations

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
