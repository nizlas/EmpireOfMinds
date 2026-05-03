# Headless: forest front grid — experimental **20** slots **`2/3/5/5/3/2`**; **disk(S, R+M)** inside hex; deterministic jitter.
# Baseline revert: **10** slots **`2/3/3/2`**, **`_GRID_UPPER_SLOT_COUNT=5`**, old **`forest_grid_slot_base_local`** mapping.
# Row pitch **P** = **`_GRID_ROW_PITCH_FRAC × HexLayout.SIZE`**; **row jitter gap** = **`P − 2×R_jitter`**. PNG **diag_pad_ref** does not drive **P**.
# Editor: **TerrainForegroundView.forest_grid_debug_draw_jitter_circles** — optional projected jitter-ring overlay (base + circle + root); does not affect this script’s assertions.
# Usage: godot --headless --path game -s res://presentation/tests/test_forest_front_grid.gd
extends SceneTree

const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const HexMapScript = preload("res://domain/hex_map.gd")
const MapCameraScript = preload("res://presentation/map_camera.gd")
const MapPlaneProjectionScript = preload("res://presentation/map_plane_projection.gd")
const TerrainForegroundViewScript = preload("res://presentation/terrain_foreground_view.gd")

const _EXPECT_ROW_PITCH_FRAC: float = 0.28
## Upper bound on **row_jitter_gap/H** under old **P = 2×R + PNG-derived pad** (pre fraction-pitch); new gap must be larger.
const _LEGACY_ROW_JITTER_GAP_FRAC_BEFORE_PITCH_MODEL: float = 0.0065
const _EXPECT_GRID_SLOTS: int = 20
const _EXPECT_UPPER_SLOTS: int = 10
## **P/H = 0.28** row centers: **k × P** for **k ∈ {−2.5,…,2.5}**.
const _EXPECT_ROW_Y_OVER_H: Array[float] = [-0.70, -0.42, -0.14, 0.14, 0.42, 0.70]
## **(q,r)** for jitter diversity checks — chosen so column-slot decorrelation never degenerates for fixed hashes.
const _JITTER_SAMPLE_Q: int = -8
const _JITTER_SAMPLE_R: int = -3

## **True** if every **non-degenerate** pair in **slot_indices** has **|dot(na,nb)| > dot_thresh** (entire column near-parallel).
func _forest_column_group_all_near_parallel(
	q: int, r: int, slot_indices: Array, dot_thresh: float
) -> bool:
	var n: int = slot_indices.size()
	var vecs: Array[Vector2] = []
	var i: int = 0
	while i < n:
		vecs.append(
			TerrainForegroundViewScript.forest_grid_jitter_local_deterministic(
				q, r, int(slot_indices[i]), false
			)
		)
		i += 1
	var had_pair: bool = false
	var a: int = 0
	while a < n:
		var b: int = a + 1
		while b < n:
			var va: Vector2 = vecs[a]
			var vb: Vector2 = vecs[b]
			if va.length_squared() < 1e-12 or vb.length_squared() < 1e-12:
				b += 1
				continue
			had_pair = true
			if absf(va.normalized().dot(vb.normalized())) <= dot_thresh:
				return false
			b += 1
		a += 1
	return had_pair


func _assert_disk_samples_inside_hex(
	layout, slot_center: Vector2, safe_r: float, slot_index: int, n_samples: int
) -> bool:
	var k: int = 0
	while k < n_samples:
		var ang: float = TAU * float(k) / float(n_samples)
		var p: Vector2 = slot_center + Vector2(cos(ang), sin(ang)) * safe_r
		if not layout.is_point_inside_hex_local(p):
			push_error(
				"FAIL: slot %d sample %d p=%s safe_r=%.4f outside hex (center=%s)"
				% [slot_index, k, p, safe_r, slot_center]
			)
			return false
		k += 1
	return true


func _assert_full_jitter_offsets_inside_hex(layout, slot_index: int) -> bool:
	var S: Vector2 = TerrainForegroundViewScript.forest_grid_slot_base_local(slot_index)
	var rj: float = TerrainForegroundViewScript.forest_grid_jitter_max_radius_world()
	var nj: int = 16
	var k: int = 0
	while k < nj:
		var ang: float = TAU * float(k) / float(nj)
		var root: Vector2 = S + Vector2(cos(ang), sin(ang)) * rj
		if not layout.is_point_inside_hex_local(root):
			push_error("FAIL: slot %d jitter tip %d root=%s outside hex" % [slot_index, k, root])
			return false
		k += 1
	return true


func _tfv_attach_isolated(tfv: Node, perfect_export: bool) -> void:
	var rt: Node = get_root()
	rt.add_child(tfv)
	tfv.map = HexMapScript.make_tiny_test_map()
	tfv.layout = HexLayoutScript.new()
	var cam = MapCameraScript.new()
	cam.projection = MapPlaneProjectionScript.new()
	tfv.camera = cam
	tfv.scenario = null
	tfv.forest_density_ratio = 1.0
	tfv.use_forest_symbol_scatter = true
	tfv.forest_grid_debug_isolated = true
	tfv.forest_grid_debug_isolated_one_hex = true
	tfv.forest_grid_debug_draw_roots = true
	tfv.forest_grid_debug_suppress_map_back = true
	tfv.forest_grid_debug_perfect = perfect_export
	tfv.forest_grid_debug_draw_jitter_circles = true


