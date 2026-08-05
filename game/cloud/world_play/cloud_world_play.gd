# N6/N7c production scene for server-fed world_map matches (cloud play route).
#
# This is the dedicated gameplay entry for snapshot-v3 matches: the cloud
# front door / staging routes here via BootIntent.play_scene_for_match_kind
# ("world_map"); legacy matches keep res://main.tscn untouched. The flow is:
#   1. consume BootIntent (create / enter-created / reconnect);
#   2. fetch the authoritative snapshot v3 from the server (one persistent
#      CloudSession, kept for the N7d action/polling loop);
#   3. WorldSnapshotBootstrap: parse the envelope, load the canonical map
#      content by map_id through the derived-package manifest, and verify the
#      schema version + raw-byte content hash against the server identity;
#   4. build the shared TerrainWorld (N3c.6), attach the N4 projected
#      screen-space anchor UI, and render the snapshot's units as the
#      existing 3D characters at the tile anchors (N7c, WorldUnitsView).
# Any missing content or identity mismatch fails VISIBLY (on-screen error +
# push_error) with no fallback map — a silent substitute would desync the
# authoritative WorldMap. Unit legality stays server-only (N7a/N7b);
# selection, destination markers, action submission, movement/facing
# presentation, End Turn, polling, and turn/status UI land in N7d.
extends Node3D

const BootIntentScript = preload("res://cloud/boot_intent.gd")
const CloudSessionScript = preload("res://cloud/cloud_session.gd")
const WorldSnapshotBootstrapScript = preload("res://cloud/world_snapshot_bootstrap.gd")
const TerrainWorldScript = preload("res://presentation/world/terrain_world.gd")
const WorldAnchorUiScript = preload("res://presentation/world/world_anchor_ui.gd")
const WorldUnitsViewScript = preload("res://presentation/world/world_units_view.gd")
const Ts08HeightSolver = preload("res://domain/world/ts08_height_solver.gd")

const FRONT_DOOR_SCENE := "res://cloud/cloud_front_door.tscn"
const NATIVE_DESCRIPTOR_PATH := "res://bin/eom_native.gdextension"

# Built world + anchor UI + unit view, exposed for the headless smoke test.
var world = null
var anchor_ui = null
var units_view = null
# One persistent CloudSession for this match (fetch now; N7d actions later).
var session = null
# Held authoritative snapshot (the live server state this scene renders).
var snapshot: Dictionary = {}
# Last bootstrap failure ("" while healthy); mirrors the on-screen status.
var bootstrap_error := ""

var _status_layer: CanvasLayer = null
var _status_label: Label = null


# N7c small-unit quality profile: the WorldMap 3D viewport renders with
# MSAA 2x + FXAA (the AA level the previously approved real-3D unit path
# used), configured once here on the existing viewport — no SubViewport/
# blit indirection. Terrain, lighting, and camera are unchanged by this.
static func configure_world_viewport_aa(vp: Viewport) -> void:
	vp.msaa_3d = Viewport.MSAA_2X
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA


func _ready() -> void:
	configure_world_viewport_aa(get_viewport())
	_build_status_ui()
	var boot: Dictionary = BootIntentScript.consume_for_main()
	var mode := str(boot.get("mode", ""))
	if (
		mode != BootIntentScript.MODE_CLOUD_CREATE
		and mode != BootIntentScript.MODE_CLOUD_ENTER_CREATED
		and mode != BootIntentScript.MODE_CLOUD_RECONNECT
	):
		push_warning("cloud_world_play: no cloud boot intent (mode=%s); returning to front door" % mode)
		get_tree().change_scene_to_file(FRONT_DOOR_SCENE)
		return
	await _start_from_boot(boot, mode)


func _start_from_boot(boot: Dictionary, mode: String) -> void:
	_set_status(BootIntentScript.CLOUD_CONNECTING_STATUS)
	session = CloudSessionScript.new()
	session.base_url = str(boot.get("server_url", ""))
	session.seat_token = str(boot.get("seat_token", "")).strip_edges()
	add_child(session)
	var resp: Dictionary = {}
	if mode == BootIntentScript.MODE_CLOUD_CREATE:
		var kind := str(boot.get("match_kind", "")).strip_edges()
		if kind != BootIntentScript.MATCH_KIND_WORLD_MAP:
			_fail("cloud_world_play entered in create mode without match_kind=world_map")
			return
		resp = await session.post_create_match(
			"prototype_play",
			str(boot.get("display_name", "")),
			kind,
			BootIntentScript.env_map_id(),
		)
	else:
		session.match_id = str(boot.get("match_id", "")).strip_edges()
		resp = await session.get_match()
	if resp.has("_error"):
		_fail(
			"server request failed: %s (HTTP %s)"
			% [str(resp.get("_error", "")), str(resp.get("_http_code", "?"))]
		)
		return
	var snap = resp.get("snapshot", null)
	if typeof(snap) != TYPE_DICTIONARY:
		_fail("server response has no snapshot object")
		return
	_set_status(BootIntentScript.CLOUD_LOADING_STATUS)
	bootstrap_from_snapshot(snap as Dictionary)


