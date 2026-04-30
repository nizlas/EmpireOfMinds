# Immutable faction profile registry. Phase 3.5b debug seed only — non-canonical. Metadata only, no enforcement, no cross-registry validation. See docs/FACTION_IDENTITY.md.
class_name FactionDefinitions
extends RefCounted

const _ORDERED_IDS: Array = [
	"debug_vasterviksjavlarna",
	"debug_malmofubikkarna",
	"debug_pajasarna_fran_paris",
]

const _DEFINITIONS: Dictionary = {
	"debug_vasterviksjavlarna":
	{
		"id": "debug_vasterviksjavlarna",
		"display_name": "Västerviksjävlarna",
		"profile_type": "debug_example",
		"canon_status": "non_canonical",
		"one_line_fantasy": "Coastal, stubborn, overambitious, theory-heavy proto-civilisation with poor practical logistics.",
		"trait_ids": [
			"origin:coastal_people",
			"science:theoretical_research_culture",
			"value:stubborn_independence",
			"weakness:poor_logistics",
			"weakness:impractical_implementation",
		],
		"strength_biases": ["science", "progress_insight"],
		"weakness_biases": ["logistics", "practical_conversion", "production_efficiency"],
		"visual_identity":
		{
			"palette": ["sea_storm", "weathered_wood", "cold_blue_gray"],
			"motifs": ["defiant_fishing_village_banner", "storm", "coast"],
			"banner_direction": "Defiant coastal banner; humorous but readable.",
		},
		"prototype_notes": "Non-canonical toy profile used to test extreme science-vs-logistics asymmetry.",
	},
	"debug_malmofubikkarna":
	{
		"id": "debug_malmofubikkarna",
		"display_name": "Malmöfubikkarna",
		"profile_type": "debug_example",
		"canon_status": "non_canonical",
		"one_line_fantasy": "Blunt, practical, urban fighters with lower science but higher combat value.",
		"trait_ids": [
			"origin:urban_coastal_people",
			"military:strong_militia_tradition",
			"society:pragmatic_mobilization",
			"weakness:lower_theoretical_science",
			"weakness:diplomatic_rough_edges",
		],
		"strength_biases": ["combat", "local_defense", "mobilization"],
		"weakness_biases": ["science", "diplomacy"],
		"visual_identity":
		{
			"palette": ["soot_gray", "industrial_orange", "harbor_blue"],
			"motifs": ["gritty_industrial_port_banner", "anvil", "dockyard"],
			"banner_direction": "Gritty industrial-port banner; pragmatic and unfussy.",
		},
		"prototype_notes": "Non-canonical toy profile used to test militia / urban-resilience identity without science focus.",
	},
	"debug_pajasarna_fran_paris":
	{
		"id": "debug_pajasarna_fran_paris",
		"display_name": "Pajasarna från Paris",
		"profile_type": "debug_example",
		"canon_status": "non_canonical",
		"one_line_fantasy": "Culture-heavy performance society with strong influence and questionable discipline.",
		"trait_ids": [
			"culture:theatrical_public_life",
			"value:prestige_and_style",
			"diplomacy:soft_power_networks",
			"weakness:military_discipline_gap",
			"weakness:practical_overhead",
		],
		"strength_biases": ["culture", "influence", "diplomacy", "morale"],
		"weakness_biases": ["military_discipline", "production_practicality"],
		"visual_identity":
		{
			"palette": ["stage_red", "gilt_gold", "midnight_violet"],
			"motifs": ["theatrical_mask_banner", "ribbon", "spotlight"],
			"banner_direction": "Theatrical-mask banner; bold, performative, slightly absurd.",
		},
		"prototype_notes": "Non-canonical toy profile used to test pure soft-power profile against stability, production, and combat-heavy prototypes.",
	},
}


static func has(id: String) -> bool:
	return _DEFINITIONS.has(id)


static func ids() -> Array:
	return _ORDERED_IDS.duplicate()


static func get_definition(id: String):
	if not _DEFINITIONS.has(id):
		return null
	var src: Dictionary = _DEFINITIONS[id]
	return src.duplicate(true)


static func display_name(id: String) -> String:
	if not _DEFINITIONS.has(id):
		return ""
	return String((_DEFINITIONS[id] as Dictionary)["display_name"])


static func profile_type(id: String) -> String:
	if not _DEFINITIONS.has(id):
		return ""
	return String((_DEFINITIONS[id] as Dictionary)["profile_type"])


static func canon_status(id: String) -> String:
	if not _DEFINITIONS.has(id):
		return ""
	return String((_DEFINITIONS[id] as Dictionary)["canon_status"])


static func one_line_fantasy(id: String) -> String:
	if not _DEFINITIONS.has(id):
		return ""
	return String((_DEFINITIONS[id] as Dictionary)["one_line_fantasy"])


static func trait_ids(id: String) -> Array:
	if not _DEFINITIONS.has(id):
		return []
	var row: Dictionary = _DEFINITIONS[id]
	return (row["trait_ids"] as Array).duplicate(true)


static func strength_biases(id: String) -> Array:
	if not _DEFINITIONS.has(id):
		return []
	var row: Dictionary = _DEFINITIONS[id]
	return (row["strength_biases"] as Array).duplicate(true)


static func weakness_biases(id: String) -> Array:
	if not _DEFINITIONS.has(id):
		return []
	var row: Dictionary = _DEFINITIONS[id]
	return (row["weakness_biases"] as Array).duplicate(true)


static func visual_identity(id: String) -> Dictionary:
	if not _DEFINITIONS.has(id):
		return {}
	var row: Dictionary = _DEFINITIONS[id]
	return (row["visual_identity"] as Dictionary).duplicate(true)


static func prototype_notes(id: String) -> String:
	if not _DEFINITIONS.has(id):
		return ""
	return String((_DEFINITIONS[id] as Dictionary)["prototype_notes"])
