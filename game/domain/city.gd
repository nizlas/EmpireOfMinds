# Domain city: id, owner, hex position, optional production project. Immutable RefCounted value.
# See docs/CITIES.md
class_name City
extends RefCounted

const HexCoordScript = preload("res://domain/hex_coord.gd")

var id: int
var owner_id: int
var position
var current_project
## Phase 5.1.15 — set by **FoundCity** (deterministic placeholders); preserved when scenarios rebuild city rows.
var city_name: String

func _init(p_id: int, p_owner_id: int, p_position, p_current_project = null, p_city_name: String = "") -> void:
	id = p_id
	owner_id = p_owner_id
	position = p_position
	city_name = str(p_city_name)
	if p_current_project == null:
		current_project = null
	elif typeof(p_current_project) == TYPE_DICTIONARY:
		current_project = (p_current_project as Dictionary).duplicate(true)
	else:
		current_project = null

func equals(other) -> bool:
	if other == null:
		return false
	return id == other.id

func equals_id(other_id: int) -> bool:
	return id == other_id
