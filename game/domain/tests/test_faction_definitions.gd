extends SceneTree

const FactionDefinitionsScript = preload("res://domain/content/faction_definitions.gd")

var _total: int = 0
var _any_fail: bool = false


func _init() -> void:
	# 1) has positives
	_check(FactionDefinitionsScript.has("debug_vasterviksjavlarna"), "has(debug_vasterviksjavlarna)")
	_check(FactionDefinitionsScript.has("debug_malmofubikkarna"), "has(debug_malmofubikkarna)")
	_check(FactionDefinitionsScript.has("debug_pajasarna_fran_paris"), "has(debug_pajasarna_fran_paris)")

	# 2) has negatives
	_check(FactionDefinitionsScript.has("hearthbound") == false, "has(hearthbound) is false")
	_check(FactionDefinitionsScript.has("wayfinders") == false, "has(wayfinders) is false")
	_check(FactionDefinitionsScript.has("forge_compact") == false, "has(forge_compact) is false")
	_check(FactionDefinitionsScript.has("nope") == false, "has(nope) is false")

	# 3) ids exact order and size
	var expected_ids: Array = [
		"debug_vasterviksjavlarna",
		"debug_malmofubikkarna",
		"debug_pajasarna_fran_paris",
	]
	var ids: Array = FactionDefinitionsScript.ids()
	_check(ids.size() == 3, "ids size is 3")
	_check(ids == expected_ids, "ids exact order")

	# 4) ids defensive duplicate
	var ids_mutable: Array = FactionDefinitionsScript.ids()
	ids_mutable.append("mutated")
	var ids2: Array = FactionDefinitionsScript.ids()
	_check(ids2 == expected_ids, "ids() not mutated by caller")

	# 5) Full row read for debug_vasterviksjavlarna
	_check(FactionDefinitionsScript.display_name("debug_vasterviksjavlarna") == "Västerviksjävlarna", "vastervik display_name")
	_check(FactionDefinitionsScript.profile_type("debug_vasterviksjavlarna") == "debug_example", "vastervik profile_type")
	_check(FactionDefinitionsScript.canon_status("debug_vasterviksjavlarna") == "non_canonical", "vastervik canon_status")
	var olf: String = FactionDefinitionsScript.one_line_fantasy("debug_vasterviksjavlarna")
	_check(olf.length() > 0, "vastervik one_line_fantasy non-empty")
	var traits: Array = FactionDefinitionsScript.trait_ids("debug_vasterviksjavlarna")
	_check(traits is Array, "trait_ids is Array")
	var expected_traits: Array = [
		"origin:coastal_people",
		"science:theoretical_research_culture",
		"value:stubborn_independence",
		"weakness:poor_logistics",
		"weakness:impractical_implementation",
	]
	_check(traits == expected_traits, "trait_ids exact order")

	var sb: Array = FactionDefinitionsScript.strength_biases("debug_vasterviksjavlarna")
	_check(sb.size() == 2, "strength_biases size")
	_check(sb.has("science"), "strength includes science")
	_check(sb.has("progress_insight"), "strength includes progress_insight")

	var wb: Array = FactionDefinitionsScript.weakness_biases("debug_vasterviksjavlarna")
	_check(wb.has("logistics"), "weakness includes logistics")
	_check(wb.has("practical_conversion"), "weakness includes practical_conversion")
	_check(wb.has("production_efficiency"), "weakness includes production_efficiency")

	var vi: Dictionary = FactionDefinitionsScript.visual_identity("debug_vasterviksjavlarna")
	_check(vi is Dictionary, "visual_identity is Dictionary")
	_check(vi.has("palette") and vi.has("motifs") and vi.has("banner_direction"), "visual_identity keys")
	_check((vi["palette"] as Array) is Array, "visual_identity palette is Array")
	var pn: String = FactionDefinitionsScript.prototype_notes("debug_vasterviksjavlarna")
	_check(pn.length() > 0, "prototype_notes non-empty")

	# 6) Display-name spot checks
	_check(FactionDefinitionsScript.display_name("debug_malmofubikkarna") == "Malmöfubikkarna", "malmö display_name")
	_check(FactionDefinitionsScript.display_name("debug_pajasarna_fran_paris") == "Pajasarna från Paris", "pajasarna display_name")

	# 7) Profile / canon spot checks (all three)
	for id_str in expected_ids:
		_check(FactionDefinitionsScript.profile_type(id_str) == "debug_example", "profile_type debug_example for %s" % id_str)
		_check(FactionDefinitionsScript.canon_status(id_str) == "non_canonical", "canon_status non_canonical for %s" % id_str)

	# 8) Unknown helpers
	_check(FactionDefinitionsScript.get_definition("nope") == null, "get_definition nope null")
	_check(FactionDefinitionsScript.display_name("nope") == "", "display_name nope")
	_check(FactionDefinitionsScript.profile_type("nope") == "", "profile_type nope")
	_check(FactionDefinitionsScript.canon_status("nope") == "", "canon_status nope")
	_check(FactionDefinitionsScript.one_line_fantasy("nope") == "", "one_line_fantasy nope")
	_check(FactionDefinitionsScript.trait_ids("nope") == [], "trait_ids nope")
	_check(FactionDefinitionsScript.strength_biases("nope") == [], "strength_biases nope")
	_check(FactionDefinitionsScript.weakness_biases("nope") == [], "weakness_biases nope")
	_check(FactionDefinitionsScript.visual_identity("nope") == {}, "visual_identity nope")
	_check(FactionDefinitionsScript.prototype_notes("nope") == "", "prototype_notes nope")

	# 9) Deep-copy guarantee for get_definition
	var row: Dictionary = FactionDefinitionsScript.get_definition("debug_vasterviksjavlarna")
	_check(row != null and row is Dictionary, "get_definition row")
	row["display_name"] = "MUTATED"
	row["trait_ids"].append("mutated_trait")
	(row["visual_identity"] as Dictionary)["palette"].append("mutated_palette")
	var row2: Dictionary = FactionDefinitionsScript.get_definition("debug_vasterviksjavlarna")
	_check(row2["display_name"] == "Västerviksjävlarna", "row2 display_name intact")
	_check((row2["trait_ids"] as Array).size() == 5, "row2 trait_ids intact count")
	_check((row2["trait_ids"] as Array).has("mutated_trait") == false, "row2 trait_ids no mutation")
	_check(((row2["visual_identity"] as Dictionary)["palette"] as Array).size() == 3, "row2 palette intact count")

	# 10) Deep-copy for helpers
	var t_mut: Array = FactionDefinitionsScript.trait_ids("debug_vasterviksjavlarna")
	t_mut.append("x")
	var s_mut: Array = FactionDefinitionsScript.strength_biases("debug_vasterviksjavlarna")
	s_mut.append("x")
	var w_mut: Array = FactionDefinitionsScript.weakness_biases("debug_vasterviksjavlarna")
	w_mut.append("x")
	var vi_mut: Dictionary = FactionDefinitionsScript.visual_identity("debug_vasterviksjavlarna")
	(vi_mut["palette"] as Array).append("x")
	(vi_mut["motifs"] as Array).append("x")
	var traits2: Array = FactionDefinitionsScript.trait_ids("debug_vasterviksjavlarna")
	var sb2: Array = FactionDefinitionsScript.strength_biases("debug_vasterviksjavlarna")
	var wb2: Array = FactionDefinitionsScript.weakness_biases("debug_vasterviksjavlarna")
	var vi2: Dictionary = FactionDefinitionsScript.visual_identity("debug_vasterviksjavlarna")
	_check(traits2 == expected_traits, "trait_ids helper deep copy")
	_check(sb2 == ["science", "progress_insight"], "strength_biases helper deep copy")
	_check(wb2.size() == 3 and not wb2.has("x"), "weakness_biases helper deep copy")
	_check((vi2["palette"] as Array).size() == 3, "visual_identity palette deep copy")
	_check((vi2["motifs"] as Array).size() == 3, "visual_identity motifs deep copy")

	# 11) No unexpected keys
	var allowed: Array = [
		"id",
		"display_name",
		"profile_type",
		"canon_status",
		"one_line_fantasy",
		"trait_ids",
		"strength_biases",
		"weakness_biases",
		"visual_identity",
		"prototype_notes",
	]
	for id_str in expected_ids:
		var def: Dictionary = FactionDefinitionsScript.get_definition(id_str)
		_check(def.keys().size() == allowed.size(), "row key count %s" % id_str)
		for k in allowed:
			_check(def.has(k), "row has key %s %s" % [k, id_str])
		for k in def.keys():
			_check(allowed.has(k), "row has no extra key %s %s" % [String(k), id_str])

	# 12) Forward-reference policy: trait_ids are raw strings only
	for id_str in expected_ids:
		var t_raw: Array = FactionDefinitionsScript.trait_ids(id_str)
		for tid in t_raw:
			_check(tid is String, "trait_id is String for %s" % id_str)

	if _any_fail:
		call_deferred("quit", 1)
	else:
		print("PASS %d/%d" % [_total, _total])
		call_deferred("quit", 0)


func _check(cond, message) -> void:
	_total = _total + 1
	if cond:
		return
	_any_fail = true
	var line = "FAIL: %s" % message
	print(line)
	push_error(line)
