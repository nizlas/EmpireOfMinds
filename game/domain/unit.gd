# Domain unit identity: id, owner, hex position, content type id, per-turn movement budget (**5.2.5**).
# type_id references rows in UnitDefinitions (docs/CONTENT_MODEL.md).
# See docs/UNITS.md
class_name Unit
extends RefCounted

const UnitDefinitionsScript = preload("res://domain/content/unit_definitions.gd")

var id: int
var owner_id: int
var position
var type_id: String
## Cached from **`UnitDefinitions`** at init — not deserialized independently in this slice.
var max_movement: int
var remaining_movement: int

## If **`p_remaining_movement < 0`**, **`remaining_movement`** is set to **`max_movement`** (fresh turn / new unit).
func _init(
	p_id: int,
	p_owner_id: int,
	p_position,
	p_type_id: String = "warrior",
	p_remaining_movement: int = -1,
) -> void:
	id = p_id
	owner_id = p_owner_id
	position = p_position
	type_id = p_type_id
	max_movement = UnitDefinitionsScript.max_movement_for_type(type_id)
	if p_remaining_movement < 0:
		remaining_movement = max_movement
	else:
		remaining_movement = clampi(p_remaining_movement, 0, max_movement)

func equals(other) -> bool:
	if other == null:
		return false
	return id == other.id

func equals_id(other_id: int) -> bool:
	return id == other_id
