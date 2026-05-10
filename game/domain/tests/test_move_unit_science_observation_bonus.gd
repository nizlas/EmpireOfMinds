# Headless: godot --headless --path game -s res://domain/tests/test_move_unit_science_observation_bonus.gd
extends SceneTree

const GameStateScript = preload("res://domain/game_state.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const HexMapScript = preload("res://domain/hex_map.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const UnitScript = preload("res://domain/unit.gd")
const CityScript = preload("res://domain/city.gd")
const MoveUnitScript = preload("res://domain/actions/move_unit.gd")
const ProgressDefinitionsScript = preload("res://domain/content/progress_definitions.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	var m = HexMapScript.make_tiny_test_map()
	var u = [UnitScript.new(1, 0, HexCoordScript.new(0, 0), "warrior")]
	var city = CityScript.new(3, 0, HexCoordScript.new(1, -1), null)
	var tree = HexCoordScript.new(1, 0)
	var scen = ScenarioScript.new(m, u, [city], 10, 20, tree)
	var gs = GameStateScript.new(scen)
	var n0 = gs.log.size()
	var mv = gs.try_apply(MoveUnitScript.make(0, 1, 0, 0, 1, 0))
	_check(mv["accepted"], "move onto tree")
	_check(gs.log.size() > n0, "entries after move")
	var bonus_rows = 0
	var sci = 0
	var i = n0
	while i < gs.log.size():
		var e = gs.log.get_entry(i) as Dictionary
		var at = str(e.get("action_type", ""))
		if at == "science_bonus":
			bonus_rows += 1
			_check(str(e.get("bonus_id", "")) == "lightning_scarred_tree", "log bonus_id")
			_check(int(e.get("delta", 0)) == 4, "log bonus delta")
			_check(int(e.get("cost", 0)) == ProgressDefinitionsScript.cost("controlled_fire"), "log bonus cost")
			_check(str(e.get("progress_id", "")) == "controlled_fire", "log progress_id")
		if at == "science_progress":
			sci += 1
		i = i + 1
	_check(bonus_rows == 1, "exactly one science_bonus")
	_check(sci >= 1, "at least one science_progress")

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
