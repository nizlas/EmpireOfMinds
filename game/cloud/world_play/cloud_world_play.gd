# N6/N7c/N7d production scene for server-fed world_map matches (cloud play).
#
# This is the dedicated gameplay entry for snapshot-v3 matches: the cloud
# front door / staging routes here via BootIntent.play_scene_for_match_kind
# ("world_map"); legacy matches keep res://main.tscn untouched. The flow is:
#   1. consume BootIntent (create / enter-created / reconnect);
#   2. fetch the authoritative snapshot v3 from the server (one persistent
#      CloudSession used for the whole N7d action/polling loop);
#   3. WorldSnapshotBootstrap: parse the envelope, load the canonical map
#      content by map_id through the derived-package manifest, and verify the
#      schema version + raw-byte content hash against the server identity;
#   4. build the shared TerrainWorld (N3c.6), attach the N4 projected
#      screen-space anchor UI, and render the snapshot's units as the
#      existing 3D characters at the tile anchors (N7c, WorldUnitsView);
#   5. N7d interaction loop: own-unit selection from terrain picks, SERVED
#      legal destinations rendered as projected markers, submission of the
#      exact served rows (move_unit / summary end_turn), out-of-turn
#      snapshot polling, and a minimal turn/status + rejection UI.
# Any missing content or identity mismatch fails VISIBLY (on-screen error +
# push_error) with no fallback map — a silent substitute would desync the
# authoritative WorldMap. Unit legality stays server-only (N7a/N7b): the
# client renders and submits only served rows, bound to their revision and
# selection per the locked N7d freshness contract. Movement animation,
# facing, slope alignment, and foot grounding are N7f; combat is N7g;
# cities/production are N8a–N8d.
extends Node3D

const BootIntentScript = preload("res://cloud/boot_intent.gd")
const CloudSessionScript = preload("res://cloud/cloud_session.gd")
const CloudTurnOwnershipScript = preload("res://cloud/cloud_turn_ownership.gd")
const CloudPlayerIdentityScript = preload("res://cloud/cloud_player_identity.gd")
const WorldSnapshotBootstrapScript = preload("res://cloud/world_snapshot_bootstrap.gd")
const WorldInteractionStateScript = preload("res://cloud/world_play/world_interaction_state.gd")
const TerrainWorldScript = preload("res://presentation/world/terrain_world.gd")
const WorldAnchorUiScript = preload("res://presentation/world/world_anchor_ui.gd")
const WorldUnitsViewScript = preload("res://presentation/world/world_units_view.gd")
const WorldDestinationMarkersScript = preload("res://presentation/world/world_destination_markers.gd")
const Ts08HeightSolver = preload("res://domain/world/ts08_height_solver.gd")

const FRONT_DOOR_SCENE := "res://cloud/cloud_front_door.tscn"
const NATIVE_DESCRIPTOR_PATH := "res://bin/eom_native.gdextension"

# Built world + anchor UI + unit view, exposed for the headless smoke test.
var world = null
var anchor_ui = null
var units_view = null
# One persistent CloudSession for this match (bootstrap fetch + N7d loop).
var session = null
# Held authoritative snapshot (the live server state this scene renders).
var snapshot: Dictionary = {}
# Last bootstrap failure ("" while healthy); mirrors the on-screen status.
var bootstrap_error := ""
# N7d interaction state (freshness/selection/poll gating) + marker layer.
var interaction = null
var markers = null

var _status_layer: CanvasLayer = null
var _status_label: Label = null
var _action_label: Label = null
var _end_turn_button: Button = null
var _poll_timer: Timer = null
# Own seat identity from the boot intent (st_ token + actor id; -1 = none).
var _boot_actor_id := -1
# One request at a time on the shared CloudSession HTTPRequest.
var _request_busy := false
# A legal-actions refetch is due (set by snapshot applies / selection moves).
var _legal_refetch_needed := false


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
	_boot_actor_id = CloudTurnOwnershipScript.gameplay_actor_id_from_boot(boot)
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
	if session.match_id.is_empty():
		session.match_id = str(resp.get("match_id", "")).strip_edges()
	var snap = resp.get("snapshot", null)
	if typeof(snap) != TYPE_DICTIONARY:
		_fail("server response has no snapshot object")
		return
	_set_status(BootIntentScript.CLOUD_LOADING_STATUS)
	if bootstrap_from_snapshot(snap as Dictionary):
		await _pump_legal_fetch()


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
	_setup_interaction()
	bootstrap_error = ""
	_refresh_interaction_ui()
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


