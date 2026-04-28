# Append-only log of accepted actions. Stores deep-copied Dictionaries so callers cannot mutate history.
# See docs/ACTIONS.md
class_name ActionLog
extends RefCounted

var _entries: Array

func _init() -> void:
	_entries = []

func append(entry: Dictionary) -> int:
	var idx = _entries.size()
	var copy = entry.duplicate(true)
	copy["index"] = idx
	_entries.append(copy)
	return idx

func size() -> int:
	return _entries.size()

func get_entry(i: int) -> Dictionary:
	return (_entries[i] as Dictionary).duplicate(true)

func entries() -> Array:
	var out = []
	var j = 0
	while j < _entries.size():
		out.append((_entries[j] as Dictionary).duplicate(true))
		j = j + 1
	return out
