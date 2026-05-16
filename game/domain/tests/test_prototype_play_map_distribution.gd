# Headless: structural acceptance for **`HexMap.make_prototype_play_map()`** (Phase 5.1.16g.2 **corrected** curated island).
extends SceneTree

const HexMapScript = preload("res://domain/hex_map.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const PrototypeTerrainFeaturesScript = preload("res://domain/prototype_terrain_features.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const FoundCityScript = preload("res://domain/actions/found_city.gd")
const UnitScript = preload("res://domain/unit.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const MapCameraScript = preload("res://presentation/map_camera.gd")
const MapPlaneProjectionScript = preload("res://presentation/map_plane_projection.gd")
const TileYieldOverlayViewScript = preload("res://presentation/tile_yield_overlay_view.gd")

const _AX_NEI: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(1, -1),
	Vector2i(0, -1),
	Vector2i(-1, 0),
	Vector2i(-1, 1),
	Vector2i(0, 1),
]

var _total = 0
var _any_fail = false


func _land_keys(m) -> Dictionary:
	var out: Dictionary = {}
	for hco in m.coords():
		if int(m.terrain_at(hco)) != HexMapScript.Terrain.WATER:
			out[Vector2i(hco.q, hco.r)] = true
	return out


func _min_axial_distance(a: Vector2i, b: Vector2i) -> int:
	return int(abs(a.x - b.x) + abs(a.y - b.y) + abs(a.x + a.y - b.x - b.y)) / 2


func _init() -> void:
	var m = HexMapScript.make_prototype_play_map()
	var c00 = HexCoordScript.new(0, 0)
	var cw = HexCoordScript.new(-1, 0)
	_check(m.terrain_at(c00) == HexMapScript.Terrain.PLAINS, "(0,0) PLAINS")
	_check(m.landform_at(c00) == HexMapScript.Landform.FLAT, "(0,0) FLAT")
	_check(m.terrain_at(cw) == HexMapScript.Terrain.WATER, "(-1,0) canonical WATER")

	var n_water = 0
	var n_land = 0
	var n_pf = 0
	var n_ph = 0
	var n_gf = 0
	var n_gh = 0
	var n_flat = 0
	var n_hill = 0
	for c in m.coords():
		var t: int = m.terrain_at(c)
		var lf: int = m.landform_at(c)
		if t == HexMapScript.Terrain.WATER:
			n_water += 1
		else:
			n_land += 1
			if lf == HexMapScript.Landform.FLAT:
				n_flat += 1
			else:
				n_hill += 1
		if t == HexMapScript.Terrain.PLAINS and lf == HexMapScript.Landform.FLAT:
			n_pf += 1
		elif t == HexMapScript.Terrain.PLAINS and lf == HexMapScript.Landform.HILLS:
			n_ph += 1
		elif t == HexMapScript.Terrain.GRASSLAND and lf == HexMapScript.Landform.FLAT:
			n_gf += 1
		elif t == HexMapScript.Terrain.GRASSLAND and lf == HexMapScript.Landform.HILLS:
			n_gh += 1

	var land_dict: Dictionary = _land_keys(m)

	_check(n_land >= 130 and n_water >= 400, "expanded island: land mass + axis-aligned sea shell")
	_check(m.size() >= 220 and m.size() <= 750, "total cell count (land + world-rect sea shell)")
	_check(n_pf >= 12 and n_ph >= 8 and n_gf >= 35 and n_gh >= 6, "mixed terrain: grass-forward balance + visible hills")
	_check(n_flat >= 35 and n_hill >= 18, "flat/hill variety on land")
	var n_plains: int = n_pf + n_ph
	var n_grass: int = n_gf + n_gh
	_check(n_grass > n_plains, "grass + grass-hills dominate over plains + plains-hills (anti-monotone)")
	_check(n_pf + n_ph < int(n_land * 0.52), "plains classes do not cover majority of land tiles")

	for lk in land_dict.keys():
		for dv in _AX_NEI:
			var nk := Vector2i(lk.x + dv.x, lk.y + dv.y)
			var hn = HexCoordScript.new(nk.x, nk.y)
			_check(m.has(hn), "island closure: every land neighbor exists on the finite map")
			_check(
				land_dict.has(nk) or int(m.terrain_at(hn)) == HexMapScript.Terrain.WATER,
				"full outer boundary: land touches only land or WATER (sea shell)"
			)

	var ne_core = Vector2i(10, 5)
	_check(land_dict.has(ne_core), "NE / upper-right extension is land (tongue spine)")
	_check(_min_axial_distance(ne_core, Vector2i(0, 0)) >= 8, "NE spine far enough from capital zone")

	var woods_comp_big: int = 0
	var woods_max: int = 0
	var wset: Dictionary = {}
	for wv in PrototypeTerrainFeaturesScript.PROTOTYPE_WOODS_HEXES:
		wset[wv] = true
	var wunseen: Dictionary = wset.duplicate()
	while wunseen.size() > 0:
		var wseed: Vector2i = wunseen.keys()[0]
		var wstack: Array[Vector2i] = [wseed]
		var wcomp: int = 0
		while wstack.size() > 0:
			var wv2: Vector2i = wstack.pop_back()
			if not wunseen.has(wv2):
				continue
			wunseen.erase(wv2)
			wcomp += 1
			var wi: int = 0
			while wi < 6:
				var wn := Vector2i(wv2.x + _AX_NEI[wi].x, wv2.y + _AX_NEI[wi].y)
				if wset.has(wn) and wunseen.has(wn):
					wstack.append(wn)
				wi += 1
		if wcomp > woods_max:
			woods_max = wcomp
		if wcomp >= 4:
			woods_comp_big += 1
	_check(woods_comp_big >= 3, "prototype woods: at least three separable clusters at size ≥4")
	_check(woods_max <= 9, "woods: largest connected patch capped (decoration fragmentation)")
	_check(
		woods_max * 4 <= wset.size() * 3,
		"woods: no single connected patch exceeds ~75% of listed woods (anti-mega-blob)"
	)

	var land_w_water_nei: int = 0
	var water_w_land_nei: int = 0
	for lk in land_dict.keys():
		var qi: int = lk.x
		var ri: int = lk.y
		for dv in _AX_NEI:
			var wk := Vector2i(qi + dv.x, ri + dv.y)
			if m.has(HexCoordScript.new(wk.x, wk.y)):
				if int(m.terrain_at(HexCoordScript.new(wk.x, wk.y))) == HexMapScript.Terrain.WATER:
					land_w_water_nei += 1
	for wc in m.coords():
		if int(m.terrain_at(wc)) != HexMapScript.Terrain.WATER:
			continue
		for dv in _AX_NEI:
			var lk2 := Vector2i(wc.q + dv.x, wc.r + dv.y)
			if land_dict.has(lk2):
				water_w_land_nei += 1
	_check(land_w_water_nei >= 24, "coast: many land cells border water")
	_check(water_w_land_nei >= 24, "coast: many water cells border land")

	var wn: int = 0
	for v in PrototypeTerrainFeaturesScript.PROTOTYPE_WOODS_HEXES:
		var wh = HexCoordScript.new(v.x, v.y)
		_check(m.has(wh), "woods hex on map")
		_check(int(m.terrain_at(wh)) != HexMapScript.Terrain.WATER, "woods not on WATER")
		_check(int(m.terrain_at(wh)) == HexMapScript.Terrain.PLAINS, "prototype woods stay PLAINS terrain")
		if m.has_woods(wh):
			wn += 1
	_check(wn == PrototypeTerrainFeaturesScript.PROTOTYPE_WOODS_HEXES.size(), "woods overlay count")

	var woods_west: int = 0
	for wvx in PrototypeTerrainFeaturesScript.PROTOTYPE_WOODS_HEXES:
		if wvx.x <= 0:
			woods_west += 1
	_check(woods_west >= 10, "west-of-axis (q≤0) prototype woods presence (NW / left-half polish)")

	var ne_tongue_site := Vector2i(12, 6)
	_check(land_dict.has(ne_tongue_site), "NE land tongue contains land")
	_check(_min_axial_distance(ne_tongue_site, Vector2i(0, 0)) >= 10, "NE tongue anchored away from origin")

	var sites: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(-3, -2),
		Vector2i(8, -2),
		Vector2i(4, -2),
		Vector2i(-5, 0),
		Vector2i(-1, 3),
		Vector2i(11, 6),
		Vector2i(7, 7),
	]
	var si: int = 0
	while si < sites.size():
		var s: Vector2i = sites[si]
		var sh = HexCoordScript.new(s.x, s.y)
		_check(m.has(sh), "planned site on map")
		_check(int(m.terrain_at(sh)) != HexMapScript.Terrain.WATER, "planned site not water")
		si += 1
	var cap_xy := Vector2i(0, 0)
	var sj: int = 0
	while sj < sites.size():
		var s2: Vector2i = sites[sj]
		if s2 != cap_xy:
			_check(
				_min_axial_distance(cap_xy, s2) >= 3,
				"each expansion site is far enough from the capital candidate for ring-1 territory"
			)
		sj += 1

	var pm = m
	var u4 = [
		UnitScript.new(1, 0, HexCoordScript.new(0, 0), "settler"),
		UnitScript.new(4, 0, HexCoordScript.new(4, -2), "settler"),
		UnitScript.new(5, 0, HexCoordScript.new(8, -2), "settler"),
		UnitScript.new(6, 0, HexCoordScript.new(11, 6), "settler"),
	]
	var sc4 = ScenarioScript.new(pm, u4, [], 500, 300)
	var r1 = FoundCityScript.apply(sc4, FoundCityScript.make(0, 1, 0, 0))
	var r2 = FoundCityScript.apply(r1, FoundCityScript.make(0, 4, 4, -2))
	var r3 = FoundCityScript.apply(r2, FoundCityScript.make(0, 5, 8, -2))
	var r4 = FoundCityScript.apply(r3, FoundCityScript.make(0, 6, 11, 6))
	_check(r4.peek_next_city_id() == 304, "four cities founded in planned order without tile_already_owned")

	var coastal_center = HexCoordScript.new(-1, 3)
	_check(m.has(coastal_center), "coastal site hex")
	var sc_w = ScenarioScript.new(
		pm,
		[UnitScript.new(50, 0, coastal_center, "settler")],
		[],
		600,
		400
	)
	var fcw = FoundCityScript.apply(sc_w, FoundCityScript.make(0, 50, -1, 3))
	var cid = fcw.peek_next_city_id() - 1
	var coastal_city = fcw.city_by_id(cid)
	_check(coastal_city != null, "coastal city exists")
	var owns_water: bool = false
	var oi: int = 0
	while oi < coastal_city.owned_tiles.size():
		var ot = coastal_city.owned_tiles[oi]
		if int(m.terrain_at(ot)) == HexMapScript.Terrain.WATER:
			owns_water = true
			break
		oi += 1
	_check(owns_water, "at least one coastal founded site claims WATER in owned_tiles")

	var scen_proto = ScenarioScript.make_prototype_play_scenario()
	var layout = HexLayoutScript.new()
	var cam = MapCameraScript.new()
	cam.projection = MapPlaneProjectionScript.new()
	cam.vanishing_pres = Vector2(400.0, 300.0)
	var entries = TileYieldOverlayViewScript.compute_overlay_entries(scen_proto, layout, cam)
	_check(entries.size() > m.size() / 2, "yield overlay entries for most cells")

	var tr = scen_proto.lightning_tree_hex
	_check(tr != null, "prototype tree set")
	_check(int(m.terrain_at(tr)) != HexMapScript.Terrain.WATER, "tree not water")
	_check(not m.has_woods(tr), "tree not woods")

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
	var line = "FAIL: %s" % message
	print(line)
	push_error(line)
