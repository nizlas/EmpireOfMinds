# C14d-4f: cloud hides redundant TurnStatusPanel; chips + waiting text remain.
extends SceneTree

const TurnOwnershipScript = preload("res://cloud/cloud_turn_ownership.gd")
const TurnStatusPanelScript = preload("res://presentation/turn_status_panel.gd")
const PlayerContactStripScript = preload("res://presentation/player_contact_strip.gd")
const PlaytestPlayerDisplayScript = preload("res://presentation/playtest_player_display.gd")

const GameStateScript = preload("res://domain/game_state.gd")
var _total: int = 0


func _init() -> void:
	var failed: int = _run()
	if failed == 0:
		print("PASS %d/%d" % [_total, _total])
	else:
		printerr("FAIL %d assertion(s) failed" % failed)
	quit(failed)


func _check(ok: bool, msg: String) -> int:
	_total += 1
	if ok:
		return 0
	printerr("FAIL: %s" % msg)
	return 1


func _make_gs() -> Variant:
	return GameStateScript.make_tiny_test_state()


func _run() -> int:
	var failed: int = 0
	failed += _test_turn_status_panel_visibility_policy()
	failed += _test_waiting_text_and_chips_unchanged()
	failed += _test_hotseat_panel_view_model_unchanged()
	return failed


func _test_turn_status_panel_visibility_policy() -> int:
	var failed: int = 0
	failed += _check(
		not TurnOwnershipScript.should_show_turn_status_panel(true),
		"cloud suppresses TurnStatusPanel",
	)
	failed += _check(
		TurnOwnershipScript.should_show_turn_status_panel(false),
		"local hotseat shows TurnStatusPanel",
	)
	return failed


func _test_waiting_text_and_chips_unchanged() -> int:
	var failed: int = 0
	var gs = _make_gs()
	failed += _check(
		TurnOwnershipScript.waiting_status_text(true, 1, gs.turn_state)
		== TurnOwnershipScript.WAITING_STATUS_TEXT,
		"waiting client keeps small status text",
	)
	failed += _check(
		TurnOwnershipScript.waiting_status_text(true, 0, gs.turn_state).is_empty(),
		"active cloud seat has no waiting line",
	)
	var strip_vm: Dictionary = PlayerContactStripScript.compute_view_model(gs)
	var entries: Array = strip_vm.get("entries", []) as Array
	failed += _check(entries.size() >= 2, "player chips still render entries")
	var cur_id: int = int(gs.turn_state.current_player_id())
	var found_current: bool = false
	var ei: int = 0
	while ei < entries.size():
		var ed: Dictionary = entries[ei] as Dictionary
		if bool(ed.get("is_current_turn", false)):
			found_current = true
			failed += _check(
				int(ed.get("player_id", -1)) == cur_id,
				"current player chip highlighted",
			)
		ei += 1
	failed += _check(found_current, "one chip marked current turn")
	var pname: String = PlaytestPlayerDisplayScript.display_name_for_player_id(cur_id)
	failed += _check(not pname.is_empty(), "chip label uses display name not id")
	failed += _check(not pname.contains("st_"), "chip label has no token")
	failed += _check(not pname.contains("http"), "chip label has no url")
	return failed


func _test_hotseat_panel_view_model_unchanged() -> int:
	var failed: int = 0
	var gs = _make_gs()
	var vm: Dictionary = TurnStatusPanelScript.compute_view_model(gs, 0)
	failed += _check(str(vm.get("title", "")).contains("'s turn"), "hotseat panel title format")
	failed += _check(str(vm.get("detail", "")).begins_with("Turn "), "hotseat panel turn detail")
	return failed