# Deterministic client bootstrap from an already fetched snapshot v3 (also
# the headless-test entry: no networking in here). Returns true when the
# shared TerrainWorld, the anchor UI, and the unit view are built/updated.
func bootstrap_from_snapshot(snap: Dictionary) -> bool:
	var result: Dictionary = WorldSnapshotBootstrapScript.load_and_verify_world_map(snap)
	if not result["ok"]:
		_fail(str(result["error"]))
		return false
	snapshot = snap.duplicate(true)
	var world_map = result["world_map"]
	var backend := _auto_backend()
	if backend == Ts08HeightSolver.BACKEND_GDSCRIPT:
		print("cloud_world_play: native extension unavailable; GDScript solve is slow")
	world = TerrainWorldScript.new()
	world.name = "TerrainWorld"
	add_child(world)
	if not world.build(world_map, backend):
		world.queue_free()
		world = null
		_fail("terrain world build failed for map %s" % world_map.identity.map_id)
		return false
	anchor_ui = WorldAnchorUiScript.new()
	anchor_ui.name = "WorldAnchorUi"
	add_child(anchor_ui)
	anchor_ui.attach(world)
	_render_units()
	bootstrap_error = ""
	var parsed: Dictionary = result["parsed"]
	_set_status(
		"World match — map %s (revision %d, turn %d). Unit actions arrive with N7d."
		% [
			str(parsed.get("map_id", "")),
			int(parsed.get("revision", -1)),
			int((parsed.get("turn_state", {}) as Dictionary).get("turn_number", -1)),
		]
	)
	print(
		"cloud_world_play: world ready (map %s, backend %s)"
		% [world_map.identity.map_id, world.backend_used]
	)
	return true


# N7c unit projection: renders the held authoritative snapshot's units at
# the built terrain's tile anchors. One persistent WorldUnitsView reconciles
# by unit id, so reapplying the same snapshot never duplicates units; the
# view itself waits until BOTH the snapshot units and the anchors exist
# (whichever arrives first) and never falls back to the origin.
func _render_units() -> void:
	if world == null or snapshot.is_empty():
		return
	if units_view == null:
		units_view = WorldUnitsViewScript.new()
		units_view.name = "WorldUnitsView"
		add_child(units_view)
	units_view.set_tile_anchors(world.tile_anchors)
	var units_variant = snapshot.get("units", [])
	units_view.apply_snapshot_units(units_variant if units_variant is Array else [])


# Explicit, visible failure — the locked N6 contract forbids any fallback
# map when content is missing or the identity mismatches.
func _fail(message: String) -> void:
	bootstrap_error = message
	push_error("cloud_world_play: %s" % message)
	_set_status("WORLD BOOTSTRAP FAILED\n%s\nNo fallback map is loaded." % message)


func _build_status_ui() -> void:
	_status_layer = CanvasLayer.new()
	_status_layer.name = "WorldPlayStatus"
	_status_layer.layer = 20
	add_child(_status_layer)
	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	_status_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	_status_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	_status_label.add_theme_constant_override("outline_size", 4)
	_status_layer.add_child(_status_label)


func _set_status(message: String) -> void:
	if _status_label != null:
		_status_label.text = message


# Client presentation backend policy for this production scene: the built
# native solver when available, otherwise the GDScript reference backend
# (identical results; the shared TerrainWorld stays caller-supplied).
func _auto_backend() -> String:
	if not FileAccess.file_exists(NATIVE_DESCRIPTOR_PATH):
		return Ts08HeightSolver.BACKEND_GDSCRIPT
	if not GDExtensionManager.is_extension_loaded(NATIVE_DESCRIPTOR_PATH):
		if GDExtensionManager.load_extension(NATIVE_DESCRIPTOR_PATH) != GDExtensionManager.LOAD_STATUS_OK:
			return Ts08HeightSolver.BACKEND_GDSCRIPT
	if ClassDB.can_instantiate(&"EomTerrainNative"):
		return Ts08HeightSolver.BACKEND_NATIVE
	return Ts08HeightSolver.BACKEND_GDSCRIPT
