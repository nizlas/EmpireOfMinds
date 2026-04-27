# Domain unit identity: id, owner, hex position. Immutable in Phase 1.4; no actions or movement here.
# See docs/UNITS.md
class_name Unit
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
