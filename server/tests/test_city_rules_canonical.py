"""N8R single-gameplay-core guards: canonical city rules + dependency walls.

Three layers:

1. Pure-rule behavior: the canonical founding/production decisions, naming,
   project state, and event progress representation — exercised with plain
   facts, requiring NO presentation, transport, snapshot, or persistence.
2. Delegation: the active WorldMap path (POST validators, apply, and
   legal-action generation) provably routes through the SAME canonical
   validators — patched canonical rules change world behavior.
3. Dependency walls (AST, no execution): the canonical rule modules stay
   map-/transport-/persistence-free, and the world domain modules never
   import deprecated Scenario/HexMap snapshot-v2 gameplay orchestration.
"""

from __future__ import annotations

import ast
from pathlib import Path

import pytest

from app.domain import (
    city_founding_rules as cfr,
    city_production_rules as cpr,
    world_actions,
    world_legal_actions,
)

# --------------------------------------------------------- canonical naming


def test_default_city_name_sequence() -> None:
    assert cfr.default_city_name(0) == "Capital"
    assert cfr.default_city_name(1) == "Settlement 2"
    assert cfr.default_city_name(2) == "Settlement 3"
    assert cfr.default_city_name(9) == "Settlement 10"


# ------------------------------------------------- canonical founding rules


def _founder(owner=1, type_id="settler", pos=(1, 1)) -> cfr.FounderFacts:
    return cfr.FounderFacts(owner_id=owner, type_id=type_id, position=pos)


def _validate_found(**overrides):
    kwargs = dict(
        actor_id=1,
        current_player_id=1,
        founder=_founder(),
        position=(1, 1),
        tile_has_city=False,
    )
    kwargs.update(overrides)
    return cfr.validate_found_city(**kwargs)


def test_found_city_accepts_valid_settler() -> None:
    assert _validate_found() == {"ok": True, "reason": ""}


@pytest.mark.parametrize(
    ("overrides", "reason"),
    [
        ({"current_player_id": 2}, "not_current_player"),
        ({"founder": None}, "unknown_unit"),
        ({"founder": _founder(owner=2)}, "unit_not_owned_by_player"),
        ({"founder": _founder(type_id="warrior")}, "unit_cannot_found_city"),
        ({"founder": _founder(pos=(0, 1))}, "unit_not_at_position"),
        ({"tile_has_city": True}, "tile_already_has_city"),
    ],
)
def test_found_city_locked_rejections(overrides, reason) -> None:
    vr = _validate_found(**overrides)
    assert vr == {"ok": False, "reason": reason}


def test_found_city_locked_first_failure_order() -> None:
    # Every later defect present at once: the earliest reason wins, in the
    # locked chain order.
    vr = _validate_found(
        current_player_id=2,
        founder=_founder(owner=2, type_id="warrior", pos=(9, 9)),
        tile_has_city=True,
    )
    assert vr["reason"] == "not_current_player"
    vr = _validate_found(
        founder=_founder(owner=2, type_id="warrior", pos=(9, 9)),
        tile_has_city=True,
    )
    assert vr["reason"] == "unit_not_owned_by_player"
    vr = _validate_found(
        founder=_founder(type_id="warrior", pos=(9, 9)), tile_has_city=True
    )
    assert vr["reason"] == "unit_cannot_found_city"
    vr = _validate_found(founder=_founder(pos=(9, 9)), tile_has_city=True)
    assert vr["reason"] == "unit_not_at_position"


def test_found_city_effect_semantics() -> None:
    effect = cfr.found_city_effect(owner_id=7, position=(3, 4), owned_city_count=0)
    assert effect == {
        "owner_id": 7,
        "position": (3, 4),
        "name": "Capital",
        "current_project": None,
    }
    assert (
        cfr.found_city_effect(owner_id=7, position=(3, 4), owned_city_count=2)["name"]
        == "Settlement 3"
    )


# ----------------------------------------------- canonical production rules


def _city(owner=1, active=None) -> cpr.CityProductionFacts:
    return cpr.CityProductionFacts(owner_id=owner, active_project_id=active)


def _validate_prod(**overrides):
    kwargs = dict(
        actor_id=1,
        current_player_id=1,
        city=_city(),
        project_id="produce_unit:warrior",
    )
    kwargs.update(overrides)
    return cpr.validate_set_city_production(**kwargs)


def test_set_production_accepts_registry_project_and_clear() -> None:
    assert _validate_prod() == {"ok": True, "reason": ""}
    assert _validate_prod(
        city=_city(active="produce_unit:warrior"), project_id="produce_unit:settler"
    )["ok"]
    assert _validate_prod(city=_city(active="produce_unit:warrior"), project_id="none")[
        "ok"
    ]


