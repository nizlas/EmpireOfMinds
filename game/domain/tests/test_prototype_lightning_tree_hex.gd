# Headless: godot --headless --path game -s res://domain/tests/test_prototype_lightning_tree_hex.gd
# Phase 5.1.8c: prototype lightning_tree_hex is open PLAINS/GRASSLAND (not prototype forest decoration).
extends SceneTree

const ScenarioScript = preload("res://domain/scenario.gd")
const HexMapScript = preload("res://domain/hex_map.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const GameStateScript = preload("res://domain/game_state.gd")
const MoveUnitScript = preload("res://domain/actions/move_unit.gd")
const ProgressCandidateFilterScript = preload("res://domain/progress_candidate_filter.gd")
const PlainsForestScript = preload("res://presentation/plains_forest_decoration.gd")

var _total = 0
var _any_fail = false


func _axial_dist(q1: int, r1: int, q2: int, r2: int) -> int:
	return int(abs(q1 - q2) + abs(r1 - r2) + abs(q1 + r1 - q2 - r2)) / 2


func _starts() -> Array:
	return [[0, 0], [1, 0], [0, -1]]


func _init() -> void:
	var proto = ScenarioScript.make_prototype_play_scenario()
	var t = proto.lightning_tree_hex
	_check(t != null, "prototype tree non-null")
	var terr = proto.map.terrain_at(t)
	_check(
		terr == HexMapScript.Terrain.PLAINS or terr == HexMapScript.Terrain.GRASSLAND,
		"tree base terrain PLAINS or GRASSLAND",
	)
	_check(
		not PlainsForestScript.is_prototype_foreground_forest_hex(t.q, t.r),
		"tree not in prototype forest-cluster overlay list",
	)
	_check(proto.map.has(t), "tree on disk")
	for s in _starts():
		var d: int = _axial_dist(t.q, t.r, int(s[0]), int(s[1]))
		_check(d >= 2, "tree not adjacent to a starting unit hex (deliberate move)")
	_check(t.q == 3 and t.r == 0, "deterministic axial (3,0) for prototype play")

	var gs = GameStateScript.new(ScenarioScript.make_prototype_play_scenario())
	_check(gs.try_apply(MoveUnitScript.make(0, 2, 1, 0, 2, 0))["accepted"], "warrior step toward tree")
	_check(gs.try_apply(MoveUnitScript.make(0, 2, 2, 0, 3, 0))["accepted"], "warrior onto prototype tree")
	var f = ProgressCandidateFilterScript.for_current_player(gs)
	_check(f.size() == 1, "controlled_fire candidate after observation")
	_check(str((f[0] as Dictionary).get("progress_id", "")) == "controlled_fire", "progress_id")

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
