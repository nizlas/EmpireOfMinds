# Headless: godot --headless --path game -s res://ai/tests/test_rule_based_ai_player.gd
extends SceneTree
const RuleBasedAIPlayerScript = preload("res://ai/rule_based_ai_player.gd")
const MoveUnitScript = preload("res://domain/actions/move_unit.gd")
const EndTurnScript = preload("res://domain/actions/end_turn.gd")
const FoundCityScript = preload("res://domain/actions/found_city.gd")
const SetCityProductionScript = preload("res://domain/actions/set_city_production.gd")
const GameStateScript = preload("res://domain/game_state.gd")
const LegalActionsScript = preload("res://domain/legal_actions.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const HexMapScript = preload("res://domain/hex_map.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const UnitScript = preload("res://domain/unit.gd")
const CityScript = preload("res://domain/city.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	var d0 = RuleBasedAIPlayerScript.decide(null, [])
	_check(d0.is_empty(), "empty legal -> empty dict")
	var et = EndTurnScript.make(0)
	var only_end = [et]
	var d1 = RuleBasedAIPlayerScript.decide(null, only_end)
	_check(_action_equals(d1, et), "only EndTurn chosen")
	var mv = MoveUnitScript.make(0, 1, 0, 0, -1, 1)
	var mixed = [et, mv]
	var d2 = RuleBasedAIPlayerScript.decide(null, mixed)
	_check(_action_equals(d2, mv), "prefers MoveUnit when listed after EndTurn")
	var d2b = RuleBasedAIPlayerScript.decide(null, mixed)
	_check(_action_equals(d2, d2b), "deterministic same input")
	var mv2 = MoveUnitScript.make(0, 1, 0, 0, 0, 1)
	var two_moves = [mv, mv2]
	var d3 = RuleBasedAIPlayerScript.decide(null, two_moves)
	_check(_action_equals(d3, mv), "first MoveUnit wins")
	_check(_action_matches_list(d3, two_moves), "choice in list")
	var junk_list = [{"foo": 1}, {"action_type": "nope"}]
	var d4 = RuleBasedAIPlayerScript.decide(null, junk_list)
	_check(d4.is_empty(), "no known actions -> empty")

	var gs0 = GameStateScript.make_tiny_test_state()
	var leg0 = LegalActionsScript.for_current_player(gs0)
	var df = RuleBasedAIPlayerScript.decide(gs0, leg0)
	_check(df.get("action_type", "") == FoundCityScript.ACTION_TYPE, "no city prefers FoundCity")
	_check(_action_matches_list(df, leg0), "found in legal list")

	var m1 = HexMapScript.make_tiny_test_map()
	var u1 = [UnitScript.new(1, 0, HexCoordScript.new(0, 0))]
	var cy1 = CityScript.new(10, 0, HexCoordScript.new(1, -1), null)
	var sc1 = ScenarioScript.new(m1, u1, [cy1], 50, 60)
	var gs1 = GameStateScript.new(sc1)
	var leg1 = LegalActionsScript.for_current_player(gs1)
	var ds = RuleBasedAIPlayerScript.decide(gs1, leg1)
	_check(ds.get("action_type", "") == SetCityProductionScript.ACTION_TYPE, "empty project prefers SetCityProduction")
	_check(_action_matches_list(ds, leg1), "set in legal list")

	var m2 = HexMapScript.make_tiny_test_map()
	var d_pr: Dictionary = {}
	d_pr["project_type"] = "produce_unit"
	d_pr["progress"] = 0
	d_pr["cost"] = 2
	d_pr["ready"] = false
	var cy2 = CityScript.new(2, 0, HexCoordScript.new(1, -1), d_pr)
	var u2 = [UnitScript.new(1, 0, HexCoordScript.new(0, 0))]
	var sc2 = ScenarioScript.new(m2, u2, [cy2], 50, 60)
	var gs2 = GameStateScript.new(sc2)
	var leg2 = LegalActionsScript.for_current_player(gs2)
	var dm = RuleBasedAIPlayerScript.decide(gs2, leg2)
	_check(dm.get("action_type", "") == MoveUnitScript.ACTION_TYPE, "city has project prefer MoveUnit")
	_check(_action_matches_list(dm, leg2), "move in list")

	var rm = gs2.try_apply(MoveUnitScript.make(0, 1, 0, 0, -1, 1))
	_check(rm["accepted"], "setup move")
	var leg2b = LegalActionsScript.for_current_player(gs2)
	var de = RuleBasedAIPlayerScript.decide(gs2, leg2b)
	_check(de.get("action_type", "") == EndTurnScript.ACTION_TYPE, "after move pick EndTurn")
	_check(_action_matches_list(de, leg2b), "end in list")

	var gs = GameStateScript.make_tiny_test_state()
	var rm2 = gs.try_apply(MoveUnitScript.make(0, 1, 0, 0, -1, 1))
	_check(rm2["accepted"], "setup move for policy branch")
	var leg_city = LegalActionsScript.for_current_player(gs)
	var d5a = RuleBasedAIPlayerScript.decide(gs, leg_city)
	_check(d5a.get("action_type", "") == FoundCityScript.ACTION_TYPE, "no cities after move still prefers FoundCity")
	_check(_action_matches_list(d5a, leg_city), "found still in legal list")

	var m_pol = HexMapScript.make_tiny_test_map()
	var d_po: Dictionary = {}
	d_po["project_type"] = "produce_unit"
	d_po["progress"] = 0
	d_po["cost"] = 2
	d_po["ready"] = false
	var cy_pol = CityScript.new(7, 0, HexCoordScript.new(1, -1), d_po)
	var u_pol = [
		UnitScript.new(1, 0, HexCoordScript.new(0, 0)),
		UnitScript.new(2, 0, HexCoordScript.new(1, 0)),
	]
	var sc_pol = ScenarioScript.new(m_pol, u_pol, [cy_pol], 50, 71)
	var gs_pol = GameStateScript.new(sc_pol)
	var rm_pol = gs_pol.try_apply(MoveUnitScript.make(0, 1, 0, 0, -1, 1))
	_check(rm_pol["accepted"], "setup move with city for end-turn branch")
	var leg_pol = LegalActionsScript.for_current_player(gs_pol)
	var d5 = RuleBasedAIPlayerScript.decide(gs_pol, leg_pol)
	_check(d5.get("action_type", "") == EndTurnScript.ACTION_TYPE, "after one move pick EndTurn when player has city")
	_check(int(d5.get("actor_id", -1)) == 0, "EndTurn actor 0")
	_check(_action_matches_list(d5, leg_pol), "end from legal")

	if _any_fail:
		call_deferred("quit", 1)
	else:
		print("PASS %d/%d" % [_total, _total])
		call_deferred("quit", 0)


func _action_matches_list(action: Dictionary, legal: Array) -> bool:
	var i = 0
	while i < legal.size():
		if _action_equals(action, legal[i]):
			return true
		i = i + 1
	return false


func _action_equals(a: Dictionary, b) -> bool:
	if typeof(b) != TYPE_DICTIONARY:
		return false
	for k in a:
		if not b.has(k):
			return false
		var va = a[k]
		var vb = b[k]
		if va is Array and vb is Array:
			var aa = va as Array
			var ab = vb as Array
			if aa.size() != ab.size():
				return false
			var j = 0
			while j < aa.size():
				if aa[j] != ab[j]:
					return false
				j = j + 1
		else:
			if va != vb:
				return false
	for k2 in b:
		if not a.has(k2):
			return false
	return true


func _check(cond, message) -> void:
	_total = _total + 1
	if cond:
		return
	_any_fail = true
	var line = "FAIL: %s" % message
	print(line)
	push_error(line)
