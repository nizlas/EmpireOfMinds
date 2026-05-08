# Headless: godot --headless --path game -s res://presentation/tests/test_map_view_draw.gd
extends SceneTree
const MapViewScript = preload("res://presentation/map_view.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const HexMapScript = preload("res://domain/hex_map.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")

var _total = 0
var _any_fail = false


func _solid_tex_c(col: Color) -> ImageTexture:
	var img: Image = Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(col)
	return ImageTexture.create_from_image(img)


func _init() -> void:
	var m = HexMapScript.make_tiny_test_map()
	var layout = HexLayoutScript.new()
	var items = MapViewScript.compute_draw_items(m, layout)
	_check(
		items.size() == m.size(),
		"items.size() should match map.size()"
	)
	var cl = m.coords()
	_check(
		items.size() == cl.size(),
		"items.size() should match coords().size()"
	)
	var cidx = 0
	while cidx < cl.size():
		var dc = cl[cidx]
		var found = 0
		var t = 0
		while t < items.size():
			var it1 = items[t]
			if it1["coord"].equals(dc):
				found = found + 1
			t = t + 1
		_check(
			found == 1,
			"each coord from domain should appear exactly once in items"
		)
		cidx = cidx + 1
	var u = 0
	while u < items.size():
		var it2 = items[u]
		_check(
			m.has(it2["coord"]),
			"draw item coord must be on the map"
		)
		u = u + 1
	var c00: Color
	var cW: Color
	var got00 = false
	var gotW = false
	var v = 0
	while v < items.size():
		var it3 = items[v]
		if it3["coord"].equals(HexCoordScript.new(0, 0)):
			c00 = it3["color"]
			got00 = true
		if it3["coord"].equals(HexCoordScript.new(-1, 0)):
			cW = it3["color"]
			gotW = true
		v = v + 1
	_check(got00, "items should include coord (0,0)")
	_check(gotW, "items should include coord (-1,0)")
	_check(c00 != cW, "WATER and PLAINS cells should have different draw colors")
	var w = 0
	while w < items.size():
		var it4 = items[w]
		_check(it4.has("landform"), "draw item should include landform")
		_check(
			it4["corners"].size() == 6,
			"each hex should have 6 corner points"
		)
		var coord = it4["coord"]
		var wexp = layout.hex_to_world(coord.q, coord.r)
		_check(
			(it4["world"] as Vector2).is_equal_approx(wexp),
			"item world should match layout.hex_to_world for that coord"
		)
		w = w + 1
	var mv_defaults = MapViewScript.new()
	_check(
		is_equal_approx(mv_defaults.hills_overlay_scale, 1.0),
		"MapView hills_overlay_scale export default 1.0"
	)
	_check(
		is_equal_approx(mv_defaults.hills_overlay_uv_zoom, 1.24),
		"MapView hills_overlay_uv_zoom export default 1.24"
	)
	_check(
		is_equal_approx(mv_defaults.plains_hills_overlay_opacity, 0.45),
		"MapView plains_hills_overlay_opacity export default 0.45"
	)
	_check(
		is_equal_approx(mv_defaults.grassland_hills_overlay_opacity, 0.40),
		"MapView grassland_hills_overlay_opacity export default 0.40"
	)
	_check(not mv_defaults.debug_draw_hills_overlay_bounds, "debug_draw_hills_overlay_bounds default false")
	_check(not mv_defaults.debug_force_hills_overlay_extreme, "debug_force_hills_overlay_extreme default false")
	_check(
		is_equal_approx(
			MapViewScript._hills_overlay_base_opacity_for_terrain(
				HexMapScript.Terrain.PLAINS, 0.45, 0.40
			),
			0.45
		),
		"_hills_overlay_base_opacity_for_terrain PLAINS"
	)
	_check(
		is_equal_approx(
			MapViewScript._hills_overlay_base_opacity_for_terrain(
				HexMapScript.Terrain.GRASSLAND, 0.45, 0.40
			),
			0.40
		),
		"_hills_overlay_base_opacity_for_terrain GRASSLAND"
	)
	_check(
		MapViewScript._hills_overlay_base_opacity_for_terrain(
			HexMapScript.Terrain.WATER, 0.45, 0.40
		)
		<= 0.001,
		"_hills_overlay_base_opacity_for_terrain non-hill terrains 0"
	)
	var tun_norm: Vector3 = MapViewScript._hills_overlay_effective_tuning(false, 1.0, 1.24, 0.45)
	_check(is_equal_approx(tun_norm.x, 1.0), "_hills_overlay_effective_tuning preserves scale when not forced")
	_check(is_equal_approx(tun_norm.y, 1.24), "_hills_overlay_effective_tuning preserves uv_zoom when not forced")
	_check(is_equal_approx(tun_norm.z, 0.45), "_hills_overlay_effective_tuning preserves opacity when not forced")
	var tun_x: Vector3 = MapViewScript._hills_overlay_effective_tuning(true, 0.55, 1.2, 0.40)
	_check(is_equal_approx(tun_x.x, 1.0), "extreme mode forces effective_scale 1.0")
	_check(is_equal_approx(tun_x.y, 2.0), "extreme mode forces effective_uv_zoom 2.0")
	_check(is_equal_approx(tun_x.z, 1.0), "extreme mode forces effective_opacity 1.0")
	var c_var_a = HexCoordScript.new(0, 0)
	var c_var_b = HexCoordScript.new(3, -2)
	var vc: int = 4
	var ia: int = MapViewScript._hills_overlay_variant_index_for_coord(
		c_var_a, HexMapScript.Terrain.PLAINS, vc
	)
	var ia_again: int = MapViewScript._hills_overlay_variant_index_for_coord(
		c_var_a, HexMapScript.Terrain.PLAINS, vc
	)
	_check(ia == ia_again, "hills overlay variant index stable for same coord/terrain/count")
	_check(ia >= 0 and ia < vc, "variant index in bounds (a)")
	var ib: int = MapViewScript._hills_overlay_variant_index_for_coord(
		c_var_b, HexMapScript.Terrain.PLAINS, vc
	)
	_check(ib >= 0 and ib < vc, "variant index in bounds (b)")
	var saw_multi: bool = false
	var uq: int = -3
	while uq <= 3 and not saw_multi:
		var ur: int = -3
		var first_i: int = -1
		while ur <= 3:
			var ii: int = MapViewScript._hills_overlay_variant_index_for_coord(
				HexCoordScript.new(uq, ur), HexMapScript.Terrain.PLAINS, vc
			)
			if first_i < 0:
				first_i = ii
			elif ii != first_i:
				saw_multi = true
				break
			ur += 1
		uq += 1
	_check(saw_multi, "some nearby hexes get different variant indices")
	var found_terrain_salt: bool = false
	var ts: int = 0
	while ts < 24:
		var cq = HexCoordScript.new(ts - 8, ts % 5 - 2)
		var jp: int = MapViewScript._hills_overlay_variant_index_for_coord(cq, HexMapScript.Terrain.PLAINS, vc)
		var jg: int = MapViewScript._hills_overlay_variant_index_for_coord(cq, HexMapScript.Terrain.GRASSLAND, vc)
		if jp != jg:
			found_terrain_salt = true
			break
		ts += 1
	_check(found_terrain_salt, "terrain salt yields different variants for some coord")
	_check(
		MapViewScript._hills_overlay_variant_index_for_coord(c_var_a, HexMapScript.Terrain.PLAINS, 0) == 0,
		"variant_count 0 returns 0"
	)
	var mv_h: MapView = MapViewScript.new()
	var t_p0: Texture2D = _solid_tex_c(Color(1.0, 0.0, 0.0, 1.0))
	var t_p1: Texture2D = _solid_tex_c(Color(0.0, 1.0, 0.0, 1.0))
	var t_g0: Texture2D = _solid_tex_c(Color(0.0, 0.0, 1.0, 1.0))
	mv_h._plains_hills_overlay_textures = [t_p0, t_p1]
	mv_h._grassland_hills_overlay_textures = [t_g0]
	var ix_p: int = MapViewScript._hills_overlay_variant_index_for_coord(
		c_var_a, HexMapScript.Terrain.PLAINS, 2
	)
	var exp_p: Texture2D = t_p0
	if ix_p == 1:
		exp_p = t_p1
	var pick_p: Texture2D = mv_h._hills_overlay_texture_for_hex(c_var_a, HexMapScript.Terrain.PLAINS)
	_check(pick_p == exp_p, "_hills_overlay_texture_for_hex uses plains array slice")
	var pick_g: Texture2D = mv_h._hills_overlay_texture_for_hex(c_var_a, HexMapScript.Terrain.GRASSLAND)
	_check(pick_g == t_g0, "_hills_overlay_texture_for_hex uses grassland array")
	_check(
		mv_h._hills_overlay_texture_for_hex(c_var_a, HexMapScript.Terrain.WATER) == null,
		"_hills_overlay_texture_for_hex WATER null"
	)
	mv_h._plains_hills_overlay_textures = []
	_check(
		mv_h._hills_overlay_texture_for_hex(c_var_a, HexMapScript.Terrain.PLAINS) == null,
		"_hills_overlay_texture_for_hex null when family empty"
	)
	mv_h.free()
	mv_defaults.free()
	var t_pl: Texture2D = _solid_tex_c(Color(1.0, 0.0, 0.0, 1.0))
	var t_gl: Texture2D = _solid_tex_c(Color(0.0, 0.0, 1.0, 1.0))
	var t_wv: Texture2D = _solid_tex_c(Color(0.5, 0.5, 0.5, 1.0))
	_check(
		MapViewScript._texture_for_land(HexMapScript.Terrain.PLAINS, t_pl, t_gl, t_wv) == t_pl,
		"PLAINS+FLAT -> plains tex (terrain-only routing)"
	)
	_check(
		MapViewScript._texture_for_land(HexMapScript.Terrain.PLAINS, t_pl, t_gl, t_wv) == t_pl,
		"PLAINS+HILLS -> plains tex base (not full hills texture)"
	)
	_check(
		MapViewScript._texture_for_land(HexMapScript.Terrain.GRASSLAND, t_pl, t_gl, t_wv) == t_gl,
		"GRASSLAND+FLAT -> grassland tex"
	)
	_check(
		MapViewScript._texture_for_land(HexMapScript.Terrain.GRASSLAND, t_pl, t_gl, t_wv) == t_gl,
		"GRASSLAND+HILLS -> grassland tex base"
	)
	_check(
		MapViewScript._texture_for_land(HexMapScript.Terrain.WATER, t_pl, t_gl, t_wv) == t_wv,
		"WATER -> water tex"
	)
	_check(
		MapViewScript._hills_overlay_eligible(HexMapScript.Terrain.PLAINS, HexMapScript.Landform.HILLS),
		"_hills_overlay_eligible PLAINS+HILLS"
	)
	_check(
		MapViewScript._hills_overlay_eligible(HexMapScript.Terrain.GRASSLAND, HexMapScript.Landform.HILLS),
		"_hills_overlay_eligible GRASSLAND+HILLS"
	)
	_check(
		not MapViewScript._hills_overlay_eligible(HexMapScript.Terrain.PLAINS, HexMapScript.Landform.FLAT),
		"PLAINS FLAT: no overlay eligibility"
	)
	_check(
		not MapViewScript._hills_overlay_eligible(HexMapScript.Terrain.WATER, HexMapScript.Landform.FLAT),
		"WATER: no overlay eligibility"
	)
	_check(
		not MapViewScript._hills_overlay_eligible(HexMapScript.Terrain.WATER, HexMapScript.Landform.HILLS),
		"WATER+HILLS: no overlay eligibility"
	)
	var layout_uv = HexLayoutScript.new()
	var w_a: Vector2 = layout_uv.hex_to_world(0, 0)
	var w_b: Vector2 = layout_uv.hex_to_world(4, -2)
	var corners_a: PackedVector2Array = layout_uv.hex_corners(w_a)
	var corners_b: PackedVector2Array = layout_uv.hex_corners(w_b)
	var world_scale_uv: float = 512.0
	var wa0: Vector2 = MapViewScript._world_anchored_corner_uvs(corners_a, world_scale_uv)[0]
	var wb0: Vector2 = MapViewScript._world_anchored_corner_uvs(corners_b, world_scale_uv)[0]
	_check(not wa0.is_equal_approx(wb0), "world-anchored UVs differ for different hex positions (sanity)")
	var la0: Vector2 = MapViewScript._hex_local_corner_uvs(corners_a, w_a, 1.0)[0]
	var lb0: Vector2 = MapViewScript._hex_local_corner_uvs(corners_b, w_b, 1.0)[0]
	_check(la0.is_equal_approx(lb0), "hex-local UVs match per corner index across translated hexes (extent 1)")
	var hi: int = 0
	while hi < 6:
		var uvl: Vector2 = MapViewScript._hex_local_corner_uvs(corners_a, w_a, 1.0)[hi]
		_check(uvl.x >= -0.001 and uvl.x <= 1.001 and uvl.y >= -0.001 and uvl.y <= 1.001, "hex-local UV in unit square")
		hi += 1
	var full_hex: PackedVector2Array = MapViewScript._hex_overlay_polygon_world(w_a, 1.0)
	_check(full_hex.size() == 6, "overlay polygon has 6 corners")
	var kk: int = 0
	while kk < 6:
		_check(full_hex[kk].is_equal_approx(corners_a[kk]), "overlay scale 1 matches hex corners")
		kk += 1
	var inner: PackedVector2Array = MapViewScript._hex_overlay_polygon_world(w_a, 0.70)
	var jj: int = 0
	while jj < 6:
		var dist_inner: float = inner[jj].distance_to(w_a)
		var dist_full: float = corners_a[jj].distance_to(w_a)
		_check(dist_inner < dist_full - 0.001, "inner overlay polygon strictly inside hex")
		jj += 1
	var inner90: PackedVector2Array = MapViewScript._hex_overlay_polygon_world(w_a, 0.90)
	var inner70again: PackedVector2Array = MapViewScript._hex_overlay_polygon_world(w_a, 0.70)
	var j90: int = 0
	while j90 < 6:
		_check(
			inner90[j90].distance_to(w_a) > inner70again[j90].distance_to(w_a) + 0.001,
			"overlay polygon at scale 0.90 extends farther from center than 0.70"
		)
		j90 += 1
	var uvs_default_zoom: PackedVector2Array = MapViewScript._hex_local_corner_uvs(corners_a, w_a, 1.0)
	var uvs_explicit_1: PackedVector2Array = MapViewScript._hex_local_corner_uvs(corners_a, w_a, 1.0, 1.0)
	var zi: int = 0
	while zi < 6:
		_check(
			uvs_default_zoom[zi].is_equal_approx(uvs_explicit_1[zi]),
			"hex-local UVs uv_zoom=1.0 matches 3-arg call"
		)
		zi += 1
	var uvs_zoom2: PackedVector2Array = MapViewScript._hex_local_corner_uvs(corners_a, w_a, 1.0, 2.0)
	var zu: int = 0
	var any_strict_pull: bool = false
	while zu < 6:
		var base_uv: Vector2 = uvs_default_zoom[zu]
		var z2: Vector2 = uvs_zoom2[zu]
		_check(
			absf(z2.x - 0.5) <= absf(base_uv.x - 0.5) + 0.0001
			and absf(z2.y - 0.5) <= absf(base_uv.y - 0.5) + 0.0001,
			"uv_zoom > 1 pulls UVs toward texture center (0.5,0.5)"
		)
		if (
			absf(z2.x - 0.5) + 0.001 < absf(base_uv.x - 0.5)
			or absf(z2.y - 0.5) + 0.001 < absf(base_uv.y - 0.5)
		):
			any_strict_pull = true
		zu += 1
	_check(any_strict_pull, "uv_zoom 2.0 strictly tightens UV offset from center on at least one corner")
	var umin: float = 1.0
	var umax: float = 0.0
	var vimin: float = 1.0
	var vimax: float = 0.0
	var uu: int = 0
	var uvs_scaled: PackedVector2Array = MapViewScript._hex_local_corner_uvs(inner, w_a, 0.70)
	while uu < 6:
		var uv: Vector2 = uvs_scaled[uu]
		if uv.x < umin:
			umin = uv.x
		if uv.x > umax:
			umax = uv.x
		if uv.y < vimin:
			vimin = uv.y
		if uv.y > vimax:
			vimax = uv.y
		uu += 1
	_check(umin <= 0.001 and umax >= 1.0 - 0.001, "scaled overlay UVs span U")
	_check(vimin <= 0.001 and vimax >= 1.0 - 0.001, "scaled overlay UVs span V")
	var stub_ov: Texture2D = _solid_tex_c(Color(1.0, 1.0, 1.0, 1.0))
	_check(
		MapViewScript._hills_overlay_will_draw(
			HexMapScript.Terrain.PLAINS, HexMapScript.Landform.HILLS, [stub_ov], [stub_ov]
		),
		"_hills_overlay_will_draw PLAINS+HILLS with textures"
	)
	_check(
		not MapViewScript._hills_overlay_will_draw(
			HexMapScript.Terrain.PLAINS, HexMapScript.Landform.HILLS, [], [stub_ov]
		),
		"PLAINS+HILLS with missing plains overlay texture does not draw"
	)
	_check(
		not MapViewScript._hills_overlay_will_draw(
			HexMapScript.Terrain.GRASSLAND, HexMapScript.Landform.HILLS, [stub_ov], []
		),
		"GRASSLAND+HILLS with missing grassland overlay texture does not draw"
	)
	_check(
		not MapViewScript._hills_overlay_will_draw(
			HexMapScript.Terrain.PLAINS, HexMapScript.Landform.FLAT, [stub_ov], [stub_ov]
		),
		"PLAINS FLAT does not attempt overlay"
	)
	_check(
		not MapViewScript._hills_overlay_will_draw(
			HexMapScript.Terrain.WATER, HexMapScript.Landform.HILLS, [stub_ov], [stub_ov]
		),
		"WATER does not attempt overlay"
	)
	_check(
		MapViewScript._hills_overlay_texture_for_terrain(HexMapScript.Terrain.PLAINS, [stub_ov], []) == stub_ov,
		"texture for PLAINS is first plains overlay"
	)
	_check(
		MapViewScript._hills_overlay_texture_for_terrain(HexMapScript.Terrain.GRASSLAND, [], [stub_ov])
		== stub_ov,
		"texture for GRASSLAND is first grassland overlay"
	)
	var mh_pl: Color = Color(0.9, 1.1, 0.8, 1.0)
	var mh_gl: Color = Color(1.15, 0.85, 0.95, 1.0)
	var op85: float = 0.85
	_check(
		MapViewScript._hills_overlay_tint_channels(HexMapScript.Terrain.WATER, mh_pl, mh_gl, op85).a <= 0.001,
		"WATER overlay tint has no alpha"
	)
	var exp_ph: Color = Color(
		clampf(mh_pl.r, 0.75, 1.25),
		clampf(mh_pl.g, 0.75, 1.25),
		clampf(mh_pl.b, 0.75, 1.25),
		clampf(mh_pl.a * op85, 0.0, 1.0)
	)
	_check(
		MapViewScript._hills_overlay_tint_channels(HexMapScript.Terrain.PLAINS, mh_pl, mh_gl, op85).is_equal_approx(exp_ph),
		"PLAINS overlay tint uses plains modulate clamped and opacity"
	)
	var exp_gh: Color = Color(
		clampf(mh_gl.r, 0.75, 1.25),
		clampf(mh_gl.g, 0.75, 1.25),
		clampf(mh_gl.b, 0.75, 1.25),
		clampf(mh_gl.a * op85, 0.0, 1.0)
	)
	_check(
		MapViewScript._hills_overlay_tint_channels(HexMapScript.Terrain.GRASSLAND, mh_pl, mh_gl, op85).is_equal_approx(exp_gh),
		"GRASSLAND overlay tint uses grassland modulate clamped and opacity"
	)
	if _any_fail:
		call_deferred("quit", 1)
	else:
		print("PASS %d/%d" % [_total, _total])
		call_deferred("quit", 0)

func _check(cond, message) -> void:
	_total = _total + 1
	if cond:
		return
	_any_fail = true
	var line = "FAIL: %s" % message
	print(line)
	push_error(line)
