"""API tests for GET /v1/matches lobby list (C14b)."""

from __future__ import annotations

import json

from fastapi.testclient import TestClient

from app.domain import seats
from app.storage import file_store
from match_helpers import create_seated_match


def _response_has_no_tokens(payload: object) -> bool:
    if isinstance(payload, dict):
        for k, v in payload.items():
            if k in ("host_token", "seat_token", "token") or "token" in str(k):
                return False
            if not _response_has_no_tokens(v):
                return False
    elif isinstance(payload, list):
        for item in payload:
            if not _response_has_no_tokens(item):
                return False
    return True


def test_create_appears_in_list_without_tokens(client: TestClient) -> None:
    m = create_seated_match(client, {"scenario_id": "tiny_test"})
    listed = client.get("/v1/matches").json()
    assert _response_has_no_tokens(listed)
    rows = listed["matches"]
    hit = next(r for r in rows if r["match_id"] == m["match_id"])
    assert hit["status"] == seats.STATUS_STAGING
    assert hit["display_name"] == seats.default_display_name(m["match_id"])
    assert hit["scenario_id"] == "tiny_test"
    assert hit["player_count"] == 2
    assert hit["open_seat_count"] == 2
    assert hit["revision"] == 0
    assert hit["turn_number"] == 1
    assert all("token" not in s for s in hit["seats"])
    assert all("claimed" in s and "actor_id" in s for s in hit["seats"])
    assert "available_factions" in hit
    assert len(hit["available_factions"]) == 3
    assert hit["ready_to_start"] is False
    assert all(s.get("faction_id") is None and s.get("ready") is False for s in hit["seats"])
    assert seats.summary_has_no_tokens(hit)


def test_status_staging_filter(client: TestClient) -> None:
    m = create_seated_match(client, {"scenario_id": "tiny_test"})
    only_staging = client.get("/v1/matches", params={"status": "staging"}).json()
    ids = {r["match_id"] for r in only_staging["matches"]}
    assert m["match_id"] in ids
    for row in only_staging["matches"]:
        assert row["status"] == seats.STATUS_STAGING


def test_v1_meta_lists_as_ongoing_excluded_from_staging_filter(client: TestClient) -> None:
    m = create_seated_match(client, {"scenario_id": "tiny_test"})
    mid = m["match_id"]
    meta = file_store.read_meta(mid)
    assert meta is not None
    meta["schema_version"] = seats.META_SCHEMA_VERSION_V1
    meta.pop("status", None)
    meta.pop("created_at", None)
    meta.pop("scenario_id", None)
    for s in meta["seats"]:
        s.pop("claimed", None)
    file_store.write_meta(mid, meta)

    all_rows = client.get("/v1/matches").json()["matches"]
    hit = next(r for r in all_rows if r["match_id"] == mid)
    assert hit["status"] == seats.STATUS_ONGOING
    assert all(s["claimed"] is True for s in hit["seats"])

    staging_only = client.get("/v1/matches", params={"status": "staging"}).json()["matches"]
    assert mid not in {r["match_id"] for r in staging_only}


def test_legacy_no_meta_excluded_from_list(client: TestClient) -> None:
    m = create_seated_match(client, {"scenario_id": "tiny_test"})
    mid = m["match_id"]
    file_store.meta_path(mid).unlink()
    listed = client.get("/v1/matches").json()["matches"]
    assert mid not in {r["match_id"] for r in listed}


def test_list_tolerates_corrupt_meta_dir(client: TestClient) -> None:
    create_seated_match(client, {"scenario_id": "tiny_test"})
    bad_dir = file_store.matches_root() / "m_badmeta"
    bad_dir.mkdir(parents=True, exist_ok=True)
    (bad_dir / "snapshot.json").write_text(
        json.dumps(
            {
                "match_id": "m_badmeta",
                "schema_version": 2,
                "revision": 0,
                "scenario_id": "tiny_test",
                "turn_state": {"players": [0], "current_index": 0, "turn_number": 1},
                "scenario": {"map": {"cells": []}, "units": [], "cities": []},
                "progress_state": {},
                "visibility_state": {},
            }
        ),
        encoding="utf-8",
    )
    (bad_dir / "meta.json").write_text("{not-json", encoding="utf-8")
    r = client.get("/v1/matches")
    assert r.status_code == 200
