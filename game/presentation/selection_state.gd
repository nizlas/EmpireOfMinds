# Presentation-only: focused unit and/or city for UI. Not authoritative game state.
# See docs/SELECTION.md
class_name SelectionState
extends RefCounted

const NONE: int = -1
var unit_id: int = NONE
var city_id: int = NONE


func select(p_unit_id: int) -> void:
	unit_id = p_unit_id
	city_id = NONE


func select_city(p_city_id: int) -> void:
	city_id = p_city_id
	unit_id = NONE


func clear_unit() -> void:
	unit_id = NONE


func clear_city() -> void:
	city_id = NONE


func clear() -> void:
	unit_id = NONE
	city_id = NONE


func has_city() -> bool:
	return city_id != NONE


## True when no unit is selected (city-only selection still returns true).
func is_empty() -> bool:
	return unit_id == NONE


func equals(other) -> bool:
	if other == null:
		return false
	return unit_id == other.unit_id and city_id == other.city_id
