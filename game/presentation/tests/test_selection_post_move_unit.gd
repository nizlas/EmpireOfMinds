# Headless: Phase **5.2.5a** — keep unit selected after accepted **MoveUnit** while MP remain.
extends SceneTree

const GameStateScript = preload("res://domain/game_state.gd")
const MoveUnitScript = preload("res://domain/actions/move_unit.gd")
const SelectionStateScript = preload("res://presentation/selection_state.gd")
const SelectionViewScript = preload("res://presentation/selection_view.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const SelectionControllerScript = preload("res://presentation/selection_controller.gd")

class PanelStub extends RefCounted:
	var city_view_state = null


var _total: int = 0
var _any_fail: bool = false


func _init() -> void:
	call_deferred("_run")


func _overlay_ring_and_dest(items: Array) -> Vector2i:
	var ring: int = 0
	var dest: int = 0
	var i: int = 0
	while i < items.size():
		var k = str((items[i] as Dictionary).get("kind", ""))
		if k == "selected_ring":
			ring += 1
		elif k == "destination_fill":
			dest += 1
		i += 1
	return Vector2i(ring, dest)


func _run() -> void:
	var layout = HexLayoutScript.new()
	# --- Settler: two steps, selection + overlays ---
	var gs = GameStateScript.make_tiny_test_state()
	var sel = SelectionStateScript.new()
	sel.select(1)
	_check(
		gs.try_apply(MoveUnitScript.make(0, 1, 0, 0, 1, -1))["accepted"],
		"settler first move",
	)
	SelectionControllerScript.apply_post_accepted_move_unit_selection(sel, gs.scenario, 1)
	_check(sel.unit_id == 1, "settler still selected after first move")
	_check(gs.scenario.unit_by_id(1).remaining_movement == 1, "settler MP 1")
	var it1 = SelectionViewScript.compute_overlay_items(gs.scenario, layout, sel)
	var c1 = _overlay_ring_and_dest(it1)
	_check(c1.x == 1 and c1.y >= 1, "first move: ring + at least one legal dest")
	_check(
		gs.try_apply(MoveUnitScript.make(0, 1, 1, -1, 0, 0))["accepted"],
		"settler second move",
	)
	SelectionControllerScript.apply_post_accepted_move_unit_selection(sel, gs.scenario, 1)
	_check(sel.unit_id == 1, "settler still selected when exhausted (v0)")
	_check(gs.scenario.unit_by_id(1).remaining_movement == 0, "settler MP 0")
	var it2 = SelectionViewScript.compute_overlay_items(gs.scenario, layout, sel)
	var c2 = _overlay_ring_and_dest(it2)
	_check(c2.x == 1 and c2.y == 0, "exhausted: ring only, no destination highlights")
	var bad = gs.try_apply(MoveUnitScript.make(0, 1, 0, 0, 1, -1))
	_check(not bad["accepted"], "third move rejected")
	_check(sel.unit_id == 1, "rejected move does not clear selection")
	# --- Warrior: one step + selection ---
	var gs_w = GameStateScript.make_tiny_test_state()
	var sel_w = SelectionStateScript.new()
	sel_w.select(2)
	_check(
		gs_w.try_apply(MoveUnitScript.make(0, 2, 1, 0, 1, -1))["accepted"],
		"warrior first move",
	)
	SelectionControllerScript.apply_post_accepted_move_unit_selection(sel_w, gs_w.scenario, 2)
	_check(sel_w.unit_id == 2, "warrior still selected after first move")
	_check(gs_w.scenario.unit_by_id(2).remaining_movement == 1, "warrior MP 1")
	var it_w = SelectionViewScript.compute_overlay_items(gs_w.scenario, layout, sel_w)
	var cw = _overlay_ring_and_dest(it_w)
	_check(cw.x == 1 and cw.y >= 1, "warrior: ring + legal dests after one step")
	# --- EndTurn hotseat clear unchanged (5.2.1) ---
	var sel_end = SelectionStateScript.new()
	sel_end.select(2)
	EndTurnController.apply_hotseat_clear_after_accepted_end_turn(sel_end, PanelStub.new())
	_check(
		sel_end.unit_id == SelectionStateScript.NONE,
		"end turn helper still clears unit selection",
	)
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
