# Headless: godot --headless --path game -s res://presentation/tests/test_log_view.gd
extends SceneTree
const LogViewScript = preload("res://presentation/log_view.gd")
const GameStateScript = preload("res://domain/game_state.gd")
const MoveUnitScript = preload("res://domain/actions/move_unit.gd")
const EndTurnScript = preload("res://domain/actions/end_turn.gd")
const MovementRulesScript = preload("res://domain/movement_rules.gd")

var _total = 0
var _any_fail = false


func _grow_log_to_at_least(gs, min_size: int) -> void:
	var guard = 0
	while gs.log.size() < min_size and guard < 500:
		guard = guard + 1
		var pid = gs.turn_state.current_player_id()
		var moved = false
		var units = gs.scenario.units()
		var ui = 0
		while ui < units.size():
			var uu = units[ui]
			if uu.owner_id != pid:
				ui = ui + 1
				continue
			var dests = MovementRulesScript.legal_destinations(gs.scenario, uu.id)
			if dests.size() > 0:
				var d = dests[0]
				var r = gs.try_apply(
					MoveUnitScript.make(pid, uu.id, uu.position.q, uu.position.r, d.q, d.r)
				)
				if r["accepted"]:
					moved = true
					break
			ui = ui + 1
		if not moved:
			var er = gs.try_apply(EndTurnScript.make(pid))
			if not er["accepted"]:
				break


func _init() -> void:
	_check(LogViewScript.compute_text(null) == "", "null game_state -> empty")
	var gs0 = GameStateScript.make_tiny_test_state()
	_check(LogViewScript.compute_text(gs0) == "", "empty log -> empty")
	var gs = GameStateScript.make_tiny_test_state()
	var mv = gs.try_apply(MoveUnitScript.make(0, 1, 0, 0, 1, -1))
	_check(mv["accepted"], "MoveUnit applies")
	var one = LogViewScript.compute_text(gs)
	var expect_one = LogViewScript.format_entry(gs.log.get_entry(0))
	_check(one == expect_one, "one move: single formatted line")
	_check(one == "[0] P0 move_unit unit 1 (0,0) -> (1,-1)", "one move exact")
	var en = gs.try_apply(EndTurnScript.make(0))
	_check(en["accepted"], "EndTurn applies")
	var two = LogViewScript.compute_text(gs)
	var exp0 = LogViewScript.format_entry(gs.log.get_entry(0))
	var exp1 = LogViewScript.format_entry(gs.log.get_entry(1))
	_check(two == (exp0 + "\n" + exp1), "move then end: two lines")
	_grow_log_to_at_least(gs, LogViewScript.MAX_ENTRIES + 1)
	_check(gs.log.size() >= LogViewScript.MAX_ENTRIES + 1, "log grown for tail test")
	var tail = LogViewScript.compute_text(gs, LogViewScript.MAX_ENTRIES)
	var tail_lines = tail.split("\n")
	_check(tail_lines.size() == LogViewScript.MAX_ENTRIES, "tail has MAX_ENTRIES lines")
	var first_idx = gs.log.size() - LogViewScript.MAX_ENTRIES
	var exp_first = LogViewScript.format_entry(gs.log.get_entry(first_idx))
	_check(tail_lines[0] == exp_first, "tail starts at oldest of window")
	var sz_before = gs.log.size()
	LogViewScript.compute_text(gs)
	_check(gs.log.size() == sz_before, "compute_text does not change log size")
	var unk = LogViewScript.format_entry(
		{"index": 7, "action_type": "future_kind", "actor_id": 2}
	)
	_check(unk == "[7] P2 future_kind", "unknown action_type fallback")
	var fc_fmt = LogViewScript.format_entry(
		{
			"index": 0,
			"action_type": "found_city",
			"actor_id": 0,
			"unit_id": 3,
			"city_id": 10,
			"position": [1, -1],
		}
	)
	_check(fc_fmt == "[0] P0 found city c10 at (1,-1) from u3", "found_city format")
	var sp_fmt = LogViewScript.format_entry(
		{
			"index": 0,
			"action_type": "set_city_production",
			"actor_id": 0,
			"city_id": 1,
			"project_type": "produce_unit",
		}
	)
	_check(sp_fmt == "[0] P0 set_city_production c1 produce_unit", "set_city_production format")
	var pr_fmt = LogViewScript.format_entry(
		{
			"index": 3,
			"action_type": "production_progress",
			"actor_id": 0,
			"city_id": 1,
			"project_type": "produce_unit",
			"progress_before": 0,
			"progress_after": 1,
			"cost": 2,
			"source": "engine",
			"result": "accepted",
		}
	)
	_check(pr_fmt == "[3] P0 production c1 produce_unit 0->1/2", "production_progress format")
	var up_fmt = LogViewScript.format_entry(
		{
			"index": 42,
			"action_type": "unit_produced",
			"actor_id": 0,
			"city_id": 1,
			"unit_id": 99,
			"position": [2, -3],
			"project_type": "produce_unit",
			"source": "engine",
			"result": "accepted",
		}
	)
	_check(up_fmt == "[42] P0 produced u99 at (2,-3) from c1", "unit_produced format")
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
