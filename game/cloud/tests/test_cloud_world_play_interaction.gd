# Headless: godot --headless --path game -s res://cloud/tests/test_cloud_world_play_interaction.gd
#
# N7d wiring in the production world-play scene (cloud_world_play.gd),
# covered without a terrain build or networking:
# - the status layer carries the End Turn button (disabled by default) and
#   the rejection/error feedback label;
# - the End Turn gate follows the interaction state's locked freshness rule
#   (summary row + matching revision) and the busy flag;
# - pick/End Turn handlers are inert before the interaction exists and
#   without a session (no crash, no state invented);
# - a mid-match snapshot whose map identity differs from the held one fails
#   VISIBLY (server/content drift — locked no-fallback rule).
extends SceneTree

const WorldInteractionStateScript = preload("res://cloud/world_play/world_interaction_state.gd")

var _total := 0
var _any_fail := false


func _snapshot(rev: int, map_hash: String) -> Dictionary:
	return {
		"match_id": "m_wire",
		"schema_version": 3,
		"match_kind": "world_map",
		"map": {"map_id": "handdrawn_test_map_full_01", "schema_version": 1, "content_hash": map_hash},
		"revision": rev,
		"turn_state": {"players": [0, 1], "current_index": 0, "turn_number": 1},
		"units": [
			{"id": 1, "owner_id": 0, "position": [1, 1], "type_id": "settler"},
		],
	}


func _init() -> void:
	var packed: PackedScene = load("res://cloud/world_play/cloud_world_play.tscn") as PackedScene
	_check(packed != null, "cloud_world_play scene loads")
	if packed == null:
		_finish()
		return
	var scene = packed.instantiate()
	_check(scene != null, "cloud_world_play instantiates")

	# --- handlers are inert before bootstrap (no interaction, no session) ---
	scene._on_terrain_picked({})
	scene._on_terrain_picked({"kind": "tile", "tile": Vector2i(1, 1)})
	scene._on_end_turn_pressed()
	_check(scene.interaction == null, "picks before bootstrap create no interaction state")
	_check(scene.bootstrap_error == "", "inert handlers report no failure")

	# --- status UI: End Turn button + feedback label ---
	scene._build_status_ui()
	var status_layer: Node = scene.get_node_or_null("WorldPlayStatus")
	_check(status_layer != null, "status layer exists")
	var button: Button = status_layer.get_node_or_null("EndTurnButton") as Button
	_check(button != null, "End Turn button exists in the status layer")
	_check(button != null and button.disabled, "End Turn starts disabled")
	var feedback: Label = status_layer.get_node_or_null("ActionFeedbackLabel") as Label
	_check(feedback != null, "action rejection/error feedback label exists")

	# --- End Turn gate follows the interaction state's freshness rules ---
	var st = WorldInteractionStateScript.new(0)
	scene.interaction = st
	scene.snapshot = _snapshot(0, "a".repeat(64))
	st.apply_snapshot(scene.snapshot)
	scene._refresh_interaction_ui()
	_check(button.disabled, "End Turn stays disabled without a summary row")
	var serial: int = st.begin_legal_fetch()
	st.accept_legal_actions(
		serial,
		{
			"revision": 0,
			"actor_id": 0,
			"is_current_player": true,
			"selected_unit_id": null,
			"actions": [{"schema_version": 1, "action_type": "end_turn", "actor_id": 0}],
		}
	)
	scene._refresh_interaction_ui()
	_check(not button.disabled, "End Turn enables with a fresh summary end_turn row")
	scene._request_busy = true
	scene._refresh_interaction_ui()
	_check(button.disabled, "End Turn disables while a request is in flight")
	scene._request_busy = false

	# End Turn press without a session stays inert (no crash, row retained).
	scene._on_end_turn_pressed()
	_check(st.can_submit_end_turn(), "End Turn press without a session changes nothing")

	# --- mid-match map identity drift fails visibly (no fallback) ---
	scene._apply_authoritative_snapshot(_snapshot(1, "b".repeat(64)))
	_check(
		str(scene.bootstrap_error).contains("identity changed"),
		"mid-match map identity drift fails visibly"
	)
	_check(
		int(scene.snapshot.get("revision", -1)) == 0,
		"drifted snapshot is not applied"
	)

	scene.free()
	_finish()


func _check(condition: bool, label: String) -> void:
	_total += 1
	if condition:
		print("PASS ", label)
	else:
		_any_fail = true
		print("FAIL ", label)


func _finish() -> void:
	print("CloudWorldPlayInteraction tests: %d checks" % _total)
	if _any_fail:
		print("FAIL")
		quit(1)
	else:
		print("PASS")
		quit(0)
