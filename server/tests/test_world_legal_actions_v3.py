"""N7b: world legal-actions — credential gate, envelope parity, derivation.

Covers: removal of the final 409; host/matching-seat/missing/invalid/wrong-
seat credentials (403 detail strings); out-of-turn empty response with the
legacy envelope; deterministic summaries and DIRECTIONS-ordered move rows
pinned against canonical content; all selection errors; cliff and occupied
destinations excluded; map-content drift failing closed (HTTP 500, strictly
read-only); every advertised action accepted by the N7a POST path on an
isolated equivalent match; legacy legal-actions remaining token-free and
unchanged.
"""

from __future__ import annotations

from fastapi.testclient import TestClient

from app.domain.map_content_loader import load_world_map
from app.domain.state_hash import state_hash
from app.domain.world_map import EDGE_CLIFF
from app.storage import file_store
from match_helpers import SEAT_TOKEN_HEADER, create_seated_match
from test_world_map_actions_v3 import (
    MISMATCH_DETAIL,
    REFERENCE_MAP_ID,
    _delete_meta,
    _make_drifted_content_root,
    _post,
    _start_world_match,
    _teleport_unit,
)

# Pinned against canonical handdrawn_test_map_full_01 content: each spawn
# unit has exactly 5 legal destinations (one neighbor occupied by its group
# partner). DIRECTIONS order is E, NE, NW, W, SW, SE.
UNIT_1_DESTINATIONS = [[2, 0], [1, 0], [0, 1], [0, 2], [1, 2]]
UNIT_2_DESTINATIONS = [[3, 1], [3, 0], [2, 0], [1, 2], [2, 2]]


def _get_legal(
    client: TestClient,
    match_id: str,
    actor_id: int,
    token: str | None,
    **params,
):
    headers = {SEAT_TOKEN_HEADER: token} if token else {}
    return client.get(
        f"/v1/matches/{match_id}/legal-actions",
        params={"actor_id": actor_id, **params},
        headers=headers,
    )


def _move_row(actor_id: int, unit_id: int, from_c, to_c) -> dict:
    return {
        "schema_version": 1,
        "action_type": "move_unit",
        "actor_id": actor_id,
        "unit_id": unit_id,
        "from": list(from_c),
        "to": list(to_c),
    }


# ------------------------------------------------------------- credentials


def test_missing_token_403(client: TestClient) -> None:
    match_id, _, _ = _start_world_match(client)
    r = _get_legal(client, match_id, 0, token=None)
    assert r.status_code == 403
    assert r.json()["detail"] == "missing_seat_token"


def test_invalid_token_403(client: TestClient) -> None:
    match_id, _, _ = _start_world_match(client)
    r = _get_legal(client, match_id, 0, token="st_bogus")
    assert r.status_code == 403
    assert r.json()["detail"] == "invalid_seat_token"


