# Headless: godot --headless --path game -s res://domain/tests/test_legal_actions.gd
extends SceneTree

# Minimal shell: LegalActions only reads scenario + turn_state. Use when GameState._init
# would run ProductionDelivery and change the scenario (e.g. ready produce_unit).
class _LegalActionsTestGameStateShell:
	extends RefCounted
	var scenario
	var turn_state
	var progress_state = null

	func _init(p_scenario, p_turn_state) -> void:
		scenario = p_scenario
		turn_state = p_turn_state


const LegalActionsScript = preload("res://domain/legal_actions.gd")
const GameStateScript = preload("res://domain/game_state.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const TurnStateScript = preload("res://domain/turn_state.gd")
const HexMapScript = preload("res://domain/hex_map.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const UnitScript = preload("res://domain/unit.gd")
const CityScript = preload("res://domain/city.gd")
const MoveUnitScript = preload("res://domain/actions/move_unit.gd")
const EndTurnScript = preload("res://domain/actions/end_turn.gd")
const FoundCityScript = preload("res://domain/actions/found_city.gd")
const SetCityProductionScript = preload("res://domain/actions/set_city_production.gd")

var _total = 0
var _any_fail = false


func _check_list_segments_no_engine(L: Array) -> void:
	var n = L.size()
	_check(n > 0, "nonempty")
	var last = L[n - 1] as Dictionary
	_check(last["action_type"] == EndTurnScript.ACTION_TYPE, "last EndTurn")
	var i = 0
	while i < n - 1:
		var at = (L[i] as Dictionary)["action_type"]
		_check(at != "production_progress", "no engine progress")
		_check(at != "unit_produced", "no engine unit_produced")
		i = i + 1
	i = 0
	while i < n - 1 and (L[i] as Dictionary)["action_type"] == MoveUnitScript.ACTION_TYPE:
		i = i + 1
	while i < n - 1 and (L[i] as Dictionary)["action_type"] == FoundCityScript.ACTION_TYPE:
		i = i + 1
	while i < n - 1 and (L[i] as Dictionary)["action_type"] == SetCityProductionScript.ACTION_TYPE:
		i = i + 1
	_check(i == n - 1, "ordered moves fc sp then only end")


func _init() -> void:
	var empty = LegalActionsScript.for_current_player(null)
	_check(empty.size() == 0, "null game_state empty list")

	var gs = GameStateScript.make_tiny_test_state()
	var L = LegalActionsScript.for_current_player(gs)
	_check_list_segments_no_engine(L)
	_check(L[L.size() - 1]["actor_id"] == 0, "EndTurn actor 0")
	var li = 0
	while li < L.size():
		_check((L[li] as Dictionary)["actor_id"] == 0, "p0 actor")
		li = li + 1
	var nm = 0
	var nf = 0
	var ns = 0
	var lj = 0
	while lj < L.size() - 1:
		var e = L[lj] as Dictionary
		var at = e["action_type"]
		if at == MoveUnitScript.ACTION_TYPE:
			nm = nm + 1
			var vr = MoveUnitScript.validate(gs.scenario, e)
			_check(vr["ok"], "move validates")
		elif at == FoundCityScript.ACTION_TYPE:
			nf = nf + 1
			var fr = FoundCityScript.validate(gs.scenario, e)
			_check(fr["ok"], "found validates")
		elif at == SetCityProductionScript.ACTION_TYPE:
			ns = ns + 1
		lj = lj + 1
	_check(nm > 0, "at least one move")
	_check(nf == 1, "one FoundCity for settler u1")
	_check(ns == 0, "no city yet no SetCityProduction")
	var first = L[0] as Dictionary
	_check(first["unit_id"] == 1, "first move unit 1")

	var m_solo_s = HexMapScript.make_tiny_test_map()
	var u_solo_s = [UnitScript.new(9, 0, HexCoordScript.new(0, 0), "settler")]
	var sc_solo_s = ScenarioScript.new(m_solo_s, u_solo_s, [], 20, 30)
	var gs_solo_s = GameStateScript.new(sc_solo_s)
	var Ls = LegalActionsScript.for_current_player(gs_solo_s)
	var nf_s = 0
	var ls = 0
	while ls < Ls.size() - 1:
		if (Ls[ls] as Dictionary)["action_type"] == FoundCityScript.ACTION_TYPE:
			nf_s = nf_s + 1
		ls = ls + 1
	_check(nf_s == 1, "single settler one FoundCity")

	var m_solo_w = HexMapScript.make_tiny_test_map()
	var u_solo_w = [UnitScript.new(8, 0, HexCoordScript.new(0, 0), "warrior")]
	var sc_solo_w = ScenarioScript.new(m_solo_w, u_solo_w, [], 20, 30)
	var gs_solo_w = GameStateScript.new(sc_solo_w)
	var Lw1 = LegalActionsScript.for_current_player(gs_solo_w)
	var nf_w = 0
	var lw1 = 0
	while lw1 < Lw1.size() - 1:
		if (Lw1[lw1] as Dictionary)["action_type"] == FoundCityScript.ACTION_TYPE:
			nf_w = nf_w + 1
		lw1 = lw1 + 1
	_check(nf_w == 0, "warrior alone no FoundCity")

	var m_c = HexMapScript.make_tiny_test_map()
	var u_c = [UnitScript.new(1, 0, HexCoordScript.new(0, 0))]
	var city_n = CityScript.new(5, 0, HexCoordScript.new(1, -1), null)
	var sc_c = ScenarioScript.new(m_c, u_c, [city_n], 10, 20)
	var gs_c = GameStateScript.new(sc_c)
	var Lc = LegalActionsScript.for_current_player(gs_c)
	_check_list_segments_no_engine(Lc)
	var saw_sp = false
	var lk = 0
	while lk < Lc.size() - 1:
		if (Lc[lk] as Dictionary)["action_type"] == SetCityProductionScript.ACTION_TYPE:
			saw_sp = true
			var se = Lc[lk] as Dictionary
			_check(se["city_id"] == 5, "set city 5")
			_check(
				se["project_id"] == SetCityProductionScript.PROJECT_ID_PRODUCE_UNIT_WARRIOR,
				"set project_id"
			)
			_check(not se.has("project_type"), "no project_type on action")
			var sr = SetCityProductionScript.validate(gs_c.scenario, se)
			_check(sr["ok"], "set validates")
		lk = lk + 1
	_check(saw_sp, "SetCityProduction when city empty project")

	var m_pr = HexMapScript.make_tiny_test_map()
	var u_pr = [UnitScript.new(1, 0, HexCoordScript.new(0, 0))]
	var d_pr: Dictionary = {}
	d_pr["project_type"] = "produce_unit"
	d_pr["progress"] = 0
	d_pr["cost"] = 2
	d_pr["ready"] = false
	var city_pr = CityScript.new(3, 0, HexCoordScript.new(0, -1), d_pr)
	var sc_pr = ScenarioScript.new(m_pr, u_pr, [city_pr], 11, 21)
	var gs_pr = GameStateScript.new(sc_pr)
	var Lpr = LegalActionsScript.for_current_player(gs_pr)
	var has_sp_pr = false
	var lp = 0
	while lp < Lpr.size() - 1:
		if (Lpr[lp] as Dictionary)["action_type"] == SetCityProductionScript.ACTION_TYPE:
			has_sp_pr = true
		lp = lp + 1
	_check(not has_sp_pr, "no SetCityProduction when project set")

	var m_rd = HexMapScript.make_tiny_test_map()
	var u_rd = [UnitScript.new(1, 0, HexCoordScript.new(0, 0))]
	var d_rd: Dictionary = {}
	d_rd["project_type"] = "produce_unit"
	d_rd["progress"] = 2
	d_rd["cost"] = 2
	d_rd["ready"] = true
	var city_rd = CityScript.new(4, 0, HexCoordScript.new(0, -1), d_rd)
	var sc_rd = ScenarioScript.new(m_rd, u_rd, [city_rd], 11, 22)
	var ts_rd = TurnStateScript.new([0, 1], 0, 1)
	var gs_rd = _LegalActionsTestGameStateShell.new(sc_rd, ts_rd)
	var Lrd = LegalActionsScript.for_current_player(gs_rd)
	var has_sp_rd = false
	var lr = 0
	while lr < Lrd.size() - 1:
		if (Lrd[lr] as Dictionary)["action_type"] == SetCityProductionScript.ACTION_TYPE:
			has_sp_rd = true
		lr = lr + 1
	_check(not has_sp_rd, "no SetCityProduction when ready project")

	var m_w = HexMapScript.make_tiny_test_map()
	var u_w = [UnitScript.new(2, 0, HexCoordScript.new(-1, 0), "settler")]
	var sc_w = ScenarioScript.new(m_w, u_w, [], 50, 60)
	var gs_w = GameStateScript.new(sc_w)
	var Lw = LegalActionsScript.for_current_player(gs_w)
	var has_fc_w = false
	var lw = 0
	while lw < Lw.size() - 1:
		if (Lw[lw] as Dictionary)["action_type"] == FoundCityScript.ACTION_TYPE:
			has_fc_w = true
		lw = lw + 1
	_check(not has_fc_w, "no FoundCity on WATER tile")

	var r_end = gs.try_apply(EndTurnScript.make(0))
	_check(r_end["accepted"], "manual advance to p1")
	var L1 = LegalActionsScript.for_current_player(gs)
	_check(L1.size() > 0, "p1 nonempty")
	_check_list_segments_no_engine(L1)
	var last1 = L1[L1.size() - 1] as Dictionary
	_check(last1["action_type"] == EndTurnScript.ACTION_TYPE, "p1 last EndTurn")
	_check(last1["actor_id"] == 1, "p1 EndTurn actor")
	var l1i = 0
	while l1i < L1.size():
		_check((L1[l1i] as Dictionary)["actor_id"] == 1, "p1 all entries actor 1")
		l1i = l1i + 1

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
