# Headless: godot --headless --path game -s res://domain/tests/test_progress_definitions.gd
extends SceneTree

const ProgressDefinitionsScript = preload("res://domain/content/progress_definitions.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	_check(ProgressDefinitionsScript.has("foraging_systems"), "has foraging_systems")
	_check(ProgressDefinitionsScript.has("stone_tools"), "has stone_tools")
	_check(ProgressDefinitionsScript.has("controlled_fire"), "has controlled_fire")
	_check(ProgressDefinitionsScript.has("oral_surveying"), "has oral_surveying")
	_check(ProgressDefinitionsScript.has("animal_tracking"), "has animal_tracking")
	_check(not ProgressDefinitionsScript.has("rail_logistics"), "no rail_logistics")

	var exp_ids = [
		"foraging_systems",
		"stone_tools",
		"controlled_fire",
		"oral_surveying",
		"animal_tracking",
	]
	var ids0 = ProgressDefinitionsScript.ids() as Array
	_check(ids0.size() == 5, "ids size")
	var ii = 0
	while ii < 5:
		_check(str(ids0[ii]) == exp_ids[ii], "ids order %d" % ii)
		ii = ii + 1
	ids0.append("bogus")
	var ids1 = ProgressDefinitionsScript.ids() as Array
	_check(ids1.size() == 5, "ids duplicate safe size")
	var jj = 0
	while jj < 5:
		_check(str(ids1[jj]) == exp_ids[jj], "ids duplicate safe %d" % jj)
		jj = jj + 1

	var d = ProgressDefinitionsScript.get_definition("foraging_systems") as Dictionary
	_check(d["id"] == "foraging_systems", "def id")
	_check(d["display_name"] == "Foraging Systems", "def display_name")
	_check(d["category"] == "science", "def category")
	_check(d["era_bucket"] == "ancient_foundations", "def era_bucket")
	_check(d["role"] == "early_food_scouting_survival", "def role")
	_check(
		d["description"] == "Early food gathering, camps, and simple survival practices.",
		"def description"
	)
	var cu = d["concrete_unlocks"] as Array
	var se = d["systemic_effects"] as Array
	var fd = d["future_dependencies"] as Array
	_check(cu.size() == 2 and se.size() == 2 and fd.size() == 2, "def array sizes")
	_check((cu[0] as Dictionary)["target_type"] == "building", "cu0 type")
	_check((cu[0] as Dictionary)["target_id"] == "scout_camp", "cu0 id")
	_check((cu[1] as Dictionary)["target_type"] == "specialist", "cu1 type")
	_check((cu[1] as Dictionary)["target_id"] == "forager", "cu1 id")
	_check((se[0] as Dictionary)["target_id"] == "forest_food_bonus", "se0 id")
	_check((fd[0] as Dictionary)["target_id"] == "survival_knowledge", "fd0 id")

	_check(ProgressDefinitionsScript.get_definition("nope") == null, "unknown null")

	var m0 = ProgressDefinitionsScript.get_definition("foraging_systems") as Dictionary
	m0["display_name"] = "X"
	var m1 = ProgressDefinitionsScript.get_definition("foraging_systems") as Dictionary
	_check(m1["display_name"] == "Foraging Systems", "get_definition deep copy")

	_check(ProgressDefinitionsScript.category("foraging_systems") == "science", "category ok")
	_check(ProgressDefinitionsScript.era_bucket("foraging_systems") == "ancient_foundations", "era ok")
	_check(ProgressDefinitionsScript.category("nope") == "", "category unknown")
	_check(ProgressDefinitionsScript.era_bucket("nope") == "", "era unknown")

	var cu_f = ProgressDefinitionsScript.concrete_unlocks("foraging_systems") as Array
	_check(cu_f.size() == 2, "concrete_unlocks size")
	_check((cu_f[0] as Dictionary)["target_type"] == "building", "concrete_unlocks sample type")
	_check((cu_f[0] as Dictionary)["target_id"] == "scout_camp", "concrete_unlocks sample id")
	var se_f = ProgressDefinitionsScript.systemic_effects("foraging_systems") as Array
	_check(se_f.size() == 2, "systemic_effects size")
	_check((se_f[1] as Dictionary)["target_id"] == "outside_borders_healing", "systemic sample id")
	var fd_f = ProgressDefinitionsScript.future_dependencies("foraging_systems") as Array
	_check(fd_f.size() == 2, "future_dependencies size")
	_check((fd_f[1] as Dictionary)["target_id"] == "woodland_logistics", "future sample id")

	_check((ProgressDefinitionsScript.concrete_unlocks("nope") as Array).size() == 0, "concrete nope")
	_check((ProgressDefinitionsScript.systemic_effects("nope") as Array).size() == 0, "systemic nope")
	_check((ProgressDefinitionsScript.future_dependencies("nope") as Array).size() == 0, "future nope")

	var cu_mut = ProgressDefinitionsScript.concrete_unlocks("foraging_systems") as Array
	cu_mut.append({"target_type": "x", "target_id": "y"})
	var cu_mut0 = cu_mut[0] as Dictionary
	cu_mut0["target_id"] = "corrupted"
	var cu_after = ProgressDefinitionsScript.concrete_unlocks("foraging_systems") as Array
	_check(cu_after.size() == 2, "concrete_unlocks mutate size restored")
	_check((cu_after[0] as Dictionary)["target_id"] == "scout_camp", "concrete_unlocks inner intact")

	var se_mut = ProgressDefinitionsScript.systemic_effects("foraging_systems") as Array
	se_mut.append({"target_type": "m", "target_id": "bogus_mod"})
	var se_mut0 = se_mut[0] as Dictionary
	se_mut0["target_id"] = "corrupted_mod"
	var se_after = ProgressDefinitionsScript.systemic_effects("foraging_systems") as Array
	_check(se_after.size() == 2, "systemic_mut size restored")
	_check((se_after[0] as Dictionary)["target_id"] == "forest_food_bonus", "systemic inner intact")

	var fd_mut = ProgressDefinitionsScript.future_dependencies("foraging_systems") as Array
	fd_mut.append({"target_type": "science", "target_id": "bogus_sci"})
	var fd_mut0 = fd_mut[0] as Dictionary
	fd_mut0["target_id"] = "corrupted_sci"
	var fd_after = ProgressDefinitionsScript.future_dependencies("foraging_systems") as Array
	_check(fd_after.size() == 2, "future_mut size restored")
	_check((fd_after[0] as Dictionary)["target_id"] == "survival_knowledge", "future inner intact")

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