def test_wrong_seat_token_403(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    r = _get_legal(client, match_id, 0, token=tokens[1])
    assert r.status_code == 403
    assert r.json()["detail"] == "seat_not_allowed"


def test_host_token_any_actor_200(client: TestClient) -> None:
    match_id, _, data = _start_world_match(client)
    for actor in (0, 1):
        r = _get_legal(client, match_id, actor, token=data["host_token"])
        assert r.status_code == 200, r.text


def test_matching_seat_token_200(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    r = _get_legal(client, match_id, 0, token=tokens[0])
    assert r.status_code == 200


def test_missing_meta_fails_closed(client: TestClient) -> None:
    """No metadata-free mode for world_map: with meta.json absent, a blank
    token is 403 missing_seat_token and any supplied token (even a previously
    valid seat token) is 403 invalid_seat_token — the request stops at the
    credential gate and stays read-only."""
    match_id, tokens, _ = _start_world_match(client)
    snap_before = file_store.read_snapshot(match_id)
    events_before = file_store.read_events(match_id)
    _delete_meta(match_id)

    r = _get_legal(client, match_id, 0, token=None)
    assert r.status_code == 403
    assert r.json()["detail"] == "missing_seat_token"
    r = _get_legal(client, match_id, 0, token=tokens[0])
    assert r.status_code == 403
    assert r.json()["detail"] == "invalid_seat_token"

    assert file_store.read_snapshot(match_id) == snap_before
    assert file_store.read_events(match_id) == events_before


# ------------------------------------------------------- envelope / summary


def test_out_of_turn_empty_response(client: TestClient) -> None:
    """Authenticated out-of-turn actor: 200 with is_current_player false and
    empty actions — no status gate, no current-player rejection."""
    match_id, tokens, _ = _start_world_match(client)
    r = _get_legal(client, match_id, 1, token=tokens[1])
    assert r.status_code == 200
    body = r.json()
    assert body["is_current_player"] is False
    assert body["actions"] == []
    assert body["selection_error"] is None
    # Legacy envelope parity: summaries are absent for out-of-turn actors.
    assert "unit_summaries" not in body and "city_summaries" not in body


def test_summary_mode_deterministic(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    r = _get_legal(client, match_id, 0, token=tokens[0])
    body = r.json()
    assert body["match_id"] == match_id
    assert body["revision"] == 0
    assert body["schema_version"] == 1
    assert body["actor_id"] == 0
    assert body["is_current_player"] is True
    assert body["selected_unit_id"] is None and body["selected_city_id"] is None
    assert body["selection_error"] is None
    assert body["actions"] == [
        {"schema_version": 1, "action_type": "end_turn", "actor_id": 0}
    ]
    assert body["unit_summaries"] == [
        {"unit_id": 1, "legal_action_count": 5},
        {"unit_id": 2, "legal_action_count": 5},
    ]
    assert body["city_summaries"] == []


# ------------------------------------------------- selected-unit move rows


def test_selected_unit_rows_direction_order(client: TestClient) -> None:
    """Move rows use the exact N7a POST shape in canonical DIRECTIONS order;
    the occupied partner tile (2,1) is excluded for unit 1."""
    match_id, tokens, _ = _start_world_match(client)
    r = _get_legal(client, match_id, 0, token=tokens[0], selected_unit_id=1)
    body = r.json()
    assert body["selected_unit_id"] == 1
    assert body["selection_error"] is None
    assert body["actions"] == [
        _move_row(0, 1, [1, 1], to) for to in UNIT_1_DESTINATIONS
    ]
    assert [2, 1] not in [a["to"] for a in body["actions"]]


def test_summary_count_equals_selected_rows(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    summary = _get_legal(client, match_id, 0, token=tokens[0]).json()
    for row in summary["unit_summaries"]:
        sel = _get_legal(
            client, match_id, 0, token=tokens[0], selected_unit_id=row["unit_id"]
        ).json()
        assert row["legal_action_count"] == len(sel["actions"])
    sel2 = _get_legal(client, match_id, 0, token=tokens[0], selected_unit_id=2).json()
    assert sel2["actions"] == [_move_row(0, 2, [2, 1], to) for to in UNIT_2_DESTINATIONS]


def test_cliff_destination_excluded(client: TestClient) -> None:
    """A real canonical cliff edge never appears as an advertised move."""
    match_id, tokens, _ = _start_world_match(client)
    wm = load_world_map(REFERENCE_MAP_ID)
    snap = file_store.read_snapshot(match_id)
    assert snap is not None
    other_positions = {
        (int(u["position"][0]), int(u["position"][1]))
        for u in snap["units"]
        if int(u["id"]) != 2
    }
    cliff = next(
        e
        for e in wm.all_edges()
        if e.transition == EDGE_CLIFF
        and e.tile_a not in other_positions
        and e.tile_b not in other_positions
    )
    _teleport_unit(match_id, 2, cliff.tile_a)
    body = _get_legal(client, match_id, 0, token=tokens[0], selected_unit_id=2).json()
    destinations = [tuple(a["to"]) for a in body["actions"]]
    assert cliff.tile_b not in destinations
    # And every returned destination is a smooth-edge neighbor.
    for dest in destinations:
        assert wm.edge_between(cliff.tile_a, dest).transition == "smooth"


# --------------------------------------------------------- selection errors


def test_selection_unknown_unit(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    body = _get_legal(client, match_id, 0, token=tokens[0], selected_unit_id=99).json()
    assert body["selection_error"] == "unknown_unit"
    assert body["actions"] == []


def test_selection_not_owned(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    body = _get_legal(client, match_id, 0, token=tokens[0], selected_unit_id=3).json()
    assert body["selection_error"] == "selection_not_owned"
    assert body["actions"] == []


def test_selection_unknown_city(client: TestClient) -> None:
    """No world cities in N7: any city selection is unknown_city, including
    beside a valid owned unit selection (legacy precedence preserved)."""
    match_id, tokens, _ = _start_world_match(client)
    body = _get_legal(client, match_id, 0, token=tokens[0], selected_city_id=1).json()
    assert body["selection_error"] == "unknown_city"
    assert body["actions"] == []
    both = _get_legal(
        client, match_id, 0, token=tokens[0], selected_unit_id=1, selected_city_id=1
    ).json()
    assert both["selection_error"] == "unknown_city"
    assert both["actions"] == []


# ------------------------------------------------- drift + read-only checks


def test_content_drift_500_read_only(client: TestClient, tmp_path, monkeypatch) -> None:
    match_id, tokens, _ = _start_world_match(client)
    snap_before = file_store.read_snapshot(match_id)
    events_before = file_store.read_events(match_id)
    drift_root = _make_drifted_content_root(tmp_path)
    monkeypatch.setenv("EMPIRE_MAP_CONTENT_DIR", str(drift_root))
    r = _get_legal(client, match_id, 0, token=tokens[0])
    assert r.status_code == 500
    assert r.json()["detail"] == MISMATCH_DETAIL
    assert file_store.read_snapshot(match_id) == snap_before
    assert file_store.read_events(match_id) == events_before


def test_success_is_read_only(client: TestClient) -> None:
    match_id, tokens, _ = _start_world_match(client)
    snap_before = file_store.read_snapshot(match_id)
    events_before = file_store.read_events(match_id)
    hash_before = state_hash(snap_before)
    for params in ({}, {"selected_unit_id": 1}, {"selected_unit_id": 99}):
        r = _get_legal(client, match_id, 0, token=tokens[0], **params)
        assert r.status_code == 200
    snap_after = file_store.read_snapshot(match_id)
    assert snap_after == snap_before
    assert state_hash(snap_after) == hash_before
    assert file_store.read_events(match_id) == events_before


# ---------------------------------------------------- submit-ready round trip


def test_every_advertised_action_accepted_by_n7a(client: TestClient) -> None:
    """Each advertised action, submitted against an isolated equivalent match
    (identical create + auto-start), is accepted by the N7a POST path."""
    match_id, tokens, _ = _start_world_match(client)
    summary = _get_legal(client, match_id, 0, token=tokens[0]).json()
    advertised: list[dict] = list(summary["actions"])  # end_turn
    for row in summary["unit_summaries"]:
        sel = _get_legal(
            client, match_id, 0, token=tokens[0], selected_unit_id=row["unit_id"]
        ).json()
        advertised.extend(sel["actions"])
    assert len(advertised) == 1 + 5 + 5
    for action in advertised:
        fresh_id, fresh_tokens, _ = _start_world_match(client)
        r = _post(client, fresh_id, action, fresh_tokens[0])
        assert r.status_code == 200, r.text
        assert r.json()["accepted"] is True, (action, r.text)


# ----------------------------------------------------------- legacy intact


def test_legacy_legal_actions_token_free_unchanged(client: TestClient) -> None:
    seated = create_seated_match(client, {"player_ids": [0, 1]})
    match_id = seated["match_id"]
    r = client.get(f"/v1/matches/{match_id}/legal-actions", params={"actor_id": 0})
    assert r.status_code == 200
    body = r.json()
    assert body["schema_version"] == 1
    assert body["is_current_player"] is True
    assert any(a["action_type"] == "end_turn" for a in body["actions"])
    assert "unit_summaries" in body and "city_summaries" in body
