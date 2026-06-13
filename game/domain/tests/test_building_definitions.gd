# Headless: godot --headless --path game -s res://domain/tests/test_building_definitions.gd
extends SceneTree

const BuildingDefinitionsScript = preload("res://domain/content/building_definitions.gd")
const CityYieldsScript = preload("res://domain/city_yields.gd")
const CityScript = preload("res://domain/city.gd")
const HexMapScript = preload("res://domain/hex_map.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const UnitScript = preload("res://domain/unit.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	var y_hearth = BuildingDefinitionsScript.yield_effects(BuildingDefinitionsScript.BUILDING_ID_HEARTH)
	_check(int(y_hearth["production"]) == 1 and int(y_hearth["food"]) == 0, "registry hearth +1 production")

	var y_pw = BuildingDefinitionsScript.yield_effects(
		BuildingDefinitionsScript.BUILDING_ID_POTTERY_WORKSHOP
	)
	_check(int(y_pw["food"]) == 1 and int(y_pw["production"]) == 0, "registry pottery +1 food")

	var y_sl = BuildingDefinitionsScript.yield_effects(
		BuildingDefinitionsScript.BUILDING_ID_STOREHOUSE_LEDGER
	)
	_check(int(y_sl["coin"]) == 2 and int(y_sl["food"]) == 0, "registry storehouse ledger +2 coin")

	var y_sh = BuildingDefinitionsScript.yield_effects(BuildingDefinitionsScript.BUILDING_ID_STORAGE_HALL)
	_check(int(y_sh["food"]) == 1, "registry storage hall +1 food")

	var y_wh = BuildingDefinitionsScript.yield_effects(BuildingDefinitionsScript.BUILDING_ID_WEAVER_HUT)
	_check(int(y_wh["coin"]) == 2, "registry weaver hut +2 coin")

	var y_mh = BuildingDefinitionsScript.yield_effects(
		BuildingDefinitionsScript.BUILDING_ID_MUDBRICK_HOUSING
	)
	_check(int(y_mh["housing"]) == 2 and int(y_mh["food"]) == 0, "registry mudbrick housing +2 housing")

	var y_ah = BuildingDefinitionsScript.yield_effects(BuildingDefinitionsScript.BUILDING_ID_ARCHIVE_HUT)
	_check(int(y_ah["science"]) == 2, "registry archive hut +2 science")

	var y_ar = BuildingDefinitionsScript.yield_effects(BuildingDefinitionsScript.BUILDING_ID_ARMORY)
	_check(int(y_ar["production"]) == 1, "registry armory +1 production")

	var y_unk = BuildingDefinitionsScript.yield_effects("future_silo")
	_check(
		int(y_unk["food"]) == 0
			and int(y_unk["production"]) == 0
			and int(y_unk["science"]) == 0
			and int(y_unk["coin"]) == 0
			and int(y_unk["housing"]) == 0,
		"unknown building yields zero"
	)
	_check(not BuildingDefinitionsScript.has("future_silo"), "unknown not in registry")

	_check(
		CityYieldsScript.building_yield(BuildingDefinitionsScript.BUILDING_ID_HEARTH) == y_hearth,
		"CityYields delegates hearth to registry"
	)

	var m = HexMapScript.make_tiny_test_map()
	var u = [UnitScript.new(1, 0, HexCoordScript.new(0, 0), "warrior")]
	var center = HexCoordScript.new(1, -1)
	var c_both = CityScript.new(
		7,
		0,
		center,
		null,
		"",
		false,
		[
			BuildingDefinitionsScript.BUILDING_ID_HEARTH,
			BuildingDefinitionsScript.BUILDING_ID_POTTERY_WORKSHOP,
		]
	)
	var scen = ScenarioScript.new(m, u, [c_both], 10, 20, null)
	var y_base = CityYieldsScript.city_center_yield(m, c_both)
	var y_tot = CityYieldsScript.city_total_yield(scen, c_both)
	_check(
		CityYieldsScript.get_yield(y_tot, "food") == CityYieldsScript.get_yield(y_base, "food") + 1,
		"both buildings +1 food from pottery"
	)
	_check(
		CityYieldsScript.get_yield(y_tot, "production") == CityYieldsScript.get_yield(y_base, "production") + 1,
		"both buildings +1 production from hearth"
	)

	if _any_fail:
		call_deferred("quit", 1)
	else:
		print("PASS %d/%d" % [_total, _total])
		call_deferred("quit", 0)


func _check(cond: bool, message: String) -> void:
	_total += 1
	if cond:
		return
	_any_fail = true
	var line = "FAIL: %s" % message
	print(line)
	push_error(line)