@pytest.mark.parametrize(
    ("overrides", "reason"),
    [
        ({"current_player_id": 2}, "not_current_player"),
        ({"city": None}, "unknown_city"),
        ({"city": _city(owner=2)}, "city_not_owned_by_player"),
        ({"project_id": "produce_unit:archer"}, "unknown_city_project"),
        (
            {"city": _city(active="produce_unit:warrior")},
            "project_already_set",
        ),
        ({"project_id": "none"}, "project_already_set"),
    ],
)
def test_set_production_locked_rejections(overrides, reason) -> None:
    vr = _validate_prod(**overrides)
    assert vr == {"ok": False, "reason": reason}


def test_new_project_state_uses_registry_costs() -> None:
    assert cpr.new_project_state("none") is None
    assert cpr.new_project_state("produce_unit:warrior") == {
        "project_id": "produce_unit:warrior",
        "progress": 0,
        "cost": 2,
    }
    assert cpr.new_project_state("produce_unit:settler")["cost"] == 2


def test_project_progress_for_event_representation() -> None:
    assert cpr.project_progress_for_event(None) is None
    assert cpr.project_progress_for_event("bogus") is None
    assert cpr.project_progress_for_event({}) is None
    assert (
        cpr.project_progress_for_event(
            {"project_id": "produce_unit:warrior", "progress": 1, "cost": 2}
        )
        == 1
    )
    assert cpr.active_project_id(None) is None
    assert cpr.active_project_id({"project_id": "produce_unit:settler"}) == (
        "produce_unit:settler"
    )


def test_flat_production_constant_is_canonical() -> None:
    assert cpr.FLAT_PRODUCTION_PER_CITY == 1


# ------------------------------------------- world path uses canonical core


def _snapshot() -> dict:
    return {
        "match_id": "m_test",
        "revision": 4,
        "turn_state": {"players": [1, 2], "current_index": 0, "turn_number": 1},
        "units": [
            {
                "id": 1,
                "owner_id": 1,
                "position": [1, 1],
                "type_id": "settler",
                "current_hp": 70,
                "has_attacked": False,
            }
        ],
        "cities": [
            {
                "id": 1,
                "owner_id": 1,
                "position": [2, 2],
                "name": "Capital",
                "current_project": None,
            }
        ],
        "next_city_id": 2,
    }


def _found_action() -> dict:
    return {
        "schema_version": 1,
        "action_type": "found_city",
        "actor_id": 1,
        "unit_id": 1,
        "position": [1, 1],
    }


def _prod_action() -> dict:
    return {
        "schema_version": 2,
        "action_type": "set_city_production",
        "actor_id": 1,
        "city_id": 1,
        "project_id": "produce_unit:warrior",
    }


def test_world_found_city_routes_through_canonical_validator(monkeypatch) -> None:
    seen: list[dict] = []

    def spy(**kwargs):
        seen.append(kwargs)
        return {"ok": False, "reason": "canonical_spy"}

    monkeypatch.setattr(cfr, "validate_found_city", spy)
    vr = world_actions.validate_found_city(_snapshot(), _found_action())
    assert vr == {"ok": False, "reason": "canonical_spy"}
    assert seen and seen[0]["actor_id"] == 1
    assert seen[0]["founder"] == _founder()
    assert seen[0]["tile_has_city"] is False


def test_world_found_city_apply_uses_canonical_effect(monkeypatch) -> None:
    monkeypatch.setattr(
        cfr, "default_city_name", lambda owned: f"CANONICAL {owned}"
    )
    new_snap = world_actions.apply_found_city(_snapshot(), _found_action())
    added = [c for c in new_snap["cities"] if int(c["id"]) == 2]
    assert added and added[0]["name"] == "CANONICAL 1"


def test_world_set_production_routes_through_canonical_validator(monkeypatch) -> None:
    seen: list[dict] = []

    def spy(**kwargs):
        seen.append(kwargs)
        return {"ok": False, "reason": "canonical_spy"}

    monkeypatch.setattr(cpr, "validate_set_city_production", spy)
    vr = world_actions.validate_set_city_production(_snapshot(), _prod_action())
    assert vr == {"ok": False, "reason": "canonical_spy"}
    assert seen and seen[0]["city"] == _city()
    assert seen[0]["project_id"] == "produce_unit:warrior"


