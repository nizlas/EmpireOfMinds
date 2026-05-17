from __future__ import annotations

from fastapi.testclient import TestClient


def test_create_default_is_prototype_play(client: TestClient) -> None:
    r = client.post("/v1/matches", json={})
    assert r.status_code == 200
    snap = r.json()["snapshot"]
    assert snap["schema_version"] == 2
    assert snap["scenario_id"] == "prototype_play"
    assert snap["scenario"]["map"]["cells"]


def test_create_tiny_test_scenario(client: TestClient) -> None:
    r2 = client.post("/v1/matches", json={"scenario_id": "tiny_test"})
    assert r2.status_code == 200
    assert r2.json()["snapshot"]["scenario_id"] == "tiny_test"
    assert len(r2.json()["snapshot"]["scenario"]["map"]["cells"]) == 7


def test_unknown_scenario_400(client: TestClient) -> None:
    r = client.post("/v1/matches", json={"scenario_id": "nope"})
    assert r.status_code == 400
