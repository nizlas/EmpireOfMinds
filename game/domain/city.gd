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
## Phase 5.1.16c — first city per owner is capital (Palace building); preserved on production rebuilds.
var is_capital: bool
## Building id strings (v0: **FoundCity** adds **palace** to the capital only).
var building_ids: Array
## Phase 5.1.16g — territory: hexes this city owns (center first). Not culture/border growth.
var owned_tiles: Array

func _init(
	p_id: int,
	p_owner_id: int,
	p_position,
	p_current_project = null,
	p_city_name: String = "",
	p_is_capital: bool = false,
	p_building_ids = null,
	p_owned_tiles = null,
) -> void:
	id = p_id
	owner_id = p_owner_id
	position = p_position
	is_capital = p_is_capital
	city_name = str(p_city_name)
	building_ids = []
	if p_building_ids != null and typeof(p_building_ids) == TYPE_ARRAY:
		var ba: Array = p_building_ids as Array
		var bi: int = 0
		while bi < ba.size():
			building_ids.append(str(ba[bi]))
			bi = bi + 1
	if p_current_project == null:
		current_project = null
	elif typeof(p_current_project) == TYPE_DICTIONARY:
		current_project = (p_current_project as Dictionary).duplicate(true)
	else:
		current_project = null

	owned_tiles = []
	if p_owned_tiles == null or typeof(p_owned_tiles) != TYPE_ARRAY or (p_owned_tiles as Array).is_empty():
		owned_tiles.append(HexCoordScript.new(position.q, position.r))
	else:
		var seen: Dictionary = {}
		var center_k := Vector2i(position.q, position.r)
		seen[center_k] = true
		owned_tiles.append(HexCoordScript.new(position.q, position.r))
		var ot_a: Array = p_owned_tiles as Array
		var oi: int = 0
		while oi < ot_a.size():
			var oc = ot_a[oi]
			oi = oi + 1
			if oc == null or typeof(oc) != TYPE_OBJECT or not (oc is HexCoord):
				continue
			var ok := Vector2i(oc.q, oc.r)
			if seen.has(ok):
				continue
			seen[ok] = true
			owned_tiles.append(HexCoordScript.new(oc.q, oc.r))

func equals(other) -> bool:
	if other == null:
		return false
	return id == other.id

func equals_id(other_id: int) -> bool:
	return id == other_id
