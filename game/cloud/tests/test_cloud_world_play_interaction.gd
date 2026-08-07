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


# Stub world for _render_units: the production path reads tile_anchors and
# resolves a (cleanly missing) surface sampler from the world Node.
class WorldStub:
	extends Node3D
	const ANCHOR_A := Vector3(0.0, 0.0, 0.0)
	const ANCHOR_B := Vector3(2.0, 0.4, 0.0)
	const ANCHOR_C := Vector3(0.0, 0.2, 2.0)
	var tile_anchors := {
		Vector2i(0, 0): ANCHOR_A,
		Vector2i(1, 0): ANCHOR_B,
		Vector2i(0, 1): ANCHOR_C,
	}


# Scripted session for the arrival-gate wiring: records every POST and
# legality fetch; `mode` selects accepted / rejected / transport-failure /
# accepted-without-snapshot responses. Awaiting its plain methods resumes
# immediately, so the whole scene flow runs synchronously in tests.
class FakeMoveSession:
	extends RefCounted
	const GATE_MAP := {
		"map_id": "handdrawn_test_map_full_01",
		"schema_version": 1,
		"content_hash": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
	}
	# When `deferred` is set, post_action suspends on the `respond` signal —
	# a genuinely pending POST across process frames until the test emits it.
	signal respond
	var deferred := false
	var pending := 0
	var mode := "accept"
	var revision := 0
	var unit_pos: Array = [0, 0]
	var extra_units: Array = []
	var post_calls: Array = []
	var legal_calls: Array = []

	static func make_snapshot(rev: int, upos: Array, current_index: int = 0, extra: Array = []) -> Dictionary:
		var units: Array = [
			{"id": 1, "owner_id": 0, "position": upos, "type_id": "settler"},
		]
		units.append_array(extra.duplicate(true))
		return {
			"match_id": "m_gate",
			"schema_version": 3,
			"match_kind": "world_map",
			"map": GATE_MAP.duplicate(true),
			"revision": rev,
			"turn_state": {"players": [0, 1], "current_index": current_index, "turn_number": 1},
			"units": units,
		}

	func post_action(action: Dictionary) -> Dictionary:
		post_calls.append(action.duplicate(true))
		if deferred:
			pending += 1
			await respond
			pending -= 1
		if mode == "error":
			return {"_error": "http", "_http_code": 0}
		if mode == "reject":
			return {"accepted": false, "reason": "destination_occupied", "index": -1}
		if mode == "accepted_no_snapshot":
			return {"accepted": true, "reason": "", "index": 0, "revision": revision + 1}
		if mode == "accept_stationary":
			# Accepted move whose authoritative snapshot leaves the unit at
			# its current anchor — the applied snapshot starts NO glide.
			revision += 1
			return {
				"accepted": true, "reason": "", "index": 0, "revision": revision,
				"snapshot": make_snapshot(revision, unit_pos, 0, extra_units),
			}
		revision += 1
		if str(action.get("action_type", "")) == "move_unit":
			unit_pos = (action.get("to", [0, 0]) as Array).duplicate()
			return {
				"accepted": true, "reason": "", "index": 0, "revision": revision,
				"snapshot": make_snapshot(revision, unit_pos, 0, extra_units),
			}
		return {
			"accepted": true, "reason": "", "index": 0, "revision": revision,
			"snapshot": make_snapshot(revision, unit_pos, 1, extra_units),
		}

	func get_legal_actions(actor_id: int, selected_unit_id: int = -1, _selected_city_id: int = -1) -> Dictionary:
		legal_calls.append([actor_id, selected_unit_id])
		if selected_unit_id >= 0:
			return selection_response()
		return summary_response()

	func summary_response() -> Dictionary:
		return {
			"revision": revision,
			"actor_id": 0,
			"is_current_player": true,
			"selected_unit_id": null,
			"actions": [{"schema_version": 1, "action_type": "end_turn", "actor_id": 0}],
		}

	func selection_response() -> Dictionary:
		return {
			"revision": revision,
			"actor_id": 0,
			"is_current_player": true,
			"selected_unit_id": 1,
			"actions": [{
				"schema_version": 1,
				"action_type": "move_unit",
				"actor_id": 0,
				"unit_id": 1,
				"from": unit_pos.duplicate(),
				"to": [1, 0] if unit_pos == [0, 0] else [0, 0],
			}],
		}


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
	var serial: int = st.begin_summary_fetch()
	st.accept_summary_legal_actions(
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

	# --- N7f.1 arrival gate: production wiring with a scripted session -------
	var scene2 = packed.instantiate()
	scene2._build_status_ui()
	var button2: Button = scene2.get_node("WorldPlayStatus/EndTurnButton") as Button
	var fake := FakeMoveSession.new()
	scene2.session = fake
	var stub_world := WorldStub.new()
	scene2.add_child(stub_world)
	scene2.world = stub_world
	scene2.snapshot = FakeMoveSession.make_snapshot(0, [0, 0])
	var st2 = WorldInteractionStateScript.new(0)
	scene2.interaction = st2
	st2.apply_snapshot(scene2.snapshot)
	st2.select_unit(1)
	var s_sum: int = st2.begin_summary_fetch()
	st2.accept_summary_legal_actions(s_sum, fake.summary_response())
	var s_sel: int = st2.begin_selection_fetch()
	st2.accept_selection_legal_actions(s_sel, fake.selection_response())
	_check(st2.can_submit_end_turn() and not st2.destination_tiles().is_empty(), "gate scene precondition: live rows")
	scene2._render_units()
	_check(scene2.units_view != null, "production _render_units builds the units view from the stub world")
	_check(
		(scene2.units_view as Node).is_connected("unit_arrived", scene2._on_unit_arrived),
		"production wiring connects unit_arrived to the arrival-gate handler"
	)

	# Accepted move: one POST, gate armed, glide running, no legality fetch.
	scene2._on_terrain_picked({"kind": "tile", "tile": Vector2i(1, 0)})
	_check(fake.post_calls.size() == 1, "the destination click POSTs exactly once")
	_check(st2.arrival_gate_active(), "accepted move arms the arrival gate")
	_check(int(scene2.snapshot.get("revision", -1)) == 1, "the accepted snapshot is applied immediately")
	_check(scene2.units_view.root_for_unit(1).position == WorldStub.ANCHOR_B, "the authoritative root snapped to the new anchor immediately")
	_check(scene2.units_view.is_unit_moving(1), "the visual glide is running while gated")
	_check(fake.legal_calls.size() == 0, "no summary/selection legality is fetched during locomotion")
	_check(button2.disabled, "End Turn is disabled while gated")
	_check(st2.destination_tiles().is_empty(), "destination markers are hidden while gated")
	_check(st2.selected_unit_id == 1, "the moved unit stays selected while gated")

	# Rapid repeated clicks (and every other pick kind) cannot double-POST.
	for rapid_pick in [
		{"kind": "tile", "tile": Vector2i(1, 0)},
		{"kind": "tile", "tile": Vector2i(0, 0)},
		{"kind": "tile", "tile": Vector2i(9, 9)},
		{},
		{"kind": "cliff", "edge": [], "tiles": []},
	]:
		scene2._on_terrain_picked(rapid_pick)
	scene2._on_end_turn_pressed()
	_check(fake.post_calls.size() == 1, "rapid clicks + End Turn while gated produce NO second POST")

	# Stale/wrong arrival stays locked; the real one releases + refetches.
	scene2._on_unit_arrived(99)
	_check(st2.arrival_gate_active() and fake.legal_calls.size() == 0, "wrong-unit arrival stays inert")
	scene2.units_view.advance_locomotion(60.0)
	_check(not st2.arrival_gate_active(), "the real visual arrival releases the gate")
	_check(
		fake.legal_calls == [[0, -1], [0, 1]],
		"exactly one summary + one selected-unit refetch after arrival"
	)
	_check(not st2.destination_tiles().is_empty(), "markers return only from the fresh served rows")
	scene2._refresh_interaction_ui()
	_check(not button2.disabled, "End Turn re-enables from the fresh summary row")

	# Rejection, transport failure, and accepted-without-snapshot never gate.
	fake.mode = "reject"
	scene2._on_terrain_picked({"kind": "tile", "tile": Vector2i(0, 0)})
	_check(fake.post_calls.size() == 2, "rejected move still POSTs (once)")
	_check(not st2.arrival_gate_active(), "a rejected move never enters the gate")
	_check(not st2.destination_tiles().is_empty(), "served rows stay usable after a rejection")
	fake.mode = "error"
	scene2._on_terrain_picked({"kind": "tile", "tile": Vector2i(0, 0)})
	_check(not st2.arrival_gate_active(), "a transport failure never enters the gate")
	fake.mode = "accepted_no_snapshot"
	scene2._on_terrain_picked({"kind": "tile", "tile": Vector2i(0, 0)})
	_check(not st2.arrival_gate_active(), "an accepted response without a snapshot leaves no gate")
	var feedback2: Label = scene2.get_node("WorldPlayStatus/ActionFeedbackLabel") as Label
	_check(feedback2.text.contains("no snapshot"), "the unusable accepted response fails visibly")

	# Accepted NON-move action (End Turn) behaves exactly as before: no gate.
	fake.mode = "accept"
	scene2._on_end_turn_pressed()
	_check(fake.post_calls.size() == 5 and str((fake.post_calls[4] as Dictionary).get("action_type", "")) == "end_turn", "End Turn POSTs normally once un-gated")
	_check(not st2.arrival_gate_active(), "accepted non-move actions never enter the gate")
	_check(int(scene2.snapshot.get("revision", -1)) == 2, "the end-turn snapshot applied normally")

	scene2.free()

	# --- N7f.1 request race: picks are inert while a POST is pending ----------
	# A DEFERRED move response stays genuinely pending across a process frame;
	# rapid picks during that window must not change or clear the selection
	# the pending response's arrival gate is about to bind to.
	var scene3 = packed.instantiate()
	scene3._build_status_ui()
	var dfake := FakeMoveSession.new()
	dfake.deferred = true
	dfake.extra_units = [
		{"id": 2, "owner_id": 0, "position": [0, 1], "type_id": "warrior"},
	]
	scene3.session = dfake
	var stub3 := WorldStub.new()
	scene3.add_child(stub3)
	scene3.world = stub3
	scene3.snapshot = FakeMoveSession.make_snapshot(0, [0, 0], 0, dfake.extra_units)
	var st3 = WorldInteractionStateScript.new(0)
	scene3.interaction = st3
	st3.apply_snapshot(scene3.snapshot)
	st3.select_unit(1)
	var d_sum: int = st3.begin_summary_fetch()
	st3.accept_summary_legal_actions(d_sum, dfake.summary_response())
	var d_sel: int = st3.begin_selection_fetch()
	st3.accept_selection_legal_actions(d_sel, dfake.selection_response())
	scene3._render_units()
	var served_before: Array = st3.destination_tiles()
	scene3._on_terrain_picked({"kind": "tile", "tile": Vector2i(1, 0)})  # not awaited — stays pending
	_check(dfake.post_calls.size() == 1 and dfake.pending == 1, "the move POST is genuinely pending")
	_check(scene3._request_busy, "_request_busy is active while the POST is pending")
	await process_frame
	_check(dfake.pending == 1, "the POST remains pending across a process frame")
	for racy_pick in [
		{"kind": "tile", "tile": Vector2i(0, 1)},  # another OWN unit
		{"kind": "tile", "tile": Vector2i(9, 9)},  # empty terrain
		{"kind": "tile", "tile": Vector2i(1, 0)},  # the served destination
		{},  # miss
		{"kind": "cliff", "edge": [], "tiles": []},  # cliff
	]:
		scene3._on_terrain_picked(racy_pick)
	scene3._on_end_turn_pressed()
	_check(st3.selected_unit_id == 1, "selection stays the moved unit through every pending-POST pick")
	_check(st3.destination_tiles() == served_before, "served rows are unchanged during the pending POST")
	_check(dfake.post_calls.size() == 1, "no second POST while the request is pending")
	_check(not st3.arrival_gate_active(), "the gate is not entered before the response resolves")
	_check(dfake.legal_calls.size() == 0, "no legality fetch while the request is pending")
	dfake.respond.emit()  # resolve the accepted response
	_check(dfake.pending == 0 and not scene3._request_busy, "the deferred response resolved")
	_check(int(scene3.snapshot.get("revision", -1)) == 1, "the authoritative snapshot applied on resolution")
	_check(
		st3.arrival_gate_active()
			and st3.arrival_gate_unit_id == 1
			and st3.arrival_gate_revision == 1,
		"the gate binds to the moved unit and the accepted revision"
	)
	_check(st3.selected_unit_id == 1, "unit 1 remains selected after resolution")
	_check(scene3.units_view.is_unit_moving(1), "the visual glide runs after resolution")
	_check(dfake.legal_calls.size() == 0, "no legality is fetched before the visual arrival")
	scene3.units_view.advance_locomotion(60.0)
	_check(not st3.arrival_gate_active(), "the deferred flow still releases on the real arrival")
	_check(dfake.legal_calls == [[0, -1], [0, 1]], "one summary + one selection refetch after arrival")
	scene3.free()

	# --- N7f.1 degenerate/no-glide release: accepted move without a glide -----
	# The applied snapshot leaves the unit at its current anchor, so no
	# locomotion starts and no unit_arrived signal will EVER come — the
	# scene's degenerate-settlement path must release the just-entered gate
	# synchronously, with exactly one summary + still-valid-selection refetch.
	var scene4 = packed.instantiate()
	scene4._build_status_ui()
	var button4: Button = scene4.get_node("WorldPlayStatus/EndTurnButton") as Button
	var sfake := FakeMoveSession.new()
	sfake.mode = "accept_stationary"
	scene4.session = sfake
	var stub4 := WorldStub.new()
	scene4.add_child(stub4)
	scene4.world = stub4
	scene4.snapshot = FakeMoveSession.make_snapshot(0, [0, 0])
	var st4b = WorldInteractionStateScript.new(0)
	scene4.interaction = st4b
	st4b.apply_snapshot(scene4.snapshot)
	st4b.select_unit(1)
	var g_sum: int = st4b.begin_summary_fetch()
	st4b.accept_summary_legal_actions(g_sum, sfake.summary_response())
	var g_sel: int = st4b.begin_selection_fetch()
	st4b.accept_selection_legal_actions(g_sel, sfake.selection_response())
	scene4._render_units()
	scene4._on_terrain_picked({"kind": "tile", "tile": Vector2i(1, 0)})
	_check(sfake.post_calls.size() == 1, "the degenerate move POSTs exactly once")
	_check(int(scene4.snapshot.get("revision", -1)) == 1, "the accepted stationary snapshot applied")
	_check(not scene4.units_view.is_unit_moving(1), "no glide started (degenerate settlement)")
	_check(not st4b.arrival_gate_active(), "the gate released synchronously without a unit_arrived signal")
	_check(
		sfake.legal_calls == [[0, -1], [0, 1]],
		"exactly one summary + one still-valid-selection refetch (no duplicates)"
	)
	_check(st4b.selected_unit_id == 1, "the selection survives the degenerate release")
	_check(not st4b.destination_tiles().is_empty(), "fresh served rows are usable again — no permanent lock")
	scene4._refresh_interaction_ui()
	_check(not button4.disabled, "End Turn re-enables after the degenerate release")
	scene4.units_view.advance_locomotion(60.0)
	scene4._on_unit_arrived(1)
	_check(
		sfake.legal_calls.size() == 2,
		"no duplicate release/refetch from later idle advancing or stale arrivals"
	)
	scene4.free()
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
