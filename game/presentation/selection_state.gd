# Presentation-only: which unit id the player has focused for queries. Not authoritative game state.
# See docs/SELECTION.md
class_name SelectionState
extends RefCounted

const NONE: int = -1
var unit_id: int = NONE

func select(p_unit_id: int) -> void:
	unit_id = p_unit_id

func clear() -> void:
	unit_id = NONE

func is_empty() -> bool:
	return unit_id == NONE

func equals(other) -> bool:
	if other == null:
		return false
	return unit_id == other.unit_id
