# Headless: godot --headless --path game -s res://domain/tests/test_player_visibility_state.gd
extends SceneTree

const PlayerVisibilityStateScript = preload("res://domain/player_visibility_state.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")

var _total: int = 0
var _any_fail: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var empty = PlayerVisibilityStateScript.empty_for_players([0, 1])
	var e0: Array = empty.explored_for_player(0)
	var e1: Array = empty.explored_for_player(1)
	_check(e0.is_empty() and e1.is_empty(), "empty_for_players no tiles")
	_check(
		not empty.is_explored(0, HexCoordScript.new(0, 0)),
		"is_explored false unknown P0"
	)
	_check(
		not empty.is_explored(1, HexCoordScript.new(5, 5)),
		"is_explored false unknown P1"
	)

	var w0 = empty.with_revealed(
		0,
		[HexCoordScript.new(0, 0), HexCoordScript.new(1, 0)],
	)
	_check(e0.is_empty(), "with_revealed does not mutate original")
	_check(w0.explored_for_player(0).size() == 2, "with_revealed adds two P0")
	_check(w0.explored_for_player(1).is_empty(), "P1 still empty")
	var exp0: Array = w0.explored_for_player(0)
	_check(
		int((exp0[0] as HexCoord).q) == 0 and int((exp0[0] as HexCoord).r) == 0,
		"sort q,r first"
	)
	_check(
		int((exp0[1] as HexCoord).q) == 1 and int((exp0[1] as HexCoord).r) == 0,
		"sort q,r second"
	)

	var w1 = w0.with_revealed(0, [HexCoordScript.new(1, 0)])
	_check(w1.explored_for_player(0).size() == 2, "union idempotent")
	var w2 = w0.with_revealed(0, [HexCoordScript.new(-2, 3)])
	_check(w2.explored_for_player(0).size() == 3, "union grows")

	_check(w0.equals(w0), "equals reflexive")
	_check(w0.equals(w1), "equals same tiles idempotent case")
	_check(not w0.equals(w2), "equals false when different")
	_check(not w0.equals(null), "equals null false")
	_check(not w0.equals("x"), "equals wrong type")

	var p1_only = empty.with_revealed(1, [HexCoordScript.new(0, 0)])
	_check(not w0.equals(p1_only), "equals false different owner tiles")

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
	var line: String = "FAIL: %s" % message
	print(line)
	push_error(line)