def test_world_set_production_apply_uses_canonical_project_state(monkeypatch) -> None:
    sentinel = {"project_id": "produce_unit:warrior", "progress": 0, "cost": 99}
    monkeypatch.setattr(cpr, "new_project_state", lambda pid: dict(sentinel))
    new_snap = world_actions.apply_set_city_production(_snapshot(), _prod_action())
    assert new_snap["cities"][0]["current_project"] == sentinel


def test_legal_actions_and_post_share_canonical_validators(monkeypatch) -> None:
    """Legal-action generation derives rows through the SAME canonical
    validators the POST path uses: rejecting everything canonically removes
    the found_city and set_city_production rows (moves stay untouched)."""

    class _NoTileMap:
        def has_tile_coord(self, _c):
            return False

    snap = _snapshot()
    payload = world_legal_actions.compute_world_legal_actions_payload(
        snap, _NoTileMap(), 1, None, 1
    )
    # Active project None: "none" is excluded by project_already_set, both
    # registry projects are offered (sorted).
    assert [a["project_id"] for a in payload["actions"]] == [
        "produce_unit:settler",
        "produce_unit:warrior",
    ]

    monkeypatch.setattr(
        cpr,
        "validate_set_city_production",
        lambda **_: {"ok": False, "reason": "canonical_spy"},
    )
    payload = world_legal_actions.compute_world_legal_actions_payload(
        snap, _NoTileMap(), 1, None, 1
    )
    assert payload["actions"] == []

    payload = world_legal_actions.compute_world_legal_actions_payload(
        snap, _NoTileMap(), 1, 1, None
    )
    assert [a["action_type"] for a in payload["actions"]] == ["found_city"]
    monkeypatch.setattr(
        cfr,
        "validate_found_city",
        lambda **_: {"ok": False, "reason": "canonical_spy"},
    )
    payload = world_legal_actions.compute_world_legal_actions_payload(
        snap, _NoTileMap(), 1, 1, None
    )
    assert payload["actions"] == []


# --------------------------------------------------------- dependency walls

_DOMAIN_DIR = Path(__file__).resolve().parents[1] / "app" / "domain"

# Deprecated snapshot-v2 gameplay orchestration and state types: the active
# WorldMap path must never import these (frozen legacy, N9 removal).
_DEPRECATED_GAMEPLAY_MODULES = (
    "app.domain.scenario",
    "app.domain.hex_map",
    "app.domain.legal_actions",
    "app.domain.movement_rules",
    "app.domain.production_rules",
    "app.domain.city_yields",
    "app.domain.food_growth_rules",
    "app.domain.science_tick_rules",
    "app.domain.progress_state",
    "app.domain.progress_unlock_resolver",
    "app.domain.snapshot",
    "app.domain.prototype_maps",
    "app.domain.match_state",
    "app.domain.actions",
)

# Canonical pure rules: map-, transport-, and persistence-free. Only shared
# registries (app.domain.content.*) and the stdlib are allowed.
_PURE_RULE_FORBIDDEN = _DEPRECATED_GAMEPLAY_MODULES + (
    "app.domain.world_map",
    "app.domain.world_match",
    "app.domain.world_scenario",
    "app.storage",
    "app.api",
    "fastapi",
)


def _imports_of(module_filename: str) -> set[str]:
    tree = ast.parse((_DOMAIN_DIR / module_filename).read_text(encoding="utf-8"))
    found: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            found.update(alias.name for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            found.add(node.module)
            found.update(f"{node.module}.{alias.name}" for alias in node.names)
    return found


@pytest.mark.parametrize(
    "module_filename", ["city_founding_rules.py", "city_production_rules.py"]
)
def test_canonical_rule_modules_are_pure(module_filename) -> None:
    imports = _imports_of(module_filename)
    for imp in imports:
        for forbidden in _PURE_RULE_FORBIDDEN:
            assert not imp.startswith(forbidden), (
                f"{module_filename} imports {imp}: canonical gameplay rules "
                "must stay map-, transport-, and persistence-free"
            )


@pytest.mark.parametrize(
    "module_filename",
    [
        "world_actions.py",
        "world_legal_actions.py",
        "world_match.py",
        "world_scenario.py",
    ],
)
def test_world_modules_never_import_deprecated_gameplay(module_filename) -> None:
    imports = _imports_of(module_filename)
    for imp in imports:
        for forbidden in _DEPRECATED_GAMEPLAY_MODULES:
            assert not imp.startswith(forbidden), (
                f"{module_filename} imports {imp}: the active WorldMap path "
                "must not depend on deprecated snapshot-v2 gameplay"
            )


def test_no_world_production_rules_duplicate_module_remains() -> None:
    """The N8b duplicate rules module was folded into the canonical core."""
    assert not (_DOMAIN_DIR / "world_production_rules.py").exists()
