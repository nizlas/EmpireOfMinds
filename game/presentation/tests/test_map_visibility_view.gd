# Headless: godot --headless --path game -s res://presentation/tests/test_map_visibility_view.gd
extends SceneTree

const GameStateScript = preload("res://domain/game_state.gd")
const MapVisibilityViewScript = preload("res://presentation/map_visibility_view.gd")
const EndTurnScript = preload("res://domain/actions/end_turn.gd")

var _total: int = 0
var _any_fail: bool = false


func _init() -> void:
	call_deferred("_run")


func _set_from_overlay(overlay: Array) -> Dictionary:
	var d: Dictionary = {}
	var i: int = 0
	while i < overlay.size():
		var c = overlay[i]
		d[Vector2i(int((c as HexCoord).q), int((c as HexCoord).r))] = true
		i = i + 1
	return d


func _run() -> void:
	var layout_stub = RefCounted.new()
	_check(MapVisibilityViewScript.compute_overlay_items(null, layout_stub).is_empty(), "null game_state -> empty")
	var gs = GameStateScript.make_tiny_test_state()
	_check(MapVisibilityViewScript.compute_overlay_items(gs, null).is_empty(), "null layout -> empty")
	var coords: Array = gs.scenario.map.coords()
	var ov0: Array = MapVisibilityViewScript.compute_overlay_items(gs, layout_stub)
	var s0: Dictionary = _set_from_overlay(ov0)
	var idx: int = 0
	while idx < coords.size():
		var hc: HexCoord = coords[idx] as HexCoord
		var vk := Vector2i(int(hc.q), int(hc.r))
		var explored_p0: bool = gs.visibility_state.is_explored(0, hc)
		_check(s0.has(vk) != explored_p0, "P0: overlay is complement of explored")
		idx += 1
	var et = EndTurnScript.make(0)
	_check(gs.try_apply(et)["accepted"], "EndTurn to P1")
	_check(int(gs.turn_state.current_player_id()) == 1, "current player P1")
	var ov1: Array = MapVisibilityViewScript.compute_overlay_items(gs, layout_stub)
	var s1: Dictionary = _set_from_overlay(ov1)
	var j: int = 0
	while j < coords.size():
		var hc1: HexCoord = coords[j] as HexCoord
		var vk1 := Vector2i(int(hc1.q), int(hc1.r))
		var explored_p1: bool = gs.visibility_state.is_explored(1, hc1)
		_check(s1.has(vk1) != explored_p1, "P1: overlay is complement of explored after EndTurn")
		j += 1

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
