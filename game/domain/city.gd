# Domain city: id, owner, hex position, optional production project. Immutable RefCounted value.
# See docs/CITIES.md
class_name City
extends RefCounted

const HexCoordScript = preload("res://domain/hex_coord.gd")

## **`"auto"`** — deterministic auto-worked tiles up to **`population`** (ignores **`manual_worked_tiles`**). **`"manual"`** — only valid **`manual_worked_tiles`** count; empty list = citizens idle on **worked** layer (`SetCityWorkedTiles` enters **manual**).
const WORKED_TILES_MODE_AUTO := "auto"
const WORKED_TILES_MODE_MANUAL := "manual"

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
## Phase 5.1.17a — population selects extra auto-worked territory tiles (domain embryo; no growth UI).
var population: int
## Phase 5.1.18a — explicit worked tiles (fresh **HexCoord** rows); meaning depends on **`worked_tiles_mode`**.
var manual_worked_tiles: Array
## Phase 5.1.19b — food banked toward growth (**FoodGrowthTick**); clamped **>= 0**.
var food_stored: int
## **`WORKED_TILES_MODE_AUTO`** (default) vs **`WORKED_TILES_MODE_MANUAL`** after **`SetCityWorkedTiles`**.
var worked_tiles_mode: String

func _init(
	p_id: int,
	p_owner_id: int,
	p_position,
	p_current_project = null,
	p_city_name: String = "",
	p_is_capital: bool = false,
	p_building_ids = null,
	p_owned_tiles = null,
	p_population: int = 1,
	p_manual_worked_tiles = null,
	p_food_stored: int = 0,
	p_worked_tiles_mode: String = WORKED_TILES_MODE_AUTO,
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

	population = maxi(0, int(p_population))

	manual_worked_tiles = []
	if p_manual_worked_tiles != null and typeof(p_manual_worked_tiles) == TYPE_ARRAY:
		var owned_keys: Dictionary = {}
		var oki: int = 0
		while oki < owned_tiles.size():
			var oh = owned_tiles[oki]
			owned_keys[Vector2i(oh.q, oh.r)] = true
			oki += 1
		var seen_manual: Dictionary = {}
		var msrc: Array = p_manual_worked_tiles as Array
		var mi: int = 0
		while mi < msrc.size():
			var ment = msrc[mi]
			mi += 1
			var mq: int = 0
			var mr: int = 0
			if ment != null and typeof(ment) == TYPE_OBJECT and ment is HexCoord:
				mq = ment.q
				mr = ment.r
			elif ment != null and typeof(ment) == TYPE_ARRAY:
				var marr = ment as Array
				if marr.size() != 2 or typeof(marr[0]) != TYPE_INT or typeof(marr[1]) != TYPE_INT:
					continue
				mq = marr[0] as int
				mr = marr[1] as int
			else:
				continue
			if mq == position.q and mr == position.r:
				continue
			var mk := Vector2i(mq, mr)
			if not owned_keys.has(mk):
				continue
			if seen_manual.has(mk):
				continue
			seen_manual[mk] = true
			manual_worked_tiles.append(HexCoordScript.new(mq, mr))

	food_stored = maxi(0, int(p_food_stored))
	var wm_raw: String = str(p_worked_tiles_mode)
	if wm_raw == WORKED_TILES_MODE_MANUAL:
		worked_tiles_mode = WORKED_TILES_MODE_MANUAL
	else:
		worked_tiles_mode = WORKED_TILES_MODE_AUTO

func equals(other) -> bool:
	if other == null:
		return false
	return id == other.id

func equals_id(other_id: int) -> bool:
	return id == other_id
