"""N8a: server-authoritative world found_city on the world_map path.

Covers: successful founding with deterministic city id/name, atomic settler
consumption, additive snapshot cities + next_city_id, the locked first-
failure rejection order, no partial mutation on reject, duplicate/stale
posts after consume, legal-actions found_city rows + city_summaries, city
selection empty actions, fail-closed map drift (HTTP 500), deterministic
replay/matched-state, and set_city_production remaining unsupported.
"""

from __future__ import annotations

from fastapi.testclient import TestClient

from app.domain import world_actions
from app.domain.state_hash import state_hash
from app.storage import file_store
from match_helpers import SEAT_TOKEN_HEADER
from test_world_map_actions_v3 import (
    MISMATCH_DETAIL,
    _assert_reject,
    _end_turn,
    _make_drifted_content_root,
    _post,
    _start_world_match,
)


def _found(actor_id: int, unit_id: int, pos, schema: int = 1) -> dict:
    return {
        "schema_version": schema,
        "action_type": "found_city",
        "actor_id": actor_id,
        "unit_id": unit_id,
        "position": list(pos),
    }


def _get_legal(client: TestClient, match_id: str, actor_id: int, token: str, **params):
    return client.get(
        f"/v1/matches/{match_id}/legal-actions",
        params={"actor_id": actor_id, **params},
        headers={SEAT_TOKEN_HEADER: token},
    )


def _seed_city(match_id: str, city: dict, next_city_id: int | None = None) -> None:
    """Test fixture only: inject a city row into the persisted snapshot."""
    snap = file_store.read_snapshot(match_id)
    assert snap is not None
    cities = list(snap.get("cities", []))
    cities.append(dict(city))
    cities.sort(key=lambda c: int(c["id"]))
    snap["cities"] = cities
    if next_city_id is not None:
        snap["next_city_id"] = int(next_city_id)
    elif int(snap.get("next_city_id", 1)) <= int(city["id"]):
        snap["next_city_id"] = int(city["id"]) + 1
    file_store.write_snapshot(match_id, snap)


# ----------------------------------------------------------- snapshot shape


def test_initial_snapshot_has_empty_cities(client: TestClient) -> None:
    match_id, _, data = _start_world_match(client)
    snap = data["snapshot"]
    assert snap["cities"] == []
    assert snap["next_city_id"] == 1
    # Readback matches create body.
    assert file_store.read_snapshot(match_id)["cities"] == []


# ----------------------------------------------------------- success path


