"""Slice C10: server attack_unit flow and legal-actions."""

from __future__ import annotations

from fastapi.testclient import TestClient

from app.domain.actions import attack_unit
from app.domain.snapshot import scenario_from_snapshot_dict
from app.storage import file_store
from tests.combat_test_helpers import (
    inject_adjacent_warriors_for_combat_tests,
    inject_distant_enemy_warrior_on_prototype_play,
    inject_friendly_adjacent_warrior_defender,
)


def _u_by_id(snap: dict, uid: int) -> dict | None:
    for u in snap["scenario"]["units"]:
        if u["id"] == uid:
            return u
    return None


def _combat_mid(client: TestClient) -> str:
    mid = client.post("/v1/matches", json={"scenario_id": "tiny_test"}).json()["match_id"]
    inject_adjacent_warriors_for_combat_tests(mid)
    return mid


def test_accepted_attack_adjacent_enemy(client: TestClient) -> None:
    mid = _combat_mid(client)
    snap0 = client.get(f"/v1/matches/{mid}").json()
    r = client.post(
        f"/v1/matches/{mid}/actions",
        json={
            "schema_version": 1,
            "action_type": "attack_unit",
            "actor_id": 0,
            "attacker_id": 2,
            "defender_id": 3,
        },
    )
    assert r.status_code == 200
    body = r.json()
    assert body["accepted"] is True
    assert body["revision"] == snap0["revision"] + 1
    atk = _u_by_id(body["snapshot"], 2)
    assert atk is not None
    assert atk["current_hp"] == 70
    assert atk["remaining_movement"] == 0
    def_u = _u_by_id(body["snapshot"], 3)
    assert def_u is not None
    assert def_u["current_hp"] == 70
    ev = client.get(f"/v1/matches/{mid}/events").json()["events"][0]
    assert ev["action_type"] == "attack_unit"
    assert body["event"] == ev
    assert ev["defender_damage_taken"] == 30
    assert ev["attacker_damage_taken"] == 30
    assert ev["retaliated"] is True
    assert ev["attacker_position"] == [1, 0]
    assert ev["defender_position"] == [1, -1]


def test_rejects_not_current_player(client: TestClient) -> None:
    mid = _combat_mid(client)
    r = client.post(
        f"/v1/matches/{mid}/actions",
        json={
            "schema_version": 1,
            "action_type": "attack_unit",
            "actor_id": 1,
            "attacker_id": 2,
            "defender_id": 3,
        },
    )
    assert r.json()["accepted"] is False
    assert r.json()["reason"] == "not_current_player"


def test_rejects_unknown_attacker(client: TestClient) -> None:
    mid = _combat_mid(client)
    r = client.post(
        f"/v1/matches/{mid}/actions",
        json={
            "schema_version": 1,
            "action_type": "attack_unit",
            "actor_id": 0,
            "attacker_id": 99,
            "defender_id": 3,
        },
    )
    assert r.json()["reason"] == "unknown_attacker"


def test_rejects_unknown_defender(client: TestClient) -> None:
    mid = _combat_mid(client)
    r = client.post(
        f"/v1/matches/{mid}/actions",
        json={
            "schema_version": 1,
            "action_type": "attack_unit",
            "actor_id": 0,
            "attacker_id": 2,
            "defender_id": 99,
        },
    )
    assert r.json()["reason"] == "unknown_defender"


def test_rejects_actor_not_owner(client: TestClient) -> None:
    mid = _combat_mid(client)
    r = client.post(
        f"/v1/matches/{mid}/actions",
        json={
            "schema_version": 1,
            "action_type": "attack_unit",
            "actor_id": 0,
            "attacker_id": 3,
            "defender_id": 2,
        },
    )
    assert r.json()["reason"] == "actor_not_owner"


