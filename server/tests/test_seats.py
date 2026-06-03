"""Unit tests for seat/host credentials and lobby meta (C13a/C14b/C14d-1)."""

from __future__ import annotations

from app.domain import factions, seats


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
    assert isinstance(meta.get("match_seed"), str)
    assert len(meta["match_seed"]) == 32
    for s in meta["seats"]:
        assert s.get("faction_id") is None
        assert s.get("ready") is False


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


def test_seat_token_actor_id_rejects_host_token() -> None:
    meta = seats.build_meta("m_z", [0, 1])
    assert seats.seat_token_actor_id(meta, meta["host_token"]) is None
    seat0 = meta["seats"][0]["token"]
    assert seats.seat_token_actor_id(meta, seat0) == 0


def test_lobby_summary_includes_factions_and_ready_to_start() -> None:
    meta = seats.build_meta("m_lobby", [0, 1])
    claimed = seats.try_claim_seat(meta, 0)
    assert claimed.ok and claimed.meta is not None
    m1 = seats.try_claim_seat(claimed.meta, 1)
    assert m1.ok and m1.meta is not None
    f0 = seats.try_set_seat_faction(m1.meta, 0, factions.FACTION_MALMO)
    f1 = seats.try_set_seat_faction(f0.meta, 1, factions.FACTION_VASTERVIK)
    assert f1.ok and f1.meta is not None
    snap = {"revision": 0, "turn_state": {"turn_number": 1}}
    summary = seats.lobby_summary("m_lobby", f1.meta, snap)
    assert summary["ready_to_start"] is False
    assert len(summary["available_factions"]) == 3
    assert seats.summary_has_no_tokens(summary)
    ready_meta = seats.try_set_seat_ready(f1.meta, 0, True).meta
    assert ready_meta is not None
    ready_meta = seats.try_set_seat_ready(ready_meta, 1, True).meta
    assert ready_meta is not None
    summary2 = seats.lobby_summary("m_lobby", ready_meta, snap)
    assert summary2["ready_to_start"] is True


def test_try_set_faction_clears_ready() -> None:
    meta = seats.build_meta("m_swap", [0])
    meta = seats.try_claim_seat(meta, 0).meta
    assert meta is not None
    meta = seats.try_set_seat_faction(meta, 0, factions.FACTION_MALMO).meta
    assert meta is not None
    meta = seats.try_set_seat_ready(meta, 0, True).meta
    assert meta is not None
    seat = next(s for s in meta["seats"] if s["actor_id"] == 0)
    assert seat["ready"] is True
    meta = seats.try_set_seat_faction(meta, 0, factions.FACTION_PARIS).meta
    assert meta is not None
    seat = next(s for s in meta["seats"] if s["actor_id"] == 0)
    assert seat["faction_id"] == factions.FACTION_PARIS
    assert seat["ready"] is False
    assert "ready_at" not in seat


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
    assert seat1.get("claimed_at")
    r2 = seats.try_claim_seat(r.meta, 1)
    assert not r2.ok
    assert r2.reason == "seat_already_claimed"
