# Headless: godot --headless --path game -s res://presentation/tests/test_selection_state.gd
extends SceneTree
const SelectionStateScript = preload("res://presentation/selection_state.gd")

var _total = 0
var _any_fail = false

func _init() -> void:
	var s = SelectionStateScript.new()
	_check(s.is_empty(), "new SelectionState should be empty (no unit)")
	_check(s.unit_id == SelectionStateScript.NONE, "new unit_id should be NONE")
	_check(s.city_id == SelectionStateScript.NONE, "new city_id should be NONE")
	_check(not s.has_city(), "new state has no city")
	s.select(7)
	_check(not s.is_empty(), "after select, not empty")
	_check(s.unit_id == 7, "unit_id should be 7")
	_check(not s.has_city(), "unit select clears city focus")
	s.select_city(3)
	_check(s.is_empty(), "city-only selection is empty for unit queries")
	_check(s.has_city(), "city focus set")
	_check(s.city_id == 3, "city_id should be 3")
	_check(s.unit_id == SelectionStateScript.NONE, "city select clears unit")
	s.clear_unit()
	_check(s.has_city(), "clear_unit keeps city")
	s.select(5)
	_check(s.unit_id == 5 and not s.has_city(), "select unit clears city")
	s.select_city(9)
	s.clear_city()
	_check(not s.has_city(), "clear_city")
	_check(s.city_id == SelectionStateScript.NONE, "city id none")
	s.clear()
	_check(s.is_empty(), "after clear, empty again")
	_check(not s.has_city(), "clear drops city")
	_check(not s.equals(null), "equals null should be false")
	var a = SelectionStateScript.new()
	var b = SelectionStateScript.new()
	a.select(5)
	b.select(5)
	_check(a.equals(b), "same unit should equal")
	b.select(6)
	_check(not a.equals(b), "different unit should not equal")
	a.clear()
	b.clear()
	a.select_city(2)
	b.select_city(2)
	_check(a.equals(b), "same city should equal")
	b.select_city(4)
	_check(not a.equals(b), "different city should not equal")
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
