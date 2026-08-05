# N6 production scene for server-fed world_map matches (cloud play route).
#
# This is the dedicated gameplay entry for snapshot-v3 matches: the cloud
# front door / staging routes here via BootIntent.play_scene_for_match_kind
# ("world_map"); legacy matches keep res://main.tscn untouched. The flow is:
#   1. consume BootIntent (create / enter-created / reconnect);
#   2. fetch the authoritative snapshot v3 from the server (CloudSession);
#   3. WorldSnapshotBootstrap: parse the envelope, load the canonical map
#      content by map_id through the derived-package manifest, and verify the
#      schema version + raw-byte content hash against the server identity;
#   4. build the shared TerrainWorld (N3c.6) and attach the N4 projected
#      screen-space anchor UI.
# Any missing content or identity mismatch fails VISIBLY (on-screen error +
# push_error) with no fallback map — a silent substitute would desync the
# authoritative WorldMap. No units, movement, actions, yields, cities, or
# client-side legality here (N7+); the server rejects gameplay endpoints for
# world_map matches until N7.
extends Node3D

const BootIntentScript = preload("res://cloud/boot_intent.gd")
const CloudSessionScript = preload("res://cloud/cloud_session.gd")
const WorldSnapshotBootstrapScript = preload("res://cloud/world_snapshot_bootstrap.gd")
const TerrainWorldScript = preload("res://presentation/world/terrain_world.gd")
const WorldAnchorUiScript = preload("res://presentation/world/world_anchor_ui.gd")
const Ts08HeightSolver = preload("res://domain/world/ts08_height_solver.gd")

const FRONT_DOOR_SCENE := "res://cloud/cloud_front_door.tscn"
const NATIVE_DESCRIPTOR_PATH := "res://bin/eom_native.gdextension"

# Built world + anchor UI, exposed for the headless smoke test.
var world = null
var anchor_ui = null
# Last bootstrap failure ("" while healthy); mirrors the on-screen status.
var bootstrap_error := ""

var _status_layer: CanvasLayer = null
var _status_label: Label = null


func _ready() -> void:
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
	var sess = CloudSessionScript.new()
	sess.base_url = str(boot.get("server_url", ""))
	sess.seat_token = str(boot.get("seat_token", "")).strip_edges()
	add_child(sess)
	var resp: Dictionary = {}
	if mode == BootIntentScript.MODE_CLOUD_CREATE:
		var kind := str(boot.get("match_kind", "")).strip_edges()
		if kind != BootIntentScript.MATCH_KIND_WORLD_MAP:
			sess.queue_free()
			_fail("cloud_world_play entered in create mode without match_kind=world_map")
			return
		resp = await sess.post_create_match(
			"prototype_play",
			str(boot.get("display_name", "")),
			kind,
			BootIntentScript.env_map_id(),
		)
	else:
		sess.match_id = str(boot.get("match_id", "")).strip_edges()
		resp = await sess.get_match()
	sess.queue_free()
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
# shared TerrainWorld and the anchor UI are built and attached.
func bootstrap_from_snapshot(snap: Dictionary) -> bool:
	var result: Dictionary = WorldSnapshotBootstrapScript.load_and_verify_world_map(snap)
	if not result["ok"]:
		_fail(str(result["error"]))
		return false
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
	bootstrap_error = ""
	var parsed: Dictionary = result["parsed"]
	_set_status(
		"World match — map %s (revision %d, turn %d). Gameplay actions arrive with N7."
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
