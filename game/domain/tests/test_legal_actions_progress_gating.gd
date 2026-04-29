# Headless: godot --headless --path game -s res://domain/tests/test_legal_actions_progress_gating.gd
extends SceneTree

class _ProgressGatingShell:
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
const SetCityProductionScript = preload("res://domain/actions/set_city_production.gd")
const ProgressStateScript = preload("res://domain/progress_state.gd")

var _total = 0
var _any_fail = false


func _action_dicts_equal(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	var ks = a.keys()
	var ki = 0
	while ki < ks.size():
		var k = ks[ki]
		if not b.has(k):
			return false
		var va = a[k]
		var vb = b[k]
		if typeof(va) != typeof(vb):
			return false
		if typeof(va) == TYPE_ARRAY:
			var aa = va as Array
			var ab = vb as Array
			if aa.size() != ab.size():
				return false
			var ai = 0
			while ai < aa.size():
				if aa[ai] != ab[ai]:
					return false
				ai = ai + 1
		else:
			if va != vb:
				return false
		ki = ki + 1
	return true


func _lists_equal_actions(La: Array, Lb: Array) -> bool:
	if La.size() != Lb.size():
		return false
	var i = 0
	while i < La.size():
		if not _action_dicts_equal(La[i] as Dictionary, Lb[i] as Dictionary):
			return false
		i = i + 1
	return true


func _init() -> void:
	var m_c = HexMapScript.make_tiny_test_map()
	var u_c = [UnitScript.new(1, 0, HexCoordScript.new(0, 0))]
	var city_n = CityScript.new(5, 0, HexCoordScript.new(1, -1), null)
	var sc_c = ScenarioScript.new(m_c, u_c, [city_n], 10, 20)

	var gs_default = GameStateScript.new(sc_c)
	var L_def = LegalActionsScript.for_current_player(gs_default)
	var saw_sp = false
	var i = 0
	while i < L_def.size() - 1:
		var e = L_def[i] as Dictionary
		if e["action_type"] == SetCityProductionScript.ACTION_TYPE:
			saw_sp = true
			_check(
				e["project_id"] == SetCityProductionScript.PROJECT_ID_PRODUCE_UNIT_WARRIOR,
				"default includes warrior sp"
			)
		i = i + 1
	_check(saw_sp, "default has set_city_production")

	var gs_empty = GameStateScript.new(sc_c, ProgressStateScript.new({}))
	var L_lock = LegalActionsScript.for_current_player(gs_empty)
	var sp_ct = 0
	var j = 0
	while j < L_lock.size():
		if (L_lock[j] as Dictionary)["action_type"] == SetCityProductionScript.ACTION_TYPE:
			sp_ct = sp_ct + 1
		j = j + 1
	_check(sp_ct == 0, "empty progress omits all sp")

	var filtered: Array = []
	var k = 0
	while k < L_def.size():
		var ek = L_def[k] as Dictionary
		if ek["action_type"] != SetCityProductionScript.ACTION_TYPE:
			filtered.append(ek)
		k = k + 1
	_check(_lists_equal_actions(filtered, L_lock), "ordering preserved minus sp")

	var nm = 0
	var lm = 0
	while lm < L_lock.size() - 1:
		if (L_lock[lm] as Dictionary)["action_type"] == MoveUnitScript.ACTION_TYPE:
			nm = nm + 1
		lm = lm + 1
	_check(nm > 0, "locked still has moves")
	var last = L_lock[L_lock.size() - 1] as Dictionary
	_check(last["action_type"] == EndTurnScript.ACTION_TYPE, "locked ends end_turn")

	var ts_shell = TurnStateScript.new([0, 1], 0, 1)
	var sh = _ProgressGatingShell.new(sc_c, ts_shell)
	var L_shell = LegalActionsScript.for_current_player(sh)
	var sh_sp = false
	var si = 0
	while si < L_shell.size() - 1:
		if (L_shell[si] as Dictionary)["action_type"] == SetCityProductionScript.ACTION_TYPE:
			sh_sp = true
		si = si + 1
	_check(sh_sp, "null progress shell still enumerates sp")

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
