# Headless: prototype map **5.2.4l** — real WATER shell from axis-aligned world rect (no presentation filler).
extends SceneTree

const HexMapScript = preload("res://domain/hex_map.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const GameStateScript = preload("res://domain/game_state.gd")

const _PAD_STEPS: int = 3
const _HEX_SIZE: float = 128.0
const _STEP_X: float = sqrt(3.0) * _HEX_SIZE
const _STEP_Y: float = 1.5 * _HEX_SIZE
const _BLEED: float = _HEX_SIZE * 1.05

var _total: int = 0
var _any_fail: bool = false


func _hex_aabb(q: int, r: int) -> Rect2:
	return HexMapScript._proto_hex_world_aabb_xy(q, r)


func _merge_map_world_rect(m) -> Rect2:
	var first: bool = true
	var acc: Rect2 = Rect2()
	for c in m.coords():
		var hb: Rect2 = _hex_aabb(int(c.q), int(c.r))
		if first:
			acc = hb
			first = false
		else:
			acc = acc.merge(hb)
	return acc


func _snapshot_terrain(m) -> Dictionary:
	var d: Dictionary = {}
	for c in m.coords():
		var k := Vector2i(int(c.q), int(c.r))
		d[k] = Vector3i(
			int(m.terrain_at(c)),
			int(m.landform_at(c)),
			1 if m.has_woods(c) else 0,
		)
	return d


func _init() -> void:
	var land: Dictionary = HexMapScript.prototype_play_land_key_set()
	var outer: Rect2 = HexMapScript.prototype_play_target_sea_world_rect()
	var inner_land: Rect2 = HexMapScript._proto_land_world_rect(land)

	var m1 = HexMapScript.make_prototype_play_map()
	var m2 = HexMapScript.make_prototype_play_map()
	var snap1: Dictionary = _snapshot_terrain(m1)
	var snap2: Dictionary = _snapshot_terrain(m2)
	_check(snap1 == snap2, "deterministic prototype map (full terrain snapshot)")

	var merged: Rect2 = _merge_map_world_rect(m1)
	_check(merged.grow(_BLEED).encloses(outer), "map world AABB covers target sea rectangle (hex bleed margin)")

	var expad_x: float = float(_PAD_STEPS) * _STEP_X
	var expad_y: float = float(_PAD_STEPS) * _STEP_Y
	_check(
		is_equal_approx(inner_land.position.x - outer.position.x, expad_x),
		"target rect: west padding matches N hex steps on X",
	)
	_check(
		is_equal_approx(inner_land.position.y - outer.position.y, expad_y),
		"target rect: north padding matches N hex steps on Y",
	)

	var ml: float = merged.position.x
	var mr: float = merged.position.x + merged.size.x
	var mt: float = merged.position.y
	var mb: float = merged.position.y + merged.size.y
	var il: float = inner_land.position.x
	var ir: float = inner_land.position.x + inner_land.size.x
	var it: float = inner_land.position.y
	var ib: float = inner_land.position.y + inner_land.size.y
	var want_lo: float = 0.72 * expad_x
	var want_hi: float = 1.35 * expad_x
	var pad_w: float = il - ml
	var pad_e: float = mr - ir
	var pad_n: float = it - mt
	var pad_s: float = mb - ib
	_check(pad_w >= want_lo and pad_w <= want_hi, "world padding ~N steps west of land (tolerance)")
	_check(pad_e >= want_lo and pad_e <= want_hi, "world padding ~N steps east",
	)
	_check(pad_n >= 0.72 * expad_y and pad_n <= 1.35 * expad_y, "world padding ~N steps north",
	)
	_check(pad_s >= 0.72 * expad_y and pad_s <= 1.35 * expad_y, "world padding ~N steps south",
	)

	var bad_land: int = 0
	for lk in land.keys():
		var h = HexCoordScript.new(lk.x, lk.y)
		if not m1.has(h) or int(m1.terrain_at(h)) == HexMapScript.Terrain.WATER:
			bad_land += 1
	_check(bad_land == 0, "all curated land keys present and non-WATER")

	var bad_w: int = 0
	var bad_lf: int = 0
	var bad_wo: int = 0
	for c in m1.coords():
		var kk := Vector2i(int(c.q), int(c.r))
		if land.has(kk):
			continue
		if int(m1.terrain_at(c)) != HexMapScript.Terrain.WATER:
			bad_w += 1
		if int(m1.landform_at(c)) != HexMapScript.Landform.FLAT:
			bad_lf += 1
		if m1.has_woods(c):
			bad_wo += 1
	_check(bad_w == 0, "non-land cells are WATER")
	_check(bad_lf == 0, "water shell landform FLAT")
	_check(bad_wo == 0, "no woods on shell water")

	var scen = ScenarioScript.make_prototype_play_scenario()
	var bad_u: int = 0
	var uu = 0
	while uu < scen.units().size():
		var u = scen.units()[uu]
		var uk := Vector2i(int(u.position.q), int(u.position.r))
		if not land.has(uk):
			bad_u += 1
		uu += 1
	_check(bad_u == 0, "prototype units stay on curated land keys")

	var gs = GameStateScript.new(scen)
	_check(gs.visibility_state != null, "visibility state on prototype GameState")
	var wc: HexCoordScript = HexCoordScript.new(-20, 2)
	if scen.map.has(wc):
		var ex0: bool = gs.visibility_state.is_explored(0, wc)
		var ex1: bool = gs.visibility_state.is_explored(1, wc)
		_check(ex0 == ex1, "deep water exploration symmetric for players when present")

	if _any_fail:
		call_deferred("quit", 1)
	else:
		print("PASS %d/%d" % [_total, _total])
		call_deferred("quit", 0)


func _check(cond: bool, message: String) -> void:
	_total += 1
	if cond:
		return
	_any_fail = true
	var line: String = "FAIL: %s" % message
	print(line)
	push_error(line)