def test_rejects_friendly_target(client: TestClient) -> None:
    mid = _combat_mid(client)
    inject_friendly_adjacent_warrior_defender(mid)
    r = client.post(
        f"/v1/matches/{mid}/actions",
        json={
            "schema_version": 1,
            "action_type": "attack_unit",
            "actor_id": 0,
            "attacker_id": 2,
            "defender_id": 3,
        },
    )
    assert r.json()["reason"] == "cannot_attack_own_unit"


def test_rejects_non_adjacent(client: TestClient) -> None:
    mid = client.post("/v1/matches", json={"scenario_id": "prototype_play"}).json()["match_id"]
    inject_distant_enemy_warrior_on_prototype_play(mid)
    r = client.post(
        f"/v1/matches/{mid}/actions",
        json={
            "schema_version": 1,
            "action_type": "attack_unit",
            "actor_id": 0,
            "attacker_id": 2,
            "defender_id": 3,
        },
    )
    assert r.json()["reason"] == "defender_not_adjacent"


def test_rejects_movement_exhausted(client: TestClient) -> None:
    mid = _combat_mid(client)
    snap = file_store.read_snapshot(mid)
    assert snap is not None
    for u in snap["scenario"]["units"]:
        if int(u["id"]) == 2:
            u["remaining_movement"] = 0
    file_store.write_snapshot(mid, snap)
    r = client.post(
        f"/v1/matches/{mid}/actions",
        json={
            "schema_version": 1,
            "action_type": "attack_unit",
            "actor_id": 0,
            "attacker_id": 2,
            "defender_id": 3,
        },
    )
    assert r.json()["reason"] == "movement_exhausted"


def test_defender_removed_at_zero_hp(client: TestClient) -> None:
    mid = _combat_mid(client)
    snap = file_store.read_snapshot(mid)
    assert snap is not None
    for u in snap["scenario"]["units"]:
        if int(u["id"]) == 3:
            u["current_hp"] = 20
    file_store.write_snapshot(mid, snap)
    r = client.post(
        f"/v1/matches/{mid}/actions",
        json={
            "schema_version": 1,
            "action_type": "attack_unit",
            "actor_id": 0,
            "attacker_id": 2,
            "defender_id": 3,
        },
    )
    assert r.json()["accepted"] is True
    assert _u_by_id(r.json()["snapshot"], 3) is None
    ev = client.get(f"/v1/matches/{mid}/events").json()["events"][0]
    assert ev["defender_killed"] is True
    assert ev["attacker_damage_taken"] == 0


def test_legal_actions_lists_attack_for_adjacent_enemy(client: TestClient) -> None:
    mid = _combat_mid(client)
    g = client.get(
        f"/v1/matches/{mid}/legal-actions",
        params={"actor_id": 0, "selected_unit_id": 2},
    ).json()
    attacks = [a for a in g["actions"] if a["action_type"] == "attack_unit"]
    assert len(attacks) == 1
    assert attacks[0] == {
        "schema_version": 1,
        "action_type": "attack_unit",
        "actor_id": 0,
        "attacker_id": 2,
        "defender_id": 3,
    }
    snap = file_store.read_snapshot(mid)
    assert snap is not None
    assert attack_unit.validate(scenario_from_snapshot_dict(snap["scenario"]), attacks[0])["ok"]


def test_summary_mode_no_attack_rows(client: TestClient) -> None:
    mid = _combat_mid(client)
    g = client.get(f"/v1/matches/{mid}/legal-actions", params={"actor_id": 0}).json()
    assert not any(a["action_type"] == "attack_unit" for a in g["actions"])


def test_rejected_attack_has_no_event(client: TestClient) -> None:
    mid = _combat_mid(client)
    r = client.post(
        f"/v1/matches/{mid}/actions",
        json={
            "schema_version": 1,
            "action_type": "attack_unit",
            "actor_id": 1,
            "attacker_id": 2,
            "defender_id": 3,
        },
    )
    body = r.json()
    assert body["accepted"] is False
    assert "event" not in body
