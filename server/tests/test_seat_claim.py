"""API tests for POST /v1/matches/{id}/seats/{actor_id}/claim (C14b)."""

from __future__ import annotations

import json

from fastapi.testclient import TestClient

from app.domain import seats
from app.storage import file_store
from match_helpers import SEAT_TOKEN_HEADER, create_staging_match, post_match_action


def _end_turn(actor_id: int) -> dict:
    return {"schema_version": 1, "action_type": "end_turn", "actor_id": actor_id}


def test_claim_open_seat_returns_only_that_token(client: TestClient) -> None:
    m = create_staging_match(client, {"scenario_id": "tiny_test"})
    mid = m["match_id"]
    r = client.post(f"/v1/matches/{mid}/seats/1/claim")
    assert r.status_code == 200
    body = r.json()
    assert body["match_id"] == mid
    assert body["actor_id"] == 1
    assert body["seat_token"].startswith(seats.SEAT_TOKEN_PREFIX)
    assert body["status"] == seats.STATUS_STAGING
    assert "host_token" not in body
    assert "seats" not in body

    meta = file_store.read_meta(mid)
    assert meta is not None
    seat1 = next(s for s in meta["seats"] if s["actor_id"] == 1)
    assert seat1["claimed"] is True
    assert seat1["token"] == body["seat_token"]


def test_claim_same_seat_twice_rejected(client: TestClient) -> None:
    m = create_staging_match(client, {"scenario_id": "tiny_test"})
    mid = m["match_id"]
    assert client.post(f"/v1/matches/{mid}/seats/0/claim").status_code == 200
    r2 = client.post(f"/v1/matches/{mid}/seats/0/claim")
    assert r2.status_code == 409
    assert r2.json()["detail"] == "seat_already_claimed"


def test_claim_missing_seat_404(client: TestClient) -> None:
    m = create_staging_match(client, {"scenario_id": "tiny_test", "player_ids": [0]})
    r = client.post(f"/v1/matches/{m['match_id']}/seats/9/claim")
    assert r.status_code == 404
    assert r.json()["detail"] == "seat_not_found"


def test_claim_unknown_match_404(client: TestClient) -> None:
    r = client.post("/v1/matches/m_nope/seats/0/claim")
    assert r.status_code == 404
    assert r.json()["detail"] == "match_not_found"


def test_claim_v1_meta_rejects_not_staging(client: TestClient) -> None:
    m = create_staging_match(client, {"scenario_id": "tiny_test"})
    mid = m["match_id"]
    meta = file_store.read_meta(mid)
    assert meta is not None
    meta["schema_version"] = seats.META_SCHEMA_VERSION_V1
    meta.pop("status", None)
    file_store.write_meta(mid, meta)
    r = client.post(f"/v1/matches/{mid}/seats/0/claim")
    assert r.status_code == 409
    assert r.json()["detail"] == "match_not_in_staging"


def test_staging_match_actions_rejected_after_c14d2(client: TestClient) -> None:
    """C14d-2: gameplay actions blocked while status=staging."""
    m = create_staging_match(client, {"scenario_id": "tiny_test"})
    meta = file_store.read_meta(m["match_id"])
    assert meta is not None
    assert seats.match_status(meta) == seats.STATUS_STAGING
    r = post_match_action(client, m["match_id"], _end_turn(0), m["headers"])
    assert r.json()["accepted"] is False
    assert r.json()["reason"] == "match_not_ongoing"


def test_claim_updates_list_open_seat_count(client: TestClient) -> None:
    m = create_staging_match(client, {"scenario_id": "tiny_test"})
    mid = m["match_id"]
    client.post(f"/v1/matches/{mid}/seats/0/claim")
    hit = next(r for r in client.get("/v1/matches").json()["matches"] if r["match_id"] == mid)
    assert hit["open_seat_count"] == 1
    assert next(s for s in hit["seats"] if s["actor_id"] == 0)["claimed"] is True
