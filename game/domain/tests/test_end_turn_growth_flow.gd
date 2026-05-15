# Headless: godot --headless --path game -s res://domain/tests/test_end_turn_growth_flow.gd
extends SceneTree

const GameStateScript = preload("res://domain/game_state.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const HexMapScript = preload("res://domain/hex_map.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const UnitScript = preload("res://domain/unit.gd")
const CityScript = preload("res://domain/city.gd")
const EndTurnScript = preload("res://domain/actions/end_turn.gd")
const SetCityProductionScript = preload("res://domain/actions/set_city_production.gd")
const ProductionTickScript = preload("res://domain/production_tick.gd")
const FoodGrowthTickScript = preload("res://domain/food_growth_tick.gd")
const ProductionDeliveryScript = preload("res://domain/production_delivery.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	var m = HexMapScript.make_tiny_test_map()
	var us = [UnitScript.new(1, 0, HexCoordScript.new(0, 0), "warrior")]
	var own: Array = [HexCoordScript.new(0, 0), HexCoordScript.new(1, 0)]
	var city = CityScript.new(
		1,
		0,
		HexCoordScript.new(0, 0),
		null,
		"Cap",
		true,
		["palace"],
		own,
		1,
		[],
		0
	)
	var scen = ScenarioScript.new(m, us, [city], 10, 20, null)
	var gs = GameStateScript.new(scen)
	_check(gs.try_apply(SetCityProductionScript.make(0, 1, SetCityProductionScript.PROJECT_ID_PRODUCE_UNIT_WARRIOR))["accepted"], "production set")
	var before = gs.log.size()
	var er = gs.try_apply(EndTurnScript.make(0))
	_check(er["accepted"], "end turn")
	var slice: Array = []
	var i = before
	while i < gs.log.size():
		slice.append(str((gs.log.get_entry(i) as Dictionary).get("action_type", "")))
		i += 1
	var pi = slice.find(ProductionTickScript.EVENT_TYPE)
	var fi = slice.find(FoodGrowthTickScript.EVENT_TYPE_PROGRESS)
	var ei = slice.find(EndTurnScript.ACTION_TYPE)
	_check(pi >= 0, "production tick logged")
	_check(fi >= 0, "food growth logged")
	_check(ei >= 0, "end_turn logged")
	_check(pi < fi, "production before food")
	_check(fi < ei, "food before end_turn")
	var deli = slice.find(ProductionDeliveryScript.EVENT_TYPE)
	if deli >= 0:
		_check(ei < deli, "delivery after end_turn")

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
