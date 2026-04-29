# Domain unit identity: id, owner, hex position, content type id. Immutable in Phase 1.4; no actions or movement here.
# type_id references rows in UnitDefinitions (docs/CONTENT_MODEL.md).
# See docs/UNITS.md
class_name Unit
extends RefCounted

const HexCoordScript = preload("res://domain/hex_coord.gd")

var id: int
var owner_id: int
var position
var type_id: String

func _init(p_id: int, p_owner_id: int, p_position, p_type_id: String = "warrior") -> void:
	id = p_id
	owner_id = p_owner_id
	position = p_position
	type_id = p_type_id

func equals(other) -> bool:
	if other == null:
		return false
	return id == other.id

func equals_id(other_id: int) -> bool:
	return id == other_id
