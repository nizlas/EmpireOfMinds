"""Parity smoke tests for server content registries vs game/domain/content/*.gd."""

from __future__ import annotations

from app.domain.content import (
    city_project_definitions,
    progress_definitions,
    terrain_rule_definitions,
    unit_definitions,
)


def test_unit_definitions_ids_and_rows() -> None:
    assert unit_definitions.ids() == ["settler", "warrior"]
    s = unit_definitions.get_definition("settler")
    assert s is not None
    assert s["max_movement"] == 2
    assert s["max_hp"] == 100
    assert s["combat_strength"] == 0
    assert unit_definitions.can_found_city("settler") is True
    w = unit_definitions.get_definition("warrior")
    assert w is not None
    assert w["combat_strength"] == 20
    assert unit_definitions.can_found_city("warrior") is False


def test_city_project_definitions() -> None:
    assert "produce_unit:warrior" in city_project_definitions.ids()
    assert "produce_unit:settler" in city_project_definitions.ids()
    assert city_project_definitions.cost("produce_unit:warrior") == 2
    assert city_project_definitions.produces_unit_type("produce_unit:warrior") == "warrior"


def test_terrain_rule_definitions() -> None:
    assert terrain_rule_definitions.is_passable("plains") is True
    water = terrain_rule_definitions.get_definition("water")
    assert water is not None
    assert water["passable"] is False
    assert terrain_rule_definitions.terrain_id_for_hex_map_value(0) == "plains"
    assert terrain_rule_definitions.terrain_id_for_hex_map_value(1) == "water"
    assert terrain_rule_definitions.terrain_id_for_hex_map_value(2) == "grassland"


def test_progress_definitions_ancient_tree() -> None:
    ids = progress_definitions.ids()
    assert len(ids) == 19
    assert progress_definitions.cost("foraging_systems") == 6
    assert progress_definitions.prerequisites("controlled_fire") == []
    assert progress_definitions.prerequisites("agrarian_practice") == [
        "pottery_craft",
        "seasonal_calendars",
    ]
