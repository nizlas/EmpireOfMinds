"""N8b: server-authoritative world set_city_production on the world_map path.

Covers: flat production constant, additive city current_project, successful
set/switch/clear with registry costs, locked first-failure rejection order,
no unlock gating, atomicity (no write on reject), deterministic snapshot/
event round-trip, legal-actions production rows + city_summaries, and
fail-closed WorldMap content drift (HTTP 500).
"""

from __future__ import annotations

from fastapi.testclient import TestClient

from app.domain import world_actions
from app.domain.content import city_project_definitions as cpd
from app.domain.state_hash import state_hash
from app.domain.city_production_rules import FLAT_PRODUCTION_PER_CITY
from app.storage import file_store
from test_world_found_city_v3 import _found, _get_legal, _seed_city
from test_world_map_actions_v3 import (
    MISMATCH_DETAIL,
    _assert_reject,
    _make_drifted_content_root,
    _post,
    _start_world_match,
)


def _set_prod(
    actor_id: int,
    city_id: int,
    project_id: str,
    schema: int = 2,
) -> dict:
    return {
        "schema_version": schema,
        "action_type": "set_city_production",
        "actor_id": actor_id,
        "city_id": city_id,
        "project_id": project_id,
    }


def _found_capital(client: TestClient, match_id: str, token: str) -> dict:
    r = _post(client, match_id, _found(0, 1, (1, 1)), token)
    assert r.status_code == 200, r.text
    assert r.json()["accepted"] is True
    return r.json()


# ----------------------------------------------------------- rules / shape


def test_flat_production_constant_is_one() -> None:
    """N8b establishes the locked flat yield; N8c ticks it — never tile reads."""
    assert FLAT_PRODUCTION_PER_CITY == 1


def test_registry_costs_warrior_and_settler_are_two() -> None:
    assert cpd.cost("produce_unit:warrior") == 2
    assert cpd.cost("produce_unit:settler") == 2


