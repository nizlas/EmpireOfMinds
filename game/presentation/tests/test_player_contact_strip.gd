# Headless: godot --headless --path game -s res://presentation/tests/test_player_contact_strip.gd
extends SceneTree

const GameStateScript = preload("res://domain/game_state.gd")
const EndTurnScript = preload("res://domain/actions/end_turn.gd")
const PlayerContactStripScr = preload("res://presentation/player_contact_strip.gd")
const UnitNameplateViewScript = preload("res://presentation/unit_nameplate_view.gd")
const PlaytestPlayerDisplayScript = preload("res://presentation/playtest_player_display.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	call_deferred("_run")


func _vm_text_has_no_waiting(vm: Dictionary) -> bool:
	var entries: Array = vm.get("entries", []) as Array
	var ei: int = 0
	while ei < entries.size():
		var d: Dictionary = entries[ei] as Dictionary
		if str(d.get("label_short", "")).to_lower().find("wait") >= 0:
			return false
		if str(d.get("label_long", "")).to_lower().find("waiting") >= 0:
			return false
		ei = ei + 1
	return true


func _run() -> void:
	var vm0: Dictionary = PlayerContactStripScr.compute_view_model(null)
	_check(not bool(vm0.get("visible", true)), "null game_state not visible")
	_check((vm0.get("entries", []) as Array).is_empty(), "null game_state empty entries")

	var gs = GameStateScript.make_tiny_test_state()
	var vm1: Dictionary = PlayerContactStripScr.compute_view_model(gs)
	var e1: Array = vm1.get("entries", []) as Array
	_check(e1.size() == 2, "two turn_state players => two entries")
	var d0: Dictionary = e1[0] as Dictionary
	var d1: Dictionary = e1[1] as Dictionary
	_check(bool(d0.get("is_current_turn", false)), "P0 is current initially")
	_check(not bool(d1.get("is_current_turn", true)), "P1 not current initially")
	_check(int(d0.get("player_id", -9)) == 0, "first id 0")
	_check(
		str(d0.get("label_short", "")) == PlaytestPlayerDisplayScript.display_name_for_player_id(0),
		"chip label playtest P0",
	)
	_check(
		str(d0.get("label_long", "")) == PlaytestPlayerDisplayScript.display_name_for_player_id(0),
		"long label playtest P0",
	)
	_check(str(d0.get("contact_state", "")) == "known", "v0 contact_state known")
	_check(
		(d0.get("accent_color", Color.BLACK) as Color).is_equal_approx(
			UnitNameplateViewScript.owner_nameplate_accent_color(0)
		),
		"P0 accent matches nameplate helper"
	)
	_check(_vm_text_has_no_waiting(vm1), "no waiting copy in vm")

	_check(gs.try_apply(EndTurnScript.make(0))["accepted"], "advance turn")
	var vm2: Dictionary = PlayerContactStripScr.compute_view_model(gs)
	var e2: Array = vm2.get("entries", []) as Array
	_check(e2.size() == 2, "still two entries")
	var a: Dictionary = e2[0] as Dictionary
	var b: Dictionary = e2[1] as Dictionary
	_check(not bool(a.get("is_current_turn", true)) and bool(b.get("is_current_turn", false)), "highlight moves to P1")
	_check(
		(b.get("accent_color", Color.BLACK) as Color).is_equal_approx(
			UnitNameplateViewScript.owner_nameplate_accent_color(1)
		),
		"P1 accent matches helper"
	)
	_check(_vm_text_has_no_waiting(vm2), "no waiting after end turn")

	if _any_fail:
		call_deferred("quit", 1)
	else:
		print("PASS %d/%d" % [_total, _total])
		call_deferred("quit", 0)


func _check(cond, message: String) -> void:
	_total = _total + 1
	if cond:
		return
	_any_fail = true
	var line: String = "FAIL: %s" % message
	print(line)
	push_error(line)