# N7d wiring: interaction state + projected marker layer + pick routing +
# waiting poll. Deterministic and network-free — the session calls happen in
# the pump/submit/poll handlers, which all no-op without a session (headless
# tests drive bootstrap_from_snapshot directly).
func _setup_interaction() -> void:
	if interaction == null:
		interaction = WorldInteractionStateScript.new(_boot_actor_id)
	if markers == null:
		markers = WorldDestinationMarkersScript.new()
		markers.name = "WorldDestinationMarkers"
		add_child(markers)
	markers.attach(world)
	if not world.terrain_picked.is_connected(_on_terrain_picked):
		world.terrain_picked.connect(_on_terrain_picked)
	CloudPlayerIdentityScript.apply_from_snapshot(snapshot)
	var directive: String = interaction.apply_snapshot(snapshot)
	_legal_refetch_needed = directive != WorldInteractionStateScript.REFETCH_NONE
	if _poll_timer == null:
		_poll_timer = Timer.new()
		_poll_timer.name = "WorldWaitingPollTimer"
		_poll_timer.wait_time = CloudTurnOwnershipScript.WAITING_POLL_INTERVAL_SEC
		_poll_timer.autostart = true
		_poll_timer.timeout.connect(_on_poll_timeout)
		add_child(_poll_timer)
		if is_inside_tree():
			_poll_timer.start()


# Locked N4/N7d pick routing: own-unit tile selects, a fresh served
# destination submits that exact row, miss clears, cliff leaves selection
# unchanged, out-of-turn picks change nothing (classification lives in the
# deterministic interaction state).
func _on_terrain_picked(pick: Dictionary) -> void:
	if interaction == null:
		return
	var directive: Dictionary = interaction.classify_pick(pick)
	match str(directive.get("kind", "")):
		WorldInteractionStateScript.PICK_SUBMIT_MOVE:
			await _submit_action(directive["action"])
		WorldInteractionStateScript.PICK_SELECT_UNIT:
			interaction.select_unit(int(directive["unit_id"]))
			_legal_refetch_needed = true
			_refresh_interaction_ui()
			await _pump_legal_fetch()
		WorldInteractionStateScript.PICK_CLEAR:
			interaction.clear_selection()
			_refresh_interaction_ui()
		_:
			pass


func _on_end_turn_pressed() -> void:
	if interaction == null or _request_busy or not interaction.can_submit_end_turn():
		return
	await _submit_action(interaction.end_turn_row)


# Submits one EXACT served action row. Accepted responses carry the new
# authoritative snapshot; rejections (HTTP 200, accepted=false) change no
# state and only surface the literal reason.
func _submit_action(action_row: Dictionary) -> void:
	if session == null or _request_busy or action_row.is_empty():
		return
	_request_busy = true
	_refresh_interaction_ui()
	var resp: Dictionary = await session.post_action(action_row)
	_request_busy = false
	if resp.has("_error"):
		_set_action_feedback(
			"Request failed: %s (HTTP %s)"
			% [str(resp.get("_error", "")), str(resp.get("_http_code", "?"))]
		)
		_refresh_interaction_ui()
		return
	if not bool(resp.get("accepted", false)):
		_set_action_feedback("Action rejected: %s" % str(resp.get("reason", "unknown")))
		_refresh_interaction_ui()
		return
	_set_action_feedback("")
	var snap = resp.get("snapshot", null)
	if typeof(snap) == TYPE_DICTIONARY:
		_apply_authoritative_snapshot(snap as Dictionary)
		await _pump_legal_fetch()


# Applies a newer authoritative snapshot (accepted action or waiting poll)
# WITHOUT rebuilding the terrain: the map identity of a match is immutable,
# so a changed identity is server/content drift and fails visibly (locked
# no-fallback rule). Clears served rows/markers immediately and schedules
# the refetch the interaction state asks for (locked freshness contract).
func _apply_authoritative_snapshot(snap: Dictionary) -> void:
	if snapshot.has("map") and snap.get("map", null) != snapshot.get("map", null):
		_fail("snapshot map identity changed mid-match (server/content drift)")
		return
	snapshot = snap.duplicate(true)
	CloudPlayerIdentityScript.apply_from_snapshot(snapshot)
	_render_units()
	if interaction != null:
		var directive: String = interaction.apply_snapshot(snapshot)
		_legal_refetch_needed = directive != WorldInteractionStateScript.REFETCH_NONE
	_refresh_interaction_ui()


