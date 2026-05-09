# Headless: godot --headless --path game -s res://domain/tests/test_legal_actions_effective_rules.gd
extends SceneTree

class _FakeAllFalse extends RefCounted:
	func is_city_project_supported(_project_id: String) -> bool:
		return false


class _FakeAllTrue extends RefCounted:
	func is_city_project_supported(_project_id: String) -> bool:
		return true


const LegalActionsScript = preload("res://domain/legal_actions.gd")
const GameStateScript = preload("res://domain/game_state.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const HexMapScript = preload("res://domain/hex_map.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const UnitScript = preload("res://domain/unit.gd")
const CityScript = preload("res://domain/city.gd")
const MoveUnitScript = preload("res://domain/actions/move_unit.gd")
const EndTurnScript = preload("res://domain/actions/end_turn.gd")
const SetCityProductionScript = preload("res://domain/actions/set_city_production.gd")
const EffectiveRulesScript = preload("res://domain/effective_rules.gd")
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
	var gs = GameStateScript.new(sc_c)

	var L_default = LegalActionsScript.for_current_player(gs)
	var L_baseline_arg = LegalActionsScript.for_current_player(
		gs,
		EffectiveRulesScript.with_baseline_registries()
	)
	_check(_lists_equal_actions(L_default, L_baseline_arg), "explicit baseline matches default")

	var L_ff = LegalActionsScript.for_current_player(gs, _FakeAllFalse.new())
	var filtered: Array = []
	var k = 0
	while k < L_default.size():
		var ek = L_default[k] as Dictionary
		if ek["action_type"] != SetCityProductionScript.ACTION_TYPE:
			filtered.append(ek)
		k = k + 1
	_check(_lists_equal_actions(filtered, L_ff), "all-false EffectiveRules drops set_city_production only")

	var L_at = LegalActionsScript.for_current_player(gs, _FakeAllTrue.new())
	_check(
		_lists_equal_actions(L_at, L_default),
		"all-true EffectiveRules matches default for enumerated city projects (gate does not bypass validate)"
	)

	var ps_both = ProgressStateScript.new(
		{
			0:
			{
				"unlocked_targets": [
					{"target_type": "city_project", "target_id": SetCityProductionScript.PROJECT_ID_PRODUCE_UNIT_WARRIOR},
					{"target_type": "city_project", "target_id": SetCityProductionScript.PROJECT_ID_PRODUCE_UNIT_SETTLER},
				],
				"completed_progress_ids": [],
			}
		}
	)
	var gs_unlocked = GameStateScript.new(sc_c, ps_both)
	var L_ff_both = LegalActionsScript.for_current_player(gs_unlocked, _FakeAllFalse.new())
	var sp_ct_ff = 0
	var t = 0
	while t < L_ff_both.size():
		if (L_ff_both[t] as Dictionary)["action_type"] == SetCityProductionScript.ACTION_TYPE:
			sp_ct_ff = sp_ct_ff + 1
		t = t + 1
	_check(sp_ct_ff == 0, "all-false drops sp even when warrior and settler unlocked in ProgressState")

	var saw_sp = false
	var si = 0
	while si < L_default.size() - 1:
		if (L_default[si] as Dictionary)["action_type"] == SetCityProductionScript.ACTION_TYPE:
			saw_sp = true
		si = si + 1
	_check(saw_sp, "fixture still includes warrior set_city_production under baseline")

	var nm = 0
	var lm = 0
	while lm < L_ff.size() - 1:
		if (L_ff[lm] as Dictionary)["action_type"] == MoveUnitScript.ACTION_TYPE:
			nm = nm + 1
		lm = lm + 1
	_check(nm > 0, "all-false still has moves")
	var last_ff = L_ff[L_ff.size() - 1] as Dictionary
	_check(last_ff["action_type"] == EndTurnScript.ACTION_TYPE, "all-false ends end_turn")

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
