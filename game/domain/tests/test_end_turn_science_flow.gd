# Headless: godot --headless --path game -s res://domain/tests/test_end_turn_science_flow.gd
extends SceneTree

const GameStateScript = preload("res://domain/game_state.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const HexMapScript = preload("res://domain/hex_map.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const UnitScript = preload("res://domain/unit.gd")
const CityScript = preload("res://domain/city.gd")
const EndTurnScript = preload("res://domain/actions/end_turn.gd")
const SetCityProductionScript = preload("res://domain/actions/set_city_production.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	var m = HexMapScript.make_tiny_test_map()
	var u = [UnitScript.new(1, 0, HexCoordScript.new(0, 0), "warrior")]
	var city = CityScript.new(3, 0, HexCoordScript.new(1, -1), null, "", true, ["palace"])
	var scen = ScenarioScript.new(m, u, [city], 10, 20, null)
	var gs = GameStateScript.new(scen)
	# Pin controlled_fire — auto-target would research foraging_systems first in tree order.
	gs.progress_state = gs.progress_state.with_current_research(0, "controlled_fire")
	var round_i = 0
	while round_i < 6:
		_check(gs.try_apply(EndTurnScript.make(0))["accepted"], "p0 end")
		_check(gs.try_apply(EndTurnScript.make(1))["accepted"], "p1 end")
		round_i = round_i + 1
	_check(gs.progress_state.has_completed_progress(0, "controlled_fire"), "auto completed")
	_check(
		gs.progress_state.has_unlocked_target(0, "city_project", SetCityProductionScript.PROJECT_ID_PRODUCE_UNIT_SETTLER),
		"settler baseline independent of CF"
	)
	_check(gs.progress_state.has_unlocked_target(0, "building", "hearth"), "cf bundle hearth after auto complete")
	var saw_completed = false
	var saw_no_settler_in_log = true
	var li = 0
	while li < gs.log.size():
		var e = gs.log.get_entry(li) as Dictionary
		if str(e.get("action_type", "")) == "science_completed":
			saw_completed = true
			_check(int(e.get("actor_id", -1)) == 0, "completed for p0")
			if e.has("unlocked_targets") and typeof(e["unlocked_targets"]) == TYPE_ARRAY:
				var ut = e["unlocked_targets"] as Array
				var uj = 0
				while uj < ut.size():
					var row = ut[uj] as Dictionary
					if (
						str(row.get("target_type", "")) == "city_project"
						and str(row.get("target_id", "")) == SetCityProductionScript.PROJECT_ID_PRODUCE_UNIT_SETTLER
					):
						saw_no_settler_in_log = false
					uj = uj + 1
		li = li + 1
	_check(saw_completed, "log contains science_completed")
	_check(saw_no_settler_in_log, "science_completed delta omits settler city_project")

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
