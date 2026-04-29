# Headless: godot --headless --path game -s res://domain/tests/test_unit_definitions.gd
extends SceneTree

const UnitDefinitionsScript = preload("res://domain/content/unit_definitions.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	_check(UnitDefinitionsScript.has("settler"), "has settler")
	_check(UnitDefinitionsScript.has("warrior"), "has warrior")
	_check(not UnitDefinitionsScript.has("worker"), "no worker")

	var ds = UnitDefinitionsScript.get_definition("settler") as Dictionary
	_check(ds["id"] == "settler", "settler id")
	_check(ds["display_name"] == "Settler", "settler display_name")
	_check(bool(ds["can_found_city"]), "settler can_found_city")
	_check(int(ds["production_cost"]) == 2, "settler production_cost")
	_check(ds["role"] == "founder", "settler role")

	var dw = UnitDefinitionsScript.get_definition("warrior") as Dictionary
	_check(not bool(dw["can_found_city"]), "warrior can_found_city")
	_check(dw["role"] == "basic_melee", "warrior role")

	_check(UnitDefinitionsScript.get_definition("nope") == null, "unknown null")

	var dup1 = UnitDefinitionsScript.get_definition("settler") as Dictionary
	dup1["display_name"] = "mutated"
	var dup2 = UnitDefinitionsScript.get_definition("settler") as Dictionary
	_check(dup2["display_name"] == "Settler", "deep dup independent")

	var ids0 = UnitDefinitionsScript.ids() as Array
	_check(ids0.size() == 2 and ids0[0] == "settler" and ids0[1] == "warrior", "ids order")

	ids0.append("bogus")
	var ids1 = UnitDefinitionsScript.ids() as Array
	_check(
		ids1.size() == 2 and ids1[0] == "settler" and ids1[1] == "warrior",
		"ids duplicate safe"
	)

	_check(UnitDefinitionsScript.can_found_city("settler"), "can_found settler")
	_check(not UnitDefinitionsScript.can_found_city("warrior"), "cannot_found warrior")
	_check(not UnitDefinitionsScript.can_found_city("nope"), "cannot_found unknown")

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