func _run_isolated_draw_assertions() -> void:
	var rt: Node = get_root()
	var tfv = TerrainForegroundViewScript.new()
	_tfv_attach_isolated(tfv, true)
	TerrainForegroundViewScript.debug_last_isolated_grid_symbols_drawn = -1
	await process_frame
	tfv.queue_redraw()
	await process_frame
	var sym_p: int = TerrainForegroundViewScript.debug_last_isolated_grid_symbols_drawn
	var rm_p: int = TerrainForegroundViewScript.debug_last_isolated_grid_root_markers_drawn
	rt.remove_child(tfv)
	tfv.queue_free()
	if sym_p != _EXPECT_GRID_SLOTS:
		push_error(
			"FAIL: isolated perfect expected %d grid symbols got %d (symbol scatter / assets loaded?)"
			% [_EXPECT_GRID_SLOTS, sym_p]
		)
		call_deferred("quit", 1)
		return
	if TerrainForegroundViewScript.debug_pipeline_tfv_front_proc != 0:
		push_error(
			"FAIL: isolated perfect expected tfv_front_proc=0 got %d"
			% TerrainForegroundViewScript.debug_pipeline_tfv_front_proc
		)
		call_deferred("quit", 1)
		return
	if TerrainForegroundViewScript.debug_pipeline_tfv_front_asset != 0:
		push_error(
			"FAIL: isolated perfect expected tfv_front_asset=0 got %d"
			% TerrainForegroundViewScript.debug_pipeline_tfv_front_asset
		)
		call_deferred("quit", 1)
		return
	if TerrainForegroundViewScript.debug_pipeline_tfv_grid_upper_symbols != _EXPECT_UPPER_SLOTS:
		push_error(
			"FAIL: isolated perfect expected upper grid symbols=%d got %d"
			% [_EXPECT_UPPER_SLOTS, TerrainForegroundViewScript.debug_pipeline_tfv_grid_upper_symbols]
		)
		call_deferred("quit", 1)
		return
	if TerrainForegroundViewScript.debug_pipeline_tfv_grid_lower_symbols != _EXPECT_UPPER_SLOTS:
		push_error(
			"FAIL: isolated perfect expected lower grid symbols=%d got %d"
			% [_EXPECT_UPPER_SLOTS, TerrainForegroundViewScript.debug_pipeline_tfv_grid_lower_symbols]
		)
		call_deferred("quit", 1)
		return
	if rm_p != _EXPECT_GRID_SLOTS:
		push_error("FAIL: isolated perfect expected %d root markers got %d" % [_EXPECT_GRID_SLOTS, rm_p])
		call_deferred("quit", 1)
		return
	if TerrainForegroundViewScript.debug_last_isolated_jitter_ring_draws != _EXPECT_GRID_SLOTS:
		push_error(
			"FAIL: isolated perfect + jitter circles expected %d ring draws got %d"
			% [_EXPECT_GRID_SLOTS, TerrainForegroundViewScript.debug_last_isolated_jitter_ring_draws]
		)
		call_deferred("quit", 1)
		return
	tfv = TerrainForegroundViewScript.new()
	_tfv_attach_isolated(tfv, false)
	TerrainForegroundViewScript.debug_last_isolated_grid_symbols_drawn = -1
	await process_frame
	tfv.queue_redraw()
	await process_frame
	var sym_n: int = TerrainForegroundViewScript.debug_last_isolated_grid_symbols_drawn
	var rm_n: int = TerrainForegroundViewScript.debug_last_isolated_grid_root_markers_drawn
	rt.remove_child(tfv)
	tfv.queue_free()
	if sym_n != _EXPECT_GRID_SLOTS:
		push_error("FAIL: isolated normal expected %d grid symbols got %d" % [_EXPECT_GRID_SLOTS, sym_n])
		call_deferred("quit", 1)
		return
	if rm_n != _EXPECT_GRID_SLOTS:
		push_error("FAIL: isolated normal expected %d root markers got %d" % [_EXPECT_GRID_SLOTS, rm_n])
		call_deferred("quit", 1)
		return
	if TerrainForegroundViewScript.debug_last_isolated_jitter_ring_draws != _EXPECT_GRID_SLOTS:
		push_error(
			"FAIL: isolated normal + jitter circles expected %d ring draws got %d"
			% [_EXPECT_GRID_SLOTS, TerrainForegroundViewScript.debug_last_isolated_jitter_ring_draws]
		)
		call_deferred("quit", 1)
		return
	print("PASS forest_front_grid")
	call_deferred("quit", 0)


