# Wires GameState, Scenario, HexLayout, MapView, UnitsView, SelectionView, and SelectionController. No gameplay loop, no autoloads.
# See docs/RENDERING.md, docs/SELECTION.md
extends Node2D

## Initial pixel origin for map-layer **Node2D** children including **`TerrainEdgeBlendView`** (**5.1.17k** — **PLAINS↔GRASSLAND** edge softening), **`EmpireBorderView`** (Phase **5.1.17h** — always-on owner **union** perimeter), **`CityTerritoryView`** (Phase **5.1.16i** — selected-city emphasis ring), **`TileYieldOverlayView`** (Phase **5.1.16f**), **`CityWorkedTilesView`** (Phase **5.1.17e** — citizen markers **PLANNING-only**), **UnitNameplateView** / **CityNameplateView** (Phase **5.1.11** / **5.1.15**). **4.5m:** set **once** in `_ready`; pan uses **MapCamera.camera_world_offset**. **`TerrainEdgeBlendView`** sibling **after** **`MapView`**, **`z_index` 0** — above **base terrain**, below **`EmpireBorderView`**. **`EmpireBorderView`** sibling **after** **`TerrainEdgeBlendView`**, **`z_index` 0**, thinner stroke — **above** terrain blend + base paint, **below** **`CityTerritoryView`** / cities / units shells (**0**, later sibling draws **above**) / **`TerrainForegroundView`** / **`LightningTreeView`** / **`TileYieldOverlayView`** (**`z_index` 1**). **`CityWorkedTilesView`** (**after** **`TileYieldOverlayView`**, same **`z_index` 1**) paints **above** yield icons in **Manage Citizens** (primary planning read); **below** nameplates (**`z_index` 2**). **5.1.15b** orders **`CityNameplateView`** before **`UnitNameplateView`** so **unit** nameplates paint **on top**. Still below **HudCanvas**.
const MAP_LAYER_ORIGIN: Vector2 = Vector2(400.0, 428.0)