def test_newly_founded_city_starts_with_null_project(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    body = _found_capital(client, match_id, tokens[0])
    city = body["snapshot"]["cities"][0]
    assert city["current_project"] is None
    assert set(city.keys()) == {
        "id",
        "owner_id",
        "position",
        "name",
        "current_project",
    }


# ----------------------------------------------------------- success paths


def test_set_city_production_success_sets_project_and_event(
    client: TestClient,
) -> None:
    match_id, tokens, _ = _start_world_match(client)
    _found_capital(client, match_id, tokens[0])
    before = file_store.read_snapshot(match_id)
    assert before is not None
    hash_before = state_hash(before)
    events_before = file_store.read_events(match_id)

    action = _set_prod(0, 1, "produce_unit:warrior")
    r = _post(client, match_id, action, tokens[0])
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["accepted"] is True
    assert body["reason"] == ""
    assert body["revision"] == int(before["revision"]) + 1
    assert body["index"] == len(events_before)

    snap = body["snapshot"]
    assert snap["cities"][0]["current_project"] == {
        "project_id": "produce_unit:warrior",
        "progress": 0,
        "cost": 2,
    }
    assert body["state_hash"] == state_hash(snap)
    assert body["state_hash"] != hash_before

    event = body["event"]
    assert event["action_type"] == "set_city_production"
    assert event["schema_version"] == 2
    assert event["actor_id"] == 0
    assert event["city_id"] == 1
    assert event["project_id"] == "produce_unit:warrior"
    assert event["project_progress"] == 0
    assert event["result"] == "accepted"
    assert event["index"] == body["index"]
    assert event["revision"] == body["revision"]

    assert file_store.read_snapshot(match_id) == snap
    assert file_store.read_events(match_id)[-1] == event


def test_switch_project_resets_progress(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    _found_capital(client, match_id, tokens[0])
    assert _post(
        client, match_id, _set_prod(0, 1, "produce_unit:warrior"), tokens[0]
    ).json()["accepted"]

    # Fixture-only: bump progress as if N8c had ticked (N8b does not tick).
    snap = file_store.read_snapshot(match_id)
    assert snap is not None
    snap["cities"][0]["current_project"]["progress"] = 1
    file_store.write_snapshot(match_id, snap)

    r = _post(client, match_id, _set_prod(0, 1, "produce_unit:settler"), tokens[0])
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["accepted"] is True
    assert body["snapshot"]["cities"][0]["current_project"] == {
        "project_id": "produce_unit:settler",
        "progress": 0,
        "cost": 2,
    }
    assert body["event"]["project_id"] == "produce_unit:settler"
    assert body["event"]["project_progress"] == 0


def test_clear_project_with_none(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    _found_capital(client, match_id, tokens[0])
    assert _post(
        client, match_id, _set_prod(0, 1, "produce_unit:warrior"), tokens[0]
    ).json()["accepted"]

    r = _post(client, match_id, _set_prod(0, 1, "none"), tokens[0])
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["accepted"] is True
    assert body["snapshot"]["cities"][0]["current_project"] is None
    assert body["event"]["project_id"] == "none"
    assert body["event"]["project_progress"] is None


def test_end_turn_does_not_tick_production_in_n8b(client: TestClient) -> None:
    """N8b establishes the yield constant but must not accrue progress."""
    match_id, tokens, _ = _start_world_match(client)
    _found_capital(client, match_id, tokens[0])
    assert _post(
        client, match_id, _set_prod(0, 1, "produce_unit:warrior"), tokens[0]
    ).json()["accepted"]
    r = _post(
        client,
        match_id,
        {"schema_version": 1, "action_type": "end_turn", "actor_id": 0},
        tokens[0],
    )
    assert r.status_code == 200, r.text
    assert r.json()["accepted"] is True
    city = r.json()["snapshot"]["cities"][0]
    assert city["current_project"]["progress"] == 0
    assert city["current_project"]["cost"] == 2


# ----------------------------------------------------------- rejection order


def test_validate_set_city_production_rejection_order() -> None:
    snap = {
        "match_id": "m",
        "revision": 0,
        "turn_state": {"players": [0, 1], "current_index": 0, "turn_number": 1},
        "units": [],
        "cities": [
            {
                "id": 1,
                "owner_id": 0,
                "position": [1, 1],
                "name": "Capital",
                "current_project": None,
            }
        ],
        "next_city_id": 2,
        "map": {"map_id": "x", "schema_version": 1, "content_hash": "h"},
    }
    assert world_actions.validate_set_city_production(
        snap, {"action_type": "move_unit"}
    ) == {"ok": False, "reason": "wrong_action_type"}
    assert world_actions.validate_set_city_production(
        snap, _set_prod(0, 1, "produce_unit:warrior", schema=1)
    ) == {"ok": False, "reason": "unsupported_schema_version"}
    assert world_actions.validate_set_city_production(
        snap,
        {
            "schema_version": 2,
            "action_type": "set_city_production",
            "actor_id": 0,
            # missing city_id / project_id
        },
    ) == {"ok": False, "reason": "malformed_action"}
    assert world_actions.validate_set_city_production(
        snap, _set_prod(1, 1, "produce_unit:warrior")
    ) == {"ok": False, "reason": "not_current_player"}
    assert world_actions.validate_set_city_production(
        snap, _set_prod(0, 99, "produce_unit:warrior")
    ) == {"ok": False, "reason": "unknown_city"}
    snap_enemy = {
        **snap,
        "cities": [
            {
                "id": 1,
                "owner_id": 1,
                "position": [1, 1],
                "name": "Capital",
                "current_project": None,
            }
        ],
    }
    assert world_actions.validate_set_city_production(
        snap_enemy, _set_prod(0, 1, "produce_unit:warrior")
    ) == {"ok": False, "reason": "city_not_owned_by_player"}
    assert world_actions.validate_set_city_production(
        snap, _set_prod(0, 1, "produce_unit:dragon")
    ) == {"ok": False, "reason": "unknown_city_project"}
    # none while already empty
    assert world_actions.validate_set_city_production(
        snap, _set_prod(0, 1, "none")
    ) == {"ok": False, "reason": "project_already_set"}
    # same project already set
    snap_set = {
        **snap,
        "cities": [
            {
                "id": 1,
                "owner_id": 0,
                "position": [1, 1],
                "name": "Capital",
                "current_project": {
                    "project_id": "produce_unit:warrior",
                    "progress": 0,
                    "cost": 2,
                },
            }
        ],
    }
    assert world_actions.validate_set_city_production(
        snap_set, _set_prod(0, 1, "produce_unit:warrior")
    ) == {"ok": False, "reason": "project_already_set"}
    # both unit projects always selectable (no unlock gate)
    assert world_actions.validate_set_city_production(
        snap, _set_prod(0, 1, "produce_unit:warrior")
    ) == {"ok": True, "reason": ""}
    assert world_actions.validate_set_city_production(
        snap, _set_prod(0, 1, "produce_unit:settler")
    ) == {"ok": True, "reason": ""}


def test_http_rejections_no_write(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    _found_capital(client, match_id, tokens[0])
    before = file_store.read_snapshot(match_id)
    events_before = file_store.read_events(match_id)

    cases = [
        (_set_prod(0, 1, "produce_unit:warrior", schema=1), tokens[0], "unsupported_schema_version"),
        (_set_prod(1, 1, "produce_unit:warrior"), tokens[1], "not_current_player"),
        (_set_prod(0, 99, "produce_unit:warrior"), tokens[0], "unknown_city"),
        (_set_prod(0, 1, "produce_unit:dragon"), tokens[0], "unknown_city_project"),
        (_set_prod(0, 1, "none"), tokens[0], "project_already_set"),
    ]
    for action, token, reason in cases:
        _assert_reject(_post(client, match_id, action, token), reason)
        assert file_store.read_snapshot(match_id) == before
        assert file_store.read_events(match_id) == events_before

    # Foreign city ownership
    _seed_city(
        match_id,
        {
            "id": 2,
            "owner_id": 1,
            "position": [3, 3],
            "name": "Enemy Capital",
            "current_project": None,
        },
        next_city_id=3,
    )
    before2 = file_store.read_snapshot(match_id)
    events2 = file_store.read_events(match_id)
    _assert_reject(
        _post(client, match_id, _set_prod(0, 2, "produce_unit:warrior"), tokens[0]),
        "city_not_owned_by_player",
    )
    assert file_store.read_snapshot(match_id) == before2
    assert file_store.read_events(match_id) == events2

    # Already-active project
    assert _post(
        client, match_id, _set_prod(0, 1, "produce_unit:warrior"), tokens[0]
    ).json()["accepted"]
    before3 = file_store.read_snapshot(match_id)
    events3 = file_store.read_events(match_id)
    _assert_reject(
        _post(client, match_id, _set_prod(0, 1, "produce_unit:warrior"), tokens[0]),
        "project_already_set",
    )
    assert file_store.read_snapshot(match_id) == before3
    assert file_store.read_events(match_id) == events3


def test_no_unlock_gating_both_projects_always_legal(client: TestClient) -> None:
    """World path has no progress_state — city_project_not_unlocked never fires."""
    match_id, tokens, _ = _start_world_match(client)
    _found_capital(client, match_id, tokens[0])
    # Snapshot has no progress_state key on world matches.
    snap = file_store.read_snapshot(match_id)
    assert snap is not None
    assert "progress_state" not in snap

    for pid in ("produce_unit:warrior", "produce_unit:settler"):
        # Fresh null project each time: clear after first if needed.
        city = file_store.read_snapshot(match_id)["cities"][0]
        if city.get("current_project") is not None:
            assert _post(
                client, match_id, _set_prod(0, 1, "none"), tokens[0]
            ).json()["accepted"]
        r = _post(client, match_id, _set_prod(0, 1, pid), tokens[0])
        assert r.status_code == 200, r.text
        assert r.json()["accepted"] is True
        assert r.json()["reason"] != "city_project_not_unlocked"


def test_content_drift_500_no_mutation(
    client: TestClient, tmp_path, monkeypatch
) -> None:
    match_id, tokens, _ = _start_world_match(client)
    _found_capital(client, match_id, tokens[0])
    before = file_store.read_snapshot(match_id)
    events_before = file_store.read_events(match_id)
    monkeypatch.setenv(
        "EMPIRE_MAP_CONTENT_DIR", str(_make_drifted_content_root(tmp_path))
    )
    r = _post(client, match_id, _set_prod(0, 1, "produce_unit:warrior"), tokens[0])
    assert r.status_code == 500
    assert r.json()["detail"] == MISMATCH_DETAIL
    assert file_store.read_snapshot(match_id) == before
    assert file_store.read_events(match_id) == events_before


# ----------------------------------------------------------- legal-actions


def test_legal_actions_production_rows_deterministic_and_submit_ready(
    client: TestClient,
) -> None:
    match_id, tokens, _ = _start_world_match(client)
    _found_capital(client, match_id, tokens[0])

    # Idle city: none excluded; settler then warrior (lexicographic after none).
    sel = _get_legal(client, match_id, 0, tokens[0], selected_city_id=1).json()
    assert sel["selection_error"] is None
    assert [a["action_type"] for a in sel["actions"]] == [
        "set_city_production",
        "set_city_production",
    ]
    assert [a["project_id"] for a in sel["actions"]] == [
        "produce_unit:settler",
        "produce_unit:warrior",
    ]
    for row in sel["actions"]:
        assert row["schema_version"] == 2
        assert row["actor_id"] == 0
        assert row["city_id"] == 1

    summary = _get_legal(client, match_id, 0, tokens[0]).json()
    assert summary["city_summaries"] == [{"city_id": 1, "legal_action_count": 2}]

    # Round-trip submit the served warrior row.
    warrior_row = next(
        a for a in sel["actions"] if a["project_id"] == "produce_unit:warrior"
    )
    r = _post(client, match_id, warrior_row, tokens[0])
    assert r.json()["accepted"] is True

    # Active warrior: none + settler (warrior excluded by project_already_set).
    sel2 = _get_legal(client, match_id, 0, tokens[0], selected_city_id=1).json()
    assert [a["project_id"] for a in sel2["actions"]] == [
        "none",
        "produce_unit:settler",
    ]
    summary2 = _get_legal(client, match_id, 0, tokens[0]).json()
    assert summary2["city_summaries"] == [{"city_id": 1, "legal_action_count": 2}]


def test_selection_errors_unknown_and_unowned_city(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    _found_capital(client, match_id, tokens[0])
    _seed_city(
        match_id,
        {
            "id": 2,
            "owner_id": 1,
            "position": [3, 3],
            "name": "Enemy Capital",
            "current_project": None,
        },
        next_city_id=3,
    )
    unknown = _get_legal(client, match_id, 0, tokens[0], selected_city_id=99).json()
    assert unknown["selection_error"] == "unknown_city"
    assert unknown["actions"] == []
    foreign = _get_legal(client, match_id, 0, tokens[0], selected_city_id=2).json()
    assert foreign["selection_error"] == "selection_not_owned_city"
    assert foreign["actions"] == []


def test_apply_set_city_production_atomic_helper() -> None:
    snap = {
        "match_id": "m",
        "revision": 3,
        "turn_state": {"players": [0, 1], "current_index": 0, "turn_number": 1},
        "units": [],
        "cities": [
            {
                "id": 1,
                "owner_id": 0,
                "position": [1, 1],
                "name": "Capital",
                "current_project": None,
            }
        ],
        "next_city_id": 2,
        "map": {"map_id": "x", "schema_version": 1, "content_hash": "h"},
    }
    out = world_actions.apply_set_city_production(
        snap, _set_prod(0, 1, "produce_unit:settler")
    )
    assert out["revision"] == 4
    assert out["cities"][0]["current_project"] == {
        "project_id": "produce_unit:settler",
        "progress": 0,
        "cost": 2,
    }
    # Original snap untouched.
    assert snap["cities"][0]["current_project"] is None
    assert snap["revision"] == 3
