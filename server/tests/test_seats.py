"""Unit tests for seat/host credentials (C13a)."""

from __future__ import annotations

from app.domain import seats


def test_generate_seats_prefixes_and_unique_tokens() -> None:
    meta = seats.build_meta("m_test", [1, 0])
    assert meta["schema_version"] == 1
    assert meta["match_id"] == "m_test"
    assert len(meta["seats"]) == 2
    assert meta["seats"][0]["actor_id"] == 0
    tokens = [s["token"] for s in meta["seats"]]
    assert all(t.startswith(seats.SEAT_TOKEN_PREFIX) for t in tokens)
    assert len(set(tokens)) == 2
    assert meta["host_token"].startswith(seats.HOST_TOKEN_PREFIX)


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
