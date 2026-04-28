# Headless: godot --headless --path game -s res://domain/tests/test_found_city_flow.gd
extends SceneTree

const GameStateScript = preload("res://domain/game_state.gd")
const FoundCityScript = preload("res://domain/actions/found_city.gd")
const MoveUnitScript = preload("res://domain/actions/move_unit.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	var gs = GameStateScript.make_tiny_test_state()
	var bad = gs.try_apply(FoundCityScript.make(1, 3, 0, -1))
	_check(
		not bad["accepted"] and bad["reason"] == "not_current_player",
		"wrong player gated in try_apply"
	)

	var old_city_id = gs.scenario.peek_next_city_id()
	var act = FoundCityScript.make(0, 1, 0, 0)
	var r = gs.try_apply(act)
	_check(r["accepted"], "found_city accepted")
	_check(gs.scenario.city_by_id(old_city_id) != null, "scenario has new city id")
	_check(gs.scenario.unit_by_id(1) == null, "founder removed")

	_check(gs.log.size() == 1, "one log entry")
	var entry = gs.log.get_entry(0)
	_check(entry["action_type"] == "found_city", "log action_type")
	_check(entry["city_id"] == old_city_id, "log city_id")
	var pos_a = entry["position"] as Array
	_check(pos_a.size() == 2 and int(pos_a[0]) == 0 and int(pos_a[1]) == 0, "log position")
	_check(entry["unit_id"] == 1, "log unit_id")
	_check(entry["actor_id"] == 0, "log actor_id")
	_check(entry["result"] == "accepted", "log result")

	var mv = gs.try_apply(MoveUnitScript.make(0, 2, 1, 0, 0, 0))
	_check(mv["accepted"] and gs.scenario.unit_by_id(2).position.equals(HexCoordScript.new(0, 0)), "unit 2 on city hex")
	var r2 = gs.try_apply(FoundCityScript.make(0, 2, 0, 0))
	_check(
		not r2["accepted"] and r2["reason"] == "tile_already_has_city",
		"second found same tile"
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