def test_found_city_success_consumes_settler_and_creates_city(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    before = file_store.read_snapshot(match_id)
    assert before is not None
    hash_before = state_hash(before)

    events_before = file_store.read_events(match_id)
    r = _post(client, match_id, _found(0, 1, (1, 1)), tokens[0])
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["accepted"] is True
    assert body["reason"] == ""
    assert body["revision"] == int(before["revision"]) + 1
    assert body["index"] == len(events_before)

    snap = body["snapshot"]
    assert snap["revision"] == body["revision"]
    assert snap["next_city_id"] == 2
    assert snap["cities"] == [
        {"id": 1, "owner_id": 0, "position": [1, 1], "name": "Capital"}
    ]
    # Settler 1 consumed; warrior 2 and opponent units remain.
    assert [u["id"] for u in snap["units"]] == [2, 3, 4]
    assert all(int(u["id"]) != 1 for u in snap["units"])
    assert body["state_hash"] == state_hash(snap)
    assert body["state_hash"] != hash_before

    event = body["event"]
    assert event["action_type"] == "found_city"
    assert event["unit_id"] == 1
    assert event["city_id"] == 1
    assert event["city_name"] == "Capital"
    assert event["at"] == [1, 1]
    assert event["settler_consumed"] is True
    assert event["result"] == "accepted"
    assert event["index"] == body["index"]

    # Persisted state matches the response.
    persisted = file_store.read_snapshot(match_id)
    assert persisted == snap
    assert file_store.read_events(match_id)[-1] == event


def test_second_city_name_and_id_deterministic(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    r1 = _post(client, match_id, _found(0, 1, (1, 1)), tokens[0])
    assert r1.json()["accepted"] is True

    # Move warrior aside and teleport a fresh settler-equivalent by reusing
    # opponent's settler after turn handoff is heavier — instead seed a second
    # founding via teleporting unit 3 after end_turn ownership change, or
    # simply found again with a re-injected settler on a free tile for P0.
    snap = file_store.read_snapshot(match_id)
    assert snap is not None
    # Inject a second settler for owner 0 at (3, 1) for the next founding.
    snap["units"].append(
        {
            "id": 10,
            "owner_id": 0,
            "position": [3, 1],
            "type_id": "settler",
            "current_hp": 100,
            "has_attacked": False,
        }
    )
    snap["units"].sort(key=lambda u: int(u["id"]))
    file_store.write_snapshot(match_id, snap)

    r2 = _post(client, match_id, _found(0, 10, (3, 1)), tokens[0])
    assert r2.status_code == 200, r2.text
    body = r2.json()
    assert body["accepted"] is True
    cities = body["snapshot"]["cities"]
    assert [c["id"] for c in cities] == [1, 2]
    assert cities[1] == {
        "id": 2,
        "owner_id": 0,
        "position": [3, 1],
        "name": "Settlement 2",
    }
    assert body["snapshot"]["next_city_id"] == 3
    assert body["event"]["city_name"] == "Settlement 2"


def test_found_city_does_not_block_unit_movement(client: TestClient) -> None:
    """Locked N8a: cities do not occupy tiles for movement purposes."""
    match_id, tokens, _ = _start_world_match(client)
    assert _post(client, match_id, _found(0, 1, (1, 1)), tokens[0]).json()["accepted"]
    # Warrior at (2,1) can still step onto the city tile (1,1).
    r = _post(
        client,
        match_id,
        {
            "schema_version": 1,
            "action_type": "move_unit",
            "actor_id": 0,
            "unit_id": 2,
            "from": [2, 1],
            "to": [1, 1],
        },
        tokens[0],
    )
    assert r.status_code == 200, r.text
    assert r.json()["accepted"] is True
    warrior = next(u for u in r.json()["snapshot"]["units"] if int(u["id"]) == 2)
    assert warrior["position"] == [1, 1]


def test_deterministic_replay_matched_city_state(client: TestClient) -> None:
    """Identical founding input on two fresh matches yields identical city
    rows, next_city_id, remaining unit ids, and event city fields (match_id
    differs so full state_hash is not compared across matches)."""
    results = []
    for _ in range(2):
        match_id, tokens, _ = _start_world_match(client)
        body = _post(client, match_id, _found(0, 1, (1, 1)), tokens[0]).json()
        assert body["accepted"] is True
        snap = body["snapshot"]
        results.append(
            {
                "cities": snap["cities"],
                "next_city_id": snap["next_city_id"],
                "unit_ids": [u["id"] for u in snap["units"]],
                "units": snap["units"],
                "event_city": {
                    "city_id": body["event"]["city_id"],
                    "city_name": body["event"]["city_name"],
                    "at": body["event"]["at"],
                    "settler_consumed": body["event"]["settler_consumed"],
                },
            }
        )
    assert results[0] == results[1]
    # Same-match helper apply also matches the accepted HTTP result.
    seed = {
        "match_id": "replay",
        "revision": 0,
        "turn_state": {"players": [0, 1], "current_index": 0, "turn_number": 1},
        "units": [
            {
                "id": 1,
                "owner_id": 0,
                "position": [1, 1],
                "type_id": "settler",
                "current_hp": 100,
                "has_attacked": False,
            },
            {
                "id": 2,
                "owner_id": 0,
                "position": [2, 1],
                "type_id": "warrior",
                "current_hp": 100,
                "has_attacked": False,
            },
            {
                "id": 3,
                "owner_id": 1,
                "position": [2, 14],
                "type_id": "settler",
                "current_hp": 100,
                "has_attacked": False,
            },
            {
                "id": 4,
                "owner_id": 1,
                "position": [2, 13],
                "type_id": "warrior",
                "current_hp": 100,
                "has_attacked": False,
            },
        ],
        "cities": [],
        "next_city_id": 1,
    }
    a = world_actions.apply_found_city(seed, _found(0, 1, (1, 1)))
    b = world_actions.apply_found_city(seed, _found(0, 1, (1, 1)))
    assert a == b
    assert a["cities"] == results[0]["cities"]
    assert a["next_city_id"] == results[0]["next_city_id"]
    assert [u["id"] for u in a["units"]] == results[0]["unit_ids"]


# ----------------------------------------------------------- rejections


def test_found_city_rejection_order_domain() -> None:
    """Locked first-failure order through tile_already_has_city."""
    base_units = [
        {
            "id": 1,
            "owner_id": 0,
            "position": [1, 1],
            "type_id": "settler",
            "current_hp": 100,
            "has_attacked": False,
        },
        {
            "id": 2,
            "owner_id": 0,
            "position": [2, 1],
            "type_id": "warrior",
            "current_hp": 100,
            "has_attacked": False,
        },
    ]
    snap = {
        "match_id": "m",
        "revision": 0,
        "turn_state": {"players": [0, 1], "current_index": 0, "turn_number": 1},
        "units": list(base_units),
        "cities": [],
        "next_city_id": 1,
    }

    assert world_actions.validate_found_city(snap, _end_turn(0)) == {
        "ok": False,
        "reason": "wrong_action_type",
    }
    assert world_actions.validate_found_city(snap, _found(0, 1, (1, 1), schema=2)) == {
        "ok": False,
        "reason": "unsupported_schema_version",
    }
    bad = _found(0, 1, (1, 1))
    del bad["unit_id"]
    assert world_actions.validate_found_city(snap, bad) == {
        "ok": False,
        "reason": "malformed_action",
    }
    # Boolean / float schema and ids are malformed/unsupported, not accepted.
    for schema in (True, 1.0):
        act = _found(0, 1, (1, 1))
        act["schema_version"] = schema
        assert world_actions.validate_found_city(snap, act)["reason"] == (
            "unsupported_schema_version"
        )
    assert world_actions.validate_found_city(snap, _found(1, 1, (1, 1))) == {
        "ok": False,
        "reason": "not_current_player",
    }
    assert world_actions.validate_found_city(snap, _found(0, 99, (1, 1))) == {
        "ok": False,
        "reason": "unknown_unit",
    }
    # Opponent settler while P0 is current.
    snap_enemy = {
        **snap,
        "units": [
            {
                "id": 3,
                "owner_id": 1,
                "position": [2, 14],
                "type_id": "settler",
                "current_hp": 100,
                "has_attacked": False,
            }
        ],
    }
    assert world_actions.validate_found_city(snap_enemy, _found(0, 3, (2, 14))) == {
        "ok": False,
        "reason": "unit_not_owned_by_player",
    }
    assert world_actions.validate_found_city(snap, _found(0, 2, (2, 1))) == {
        "ok": False,
        "reason": "unit_cannot_found_city",
    }
    assert world_actions.validate_found_city(snap, _found(0, 1, (0, 0))) == {
        "ok": False,
        "reason": "unit_not_at_position",
    }
    snap_city = {
        **snap,
        "cities": [{"id": 1, "owner_id": 0, "position": [1, 1], "name": "Capital"}],
        "next_city_id": 2,
    }
    assert world_actions.validate_found_city(snap_city, _found(0, 1, (1, 1))) == {
        "ok": False,
        "reason": "tile_already_has_city",
    }
    assert world_actions.validate_found_city(snap, _found(0, 1, (1, 1))) == {
        "ok": True,
        "reason": "",
    }


def test_found_city_http_rejections_no_write(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    before = file_store.read_snapshot(match_id)
    events_before = file_store.read_events(match_id)

    cases = [
        (_found(0, 1, (1, 1), schema=2), tokens[0], "unsupported_schema_version"),
        (_found(1, 3, (2, 14)), tokens[1], "not_current_player"),
        (_found(0, 99, (1, 1)), tokens[0], "unknown_unit"),
        (_found(0, 3, (2, 14)), tokens[0], "unit_not_owned_by_player"),
        (_found(0, 2, (2, 1)), tokens[0], "unit_cannot_found_city"),
        (_found(0, 1, (0, 0)), tokens[0], "unit_not_at_position"),
    ]
    for action, token, reason in cases:
        _assert_reject(_post(client, match_id, action, token), reason)
        assert file_store.read_snapshot(match_id) == before
        assert file_store.read_events(match_id) == events_before

    _seed_city(
        match_id,
        {"id": 1, "owner_id": 0, "position": [1, 1], "name": "Capital"},
        next_city_id=2,
    )
    before2 = file_store.read_snapshot(match_id)
    _assert_reject(
        _post(client, match_id, _found(0, 1, (1, 1)), tokens[0]),
        "tile_already_has_city",
    )
    assert file_store.read_snapshot(match_id) == before2


def test_duplicate_found_city_after_consume_is_unknown_unit(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    action = _found(0, 1, (1, 1))
    assert _post(client, match_id, action, tokens[0]).json()["accepted"] is True
    before = file_store.read_snapshot(match_id)
    events_before = file_store.read_events(match_id)
    _assert_reject(_post(client, match_id, action, tokens[0]), "unknown_unit")
    assert file_store.read_snapshot(match_id) == before
    assert file_store.read_events(match_id) == events_before


def test_found_city_content_drift_500_no_mutation(
    client: TestClient, tmp_path, monkeypatch
) -> None:
    match_id, tokens, _ = _start_world_match(client)
    before = file_store.read_snapshot(match_id)
    events_before = file_store.read_events(match_id)
    monkeypatch.setenv(
        "EMPIRE_MAP_CONTENT_DIR", str(_make_drifted_content_root(tmp_path))
    )
    r = _post(client, match_id, _found(0, 1, (1, 1)), tokens[0])
    assert r.status_code == 500
    assert r.json()["detail"] == MISMATCH_DETAIL
    assert file_store.read_snapshot(match_id) == before
    assert file_store.read_events(match_id) == events_before


def test_set_city_production_still_unsupported(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    assert _post(client, match_id, _found(0, 1, (1, 1)), tokens[0]).json()["accepted"]
    r = _post(
        client,
        match_id,
        {
            "schema_version": 2,
            "action_type": "set_city_production",
            "actor_id": 0,
            "city_id": 1,
            "project_id": "produce_unit:warrior",
        },
        tokens[0],
    )
    _assert_reject(r, "unsupported_action_for_match_kind")


# ----------------------------------------------------------- legal-actions


def test_legal_actions_found_city_row_and_round_trip(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    sel = _get_legal(client, match_id, 0, tokens[0], selected_unit_id=1).json()
    found_rows = [a for a in sel["actions"] if a["action_type"] == "found_city"]
    assert found_rows == [_found(0, 1, (1, 1))]
    # Warrior has no found_city.
    war = _get_legal(client, match_id, 0, tokens[0], selected_unit_id=2).json()
    assert not any(a["action_type"] == "found_city" for a in war["actions"])

    r = _post(client, match_id, found_rows[0], tokens[0])
    assert r.json()["accepted"] is True
    # After founding, city_summaries lists the new city with 0 actions.
    summary = _get_legal(client, match_id, 0, tokens[0]).json()
    assert summary["city_summaries"] == [{"city_id": 1, "legal_action_count": 0}]
    # Selected city: empty actions, no selection_error (N8b fills projects).
    city_sel = _get_legal(client, match_id, 0, tokens[0], selected_city_id=1).json()
    assert city_sel["selection_error"] is None
    assert city_sel["actions"] == []
    assert city_sel["selected_city_id"] == 1


def test_legal_actions_excludes_found_city_on_occupied_city_tile(
    client: TestClient,
) -> None:
    match_id, tokens, _ = _start_world_match(client)
    _seed_city(
        match_id,
        {"id": 1, "owner_id": 0, "position": [1, 1], "name": "Capital"},
        next_city_id=2,
    )
    sel = _get_legal(client, match_id, 0, tokens[0], selected_unit_id=1).json()
    assert not any(a["action_type"] == "found_city" for a in sel["actions"])


def test_apply_found_city_atomic_helper() -> None:
    snap = {
        "match_id": "m",
        "revision": 3,
        "turn_state": {"players": [0, 1], "current_index": 0, "turn_number": 1},
        "units": [
            {
                "id": 1,
                "owner_id": 0,
                "position": [1, 1],
                "type_id": "settler",
                "current_hp": 100,
                "has_attacked": False,
            },
            {
                "id": 2,
                "owner_id": 0,
                "position": [2, 1],
                "type_id": "warrior",
                "current_hp": 70,
                "has_attacked": True,
            },
        ],
        "cities": [],
        "next_city_id": 1,
        "map": {"map_id": "x", "schema_version": 1, "content_hash": "h"},
    }
    out = world_actions.apply_found_city(snap, _found(0, 1, (1, 1)))
    assert out["revision"] == 4
    assert out["next_city_id"] == 2
    assert out["cities"] == [
        {"id": 1, "owner_id": 0, "position": [1, 1], "name": "Capital"}
    ]
    assert [u["id"] for u in out["units"]] == [2]
    # Remaining unit combat fields preserved verbatim.
    assert out["units"][0]["current_hp"] == 70
    assert out["units"][0]["has_attacked"] is True
    # Original snap untouched.
    assert snap["cities"] == []
    assert snap["next_city_id"] == 1
