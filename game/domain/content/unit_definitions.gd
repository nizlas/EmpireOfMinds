# Canonical Ancient/Foundation unit gameplay definitions (content only).
# Gameplay `type_id` rows (`settler`, `warrior`) remain for active engine units; full roster uses `unit_*` ids.
# See docs/CONTENT_MODEL.md, docs/UNITS.md. No combat/production/movement rule logic here.
class_name UnitDefinitions
extends RefCounted

const ORDERED_UNIT_IDS: Array[String] = [
	"unit_settler",
	"unit_warrior",
	"unit_worker",
	"unit_slinger",
	"unit_tracker_scout",
	"unit_mounted_scout_precursor",
	"unit_reed_boat",
	"unit_archer",
	"unit_war_canoe",
	"unit_bronze_armed_warrior",
	"unit_cart_support",
	"unit_siege_precursor",
]

## Active gameplay type_ids backed by canonical rows (engine `Unit.type_id` today).
const _LEGACY_GAMEPLAY_TYPE_IDS: Array[String] = ["settler", "warrior"]

const _UNLOCK_ID_BY_GAMEPLAY_TYPE: Dictionary = {
	"settler": "unit_settler",
	"warrior": "unit_warrior",
}

static var _UNITS: Dictionary = {}


static func _row(
	unit_id: String,
	name: String,
	category: String,
	hp: int,
	production_cost: int,
	movement: int,
	melee_strength: int,
	ranged_strength: int,
	attack_range: int,
	cargo_capacity: int,
	tags: Array,
	summary: String,
	extra: Dictionary = {},
) -> Dictionary:
	var out: Dictionary = {
		"id": unit_id,
		"name": name,
		"category": category,
		"hp": hp,
		"production_cost": production_cost,
		"movement": movement,
		"melee_strength": melee_strength,
		"ranged_strength": ranged_strength,
		"attack_range": attack_range,
		"cargo_capacity": cargo_capacity,
		"tags": tags.duplicate(),
		"summary": summary,
	}
	for key in extra.keys():
		out[key] = extra[key]
	return out