const ScenarioScript = preload("res://domain/scenario.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const MapPlaneProjectionScript = preload("res://presentation/map_plane_projection.gd")
const MapCameraScript = preload("res://presentation/map_camera.gd")
const SelectionStateScript = preload("res://presentation/selection_state.gd")
const CityViewStateScript = preload("res://presentation/city_view_state.gd")
const GameStateScript = preload("res://domain/game_state.gd")
const FactionBannerGalleryScript = preload("res://presentation/faction_banner_gallery.gd")
const PlainsForestScript = preload("res://presentation/plains_forest_decoration.gd")
const YieldOverlayToggleScript = preload("res://presentation/yield_overlay_toggle.gd")
const CloudSessionScript = preload("res://cloud/cloud_session.gd")
const ServerSnapshotAdapterScript = preload("res://cloud/server_snapshot_adapter.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const EndTurnScript = preload("res://domain/actions/end_turn.gd")
const TurnViewSyncScript = preload("res://presentation/turn_view_sync.gd")
const CloudClientScript = preload("res://cloud/cloud_client.gd")
const CloudCredentialStoreScript = preload("res://cloud/cloud_credential_store.gd")
const BootIntentScript = preload("res://cloud/boot_intent.gd")
const CityProductionPanelScript = preload("res://presentation/city_production_panel.gd")
## Phase 4.5n: mouse-wheel zoom multiplier (center-anchored in layer-local space; not cursor-anchored).
const ZOOM_STEP: float = 1.10

## Slice C8: opt-in cloud client (**EOM_CLOUD_CLIENT=1** also enables). Default **local hotseat** unchanged.
@export var use_cloud_server: bool = false
@export var cloud_base_url: String = "http://127.0.0.1:8000"
@export var cloud_scenario_id: String = "prototype_play"
## Slice **C9**: reconnect to an existing match via **GET /v1/matches/{id}** (**EOM_CLOUD_MATCH_ID** overrides).
@export var cloud_match_id: String = ""
## Slice **C13a**: seat or host token for **POST /actions** (**EOM_CLOUD_SEAT_TOKEN** overrides).
@export var cloud_seat_token: String = ""

var _faction_banner_gallery
var _map_projection
var _map_camera
var _cloud_session = null
var _cloud_mode: bool = false
var _play_game_state = null
var _play_selection = null
var _session_layout = null
var _cloud_legal_busy: bool = false
var _cloud_legal_stale: bool = false
var _cloud_last_legal_actions: Array = []
## Slice C14c: credentials from consumed **BootIntent** (priority over inspector, below env).
var _boot_cloud_from_intent: bool = false
var _boot_cloud_match_id: String = ""
var _boot_cloud_seat_token: String = ""
## Slice C8: true from cloud bootstrap until first server snapshot is applied and presentation refreshed.
var _cloud_loading: bool = false
## Slice C11: blocks map input during cloud combat presentation (presentation-only; snapshot applies after).
var _cloud_combat_anim_busy: bool = false
const CLOUD_COMBAT_ANIM_SEC: float = 0.6
## After create-match / snapshot failure: keep overlay + block play (no silent hotseat fallback).
var _cloud_boot_stranded: bool = false
var _cloud_loading_overlay_root: CanvasLayer = null
var _cloud_loading_label: Label = null
## Slice C8: last **current_player_id** after a cloud snapshot apply (banner gating diagnostics).
var _cloud_last_seen_current_player_id: int = -1
## Slice C8: node names hidden until first server snapshot is wired (cloud path only).
var _cloud_gameplay_shell_node_names: Array = [
	"TurnLabel",
	"TurnStartBanner",
	"HudCanvas",
	"MapView",
	"TerrainEdgeBlendView",
	"EmpireBorderView",
	"CityTerritoryView",
	"CitiesView",
	"SelectionView",
	"UnitsView",
	"TerrainForegroundView",
	"MapVisibilityView",
	"LightningTreeView",
	"TileYieldOverlayView",
	"CityWorkedTilesView",
	"CityNameplateView",
	"UnitNameplateView",
	"CombatClashBurstView",
	"SelectionController",
	"EndTurnController",
	"AITurnController",
	"LogView",
]

func _redraw_map_layers() -> void:
	$MapView.queue_redraw()
	$TerrainEdgeBlendView.queue_redraw()
	$EmpireBorderView.queue_redraw()
	$CityTerritoryView.queue_redraw()
	$CitiesView.queue_redraw()
	$SelectionView.queue_redraw()
	$UnitsView.queue_redraw()
	$TerrainForegroundView.queue_redraw()
	$MapVisibilityView.queue_redraw()
	$LightningTreeView.queue_redraw()
	$TileYieldOverlayView.queue_redraw()
	$CityWorkedTilesView.queue_redraw()
	$CityNameplateView.queue_redraw()
	$UnitNameplateView.queue_redraw()
	$CombatClashBurstView.queue_redraw()


func _refresh_turn_hud_after_turn_label() -> void:
	$HudCanvas/TurnStatusPanel.refresh()
	$HudCanvas/PlayerContactStrip.refresh()


func _ready() -> void:
	_map_projection = MapPlaneProjectionScript.new()
	_map_projection.vanishing_pres = (get_viewport_rect().size * 0.5) - MAP_LAYER_ORIGIN
	_map_camera = MapCameraScript.new()
	_map_camera.projection = _map_projection
	for n in [
		$MapView,
		$TerrainEdgeBlendView,
		$EmpireBorderView,
		$CityTerritoryView,
		$CitiesView,
		$SelectionView,
		$UnitsView,
		$TerrainForegroundView,
		$LightningTreeView,
		$TileYieldOverlayView,
		$CityWorkedTilesView,
		$CityNameplateView,
		$UnitNameplateView,
		$CombatClashBurstView,
		$SelectionController,
	]:
		n.position = MAP_LAYER_ORIGIN
	$MapView.scale = Vector2.ONE
	$MapView.camera = _map_camera
	$CitiesView.scale = Vector2.ONE
	$CitiesView.camera = _map_camera
	$SelectionView.scale = Vector2.ONE
	$SelectionView.camera = _map_camera
	$UnitsView.scale = Vector2.ONE
	$UnitsView.camera = _map_camera
	# Phase **4.6p:** **`TerrainForegroundView.z_index = 1`** lifts the **entire foreground canvas**
	# above **`MapView`** / **`CitiesView`** / **`SelectionView`** / **`UnitsView`** node shells so **back**
	# terrain stays behind **and** forest grid passes + marker pass run in **one** TFV **`_draw`**. **`UnitsView`** /
	# **`CitiesView`** **`_draw`** are no-ops when wired to TFV — markers are not painted on a second **`CanvasItem`**.
	$UnitsView.z_index = 0
	$TerrainForegroundView.scale = Vector2.ONE
	$TerrainForegroundView.camera = _map_camera
	$TerrainForegroundView.z_index = 1
	$MapVisibilityView.scale = Vector2.ONE
	$MapVisibilityView.camera = _map_camera
	$MapVisibilityView.z_index = 1
	$LightningTreeView.z_index = 1
	$EmpireBorderView.scale = Vector2.ONE
	$EmpireBorderView.camera = _map_camera
	$EmpireBorderView.z_index = 0
	$TerrainEdgeBlendView.scale = Vector2.ONE
	$TerrainEdgeBlendView.camera = _map_camera
	$TerrainEdgeBlendView.z_index = 0
	$CityTerritoryView.scale = Vector2.ONE
	$CityTerritoryView.camera = _map_camera
	$CityTerritoryView.z_index = 0
	$TileYieldOverlayView.scale = Vector2.ONE
	$TileYieldOverlayView.camera = _map_camera
	$TileYieldOverlayView.z_index = 1
	$TileYieldOverlayView.visible = false
	$CityWorkedTilesView.scale = Vector2.ONE
	$CityWorkedTilesView.camera = _map_camera
	$CityWorkedTilesView.z_index = 1
	$UnitNameplateView.scale = Vector2.ONE
	$UnitNameplateView.camera = _map_camera
	$UnitNameplateView.z_index = 2
	$CityNameplateView.scale = Vector2.ONE
	$CityNameplateView.camera = _map_camera
	$CityNameplateView.z_index = 2
	$CombatClashBurstView.scale = Vector2.ONE
	$CombatClashBurstView.camera = _map_camera
	$CombatClashBurstView.z_index = 3
	$SelectionController.scale = Vector2.ONE
	$SelectionController.camera = _map_camera
	_install_ui_chrome_once()
	var boot: Dictionary = BootIntentScript.consume_for_main()
	var boot_mode: String = str(boot.get("mode", ""))
	if boot_mode == BootIntentScript.MODE_LOCAL_HOTSEAT:
		_start_local_hotseat_session()
	elif boot_mode == BootIntentScript.MODE_CLOUD_CREATE or boot_mode == BootIntentScript.MODE_CLOUD_RECONNECT:
		use_cloud_server = true
		_boot_cloud_from_intent = true
		_boot_cloud_match_id = str(boot.get("match_id", ""))
		_boot_cloud_seat_token = str(boot.get("seat_token", ""))
		cloud_base_url = str(boot.get("server_url", cloud_base_url))
		cloud_match_id = _boot_cloud_match_id
		cloud_seat_token = _boot_cloud_seat_token
		cloud_scenario_id = str(boot.get("scenario_id", cloud_scenario_id))
		await _start_cloud_client_session()
	elif _should_use_cloud():
		await _start_cloud_client_session()
	else:
		_start_local_hotseat_session()


func _start_local_hotseat_session() -> void:
	var scenario_loc = ScenarioScript.make_prototype_play_scenario()
	var game_state_loc = GameStateScript.new(scenario_loc)
	var selection_loc = SelectionStateScript.new()
	var city_view_state_loc = CityViewStateScript.new()
	_wire_play_session(game_state_loc, selection_loc, city_view_state_loc)
	_apply_cloud_controller_flags(false)


func _start_cloud_client_session() -> void:
	# Hide map/HUD stack before **`post_create_match`** so view **`_ready`** hooks never show as gameplay.
	_set_cloud_gameplay_presentation_visible(false)
	await _bootstrap_cloud_session()


func _set_cloud_gameplay_presentation_visible(on: bool) -> void:
	var i: int = 0
	var nnames: Array = _cloud_gameplay_shell_node_names
	while i < nnames.size():
		var p := NodePath(str(nnames[i]))
		if has_node(p):
			get_node(p).visible = on
		i += 1


func _install_ui_chrome_once() -> void:
	var yields_toggle = $HudCanvas/YieldsToggle as CheckButton
	if yields_toggle != null and not yields_toggle.toggled.is_connected(_on_yields_toggle_toggled):
		yields_toggle.toggled.connect(_on_yields_toggle_toggled)
	if _faction_banner_gallery == null:
		_faction_banner_gallery = FactionBannerGalleryScript.new()
		add_child(_faction_banner_gallery)


func _should_use_cloud() -> bool:
	if use_cloud_server:
		return true
	var flg = OS.get_environment("EOM_CLOUD_CLIENT").strip_edges()
	return flg == "1" or flg.to_lower() == "true"


func _cloud_resolve_base_url_meta() -> Dictionary:
	var env_u: String = OS.get_environment("EOM_CLOUD_BASE_URL").strip_edges()
	if env_u.length() > 0:
		return {"url": env_u, "source": "EOM_CLOUD_BASE_URL"}
	return {"url": cloud_base_url, "source": "Main.cloud_base_url"}


func _cloud_resolve_base_url() -> String:
	return str(_cloud_resolve_base_url_meta()["url"])


func _cloud_resolve_match_id_meta() -> Dictionary:
	var env_m: String = OS.get_environment("EOM_CLOUD_MATCH_ID").strip_edges()
	if env_m.length() > 0:
		return {"value": env_m, "source": "EOM_CLOUD_MATCH_ID"}
	if _boot_cloud_from_intent:
		var bmid: String = _boot_cloud_match_id.strip_edges()
		if bmid.length() > 0:
			return {"value": bmid, "source": "BootIntent"}
	return {"value": cloud_match_id.strip_edges(), "source": "Main.cloud_match_id"}


func _cloud_resolve_match_id() -> String:
	return str(_cloud_resolve_match_id_meta()["value"])


func _cloud_resolve_seat_token_meta() -> Dictionary:
	var boot_tok: String = _boot_cloud_seat_token if _boot_cloud_from_intent else ""
	return CloudCredentialStoreScript.resolve_seat_token_for_boot(
		_cloud_resolve_base_url(),
		_cloud_resolve_match_id(),
		OS.get_environment("EOM_CLOUD_SEAT_TOKEN"),
		cloud_seat_token,
		CloudCredentialStoreScript.DEFAULT_PATH,
		boot_tok,
	)


func _cloud_resolve_seat_token() -> String:
	return str(_cloud_resolve_seat_token_meta()["value"])


func _cloud_persist_credential_after_bootstrap(resp: Dictionary, reconnecting: bool) -> void:
	if _cloud_session == null:
		return
	var tok: String = _cloud_session.seat_token.strip_edges()
	if tok.is_empty():
		return
	var is_host: bool = not reconnecting
	if reconnecting:
		var existing: Dictionary = CloudCredentialStoreScript.find(
			CloudCredentialStoreScript.DEFAULT_PATH,
			_cloud_resolve_base_url(),
			_cloud_session.match_id,
		)
		if not existing.is_empty():
			is_host = bool(existing.get("is_host", false))
		else:
			is_host = tok.begins_with("ht_")
	CloudCredentialStoreScript.persist_after_bootstrap(
		CloudCredentialStoreScript.DEFAULT_PATH,
		_cloud_resolve_base_url(),
		_cloud_session.match_id,
		tok,
		is_host,
		resp,
	)


func _cloud_touch_credential_revision(revision: int) -> void:
	if not _cloud_mode or _cloud_session == null:
		return
	CloudCredentialStoreScript.touch_revision(
		CloudCredentialStoreScript.DEFAULT_PATH,
		_cloud_resolve_base_url(),
		_cloud_session.match_id,
		_cloud_session.seat_token,
		revision,
	)


func _cloud_debug_enabled() -> bool:
	return OS.get_environment("EOM_CLOUD_DEBUG").strip_edges() == "1"


func cloud_session_blocks_map_input() -> bool:
	return _cloud_loading or _cloud_boot_stranded or _cloud_combat_anim_busy


func _cloud_debug_timing(tag: String) -> void:
	if not _cloud_debug_enabled():
		return
	print("SliceC8TIME %s t=%d" % [tag, Time.get_ticks_msec()])


func _ensure_cloud_loading_overlay() -> void:
	if _cloud_loading_overlay_root != null:
		return
	var layer = CanvasLayer.new()
	layer.name = "CloudLoadingOverlay"
	layer.layer = 100
	var root = Control.new()
	root.name = "CloudLoadingRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim = ColorRect.new()
	dim.name = "CloudLoadingDim"
	dim.color = Color(0, 0, 0, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(center)
	var lbl = Label.new()
	lbl.name = "CloudLoadingLabel"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size = Vector2(640.0, 0.0)
	lbl.add_theme_font_size_override("font_size", 22)
	center.add_child(lbl)
	layer.add_child(root)
	add_child(layer)
	_cloud_loading_overlay_root = layer
	_cloud_loading_label = lbl


func _set_cloud_overlay_visible(show_o: bool) -> void:
	_ensure_cloud_loading_overlay()
	_cloud_loading_overlay_root.visible = show_o


func _set_cloud_overlay_text(text: String) -> void:
	_ensure_cloud_loading_overlay()
	if _cloud_loading_label != null:
		_cloud_loading_label.text = text


func _cloud_fail_session_and_strand(msg: String, resp: Dictionary = {}) -> void:
	if _cloud_debug_enabled():
		var meta := _cloud_resolve_base_url_meta()
		print(
			(
				"SliceC8TIME cloud_boot_failed t=%d effective_url=%s url_source=%s cloud_scenario_id=%s resp=%s"
				% [Time.get_ticks_msec(), meta["url"], meta["source"], cloud_scenario_id, resp]
			)
		)
	push_warning("Slice C8 cloud: %s (%s)" % [msg, resp])
	if _cloud_session != null:
		_cloud_session.queue_free()
		_cloud_session = null
	_cloud_mode = false
	_cloud_loading = false
	_cloud_boot_stranded = true
	$SelectionController.use_cloud_server = false
	$SelectionController.cloud_play_host = null
	$HudCanvas/CityProductionPanel.use_cloud_server = false
	$HudCanvas/CityProductionPanel.cloud_play_host = null
	$AITurnController.skip_for_cloud = false
	var yields_t = $HudCanvas/YieldsToggle as CheckButton
	if yields_t != null:
		yields_t.focus_mode = Control.FOCUS_ALL
	_set_cloud_overlay_visible(true)
	_set_cloud_overlay_text(msg)
	_set_cloud_gameplay_presentation_visible(false)


func _bootstrap_cloud_session() -> void:
	_cloud_boot_stranded = false
	_cloud_loading = true
	_cloud_debug_timing("cloud_init_start")
	_ensure_cloud_loading_overlay()
	_set_cloud_overlay_visible(true)
	_set_cloud_overlay_text("Connecting to cloud match…")
	$SelectionController.use_cloud_server = true
	$SelectionController.cloud_play_host = self
	$AITurnController.skip_for_cloud = true
	var yields_boot = $HudCanvas/YieldsToggle as CheckButton
	if yields_boot != null:
		yields_boot.focus_mode = Control.FOCUS_NONE
	_cloud_session = CloudSessionScript.new()
	_cloud_session.base_url = _cloud_resolve_base_url()
	var seat_meta: Dictionary = _cloud_resolve_seat_token_meta()
	_cloud_session.seat_token = str(seat_meta.get("value", ""))
	add_child(_cloud_session)
	if _cloud_debug_enabled():
		var umeta := _cloud_resolve_base_url_meta()
		var mmeta := _cloud_resolve_match_id_meta()
		print(
			(
				"SliceC8DBG cloud_bootstrap effective_url=%s url_source=%s cloud_scenario_id=%s match_id=%s match_id_source=%s seat_token_source=%s use_cloud_server_export=%s"
				% [
					umeta["url"],
					umeta["source"],
					cloud_scenario_id,
					mmeta["value"],
					mmeta["source"],
					seat_meta.get("source", ""),
					use_cloud_server,
				]
			)
		)
	var reconnect_mid: String = _cloud_resolve_match_id()
	var reconnecting: bool = not CloudClientScript.should_create_match(reconnect_mid)
	var resp: Dictionary = {}
	if reconnecting:
		_cloud_session.match_id = reconnect_mid
		_set_cloud_overlay_text("Reconnecting to cloud match…")
		resp = await _cloud_session.get_match()
		if resp.has("_error") or typeof(resp.get("snapshot")) != TYPE_DICTIONARY:
			_cloud_fail_session_and_strand(
				"Could not reconnect to cloud match %s. Check the match id and server." % reconnect_mid,
				resp,
			)
			return
	else:
		resp = await _cloud_session.post_create_match(cloud_scenario_id)
		if resp.has("_error") or str(resp.get("match_id", "")) == "":
			_cloud_fail_session_and_strand("Could not start a cloud match. Check the server and try again.", resp)
			return
		_cloud_session.match_id = str(resp["match_id"])
		var host_tok: String = CloudClientScript.host_token_from_create_response(resp)
		if host_tok.length() > 0 and _cloud_session.seat_token.strip_edges().is_empty():
			_cloud_session.seat_token = host_tok
	var snap = resp.get("snapshot")
	if typeof(snap) != TYPE_DICTIONARY:
		var fail_msg: String = (
			"Cloud match reconnected but the server response was missing a snapshot."
			if reconnecting
			else "Cloud match started but the server response was missing a snapshot."
		)
		_cloud_fail_session_and_strand(fail_msg, resp)
		return
	_set_cloud_overlay_text("Loading cloud match…")
	_cloud_debug_timing("snapshot_adapter_start")
	var gs_cloud = ServerSnapshotAdapterScript.build_game_state_from_api_snapshot(snap)
	_cloud_debug_timing("snapshot_adapter_done")
	if gs_cloud == null:
		_cloud_fail_session_and_strand("Could not load match data from the server.", resp)
		return
	_cloud_mode = true
	var selection_cloud = SelectionStateScript.new()
	var city_vs_cloud = CityViewStateScript.new()
	_cloud_debug_timing("presentation_rebind_start")
	_wire_play_session(gs_cloud, selection_cloud, city_vs_cloud)
	_cloud_debug_timing("presentation_rebind_done")
	_apply_cloud_controller_flags(true)
	_refresh_presentation_after_cloud_snap()
	_set_cloud_gameplay_presentation_visible(true)
	_cloud_loading = false
	_set_cloud_overlay_visible(false)
	var banner_ctx: String = "cloud_reconnect" if reconnecting else "cloud_bootstrap"
	_cloud_maybe_show_turn_start_banner(gs_cloud, null, banner_ctx)
	_cloud_debug_timing("first_cloud_snapshot_ready")
	if reconnecting:
		print(
			"Slice C9 cloud: reconnected match_id=",
			_cloud_session.match_id,
			" revision=",
			snap.get("revision", "?"),
		)
	else:
		if _cloud_debug_enabled():
			var ht_dbg: String = _cloud_session.seat_token.strip_edges()
			print(
				(
					"Slice C13 cloud: created match_id=%s EOM_CLOUD_MATCH_ID=%s EOM_CLOUD_SEAT_TOKEN=%s revision=%s"
					% [_cloud_session.match_id, _cloud_session.match_id, ht_dbg, snap.get("revision", "?")]
				)
			)
		else:
			print(
				(
					"Slice C14 cloud: created match_id=%s (credentials saved; set EOM_CLOUD_MATCH_ID to reconnect) revision=%s"
					% [_cloud_session.match_id, snap.get("revision", "?")]
				)
			)
	_cloud_persist_credential_after_bootstrap(resp, reconnecting)
	_cloud_touch_credential_revision(CloudCredentialStoreScript.revision_from_response(resp))
	call_deferred("cloud_refresh_legal_async_entry")


func _apply_cloud_controller_flags(on: bool) -> void:
	$SelectionController.use_cloud_server = on
	$SelectionController.cloud_play_host = self if on else null
	var yields_t = $HudCanvas/YieldsToggle as CheckButton
	if yields_t != null:
		yields_t.focus_mode = Control.FOCUS_NONE if on else Control.FOCUS_ALL
	$HudCanvas/CityProductionPanel.use_cloud_server = on
	$HudCanvas/CityProductionPanel.cloud_play_host = self if on else null
	$AITurnController.skip_for_cloud = on


func _wire_play_session(game_state, selection, city_view_state) -> void:
	var scenario = game_state.scenario
	_play_game_state = game_state
	_play_selection = selection
	var layout = HexLayoutScript.new()
	_session_layout = layout
	var map_view = $MapView
	var map_visibility_view = $MapVisibilityView
	map_visibility_view.layout = layout
	map_visibility_view.game_state = game_state
	map_visibility_view.parchment_world_scale = map_view.terrain_texture_world_scale * 1.5
	map_view.map = scenario.map
	map_view.layout = layout
	var terrain_edge_blend = $TerrainEdgeBlendView
	terrain_edge_blend.map = scenario.map
	terrain_edge_blend.layout = layout
	terrain_edge_blend.camera = _map_camera
	var cities_view = $CitiesView
	cities_view.scenario = scenario
	cities_view.layout = layout
	var lightning_tree_view = $LightningTreeView
	lightning_tree_view.game_state = game_state
	lightning_tree_view.scenario = scenario
	lightning_tree_view.layout = layout
	lightning_tree_view.camera = _map_camera
	var empire_border_view = $EmpireBorderView
	empire_border_view.scenario = scenario
	empire_border_view.layout = layout
	empire_border_view.camera = _map_camera
	var city_territory_view = $CityTerritoryView
	city_territory_view.scenario = scenario
	city_territory_view.layout = layout
	city_territory_view.camera = _map_camera
	city_territory_view.selection = selection
	var city_worked_tiles_view = $CityWorkedTilesView
	city_worked_tiles_view.scenario = scenario
	city_worked_tiles_view.layout = layout
	city_worked_tiles_view.camera = _map_camera
	city_worked_tiles_view.selection = selection
	city_worked_tiles_view.city_view_state = city_view_state
	var tile_yield_overlay = $TileYieldOverlayView
	tile_yield_overlay.scenario = scenario
	tile_yield_overlay.layout = layout
	tile_yield_overlay.camera = _map_camera
	tile_yield_overlay.game_state = game_state
	var units_view = $UnitsView
	units_view.scenario = scenario
	units_view.layout = layout
	units_view.selection = selection
	var terrain_foreground = $TerrainForegroundView
	map_view.terrain_foreground_view = terrain_foreground
	terrain_foreground.map = scenario.map
	terrain_foreground.layout = layout
	terrain_foreground.scenario = scenario
	terrain_foreground.game_state = game_state
	terrain_foreground.forest_density_ratio = map_view.forest_density_ratio
	terrain_foreground.foreground_unit_reference_height_ratio = units_view.unit_icon_height_ratio
	# Prototype play map only: deterministic forest clusters for visual review (not gameplay / not biome rules).
	var proto_forest_override: Dictionary = PlainsForestScript.prototype_forest_cluster_set()
	map_view.forest_decoration_override = proto_forest_override
	terrain_foreground.forest_decoration_override = proto_forest_override
	# Phase **4.6p:** cross-wire **before** any **`queue_redraw`** so **`UnitsView._draw`** / **`CitiesView._draw`**
	# skip own-canvas markers when **`TerrainForegroundView`** hosts forest + marker order.
	terrain_foreground.units_view = units_view
	terrain_foreground.map_view = map_view
	terrain_foreground.cities_view = cities_view
	cities_view.terrain_foreground_view = terrain_foreground
	units_view.terrain_foreground_view = terrain_foreground
	var unit_nameplate_view = $UnitNameplateView
	unit_nameplate_view.scenario = scenario
	var combat_clash_burst = $CombatClashBurstView
	combat_clash_burst.layout = layout
	combat_clash_burst.camera = _map_camera
	unit_nameplate_view.layout = layout
	unit_nameplate_view.units_view = units_view
	unit_nameplate_view.game_state = game_state
	var city_nameplate_view = $CityNameplateView
	city_nameplate_view.scenario = scenario
	city_nameplate_view.layout = layout
	city_nameplate_view.cities_view = cities_view
	city_nameplate_view.terrain_foreground_view = terrain_foreground
	city_nameplate_view.game_state = game_state
	var selection_view = $SelectionView
	selection_view.scenario = scenario
	selection_view.layout = layout
	selection_view.selection = selection
	var selection_controller = $SelectionController
	selection_controller.scenario = scenario
	selection_controller.game_state = game_state
	selection_controller.layout = layout
	selection_controller.selection = selection
	selection_controller.selection_view = selection_view
	selection_controller.units_view = units_view
	selection_controller.cities_view = cities_view
	selection_controller.terrain_foreground_view = terrain_foreground
	selection_controller.unit_nameplate_view = unit_nameplate_view
	selection_controller.city_nameplate_view = city_nameplate_view
	selection_controller.city_territory_view = city_territory_view
	selection_controller.empire_border_view = empire_border_view
	selection_controller.city_worked_tiles_view = city_worked_tiles_view
	selection_controller.city_view_state = city_view_state
	selection_controller.combat_clash_burst_view = combat_clash_burst
	selection_controller.yield_overlay_view = tile_yield_overlay
	selection_controller.terrain_edge_blend_view = terrain_edge_blend
	selection_controller.map_visibility_view = map_visibility_view
	selection_controller.lightning_tree_view = lightning_tree_view
	var turn_label = $TurnLabel
	turn_label.game_state = game_state
	var turn_status_panel = $HudCanvas/TurnStatusPanel
	var player_contact_strip = $HudCanvas/PlayerContactStrip
	turn_status_panel.game_state = game_state
	player_contact_strip.game_state = game_state
	turn_status_panel.local_player_id = 0
	turn_label.after_refresh = Callable(self, "_refresh_turn_hud_after_turn_label")
	turn_label.refresh()
	selection_controller.turn_label = turn_label
	var end_turn_controller = $EndTurnController
	end_turn_controller.game_state = game_state
	end_turn_controller.selection = selection
	end_turn_controller.selection_view = selection_view
	end_turn_controller.units_view = units_view
	end_turn_controller.terrain_foreground_view = terrain_foreground
	end_turn_controller.unit_nameplate_view = unit_nameplate_view
	end_turn_controller.turn_label = turn_label
	var ai_turn_controller = $AITurnController
	ai_turn_controller.game_state = game_state
	ai_turn_controller.selection = selection
	ai_turn_controller.selection_view = selection_view
	ai_turn_controller.units_view = units_view
	ai_turn_controller.terrain_foreground_view = terrain_foreground
	ai_turn_controller.unit_nameplate_view = unit_nameplate_view
	ai_turn_controller.city_nameplate_view = city_nameplate_view
	ai_turn_controller.turn_label = turn_label
	var log_view = $LogView
	log_view.game_state = game_state
	log_view.refresh()
	selection_controller.log_view = log_view
	end_turn_controller.log_view = log_view
	ai_turn_controller.log_view = log_view
	var city_production_panel = $HudCanvas/CityProductionPanel
	city_production_panel.game_state = game_state
	city_production_panel.selection = selection
	city_production_panel.selection_view = selection_view
	city_production_panel.city_territory_view = city_territory_view
	city_production_panel.city_worked_tiles_view = city_worked_tiles_view
	city_production_panel.city_view_state = city_view_state
	city_production_panel.cities_view = cities_view
	city_production_panel.turn_label = turn_label
	city_production_panel.log_view = log_view
	city_production_panel.city_nameplate_view = city_nameplate_view
	selection_controller.city_production_panel = city_production_panel
	end_turn_controller.city_production_panel = city_production_panel
	ai_turn_controller.city_production_panel = city_production_panel
	end_turn_controller.yield_overlay_view = tile_yield_overlay
	end_turn_controller.city_territory_view = city_territory_view
	end_turn_controller.empire_border_view = empire_border_view
	end_turn_controller.city_worked_tiles_view = city_worked_tiles_view
	end_turn_controller.terrain_edge_blend_view = terrain_edge_blend
	end_turn_controller.map_visibility_view = map_visibility_view
	end_turn_controller.lightning_tree_view = lightning_tree_view
	end_turn_controller.turn_start_banner = $TurnStartBanner
	ai_turn_controller.yield_overlay_view = tile_yield_overlay
	ai_turn_controller.city_territory_view = city_territory_view
	ai_turn_controller.empire_border_view = empire_border_view
	ai_turn_controller.city_worked_tiles_view = city_worked_tiles_view
	ai_turn_controller.terrain_edge_blend_view = terrain_edge_blend
	ai_turn_controller.map_visibility_view = map_visibility_view
	ai_turn_controller.lightning_tree_view = lightning_tree_view
	ai_turn_controller.turn_start_banner = $TurnStartBanner
	city_production_panel.refresh()
	var discovery_action_panel = $HudCanvas/DiscoveryActionPanel
	discovery_action_panel.game_state = game_state
	discovery_action_panel.turn_label = turn_label
	discovery_action_panel.log_view = log_view
	discovery_action_panel.city_production_panel = city_production_panel
	var science_panel = $HudCanvas/SciencePanel
	science_panel.game_state = game_state
	science_panel.turn_label = turn_label
	science_panel.log_view = log_view
	discovery_action_panel.science_panel = science_panel
	selection_controller.science_panel = science_panel
	end_turn_controller.science_panel = science_panel
	ai_turn_controller.science_panel = science_panel
	var discovery_popup = $HudCanvas/DiscoveryPopup
	discovery_popup.game_state = game_state
	discovery_action_panel.discovery_popup = discovery_popup
	var science_completed_popup = $HudCanvas/ScienceCompletedPopup
	science_completed_popup.game_state = game_state
	selection_controller.discovery_action_panel = discovery_action_panel
	end_turn_controller.discovery_action_panel = discovery_action_panel
	ai_turn_controller.discovery_action_panel = discovery_action_panel
	discovery_action_panel.refresh()
	science_panel.refresh()
	selection_controller.discovery_popup = discovery_popup
	selection_controller.science_completed_popup = science_completed_popup
	end_turn_controller.discovery_popup = discovery_popup
	end_turn_controller.science_completed_popup = science_completed_popup
	ai_turn_controller.discovery_popup = discovery_popup
	ai_turn_controller.science_completed_popup = science_completed_popup
	var turn_start_banner = $TurnStartBanner
	turn_start_banner.set_game_state(game_state)
	if not _cloud_mode:
		turn_start_banner.show_for_current_player(game_state)
	_redraw_map_layers()


func cloud_legal_actions_pending() -> bool:
	return _cloud_legal_busy


func cloud_input_diag_log(tag: String, extra: Dictionary = {}) -> void:
	if OS.get_environment("EOM_CLOUD_DEBUG").strip_edges() != "1":
		return
	print("SliceC8DBG %s %s" % [tag, extra])


func cloud_pick_found_city_action() -> Dictionary:
	for a in _cloud_last_legal_actions:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var d = a as Dictionary
		if str(d.get("action_type", "")) == "found_city":
			return d.duplicate(true)
	return {}


func cloud_refresh_legal_async_entry() -> void:
	if not _cloud_mode or _cloud_session == null or _play_game_state == null:
		return
	if _cloud_legal_busy:
		_cloud_legal_stale = true
		return
	_cloud_legal_busy = true
	while true:
		_cloud_legal_stale = false
		await _cloud_fetch_and_apply_legal()
		if not _cloud_legal_stale:
			break
	_cloud_legal_busy = false


func _cloud_fetch_and_apply_legal() -> void:
	var actor = _play_game_state.turn_state.current_player_id()
	var su = -1
	var sc = -1
	if _play_selection.has_city():
		sc = _play_selection.city_id
	elif not _play_selection.is_empty():
		su = _play_selection.unit_id
	cloud_input_diag_log("legal_actions_request", {"actor_id": actor, "selected_unit_id": su, "selected_city_id": sc})
	var la = await _cloud_session.get_legal_actions(actor, su, sc)
	if la.has("_error"):
		push_warning("Slice C8 legal-actions failed: %s" % la)
		return
	_cloud_last_legal_actions = la.get("actions", []) as Array
	var fi = 0
	while fi < _cloud_last_legal_actions.size():
		var fr = _cloud_last_legal_actions[fi]
		fi += 1
		if typeof(fr) != TYPE_DICTIONARY:
			continue
		if str((fr as Dictionary).get("action_type", "")) != "move_unit":
			continue
		cloud_input_diag_log("legal_actions_first_move_unit", {"action_json": JSON.stringify(fr)})
		break
	var dests: Array = []
	var move_map: Dictionary = {}
	var move_n = 0
	var ai = 0
	while ai < _cloud_last_legal_actions.size():
		var row = _cloud_last_legal_actions[ai]
		ai += 1
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var ad = row as Dictionary
		if str(ad.get("action_type", "")) != "move_unit":
			continue
		var to_raw = ad.get("to")
		if typeof(to_raw) != TYPE_ARRAY:
			continue
		var ta = to_raw as Array
		if ta.size() < 2:
			continue
		var hc = HexCoordScript.new(int(ta[0]), int(ta[1]))
		dests.append(hc)
		move_map[CloudClientScript.hex_action_key(int(hc.q), int(hc.r))] = ad.duplicate(true)
		move_n += 1
	cloud_input_diag_log(
		"legal_actions_result",
		{"move_unit_count": move_n, "hex_keys": move_map.keys(), "action_count": _cloud_last_legal_actions.size()}
	)
	var sv = $SelectionView
	sv.cloud_destination_coords = dests
	sv.cloud_attack_target_coords = []
	sv.queue_redraw()
	var selc = $SelectionController
	selc.cloud_move_action_by_hex = move_map
	selc.cloud_attack_action_by_hex = {}
	var attack_pack: Dictionary = CloudClientScript.build_attack_maps_from_legal_actions(
		_cloud_last_legal_actions,
		_play_game_state.scenario if _play_game_state != null else null,
	)
	sv.cloud_attack_target_coords = attack_pack["attack_targets"] as Array
	selc.cloud_attack_action_by_hex = attack_pack["attack_map"] as Dictionary
	sv.queue_redraw()
	var prod_opts: Array = []
	var pi = 0
	while pi < _cloud_last_legal_actions.size():
		var row2 = _cloud_last_legal_actions[pi]
		pi += 1
		if typeof(row2) != TYPE_DICTIONARY:
			continue
		var bd = row2 as Dictionary
		if str(bd.get("action_type", "")) != "set_city_production":
			continue
		var pid = str(bd.get("project_id", ""))
		prod_opts.append(
			{
				"city_id": int(bd.get("city_id", -1)),
				"label": "Train %s" % CityProductionPanelScript._human_project_suffix(pid),
				"action": bd.duplicate(true),
			}
		)
	var cpp = $HudCanvas/CityProductionPanel
	cpp.cloud_production_options = prod_opts
	cpp.refresh()
	_redraw_map_layers()


func cloud_post_end_turn_async_entry() -> void:
	if cloud_session_blocks_map_input() or not _cloud_mode or _play_game_state == null:
		return
	var pid = _play_game_state.turn_state.current_player_id()
	await cloud_post_action_async_entry(EndTurnScript.make(pid))


func cloud_post_action_async_entry(action: Dictionary) -> void:
	if _cloud_loading or _cloud_boot_stranded or _cloud_combat_anim_busy:
		return
	if not _cloud_mode or _cloud_session == null:
		return
	var r = await _cloud_session.post_action(action)
	await _handle_cloud_post_response(r, action)


func _handle_cloud_post_response(r: Dictionary, action: Dictionary) -> void:
	if not CloudClientScript.should_apply_snapshot(r):
		if r.has("_error"):
			push_warning("Slice C8 POST transport: %s" % r)
			cloud_input_diag_log("post_action", {"accepted": false, "transport": r})
		elif not bool(r.get("accepted", false)):
			push_warning("Slice C8 POST rejected: %s" % str(r.get("reason", "")))
			cloud_input_diag_log(
				"post_action",
				{"accepted": false, "reason": str(r.get("reason", "")), "action_type": str(action.get("action_type", ""))}
			)
		return
	cloud_input_diag_log(
		"post_action",
		{
			"accepted": true,
			"reason": str(r.get("reason", "")),
			"revision": r.get("revision", "?"),
			"action_type": str(action.get("action_type", "")),
		}
	)
	var anim_req: Dictionary = CloudClientScript.combat_animation_request_from_response(r, action)
	if bool(anim_req.get("should_animate", false)):
		await _play_cloud_combat_then_apply(r, action, anim_req)
	else:
		_apply_cloud_post_snapshot(r, action)


func _play_cloud_combat_then_apply(r: Dictionary, action: Dictionary, anim_req: Dictionary) -> void:
	_cloud_combat_anim_busy = true
	var burst = $CombatClashBurstView
	if burst != null:
		burst.show_burst_hex_centers(
			int(anim_req.get("attacker_q", 0)),
			int(anim_req.get("attacker_r", 0)),
			int(anim_req.get("defender_q", 0)),
			int(anim_req.get("defender_r", 0)),
		)
	await get_tree().create_timer(CLOUD_COMBAT_ANIM_SEC).timeout
	_cloud_combat_anim_busy = false
	_apply_cloud_post_snapshot(r, action)


func _apply_cloud_post_snapshot(r: Dictionary, action: Dictionary) -> void:
	var snap = r["snapshot"] as Dictionary
	var gs_new = ServerSnapshotAdapterScript.build_game_state_from_api_snapshot(snap)
	if gs_new == null:
		push_error("Slice C8: snapshot adapter failed on POST body")
		return
	var prev_pid = null
	if _play_game_state != null and _play_game_state.turn_state != null:
		prev_pid = _play_game_state.turn_state.current_player_id()
	_rebind_session_to_game_state(gs_new)
	_adjust_selection_after_cloud_action(action, gs_new)
	_refresh_presentation_after_cloud_snap()
	_cloud_maybe_show_turn_start_banner(gs_new, prev_pid, str(action.get("action_type", "")))
	_cloud_touch_credential_revision(CloudCredentialStoreScript.revision_from_response(r))
	call_deferred("cloud_refresh_legal_async_entry")


func _rebind_session_to_game_state(gs) -> void:
	var scenario = gs.scenario
	_play_game_state = gs
	var layout = _session_layout
	var map_view = $MapView
	map_view.map = scenario.map
	var terrain_edge_blend = $TerrainEdgeBlendView
	terrain_edge_blend.map = scenario.map
	var cities_view = $CitiesView
	cities_view.scenario = scenario
	var lightning_tree_view = $LightningTreeView
	lightning_tree_view.game_state = gs
	lightning_tree_view.scenario = scenario
	var empire_border_view = $EmpireBorderView
	empire_border_view.scenario = scenario
	var city_territory_view = $CityTerritoryView
	city_territory_view.scenario = scenario
	var city_worked_tiles_view = $CityWorkedTilesView
	city_worked_tiles_view.scenario = scenario
	var tile_yield_overlay = $TileYieldOverlayView
	tile_yield_overlay.scenario = scenario
	tile_yield_overlay.game_state = gs
	var units_view = $UnitsView
	units_view.scenario = scenario
	var terrain_foreground = $TerrainForegroundView
	terrain_foreground.map = scenario.map
	terrain_foreground.scenario = scenario
	terrain_foreground.game_state = gs
	var unit_nameplate_view = $UnitNameplateView
	unit_nameplate_view.scenario = scenario
	unit_nameplate_view.game_state = gs
	var city_nameplate_view = $CityNameplateView
	city_nameplate_view.scenario = scenario
	city_nameplate_view.game_state = gs
	var selection_view = $SelectionView
	selection_view.scenario = scenario
	var selection_controller = $SelectionController
	selection_controller.scenario = scenario
	selection_controller.game_state = gs
	var turn_label = $TurnLabel
	turn_label.game_state = gs
	$HudCanvas/TurnStatusPanel.game_state = gs
	$HudCanvas/PlayerContactStrip.game_state = gs
	var log_view = $LogView
	log_view.game_state = gs
	var city_production_panel = $HudCanvas/CityProductionPanel
	city_production_panel.game_state = gs
	var discovery_action_panel = $HudCanvas/DiscoveryActionPanel
	discovery_action_panel.game_state = gs
	var science_panel = $HudCanvas/SciencePanel
	science_panel.game_state = gs
	var discovery_popup = $HudCanvas/DiscoveryPopup
	discovery_popup.game_state = gs
	var science_completed_popup = $HudCanvas/ScienceCompletedPopup
	science_completed_popup.game_state = gs
	$EndTurnController.game_state = gs
	$AITurnController.game_state = gs
	$TurnStartBanner.set_game_state(gs)
	var map_visibility_view = $MapVisibilityView
	map_visibility_view.game_state = gs
	var combat_clash_burst = $CombatClashBurstView
	combat_clash_burst.layout = layout
	if layout != null:
		map_view.layout = layout
		map_visibility_view.layout = layout
		terrain_edge_blend.layout = layout
		cities_view.layout = layout
		lightning_tree_view.layout = layout
		empire_border_view.layout = layout
		city_territory_view.layout = layout
		city_worked_tiles_view.layout = layout
		tile_yield_overlay.layout = layout
		units_view.layout = layout
		terrain_foreground.layout = layout
		unit_nameplate_view.layout = layout
		city_nameplate_view.layout = layout
		selection_view.layout = layout
		selection_controller.layout = layout


func _adjust_selection_after_cloud_action(action: Dictionary, gs) -> void:
	var at = str(action.get("action_type", ""))
	if at == EndTurnScript.ACTION_TYPE:
		EndTurnController.apply_hotseat_clear_after_accepted_end_turn(
			_play_selection,
			$HudCanvas/CityProductionPanel
		)
	elif at == "found_city":
		_play_selection.clear()
	elif at == "move_unit":
		var uid = int(action.get("unit_id", -1))
		SelectionController.apply_post_accepted_move_unit_selection(_play_selection, gs.scenario, uid)
	elif at == "attack_unit":
		_play_selection.clear()


func _refresh_presentation_after_cloud_snap() -> void:
	var gs = _play_game_state
	TurnViewSyncScript.refresh_map_views_and_hud_after_try_apply_turn_controllers(
		gs,
		$SelectionView,
		$UnitsView,
		$TerrainForegroundView,
		$UnitNameplateView,
		$CityNameplateView,
		$TileYieldOverlayView,
		$CityTerritoryView,
		$TurnLabel,
		$LogView,
		$HudCanvas/CityProductionPanel,
		$HudCanvas/DiscoveryActionPanel,
		$HudCanvas/SciencePanel,
		$CityWorkedTilesView,
		$EmpireBorderView,
		$TerrainEdgeBlendView,
		$MapVisibilityView,
		$LightningTreeView,
	)
	$HudCanvas/DiscoveryActionPanel.refresh()
	$HudCanvas/SciencePanel.refresh()
	$TurnStartBanner.set_game_state(gs)
	_redraw_map_layers()


func _cloud_maybe_show_turn_start_banner(gs, previous_player_id, action_type: String = "") -> void:
	if not _cloud_mode or gs == null or gs.turn_state == null:
		return
	var new_pid: int = int(gs.turn_state.current_player_id())
	var show_banner: bool = CloudClientScript.should_show_turn_start_banner(previous_player_id, new_pid)
	if _cloud_debug_enabled():
		cloud_input_diag_log(
			"turn_banner_decision",
			{
				"previous_current_player_id": previous_player_id,
				"new_current_player_id": new_pid,
				"action_type": action_type,
				"show_turn_banner": show_banner,
			}
		)
	_cloud_last_seen_current_player_id = new_pid
	var turn_start_banner = $TurnStartBanner
	turn_start_banner.set_game_state(gs)
	if show_banner:
		turn_start_banner.show_for_current_player(gs)


func _input(event: InputEvent) -> void:
	if cloud_session_blocks_map_input():
		if event is InputEventKey:
			var skip := event as InputEventKey
			if skip.pressed and not skip.echo and (skip.keycode == KEY_ESCAPE or skip.keycode == KEY_F1):
				return
		get_viewport().set_input_as_handled()
		return
	var turn_start_banner = $TurnStartBanner
	if turn_start_banner != null:
		turn_start_banner.on_user_interaction(event)
	# Slice C8: **Space** must reach **`cloud_post_end_turn`** before focused HUD controls (e.g. **Yields** **CheckButton** ui_accept). **FOCUS_NONE** on yields when cloud also helps.
	if CloudClientScript.is_cloud_space_end_turn_shortcut(_cloud_mode, event):
		call_deferred("cloud_post_end_turn_async_entry")
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return
		var factor: float = 0.0
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			factor = ZOOM_STEP
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			factor = 1.0 / ZOOM_STEP
		else:
			return
		var center_local: Vector2 = get_viewport_rect().size * 0.5 - MAP_LAYER_ORIGIN
		var old_zoom: float = _map_camera.zoom
		var world_before: Vector2 = _map_camera.to_layout(center_local)
		_map_camera.set_zoom_clamped(_map_camera.zoom * factor)
		if is_equal_approx(_map_camera.zoom, old_zoom):
			get_viewport().set_input_as_handled()
			return
		var world_after: Vector2 = _map_camera.to_layout(center_local)
		if world_before.is_finite() and world_after.is_finite():
			_map_camera.camera_world_offset += world_before - world_after
		_redraw_map_layers()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if mm.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			var map_v: Node2D = $MapView
			var prev_local: Vector2 = map_v.to_local(mm.global_position - mm.relative)
			var cur_local: Vector2 = map_v.to_local(mm.global_position)
			var prev_world: Vector2 = _map_camera.to_layout(prev_local)
			var cur_world: Vector2 = _map_camera.to_layout(cur_local)
			if not (prev_world.is_finite() and cur_world.is_finite()):
				return
			_map_camera.camera_world_offset += prev_world - cur_world
			_redraw_map_layers()
			get_viewport().set_input_as_handled()


func _on_yields_toggle_toggled(pressed: bool) -> void:
	YieldOverlayToggleScript.apply_from_button($TileYieldOverlayView, pressed)


func _unhandled_input(event: InputEvent) -> void:
	if cloud_session_blocks_map_input():
		if event is InputEventKey:
			var ekb := event as InputEventKey
			if ekb.pressed and not ekb.echo and ekb.keycode == KEY_F1:
				if _faction_banner_gallery != null:
					_faction_banner_gallery.toggle_visible()
				return
		return
	if event is InputEventKey:
		var ek := event as InputEventKey
		if ek.pressed and not ek.echo and ek.keycode == KEY_Y:
			YieldOverlayToggleScript.toggle_from_keyboard(
				$TileYieldOverlayView, $HudCanvas/YieldsToggle as CheckButton
			)
			return
		if ek.pressed and not ek.echo and ek.keycode == KEY_F1:
			if _faction_banner_gallery != null:
				_faction_banner_gallery.toggle_visible()
				return
