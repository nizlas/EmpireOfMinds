"""API tests for server display_name metadata and PATCH rename (C14b.1)."""

from __future__ import annotations

import json

from fastapi.testclient import TestClient

from app.domain import seats, state_hash
from app.storage import file_store
from match_helpers import SEAT_TOKEN_HEADER, create_seated_match


def test_create_sets_display_name_default(client: TestClient) -> None:
    r = client.post("/v1/matches", json={"scenario_id": "tiny_test"})
    assert r.status_code == 200
    data = r.json()
    mid = data["match_id"]
    assert data["display_name"] == seats.default_display_name(mid)
    meta = file_store.read_meta(mid)
    assert meta is not None
    assert meta["display_name"] == data["display_name"]


def test_create_accepts_custom_display_name(client: TestClient) -> None:
    r = client.post(
        "/v1/matches",
        json={"scenario_id": "tiny_test", "display_name": "  Saturday test  "},
    )
    assert r.status_code == 200
    assert r.json()["display_name"] == "Saturday test"


def test_list_includes_display_name_no_tokens(client: TestClient) -> None:
    m = create_seated_match(client, {"scenario_id": "tiny_test", "display_name": "Lobby Alpha"})
    listed = client.get("/v1/matches").json()
    hit = next(r for r in listed["matches"] if r["match_id"] == m["match_id"])
    assert hit["display_name"] == "Lobby Alpha"
    assert seats.summary_has_no_tokens(hit)
    assert "token" not in json.dumps(hit)


def test_rename_host_succeeds(client: TestClient) -> None:
    m = create_seated_match(client, {"scenario_id": "tiny_test"})
    mid = m["match_id"]
    snap_before = file_store.read_snapshot(mid)
    events_before = file_store.read_events(mid)
    hash_before = state_hash.state_hash(snap_before) if snap_before else ""
    r = client.patch(
        f"/v1/matches/{mid}/display-name",
        json={"display_name": "Renamed on server"},
        headers=m["headers"],
    )
    assert r.status_code == 200
    assert r.json() == {"match_id": mid, "display_name": "Renamed on server"}
    meta = file_store.read_meta(mid)
    assert meta is not None
    assert meta["display_name"] == "Renamed on server"
    snap_after = file_store.read_snapshot(mid)
    events_after = file_store.read_events(mid)
    assert snap_after == snap_before
    assert events_after == events_before
    assert state_hash.state_hash(snap_after) == hash_before
    hit = next(r for r in client.get("/v1/matches").json()["matches"] if r["match_id"] == mid)
    assert hit["display_name"] == "Renamed on server"


def test_rename_seat_token_rejects(client: TestClient) -> None:
    m = create_seated_match(client, {"scenario_id": "tiny_test"})
    mid = m["match_id"]
    claim = client.post(f"/v1/matches/{mid}/seats/1/claim")
    assert claim.status_code == 200
    seat_tok = claim.json()["seat_token"]
    r = client.patch(
        f"/v1/matches/{mid}/display-name",
        json={"display_name": "Nope"},
        headers={SEAT_TOKEN_HEADER: seat_tok},
    )
    assert r.status_code == 403
    assert r.json()["detail"] == "not_host"


def test_rename_missing_token_rejects(client: TestClient) -> None:
    m = create_seated_match(client, {"scenario_id": "tiny_test"})
    r = client.patch(
        f"/v1/matches/{m['match_id']}/display-name",
        json={"display_name": "Nope"},
    )
    assert r.status_code == 403
    assert r.json()["detail"] == "missing_seat_token"


def test_rename_invalid_token_rejects(client: TestClient) -> None:
    m = create_seated_match(client, {"scenario_id": "tiny_test"})
    r = client.patch(
        f"/v1/matches/{m['match_id']}/display-name",
        json={"display_name": "Nope"},
        headers={SEAT_TOKEN_HEADER: "st_deadbeef"},
    )
    assert r.status_code == 403
    assert r.json()["detail"] == "invalid_seat_token"


def test_rename_empty_uses_default(client: TestClient) -> None:
    m = create_seated_match(client, {"scenario_id": "tiny_test"})
    mid = m["match_id"]
    r = client.patch(
        f"/v1/matches/{mid}/display-name",
        json={"display_name": "   "},
        headers=m["headers"],
    )
    assert r.status_code == 200
    assert r.json()["display_name"] == seats.default_display_name(mid)


def test_v1_meta_list_display_name_fallback(client: TestClient) -> None:
    m = create_seated_match(client, {"scenario_id": "tiny_test"})
    mid = m["match_id"]
    meta = file_store.read_meta(mid)
    assert meta is not None
    meta["schema_version"] = seats.META_SCHEMA_VERSION_V1
    meta.pop("display_name", None)
    meta.pop("status", None)
    file_store.write_meta(mid, meta)
    hit = next(r for r in client.get("/v1/matches").json()["matches"] if r["match_id"] == mid)
    assert hit["display_name"] == seats.default_display_name(mid)
