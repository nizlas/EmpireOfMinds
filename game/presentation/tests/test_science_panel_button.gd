# Headless: godot --headless --path game -s res://presentation/tests/test_science_panel_button.gd
extends SceneTree

const GameStateScript = preload("res://domain/game_state.gd")
const SciencePanelScript = preload("res://presentation/science_panel.gd")
const SetCurrentResearchScript = preload("res://domain/actions/set_current_research.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var panel = SciencePanelScript.new()
	get_root().add_child(panel)
	var gs = GameStateScript.make_tiny_test_state()
	panel.game_state = gs
	panel.refresh()
	_check(panel._available_container.get_child_count() >= 4, "buttons built")
	_check(panel._locked_container.get_child_count() > 0, "locked rows built")
	var li0 = 0
	while li0 < panel._locked_container.get_child_count():
		_check(panel._locked_container.get_child(li0) is Label, "locked row is Label not Button")
		li0 = li0 + 1
	var i = 0
	var stone_btn: Button = null
	while i < panel._available_container.get_child_count():
		var c = panel._available_container.get_child(i)
		if c is Button and str(c.get_meta("science_id", "")) == "stone_tools":
			stone_btn = c as Button
			break
		i = i + 1
	_check(stone_btn != null, "found stone_tools button")
	stone_btn.pressed.emit()
	_check(gs.progress_state.current_research_for(0) == "stone_tools", "state pinned stone_tools")
	var saw = false
	var li = 0
	while li < gs.log.size():
		var e = gs.log.get_entry(li) as Dictionary
		if (
			str(e.get("action_type", "")) == SetCurrentResearchScript.ACTION_TYPE
			and str(e.get("result", "")) == "accepted"
		):
			saw = true
			_check(str(e.get("science_id", "")) == "stone_tools", "log science_id")
		li = li + 1
	_check(saw, "log has set_current_research accepted")
	panel.refresh()
	_check(panel._target_label.text.begins_with("Researching: "), "panel refresh ok")
	panel.queue_free()
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
