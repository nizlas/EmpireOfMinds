# Headless: **CityTerritoryView** stable perimeter topology + accent lookup. Usage: godot --headless --path game -s res://presentation/tests/test_city_territory_view.gd
extends SceneTree

const CityTerritoryViewScript = preload("res://presentation/city_territory_view.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const GameStateScript = preload("res://domain/game_state.gd")
const FoundCityScript = preload("res://domain/actions/found_city.gd")
const UnitNameplateViewScript = preload("res://presentation/unit_nameplate_view.gd")
const MapCameraScript = preload("res://presentation/map_camera.gd")
const MapPlaneProjectionScript = preload("res://presentation/map_plane_projection.gd")

var _fail: bool = false


func _check(cond: bool, msg: String) -> void:
	if cond:
		return
	_fail = true
	push_error("FAIL: %s" % msg)


## Directed count: **(hex, dir)** with axial neighbor also owned — must be **zero** on perimeter faces; **>0** means shared/internal edges exist.
static func _directed_internal_neighbor_faces(owned_hexes: Array, owned_map: Dictionary) -> int:
	var n: int = 0
	var i: int = 0
	while i < owned_hexes.size():
		var h = owned_hexes[i]
		var d: int = 0
		while d < 6:
			var nb: Vector2i = CityTerritoryViewScript.neighbor_qr(int(h.q), int(h.r), d)
			var key: String = "%d,%d" % [nb.x, nb.y]
			if owned_map.has(key):
				n += 1
			d += 1
		i += 1
	return n


func _init() -> void:
	var c = CityTerritoryViewScript
	var layout = HexLayoutScript.new()
	var tab: PackedByteArray = c.edge_index_table_for_layout(layout)
	var el: float = c.hex_edge_world_length(layout)
	var el_tol: float = 0.02 * el

	_check(c.verify_pinned_axial_edge_table_matches_layout(layout), "EDGE_NEIGHBOR_AXIAL pins HexLayout.hex_corners + HexCoord.Direction order")
	_check(not c.territory_fills_owned_tiles(), "outline-only: territory_fills_owned_tiles is false (no dimming fill)")
	_check(is_equal_approx(c.TERRITORY_OUTER_W_MIN, 9.0), "pinned TERRITORY_OUTER_W_MIN (2× thickness baseline)")
	_check(is_equal_approx(c.TERRITORY_OUTER_W_MUL, 11.0), "pinned TERRITORY_OUTER_W_MUL")
	_check(is_equal_approx(c.TERRITORY_OUTER_W_MAX, 44.0), "pinned TERRITORY_OUTER_W_MAX")
	_check(is_equal_approx(c.TERRITORY_INNER_INSET_FRAC, 0.40), "pinned TERRITORY_INNER_INSET_FRAC")

	var one_hex_list: Array = [HexCoordScript.new(0, 0)]
	_check(c.territory_border_edge_count(one_hex_list) == 6, "single-hex perimeter => 6 border half-edges")
	var det1: Array = c.territory_perimeter_world_segments_detailed(layout, one_hex_list, tab)
	_check(det1.size() == 6, "single-hex => 6 detailed perimeter segments")
	var loops1: Array = c.trace_territory_perimeter_loops_edge_indices(det1)
	_check(loops1.size() == 1, "single hex => one closed perimeter loop")
	_check((loops1[0] as Array).size() == 6, "single-hex loop has 6 half-edges")
	_check(c.territory_traced_loop_edge_count_total(loops1) == det1.size(), "trace visits every half-edge once")
	_check(c.territory_perimeter_loops_connect_adjacent_half_edges(det1, loops1), "loop corners chain ka/kb without skips")
	_check(
		c.territory_perimeter_loops_axial_signature(det1, loops1)
		== c.territory_perimeter_loops_axial_signature(det1, loops1),
		"loop axial fingerprint stable"
	)
	_check(c.perimeter_segments_are_local_hex_edges(layout, one_hex_list, tab), "single-hex segments are local hex edges")
	_check(
		c.territory_perimeter_world_corner_key_count(layout, one_hex_list, tab) == 6,
		"single-hex => 6 unique perimeter corners"
	)
	var val_one: Dictionary = c.territory_perimeter_vertex_valence_by_key(layout, one_hex_list, tab)
	_check(val_one.size() == 6, "single-hex => 6 vertex join sites")
	for vk in val_one:
		_check(int(val_one[vk]) == 2, "perimeter vertex valence 2 (single hex)")
	_check(
		c.territory_join_topology_signature(layout, one_hex_list, tab)
		== c.territory_join_topology_signature(layout, one_hex_list, tab),
		"join topology signature stable (world-derived)"
	)

	var seven_list: Array = [HexCoordScript.new(0, 0)]
	var nbrs2 = (seven_list[0] as HexCoordScript).neighbors()
	var ni2: int = 0
	while ni2 < nbrs2.size():
		seven_list.append(nbrs2[ni2])
		ni2 += 1
	# Same 7 owned hexes, different array order (must not change join topology / key set).
	var seven_reorder: Array = []
	var nbrs_rev = (seven_list[0] as HexCoordScript).neighbors()
	var nr: int = nbrs_rev.size() - 1
	while nr >= 0:
		seven_reorder.append(nbrs_rev[nr])
		nr -= 1
	seven_reorder.append(seven_list[0])
	_check(c.territory_border_edge_count(seven_list) == 18, "7-hex => 18 border half-edges")
	var det7: Array = c.territory_perimeter_world_segments_detailed(layout, seven_list, tab)
	_check(det7.size() == 18, "7-hex => 18 detailed perimeter segments")
	_check(c.perimeter_segments_are_local_hex_edges(layout, seven_list, tab), "7-hex segments are local hex edges")
	var max_wlen: float = 0.0
	var si: int = 0
	while si < det7.size():
		var row: Dictionary = det7[si] as Dictionary
		var wa7: Vector2 = row["wa"] as Vector2
		var wb7: Vector2 = row["wb"] as Vector2
		max_wlen = maxf(max_wlen, wa7.distance_to(wb7))
		si += 1
	_check(max_wlen <= el + el_tol, "radius-1 territory: no long chord; each segment is one hex edge in world space")

	_check(
		c.territory_perimeter_world_corner_key_count(layout, seven_list, tab) == 18,
		"7-hex => 18 unique perimeter corner vertices"
	)
	var val_seven: Dictionary = c.territory_perimeter_vertex_valence_by_key(layout, seven_list, tab)
	_check(val_seven.size() == 18, "7-hex => 18 vertex join sites")
	for vk7 in val_seven:
		_check(int(val_seven[vk7]) == 2, "perimeter vertex valence 2 (radius-1)")
	_check(
		c.territory_join_topology_signature(layout, seven_list, tab) == c.territory_join_topology_signature(layout, seven_reorder, tab),
		"join topology matches same owned shape (owner/camera-agnostic key list)"
	)
	var loops7: Array = c.trace_territory_perimeter_loops_edge_indices(det7)
	_check(loops7.size() == 1, "radius-1 cluster => one outer loop")
	_check((loops7[0] as Array).size() == 18, "radius-1 loop has 18 half-edges")
	_check(c.territory_perimeter_loops_connect_adjacent_half_edges(det7, loops7), "radius-1 loop chains corners")
	_check(
		c.territory_perimeter_loops_axial_signature(det7, loops7)
		== c.territory_perimeter_loops_axial_signature(
			c.territory_perimeter_world_segments_detailed(layout, seven_reorder, tab),
			c.trace_territory_perimeter_loops_edge_indices(
				c.territory_perimeter_world_segments_detailed(layout, seven_reorder, tab)
			)
		),
		"loop fingerprint matches same owned set with different coord order (no camera)"
	)

	var island_a: Array = [HexCoordScript.new(0, 0), HexCoordScript.new(12, 0)]
	_check(c.territory_border_edge_count(island_a) == 12, "two non-touching hexes => 12 border half-edges")
	var det_i: Array = c.territory_perimeter_world_segments_detailed(layout, island_a, tab)
	_check(det_i.size() == 12, "two islands => 12 detailed segments")
	_check(
		c.territory_perimeter_world_corner_key_count(layout, island_a, tab) == 12,
		"two islands => 12 unique perimeter corners"
	)
	var val_isl: Dictionary = c.territory_perimeter_vertex_valence_by_key(layout, island_a, tab)
	_check(val_isl.size() == 12, "two islands => 12 vertex join sites")
	for vki in val_isl:
		_check(int(val_isl[vki]) == 2, "each island ring vertex valence 2")
	var loops_i: Array = c.trace_territory_perimeter_loops_edge_indices(det_i)
	_check(loops_i.size() == 2, "two islands => two disconnected loops")
	_check((loops_i[0] as Array).size() == 6, "island loop A has 6 edges")
	_check((loops_i[1] as Array).size() == 6, "island loop B has 6 edges")
	_check(c.territory_traced_loop_edge_count_total(loops_i) == det_i.size(), "islands cover all half-edges")

	var a_edge = Vector2(100.0, 200.0)
	var b_edge = Vector2(220.0, 200.0)
	var mid = (a_edge + b_edge) * 0.5
	var toward = Vector2(160.0, 290.0)
	var n_in = c.inward_unit_normal_for_edge(a_edge, b_edge, toward)
	_check(n_in.dot(toward - mid) > 0.001, "inward edge normal points toward owning tile center in presentation space")
	var u_edge = (b_edge - a_edge).normalized()
	_check(absf(n_in.dot(u_edge)) < 0.0002, "inward normal is perpendicular to border segment")

	var d_chk: int = 0
	while d_chk < 6:
		var ei0: int = c._compute_edge_index_for_axial_direction(layout, 0, 0, d_chk)
		var ei1: int = c._compute_edge_index_for_axial_direction(layout, 4, -3, d_chk)
		_check(int(tab[d_chk]) == ei0, "edge_index_table matches origin compute")
		_check(ei0 == ei1, "edge index translation-invariant (sample offset hex)")
		d_chk += 1

	var one: Array = [HexCoordScript.new(4, -2)]
	_check(c.territory_border_edge_count(one) == 6, "single hex => 6 border edges")
	_check(_directed_internal_neighbor_faces(one, c.owned_key_set_from_coords(one)) == 0, "single hex => zero internal faces")

	var center = HexCoordScript.new(0, 0)
	var seven: Array = [center]
	var nbrs = center.neighbors()
	var ni: int = 0
	while ni < nbrs.size():
		seven.append(nbrs[ni])
		ni += 1
	_check(seven.size() == 7, "center + radius-1 => 7 coords")
	var seven_map: Dictionary = c.owned_key_set_from_coords(seven)
	_check(_directed_internal_neighbor_faces(seven, seven_map) == 24, "7-hex cluster => 24 directed internal faces (no extra per-tile outline)")

	var dup: Array = [HexCoordScript.new(1, 1), HexCoordScript.new(1, 1)]
	_check(c.territory_border_edge_count(dup) == 6, "duplicate coord entries dedupe in set => 6 edges")

	var two_adj: Array = [HexCoordScript.new(0, 0), HexCoordScript.new(1, 0)]
	_check(c.territory_border_edge_count(two_adj) == 10, "two adjacent hexes => 10 outer edges")
	_check(_directed_internal_neighbor_faces(two_adj, c.owned_key_set_from_coords(two_adj)) == 2, "two adjacent => one shared edge (2 directed faces)")
	# Terrain is ignored for union perimeter: owned "water" vs owned "land" behaves like any two owned axial cells.
	var land_and_water_coords: Array = [HexCoordScript.new(2, 0), HexCoordScript.new(3, 0)]
	_check(c.territory_border_edge_count(land_and_water_coords) == 10, "adjacent owned coords => no border along shared edge (water+land naming irrelevant)")

	_check(c.territory_border_edge_count([]) == 0, "empty coords => 0")

	# --- Topology invariant: zoom / pan change projection only; axial edge set is camera-independent. ---
	var sig7_a: String = c.territory_perimeter_axial_signature(seven_list)
	var cam_z1 = MapCameraScript.new()
	cam_z1.projection = MapPlaneProjectionScript.new()
	cam_z1.zoom = 0.65
	var cam_z2 = MapCameraScript.new()
	cam_z2.projection = MapPlaneProjectionScript.new()
	cam_z2.zoom = 1.85
	_check(sig7_a == c.territory_perimeter_axial_signature(seven), "same owned shape => identical axial signature (owner-agnostic)")
	var pj: int = 0
	var zoom_len_delta: float = 0.0
	while pj < det7.size():
		var rowp: Dictionary = det7[pj] as Dictionary
		var wap: Vector2 = rowp["wa"] as Vector2
		var wbp: Vector2 = rowp["wb"] as Vector2
		var len_a: float = cam_z1.to_presentation(wap).distance_to(cam_z1.to_presentation(wbp))
		var len_b: float = cam_z2.to_presentation(wap).distance_to(cam_z2.to_presentation(wbp))
		zoom_len_delta = maxf(zoom_len_delta, absf(len_a - len_b))
		pj += 1
	_check(zoom_len_delta > 2.0, "zoom changes projected segment lengths (topology id list unchanged via axial signature)")

	var cam_in = MapCameraScript.new()
	cam_in.projection = MapPlaneProjectionScript.new()
	cam_in.zoom = 1.0
	var ii: int = 0
	while ii < det7.size():
		var row_i: Dictionary = det7[ii] as Dictionary
		var iq: int = int(row_i["q"])
		var ir: int = int(row_i["r"])
		var iwa: Vector2 = row_i["wa"] as Vector2
		var iwb: Vector2 = row_i["wb"] as Vector2
		var inward_u: Vector2 = c.territory_inward_unit_presentation(cam_in, layout, iq, ir, iwa, iwb)
		_check(
			inward_u.length_squared() > 1e-8 and is_equal_approx(inward_u.length(), 1.0),
			"perimeter inward is unit (or would be zero only if degenerate)"
		)
		var ipa: Vector2 = cam_in.to_presentation(iwa)
		var ipb: Vector2 = cam_in.to_presentation(iwb)
		var imid: Vector2 = (ipa + ipb) * 0.5
		var ictr: Vector2 = cam_in.to_presentation(layout.hex_to_world(iq, ir))
		var toward_c: Vector2 = ictr - imid
		if toward_c.length_squared() > 1.0:
			_check(inward_u.dot(toward_c.normalized()) > 0.98, "inner offset basis points toward owning tile center in presentation space")
		ii += 1

	# Half-edge inventory matches border count (continuous Line2D still draws one stroke per loop, not rivets).
	_check(
		c.territory_border_edge_count(seven_list) == det7.size(),
		"per outer loop, vertex count equals half-edge count"
	)

	var lp0: Array = loops7[0] as Array
	var e_prev_i: Dictionary = det7[int(lp0[(lp0.size() - 1) % lp0.size()])] as Dictionary
	var e_cur_i: Dictionary = det7[int(lp0[0])] as Dictionary
	var ow_corner: float = 22.0
	var in_px_corner: float = clampf(
		c.TERRITORY_INNER_INSET_FRAC * ow_corner, c.TERRITORY_INNER_INSET_MIN, c.TERRITORY_INNER_INSET_MAX
	)
	var inner_corner: Vector2 = c.territory_inner_corner_offset_presentation(
		cam_in, layout, in_px_corner, e_prev_i, e_cur_i
	)
	var border_corner: Vector2 = cam_in.to_presentation(e_cur_i["wa"] as Vector2)
	var own_ctr: Vector2 = cam_in.to_presentation(layout.hex_to_world(int(e_cur_i["q"]), int(e_cur_i["r"])))
	var to_in: Vector2 = (inner_corner - border_corner).normalized()
	var to_own: Vector2 = (own_ctr - border_corner).normalized()
	if (own_ctr - border_corner).length_squared() > 4.0:
		_check(to_in.dot(to_own) > 0.85, "inner loop corner shifts toward owned side vs border vertex")

	var cam_p1 = MapCameraScript.new()
	cam_p1.projection = MapPlaneProjectionScript.new()
	cam_p1.camera_world_offset = Vector2.ZERO
	var cam_p2 = MapCameraScript.new()
	cam_p2.projection = MapPlaneProjectionScript.new()
	cam_p2.camera_world_offset = Vector2(240.0, -180.0)
	var w0: Vector2 = (det7[0] as Dictionary)["wa"] as Vector2
	_check(not cam_p1.to_presentation(w0).is_equal_approx(cam_p2.to_presentation(w0)), "pan changes projected position")

	_check(det7.size() != det1.size(), "different territories => different segment counts")
	_check(
		c.territory_perimeter_axial_signature(one_hex_list) != c.territory_perimeter_axial_signature(seven_list),
		"different tile sets => different topology (view recomputes from current city tiles only; no merge of A+B)"
	)

	var bad_sel = null
	_check(
		c.territory_accent_color_for_city(bad_sel, 1) == Color(0.55, 0.55, 0.55, 1.0),
		"null scenario => gray accent"
	)
	var gs = GameStateScript.make_tiny_test_state()
	_check(
		c.territory_accent_color_for_city(gs.scenario, 999).is_equal_approx(Color(0.55, 0.55, 0.55, 1.0)),
		"missing city id => gray accent"
	)
	_check(gs.try_apply(FoundCityScript.make(0, 1, 0, 0))["accepted"], "found city for accent")
	var cy = 1
	var accent = c.territory_accent_color_for_city(gs.scenario, cy)
	var expect = UnitNameplateViewScript.owner_nameplate_accent_color(0)
	_check(accent.is_equal_approx(expect), "founded city accent matches owner nameplate palette")

	var tiles_rt: Array = gs.scenario.tiles_owned_by_city(cy)
	_check(tiles_rt.size() >= 1, "tiles_owned_by_city non-empty after found")
	var axial0 = c.try_axial_from_owned_tile_entry(tiles_rt[0])
	_check(axial0 != null, "duck-typed axial from scenario tile row")
	var v0: Vector2i = axial0 as Vector2i
	_check(v0.x == 0 and v0.y == 0, "first owned tile includes center 0,0")

	var fs = FileAccess.open("res://presentation/city_territory_view.gd", FileAccess.READ)
	_check(fs != null, "open city_territory_view.gd for render-path regression")
	if fs != null:
		var src: String = fs.get_as_text()
		fs.close()
		var i_sync: int = src.find("func _ensure_territory_line_pairs_needed")
		var i_dbg: int = src.find("func _debug_draw_territory_endpoint_caps_if_enabled")
		_check(i_sync > 0 and i_dbg > i_sync, "Line2D pool before debug-only caps")
		var dbg_src: String = src.substr(i_dbg, src.length() - i_dbg)
		_check(dbg_src.count("draw_circle(") == 2, "debug endpoint caps only (two draw_circle); no normal joint dots")
		_check(src.find("Line2D.new") > 0, "CityTerritoryView builds continuous Line2D loops")
		_check(src.find("LINE_JOINT_ROUND") > 0, "Line2D uses round joints for continuous border")
		_check(src.find("draw_colored_polygon(") < 0, "CityTerritoryView must not call draw_colored_polygon()")
		_check(src.find("draw_polyline(") < 0, "no draw_polyline ribbon assembly")
		_check(src.find("draw_line(") < 0, "no draw_line perimeter strokes (Line2D is the stroked path)")
		_check(src.find("assemble_closed_border_loops_from_segments") < 0, "no legacy named loop assembler")
		_check(src.find("collect_border_segments_presentation") < 0, "no presentation-space segment collector")
		_check(src.find("inset_open_border_loop") < 0, "no inset loop toward presentation centroid")
		_check(src.find("var _territory_") < 0, "no cached _territory_* buffers")
		_check(src.find("var _border_") < 0, "no cached _border_* buffers")

	if _fail:
		call_deferred("quit", 1)
		return
	print("PASS city_territory_view")
	call_deferred("quit", 0)