static func _registry() -> Dictionary:
	if not _UNITS.is_empty():
		return _UNITS
	_UNITS = {
	"unit_settler": _row(
		"unit_settler",
		"Settler",
		"civilian",
		100,
		80,
		2,
		0,
		0,
		0,
		0,
		["civilian", "land", "founder", "baseline"],
		"Founds new cities. Weak and must be protected.",
		{"gameplay_type_id": "settler"},
	),
	"unit_warrior": _row(
		"unit_warrior",
		"Warrior",
		"military",
		100,
		40,
		2,
		20,
		0,
		0,
		0,
		["military", "land", "melee", "baseline"],
		"Basic early melee defender and attacker.",
		{"gameplay_type_id": "warrior"},
	),
	"unit_worker": _row(
		"unit_worker",
		"Worker",
		"civilian",
		100,
		50,
		2,
		0,
		0,
		0,
		0,
		["civilian", "land", "worker"],
		"Builds and improves controlled tiles.",
	),
	"unit_slinger": _row(
		"unit_slinger",
		"Slinger",
		"military",
		100,
		35,
		2,
		5,
		15,
		1,
		0,
		["military", "land", "ranged", "early_ranged"],
		"Cheap early ranged unit with short reach and weak melee defense.",
	),
	"unit_tracker_scout": _row(
		"unit_tracker_scout",
		"Tracker Scout",
		"military",
		100,
		35,
		3,
		10,
		0,
		0,
		0,
		["military", "land", "recon"],
		"Experienced scout for exploration and early warning.",
	),
	"unit_mounted_scout_precursor": _row(
		"unit_mounted_scout_precursor",
		"Mounted Scout",
		"military",
		100,
		55,
		3,
		16,
		0,
		0,
		0,
		["military", "land", "recon", "mounted"],
		"Fast mounted recon unit with modest combat value.",
	),
	"unit_reed_boat": _row(
		"unit_reed_boat",
		"Reed Boat",
		"naval",
		100,
		55,
		3,
		10,
		0,
		0,
		1,
		["naval", "transport", "cargo"],
		"Early troop transport. Can carry one land unit but is poor in combat.",
	),
	"unit_archer": _row(
		"unit_archer",
		"Archer",
		"military",
		100,
		65,
		2,
		15,
		25,
		2,
		0,
		["military", "land", "ranged"],
		"Stronger ranged unit with proper battlefield reach.",
	),
	"unit_war_canoe": _row(
		"unit_war_canoe",
		"War Canoe",
		"naval",
		100,
		70,
		3,
		24,
		18,
		1,
		0,
		["military", "naval", "melee", "light_ranged"],
		"First dedicated war boat. Dangerous on water but still primitive.",
	),
	# Intentionally ~80–85% of a later Swordsman / Iron Infantry power level.
	"unit_bronze_armed_warrior": _row(
		"unit_bronze_armed_warrior",
		"Bronze-Armed Warrior",
		"military",
		100,
		75,
		2,
		30,
		0,
		0,
		0,
		["military", "land", "melee", "bronze"],
		"Strong ancient melee unit armed with early bronze weapons.",
	),
	# Wheelwrighting is late in the mini-game; logistics value is intentionally strong (behavior not implemented).
	"unit_cart_support": _row(
		"unit_cart_support",
		"Cart Support Unit",
		"support",
		100,
		70,
		2,
		0,
		0,
		0,
		0,
		["support", "land", "logistics", "aura", "charges"],
		"Logistics cart that improves operational movement and can spend limited supplies to heal nearby land units.",
		{
			"charges": 3,
			"support_aura": {
				"id": "aura_cart_movement",
				"name": "Cart Movement Support",
				"effect": "friendly_land_units_within_1_gain_plus_1_movement",
				"radius": 1,
				"movement_bonus": 1,
				"applies_to_tags": ["land"],
				"excludes_tags": ["naval"],
				"stacks": false,
			},
			"support_action": {
				"id": "action_cart_supply_heal",
				"name": "Supply Heal",
				"charges": 3,
				"heal_amount": 15,
				"target": "adjacent_friendly_land_unit",
				"remove_unit_when_charges_spent": true,
			},
		},
	),
	# Effective vs palisade-tier; poor vs mudbrick/early/stone walls (mini-game near-final defenses).
	"unit_siege_precursor": _row(
		"unit_siege_precursor",
		"Siege Precursor",
		"support",
		100,
		75,
		2,
		0,
		0,
		0,
		0,
		["support", "land", "siege", "anti_palisade"],
		"Primitive assault engineering unit. Useful against palisades and light fortifications, not true walls.",
		{
			"siege_profile": {
				"id": "siege_precursor_palisade_breaker",
				"name": "Palisade Breaker",
				"effective_against": ["palisade", "barricade", "field_fortification"],
				"poor_against": ["mudbrick_wall", "early_wall", "stone_wall"],
				"effect": "adjacent_friendly_melee_attacks_reduce_or_ignore_palisade_defense",
				"stacks": false,
			},
		},
	),
	}
	return _UNITS


static func unit_ids() -> Array:
	return ORDERED_UNIT_IDS.duplicate()


static func all_units() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var i: int = 0
	while i < ORDERED_UNIT_IDS.size():
		var row: Dictionary = get_unit(ORDERED_UNIT_IDS[i])
		if not row.is_empty():
			out.append(row)
		i += 1
	return out


static func has_unit(unit_id: String) -> bool:
	return _registry().has(str(unit_id).strip_edges())


static func get_unit(unit_id: String) -> Dictionary:
	var key: String = str(unit_id).strip_edges()
	if not _registry().has(key):
		return {}
	return (_registry()[key] as Dictionary).duplicate(true)


static func tags_for(unit_id: String) -> Array:
	var unit: Dictionary = get_unit(unit_id)
	if unit.is_empty():
		return []
	var tags: Array = unit.get("tags", [])
	return tags.duplicate()


static func has_tag(unit_id: String, tag: String) -> bool:
	var needle: String = str(tag).strip_edges()
	var tags: Array = tags_for(unit_id)
	var i: int = 0
	while i < tags.size():
		if str(tags[i]) == needle:
			return true
		i += 1
	return false


static func cost_for(unit_id: String) -> int:
	var unit: Dictionary = get_unit(unit_id)
	if unit.is_empty():
		return 0
	return int(unit.get("production_cost", 0))


