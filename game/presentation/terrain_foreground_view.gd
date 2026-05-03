# Procedural PLAINS-only forest foreground (Phase 4.6b–4.6h). Drawn above UnitsView; no input; no domain rules.
# Tree symbols (tree_symbols/*.png) are per-asset building blocks; forest decoration is the composed scatter on a hex.
# Phase 4.6e: **hex-owned** foreground at **projected hex center** (**anchor_pres** = foot/contact pivot convention; not sprite-bottom, not unit data).
# Phase 4.6f: **visibility calibration** — stronger **`forest_front_opacity`** + per-primitive alpha band for **procedural** path.
# Phase 4.6g: **optional** **large** front **patches**; **4.6h** **default**: **small** **tree** **symbol** **scatter**.
# Phase 4.6c **debug-only:** `_draw_unit_forest_occluder` when **enable_unit_occlusion_test** — **additive**, never replaces hex clumps.
# See docs/RENDERING.md
extends Node2D

## Salts **4000–4099** reserved for Phase **4.6e** hex-owned foreground (deterministic only).
const _SALT_MAIN_PLACE: int = 4000
const _SALT_MAIN_SIZE: int = 4001
const _SALT_MAIN_NCIRC: int = 4002
const _SALT_MAIN_CIRC0: int = 4010
const _SALT_MAIN_POLY: int = 4038
const _SALT_SEC_GATE: int = 4050
const _SALT_SEC_LAYOUT: int = 4051
const _SALT_SEC_NCIRC: int = 4052
const _SALT_SEC_CIRC0: int = 4060

## Phase **4.6g** — raster front clump (**4100–4199**; distinct uses within band).
const _SALT_FRONT_ASSET_TEX: int = 4110
const _SALT_FRONT_ASSET_DIM: int = 4111
const _SALT_FRONT_ASSET_JX: int = 4112

## Phase **4.6h** — **front** symbol scatter (**4300–4399**).
const _SALT_FRONT_SYM_BASE: int = 4320
## **4.6p grid jitter** seeds **`forest_grid_jitter_hash`** only; no separate salt band.
const _EOM_ENV_DEBUG_FOREST_GRID: String = "EOM_DEBUG_FOREST_GRID"
const _EOM_ENV_FOREST_GRID_PERFECT: String = "EOM_DEBUG_FOREST_GRID_PERFECT"

const FOREST_FRONT_CLUMP_01: Texture2D = preload("res://assets/prototype/terrain/forest/forest_front_clump_01.png")
const FOREST_FRONT_CLUMP_02: Texture2D = preload("res://assets/prototype/terrain/forest/forest_front_clump_02.png")

