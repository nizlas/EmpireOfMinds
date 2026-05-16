# Headless: godot --headless --path game -s res://presentation/tests/test_turn_status_panel.gd
extends SceneTree

const GameStateScript = preload("res://domain/game_state.gd")
const EndTurnScript = preload("res://domain/actions/end_turn.gd")
const TurnStatusPanelScript = preload("res://presentation/turn_status_panel.gd")
const UnitNameplateViewScript = preload("res://presentation/unit_nameplate_view.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var vm0 = TurnStatusPanelScript.compute_view_model(null, 0)
	_check(str(vm0.get("title", "")) == "—", "null game_state placeholder title")
	_check(str(vm0.get("detail", "")) == "", "null game_state empty detail")

	var gs = GameStateScript.make_tiny_test_state()
	var vm_p0 = TurnStatusPanelScript.compute_view_model(gs, 0)
	_check(str(vm_p0.get("title", "")) == "Västerviksjävlarna's turn", "opening turn names playtest P0")
	_check(str(vm_p0.get("detail", "")) == "Turn 1", "detail is turn number only")
	_check(str(vm_p0.get("title", "")).find("Waiting") < 0, "no remote-waiting copy for P0")
	var accent0: Color = UnitNameplateViewScript.owner_nameplate_accent_color(0)
	_check(
		(vm_p0.get("orb_color", Color.BLACK) as Color).is_equal_approx(accent0),
		"P0 orb matches nameplate/empire accent source"
	)
	_check(
		(vm_p0.get("border_color", Color.BLACK) as Color).r > 0.01,
		"P0 border color derived from accent"
	)

	_check(gs.try_apply(EndTurnScript.make(0))["accepted"], "end turn to advance current player")
	var vm_p1_seat0 = TurnStatusPanelScript.compute_view_model(gs, 0)
	_check(
		str(vm_p1_seat0.get("title", "")) == "Malmöfubikkarna's turn",
		"after EndTurn copy names playtest P1 (still hotseat; local_id ignored)"
	)
	_check(str(vm_p1_seat0.get("detail", "")) == "Turn 1", "still same turn number domain state")
	_check(str(vm_p1_seat0.get("title", "")).find("Waiting") < 0, "no Waiting after P0 ends turn")
	var accent1: Color = UnitNameplateViewScript.owner_nameplate_accent_color(1)
	_check(
		(vm_p1_seat0.get("orb_color", Color.BLACK) as Color).is_equal_approx(accent1),
		"P1 orb matches nameplate/empire accent source"
	)

	var vm_p1_seat1 = TurnStatusPanelScript.compute_view_model(gs, 1)
	_check(
		str(vm_p1_seat1.get("title", "")) == "Malmöfubikkarna's turn",
		"same title with different local_id arg"
	)

	var o0 = vm_p0.get("orb_color", Color.BLACK) as Color
	var o1 = vm_p1_seat0.get("orb_color", Color.BLACK) as Color
	_check(not o0.is_equal_approx(o1), "P0 vs P1 orb colors differ")

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
