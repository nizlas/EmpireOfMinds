# Headless: godot --headless --path game -s res://domain/tests/test_city_population.gd
extends SceneTree

const CityScript = preload("res://domain/city.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const HexMapScript = preload("res://domain/hex_map.gd")
const UnitScript = preload("res://domain/unit.gd")
const GameStateScript = preload("res://domain/game_state.gd")
const FoundCityScript = preload("res://domain/actions/found_city.gd")
const SetCityProductionScript = preload("res://domain/actions/set_city_production.gd")
const ProductionTickScript = preload("res://domain/production_tick.gd")
const ProductionDeliveryScript = preload("res://domain/production_delivery.gd")

var _total = 0
var _any_fail = false


func _proj_progress(p: int, cost: int) -> Dictionary:
	var d: Dictionary = {}
	d["project_type"] = "produce_unit"
	d["progress"] = p
	d["cost"] = cost
	d["ready"] = false
	return d


func _proj_ready(p: int, cost: int) -> Dictionary:
	var d: Dictionary = {}
	d["project_type"] = "produce_unit"
	d["progress"] = p
	d["cost"] = cost
	d["ready"] = true
	return d


func _init() -> void:
	var pos = HexCoordScript.new(1, -2)
	_check(CityScript.new(70, 0, pos).population == 1, "default population is 1")

	var c_explicit = CityScript.new(71, 0, pos, null, "", false, null, null, 14)
	_check(c_explicit.population == 14, "explicit population preserved")

	var c_clamp = CityScript.new(72, 0, pos, null, "", false, null, null, -9)
	_check(c_clamp.population == 0, "negative population clamps to zero")

	var pm = HexMapScript.make_prototype_play_map()
	var us_fc = [
		UnitScript.new(1, 0, HexCoordScript.new(0, 0), "settler"),
		UnitScript.new(2, 0, HexCoordScript.new(1, 0), "warrior"),
	]
	var gs_fc = GameStateScript.new(ScenarioScript.new(pm, us_fc))
	var cid_fc = gs_fc.scenario.peek_next_city_id()
	_check(gs_fc.try_apply(FoundCityScript.make(0, 1, 0, 0))["accepted"], "found city for population")
	var founded = gs_fc.scenario.city_by_id(cid_fc)
	_check(founded != null and founded.population == 1, "found city population is 1")

	var m_t = HexMapScript.make_tiny_test_map()
	var center_k = HexCoordScript.new(1, -1)
	var owned_sp: Array = [center_k]
	var c_sp = CityScript.new(
		80,
		0,
		center_k,
		null,
		"",
		true,
		["palace"],
		owned_sp,
		11
	)
	var sc_sp = ScenarioScript.new(m_t, [], [c_sp], 50, 81)
	var gs_sp = GameStateScript.new(sc_sp)
	_check(
		gs_sp.try_apply(
			SetCityProductionScript.make(0, 80, SetCityProductionScript.PROJECT_ID_PRODUCE_UNIT_WARRIOR)
		)["accepted"],
		"set production accepts"
	)
	_check(gs_sp.scenario.city_by_id(80).population == 11, "SetCityProduction preserves population")

	var c_tick = CityScript.new(
		81,
		0,
		center_k,
		_proj_progress(0, 5),
		"",
		false,
		[],
		owned_sp,
		6
	)
	var sc_tick = ScenarioScript.new(m_t, [], [c_tick], 51, 82)
	var pack_tick = ProductionTickScript.apply_for_player(sc_tick, 0)
	var after_tick = pack_tick["scenario"].city_by_id(81)
	_check(after_tick != null and after_tick.population == 6, "ProductionTick preserves population")

	var c_del = CityScript.new(82, 0, center_k, _proj_ready(2, 2), "", false, [], owned_sp, 3)
	var sc_del = ScenarioScript.new(m_t, [UnitScript.new(1, 0, HexCoordScript.new(0, 0))], [c_del], 90, 83)
	var pack_del = ProductionDeliveryScript.deliver_pending_for_player(sc_del, 0)
	var after_del = pack_del["scenario"].city_by_id(82)
	_check(after_del != null and after_del.population == 3, "ProductionDelivery preserves population")

	if _any_fail:
		call_deferred("quit", 1)
	else:
		print("PASS %d/%d" % [_total, _total])
		call_deferred("quit", 0)


func _check(cond, message) -> void:
	_total += 1
	if cond:
		return
	_any_fail = true
	var line = "FAIL: %s" % message
	print(line)
	push_error(line)
