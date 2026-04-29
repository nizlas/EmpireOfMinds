# One-step legal destination query for Phase 1.5. Read-only; does not mutate Scenario or Unit.
# See docs/MOVEMENT_RULES.md
class_name MovementRules
extends RefCounted

const HexCoordScript = preload("res://domain/hex_coord.gd")
const HexMapScript = preload("res://domain/hex_map.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const TerrainRuleDefinitionsScript = preload("res://domain/content/terrain_rule_definitions.gd")

static func legal_destinations(a_scenario, unit_id: int) -> Array:
	assert(HexCoordScript != null)
	assert(HexMapScript != null)
	assert(ScenarioScript != null)
	if a_scenario == null:
		return []
	var u = a_scenario.unit_by_id(unit_id)
	if u == null:
		return []
	var out = []
	var ns = u.position.neighbors()
	var i = 0
	while i < ns.size():
		var n = ns[i]
		if a_scenario.map.has(n) \
			and TerrainRuleDefinitionsScript.is_passable_hex_map_value(a_scenario.map.terrain_at(n)) \
			and a_scenario.units_at(n).size() == 0:
			out.append(n)
		i = i + 1
	return out
