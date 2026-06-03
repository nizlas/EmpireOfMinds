"""Unit tests for seat/host credentials and lobby meta (C13a/C14b)."""

from __future__ import annotations

from app.domain import seats


def test_generate_seats_prefixes_and_unique_tokens() -> None:
    meta = seats.build_meta("m_test", [1, 0], "tiny_test")
    assert meta["schema_version"] == seats.META_SCHEMA_VERSION
    assert meta["match_id"] == "m_test"
    assert meta["status"] == seats.STATUS_STAGING
    assert meta["scenario_id"] == "tiny_test"
    assert meta["created_at"]
    assert len(meta["seats"]) == 2
    assert meta["seats"][0]["actor_id"] == 0
    assert meta["seats"][0]["claimed"] is False
    tokens = [s["token"] for s in meta["seats"]]
    assert all(t.startswith(seats.SEAT_TOKEN_PREFIX) for t in tokens)
    assert len(set(tokens)) == 2
    assert meta["host_token"].startswith(seats.HOST_TOKEN_PREFIX)
    assert meta["display_name"] == seats.default_display_name("m_test")


def test_allowed_actor_ids_host_vs_seat() -> None:
    meta = seats.build_meta("m_x", [0, 1])
    host_allowed = seats.allowed_actor_ids(meta, meta["host_token"])
    assert host_allowed == [0, 1]
    seat0 = meta["seats"][0]["token"]
    assert seats.allowed_actor_ids(meta, seat0) == [0]
    seat1 = next(s["token"] for s in meta["seats"] if s["actor_id"] == 1)
    assert seats.allowed_actor_ids(meta, seat1) == [1]


def test_allowed_actor_ids_invalid_returns_none() -> None:
    meta = seats.build_meta("m_y", [0])
    assert seats.allowed_actor_ids(meta, "st_deadbeef") is None
    assert seats.allowed_actor_ids(meta, None) is None
    assert seats.allowed_actor_ids(meta, "") is None


def test_match_status_v1_is_ongoing() -> None:
    v1 = {
        "match_id": "m_v1",
        "schema_version": 1,
        "seats": [{"actor_id": 0, "token": "st_x"}],
        "host_token": "ht_x",
    }
    assert seats.match_status(v1) == seats.STATUS_ONGOING


def test_try_claim_seat_staging_flow() -> None:
    meta = seats.build_meta("m_claim", [0, 1])
    r = seats.try_claim_seat(meta, 1)
    assert r.ok
    assert r.seat_token.startswith(seats.SEAT_TOKEN_PREFIX)
    assert r.meta is not None
    seat1 = next(s for s in r.meta["seats"] if s["actor_id"] == 1)
    assert seat1["claimed"] is True
    r2 = seats.try_claim_seat(r.meta, 1)
    assert not r2.ok
    assert r2.reason == "seat_already_claimed"