# Fetches served legality for the CURRENT selection/summary state when due.
# Responses are accepted only through the locked freshness rules (serial +
# revision + still-current selection); discarded responses trigger another
# pump so a still-valid selection is refetched, never rendered stale.
func _pump_legal_fetch() -> void:
	while _legal_refetch_needed and session != null and interaction != null and not _request_busy:
		if interaction.my_actor_id < 0:
			_legal_refetch_needed = false
			return
		_legal_refetch_needed = false
		var serial: int = interaction.begin_legal_fetch()
		_request_busy = true
		_refresh_interaction_ui()
		var resp: Dictionary = await session.get_legal_actions(
			interaction.my_actor_id, interaction.selected_unit_id
		)
		_request_busy = false
		if resp.has("_error"):
			_set_action_feedback(
				"legal-actions failed: %s (HTTP %s)"
				% [str(resp.get("_error", "")), str(resp.get("_http_code", "?"))]
			)
			_refresh_interaction_ui()
			return
		if not interaction.accept_legal_actions(serial, resp):
			# Stale (revision/selection/serial moved on) — never rendered.
			# Refetch when the current state still wants served rows.
			_legal_refetch_needed = (
				interaction.is_my_turn()
				and int(resp.get("revision", -1)) == interaction.revision
			) or _legal_refetch_needed
		_refresh_interaction_ui()


# Conservative out-of-turn waiting poll (C14d-4b pattern): only while
# seated, out of turn, and idle; newer snapshots apply through the same
# freshness path as accepted actions.
func _on_poll_timeout() -> void:
	if session == null or interaction == null:
		return
	if not interaction.should_poll(_request_busy):
		return
	_request_busy = true
	var resp: Dictionary = await session.get_match()
	_request_busy = false
	if resp.has("_error"):
		return
	var snap = resp.get("snapshot", null)
	if typeof(snap) == TYPE_DICTIONARY and interaction.is_newer_snapshot(snap as Dictionary):
		_apply_authoritative_snapshot(snap as Dictionary)
		await _pump_legal_fetch()


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
	# N7d: rejection/error feedback line under the status strip.
	_action_label = Label.new()
	_action_label.name = "ActionFeedbackLabel"
	_action_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_action_label.offset_top = -32.0
	_action_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_action_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.6))
	_action_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	_action_label.add_theme_constant_override("outline_size", 4)
	_status_layer.add_child(_action_label)
	# N7d: End Turn — posts the summary-mode submit-ready end_turn row only.
	_end_turn_button = Button.new()
	_end_turn_button.name = "EndTurnButton"
	_end_turn_button.text = "End Turn"
	_end_turn_button.disabled = true
	_end_turn_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_end_turn_button.offset_left = -140.0
	_end_turn_button.offset_top = -76.0
	_end_turn_button.offset_right = -16.0
	_end_turn_button.offset_bottom = -40.0
	_end_turn_button.pressed.connect(_on_end_turn_pressed)
	_status_layer.add_child(_end_turn_button)


func _set_status(message: String) -> void:
	if _status_label != null:
		_status_label.text = message


func _set_action_feedback(message: String) -> void:
	if _action_label != null:
		_action_label.text = message


# One place recomputes every N7d-visible output from the current state:
# status line, marker set (exactly the fresh served rows), End Turn gate.
func _refresh_interaction_ui() -> void:
	if interaction == null:
		return
	if markers != null:
		markers.set_markers(interaction.selected_tile(), interaction.destination_tiles())
	if _end_turn_button != null:
		_end_turn_button.disabled = _request_busy or not interaction.can_submit_end_turn()
	if bootstrap_error.is_empty() and not snapshot.is_empty():
		var parsed_map = snapshot.get("map", {})
		var map_id := str((parsed_map as Dictionary).get("map_id", "")) if typeof(parsed_map) == TYPE_DICTIONARY else ""
		var line := "World match — map %s (revision %d, turn %d)" % [
			map_id,
			int(snapshot.get("revision", -1)),
			int((snapshot.get("turn_state", {}) as Dictionary).get("turn_number", -1)),
		]
		var turn_line: String = interaction.status_text()
		if not turn_line.is_empty():
			line += "\n" + turn_line
		_set_status(line)


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
