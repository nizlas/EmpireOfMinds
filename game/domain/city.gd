# Domain city: id, owner, hex position. Immutable RefCounted value; no gameplay actions in Phase 2.1.
# See docs/CITIES.md
class_name City
extends RefCounted

const HexCoordScript = preload("res://domain/hex_coord.gd")

var id: int
var owner_id: int
var position

func _init(p_id: int, p_owner_id: int, p_position) -> void:
	id = p_id
	owner_id = p_owner_id
	position = p_position

func equals(other) -> bool:
	if other == null:
		return false
	return id == other.id

func equals_id(other_id: int) -> bool:
	return id == other_id
