# Headless: godot --headless --path game -s res://domain/tests/test_city_project_definitions.gd
extends SceneTree

const CityProjectDefinitionsScript = preload("res://domain/content/city_project_definitions.gd")
const UnitDefinitionsScript = preload("res://domain/content/unit_definitions.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	_check(CityProjectDefinitionsScript.has("produce_unit:warrior"), "has warrior project")
	_check(not CityProjectDefinitionsScript.has("produce_unit:settler"), "no settler project")
	_check(not CityProjectDefinitionsScript.has("none"), "has none false")

	var ids0 = CityProjectDefinitionsScript.ids() as Array
	_check(
		ids0.size() == 1 and str(ids0[0]) == "produce_unit:warrior",
		"ids single warrior"
	)
	ids0.append("bogus")
	var ids1 = CityProjectDefinitionsScript.ids() as Array
	_check(
		ids1.size() == 1 and str(ids1[0]) == "produce_unit:warrior",
		"ids duplicate safe"
	)

	var d = CityProjectDefinitionsScript.get_definition("produce_unit:warrior") as Dictionary
	_check(d["id"] == "produce_unit:warrior", "def id")
	_check(d["display_name"] == "Train Warrior", "def display_name")
	_check(d["project_type"] == "produce_unit", "def project_type")
	_check(d["produces_unit_type"] == "warrior", "def produces_unit_type")
	_check(int(d["cost"]) == 2, "def cost")
	_check(d["role"] == "basic_unit_training", "def role")

	_check(CityProjectDefinitionsScript.get_definition("nope") == null, "unknown null")

	var m0 = CityProjectDefinitionsScript.get_definition("produce_unit:warrior") as Dictionary
	m0["cost"] = 999
	var m1 = CityProjectDefinitionsScript.get_definition("produce_unit:warrior") as Dictionary
	_check(int(m1["cost"]) == 2, "get_definition deep copy")

	_check(CityProjectDefinitionsScript.project_type("produce_unit:warrior") == "produce_unit", "project_type ok")
	_check(CityProjectDefinitionsScript.project_type("nope") == "", "project_type unknown")

	_check(CityProjectDefinitionsScript.cost("produce_unit:warrior") == 2, "cost ok")
	_check(CityProjectDefinitionsScript.cost("nope") == 0, "cost unknown")

	_check(CityProjectDefinitionsScript.produces_unit_type("produce_unit:warrior") == "warrior", "produces ok")
	_check(CityProjectDefinitionsScript.produces_unit_type("nope") == "", "produces unknown")

	_check(CityProjectDefinitionsScript.is_supported_project_id("produce_unit:warrior"), "supported warrior")
	_check(not CityProjectDefinitionsScript.is_supported_project_id("none"), "none not supported id")
	_check(not CityProjectDefinitionsScript.is_supported_project_id("nope"), "unknown not supported")

	_check(
		UnitDefinitionsScript.has(CityProjectDefinitionsScript.produces_unit_type("produce_unit:warrior")),
		"produces_unit_type in UnitDefinitions"
	)

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
