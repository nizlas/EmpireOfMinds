# Headless: **CityViewState** transitions only (presentation **RefCounted**).
# Usage: godot --headless --path game -s res://presentation/tests/test_city_view_state.gd
extends SceneTree

const CityViewStateScript = preload("res://presentation/city_view_state.gd")

var _total := 0
var _any_fail := false


func _init() -> void:
	var fp = FileAccess.open("res://presentation/city_view_state.gd", FileAccess.READ)
	_check(fp != null, "city_view_state.gd readable")
	if fp != null:
		var txt = fp.get_as_text().to_lower()
		fp.close()
		_check(txt.find("legal_actions") < 0, "no legal_actions")
		_check(txt.find("try_apply") < 0, "no try_apply substring in source")

	var s = CityViewStateScript.new()
	_check(not s.is_planning(), "default NORMAL")
	s.enter_planning()
	_check(s.is_planning(), "enter_planning -> PLANNING")
	s.enter_planning()
	_check(s.is_planning(), "enter_planning idempotent")
	s.exit_planning()
	_check(not s.is_planning(), "exit_planning -> NORMAL")
	s.exit_planning()
	_check(not s.is_planning(), "exit_planning idempotent")
	s.enter_planning()
	_check(s.is_planning(), "re-enter PLANNING")
	s.reset_to_normal()
	_check(not s.is_planning(), "reset_to_normal -> NORMAL")
	s.reset_to_normal()
	_check(not s.is_planning(), "reset_to_normal idempotent")

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
