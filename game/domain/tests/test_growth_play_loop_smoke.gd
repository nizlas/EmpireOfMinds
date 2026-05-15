# Headless: godot --headless --path game -s res://domain/tests/test_growth_play_loop_smoke.gd
# Phase 5.1.19c — prototype-map growth/play loop smoke (no rule changes; GameState.try_apply only).
extends SceneTree

const GameStateScript = preload("res://domain/game_state.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const FoundCityScript = preload("res://domain/actions/found_city.gd")
const SetCityProductionScript = preload("res://domain/actions/set_city_production.gd")
const SetCityWorkedTilesScript = preload("res://domain/actions/set_city_worked_tiles.gd")
const EndTurnScript = preload("res://domain/actions/end_turn.gd")
const MoveUnitScript = preload("res://domain/actions/move_unit.gd")
const ProductionTickScript = preload("res://domain/production_tick.gd")
const ProductionDeliveryScript = preload("res://domain/production_delivery.gd")
const FoodGrowthTickScript = preload("res://domain/food_growth_tick.gd")
const CityYieldsScript = preload("res://domain/city_yields.gd")
const MovementRulesScript = preload("res://domain/movement_rules.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")

var _total = 0
var _any_fail = false


func _hex_dist(q1: int, r1: int, q2: int, r2: int) -> int:
	return (abs(q1 - q2) + abs(r1 - r2) + abs(q1 + r1 - q2 - r2)) / 2


func _raw_nonzero(raw: Dictionary) -> bool:
	return (
		CityYieldsScript.get_yield(raw, "food") != 0
		or CityYieldsScript.get_yield(raw, "production") != 0
		or CityYieldsScript.get_yield(raw, "science") != 0
		or CityYieldsScript.get_yield(raw, "coin") != 0
	)


func _is_science_type(t: String) -> bool:
	return t == "science_progress" or t == "science_completed" or t == "science_bonus" or t == "science_no_target"


func _check_end_turn_pipeline_slice(gs, log_before: int, message: String) -> void:
	var n = gs.log.size()
	var types: Array = []
	var i = log_before
	while i < n:
		types.append(str((gs.log.get_entry(i) as Dictionary).get("action_type", "")))
		i += 1
	var first_end: int = -1
	var first_del: int = -1
	var last_prod: int = -1
	var first_food: int = -1
	var last_food: int = -1
	var ti = 0
	while ti < types.size():
		var t: String = types[ti] as String
		if t == EndTurnScript.ACTION_TYPE and first_end < 0:
			first_end = ti
		if t == ProductionDeliveryScript.EVENT_TYPE and first_del < 0:
			first_del = ti
		if t == ProductionTickScript.EVENT_TYPE:
			last_prod = ti
		if t == FoodGrowthTickScript.EVENT_TYPE_PROGRESS:
			if first_food < 0:
				first_food = ti
			last_food = ti
		ti += 1
	if first_end >= 0 and first_del >= 0:
		_check(first_end < first_del, "%s: end_turn before delivery" % message)
	if last_prod >= 0 and first_food >= 0:
		_check(last_prod < first_food, "%s: production before food_growth" % message)
	if first_food >= 0 and first_end >= 0:
		_check(last_food < first_end, "%s: food_growth before end_turn" % message)
	var si = 0
	while si < types.size():
		if _is_science_type(types[si] as String):
			if first_food >= 0 and first_end >= 0:
				_check(si > last_food and si < first_end, "%s: science between food and end_turn" % message)
		si += 1


func _apply_end_turn(gs, player_id: int, pipeline_label: String) -> bool:
	var log_before = gs.log.size()
	var r = gs.try_apply(EndTurnScript.make(player_id))
	if not bool(r.get("accepted", false)):
		return false
	_check(gs.log.size() > log_before, "%s: log grows after EndTurn P%d" % [pipeline_label, player_id])
	_check_end_turn_pipeline_slice(gs, log_before, pipeline_label)
	return true


func _full_round(gs, label: String) -> bool:
	if not _apply_end_turn(gs, 0, label):
		return false
	return _apply_end_turn(gs, 1, label)


func _slice_has_unit_produced(gs, log_before: int, city_id: int) -> bool:
	var i = log_before
	while i < gs.log.size():
		var e = gs.log.get_entry(i) as Dictionary
		if (
			str(e.get("action_type", "")) == ProductionDeliveryScript.EVENT_TYPE
			and int(e.get("city_id", -1)) == city_id
		):
			return true
		i += 1
	return false


func _move_unit_toward(gs, actor: int, unit_id: int, target_q: int, target_r: int, max_steps: int) -> void:
	var step = 0
	while step < max_steps:
		var u = gs.scenario.unit_by_id(unit_id)
		if u == null:
			return
		if u.position.q == target_q and u.position.r == target_r:
			return
		var legals: Array = MovementRulesScript.legal_destinations(gs.scenario, unit_id)
		if legals.is_empty():
			return
		var best = legals[0]
		var bd = _hex_dist(best.q, best.r, target_q, target_r)
		var li = 1
		while li < legals.size():
			var h = legals[li]
			var d = _hex_dist(h.q, h.r, target_q, target_r)
			if d < bd:
				bd = d
				best = h
			li += 1
		var r_m = gs.try_apply(
			MoveUnitScript.make(actor, unit_id, u.position.q, u.position.r, best.q, best.r)
		)
		_check(bool(r_m.get("accepted", false)), "move step toward (%d,%d) for unit %d" % [target_q, target_r, unit_id])
		step += 1


func _try_found_city_at_candidates(gs, unit_id: int, candidates: Array) -> bool:
	var ci = 0
	while ci < candidates.size():
		var pair = candidates[ci] as Array
		var fq: int = int(pair[0])
		var fr: int = int(pair[1])
		var r_fc = gs.try_apply(FoundCityScript.make(0, unit_id, fq, fr))
		if bool(r_fc.get("accepted", false)):
			return true
		ci += 1
	return false


func _run_manual_worked_probe() -> void:
	var gs = GameStateScript.new(ScenarioScript.make_prototype_play_scenario())
	var city_id = int(gs.scenario.peek_next_city_id())
	_check(gs.try_apply(FoundCityScript.make(0, 1, 0, 0))["accepted"], "probe: found capital")
	var cap = gs.scenario.city_by_id(city_id)
	_check(cap != null, "probe: capital exists")
	var brk: Dictionary = CityYieldsScript.yield_breakdown_for_city(gs.scenario, cap)
	var wt: Array = brk.get("worked_tiles", []) as Array
	_check(not wt.is_empty(), "probe: auto worked_tiles non-empty at pop 1")
	var auto_h = wt[0]
	_check(auto_h != null and auto_h is HexCoord, "probe: first worked tile HexCoord")
	var aq: int = int((auto_h as HexCoord).q)
	var ar: int = int((auto_h as HexCoord).r)
	var food_before: int = CityYieldsScript.get_yield(CityYieldsScript.city_total_yield(gs.scenario, cap), "food")
	var alt: Array = [-1, -1]
	var oi = 0
	while oi < cap.owned_tiles.size():
		var oh = cap.owned_tiles[oi]
		oi += 1
		if oh == null:
			continue
		if oh.q == cap.position.q and oh.r == cap.position.r:
			continue
		if oh.q == aq and oh.r == ar:
			continue
		var rw: Dictionary = CityYieldsScript.raw_terrain_yield(gs.scenario.map, oh)
		if not _raw_nonzero(rw):
			continue
		alt = [oh.q, oh.r]
		break
	if int(alt[0]) < 0:
		print("PROBE NOTE: no alternate eligible owned worked tile; auto vs manual equality case by map geometry.")
		_check(true, "probe: skip manual differing tile — documented equality case")
		return
	var r_s = gs.try_apply(SetCityWorkedTilesScript.make(0, city_id, [alt]))
	_check(bool(r_s["accepted"]), "probe: set_city_worked_tiles accepted")
	cap = gs.scenario.city_by_id(city_id)
	var food_after: int = CityYieldsScript.get_yield(CityYieldsScript.city_total_yield(gs.scenario, cap), "food")
	_check(food_after != food_before, "probe: manual tile differs from auto -> total food changes (%d vs %d)" % [food_before, food_after])


func _init() -> void:
	var gs = GameStateScript.new(ScenarioScript.make_prototype_play_scenario())
	var capital_id = int(gs.scenario.peek_next_city_id())
	# Found city + baseline
	_check(gs.try_apply(FoundCityScript.make(0, 1, 0, 0))["accepted"], "found capital at settler start")
	var cap0 = gs.scenario.city_by_id(capital_id)
	_check(cap0 != null and cap0.population >= 1 and cap0.food_stored >= 0, "capital pop/food_stored baseline")

	_check(
		gs.try_apply(SetCityProductionScript.make(0, capital_id, SetCityProductionScript.PROJECT_ID_PRODUCE_UNIT_WARRIOR))[
			"accepted"
		],
		"set warrior production"
	)
	var warrior_deliver_round = 0
	var got_warrior = false
	while warrior_deliver_round < 25:
		var lb = gs.log.size()
		_check(_full_round(gs, "warrior phase"), "warrior phase full round")
		if _slice_has_unit_produced(gs, lb, capital_id):
			got_warrior = true
			break
		warrior_deliver_round += 1
	_check(got_warrior, "warrior unit_produced within inclusive bound (25 rounds)")

	var war_uid = -1
	var ulist = gs.scenario.units()
	var ui = 0
	while ui < ulist.size():
		var uu = ulist[ui]
		if uu.owner_id == 0 and str(uu.type_id) == "warrior" and uu.position.equals(HexCoordScript.new(0, 0)):
			war_uid = uu.id
		ui += 1
	_check(war_uid >= 0, "warrior on capital hex for offload")

	_move_unit_toward(gs, 0, war_uid, 5, 5, 24)

	_check(
		gs.try_apply(
			SetCityProductionScript.make(0, capital_id, SetCityProductionScript.PROJECT_ID_PRODUCE_UNIT_SETTLER)
		)["accepted"],
		"set settler production"
	)
	var settler_deliver_round = 0
	var got_settler = false
	while settler_deliver_round < 25:
		var lb2 = gs.log.size()
		_check(_full_round(gs, "settler phase"), "settler phase full round")
		if _slice_has_unit_produced(gs, lb2, capital_id):
			got_settler = true
			break
		settler_deliver_round += 1
	_check(got_settler, "settler unit_produced within inclusive bound (25 rounds)")

	var settler_uid = -1
	var ulist2 = gs.scenario.units()
	var uj = 0
	while uj < ulist2.size():
		var uv = ulist2[uj]
		if uv.owner_id == 0 and str(uv.type_id) == "settler":
			settler_uid = uv.id
			break
		uj += 1
	_check(settler_uid >= 0, "located P0 settler unit id")

	var tgt_q = -1
	var tgt_r = 3
	var cands: Array = []
	var oa = 0
	while oa < 7:
		var dq = 0
		var dr = 0
		match oa:
			0:
				dq = -1
				dr = 3
			1:
				dq = 0
				dr = 3
			2:
				dq = -1
				dr = 2
			3:
				dq = -2
				dr = 4
			4:
				dq = -1
				dr = 4
			5:
				dq = 0
				dr = 2
			6:
				dq = 1
				dr = 2
		cands.append([dq, dr])
		oa += 1

	_move_unit_toward(gs, 0, settler_uid, tgt_q, tgt_r, 80)
	var su = gs.scenario.unit_by_id(settler_uid)
	_check(su != null, "settler still exists before found")
	var found_second = _try_found_city_at_candidates(gs, settler_uid, cands)
	_check(found_second, "second FoundCity accepted for P0")
	_check(gs.scenario.cities_owned_by(0).size() == 2, "P0 owns two cities")

	var second_id = -1
	var cities = gs.scenario.cities()
	var ck = 0
	while ck < cities.size():
		var cc = cities[ck]
		if cc.owner_id == 0 and cc.id != capital_id:
			second_id = cc.id
		ck += 1
	_check(second_id >= 0, "resolved second city id")

	var growth_round = 0
	var cap_grew = false
	var second_food_ev = false
	while growth_round < 35:
		var lb3 = gs.log.size()
		_check(_full_round(gs, "growth phase"), "growth phase full round")
		var j = lb3
		while j < gs.log.size():
			var e2 = gs.log.get_entry(j) as Dictionary
			var at2 = str(e2.get("action_type", ""))
			if at2 == FoodGrowthTickScript.EVENT_TYPE_GREW and int(e2.get("city_id", -1)) == capital_id:
				cap_grew = true
			if at2 == FoodGrowthTickScript.EVENT_TYPE_PROGRESS and int(e2.get("city_id", -1)) == second_id:
				if int(e2.get("surplus", 0)) >= 1:
					second_food_ev = true
			j += 1
		if cap_grew and second_food_ev:
			break
		growth_round += 1
	_check(cap_grew, "capital grew (city_grew) within inclusive bound (~35 rounds)")
	var cap_fin = gs.scenario.city_by_id(capital_id)
	_check(cap_fin != null and cap_fin.population >= 2, "capital population >= 2")
	_check(second_food_ev, "second city food_growth_progress surplus>=1 in window")

	_run_manual_worked_probe()

	if _any_fail:
		call_deferred("quit", 1)
	else:
		print("PASS %d/%d" % [_total, _total])
		call_deferred("quit", 0)


func _check(cond, message) -> void:
	_total += 1
	if cond:
		return
	var line = "FAIL: %s" % message
	_any_fail = true
	print(line)
	push_error(line)
