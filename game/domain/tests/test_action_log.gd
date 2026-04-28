# Headless: godot --headless --path game -s res://domain/tests/test_action_log.gd
extends SceneTree
const ActionLogScript = preload("res://domain/action_log.gd")

var _total = 0
var _any_fail = false

func _init() -> void:
	var log = ActionLogScript.new()
	_check(log.size() == 0, "new log empty")
	_check(log.entries().size() == 0, "entries empty")
	var i0 = log.append({"schema_version": 1, "action_type": "move_unit", "unit_id": 1})
	_check(i0 == 0, "first index 0")
	_check(log.size() == 1, "size 1")
	var g0 = log.get_entry(0)
	_check(g0["unit_id"] == 1, "get_entry unit_id")
	_check(g0["index"] == 0, "index field set")
	var e1 = log.entries()
	_check(e1.size() == 1, "entries size")
	g0["unit_id"] = 999
	var g1 = log.get_entry(0)
	_check(g1["unit_id"] == 1, "mutating copy does not change stored entry")
	var arr = log.entries()
	arr.clear()
	_check(log.size() == 1, "mutating entries() duplicate does not shrink log")
	var entry2 = {"schema_version": 1, "action_type": "move_unit", "unit_id": 2}
	var i1 = log.append(entry2)
	_check(i1 == 1, "second index 1")
	_check(log.get_entry(1)["index"] == 1, "second has index 1")
	_check(log.size() == 2, "size 2")
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
