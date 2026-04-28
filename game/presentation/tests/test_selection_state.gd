# Headless: godot --headless --path game -s res://presentation/tests/test_selection_state.gd
extends SceneTree
const SelectionStateScript = preload("res://presentation/selection_state.gd")

var _total = 0
var _any_fail = false

func _init() -> void:
	var s = SelectionStateScript.new()
	_check(s.is_empty(), "new SelectionState should be empty")
	_check(s.unit_id == SelectionStateScript.NONE, "new unit_id should be NONE")
	s.select(7)
	_check(not s.is_empty(), "after select, not empty")
	_check(s.unit_id == 7, "unit_id should be 7")
	s.clear()
	_check(s.is_empty(), "after clear, empty again")
	_check(not s.equals(null), "equals null should be false")
	var a = SelectionStateScript.new()
	var b = SelectionStateScript.new()
	a.select(5)
	b.select(5)
	_check(a.equals(b), "same id should equal")
	b.select(6)
	_check(not a.equals(b), "different id should not equal")
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
