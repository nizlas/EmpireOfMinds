"""Shared helpers for seated-match API tests (C13a)."""

from __future__ import annotations

from typing import Any

from fastapi.testclient import TestClient

SEAT_TOKEN_HEADER = "X-Empire-Seat-Token"


def create_seated_match(client: TestClient, body: dict[str, Any] | None = None) -> dict[str, Any]:
    payload = body if body is not None else {}
    r = client.post("/v1/matches", json=payload)
    assert r.status_code == 200, r.text
    data = r.json()
    host = data["host_token"]
    return {
        "match_id": data["match_id"],
        "host_token": host,
        "headers": {SEAT_TOKEN_HEADER: host},
        "data": data,
    }


def post_match_action(
    client: TestClient,
    match_id: str,
    action: dict[str, Any],
    headers: dict[str, str] | None = None,
):
    return client.post(
        f"/v1/matches/{match_id}/actions",
        json=action,
        headers=headers or {},
    )
