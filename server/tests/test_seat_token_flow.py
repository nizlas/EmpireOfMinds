"""API tests for C13a seat/host token gate on POST /actions."""

from __future__ import annotations

from fastapi.testclient import TestClient

from app.storage import file_store
from match_helpers import SEAT_TOKEN_HEADER, create_seated_match, post_match_action


def _end_turn(actor_id: int) -> dict:
    return {"schema_version": 1, "action_type": "end_turn", "actor_id": actor_id}


def test_create_returns_seats_and_host_token(client: TestClient) -> None:
    m = create_seated_match(client, {"scenario_id": "tiny_test"})
    data = m["data"]
    assert "seats" in data
    assert len(data["seats"]) == 2
    assert all("actor_id" in s and "token" in s for s in data["seats"])
    assert str(data["host_token"]).startswith("ht_")


def test_get_match_excludes_tokens(client: TestClient) -> None:
    m = create_seated_match(client, {"scenario_id": "tiny_test"})
    got = client.get(f"/v1/matches/{m['match_id']}").json()
    assert "host_token" not in got
    assert "seats" not in got
    assert "host_token" not in got["snapshot"]
    assert "seats" not in got["snapshot"]


def test_missing_token_rejected(client: TestClient) -> None:
    m = create_seated_match(client, {"scenario_id": "tiny_test"})
    r = post_match_action(client, m["match_id"], _end_turn(0))
    assert r.json()["accepted"] is False
    assert r.json()["reason"] == "missing_seat_token"


def test_invalid_token_rejected(client: TestClient) -> None:
    m = create_seated_match(client, {"scenario_id": "tiny_test"})
    r = post_match_action(
        client,
        m["match_id"],
        _end_turn(0),
        {SEAT_TOKEN_HEADER: "st_invalid"},
    )
    assert r.json()["accepted"] is False
    assert r.json()["reason"] == "invalid_seat_token"


def test_host_token_allows_current_player_end_turn(client: TestClient) -> None:
    m = create_seated_match(client, {"scenario_id": "tiny_test"})
    r = post_match_action(client, m["match_id"], _end_turn(0), m["headers"])
    assert r.json()["accepted"] is True


def test_seat_token_cannot_act_as_other_seat(client: TestClient) -> None:
    m = create_seated_match(client, {"scenario_id": "tiny_test"})
    seat0 = next(s for s in m["data"]["seats"] if s["actor_id"] == 0)
    r = post_match_action(
        client,
        m["match_id"],
        _end_turn(1),
        {SEAT_TOKEN_HEADER: seat0["token"]},
    )
    assert r.json()["accepted"] is False
    assert r.json()["reason"] == "seat_not_allowed"


def test_legacy_match_without_meta_is_permissive(client: TestClient) -> None:
    m = create_seated_match(client, {"scenario_id": "tiny_test"})
    mid = m["match_id"]
    meta_p = file_store.meta_path(mid)
    assert meta_p.is_file()
    meta_p.unlink()
    r = post_match_action(client, mid, _end_turn(0))
    assert r.json()["accepted"] is True