const HexMapScript = preload("res://domain/hex_map.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const MapPlaneProjectionScript = preload("res://presentation/map_plane_projection.gd")
const MapCameraScript = preload("res://presentation/map_camera.gd")
const PlainsForestScript = preload("res://presentation/plains_forest_decoration.gd")
const TextureAlphaMetricsClass = preload("res://presentation/texture_alpha_metrics.gd")

@export_range(0.0, 1.0) var forest_density_ratio: float = 0.25
@export_range(0.0, 1.0) var forest_front_opacity: float = 0.62
## Matches **UnitsView.unit_icon_height_ratio** for **`side`**; **main.gd** overwrites from **UnitsView** when wired (**debug occluder** only).
@export_range(0.05, 1.2) var foreground_unit_reference_height_ratio: float = 0.70
## Presentation-space hub: **anchor_pres.y − side ×** this (feet / lower-leg overlap test).
@export_range(0.0, 0.45) var unit_occluder_y_ratio: float = 0.18
@export_range(0.1, 1.0) var unit_occluder_width_ratio: float = 0.45
@export_range(0.05, 0.55) var unit_occluder_height_ratio: float = 0.28
## Multiplies alphas for the **debug** unit-aware mass only (tune if occluder dominates).
@export_range(0.0, 1.5) var unit_occluder_opacity_scale: float = 0.88
## **Debug / test only (4.6e):** extra unit-anchored overlay when **true**. Normal look = hex-owned `_draw_plains_forest_front_hex_owned` only.
@export var enable_unit_occlusion_test: bool = false
## One-shot: prints PLAINS / decorated counts and density (editor or F5 run); no per-frame spam.
@export var forest_debug_log_counts_once: bool = false
## Phase **4.6g:** **large** **front** **patch**; **off** when **symbol** scatter is primary.
@export var use_forest_asset_overlays: bool = false
@export_range(0.0, 1.0) var forest_front_asset_opacity: float = 0.95
## Phase **4.6h:** **`use_forest_symbol_scatter`** — **forest** **decoration** = composed **scatter** of **tree** **symbol** PNGs (**`tree_symbols/`**); **fallback** **procedural**/ **patch**.
@export var use_forest_symbol_scatter: bool = true
@export_range(0.0, 1.0) var forest_front_symbol_opacity: float = 0.84
## **Debug:** log unit draw delegation / cross-wiring once per **`TerrainForegroundView._draw`** when set or **`EOM_DEBUG_UNIT_DRAW=1`**.
@export var debug_unit_tree_draw_ownership: bool = false
## **Debug:** after all forest overlay primitives, draw **PNG bottom-edge** tick (**raw** quad). **`EOM_DEBUG_UNIT_PNG_BOTTOM=1`** also enables.
@export var debug_draw_unit_png_bottom_center: bool = false
## **Debug:** draw raw (**cyan**) + **effective** depth ticks for trees/units (**effective** matches **production** anchors when alpha metrics apply).
@export var debug_draw_effective_depth_points: bool = false
## **Debug:** zero jitter, full **10** slots; set or **`EOM_DEBUG_FOREST_GRID_PERFECT=1`**. Implies **no_jitter** only. **Root markers** require **`forest_grid_debug_draw_roots`**; **perfect does not** imply markers.
@export var forest_grid_debug_perfect: bool = false
## **Debug:** log resolved perfect/jitter state and per-slot **base / jitter / root_local** when set or **`EOM_DEBUG_FOREST_GRID=1`**. One banner per redraw; prefix **`[EOM_DEBUG_FOREST_GRID]`**. Also: clear stuck env — Windows CMD: `set EOM_DEBUG_FOREST_GRID_PERFECT=` then restart editor; PowerShell: `Remove-Item Env:EOM_DEBUG_FOREST_GRID_PERFECT`; bash: `unset EOM_DEBUG_FOREST_GRID_PERFECT`.
@export var forest_grid_debug_log: bool = false
## **Debug:** hide **MapView** back-forest overlays (same as perfect-only suppression) to inspect **TerrainForegroundView** grid alone (optional; **does not** change gameplay when unset).
@export var forest_grid_debug_suppress_map_back: bool = false
## **Debug:** draw cyan/orange root markers at **intended/effective** grid root **`root_pres`** (raw quad bottom is lower when **tree_scaled_bottom_pad_y > 0**).
@export var forest_grid_debug_draw_roots: bool = false
## **Debug:** draw the **same** production jitter disk (**layout/world** **R_max**) around each slot base (perfect: root on base, ring still shows **R_max**).
@export var forest_grid_debug_draw_jitter_circles: bool = false
## **Debug (isolated sample hex):** draw a **thin line** from slot **base** → **jittered root** (presentation px) on the overlay **after** roots/labels so direction correlation is visible.
@export var forest_grid_debug_draw_jitter_displacement_vectors: bool = false
## **Debug (isolated sample hex):** print **`[EOM_DEBUG_FOREST_JITTER_SLOT]`** per slot (**h_θ, h_r, u, θ, r, clamp**, …) when **`forest_grid_debug_trace_pipeline`** is **off**; also included whenever trace is **on**.
@export var forest_grid_debug_log_grid_jitter_slots: bool = false
## **Debug:** **only** the **10-slot** front **symbol** **grid** may draw forest trees on **`TerrainForegroundView`**; **MapView** back-forest suppressed; no procedural/asset fallbacks on TFV. **`forest_grid_debug_perfect`** → all defined slots + zero jitter; **off** → same slots + deterministic jitter. Units still draw. **`main`** wires **`map_view`** for **`map_back`** draw counts.
@export var forest_grid_debug_isolated: bool = false
## **Debug (isolated only):** draw the grid on the **first** decorated PLAINS hex in **`map.coords()`** order only (clearest single-hex validation).
@export var forest_grid_debug_isolated_one_hex: bool = true
## **Pipeline debug:** print **`[EOM_DEBUG_FOREST_PIPELINE] TFV runtime_identity`** at **every** `_draw` start (path, instance id, exports, canonical **slot_base** list). **Off** in production; **does not** require **`forest_grid_debug_log`**.
@export var forest_grid_debug_trace_pipeline: bool = false
## **Debug (isolated):** slot index labels on the overlay when **`forest_grid_debug_trace_pipeline`**, **`forest_grid_debug_log_grid_jitter_slots`**, or this is **on**. **`forest_grid_debug_isolated` alone** does **not** enable labels.
@export var forest_grid_debug_draw_slot_labels: bool = false
## **Debug (isolated only):** replace canonical lattice with an exaggerated zig-zag layout to prove the **grid slot path** is live (**default** lattice unchanged when **off**).
@export var forest_grid_debug_exaggerated_layout_probe: bool = false

## Read-only **Scenario** for **units_at** / **cities_at** (presentation-only); **null** → city-skip always false.
var scenario
var map
var layout
var camera
## Phase **4.6p:** when set, unit markers are drawn in **`TerrainForegroundView`** between
## **upper** and **lower** local grid passes (**behind / in front** by construction), via
## **`UnitsView.draw_unit_marker_at(self, …)`**. **`UnitsView._draw`** early-returns when wired.
var units_view
## Wired by **`main`** — read **`MapView.debug_plains_back_forest_draw_calls`** for isolated summaries.
var map_view
## **Uniform 4-row lattice:** **P = 2×R_jitter + padding** (**layout/world**). Row centers **y_k = (-1.5, -0.5, +0.5, +1.5) × P**. Circle-edge gap between adjacent rows = **padding** (not **R+M**).
## **Padding** from min displayed symbol height × **padding_px_at_512/512** (see **`forest_grid_row_padding_world`**).
const _GRID_ROW_PADDING_PX_AT_512: float = 5.0
## Min **(0.69 + 0×0.30)×0.5** of **`base/SIZE`** in **`side = base × (…) × 0.5`** — same tree-size formula floor, **pscale**-independent ratio.
const _GRID_TREE_DISPLAYED_SIDE_MIN_FRAC: float = 0.69 * 0.5
## **Two-slot** rows (**top/bottom**): **x = ±A × SIZE**.
const _GRID_TWO_SLOT_X_FRAC: float = 0.16
## **Three-slot** rows (**middle**): **x ∈ { −B, 0, +B } × SIZE**.
const _GRID_THREE_SLOT_X_FRAC: float = 0.28
## Phase **4.6p** — max jitter disk radius (**layout/world**), **fraction of SIZE** (uniform-in-disk:
## **r = R_max × sqrt(U)**). **Promoted** from **0.030 × ~3.05 ≈ 0.0915H** (old **debug-only** scale removed — this **is** the real radius). With **`_GRID_SLOT_SAFETY_MARGIN_FRAC`**, **eff_R = R+M** keeps full disk inside the hex for every base slot **S**.
const _GRID_JITTER_RADIUS_FRAC: float = 0.0915
## Extra **layout** margin **M** (fraction of **SIZE**) so **R+M** disks around each slot center stay strictly inside the hex (tests sample the full circle).
const _GRID_SLOT_SAFETY_MARGIN_FRAC: float = 0.028
## **10** roots (**2/3/3/2** row bands): **0–4** upper (**before** unit), **5–9** lower (**after** unit).
const _GRID_SLOT_COUNT: int = 10
const _GRID_UPPER_SLOT_COUNT: int = 5
## **Symbol-grid debug:** root markers use **fixed presentation px** (not **`side`** / **pscale**) so perfect vs normal isolated modes match size.
const _FG_GRID_ROOT_MARKER_CIRCLE_R_PX: float = 6.0
const _FG_GRID_ROOT_MARKER_CROSS_HALF_PX: float = 8.0
const _FG_GRID_ROOT_MARKER_LINE_W_PX: float = 2.0
const _FG_GRID_JITTER_DEBUG_POLY_SEGMENTS: int = 28
## **Final overlay flush** — jitter rings / base cross / jitter-root dot (thicker, higher-alpha vs inline legacy).
const _FG_OVERLAY_JITTER_RING_LINE_W: float = 2.75
const _FG_OVERLAY_JITTER_BASE_CROSS_HALF_PX: float = 4.0
const _FG_OVERLAY_JITTER_BASE_LINE_W: float = 2.0
const _FG_OVERLAY_JITTER_ROOT_DOT_R_PX: float = 5.0
const _FG_OVERLAY_JITTER_ROOT_DOT_LINE_W: float = 2.25
const _FG_OVERLAY_TREE_EFFECTIVE_TICK_HALF_PX: float = 5.0
const _FG_OVERLAY_UNIT_RAW_PNG_COLOR: Color = Color(0.35, 0.92, 1.0, 0.92)
const _FG_OVERLAY_TREE_EFFECTIVE_COLOR: Color = Color(1.0, 0.95, 0.25, 0.95)
const _FG_OVERLAY_UNIT_PNG_BOTTOM_H_HALF_PX: float = 8.0
const _FG_OVERLAY_UNIT_PNG_BOTTOM_TICK_HALF_PX: float = 2.0
const _FG_OVERLAY_UNIT_PNG_BOTTOM_LINE_W: float = 1.35
const _FG_OVERLAY_UNIT_PNG_BOTTOM_TICK_W: float = 1.0
## **Rect2** bottom-center must match **root_pres** within this (presentation units).
const _FG_GRID_ROOT_MARKER_GEOM_EPS_PX: float = 0.5
var _forest_counts_logged: bool = false
var _forest_tree_symbols: Array[Texture2D] = []  # Cached tree symbol textures (building blocks for forest decoration).
var _forest_symbol_scatter_unavailable_logged: bool = false

const _TREE_SYMBOL_COUNT: int = 20
## One **`_draw`** snapshot for grid/jitter/debug (symbol-grid path).
var _fg_sess_no_jitter: bool = false
var _fg_sess_perfect: bool = false
var _fg_sess_draw_roots: bool = false
var _fg_sess_frame_grid_textures: int = 0
var _fg_sess_frame_front_proc_calls: int = 0
var _fg_sess_frame_front_asset_calls: int = 0
var _fg_sess_roots_detail_log: bool = false
var _fg_sess_detail_hex_chosen: bool = false
var _fg_sess_detail_q: int = 0
var _fg_sess_detail_r: int = 0
var _fg_sess_detail_grid_acc: int = 0
var _fg_sess_detail_totals_printed: bool = false
var _dbg_perf_grid_tex_drawn: int = 0
var _dbg_perf_root_markers_drawn: int = 0
var _fg_warned_isolated_no_symbols: bool = false
## **Debug overlay (single flush):** jitter items, root markers, slot labels, unit **PNG bottom-center** ticks — **collected** during grid/unit passes, **`_fg_flush_debug_overlay_top`** after pass **3** (`flush_at=end_of_tfv_draw`).
var _fg_overlay_root_markers: Array = []
var _fg_overlay_jitter_items: Array = []
## Isolated grid: **`base_pres` → `root_pres`** segment (topmost forest jitter diagnostic).
var _fg_overlay_jitter_vectors: Array = []
var _fg_overlay_slot_labels: Array = []
var _fg_overlay_unit_raw_png_bottom: Array = []
var _fg_overlay_unit_effective_depth: Array = []
var _fg_overlay_tree_effective_depth: Array = []
var _fg_sess_logged_unit_png_bottom_sample: bool = false
var _fg_isolated_drawn_hex_keys: Dictionary = {}
var _fg_sess_isolated_candidate_hexes: int = 0
var _fg_sess_grid_symbols_drawn: int = 0
var _fg_sess_grid_upper_symbols_drawn: int = 0
var _fg_sess_grid_lower_symbols_drawn: int = 0
var _fg_sess_grid_root_markers_drawn: int = 0
var _fg_sess_unit_occluder_draws: int = 0
var _fg_root_markers_drawn_total: int = 0
var _fg_root_markers_drawn_upper: int = 0
var _fg_root_markers_drawn_lower: int = 0
var _fg_root_marker_draw_helper_calls: int = 0
var _fg_root_marker_radius_px_used: float = 0.0
var _fg_root_marker_geom_checks_passed: int = 0
var _fg_sess_jitter_debug_rings_drawn: int = 0
## **Headless tests:** last **`_draw`** totals when **`forest_grid_debug_isolated`** was **true** (**−1** = no isolated **draw** yet this run).
static var debug_last_isolated_grid_symbols_drawn: int = -1
static var debug_last_isolated_grid_root_markers_drawn: int = -1
## **Headless tests:** jitter-ring **draw** calls last isolated frame when **`forest_grid_debug_draw_jitter_circles`** (**−1** = flag off or no isolated **draw**).
static var debug_last_isolated_jitter_ring_draws: int = -1
## **Headless tests (`forest_grid_debug_isolated`):** last **`_fg_flush_debug_overlay_top`** enqueue sizes (**−1** before first isolated flush this run).
static var debug_last_overlay_flush_roots: int = -1
static var debug_last_overlay_flush_circles: int = -1
static var debug_last_overlay_flush_vectors: int = -1
static var debug_last_overlay_flush_labels: int = -1
static var debug_last_overlay_flush_tree_effective: int = -1
static var debug_last_overlay_flush_unit_raw: int = -1
static var debug_last_overlay_flush_unit_effective: int = -1
## **Pipeline debug (last `TerrainForegroundView._draw`):** per-path forest draw counts ( **`−1`** before first draw this run ).
static var debug_pipeline_tfv_path: String = ""
static var debug_pipeline_tfv_instance_id: int = -1
static var debug_pipeline_tfv_grid_symbols: int = -1
static var debug_pipeline_tfv_grid_upper_symbols: int = -1
static var debug_pipeline_tfv_grid_lower_symbols: int = -1
static var debug_pipeline_tfv_grid_roots: int = -1
static var debug_pipeline_tfv_jitter_circles: int = -1
static var debug_pipeline_tfv_front_asset: int = -1
static var debug_pipeline_tfv_front_proc: int = -1
static var debug_pipeline_tfv_unit_occluder: int = -1
## **Debug / tests:** counts after pass **2** / pass **3** prep (**before** overlay flush).
static var debug_last_overlay_unit_raw_png_queued: int = -1
static var debug_last_overlay_unit_effective_depth_queued: int = -1


func _eom_debug_unit_tree_draw() -> bool:
	return debug_unit_tree_draw_ownership or OS.get_environment("EOM_DEBUG_UNIT_DRAW") == "1"


func _eom_debug_unit_png_bottom() -> bool:
	return (
		debug_draw_unit_png_bottom_center
		or OS.get_environment("EOM_DEBUG_UNIT_PNG_BOTTOM") == "1"
	)


func _eom_forest_grid_perfect() -> bool:
	return forest_grid_debug_perfect or OS.get_environment(_EOM_ENV_FOREST_GRID_PERFECT) == "1"


func _eom_forest_grid_debug_log() -> bool:
	return forest_grid_debug_log or OS.get_environment(_EOM_ENV_DEBUG_FOREST_GRID) == "1"


func _fg_should_print_runtime_identity() -> bool:
	return (
		forest_grid_debug_isolated
		or forest_grid_debug_draw_jitter_circles
		or forest_grid_debug_draw_jitter_displacement_vectors
		or forest_grid_debug_log_grid_jitter_slots
		or forest_grid_debug_trace_pipeline
		or _eom_forest_grid_debug_log()
	)


func _fg_print_runtime_identity() -> void:
	var scr_path: String = ""
	var gs = get_script()
	if gs != null:
		var p = gs.resource_path
		if typeof(p) == TYPE_STRING:
			scr_path = p
	var H: float = HexLayoutScript.SIZE
	var gap_f: float = forest_grid_vertical_gap_jitter_edges_frac()
	var P_frac: float = forest_grid_row_pitch_frac()
	print(
		(
			"[EOM_DEBUG_FOREST_PIPELINE] TFV runtime_identity path=%s instance_id=%d script=%s | exports: isolated=%s one_hex=%s perfect=%s draw_roots=%s jitter_circles=%s jitter_disp_vec=%s jitter_slot_log=%s trace_pipeline=%s draw_slot_labels=%s exaggerated_probe=%s suppress_map_back=%s log_export=%s | scatter=%s asset_overlays=%s | lattice: P/H=%.5f R_jitter/H=%.3f padding/H=%.5f row_edge_gap/H=%.5f A/H=%.3f B/H=%.3f eff_R_safe/H=%.3f SIZE=%.1f"
		)
		% [
			str(get_path()),
			get_instance_id(),
			scr_path,
			forest_grid_debug_isolated,
			forest_grid_debug_isolated_one_hex,
			forest_grid_debug_perfect,
			forest_grid_debug_draw_roots,
			forest_grid_debug_draw_jitter_circles,
			forest_grid_debug_draw_jitter_displacement_vectors,
			forest_grid_debug_log_grid_jitter_slots,
			forest_grid_debug_trace_pipeline,
			forest_grid_debug_draw_slot_labels,
			forest_grid_debug_exaggerated_layout_probe,
			forest_grid_debug_suppress_map_back,
			forest_grid_debug_log,
			use_forest_symbol_scatter,
			use_forest_asset_overlays,
			P_frac,
			_GRID_JITTER_RADIUS_FRAC,
			forest_grid_row_padding_frac(),
			gap_f,
			_GRID_TWO_SLOT_X_FRAC,
			_GRID_THREE_SLOT_X_FRAC,
			forest_grid_eff_R_frac(),
			H,
		]
	)
	print(
		"[EOM_DEBUG_FOREST_PIPELINE] TFV forest_grid_slot_base_local canonical (×H then world):"
	)
	var sb: int = 0
	while sb < _GRID_SLOT_COUNT:
		var bl: Vector2 = forest_grid_slot_base_local(sb)
		print(
			"  slot %2d  frac_xy=(%.4f,%.4f)  local_xy=(%.4f,%.4f)"
			% [sb, bl.x / H, bl.y / H, bl.x, bl.y]
		)
		sb += 1
	if forest_grid_debug_isolated and forest_grid_debug_exaggerated_layout_probe:
		print(
			"[EOM_DEBUG_FOREST_PIPELINE] TFV grid pass uses EXAGGERATED_PROBE (not canonical bases above)"
		)


func _fg_resolved_slot_base_local(slot_index: int) -> Vector2:
	if forest_grid_debug_isolated and forest_grid_debug_exaggerated_layout_probe:
		return forest_grid_exaggerated_probe_slot_local(slot_index)
	return forest_grid_slot_base_local(slot_index)


func _fg_overlay_draw_slot_label(screen_pos: Vector2, slot_index: int, upper_band: bool) -> void:
	var f: Font = ThemeDB.fallback_font
	if f == null:
		return
	var fs: int = 12
	var t: String = str(slot_index)
	var col: Color = (
		Color(0.52, 0.95, 1.0, 0.98) if upper_band else Color(1.0, 0.58, 0.22, 0.98)
	)
	var outl: Color = Color(0.05, 0.05, 0.08, 0.94)
	draw_string_outline(
		f, screen_pos + Vector2(7.0, -10.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 12, outl
	)
	draw_string(
		f, screen_pos + Vector2(7.0, -10.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col
	)


func _fg_warn_isolated_non_grid_pipeline_leak() -> void:
	if not forest_grid_debug_isolated:
		return
	var p: String = str(get_path())
	if _fg_sess_frame_front_proc_calls != 0:
		push_warning(
			"[EOM_DEBUG_FOREST_PIPELINE] %s: tfv_front_procedural_draws=%d in isolated mode (expected 0)"
			% [p, _fg_sess_frame_front_proc_calls]
		)
	if _fg_sess_frame_front_asset_calls != 0:
		push_warning(
			"[EOM_DEBUG_FOREST_PIPELINE] %s: tfv_front_asset_draws=%d in isolated mode (expected 0)"
			% [p, _fg_sess_frame_front_asset_calls]
		)
	if _fg_sess_unit_occluder_draws != 0:
		push_warning(
			"[EOM_DEBUG_FOREST_PIPELINE] %s: tfv_unit_occluder_forest_draws=%d in isolated mode (expected 0)"
			% [p, _fg_sess_unit_occluder_draws]
		)
	var mv_ok: bool = map_view != null and is_instance_valid(map_view)
	if mv_ok:
		if map_view.debug_plains_back_forest_draw_calls != 0:
			push_warning(
				(
					"[EOM_DEBUG_FOREST_PIPELINE] %s: mapview back forest total=%d (sym=%d asset=%d proc=%d) — isolated should suppress MapView back"
				)
				% [
					p,
					map_view.debug_plains_back_forest_draw_calls,
					map_view.debug_plains_back_symbol_draws,
					map_view.debug_plains_back_asset_draws,
					map_view.debug_plains_back_procedural_draws,
				]
			)


static func forest_grid_env_perfect_active() -> bool:
	return OS.get_environment(_EOM_ENV_FOREST_GRID_PERFECT) == "1"


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_reload_forest_tree_symbols_if_needed()
	if (
		use_forest_symbol_scatter
		and not _forest_symbol_scatter_ready()
		and not _forest_symbol_scatter_unavailable_logged
	):
		_forest_symbol_scatter_unavailable_logged = true
		push_warning(
			"TerrainForegroundView: use_forest_symbol_scatter enabled but tree_symbol_01..20 not all loadable under tree_symbols/; using fallback forest draw."
		)
	queue_redraw()

func _should_skip_main_clump_for_city(coord) -> bool:
	if scenario == null:
		return false
	return scenario.cities_at(coord).size() > 0

func _mix255(h: int) -> float:
	return float(h & 0xFF) / 255.0


static func _tree_symbol_res_path(idx_1_based: int) -> String:
	return "res://assets/prototype/terrain/tree_symbols/tree_symbol_%02d.png" % idx_1_based


func _reload_forest_tree_symbols_if_needed() -> void:
	if _forest_tree_symbols.size() == _TREE_SYMBOL_COUNT:
		return
	_forest_tree_symbols.clear()
	var ii: int = 1
	while ii <= _TREE_SYMBOL_COUNT:
		var res = ResourceLoader.load(_tree_symbol_res_path(ii), "", ResourceLoader.CACHE_MODE_REUSE)
		if res is Texture2D:
			_forest_tree_symbols.append(res as Texture2D)
		else:
			_forest_tree_symbols.clear()
			return
		ii += 1


func _forest_symbol_scatter_ready() -> bool:
	return _forest_tree_symbols.size() == _TREE_SYMBOL_COUNT


func _fg_pick_sample_decorated_plains_hex(coord_list) -> void:
	_fg_sess_detail_hex_chosen = false
	if map == null:
		return
	var i: int = 0
	while i < coord_list.size():
		var c = coord_list[i]
		if int(map.terrain_at(c)) == HexMapScript.Terrain.PLAINS:
			if PlainsForestScript.is_plains_forest_decorated(c.q, c.r, forest_density_ratio):
				_fg_sess_detail_q = c.q
				_fg_sess_detail_r = c.r
				_fg_sess_detail_hex_chosen = true
				return
		i += 1


func _fg_clamp_root_local(loc_j: Vector2, loff: Vector2) -> Vector2:
	if layout == null:
		return loc_j
	var t: float = 1.0
	var s: int = 0
	while s < 24:
		var p: Vector2 = loff.lerp(loc_j, t)
		if layout.is_point_inside_hex_local(p):
			return p
		t *= 0.88
		s += 1
	return loff


func _fg_grid_mode_log_label() -> String:
	return "perfect_zero_jitter" if _fg_sess_no_jitter else "jittered_all_slots"


func _fg_print_sample_hex_grid_summary(q: int, r: int) -> void:
	var roots_n: int = _fg_sess_detail_grid_acc if _fg_sess_draw_roots else 0
	print(
		(
			"[EOM_DEBUG_FOREST_GRID] sample_hex(%d,%d) grid_mode=%s slots_drawn=%d roots_drawn=%d jitter_enabled=%s front_proc_fallback_calls=%d front_asset_fallback_calls=%d symbol_scatter_active=%s"
		)
		% [
			q,
			r,
			_fg_grid_mode_log_label(),
			_fg_sess_detail_grid_acc,
			roots_n,
			str(not _fg_sess_no_jitter),
			_fg_sess_frame_front_proc_calls,
			_fg_sess_frame_front_asset_calls,
			use_forest_symbol_scatter and _forest_symbol_scatter_ready(),
		]
	)


func _draw_unit_forest_occluder(anchor_pres: Vector2, side: float, q: int, r: int) -> void:
	# Phase 4.6c — **debug/test only** when **enable_unit_occlusion_test**. Not the 4.6e visual model.
	var op: float = forest_front_opacity * unit_occluder_opacity_scale
	var w: float = side * unit_occluder_width_ratio
	var h: float = side * unit_occluder_height_ratio
	var jx: float = float((PlainsForestScript.cell_mix(q, r, 2000) % 19) - 9) * 0.55
	var jy: float = float((PlainsForestScript.cell_mix(q, r, 2001) % 13) - 6) * 0.45
	var cx: float = anchor_pres.x + jx
	var cy: float = anchor_pres.y - side * unit_occluder_y_ratio + jy
	var base_r: float = maxf(w, h) * 0.26
	var n_circ: int = 4 + (PlainsForestScript.cell_mix(q, r, 2002) % 2)
	var i: int = 0
	while i < n_circ:
		var h2: int = PlainsForestScript.cell_mix(q, r, 2010 + i)
		var ox: float = (float(h2 % 41) - 20.0) / 20.0 * w * 0.42
		var oy: float = (float((h2 >> 6) % 31) - 15.0) / 15.0 * h * 0.38
		var pr: Vector2 = Vector2(cx + ox, cy + oy)
		var rad: float = base_r * (0.82 + float(i) * 0.07 + float((h2 >> 14) & 7) * 0.02)
		var ca: float = (0.14 + float((h2 >> 10) & 3) * 0.04) * op
		draw_circle(pr, rad, Color(0.22, 0.42, 0.22, clampf(ca, 0.0, 1.0)))
		i += 1
	var hp: int = PlainsForestScript.cell_mix(q, r, 2030)
	var mx: float = w * 0.48 + float((hp >> 4) & 7) * 1.1
	var my: float = h * 0.42 + float((hp >> 7) & 7) * 0.9
	var skew: float = deg_to_rad(float((hp >> 10) % 32) - 16.0)
	var ck: float = cos(skew)
	var sk: float = sin(skew)
	var tri: PackedVector2Array = PackedVector2Array([
		Vector2(cx, cy) + Vector2(-mx * ck + 0.2 * my * sk, -mx * sk - 0.2 * my * ck),
		Vector2(cx, cy) + Vector2(mx * ck * 0.88 + 0.28 * my * sk, mx * sk * 0.88 - 0.28 * my * ck),
		Vector2(cx, cy) + Vector2(0.15 * mx * ck - my * sk, 0.15 * mx * sk + my * ck),
	])
	var ta: float = (0.12 + float((hp >> 13) & 3) * 0.03) * op
	draw_colored_polygon(tri, Color(0.28, 0.40, 0.20, clampf(ta, 0.0, 1.0)))

func _draw_plains_forest_front_hex_owned(proj, world: Vector2, q: int, r: int, skip_main_for_city: bool) -> void:
	_fg_sess_frame_front_proc_calls += 1
	# Phase 4.6e: pscale-scaled clumps around **anchor_pres** (foot/contact = projected hex center). No unit data.
	# Phase 4.6f: per-primitive alpha multipliers slightly raised for evaluative readability (palette unchanged).
	var op: float = forest_front_opacity
	var anchor_pres: Vector2 = proj.to_presentation(world)
	var pscale: float = proj.perspective_scale_at(world)
	var base: float = HexLayoutScript.SIZE * pscale

	var hp: int = PlainsForestScript.cell_mix(q, r, _SALT_MAIN_PLACE)
	var jx: float = (float(hp % 201) / 100.0 - 1.0) * 0.06 * base
	var yo: float = 0.02 + _mix255(hp >> 9) * 0.08
	var jy: float = (float((hp >> 17) % 201) / 100.0 - 1.0) * 0.03 * base
	var cx: float = anchor_pres.x + jx
	var cy: float = anchor_pres.y - base * yo + jy

	var hs: int = PlainsForestScript.cell_mix(q, r, _SALT_MAIN_SIZE)
	var w_main: float = (0.55 + _mix255(hs) * 0.17) * base
	var h_main: float = (0.30 + _mix255(hs >> 8) * 0.12) * base

	if not skip_main_for_city:
		var n_main: int = 4 + (PlainsForestScript.cell_mix(q, r, _SALT_MAIN_NCIRC) % 3)
		var k: int = 0
		while k < n_main:
			var hc: int = PlainsForestScript.cell_mix(q, r, _SALT_MAIN_CIRC0 + k)
			var ox: float = (float(hc % 201) / 100.0 - 1.0) * w_main * 0.88
			var oy: float = (float((hc >> 9) % 201) / 100.0 - 1.0) * h_main * 0.88
			var rad: float = (0.18 + _mix255(hc >> 18) * 0.10) * base
			var ca: float = (0.20 + _mix255(hc >> 2) * 0.16) * op
			var cr: float = 0.22 + _mix255(hc >> 10) * 0.08
			var cg: float = 0.40 + _mix255(hc >> 16) * 0.06
			var cb: float = 0.20 + _mix255(hc >> 24) * 0.06
			draw_circle(
				Vector2(cx + ox, cy + oy),
				rad,
				Color(cr, cg, cb, clampf(ca, 0.0, 1.0))
			)
			k += 1
		var hpol: int = PlainsForestScript.cell_mix(q, r, _SALT_MAIN_POLY)
		var pw: float = w_main * 0.65
		var ph: float = h_main * 0.70
		var skew: float = deg_to_rad(float((hpol >> 5) % 28) - 14.0)
		var ck: float = cos(skew)
		var sk: float = sin(skew)
		var qa: float = (0.18 + _mix255(hpol >> 13) * 0.12) * op
		var pr: float = 0.24 + _mix255(hpol) * 0.06
		var pg: float = 0.42 + _mix255(hpol >> 8) * 0.04
		var pb: float = 0.22 + _mix255(hpol >> 16) * 0.04
		var ovl: PackedVector2Array = PackedVector2Array([
			Vector2(cx, cy) + Vector2(-pw * ck + 0.22 * ph * sk, -pw * sk - 0.22 * ph * ck),
			Vector2(cx, cy) + Vector2(pw * ck * 0.86 + 0.30 * ph * sk, pw * sk * 0.86 - 0.30 * ph * ck),
			Vector2(cx, cy) + Vector2(0.12 * pw * ck - ph * sk, 0.12 * pw * sk + ph * ck),
		])
		draw_colored_polygon(ovl, Color(pr, pg, pb, clampf(qa, 0.0, 1.0)))

	if (PlainsForestScript.cell_mix(q, r, _SALT_SEC_GATE) & 1) != 0:
		return
	var hsec: int = PlainsForestScript.cell_mix(q, r, _SALT_SEC_LAYOUT)
	var w_s: float = (0.30 + _mix255(hsec) * 0.12) * base
	var h_s: float = (0.20 + _mix255(hsec >> 8) * 0.08) * base
	var sign_s: float = -1.0 if ((hsec >> 16) & 1) == 0 else 1.0
	var off_s: float = (0.30 + _mix255(hsec >> 17) * 0.12) * base
	var cx2: float = anchor_pres.x + sign_s * off_s
	var cy2: float = anchor_pres.y + (0.04 + _mix255(hsec >> 1) * 0.06) * base
	var n_sec: int = 2 + (PlainsForestScript.cell_mix(q, r, _SALT_SEC_NCIRC) % 2)
	var si: int = 0
	while si < n_sec:
		var hsc: int = PlainsForestScript.cell_mix(q, r, _SALT_SEC_CIRC0 + si)
		var sx: float = (float(hsc % 181) / 90.0 - 1.0) * w_s * 0.82
		var sy: float = (float((hsc >> 8) % 181) / 90.0 - 1.0) * h_s * 0.82
		var srad: float = (0.16 + _mix255(hsc >> 16) * 0.12) * base
		var sa: float = (0.20 + _mix255(hsc >> 1) * 0.16) * op
		var sr: float = 0.22 + _mix255(hsc >> 10) * 0.08
		var sg: float = 0.40 + _mix255(hsc >> 18) * 0.06
		var sb: float = 0.20 + _mix255(hsc >> 24) * 0.06
		draw_circle(Vector2(cx2 + sx, cy2 + sy), srad, Color(sr, sg, sb, clampf(sa, 0.0, 1.0)))
		si += 1

func _draw_plains_forest_front_asset(proj, world: Vector2, q: int, r: int) -> void:
	_fg_sess_frame_front_asset_calls += 1
	# Phase 4.6g: **hex-owned** front **raster**; **anchor_pres** = foot/contact **reference** (**no** **unit** **data**).
	var anchor_pres: Vector2 = proj.to_presentation(world)
	var pscale: float = proj.perspective_scale_at(world)
	var base: float = HexLayoutScript.SIZE * pscale
	var hd: int = PlainsForestScript.cell_mix(q, r, _SALT_FRONT_ASSET_DIM)
	var wmult: float = 1.6 + _mix255(hd) * 0.40
	var hmult: float = 1.0 + _mix255(hd >> 8) * 0.35
	var wrect: float = base * wmult
	var hrect: float = base * hmult
	var hj: int = PlainsForestScript.cell_mix(q, r, _SALT_FRONT_ASSET_JX)
	var jx: float = (float(hj % 201) / 100.0 - 1.0) * 0.06 * base
	var tex: Texture2D = (
		FOREST_FRONT_CLUMP_01
		if (PlainsForestScript.cell_mix(q, r, _SALT_FRONT_ASSET_TEX) & 1) == 0
		else FOREST_FRONT_CLUMP_02
	)
	var rect: Rect2 = Rect2(anchor_pres.x - wrect * 0.5 + jx, anchor_pres.y - hrect * 0.60, wrect, hrect)
	draw_texture_rect(
		tex,
		rect,
		false,
		Color(1.0, 1.0, 1.0, clampf(forest_front_asset_opacity, 0.0, 1.0))
	)


## **Tests:** **|x|** in **two-slot** rows, as fraction of **SIZE**.
static func forest_grid_two_slot_x_frac() -> float:
	return _GRID_TWO_SLOT_X_FRAC


## **Tests:** **|x|** of wing slots in **three-slot** rows, as fraction of **SIZE**.
static func forest_grid_three_slot_x_frac() -> float:
	return _GRID_THREE_SLOT_X_FRAC


## **Tests:** **eff_R = R_fr + M_fr** (fraction of **SIZE**); safe disk radius for jitter+margin checks.
static func forest_grid_eff_R_frac() -> float:
	return _GRID_JITTER_RADIUS_FRAC + _GRID_SLOT_SAFETY_MARGIN_FRAC


## **Tests / docs:** number of forest front grid slots (**10**).
static func forest_grid_slot_count() -> int:
	return _GRID_SLOT_COUNT


## **Tests:** fixed presentation-space radius for **symbol-grid** root marker circle (**px**).
static func forest_grid_debug_root_marker_circle_radius_px() -> float:
	return _FG_GRID_ROOT_MARKER_CIRCLE_R_PX


## **Tests:** fixed half-length of **+** cross arms for symbol-grid root markers (**px**).
static func forest_grid_debug_root_marker_cross_half_px() -> float:
	return _FG_GRID_ROOT_MARKER_CROSS_HALF_PX


## **Tests:** **Raw PNG rect** bottom-center when the **visible/effective** root **`== intended_root_pres`** and the quad is **`side×side`** with **scaled_bottom_pad_y** (**0** = legacy: raw bottom **`== intended_root`**).
static func forest_grid_texture_rect_bottom_center(
	intended_root_pres: Vector2, side: float, scaled_bottom_pad_y: float = 0.0
) -> Vector2:
	var r: Rect2 = Rect2(
		intended_root_pres.x - side * 0.5,
		intended_root_pres.y + scaled_bottom_pad_y - side,
		side,
		side
	)
	return r.position + Vector2(r.size.x * 0.5, r.size.y)


## **Tests:** max jitter radius in **layout/world** (**R**).
static func forest_grid_jitter_max_radius_world() -> float:
	return _GRID_JITTER_RADIUS_FRAC * HexLayoutScript.SIZE


## **Tests:** debug jitter overlay ring = production **R** (**layout/world**).
static func forest_grid_debug_jitter_circle_radius_world() -> float:
	return forest_grid_jitter_max_radius_world()


## **Tests:** safety margin **M** in **layout/world** (added to **R** for disk(**S**, **R**+**M**) checks).
static func forest_grid_safety_margin_world() -> float:
	return _GRID_SLOT_SAFETY_MARGIN_FRAC * HexLayoutScript.SIZE


## **Tests / validation:** **R**+**M** — every sample on **circle(S, R+M)** must lie inside the hex.
static func forest_grid_safe_disk_radius_world() -> float:
	return forest_grid_jitter_max_radius_world() + forest_grid_safety_margin_world()


## **Tests / docs:** row **padding** in **layout/world** = **SIZE × min_displayed_side_frac × (padding_px_at_512/512)** (**min** matches **(0.69)×0.5** of **`side/base`** floor from the symbol **height** formula).
static func forest_grid_row_padding_world() -> float:
	return (
		HexLayoutScript.SIZE
		* _GRID_TREE_DISPLAYED_SIDE_MIN_FRAC
		* (_GRID_ROW_PADDING_PX_AT_512 / 512.0)
	)


## **Tests:** padding / SIZE.
static func forest_grid_row_padding_frac() -> float:
	return forest_grid_row_padding_world() / HexLayoutScript.SIZE


## **Tests / docs:** uniform row spacing **P** in **layout/world** = **2×R_jitter + padding** (production **R**, not **R+M**).
static func forest_grid_row_pitch_world() -> float:
	return 2.0 * forest_grid_jitter_max_radius_world() + forest_grid_row_padding_world()


## **Tests:** **P/SIZE**.
static func forest_grid_row_pitch_frac() -> float:
	return forest_grid_row_pitch_world() / HexLayoutScript.SIZE


## **Tests:** **P − 2×R_jitter** = **padding** ⇒ edge gap between adjacent **production** jitter circles / SIZE.
static func forest_grid_vertical_gap_jitter_edges_frac() -> float:
	return forest_grid_row_padding_frac()


## **Tests / docs:** **local** base slot offset from **hex center** (**layout/world** space) before jitter.
## **Uniform 2/3/3/2 lattice:** **`y_k = (-1.5, -0.5, +0.5, +1.5) × P`** with **`P = forest_grid_row_pitch_world()`**; two-slot rows **`x = ±A×SIZE`**, three-slot **`x = −B, 0, +B×SIZE`**.
static func forest_grid_slot_base_local(slot_index: int) -> Vector2:
	var H: float = HexLayoutScript.SIZE
	var p_y: float = forest_grid_row_pitch_world()
	var a_x: float = _GRID_TWO_SLOT_X_FRAC * H
	var b_x: float = _GRID_THREE_SLOT_X_FRAC * H
	var y0: float = -1.5 * p_y
	var y1: float = -0.5 * p_y
	var y2: float = 0.5 * p_y
	var y3: float = 1.5 * p_y
	match slot_index:
		0:
			return Vector2(-a_x, y0)
		1:
			return Vector2(a_x, y0)
		2:
			return Vector2(-b_x, y1)
		3:
			return Vector2(0.0, y1)
		4:
			return Vector2(b_x, y1)
		5:
			return Vector2(-b_x, y2)
		6:
			return Vector2(0.0, y2)
		7:
			return Vector2(b_x, y2)
		8:
			return Vector2(-a_x, y3)
		9:
			return Vector2(a_x, y3)
		_:
			return Vector2.ZERO


## **Tests / pipeline probe:** exaggerated **layout/world** slot offsets (**zig-zag**); used only when **`forest_grid_debug_exaggerated_layout_probe`** **and** isolated.
static func forest_grid_exaggerated_probe_slot_local(slot_index: int) -> Vector2:
	var H: float = HexLayoutScript.SIZE
	match slot_index:
		0:
			return Vector2(-0.50 * H, -0.50 * H)
		1:
			return Vector2(0.50 * H, -0.38 * H)
		2:
			return Vector2(-0.45 * H, -0.15 * H)
		3:
			return Vector2(0.00 * H, -0.05 * H)
		4:
			return Vector2(0.45 * H, -0.12 * H)
		5:
			return Vector2(-0.48 * H, 0.12 * H)
		6:
			return Vector2(0.00 * H, 0.05 * H)
		7:
			return Vector2(0.48 * H, 0.15 * H)
		8:
			return Vector2(-0.42 * H, 0.42 * H)
		9:
			return Vector2(0.46 * H, 0.48 * H)
		_:
			return Vector2.ZERO


## **Tests:** max **`draw_texture_rect`** tree symbols for one decorated PLAINS hex in symbol-grid mode (**city** → no lower pass).
static func forest_grid_symbol_rect_cap_per_decorated_hex(city_skips_lower_band: bool) -> int:
	return _GRID_UPPER_SLOT_COUNT if city_skips_lower_band else _GRID_SLOT_COUNT


## **32-bit avalanche** finalize; result **& 0x7FFFFFFF** (same range as **`cell_mix`**).
static func _forest_grid_jitter_mix32(x0: int) -> int:
	var x: int = x0 & 0xFFFFFFFF
	x = (x ^ (x >> 16)) & 0xFFFFFFFF
	x = (x * 0x7FEB352D) & 0xFFFFFFFF
	x = (x ^ (x >> 15)) & 0xFFFFFFFF
	x = (x * 0x846CA68B) & 0xFFFFFFFF
	x = (x ^ (x >> 16)) & 0xFFFFFFFF
	return x & 0x7FFFFFFF


## **Decorrelated** jitter seed: combines **q, r, slot_index, stream_id** (0 = θ, 1 = radial); **two** avalanche rounds so slot columns do not share a near-fixed **θ**.
static func forest_grid_jitter_hash(q: int, r: int, slot_index: int, stream_id: int) -> int:
	var x: int = 0x9E3779B9
	x = (x ^ ((q * 0x85EBCA6B) & 0xFFFFFFFF)) & 0xFFFFFFFF
	x = (x ^ ((r * 0xC2B2AE35) & 0xFFFFFFFF)) & 0xFFFFFFFF
	x = (x ^ ((slot_index * 0x27D4EB2D) & 0xFFFFFFFF)) & 0xFFFFFFFF
	x = (x ^ ((stream_id * 0x165667B1) & 0xFFFFFFFF)) & 0xFFFFFFFF
	x = _forest_grid_jitter_mix32(x)
	x = (
		x
		^ ((slot_index * 0xCAFEBABE) & 0xFFFFFFFF)
		^ ((stream_id * 0x0FB9A763) & 0xFFFFFFFF)
		^ (((slot_index * stream_id) * 0x2E5A9D43) & 0xFFFFFFFF)
		^ ((q * 0x36155C29) & 0xFFFFFFFF)
		^ ((r * 0x9E6DD371) & 0xFFFFFFFF)
	) & 0xFFFFFFFF
	return _forest_grid_jitter_mix32(x)


## **Tests / production:** **u** from **`(h >> 8) & 0xFFFFFF` → [0,1)**.
static func forest_grid_jitter_u_from_hash(h: int) -> float:
	return float((h >> 8) & 0xFFFFFF) / 16777216.0


## **`Vector2i.x` = h_θ, `.y` = h_r** — **stream 0 / 1** via **`forest_grid_jitter_hash`**.
static func forest_grid_jitter_mix_hashes(q: int, r: int, slot_index: int) -> Vector2i:
	var h_theta: int = forest_grid_jitter_hash(q, r, slot_index, 0)
	var h_rad: int = forest_grid_jitter_hash(q, r, slot_index, 1)
	return Vector2i(h_theta, h_rad)


## **Tests:** jitter vector in **layout/world** from **independent** **u₁,u₂** in **[0,1)**; **r = R×√u₂** (**uniform disk area**).
static func forest_grid_jitter_local_for_tests(
	h_theta: int, h_rad: int, radius_world: float
) -> Vector2:
	if radius_world <= 0.0:
		return Vector2.ZERO
	var u1: float = forest_grid_jitter_u_from_hash(h_theta)
	var u2: float = forest_grid_jitter_u_from_hash(h_rad)
	var theta: float = TAU * u1
	var rad: float = radius_world * sqrt(u2)
	return Vector2(cos(theta) * rad, sin(theta) * rad)


## **-1** = upper half-plane (**before** unit pass), **+1** = lower (**after** unit). **0** = on horizontal axis (**no** slot center uses this).
static func forest_grid_local_depth_category(local_offset: Vector2) -> int:
	var ly: float = local_offset.y
	if ly < 0.0:
		return -1
	if ly > 0.0:
		return 1
	return 0


## **Tests / production:** deterministic jitter in **layout/world**; **`no_jitter`** forces **0** (perfect grid debug).
static func forest_grid_jitter_local_deterministic(
	q: int, r: int, slot_index: int, no_jitter: bool
) -> Vector2:
	if no_jitter:
		return Vector2.ZERO
	var r_max: float = forest_grid_jitter_max_radius_world()
	var mixes: Vector2i = forest_grid_jitter_mix_hashes(q, r, slot_index)
	return forest_grid_jitter_local_for_tests(mixes.x, mixes.y, r_max)


func _forest_grid_jitter_local(q: int, r: int, slot_index: int) -> Vector2:
	return forest_grid_jitter_local_deterministic(q, r, slot_index, _fg_sess_no_jitter)


func _fg_isolated_draw_this_hex(q: int, r: int) -> bool:
	if not forest_grid_debug_isolated or not forest_grid_debug_isolated_one_hex:
		return true
	return _fg_sess_detail_hex_chosen and q == _fg_sess_detail_q and r == _fg_sess_detail_r


## **Single draw path** for **symbol-grid** root debug markers (**presentation px**; same perfect/normal/isolated).
## **`root_pres`** = **intended/effective** tree root; **`raw_png_rect_bottom_center`** = actual **`draw_texture_rect`** quad bottom-center.
func _draw_forest_grid_root_marker(
	root_pres: Vector2,
	upper_band: bool,
	raw_png_rect_bottom_center: Vector2,
	side_for_geom: float,
	tree_scaled_bottom_pad_y: float = 0.0,
) -> void:
	var expected_raw: Vector2 = Vector2(root_pres.x, root_pres.y + tree_scaled_bottom_pad_y)
	if raw_png_rect_bottom_center.distance_to(expected_raw) > _FG_GRID_ROOT_MARKER_GEOM_EPS_PX:
		push_warning(
			(
				"TerrainForegroundView _draw_forest_grid_root_marker: raw PNG rect bottom-center %s != intended_root+pad %s (eps=%.2f side=%.4f pad_y=%.4f)"
				% [
					raw_png_rect_bottom_center,
					expected_raw,
					_FG_GRID_ROOT_MARKER_GEOM_EPS_PX,
					side_for_geom,
					tree_scaled_bottom_pad_y,
				]
			)
		)
	else:
		_fg_root_marker_geom_checks_passed += 1
	var mk: Color = (
		Color(0.2, 0.85, 1.0, 0.92) if upper_band else Color(1.0, 0.35, 0.15, 0.92)
	)
	var rr: float = _FG_GRID_ROOT_MARKER_CIRCLE_R_PX
	var ch: float = _FG_GRID_ROOT_MARKER_CROSS_HALF_PX
	var lw: float = _FG_GRID_ROOT_MARKER_LINE_W_PX
	if _fg_root_marker_draw_helper_calls == 0:
		_fg_root_marker_radius_px_used = rr
	elif not is_equal_approx(_fg_root_marker_radius_px_used, rr):
		push_warning(
			"TerrainForegroundView: _draw_forest_grid_root_marker circle radius changed mid-frame"
		)
	_fg_root_marker_draw_helper_calls += 1
	_fg_root_markers_drawn_total += 1
	if upper_band:
		_fg_root_markers_drawn_upper += 1
	else:
		_fg_root_markers_drawn_lower += 1
	draw_arc(root_pres, rr, 0.0, TAU - 0.001, 32, mk, lw, true)
	draw_line(
		root_pres + Vector2(-ch, 0.0), root_pres + Vector2(ch, 0.0), mk, lw
	)
	draw_line(
		root_pres + Vector2(0.0, -ch), root_pres + Vector2(0.0, ch), mk, lw
	)
	_fg_sess_grid_root_markers_drawn += 1
	if _fg_sess_perfect:
		_dbg_perf_root_markers_drawn += 1


## **Topmost overlay flush only:** jitter disk outline + base cross + jitter-root dot (**not** called during grid tile draws).
func _fg_overlay_draw_jitter_item(d: Dictionary) -> void:
	var proj = d["proj"]
	var world: Vector2 = d["world"] as Vector2
	var loff: Vector2 = d["loff"] as Vector2
	var root_pres: Vector2 = d["root_pres"] as Vector2
	var upper_band: bool = d["upper"] as bool
	var verify_ring_center: bool = d["verify"] as bool
	var r_w: float = forest_grid_jitter_max_radius_world()
	var base_pres: Vector2 = proj.to_presentation(world + loff)
	var ring_col: Color = (
		Color(0.12, 0.78, 1.0, 0.90) if upper_band else Color(1.0, 0.38, 0.12, 0.90)
	)
	var jroot_col: Color = (
		Color(0.20, 0.88, 1.0, 0.98) if upper_band else Color(1.0, 0.48, 0.20, 0.98)
	)
	var base_col: Color = Color(0.90, 0.92, 0.98, 0.95)
	var n: int = _FG_GRID_JITTER_DEBUG_POLY_SEGMENTS
	var pts: PackedVector2Array = PackedVector2Array()
	pts.resize(n + 1)
	var kk: int = 0
	while kk < n:
		var ang: float = TAU * float(kk) / float(n)
		var loc_ring: Vector2 = loff + Vector2(cos(ang), sin(ang)) * r_w
		pts[kk] = proj.to_presentation(world + loc_ring)
		kk += 1
	pts[n] = pts[0]
	var ring_w: float = _FG_OVERLAY_JITTER_RING_LINE_W
	draw_polyline(pts, ring_col, ring_w, true)
	var bh: float = _FG_OVERLAY_JITTER_BASE_CROSS_HALF_PX
	var blw: float = _FG_OVERLAY_JITTER_BASE_LINE_W
	draw_line(
		base_pres + Vector2(-bh, 0.0), base_pres + Vector2(bh, 0.0), base_col, blw, true
	)
	draw_line(
		base_pres + Vector2(0.0, -bh), base_pres + Vector2(0.0, bh), base_col, blw, true
	)
	var jdot: float = _FG_OVERLAY_JITTER_ROOT_DOT_R_PX
	draw_arc(
		root_pres,
		jdot,
		0.0,
		TAU - 0.001,
		18,
		jroot_col,
		_FG_OVERLAY_JITTER_ROOT_DOT_LINE_W,
		true
	)
	_fg_sess_jitter_debug_rings_drawn += 1
	if verify_ring_center:
		var csum: Vector2 = Vector2.ZERO
		var kk2: int = 0
		while kk2 < n:
			csum += pts[kk2]
			kk2 += 1
		csum /= float(n)
		var eps_ring: float = 4.0
		if csum.distance_to(base_pres) > eps_ring:
			push_warning(
				(
					"[EOM_DEBUG_FOREST_PIPELINE] jitter ring projected centroid %s != base_pres %s (eps=%.1f); path=%s slot_debug=_fg_overlay_draw_jitter_item"
				)
				% [csum, base_pres, eps_ring, str(get_path())]
			)


func _fg_overlay_draw_jitter_vector_item(d: Dictionary) -> void:
	var a: Vector2 = d["base_pres"] as Vector2
	var b: Vector2 = d["root_pres"] as Vector2
	var upper_band: bool = d["upper"] as bool
	if a.distance_squared_to(b) < 0.06:
		return
	var col: Color = (
		Color(0.18, 0.92, 1.0, 0.9) if upper_band else Color(1.0, 0.4, 0.15, 0.9)
	)
	draw_line(a, b, col, 1.35, true)


func _fg_overlay_draw_thin_horizontal_tick(
	pos: Vector2, col: Color, half_w: float, tick_half_h: float, line_w: float, tick_w: float
) -> void:
	draw_line(pos + Vector2(-half_w, 0.0), pos + Vector2(half_w, 0.0), col, line_w, true)
	draw_line(
		pos + Vector2(0.0, -tick_half_h),
		pos + Vector2(0.0, tick_half_h),
		col,
		tick_w,
		true
	)


func _fg_overlay_draw_unit_raw_png_bottom_tick(raw_png_bottom_center_pres: Vector2) -> void:
	var hh: float = _FG_OVERLAY_UNIT_PNG_BOTTOM_H_HALF_PX
	var tv: float = _FG_OVERLAY_UNIT_PNG_BOTTOM_TICK_HALF_PX
	_fg_overlay_draw_thin_horizontal_tick(
		raw_png_bottom_center_pres,
		_FG_OVERLAY_UNIT_RAW_PNG_COLOR,
		hh,
		tv,
		_FG_OVERLAY_UNIT_PNG_BOTTOM_LINE_W,
		_FG_OVERLAY_UNIT_PNG_BOTTOM_TICK_W
	)


func _fg_overlay_draw_unit_effective_depth_tick(effective_pres: Vector2) -> void:
	var mk: Color = Color(1.0, 0.0, 1.0, 0.96)
	var hh: float = 9.0
	var tv: float = 1.25
	draw_line(
		effective_pres + Vector2(-hh, 0.0),
		effective_pres + Vector2(hh, 0.0),
		mk,
		1.2,
		true
	)
	draw_line(
		effective_pres + Vector2(0.0, -tv),
		effective_pres + Vector2(0.0, tv),
		mk,
		0.85,
		true
	)


func _fg_overlay_draw_tree_effective_depth_tick(p: Vector2) -> void:
	var col: Color = _FG_OVERLAY_TREE_EFFECTIVE_COLOR
	var hh: float = _FG_OVERLAY_TREE_EFFECTIVE_TICK_HALF_PX
	var tv: float = 1.5
	_fg_overlay_draw_thin_horizontal_tick(p, col, hh, tv, 1.25, 0.9)


func _fg_compact_overlay_debug_flags() -> String:
	return (
		"draw_roots=%s circles=%s jit_vec=%s slot_lbl=%s(trace=%s jitter_log=%s draw_lbl=%s) tree_eff=%s unit_png=%s unit_eff=%s"
		% [
			str(forest_grid_debug_draw_roots),
			str(forest_grid_debug_draw_jitter_circles),
			str(forest_grid_debug_draw_jitter_displacement_vectors),
			str(
				forest_grid_debug_trace_pipeline
				or forest_grid_debug_log_grid_jitter_slots
				or forest_grid_debug_draw_slot_labels
			),
			str(forest_grid_debug_trace_pipeline),
			str(forest_grid_debug_log_grid_jitter_slots),
			str(forest_grid_debug_draw_slot_labels),
			str(debug_draw_effective_depth_points),
			str(_eom_debug_unit_png_bottom()),
			str(debug_draw_effective_depth_points),
		]
	)


func _fg_flush_debug_overlay_top() -> void:
	var n_j: int = _fg_overlay_jitter_items.size()
	var n_r: int = _fg_overlay_root_markers.size()
	var n_l: int = _fg_overlay_slot_labels.size()
	var n_jv: int = _fg_overlay_jitter_vectors.size()
	var n_te: int = _fg_overlay_tree_effective_depth.size()
	var n_ur: int = _fg_overlay_unit_raw_png_bottom.size()
	var n_ue: int = _fg_overlay_unit_effective_depth.size()
	var empty: bool = (
		n_j == 0
		and n_r == 0
		and n_l == 0
		and n_jv == 0
		and n_te == 0
		and n_ur == 0
		and n_ue == 0
	)

	if not empty:
		for jit in _fg_overlay_jitter_items:
			_fg_overlay_draw_jitter_item(jit as Dictionary)
		for rm in _fg_overlay_root_markers:
			var item: Dictionary = rm as Dictionary
			_draw_forest_grid_root_marker(
				item["pres"] as Vector2,
				item["upper"] as bool,
				item["rect_bc"] as Vector2,
				float(item["side"]),
				float(item.get("tree_scaled_bottom_pad", 0.0))
			)
		for lb in _fg_overlay_slot_labels:
			var ld: Dictionary = lb as Dictionary
			_fg_overlay_draw_slot_label(
				ld["pres"] as Vector2, int(ld["slot"]), ld["upper"] as bool
			)
		for jvec in _fg_overlay_jitter_vectors:
			_fg_overlay_draw_jitter_vector_item(jvec as Dictionary)
		for te in _fg_overlay_tree_effective_depth:
			_fg_overlay_draw_tree_effective_depth_tick(te as Vector2)
		for ur in _fg_overlay_unit_raw_png_bottom:
			_fg_overlay_draw_unit_raw_png_bottom_tick(ur as Vector2)
		for ue in _fg_overlay_unit_effective_depth:
			_fg_overlay_draw_unit_effective_depth_tick(ue as Vector2)

	if forest_grid_debug_isolated:
		debug_last_overlay_flush_roots = n_r
		debug_last_overlay_flush_circles = n_j
		debug_last_overlay_flush_vectors = n_jv
		debug_last_overlay_flush_labels = n_l
		debug_last_overlay_flush_tree_effective = n_te
		debug_last_overlay_flush_unit_raw = n_ur
		debug_last_overlay_flush_unit_effective = n_ue
		print(
			(
				"[EOM_DEBUG_FOREST_OVERLAY] flush roots=%d circles=%d vectors=%d labels=%d tree_effective=%d unit_raw=%d unit_effective=%d isolated=%s flags=%s"
			)
			% [
				n_r,
				n_j,
				n_jv,
				n_l,
				n_te,
				n_ur,
				n_ue,
				str(forest_grid_debug_isolated),
				_fg_compact_overlay_debug_flags(),
			]
		)
	elif not empty:
		print(
			(
				"[EOM_DEBUG_FOREST_OVERLAY] flush forest_circles=%d forest_roots=%d forest_labels=%d forest_jitter_vec=%d tree_effective=%d unit_raw_png=%d unit_effective_depth=%d flush_at=end_of_tfv_draw"
			)
			% [n_j, n_r, n_l, n_jv, n_te, n_ur, n_ue]
		)


func _draw_plains_forest_front_symbol_grid_pass(
	proj, world: Vector2, q: int, r: int, upper_band: bool, log_hex_detail: bool
) -> int:
	# **4.6p:** **intended tree root** (**visible ground**) **`= proj.to_presentation( hex_center + base_local + jitter_local )`** (**`root_pres`**). **`draw_texture_rect`** quad is offset **down** by **`scaled_bottom_padding_y`** so the **opaque** bottom meets **`root_pres`**.
	# **`upper_band`:** slots **0–4**. Else **5–9**. Symbol-grid path: **only** these calls (no parallel scatter).
	if layout == null:
		return 0
	var pscale: float = proj.perspective_scale_at(world)
	var base: float = HexLayoutScript.SIZE * pscale
	var op: float = clampf(forest_front_symbol_opacity, 0.0, 1.0)
	var col: Color = Color(0.92, 0.86, 0.79, op)
	var si: int = 0 if upper_band else _GRID_UPPER_SLOT_COUNT
	var end_i: int = _GRID_UPPER_SLOT_COUNT if upper_band else _GRID_SLOT_COUNT
	var drawn: int = 0
	var grid_mode_s: String = _fg_grid_mode_log_label()
	var jitter_on: bool = not _fg_sess_no_jitter
	while si < end_i:
		var loff: Vector2 = _fg_resolved_slot_base_local(si)
		var jit_raw: Vector2 = _forest_grid_jitter_local(q, r, si)
		var loc_j_unc: Vector2 = loff + jit_raw
		var loc_j: Vector2 = loc_j_unc
		var jitter_clamped: bool = false
		if forest_grid_debug_isolated and not _fg_sess_perfect:
			loc_j = _fg_clamp_root_local(loc_j_unc, loff)
			jitter_clamped = not loc_j.is_equal_approx(loc_j_unc)
		var jit: Vector2 = loc_j - loff
		var root_world: Vector2 = world + loc_j
		var root_pres: Vector2 = proj.to_presentation(root_world)
		var pipeline_trace_slot: bool = (
			forest_grid_debug_isolated
			and forest_grid_debug_isolated_one_hex
			and _fg_sess_detail_hex_chosen
			and q == _fg_sess_detail_q
			and r == _fg_sess_detail_r
		)
		var log_jitter_slot: bool = (
			pipeline_trace_slot
			and (
				forest_grid_debug_trace_pipeline
				or forest_grid_debug_log_grid_jitter_slots
			)
		)
		if log_jitter_slot:
			var mixes_log: Vector2i = forest_grid_jitter_mix_hashes(q, r, si)
			var h_t_log: int = mixes_log.x
			var h_r_log: int = mixes_log.y
			var u_t_log: float = forest_grid_jitter_u_from_hash(h_t_log)
			var u_r_log: float = forest_grid_jitter_u_from_hash(h_r_log)
			var theta_log: float = TAU * u_t_log
			var r_j_log: float = forest_grid_jitter_max_radius_world()
			var rad_len_log: float = r_j_log * sqrt(u_r_log)
			var jr_for_len: Vector2 = jit_raw if jitter_on else Vector2.ZERO
			print(
				(
					"[EOM_DEBUG_FOREST_JITTER_SLOT] hex(%d,%d) slot=%2d upper=%s base_local=%s h_theta=%d h_radius=%d u_theta=%.6f u_radius=%.6f theta=%.6f rad_world=%.6f rad_div_R=%.6f jitter_raw_local=%s len_raw=%.6f len_raw_div_R=%.5f root_unc_local=%s root_clamped_local=%s jitter_post_clamp_local=%s len_post=%.6f len_post_div_R=%.5f clamped=%s jitter_on=%s"
				)
				% [
					q,
					r,
					si,
					upper_band,
					loff,
					h_t_log,
					h_r_log,
					u_t_log,
					u_r_log,
					theta_log,
					rad_len_log,
					rad_len_log / r_j_log if r_j_log > 0.0 else 0.0,
					jr_for_len,
					jr_for_len.length(),
					jr_for_len.length() / r_j_log if r_j_log > 0.0 else 0.0,
					loc_j_unc,
					loc_j,
					jit,
					jit.length(),
					jit.length() / r_j_log if r_j_log > 0.0 else 0.0,
					str(jitter_clamped),
					str(jitter_on),
				]
			)
		var h_mix_sym: int = PlainsForestScript.cell_mix(q, r, _SALT_FRONT_SYM_BASE + si)
		var ti: int = (si % _TREE_SYMBOL_COUNT) if _fg_sess_perfect else (h_mix_sym % _TREE_SYMBOL_COUNT)
		var tex: Texture2D = _forest_tree_symbols[ti]
		var side: float = base * (0.69 + _mix255(h_mix_sym >> 8) * 0.30) * 0.5
		var sym_path: String = _tree_symbol_res_path(ti + 1)
		var mtree: Dictionary = TextureAlphaMetricsClass.metrics_for_res_path(sym_path)
		var tree_pad: float = TextureAlphaMetricsClass.scaled_bottom_padding_y(mtree, side)
		var tree_sym_rect: Rect2 = Rect2(
			root_pres.x - side * 0.5, root_pres.y + tree_pad - side, side, side
		)
		var rect_bottom: Vector2 = forest_grid_texture_rect_bottom_center(
			root_pres, side, tree_pad
		)
		if pipeline_trace_slot or log_hex_detail:
			var r_j: float = forest_grid_jitter_max_radius_world()
			if pipeline_trace_slot:
				print(
					(
						"[EOM_DEBUG_FOREST_PIPELINE] grid_draw tfv=%s tfv_id=%d _draw_plains_forest_front_symbol_grid_pass hex(%d,%d) slot=%2d upper_pass=%s tex_idx=%d grid_mode=%s base_local=%s base_frac/H=(%.4f,%.4f) jitter_local=%s jitter_len=%.5f root_local=%s root_pres=%s rect_bottom_center=%s jitter_on=%s perfect=%s R_jitter_world=%.5f clamped=%s"
					)
					% [
						str(get_path()),
						get_instance_id(),
						q,
						r,
						si,
						upper_band,
						ti,
						grid_mode_s,
						loff,
						loff.x / HexLayoutScript.SIZE,
						loff.y / HexLayoutScript.SIZE,
						jit,
						jit.length(),
						loc_j,
						root_pres,
						rect_bottom,
						jitter_on,
						_fg_sess_perfect,
						r_j,
						str(jitter_clamped),
					]
				)
			elif log_hex_detail:
				print(
					(
						"[EOM_DEBUG_FOREST_GRID] hex(%d,%d) slot=%2d upper=%s grid_mode=%s base_local=%s jitter_local=%s jitter_len=%.5f root_local=%s root_pres=%s rect_bottom_center=%s jitter_enabled=%s perfect=%s isolated=%s R_jitter_world=%.4f clamped=%s"
					)
					% [
						q,
						r,
						si,
						upper_band,
						grid_mode_s,
						loff,
						jit,
						jit.length(),
						loc_j,
						root_pres,
						rect_bottom,
						str(jitter_on),
						_fg_sess_perfect,
						forest_grid_debug_isolated,
						r_j,
						str(jitter_clamped),
					]
				)
		draw_texture_rect(
			tex,
			tree_sym_rect,
			false,
			col
		)
		if forest_grid_debug_draw_jitter_circles:
			_fg_overlay_jitter_items.append(
				{
					"proj": proj,
					"world": world,
					"loff": loff,
					"root_pres": root_pres,
					"upper": upper_band,
					"verify": pipeline_trace_slot,
				}
			)
		if (
			forest_grid_debug_draw_jitter_displacement_vectors
			and pipeline_trace_slot
			and jitter_on
		):
			_fg_overlay_jitter_vectors.append(
				{
					"base_pres": proj.to_presentation(world + loff),
					"root_pres": root_pres,
					"upper": upper_band,
				}
			)
		_fg_sess_grid_symbols_drawn += 1
		if upper_band:
			_fg_sess_grid_upper_symbols_drawn += 1
		else:
			_fg_sess_grid_lower_symbols_drawn += 1
		drawn += 1
		if _fg_sess_perfect:
			_dbg_perf_grid_tex_drawn += 1
		if (
			forest_grid_debug_isolated
			and (
				forest_grid_debug_trace_pipeline
				or forest_grid_debug_log_grid_jitter_slots
				or forest_grid_debug_draw_slot_labels
			)
		):
			_fg_overlay_slot_labels.append(
				{"pres": root_pres, "slot": si, "upper": upper_band}
			)
		if _fg_sess_draw_roots:
			_fg_overlay_root_markers.append(
				{
					"pres": root_pres,
					"upper": upper_band,
					"rect_bc": rect_bottom,
					"side": side,
					"tree_scaled_bottom_pad": tree_pad,
				}
			)
		if debug_draw_effective_depth_points and _forest_symbol_scatter_ready():
			if mtree.get("ok", false):
				var bpad_t: int = int(mtree["bottom_padding_px"])
				var tht: int = int(mtree["height"])
				_fg_overlay_tree_effective_depth.append(root_pres)
				if pipeline_trace_slot:
					print(
						(
							"[EOM_DEBUG_TREE_SYMBOL_DEPTH] slot=%2d tex_idx=%d path=%s size=%dx%d bottom_padding_px=%d scaled_tree_bottom_padding_y=%.5f raw_quad_bottom_center=%s effective_tree_root_pres=%s"
						)
						% [
							si,
							ti,
							sym_path,
							int(mtree["width"]),
							tht,
							bpad_t,
							tree_pad,
							rect_bottom,
							root_pres,
						]
					)
		si += 1
	return drawn


func _fg_expected_grid_slots_for_qr(q: int, r: int) -> int:
	if scenario == null:
		return _GRID_SLOT_COUNT
	var hc = HexCoordScript.new(q, r)
	if scenario.cities_at(hc).size() > 0:
		return _GRID_UPPER_SLOT_COUNT
	return _GRID_SLOT_COUNT


func _fg_assert_isolated_perfect_invariants(symbol_scatter_active: bool) -> void:
	if not forest_grid_debug_isolated or not _fg_sess_perfect:
		return
	var n_hex: int = _fg_isolated_drawn_hex_keys.size()
	if forest_grid_debug_isolated_one_hex and n_hex != 1:
		push_warning(
			(
				"EOM ISOLATED+PERFECT invariant FAILED: isolated_one_hex expects isolated_hexes_drawn==1, got %d (keys=%s). Check TFV instance / gating."
			)
			% [n_hex, str(_fg_isolated_drawn_hex_keys.keys())]
		)
	if not symbol_scatter_active:
		push_warning(
			"EOM ISOLATED+PERFECT invariant FAILED: symbol grid inactive (use_forest_symbol_scatter or textures); grid_symbols_drawn=%d"
			% _fg_sess_grid_symbols_drawn
		)
		return
	if not _fg_sess_detail_hex_chosen:
		push_warning(
			"EOM ISOLATED+PERFECT invariant FAILED: no decorated sample hex on map; cannot draw 10-slot grid."
		)
		return
	var exp_sym: int = _fg_expected_grid_slots_for_qr(_fg_sess_detail_q, _fg_sess_detail_r)
	if _fg_sess_grid_symbols_drawn != exp_sym:
		push_warning(
			(
				"EOM ISOLATED+PERFECT invariant FAILED: grid_symbols_drawn=%d expected %d for sample hex (city skips lower band when expected==5)."
			)
			% [_fg_sess_grid_symbols_drawn, exp_sym]
		)
	if _fg_sess_draw_roots and _fg_sess_grid_root_markers_drawn != exp_sym:
		push_warning(
			(
				"EOM ISOLATED+PERFECT invariant FAILED: grid_root_markers_drawn=%d expected %d (draw_roots=%s)."
			)
			% [_fg_sess_grid_root_markers_drawn, exp_sym, _fg_sess_draw_roots]
		)
	if _fg_sess_frame_front_proc_calls > 0:
		push_warning(
			"EOM ISOLATED+PERFECT invariant FAILED: procedural_front_draws=%d expected 0"
			% _fg_sess_frame_front_proc_calls
		)
	if _fg_sess_frame_front_asset_calls > 0:
		push_warning(
			"EOM ISOLATED+PERFECT invariant FAILED: front_asset_draws=%d expected 0"
			% _fg_sess_frame_front_asset_calls
		)
	if _fg_sess_unit_occluder_draws > 0:
		push_warning(
			"EOM ISOLATED+PERFECT invariant FAILED: unit_occluder_forest_draws=%d expected 0"
			% _fg_sess_unit_occluder_draws
		)
	var mv_ok: bool = map_view != null and is_instance_valid(map_view)
	if not mv_ok:
		push_warning(
			"EOM ISOLATED+PERFECT invariant FAILED: map_view unwired; cannot assert map_back_forest_draws==0"
		)
	elif map_view.debug_plains_back_forest_draw_calls > 0:
		push_warning(
			(
				"EOM ISOLATED+PERFECT invariant FAILED: map_back_forest_draws=%d expected 0 (MapView suppression broken or wrong TFV ref)."
			)
			% map_view.debug_plains_back_forest_draw_calls
		)
	elif (
		map_view.debug_plains_back_symbol_draws != 0
		or map_view.debug_plains_back_asset_draws != 0
		or map_view.debug_plains_back_procedural_draws != 0
	):
		push_warning(
			(
				"EOM ISOLATED+PERFECT invariant FAILED: MapView back subcounts sym=%d asset=%d proc=%d (expected all 0)."
			)
			% [
				map_view.debug_plains_back_symbol_draws,
				map_view.debug_plains_back_asset_draws,
				map_view.debug_plains_back_procedural_draws,
			]
		)
	var si: int = 0
	while si < _GRID_SLOT_COUNT:
		var jt: Vector2 = forest_grid_jitter_local_deterministic(
			_fg_sess_detail_q, _fg_sess_detail_r, si, _fg_sess_no_jitter
		)
		if jt.length_squared() > 1e-12:
			push_warning(
				"EOM ISOLATED+PERFECT invariant FAILED: slot %d jitter_local=%s expected ZERO"
				% [si, jt]
			)
		si += 1


func _fg_assert_isolated_grid_pass_consistency() -> void:
	if not forest_grid_debug_isolated:
		return
	if not (use_forest_symbol_scatter and _forest_symbol_scatter_ready()):
		return
	if (
		_fg_sess_grid_upper_symbols_drawn + _fg_sess_grid_lower_symbols_drawn
		!= _fg_sess_grid_symbols_drawn
	):
		push_warning(
			(
				"[EOM_DEBUG_FOREST_PIPELINE] %s: upper_symbols=%d + lower_symbols=%d != grid_symbols=%d"
			)
			% [
				str(get_path()),
				_fg_sess_grid_upper_symbols_drawn,
				_fg_sess_grid_lower_symbols_drawn,
				_fg_sess_grid_symbols_drawn,
			]
		)


func _fg_assert_isolated_normal_root_marker_counts() -> void:
	if not forest_grid_debug_isolated or _fg_sess_perfect or not _fg_sess_draw_roots:
		return
	if _fg_root_markers_drawn_total != _fg_sess_grid_symbols_drawn:
		push_warning(
			(
				"EOM ISOLATED+NORMAL root markers: root_markers_drawn_total=%d != grid_symbols_drawn=%d"
			)
			% [_fg_root_markers_drawn_total, _fg_sess_grid_symbols_drawn]
		)
	if (
		_fg_root_marker_geom_checks_passed > 0
		and _fg_root_marker_geom_checks_passed != _fg_root_markers_drawn_total
	):
		push_warning(
			(
				"EOM ISOLATED+NORMAL root markers: geom_checks_passed=%d != root_markers_drawn_total=%d"
			)
			% [_fg_root_marker_geom_checks_passed, _fg_root_markers_drawn_total]
		)


func _fg_print_root_marker_isolated_line() -> void:
	if not forest_grid_debug_isolated or not _fg_sess_draw_roots:
		return
	var mode_s: String = "perfect" if _fg_sess_perfect else "normal"
	var je: String = str(not _fg_sess_no_jitter)
	var gm: String = _fg_grid_mode_log_label()
	var sd: int = _fg_sess_grid_symbols_drawn
	var rd: int = _fg_sess_grid_root_markers_drawn if _fg_sess_draw_roots else 0
	print(
		(
			"[EOM_DEBUG_ROOT_MARKERS] grid_mode=%s slots_drawn=%d roots_drawn=%d jitter_enabled=%s tfv_path=%s instance_id=%d root_marker_path=_draw_forest_grid_root_marker circle_r_px=%.1f cross_half_px=%.1f line_w_px=%.1f legacy_mode=%s grid_symbols_session=%d root_markers_drawn_total=%d upper=%d lower=%d helper_calls=%d marker_radius_used=%.1f geom_checks_passed=%d"
		)
		% [
			gm,
			sd,
			rd,
			je,
			str(get_path()),
			get_instance_id(),
			_FG_GRID_ROOT_MARKER_CIRCLE_R_PX,
			_FG_GRID_ROOT_MARKER_CROSS_HALF_PX,
			_FG_GRID_ROOT_MARKER_LINE_W_PX,
			mode_s,
			_fg_sess_grid_symbols_drawn,
			_fg_root_markers_drawn_total,
			_fg_root_markers_drawn_upper,
			_fg_root_markers_drawn_lower,
			_fg_root_marker_draw_helper_calls,
			_fg_root_marker_radius_px_used,
			_fg_root_marker_geom_checks_passed,
		]
	)


func _fg_print_isolated_frame_summary() -> void:
	var mb: int = 0
	var mv_ok: bool = map_view != null and is_instance_valid(map_view)
	if mv_ok:
		mb = map_view.debug_plains_back_forest_draw_calls
	var r0: float = forest_grid_jitter_max_radius_world()
	var n_iso_hex: int = _fg_isolated_drawn_hex_keys.size()
	print(
		(
			"[EOM_DEBUG_FOREST_ISOLATED_END] TFV instance_id=%d path=%s map_view_wired=%s"
			+ " | export: isolated=%s perfect_export=%s isolated_one_hex=%s draw_roots=%s suppress_map_back=%s use_forest_symbol_scatter=%s use_forest_asset_overlays=%s"
			+ " | resolved: _fg_sess_perfect=%s _fg_sess_no_jitter=%s env_PERFECT=%s"
			+ " | sample_hex=%s (%d,%d) isolated_candidate_forest_hexes=%d isolated_hexes_drawn=%d"
			+ " | grid_symbols_drawn=%d grid_root_markers_drawn=%d old_scatter_front=0 procedural_front_draws=%d front_asset_draws=%d unit_occluder_draws=%d map_back_forest_draws=%d symbol_grid_active=%s"
		)
		% [
			get_instance_id(),
			str(get_path()),
			mv_ok,
			forest_grid_debug_isolated,
			forest_grid_debug_perfect,
			forest_grid_debug_isolated_one_hex,
			forest_grid_debug_draw_roots,
			forest_grid_debug_suppress_map_back,
			use_forest_symbol_scatter,
			use_forest_asset_overlays,
			_fg_sess_perfect,
			_fg_sess_no_jitter,
			OS.get_environment(_EOM_ENV_FOREST_GRID_PERFECT) == "1",
			_fg_sess_detail_hex_chosen,
			_fg_sess_detail_q,
			_fg_sess_detail_r,
			_fg_sess_isolated_candidate_hexes,
			n_iso_hex,
			_fg_sess_grid_symbols_drawn,
			_fg_sess_grid_root_markers_drawn,
			_fg_sess_frame_front_proc_calls,
			_fg_sess_frame_front_asset_calls,
			_fg_sess_unit_occluder_draws,
			mb,
			use_forest_symbol_scatter and _forest_symbol_scatter_ready(),
		]
	)
	var roots_iso: int = (
		_fg_sess_grid_root_markers_drawn if _fg_sess_draw_roots else 0
	)
	print(
		(
			"[EOM_DEBUG_FOREST_ISOLATED] detail: grid_mode=%s slots_drawn=%d roots_drawn=%d jitter_enabled=%s R_jitter_world=%.4f padding_world=%.4f P_world=%.4f grid_textures_pass_sum=%d"
		)
		% [
			_fg_grid_mode_log_label(),
			_fg_sess_grid_symbols_drawn,
			roots_iso,
			str(not _fg_sess_no_jitter),
			r0,
			forest_grid_row_padding_world(),
			forest_grid_row_pitch_world(),
			_fg_sess_frame_grid_textures,
		]
	)
	var Hsz: float = HexLayoutScript.SIZE
	var eff_r: float = forest_grid_safe_disk_radius_world()
	var gap_f: float = forest_grid_vertical_gap_jitter_edges_frac()
	var y0: float = forest_grid_slot_base_local(0).y / Hsz
	var y1: float = forest_grid_slot_base_local(2).y / Hsz
	var y2: float = forest_grid_slot_base_local(5).y / Hsz
	var y3: float = forest_grid_slot_base_local(8).y / Hsz
	var x2: float = absf(forest_grid_slot_base_local(0).x / Hsz)
	var x3: float = absf(forest_grid_slot_base_local(2).x / Hsz)
	var P_f: float = forest_grid_row_pitch_frac()
	print(
		(
			"[EOM_DEBUG_FOREST_GRID] uniform_lattice row_y/H: y0=%.5f y1=%.5f y2=%.5f y3=%.5f P/H=%.5f | "
			+ "x_two_row=±%.3fH x_three_row=±%.3fH,0 | padding/H=%.5f eff_R_safe=%.4f (R+M) SIZE=%.1f"
		)
		% [
			y0,
			y1,
			y2,
			y3,
			P_f,
			x2,
			x3,
			gap_f,
			eff_r,
			Hsz,
		]
	)
	var sb: int = 0
	while sb < _GRID_SLOT_COUNT:
		var bl: Vector2 = forest_grid_slot_base_local(sb)
		print(
			"[EOM_DEBUG_FOREST_GRID] slot_base[%d] local_xy=(%.3f,%.3f) world_xy=(%.2f,%.2f)"
			% [sb, bl.x / Hsz, bl.y / Hsz, bl.x, bl.y]
		)
		sb += 1


func _draw() -> void:
	if map == null or layout == null:
		return
	if camera == null:
		var cam = MapCameraScript.new()
		cam.projection = MapPlaneProjectionScript.new()
		camera = cam
	if _fg_should_print_runtime_identity():
		_fg_print_runtime_identity()
	if forest_debug_log_counts_once and not _forest_counts_logged:
		_forest_counts_logged = true
		var plains_n: int = 0
		var dec_n: int = 0
		var cl = map.coords()
		var ii: int = 0
		while ii < cl.size():
			var c = cl[ii]
			if int(map.terrain_at(c)) == HexMapScript.Terrain.PLAINS:
				plains_n += 1
				if PlainsForestScript.is_plains_forest_decorated(c.q, c.r, forest_density_ratio):
					dec_n += 1
			ii += 1
		print(
			"TerrainForegroundView forest stats: PLAINS=%d decorated=%d density=%.3f front_opacity=%.3f"
			% [plains_n, dec_n, forest_density_ratio, forest_front_opacity]
		)
	if not forest_grid_debug_isolated:
		_fg_warned_isolated_no_symbols = false
	var symbol_scatter_active: bool = (
		use_forest_symbol_scatter and _forest_symbol_scatter_ready()
	)
	_fg_sess_perfect = _eom_forest_grid_perfect()
	_fg_sess_no_jitter = _fg_sess_perfect
	_fg_sess_draw_roots = forest_grid_debug_draw_roots
	_fg_sess_roots_detail_log = forest_grid_debug_log or forest_grid_debug_draw_roots
	_fg_sess_detail_grid_acc = 0
	_fg_sess_detail_totals_printed = false
	_fg_sess_frame_grid_textures = 0
	_fg_sess_frame_front_proc_calls = 0
	_fg_sess_frame_front_asset_calls = 0
	if _fg_sess_perfect:
		_dbg_perf_grid_tex_drawn = 0
		_dbg_perf_root_markers_drawn = 0
	if _fg_sess_roots_detail_log and not forest_grid_debug_isolated:
		print(
			(
				"[EOM_DEBUG_FOREST_GRID] session grid_mode=%s jitter_enabled=%s | resolved_perfect=%s export.forest_grid_debug_perfect=%s env.EOM_DEBUG_FOREST_GRID_PERFECT=%s no_jitter=%s draw_roots=%s R_max_world=%.4f M_safety_world=%.4f | Stale env still forces perfect: clear in shell/editor and restart."
			)
			% [
				_fg_grid_mode_log_label(),
				str(not _fg_sess_no_jitter),
				str(_fg_sess_perfect),
				str(forest_grid_debug_perfect),
				str(OS.get_environment(_EOM_ENV_FOREST_GRID_PERFECT) == "1"),
				str(_fg_sess_no_jitter),
				str(_fg_sess_draw_roots),
				forest_grid_jitter_max_radius_world(),
				forest_grid_safety_margin_world(),
			]
		)
	if _eom_forest_grid_debug_log():
		print(
			(
				"[EOM_DEBUG_FOREST_GRID] banner export.forest_grid_debug_log=%s env.EOM_DEBUG_FOREST_GRID=%s | Clear stale env: cmd `set EOM_DEBUG_FOREST_GRID_PERFECT=` & `set EOM_DEBUG_FOREST_GRID=`; PowerShell `Remove-Item Env:EOM_DEBUG_FOREST_GRID_PERFECT,Env:EOM_DEBUG_FOREST_GRID -ErrorAction SilentlyContinue`; bash `unset EOM_DEBUG_FOREST_GRID_PERFECT EOM_DEBUG_FOREST_GRID`."
			)
			% [
				str(forest_grid_debug_log),
				str(OS.get_environment(_EOM_ENV_DEBUG_FOREST_GRID) == "1"),
			]
		)
	var coord_list = map.coords()
	_fg_pick_sample_decorated_plains_hex(coord_list)
	_fg_overlay_root_markers.clear()
	_fg_overlay_jitter_items.clear()
	_fg_overlay_jitter_vectors.clear()
	_fg_overlay_slot_labels.clear()
	_fg_overlay_unit_raw_png_bottom.clear()
	_fg_overlay_unit_effective_depth.clear()
	_fg_overlay_tree_effective_depth.clear()
	_fg_sess_logged_unit_png_bottom_sample = false
	_fg_isolated_drawn_hex_keys.clear()
	_fg_sess_grid_symbols_drawn = 0
	_fg_sess_grid_upper_symbols_drawn = 0
	_fg_sess_grid_lower_symbols_drawn = 0
	_fg_sess_grid_root_markers_drawn = 0
	_fg_sess_jitter_debug_rings_drawn = 0
	_fg_sess_unit_occluder_draws = 0
	_fg_root_markers_drawn_total = 0
	_fg_root_markers_drawn_upper = 0
	_fg_root_markers_drawn_lower = 0
	_fg_root_marker_draw_helper_calls = 0
	_fg_root_marker_radius_px_used = 0.0
	_fg_root_marker_geom_checks_passed = 0
	_fg_sess_isolated_candidate_hexes = 0
	if forest_grid_debug_isolated:
		var cix: int = 0
		while cix < coord_list.size():
			var cx = coord_list[cix]
			if int(map.terrain_at(cx)) == HexMapScript.Terrain.PLAINS:
				if PlainsForestScript.is_plains_forest_decorated(cx.q, cx.r, forest_density_ratio):
					_fg_sess_isolated_candidate_hexes += 1
			cix += 1
		print(
			(
				"[EOM_DEBUG_FOREST_ISOLATED_START] instance_id=%d path=%s"
				+ " | export flags: isolated=%s perfect=%s one_hex=%s draw_roots=%s suppress_map_back=%s scatter=%s asset_overlay=%s"
				+ " | grid_mode=%s jitter_enabled=%s | resolved _fg_sess_perfect=%s _fg_sess_no_jitter=%s env_PERFECT=%s | sample_chosen=%s sample=(%d,%d) candidate_decorated_hexes=%d"
			)
			% [
				get_instance_id(),
				str(get_path()),
				forest_grid_debug_isolated,
				forest_grid_debug_perfect,
				forest_grid_debug_isolated_one_hex,
				forest_grid_debug_draw_roots,
				forest_grid_debug_suppress_map_back,
				use_forest_symbol_scatter,
				use_forest_asset_overlays,
				_fg_grid_mode_log_label(),
				str(not _fg_sess_no_jitter),
				_fg_sess_perfect,
				_fg_sess_no_jitter,
				OS.get_environment(_EOM_ENV_FOREST_GRID_PERFECT) == "1",
				_fg_sess_detail_hex_chosen,
				_fg_sess_detail_q,
				_fg_sess_detail_r,
				_fg_sess_isolated_candidate_hexes,
			]
		)
	# Phase **4.6p — pass 1:** non-grid paths when symbol PNGs unavailable; else **only** upper grid (**0–4**).
	var idx: int = 0
	while idx < coord_list.size():
		var coord = coord_list[idx]
		var terrain: int = int(map.terrain_at(coord))
		if terrain == HexMapScript.Terrain.PLAINS:
			if PlainsForestScript.is_plains_forest_decorated(coord.q, coord.r, forest_density_ratio):
				var world: Vector2 = layout.hex_to_world(coord.q, coord.r)
				_reload_forest_tree_symbols_if_needed()
				var skip_main: bool = _should_skip_main_clump_for_city(coord)
				var allow_iso: bool = _fg_isolated_draw_this_hex(coord.q, coord.r)
				var log_hex: bool = (
					_fg_sess_roots_detail_log
					and _fg_sess_detail_hex_chosen
					and coord.q == _fg_sess_detail_q
					and coord.r == _fg_sess_detail_r
				)
				if forest_grid_debug_isolated:
					if not symbol_scatter_active:
						if not _fg_warned_isolated_no_symbols:
							_fg_warned_isolated_no_symbols = true
							push_warning(
								"TerrainForegroundView: forest_grid_debug_isolated needs use_forest_symbol_scatter plus loadable tree_symbol_01..20; skipping TFV forest draws."
							)
					elif allow_iso:
						var up_iso: int = _draw_plains_forest_front_symbol_grid_pass(
							camera, world, coord.q, coord.r, true, log_hex
						)
						_fg_sess_frame_grid_textures += up_iso
						if forest_grid_debug_isolated and up_iso > 0:
							_fg_isolated_drawn_hex_keys["%d,%d" % [coord.q, coord.r]] = true
						if log_hex:
							_fg_sess_detail_grid_acc += up_iso
				elif symbol_scatter_active:
					var up_n: int = _draw_plains_forest_front_symbol_grid_pass(
						camera, world, coord.q, coord.r, true, log_hex
					)
					_fg_sess_frame_grid_textures += up_n
					if log_hex:
						_fg_sess_detail_grid_acc += up_n
				elif use_forest_asset_overlays:
					if skip_main:
						_draw_plains_forest_front_hex_owned(
							camera, world, coord.q, coord.r, true
						)
					else:
						_draw_plains_forest_front_asset(camera, world, coord.q, coord.r)
				else:
					_draw_plains_forest_front_hex_owned(
						camera, world, coord.q, coord.r, skip_main
					)
				if (
					enable_unit_occlusion_test
					and scenario != null
					and not forest_grid_debug_isolated
				):
					if (
						scenario.cities_at(coord).size() == 0
						and scenario.units_at(coord).size() > 0
					):
						var anchor_pres_u: Vector2 = camera.to_presentation(world)
						var pscale_u: float = camera.perspective_scale_at(world)
						var hex_h: float = HexLayoutScript.SIZE * 2.0
						var side_u: float = (
							hex_h * foreground_unit_reference_height_ratio * pscale_u
						)
						_draw_unit_forest_occluder(anchor_pres_u, side_u, coord.q, coord.r)
						_fg_sess_unit_occluder_draws += 1
		idx += 1
	# Phase **4.6p — pass 2:** units (**foot** = projected **hex center**, layout **y = 0** in local space for the band).
	if units_view != null and scenario != null:
		var ulist = scenario.units()
		var ui: int = 0
		while ui < ulist.size():
			var u = ulist[ui]
			var u_world: Vector2 = layout.hex_to_world(u.position.q, u.position.r)
			var u_anchor_pres: Vector2 = camera.to_presentation(u_world)
			var u_pscale: float = camera.perspective_scale_at(u_world)
			units_view.draw_unit_marker_at(
				self,
				u_anchor_pres,
				u_pscale,
				str(u.type_id),
				int(u.owner_id)
			)
			var collect_png_bottom: bool = _eom_debug_unit_png_bottom()
			var collect_unit_effective: bool = debug_draw_effective_depth_points
			if collect_png_bottom or collect_unit_effective:
				var u_drawn: Rect2 = UnitsView.debug_last_unit_png_rect
				if u_drawn.size.x > 0.0:
					if collect_png_bottom:
						var raw_png_bottom_center: Vector2 = (
							UnitsView.debug_last_unit_png_bottom_center
						)
						_fg_overlay_unit_raw_png_bottom.append(raw_png_bottom_center)
						var effective_unit_depth: Vector2 = (
							UnitsView.debug_last_unit_effective_depth_point
						)
						var upath: String = UnitsView.marker_texture_res_path(str(u.type_id))
						var mue: Dictionary = TextureAlphaMetricsClass.metrics_for_res_path(upath)
						var bottom_pad_px: int = 0
						var tex_w: int = 0
						var tex_h: int = 0
						var scaled_bottom_pad_y: float = 0.0
						if mue.get("ok", false):
							tex_w = int(mue["width"])
							tex_h = int(mue["height"])
							bottom_pad_px = int(mue["bottom_padding_px"])
							if tex_h > 0:
								scaled_bottom_pad_y = TextureAlphaMetricsClass.scaled_bottom_padding_y(
									mue, u_drawn.size.y
								)
						if not _fg_sess_logged_unit_png_bottom_sample:
							_fg_sess_logged_unit_png_bottom_sample = true
							print(
								(
									"[EOM_DEBUG_UNIT_PNG_BOTTOM] type_id=%s path=%s tex_size=%dx%d unit_rect=%s raw_png_bottom_center=%s bottom_padding_px=%d scaled_bottom_padding_y=%.5f effective_unit_depth_point=%s anchor_pres=%s delta_effective_minus_anchor=%s (presentation px)"
								)
								% [
									str(u.type_id),
									upath,
									tex_w,
									tex_h,
									u_drawn,
									raw_png_bottom_center,
									bottom_pad_px,
									scaled_bottom_pad_y,
									effective_unit_depth,
									u_anchor_pres,
									effective_unit_depth - u_anchor_pres,
								]
							)
					if collect_unit_effective:
						_fg_overlay_unit_effective_depth.append(
							UnitsView.debug_last_unit_effective_depth_point
						)
			ui += 1
	debug_last_overlay_unit_raw_png_queued = _fg_overlay_unit_raw_png_bottom.size()
	debug_last_overlay_unit_effective_depth_queued = (
		_fg_overlay_unit_effective_depth.size()
	)
	# Phase **4.6p — pass 3:** **lower** half-plane grid (**local_y** **>** **0** — **in front** of unit band).
	idx = 0
	while idx < coord_list.size():
		var coord_c = coord_list[idx]
		var terr_c: int = int(map.terrain_at(coord_c))
		if terr_c == HexMapScript.Terrain.PLAINS:
			if PlainsForestScript.is_plains_forest_decorated(
				coord_c.q, coord_c.r, forest_density_ratio
			):
				var world_c: Vector2 = layout.hex_to_world(coord_c.q, coord_c.r)
				_reload_forest_tree_symbols_if_needed()
				var skip_c: bool = _should_skip_main_clump_for_city(coord_c)
				var allow_iso_c: bool = _fg_isolated_draw_this_hex(coord_c.q, coord_c.r)
				var log_hex_c: bool = (
					_fg_sess_roots_detail_log
					and _fg_sess_detail_hex_chosen
					and coord_c.q == _fg_sess_detail_q
					and coord_c.r == _fg_sess_detail_r
				)
				if forest_grid_debug_isolated:
					if symbol_scatter_active and allow_iso_c:
						if skip_c:
							if (
								log_hex_c
								and not _fg_sess_detail_totals_printed
							):
								_fg_sess_detail_totals_printed = true
								_fg_print_sample_hex_grid_summary(coord_c.q, coord_c.r)
						else:
							var lo_iso: int = _draw_plains_forest_front_symbol_grid_pass(
								camera, world_c, coord_c.q, coord_c.r, false, log_hex_c
							)
							_fg_sess_frame_grid_textures += lo_iso
							if forest_grid_debug_isolated and lo_iso > 0:
								_fg_isolated_drawn_hex_keys[
									"%d,%d" % [coord_c.q, coord_c.r]
								] = true
							if log_hex_c:
								_fg_sess_detail_grid_acc += lo_iso
								if not _fg_sess_detail_totals_printed:
									_fg_sess_detail_totals_printed = true
									_fg_print_sample_hex_grid_summary(
										coord_c.q, coord_c.r
									)
				elif symbol_scatter_active and skip_c:
					if (
						_fg_sess_roots_detail_log
						and _fg_sess_detail_hex_chosen
						and coord_c.q == _fg_sess_detail_q
						and coord_c.r == _fg_sess_detail_r
						and not _fg_sess_detail_totals_printed
					):
						_fg_sess_detail_totals_printed = true
						_fg_print_sample_hex_grid_summary(coord_c.q, coord_c.r)
				elif symbol_scatter_active and not skip_c:
					var lo_n: int = _draw_plains_forest_front_symbol_grid_pass(
						camera, world_c, coord_c.q, coord_c.r, false, log_hex_c
					)
					_fg_sess_frame_grid_textures += lo_n
					if log_hex_c:
						_fg_sess_detail_grid_acc += lo_n
						if not _fg_sess_detail_totals_printed:
							_fg_sess_detail_totals_printed = true
							_fg_print_sample_hex_grid_summary(coord_c.q, coord_c.r)
		idx += 1
	_fg_flush_debug_overlay_top()
	if forest_grid_debug_isolated:
		_fg_print_root_marker_isolated_line()
		_fg_print_isolated_frame_summary()
		print(
			(
				"[EOM_DEBUG_FOREST_PIPELINE] TFV frame_counters path=%s tfv_grid_symbols=%d tfv_grid_upper=%d tfv_grid_lower=%d tfv_grid_roots=%d tfv_grid_jitter_circles=%d tfv_front_asset=%d tfv_front_proc=%d tfv_unit_occluder=%d"
			)
			% [
				str(get_path()),
				_fg_sess_grid_symbols_drawn,
				_fg_sess_grid_upper_symbols_drawn,
				_fg_sess_grid_lower_symbols_drawn,
				_fg_sess_grid_root_markers_drawn,
				_fg_sess_jitter_debug_rings_drawn,
				_fg_sess_frame_front_asset_calls,
				_fg_sess_frame_front_proc_calls,
				_fg_sess_unit_occluder_draws,
			]
		)
		_fg_warn_isolated_non_grid_pipeline_leak()
		if map_view == null or not is_instance_valid(map_view):
			push_warning(
				"TerrainForegroundView: forest_grid_debug_isolated but map_view is null — cannot verify map_back_forest_draws==0; set terrain_foreground.map_view in main.gd."
			)
		_fg_assert_isolated_perfect_invariants(symbol_scatter_active)
		_fg_assert_isolated_grid_pass_consistency()
		_fg_assert_isolated_normal_root_marker_counts()
		debug_last_isolated_grid_symbols_drawn = _fg_sess_grid_symbols_drawn
		debug_last_isolated_grid_root_markers_drawn = _fg_sess_grid_root_markers_drawn
		debug_last_isolated_jitter_ring_draws = (
			_fg_sess_jitter_debug_rings_drawn if forest_grid_debug_draw_jitter_circles else -1
		)
	if _eom_debug_unit_tree_draw():
		var uv_set: bool = units_view != null
		var uv_v: bool = uv_set and is_instance_valid(units_view)
		var back_tfv: bool = false
		if uv_v:
			var tfv_ref = units_view.terrain_foreground_view
			back_tfv = tfv_ref != null and is_instance_valid(tfv_ref) and (tfv_ref as Node) == self
		var pass2: bool = units_view != null and scenario != null
		var pass2_n: int = scenario.units().size() if pass2 else 0
		print(
			(
				"[EOM_DEBUG_UNIT_DRAW] TFV.units_view assigned=%s uv_valid=%s uv.TFV assigned=%s backrefs_this_tfv=%s | "
				+ "UV._draw delegated=%s UV.units_drawn_on_own_canvas=%d | TFV pass2_ran=%s pass2_unit_draws=%d | double_draw_risk=%s"
			)
			% [
				uv_set,
				uv_v,
				uv_v and units_view.terrain_foreground_view != null,
				back_tfv,
				UnitsView.debug_last_draw_delegated,
				UnitsView.debug_last_units_drawn_on_own_canvas,
				pass2,
				pass2_n,
				pass2_n > 0 and UnitsView.debug_last_units_drawn_on_own_canvas > 0,
			]
		)
	if _fg_sess_perfect:
		var rm_dbg: int = (
			_fg_sess_grid_root_markers_drawn
			if forest_grid_debug_isolated
			else _dbg_perf_root_markers_drawn
		)
		print(
			(
				"[EOM_DEBUG_FOREST_GRID_PERFECT] grid_mode=perfect_zero_jitter slots_drawn=%d roots_drawn=%d jitter_enabled=false textures_eq_markers=%s | undotted MapView back optional (see MapView log)."
			)
			% [
				_dbg_perf_grid_tex_drawn,
				rm_dbg,
				_dbg_perf_grid_tex_drawn == rm_dbg,
			]
		)
	if _eom_forest_grid_debug_log():
		print(
			(
				"[EOM_DEBUG_FOREST_GRID] frame_summary TFV_front_tree_symbol_rects=%d _draw_plains_forest_front_hex_owned_calls=%d _draw_plains_forest_front_asset_calls=%d symbol_scatter_grid_only=%s"
			)
			% [
				_fg_sess_frame_grid_textures,
				_fg_sess_frame_front_proc_calls,
				_fg_sess_frame_front_asset_calls,
				str(symbol_scatter_active),
			]
		)
	debug_pipeline_tfv_path = str(get_path())
	debug_pipeline_tfv_instance_id = get_instance_id()
	debug_pipeline_tfv_grid_symbols = _fg_sess_grid_symbols_drawn
	debug_pipeline_tfv_grid_upper_symbols = _fg_sess_grid_upper_symbols_drawn
	debug_pipeline_tfv_grid_lower_symbols = _fg_sess_grid_lower_symbols_drawn
	debug_pipeline_tfv_grid_roots = _fg_sess_grid_root_markers_drawn
	debug_pipeline_tfv_jitter_circles = _fg_sess_jitter_debug_rings_drawn
	debug_pipeline_tfv_front_asset = _fg_sess_frame_front_asset_calls
	debug_pipeline_tfv_front_proc = _fg_sess_frame_front_proc_calls
	debug_pipeline_tfv_unit_occluder = _fg_sess_unit_occluder_draws