static func movement_for(unit_id: String) -> int:
	var unit: Dictionary = get_unit(unit_id)
	if unit.is_empty():
		return 0
	return int(unit.get("movement", 0))


static func enrich_unit_row(row: Dictionary) -> Dictionary:
	var out: Dictionary = row.duplicate(true)
	var unit_id: String = str(out.get("id", ""))
	if not has_unit(unit_id):
		return out
	var unit: Dictionary = get_unit(unit_id)
	out["category"] = str(unit.get("category", ""))
	out["hp"] = int(unit.get("hp", 0))
	out["production_cost"] = int(unit.get("production_cost", 0))
	out["movement"] = int(unit.get("movement", 0))
	out["melee_strength"] = int(unit.get("melee_strength", 0))
	out["ranged_strength"] = int(unit.get("ranged_strength", 0))
	out["attack_range"] = int(unit.get("attack_range", 0))
	out["cargo_capacity"] = int(unit.get("cargo_capacity", 0))
	if unit.has("charges"):
		out["charges"] = int(unit.get("charges", 0))
	if unit.has("support_aura"):
		out["support_aura"] = (unit.get("support_aura", {}) as Dictionary).duplicate(true)
	if unit.has("support_action"):
		out["support_action"] = (unit.get("support_action", {}) as Dictionary).duplicate(true)
	if unit.has("siege_profile"):
		out["siege_profile"] = (unit.get("siege_profile", {}) as Dictionary).duplicate(true)
	out["unit_tags"] = tags_for(unit_id)
	if str(out.get("summary", "")).is_empty():
		out["summary"] = str(unit.get("summary", ""))
	return out


# --- Legacy gameplay type_id API (settler / warrior only) ---


static func has(id: String) -> bool:
	var key: String = str(id).strip_edges()
	return _UNLOCK_ID_BY_GAMEPLAY_TYPE.has(key)


static func get_definition(id: String):
	var gameplay_type: String = str(id).strip_edges()
	if not _UNLOCK_ID_BY_GAMEPLAY_TYPE.has(gameplay_type):
		return null
	return _legacy_definition_for_unlock_id(_UNLOCK_ID_BY_GAMEPLAY_TYPE[gameplay_type])


static func ids() -> Array:
	return _LEGACY_GAMEPLAY_TYPE_IDS.duplicate()


static func can_found_city(id: String) -> bool:
	return has_tag(str(_UNLOCK_ID_BY_GAMEPLAY_TYPE.get(str(id).strip_edges(), "")), "founder")


static func max_movement_for_type(type_id: String) -> int:
	return movement_for(str(_UNLOCK_ID_BY_GAMEPLAY_TYPE.get(str(type_id).strip_edges(), "")))


static func max_hp_for_type(type_id: String) -> int:
	var unit: Dictionary = get_unit(str(_UNLOCK_ID_BY_GAMEPLAY_TYPE.get(str(type_id).strip_edges(), "")))
	if unit.is_empty():
		return 0
	return int(unit.get("hp", 0))


static func combat_strength_for_type(type_id: String) -> int:
	var unit: Dictionary = get_unit(str(_UNLOCK_ID_BY_GAMEPLAY_TYPE.get(str(type_id).strip_edges(), "")))
	if unit.is_empty():
		return 0
	return int(unit.get("melee_strength", 0))


static func _legacy_definition_for_unlock_id(unlock_id: String) -> Dictionary:
	var unit: Dictionary = get_unit(unlock_id)
	if unit.is_empty():
		return {}
	var gameplay_type: String = str(unit.get("gameplay_type_id", ""))
	var role: String = "basic_melee"
	if has_tag(unlock_id, "founder"):
		role = "founder"
	return {
		"id": gameplay_type,
		"display_name": str(unit.get("name", "")),
		"can_found_city": has_tag(unlock_id, "founder"),
		"production_cost": int(unit.get("production_cost", 0)),
		"role": role,
		"max_movement": int(unit.get("movement", 0)),
		"combat_strength": int(unit.get("melee_strength", 0)),
		"max_hp": int(unit.get("hp", 0)),
		"unlock_id": unlock_id,
	}