func _init() -> void:
	var layout = HexLayoutScript.new()
	var n: int = TerrainForegroundViewScript.forest_grid_slot_count()
	if n != _EXPECT_GRID_SLOTS:
		push_error("FAIL: expected %d grid slots got %d" % [_EXPECT_GRID_SLOTS, n])
		call_deferred("quit", 1)
		return
	var H: float = HexLayoutScript.SIZE
	var P_frac: float = TerrainForegroundViewScript.forest_grid_row_pitch_frac()
	var A_frac: float = TerrainForegroundViewScript.forest_grid_two_slot_x_frac()
	var B_frac: float = TerrainForegroundViewScript.forest_grid_three_slot_x_frac()
	var Fo_frac: float = TerrainForegroundViewScript.forest_grid_five_slot_x_outer_frac()
	var Fi_frac: float = TerrainForegroundViewScript.forest_grid_five_slot_x_inner_frac()
	if not is_equal_approx(
		TerrainForegroundViewScript.forest_grid_row_pitch_design_frac(), _EXPECT_ROW_PITCH_FRAC
	):
		push_error(
			"FAIL: _GRID_ROW_PITCH_FRAC (design) expected %.4f got %.4f"
			% [_EXPECT_ROW_PITCH_FRAC, TerrainForegroundViewScript.forest_grid_row_pitch_design_frac()]
		)
		call_deferred("quit", 1)
		return
	if not is_equal_approx(P_frac, _EXPECT_ROW_PITCH_FRAC):
		push_error(
			"FAIL: forest_grid_row_pitch_frac expected %.4f got %.4f" % [_EXPECT_ROW_PITCH_FRAC, P_frac]
		)
		call_deferred("quit", 1)
		return
	if B_frac <= 0.47 + 1e-4:
		push_error(
			"FAIL: three-slot should be wider than previous 0.47 for this slice, got %.6f"
			% B_frac
		)
		call_deferred("quit", 1)
		return
	var y2_abs: float = TerrainForegroundViewScript.forest_grid_two_slot_row_abs_y_frac()
	if not is_equal_approx(y2_abs, 2.5 * P_frac):
		push_error("FAIL: two-slot |y|/H should be 2.5×P")
		call_deferred("quit", 1)
		return
	if not is_equal_approx(A_frac, TerrainForegroundViewScript._GRID_TWO_SLOT_X_FRAC):
		push_error(
			"FAIL: two-slot |x|/H expected %.6f (reverted), got %.6f"
			% [TerrainForegroundViewScript._GRID_TWO_SLOT_X_FRAC, A_frac]
		)
		call_deferred("quit", 1)
		return
	var hex2: float = TerrainForegroundViewScript.forest_grid_hex_half_width_frac_at_local_y_frac(y2_abs)
	if A_frac + TerrainForegroundViewScript.forest_grid_eff_R_frac() > hex2 + 1e-4:
		push_error("FAIL: two-slot |x|+(R+M) must not exceed hex_half at row y")
		call_deferred("quit", 1)
		return
	if not is_equal_approx(B_frac, TerrainForegroundViewScript._GRID_THREE_SLOT_X_FRAC):
		push_error(
			"FAIL: three-slot wing |x|/H expected %.6f (tuned), got %.6f"
			% [TerrainForegroundViewScript._GRID_THREE_SLOT_X_FRAC, B_frac]
		)
		call_deferred("quit", 1)
		return
	var R_frac: float = TerrainForegroundViewScript._GRID_JITTER_RADIUS_FRAC
	var y5_abs: float = TerrainForegroundViewScript.forest_grid_five_slot_row_abs_y_frac()
	var hex5: float = TerrainForegroundViewScript.forest_grid_hex_half_width_frac_at_local_y_frac(y5_abs)
	var outer_vis_target: float = hex5 - 1.5 * R_frac
	var outer_safe_target: float = hex5 - TerrainForegroundViewScript.forest_grid_eff_R_frac()
	var Fo_target: float = minf(outer_vis_target, outer_safe_target)
	if not is_equal_approx(Fo_frac, Fo_target):
		push_error(
			"FAIL: five-slot outer_x/H expected min(hex−1.5R, hex−(R+M))=%.6f got %.6f"
			% [Fo_target, Fo_frac]
		)
		call_deferred("quit", 1)
		return
	var s5_expect: float = TerrainForegroundViewScript.forest_grid_five_slot_column_step_frac_for_row_y_frac(y5_abs)
	if not is_equal_approx(Fi_frac, s5_expect) or not is_equal_approx(Fo_frac, 2.0 * s5_expect):
		push_error(
			"FAIL: five-slot must use x∈{−2s,−s,0,s,2s}; s=%.6f Fi=%.6f Fo=%.6f"
			% [s5_expect, Fi_frac, Fo_frac]
		)
		call_deferred("quit", 1)
		return
	var vis_gap: float = TerrainForegroundViewScript.forest_grid_five_slot_edge_gap_visible_frac_for_row_y_frac(y5_abs)
	if not is_equal_approx(vis_gap, 0.5 * R_frac):
		push_error(
			"FAIL: visible edge gap (hex−outer−R)/H should be 0.5×R/H; got %.6f want %.6f"
			% [vis_gap, 0.5 * R_frac]
		)
		call_deferred("quit", 1)
		return
	if Fo_frac + TerrainForegroundViewScript.forest_grid_eff_R_frac() > hex5 + 1e-4:
		push_error(
			"FAIL: five-slot outer + (R+M)/H must not exceed hex_half/H"
		)
		call_deferred("quit", 1)
		return
	var safe5_deprecated: float = TerrainForegroundViewScript.forest_grid_safe_half_width_frac_at_local_y_frac(y5_abs)
	var wrong_outer_scale: float = 0.8 * safe5_deprecated
	if absf(Fo_frac - wrong_outer_scale) < 0.035:
		push_error(
			"FAIL: outer_x/H too close to deprecated narrow rule 0.8×safe_half (≈%.5f); got %.6f"
			% [wrong_outer_scale, Fo_frac]
		)
		call_deferred("quit", 1)
		return
	if Fo_frac < 0.62:
		push_error(
			"FAIL: five-slot outer should be wide (continuous-edge rule); %.4f is suspiciously narrow"
			% Fo_frac
		)
		call_deferred("quit", 1)
		return
	var R_world: float = TerrainForegroundViewScript.forest_grid_jitter_max_radius_world()
	var P_world_check: float = TerrainForegroundViewScript.forest_grid_row_pitch_world()
	if not is_equal_approx(P_world_check, _EXPECT_ROW_PITCH_FRAC * H):
		push_error(
			"FAIL: row pitch world expected %.6f (P/H=%.4f) got %.6f"
			% [_EXPECT_ROW_PITCH_FRAC * H, _EXPECT_ROW_PITCH_FRAC, P_world_check]
		)
		call_deferred("quit", 1)
		return
	if not is_equal_approx(P_world_check, P_frac * H):
		push_error("FAIL: row_pitch_world vs P_frac*H mismatch")
		call_deferred("quit", 1)
		return
	var gap_frac: float = TerrainForegroundViewScript.forest_grid_vertical_gap_jitter_edges_frac()
	var gap_world: float = TerrainForegroundViewScript.forest_grid_row_jitter_circle_gap_world()
	var R_j_frac: float = R_world / H
	if not is_equal_approx(gap_frac, P_frac - 2.0 * R_j_frac):
		push_error(
			"FAIL: row jitter gap/H expected P/H-2*R/H=%.8f got %.8f"
			% [P_frac - 2.0 * R_j_frac, gap_frac]
		)
		call_deferred("quit", 1)
		return
	if not is_equal_approx(gap_world, P_world_check - 2.0 * R_world):
		push_error("FAIL: row_jitter_circle_gap_world mismatch")
		call_deferred("quit", 1)
		return
	if gap_frac <= _LEGACY_ROW_JITTER_GAP_FRAC_BEFORE_PITCH_MODEL:
		push_error(
			"FAIL: row jitter gap/H should exceed legacy ~PNG-padding model upper bound %.4f, got %.6f"
			% [_LEGACY_ROW_JITTER_GAP_FRAC_BEFORE_PITCH_MODEL, gap_frac]
		)
		call_deferred("quit", 1)
		return
	if not is_equal_approx(
		TerrainForegroundViewScript.forest_grid_debug_jitter_circle_radius_world(), R_world
	):
		push_error("FAIL: debug jitter circle radius must equal production R_jitter")
		call_deferred("quit", 1)
		return
	if gap_frac <= 0.0:
		push_error("FAIL: row edge gap must be > 0, got %.6f" % gap_frac)
		call_deferred("quit", 1)
		return
	var safe_r: float = TerrainForegroundViewScript.forest_grid_safe_disk_radius_world()
	var r_expect: float = (
		TerrainForegroundViewScript.forest_grid_jitter_max_radius_world()
		+ TerrainForegroundViewScript.forest_grid_safety_margin_world()
	)
	if not is_equal_approx(safe_r, r_expect):
		push_error("FAIL: safe disk radius mismatch")
		call_deferred("quit", 1)
		return
	var row_fracs: Array[PackedVector2Array] = [
		PackedVector2Array([Vector2(-A_frac, -2.5 * P_frac), Vector2(A_frac, -2.5 * P_frac)]),
		PackedVector2Array(
			[
				Vector2(-B_frac, -1.5 * P_frac),
				Vector2(0.0, -1.5 * P_frac),
				Vector2(B_frac, -1.5 * P_frac),
			]
		),
		PackedVector2Array(
			[
				Vector2(-Fo_frac, -0.5 * P_frac),
				Vector2(-Fi_frac, -0.5 * P_frac),
				Vector2(0.0, -0.5 * P_frac),
				Vector2(Fi_frac, -0.5 * P_frac),
				Vector2(Fo_frac, -0.5 * P_frac),
			]
		),
		PackedVector2Array(
			[
				Vector2(-Fo_frac, 0.5 * P_frac),
				Vector2(-Fi_frac, 0.5 * P_frac),
				Vector2(0.0, 0.5 * P_frac),
				Vector2(Fi_frac, 0.5 * P_frac),
				Vector2(Fo_frac, 0.5 * P_frac),
			]
		),
		PackedVector2Array(
			[
				Vector2(-B_frac, 1.5 * P_frac),
				Vector2(0.0, 1.5 * P_frac),
				Vector2(B_frac, 1.5 * P_frac),
			]
		),
		PackedVector2Array([Vector2(-A_frac, 2.5 * P_frac), Vector2(A_frac, 2.5 * P_frac)]),
	]
	var exp_fracs: Array[Vector2] = []
	var rfi: int = 0
	while rfi < row_fracs.size():
		var jdx: int = 0
		while jdx < row_fracs[rfi].size():
			exp_fracs.append(row_fracs[rfi][jdx])
			jdx += 1
		rfi += 1
	if exp_fracs.size() != n:
		push_error("FAIL: exp_fracs size=%d expected n=%d" % [exp_fracs.size(), n])
		call_deferred("quit", 1)
		return
	var row_bucket: Array[int] = [
		0, 0, 1, 1, 1, 2, 2, 2, 2, 2, 3, 3, 3, 3, 3, 4, 4, 4, 5, 5,
	]
	var row_tot: Array[int] = [0, 0, 0, 0, 0, 0]
	var ej: int = 0
	while ej < n:
		var got_b: Vector2 = TerrainForegroundViewScript.forest_grid_slot_base_local(ej)
		var want_b: Vector2 = exp_fracs[ej] * H
		if not got_b.is_equal_approx(want_b):
			push_error(
				"FAIL: slot %d base local expected %s got %s"
				% [ej, want_b, got_b]
			)
			call_deferred("quit", 1)
			return
		row_tot[row_bucket[ej]] += 1
		ej += 1
	if row_tot != [2, 3, 5, 5, 3, 2]:
		push_error("FAIL: row structure must be 2/3/5/5/3/2; counts=%s" % row_tot)
		call_deferred("quit", 1)
		return
	var row_first: Array[int] = [0, 2, 5, 10, 15, 18]
	var row_y: Array[float] = []
	var ryi: int = 0
	while ryi < row_first.size():
		row_y.append(TerrainForegroundViewScript.forest_grid_slot_base_local(row_first[ryi]).y)
		ryi += 1
	var rm: int = 0
	while rm < 6:
		if not is_equal_approx(row_y[rm] / H, _EXPECT_ROW_Y_OVER_H[rm]):
			push_error(
				"FAIL: row %d y/H expected %.5f (0.28 pitch model) got %.5f"
				% [rm, _EXPECT_ROW_Y_OVER_H[rm], row_y[rm] / H]
			)
			call_deferred("quit", 1)
			return
		if not is_equal_approx(_EXPECT_ROW_Y_OVER_H[rm], (-2.5 + float(rm)) * P_frac):
			push_error("FAIL: _EXPECT_ROW_Y_OVER_H[%d] out of sync with P/H" % rm)
			call_deferred("quit", 1)
			return
		rm += 1
	var P_world: float = TerrainForegroundViewScript.forest_grid_row_pitch_world()
	var pr: int = 1
	while pr < 6:
		var dyp: float = row_y[pr] - row_y[pr - 1]
		if not is_equal_approx(absf(dyp), P_world):
			push_error(
				"FAIL: uniform row pitch: |y_row%d - y_row%d| expected %.4f got %.4f"
				% [pr, pr - 1, P_world, absf(dyp)]
			)
			call_deferred("quit", 1)
			return
		pr += 1
	var gap_from_pitch: float = absf(row_y[1] - row_y[0]) - 2.0 * R_world
	if not is_equal_approx(gap_from_pitch, gap_world):
		push_error(
			"FAIL: vertical circle-edge gap world %.4f vs forest_grid_row_jitter_circle_gap_world %.4f"
			% [gap_from_pitch, gap_world]
		)
		call_deferred("quit", 1)
		return
	var symr: int = 0
	while symr < 3:
		if not is_equal_approx(row_y[symr], -row_y[5 - symr]):
			push_error(
				"FAIL: row Y symmetry: row %d vs %d (%.6f vs %.6f)"
				% [symr, 5 - symr, row_y[symr], row_y[5 - symr]]
			)
			call_deferred("quit", 1)
			return
		symr += 1
	var s_top_l: Vector2 = TerrainForegroundViewScript.forest_grid_slot_base_local(0)
	var s_top_r: Vector2 = TerrainForegroundViewScript.forest_grid_slot_base_local(1)
	var s_bot_l: Vector2 = TerrainForegroundViewScript.forest_grid_slot_base_local(18)
	var s_bot_r: Vector2 = TerrainForegroundViewScript.forest_grid_slot_base_local(19)
	if (
		not is_equal_approx(absf(s_top_l.x), absf(s_top_r.x))
		or not is_equal_approx(absf(s_bot_l.x), absf(s_bot_r.x))
	):
		push_error("FAIL: two-slot rows need symmetric ±x wings within row")
		call_deferred("quit", 1)
		return
	if not is_equal_approx(absf(s_top_l.x), absf(s_bot_l.x)):
		push_error("FAIL: two-slot rows must share |x| (top vs bottom)")
		call_deferred("quit", 1)
		return
	if not is_equal_approx(absf(s_top_l.x) / H, A_frac):
		push_error("FAIL: two-slot |x|/H expected %.4f" % A_frac)
		call_deferred("quit", 1)
		return
	var lx2: float = TerrainForegroundViewScript.forest_grid_slot_base_local(2).x
	var lx4: float = TerrainForegroundViewScript.forest_grid_slot_base_local(4).x
	var lx3: float = TerrainForegroundViewScript.forest_grid_slot_base_local(3).x
	if not is_equal_approx(lx3, 0.0):
		push_error("FAIL: middle slot of three-row bands must be on vertical axis")
		call_deferred("quit", 1)
		return
	if not is_equal_approx(absf(lx2), absf(lx4)):
		push_error("FAIL: three-row bands must have symmetric ±x wings (upper)")
		call_deferred("quit", 1)
		return
	if not is_equal_approx(absf(lx2) / H, B_frac):
		push_error("FAIL: three-slot |x|/H expected %.4f" % B_frac)
		call_deferred("quit", 1)
		return
	var l15: Vector2 = TerrainForegroundViewScript.forest_grid_slot_base_local(15)
	var l17: Vector2 = TerrainForegroundViewScript.forest_grid_slot_base_local(17)
	var l16: Vector2 = TerrainForegroundViewScript.forest_grid_slot_base_local(16)
	if not is_equal_approx(l16.x, 0.0):
		push_error("FAIL: lower three-row center must be on vertical axis")
		call_deferred("quit", 1)
		return
	if not is_equal_approx(absf(l15.x), absf(l17.x)) or not is_equal_approx(absf(l15.x) / H, B_frac):
		push_error("FAIL: lower three-row wings must mirror upper three-row")
		call_deferred("quit", 1)
		return
	var s5: Vector2 = TerrainForegroundViewScript.forest_grid_slot_base_local(5)
	var s14: Vector2 = TerrainForegroundViewScript.forest_grid_slot_base_local(14)
	if not is_equal_approx(s5.x, -s14.x) or not is_equal_approx(s5.y, -s14.y):
		push_error("FAIL: five-slot outer wings must be origin-symmetric (slot 5 vs 14)")
		call_deferred("quit", 1)
		return
	var s9: Vector2 = TerrainForegroundViewScript.forest_grid_slot_base_local(9)
	if not is_equal_approx(s9.x, s14.x) or not is_equal_approx(s9.y, -s14.y):
		push_error("FAIL: five-slot right column must mirror across y=0 (slot 9 vs 14)")
		call_deferred("quit", 1)
		return
	var s10v: Vector2 = TerrainForegroundViewScript.forest_grid_slot_base_local(10)
	if not is_equal_approx(s5.x, s10v.x) or not is_equal_approx(s5.y, -s10v.y):
		push_error("FAIL: five-slot left column must mirror across y=0 (slot 5 vs 10)")
		call_deferred("quit", 1)
		return
	var s6: Vector2 = TerrainForegroundViewScript.forest_grid_slot_base_local(6)
	var s11: Vector2 = TerrainForegroundViewScript.forest_grid_slot_base_local(11)
	if not is_equal_approx(s6.x, s11.x) or not is_equal_approx(s6.y, -s11.y):
		push_error("FAIL: five-slot inner-left column must mirror across y=0 (slot 6 vs 11)")
		call_deferred("quit", 1)
		return
	var s8: Vector2 = TerrainForegroundViewScript.forest_grid_slot_base_local(8)
	var s13: Vector2 = TerrainForegroundViewScript.forest_grid_slot_base_local(13)
	if not is_equal_approx(s8.x, s13.x) or not is_equal_approx(s8.y, -s13.y):
		push_error("FAIL: five-slot inner-right column must mirror across y=0 (slot 8 vs 13)")
		call_deferred("quit", 1)
		return
	var s7: Vector2 = TerrainForegroundViewScript.forest_grid_slot_base_local(7)
	var s12v: Vector2 = TerrainForegroundViewScript.forest_grid_slot_base_local(12)
	if not is_equal_approx(s7.x, 0.0) or not is_equal_approx(s12v.x, 0.0):
		push_error("FAIL: five-slot spine centers must sit on x=0")
		call_deferred("quit", 1)
		return
	if not is_equal_approx(s7.y, -s12v.y):
		push_error("FAIL: five-slot spine must mirror across y=0 (slot 7 vs 12)")
		call_deferred("quit", 1)
		return
	var d56: float = TerrainForegroundViewScript.forest_grid_slot_base_local(6).x - TerrainForegroundViewScript.forest_grid_slot_base_local(5).x
	var d89: float = TerrainForegroundViewScript.forest_grid_slot_base_local(9).x - TerrainForegroundViewScript.forest_grid_slot_base_local(8).x
	if not is_equal_approx(d56 / H, s5_expect) or not is_equal_approx(d89 / H, s5_expect):
		push_error(
			"FAIL: five-slot horizontal step outer→inner must be s/H; d56/H=%.5f d89/H=%.5f s=%.5f"
			% [d56 / H, d89 / H, s5_expect]
		)
		call_deferred("quit", 1)
		return
	var si: int = 0
	while si < n:
		var loff: Vector2 = TerrainForegroundViewScript.forest_grid_slot_base_local(si)
		var cat: int = TerrainForegroundViewScript.forest_grid_local_depth_category(loff)
		var want: int = -1 if loff.y < 0.0 else 1
		if cat != want:
			push_error("FAIL: slot %d loff=%s cat=%d want=%d" % [si, loff, cat, want])
			call_deferred("quit", 1)
			return
		if not layout.is_point_inside_hex_local(loff):
			push_error("FAIL: slot %d base local %s outside pointy hex footprint" % [si, loff])
			call_deferred("quit", 1)
			return
		if not _assert_disk_samples_inside_hex(layout, loff, safe_r, si, 32):
			call_deferred("quit", 1)
			return
		if not _assert_full_jitter_offsets_inside_hex(layout, si):
			call_deferred("quit", 1)
			return
		si += 1
	var z = TerrainForegroundViewScript.forest_grid_jitter_local_deterministic(7, -3, 2, true)
	if z.length_squared() > 0.000001:
		push_error("FAIL: perfect no-jitter should be zero, got %s" % z)
		call_deferred("quit", 1)
		return
	var j_a: Vector2 = TerrainForegroundViewScript.forest_grid_jitter_local_deterministic(1, 2, 3, false)
	var j_b: Vector2 = TerrainForegroundViewScript.forest_grid_jitter_local_deterministic(1, 2, 3, false)
	if not j_a.is_equal_approx(j_b):
		push_error("FAIL: jitter not deterministic for same cell")
		call_deferred("quit", 1)
		return
	if TerrainForegroundViewScript.forest_grid_symbol_rect_cap_per_decorated_hex(false) != _EXPECT_GRID_SLOTS:
		push_error("FAIL: expected cap %d for non-city decorated hex" % _EXPECT_GRID_SLOTS)
		call_deferred("quit", 1)
		return
	if TerrainForegroundViewScript.forest_grid_symbol_rect_cap_per_decorated_hex(true) != _EXPECT_UPPER_SLOTS:
		push_error(
			"FAIL: expected cap %d when lower band skipped (city)" % _EXPECT_UPPER_SLOTS
		)
		call_deferred("quit", 1)
		return
	# **Authoritative path:** mix hashes + **for_tests** must match **forest_grid_jitter_local_deterministic**.
	var R_mix: float = TerrainForegroundViewScript.forest_grid_jitter_max_radius_world()
	var s_mix: int = 0
	while s_mix < n:
		var mx: Vector2i = TerrainForegroundViewScript.forest_grid_jitter_mix_hashes(1, -2, s_mix)
		var j_from_h: Vector2 = TerrainForegroundViewScript.forest_grid_jitter_local_for_tests(
			mx.x, mx.y, R_mix
		)
		var j_det: Vector2 = TerrainForegroundViewScript.forest_grid_jitter_local_deterministic(
			1, -2, s_mix, false
		)
		if not j_from_h.is_equal_approx(j_det):
			push_error(
				"FAIL: forest_grid_jitter_local_for_tests(mix) != deterministic for (1,-2) slot=%d h=(%d,%d) j_h=%s j_d=%s"
				% [s_mix, mx.x, mx.y, j_from_h, j_det]
			)
			call_deferred("quit", 1)
			return
		s_mix += 1
	var qh: int = _JITTER_SAMPLE_Q
	var rh: int = _JITTER_SAMPLE_R
	var slot_vecs: Array[Vector2] = []
	var svi: int = 0
	while svi < n:
		slot_vecs.append(
			TerrainForegroundViewScript.forest_grid_jitter_local_deterministic(qh, rh, svi, false)
		)
		svi += 1
	var nz0: int = -1
	var svj: int = 0
	while svj < n:
		if slot_vecs[svj].length_squared() > 1e-12:
			nz0 = svj
			break
		svj += 1
	if nz0 < 0:
		push_error("FAIL: hex (%d,%d) expected at least one non-zero jitter among %d slots" % [qh, rh, n])
		call_deferred("quit", 1)
		return
	var dir_diff: bool = false
	var svk: int = 0
	while svk < n:
		var v_a: Vector2 = slot_vecs[nz0]
		var v_b: Vector2 = slot_vecs[svk]
		if v_b.length_squared() > 1e-12 and not v_a.is_equal_approx(v_b):
			dir_diff = true
			break
		svk += 1
	if not dir_diff:
		push_error(
			"FAIL: hex (%d,%d) slots should not all share identical jitter; vecs=%s"
			% [qh, rh, str(slot_vecs)]
		)
		call_deferred("quit", 1)
		return
	var theta_bucket: Dictionary = {}
	var rad_key: Dictionary = {}
	var svt: int = 0
	while svt < n:
		var vt: Vector2 = slot_vecs[svt]
		if vt.length_squared() > 1e-12:
			var ang_t: float = atan2(vt.y, vt.x)
			var bkt: int = int(floor((ang_t + PI) / TAU * 32.0))
			bkt = clampi(bkt, 0, 31)
			theta_bucket[bkt] = true
			var rk: int = int(round(vt.length() / R_world * 1000.0))
			rad_key[rk] = true
		svt += 1
	if theta_bucket.size() < 7:
		push_error(
			"FAIL: expected >=7 distinct angle buckets (32-bin) on (%d,%d), got %d"
			% [qh, rh, theta_bucket.size()]
		)
		call_deferred("quit", 1)
		return
	if rad_key.size() < 5:
		push_error(
			"FAIL: expected >=5 distinct jitter radii (mille-R) on (%d,%d), got %d"
			% [qh, rh, rad_key.size()]
		)
		call_deferred("quit", 1)
		return
	var col_groups: Array = [
		[0, 2, 5, 10, 15, 18],
		[1, 4, 9, 14, 17, 19],
		[3, 7, 12, 16],
		[6, 11],
		[8, 13],
	]
	var cgi: int = 0
	while cgi < col_groups.size():
		var cg: Array = col_groups[cgi]
		if _forest_column_group_all_near_parallel(qh, rh, cg, 0.95):
			push_error(
				(
					"FAIL: column slots "
					+ str(cg)
					+ (
						" on (%d,%d): all pairwise directions |dot|>0.95 (residual correlation)"
						% [qh, rh]
					)
				)
			)
			call_deferred("quit", 1)
			return
		cgi += 1
	var j_hex_a: Vector2 = TerrainForegroundViewScript.forest_grid_jitter_local_deterministic(
		0, 0, 12, false
	)
	var j_hex_b: Vector2 = TerrainForegroundViewScript.forest_grid_jitter_local_deterministic(
		2, -1, 12, false
	)
	var j_hex_c: Vector2 = TerrainForegroundViewScript.forest_grid_jitter_local_deterministic(
		-3, 2, 12, false
	)
	if j_hex_a.is_equal_approx(j_hex_b) and j_hex_a.is_equal_approx(j_hex_c):
		push_error(
			(
				"FAIL: slot 12 jitter identical on hexes (0,0) vs (2,-1) vs (-3,2): %s — unlikely except hash bug"
				% j_hex_a
			)
		)
		call_deferred("quit", 1)
		return
	var ep0: Vector2 = TerrainForegroundViewScript.forest_grid_exaggerated_probe_slot_local(0)
	var cn0: Vector2 = TerrainForegroundViewScript.forest_grid_slot_base_local(0)
	if ep0.is_equal_approx(cn0):
		push_error(
			"FAIL: exaggerated layout probe slot 0 must differ from canonical forest_grid_slot_base_local"
		)
		call_deferred("quit", 1)
		return
	var found_nonzero: bool = false
	var fq: int = 0
	var fr: int = 0
	var fs: int = 0
	var fj: Vector2 = Vector2.ZERO
	var qq: int = -4
	while qq <= 4:
		var rr: int = -4
		while rr <= 4:
			var tt: int = 0
			while tt < n:
				var jj: Vector2 = TerrainForegroundViewScript.forest_grid_jitter_local_deterministic(qq, rr, tt, false)
				if jj.length_squared() > 1e-12:
					found_nonzero = true
					fq = qq
					fr = rr
					fs = tt
					fj = jj
					break
				tt += 1
			if found_nonzero:
				break
			rr += 1
		if found_nonzero:
			break
		qq += 1
	if not found_nonzero:
		push_error("FAIL: expected at least one non-zero jitter in a small (q,r,slot) grid")
		call_deferred("quit", 1)
		return
	var base_found: Vector2 = TerrainForegroundViewScript.forest_grid_slot_base_local(fs)
	var root_found: Vector2 = base_found + fj
	if root_found.is_equal_approx(base_found):
		push_error("FAIL: root_local = base + jitter must differ from base when jitter non-zero")
		call_deferred("quit", 1)
		return
	var h_t0: int = 0x00FF1234
	var h_r0: int = 0x00ABCDEF
	var r0: float = TerrainForegroundViewScript.forest_grid_jitter_local_for_tests(
		h_t0, h_r0, 0.0
	).length()
	if r0 > 0.000001:
		push_error("FAIL: zero radius should give zero jitter")
		call_deferred("quit", 1)
		return
	var r_max_w: float = TerrainForegroundViewScript.forest_grid_jitter_max_radius_world()
	var j_max: Vector2 = TerrainForegroundViewScript.forest_grid_jitter_local_for_tests(
		0xFFFFFFFF, 0xFFFFFF, r_max_w
	)
	if j_max.length() > r_max_w * 1.0001:
		push_error("FAIL: jitter length should not exceed R_max")
		call_deferred("quit", 1)
		return
	var jz_u2: Vector2 = TerrainForegroundViewScript.forest_grid_jitter_local_for_tests(
		0xABCDEF, 0, r_max_w
	)
	if jz_u2.length_squared() > 1e-12:
		push_error("FAIL: radial u2=0 must yield zero jitter got %s" % jz_u2)
		call_deferred("quit", 1)
		return
	var j_pi: Vector2 = TerrainForegroundViewScript.forest_grid_jitter_local_for_tests(
		0x80000000, 0xFFFFFF, r_max_w
	)
	if abs(j_pi.y) > r_max_w * 0.01 or j_pi.x > -0.01:
		push_error(
			"FAIL: theta=pi u2~1 should give ~(-R,0) got %s R=%.6f"
			% [j_pi, r_max_w]
		)
		call_deferred("quit", 1)
		return
	var near_edge_ct: int = 0
	var interior_ct: int = 0
	var total_s: int = 0
	var qq2: int = -6
	while qq2 <= 6:
		var rr2: int = -6
		while rr2 <= 6:
			var sl: int = 0
			while sl < n:
				var jjv: Vector2 = TerrainForegroundViewScript.forest_grid_jitter_local_deterministic(
					qq2, rr2, sl, false
				)
				var lenv: float = jjv.length()
				if lenv < 1e-6:
					sl += 1
					continue
				total_s += 1
				if lenv > 0.97 * r_max_w:
					near_edge_ct += 1
				if lenv < 0.72 * r_max_w:
					interior_ct += 1
				sl += 1
			rr2 += 1
		qq2 += 1
	if total_s < 160:
		push_error("FAIL: expected many non-zero jitter samples in coarse scan got %d" % total_s)
		call_deferred("quit", 1)
		return
	if interior_ct < 20:
		push_error(
			(
				"FAIL: uniform disk sampling should yield interior radii; interior_ct=%d total=%d (circumference bug?)"
			)
			% [interior_ct, total_s]
		)
		call_deferred("quit", 1)
		return
	if near_edge_ct > int(ceil(float(total_s) * 0.55)):
		push_error(
			(
				"FAIL: too many near-R jitter samples (%d/%d); likely circumferential bias"
			)
			% [near_edge_ct, total_s]
		)
		call_deferred("quit", 1)
		return
	var s0: int = 0
	while s0 < n:
		var jz: Vector2 = TerrainForegroundViewScript.forest_grid_jitter_local_deterministic(
			fq, fr, s0, true
		)
		if jz.length_squared() > 1e-12:
			push_error(
				"FAIL: perfect mode (no_jitter) must be zero for all slots; failed at %d got %s"
				% [s0, jz]
			)
			call_deferred("quit", 1)
			return
		s0 += 1
	var nonzero_normal_slots: int = 0
	var s1: int = 0
	while s1 < n:
		if TerrainForegroundViewScript.forest_grid_jitter_local_deterministic(
			fq, fr, s1, false
		).length_squared() > 1e-12:
			nonzero_normal_slots += 1
		s1 += 1
	if nonzero_normal_slots < 1:
		push_error(
			"FAIL: normal mode (jitter on) expected at least one nonzero jitter among %d slots for sample hex"
			% n
		)
		call_deferred("quit", 1)
		return
	var sv: int = 0
	while sv < n:
		var base_v: Vector2 = TerrainForegroundViewScript.forest_grid_slot_base_local(sv)
		var jit_v: Vector2 = TerrainForegroundViewScript.forest_grid_jitter_local_deterministic(
			fq, fr, sv, false
		)
		var root_v: Vector2 = base_v + jit_v
		if not layout.is_point_inside_hex_local(root_v):
			push_error("FAIL: jittered root outside hex slot=%d root=%s" % [sv, root_v])
			call_deferred("quit", 1)
			return
		if jit_v.length() > R_world + 1e-5:
			push_error(
				"FAIL: jitter must lie within R_jitter disk slot=%d len=%.6f R=%.6f"
				% [sv, jit_v.length(), R_world]
			)
			call_deferred("quit", 1)
			return
		sv += 1
	var cr: float = TerrainForegroundViewScript.forest_grid_debug_root_marker_circle_radius_px()
	var xh: float = TerrainForegroundViewScript.forest_grid_debug_root_marker_cross_half_px()
	if cr <= 0.0 or xh <= 0.0:
		push_error("FAIL: debug root marker px accessors should be positive")
		call_deferred("quit", 1)
		return
	var rp_test: Vector2 = Vector2(100.0, 250.0)
	var side_test: float = 40.0
	var bc_test: Vector2 = TerrainForegroundViewScript.forest_grid_texture_rect_bottom_center(
		rp_test, side_test
	)
	if not bc_test.is_equal_approx(rp_test):
		push_error(
			"FAIL: texture rect bottom-center should equal intended root when pad=0 got %s want %s"
			% [bc_test, rp_test]
		)
		call_deferred("quit", 1)
		return
	var pad_test: float = 10.0
	var raw_padded: Vector2 = TerrainForegroundViewScript.forest_grid_texture_rect_bottom_center(
		rp_test, side_test, pad_test
	)
	var want_raw: Vector2 = Vector2(rp_test.x, rp_test.y + pad_test)
	if not raw_padded.is_equal_approx(want_raw):
		push_error(
			"FAIL: padded tree rect raw bottom-center got %s want %s"
			% [raw_padded, want_raw]
		)
		call_deferred("quit", 1)
		return
	var eff_tree: Vector2 = raw_padded - Vector2(0.0, pad_test)
	if not eff_tree.is_equal_approx(rp_test):
		push_error("FAIL: effective tree root should match intended root pres")
		call_deferred("quit", 1)
		return
	call_deferred("_run_isolated_draw_assertions")
