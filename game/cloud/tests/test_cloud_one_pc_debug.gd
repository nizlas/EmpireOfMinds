# Headless: godot --headless --path game -s res://cloud/tests/test_cloud_one_pc_debug.gd
#
# N7d one-PC debug mode (locked dual-entry direction): one Godot client
# against a LOCAL authoritative FastAPI server controls both players in
# turn, through the same client-server API/action path as remote play.
# Deterministic, network-free coverage of:
# - activation guards: explicit EOM_CLOUD_ONE_PC_DEBUG=1 only, world_map
#   only, loopback only; EOM_CLOUD_DEBUG stays logging-only; host-token
#   authority only inside the mode;
# - fresh create -> NORMAL staging APIs -> ongoing: claim both seats with
#   their own returned tokens, assign the first two distinct
#   server-advertised civilizations deterministically, ready both seats,
#   fetch the ongoing snapshot with the host token — no server bypasses;
# - gameplay handoff: Player 0 move/End Turn -> Player 1 becomes
#   controllable in the SAME client -> End Turn back; actor changes
#   invalidate the selection and BOTH served slots; stale previous-actor
#   responses are discarded;
# - normal multiplayer unchanged when the mode is off: fixed seat identity
#   and full out-of-turn inertness.
extends SceneTree

const BootIntentScript = preload("res://cloud/boot_intent.gd")
const WorldInteractionStateScript = preload("res://cloud/world_play/world_interaction_state.gd")

var _total := 0
var _any_fail := false


class FakeSession extends RefCounted:
	var base_url := "http://127.0.0.1:8000"
	var match_id := ""
	var seat_token := ""
	var calls: Array = []

	func post_claim_seat(actor_id: int) -> Dictionary:
		calls.append(["claim", actor_id, seat_token])
		return {
			"match_id": match_id,
			"actor_id": actor_id,
			"seat_token": "st_seat_%d" % actor_id,
			"status": "staging",
		}

	func get_matches_list(status_filter: String = "") -> Dictionary:
		calls.append(["list", status_filter, seat_token])
		return {
			"matches": [
				{"match_id": "m_other", "available_factions": [{"id": "paris"}]},
				{
					"match_id": match_id,
					"available_factions": [
						{"id": "malmo", "display_name": "Malmöfubikkarna"},
						{"id": "malmo", "display_name": "duplicate row"},
						{"id": "vastervik", "display_name": "Västerviksjävlarna"},
						{"id": "paris", "display_name": "Pajasarna från Paris"},
					],
				},
			],
		}

	func post_seat_faction(actor_id: int, faction_id: String) -> Dictionary:
		calls.append(["faction", actor_id, faction_id, seat_token])
		return {"match_id": match_id, "status": "staging"}

	func post_seat_ready(actor_id: int, ready: bool) -> Dictionary:
		calls.append(["ready", actor_id, ready, seat_token])
		return {"match_id": match_id, "status": "ongoing" if actor_id == 1 else "staging"}

	func get_match() -> Dictionary:
		calls.append(["get_match", seat_token])
		return {
			"match_id": match_id,
			"snapshot": {
				"match_id": match_id,
				"schema_version": 3,
				"match_kind": "world_map",
				"revision": 0,
				"turn_state": {"players": [0, 1], "current_index": 0, "turn_number": 1},
				"units": [],
				"player_factions": {"0": "malmo", "1": "vastervik"},
			},
		}


func _snapshot(rev: int, current_index: int) -> Dictionary:
	return {
		"revision": rev,
		"turn_state": {"players": [0, 1], "current_index": current_index, "turn_number": 1},
		"units": [
			{"id": 1, "owner_id": 0, "position": [1, 1], "type_id": "settler"},
			{"id": 3, "owner_id": 1, "position": [2, 14], "type_id": "settler"},
		],
	}


func _summary_response(rev: int, actor_id: int) -> Dictionary:
	return {
		"revision": rev,
		"actor_id": actor_id,
		"is_current_player": true,
		"selected_unit_id": null,
		"actions": [{"schema_version": 1, "action_type": "end_turn", "actor_id": actor_id}],
	}


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame

	# --- activation guards ---
	OS.set_environment("EOM_CLOUD_ONE_PC_DEBUG", "")
	_check(not BootIntentScript.one_pc_debug_env_requested(), "unset env flag stays off")
	OS.set_environment("EOM_CLOUD_DEBUG", "1")
	_check(
		not BootIntentScript.one_pc_debug_env_requested(),
		"EOM_CLOUD_DEBUG stays logging-only (never activates the mode)"
	)
	OS.set_environment("EOM_CLOUD_DEBUG", "")
	OS.set_environment("EOM_CLOUD_ONE_PC_DEBUG", "1")
	_check(BootIntentScript.one_pc_debug_env_requested(), "EOM_CLOUD_ONE_PC_DEBUG=1 requests the mode")
	OS.set_environment("EOM_CLOUD_ONE_PC_DEBUG", "")

	_check(BootIntentScript.is_loopback_url("http://127.0.0.1:8000"), "127.0.0.1 is loopback")
	_check(BootIntentScript.is_loopback_url("http://localhost:8000/"), "localhost is loopback")
	_check(BootIntentScript.is_loopback_url("https://LOCALHOST"), "loopback check is case/scheme tolerant")
	_check(
		not BootIntentScript.is_loopback_url("https://cloud.thewizardsapprentice.org"),
		"remote host is not loopback"
	)
	_check(
		BootIntentScript.one_pc_debug_allowed("world_map", "http://127.0.0.1:8000"),
		"world_map + loopback allows the mode"
	)
	_check(
		not BootIntentScript.one_pc_debug_allowed("", "http://127.0.0.1:8000"),
		"legacy match kind never allows the mode"
	)
	_check(
		not BootIntentScript.one_pc_debug_allowed("world_map", "https://cloud.thewizardsapprentice.org"),
		"remote server never allows the mode"
	)

	# --- fresh create -> normal staging APIs -> ongoing (scripted session) ---
	var packed: PackedScene = load("res://cloud/world_play/cloud_world_play.tscn") as PackedScene
	var scene = packed.instantiate()
	var fake := FakeSession.new()
	scene.session = fake
	var create_resp := {
		"match_id": "m_debug",
		"host_token": "ht_debug_host",
		"snapshot": {"match_kind": "world_map"},
	}
	var out: Dictionary = await scene._run_one_pc_debug_staging(create_resp)
	_check(not out.has("_error"), "debug staging flow completes")
	_check(fake.match_id == "m_debug", "session bound to the created match")
	var expected_calls := [
		["claim", 0, ""],
		["claim", 1, ""],
		["list", "staging", ""],
		["faction", 0, "malmo", "st_seat_0"],
		["faction", 1, "vastervik", "st_seat_1"],
		["ready", 0, true, "st_seat_0"],
		["ready", 1, true, "st_seat_1"],
		["get_match", "ht_debug_host"],
	]
	_check(
		fake.calls == expected_calls,
		"exact staging sequence: claim both seats, first two DISTINCT advertised civs deterministically, ready both with their own seat tokens, ongoing fetched with the host token"
	)
	_check(
		typeof(out.get("snapshot", null)) == TYPE_DICTIONARY
			and (out["snapshot"] as Dictionary).get("player_factions", {}) == {"0": "malmo", "1": "vastervik"},
		"resulting ongoing snapshot carries both assigned civilizations"
	)
	_check(fake.seat_token == "ht_debug_host", "gameplay continues under host-token authority")

	# Host-token guard: a create response without a host token fails loudly.
	var fake2 := FakeSession.new()
	scene.session = fake2
	var bad: Dictionary = await scene._run_one_pc_debug_staging({"match_id": "m_x", "snapshot": {}})
	_check(
		str(bad.get("_error", "")) == "one_pc_debug_no_host_token",
		"missing host token aborts the debug staging flow"
	)
	_check(fake2.calls.is_empty(), "no staging calls happen without a host token")
	scene.free()

	# --- gameplay handoff in one client (state level) ---
	var st = WorldInteractionStateScript.new(-1)
	st.one_pc_debug = true
	var directives: Dictionary = st.apply_snapshot(_snapshot(0, 0))
	_check(st.my_actor_id == 0, "debug actor follows the snapshot's current player (Player 0)")
	_check(st.is_my_turn(), "debug mode is always the effective actor's turn")
	_check(directives == {"summary": true, "selection": false}, "debug apply directs a summary refetch")
	_check(not st.should_poll(false), "no waiting poll in debug mode (Player 0 current)")
	_check(
		st.classify_pick({"kind": "tile", "tile": Vector2i(1, 1)})
			== {"kind": "select_unit", "unit_id": 1},
		"Player 0's unit is controllable"
	)
	st.select_unit(1)
	var sum0: int = st.begin_summary_fetch()
	_check(st.accept_summary_legal_actions(sum0, _summary_response(0, 0)), "actor-0 summary accepted")
	_check(st.can_submit_end_turn(), "End Turn available for Player 0")

	# Stale previous-actor response: issued for actor 0, arrives after the
	# End Turn snapshot rebinds to actor 1.
	var stale_serial: int = st.begin_summary_fetch()
	directives = st.apply_snapshot(_snapshot(1, 1))
	_check(st.my_actor_id == 1, "accepted End Turn rebinds the effective actor to Player 1")
	_check(st.selected_unit_id == -1, "actor change invalidates the previous player's selection")
	_check(
		st.destination_tiles().is_empty() and not st.can_submit_end_turn(),
		"actor change clears BOTH served-legality slots"
	)
	_check(
		not st.accept_summary_legal_actions(stale_serial, _summary_response(1, 0)),
		"stale previous-actor response is discarded (actor binding)"
	)
	_check(directives == {"summary": true, "selection": false}, "new actor's summary refetch directed")
	var sum1: int = st.begin_summary_fetch()
	_check(
		st.accept_summary_legal_actions(sum1, _summary_response(1, 1)),
		"fresh summary for the NEW actor is accepted"
	)
	_check(st.can_submit_end_turn(), "End Turn available for Player 1 in the same client")
	_check(
		st.classify_pick({"kind": "tile", "tile": Vector2i(2, 14)})
			== {"kind": "select_unit", "unit_id": 3},
		"Player 1's unit becomes controllable in the same client"
	)
	_check(
		st.classify_pick({"kind": "tile", "tile": Vector2i(1, 1)}) == {"kind": "clear"},
		"Player 0's unit is now a foreign unit for the effective actor"
	)
	_check(not st.should_poll(false), "no waiting poll in debug mode (Player 1 current)")

	# End Turn back to Player 0.
	st.apply_snapshot(_snapshot(2, 0))
	_check(st.my_actor_id == 0, "End Turn back rebinds to Player 0")
	_check(st.status_text().begins_with("One-PC debug"), "debug status line names the mode")

	# --- mode off: fixed seat identity, unchanged multiplayer semantics ---
	var fixed = WorldInteractionStateScript.new(0)
	fixed.apply_snapshot(_snapshot(0, 0))
	_check(fixed.my_actor_id == 0, "normal mode keeps the boot seat identity")
	fixed.apply_snapshot(_snapshot(1, 1))
	_check(fixed.my_actor_id == 0, "normal mode NEVER follows the current player")
	_check(not fixed.is_my_turn(), "normal mode waits out of turn")
	_check(fixed.should_poll(false), "normal mode polls while waiting")
	_check(
		fixed.classify_pick({"kind": "tile", "tile": Vector2i(2, 14)}) == {"kind": "none"}
			and fixed.classify_pick({}) == {"kind": "none"},
		"normal mode stays fully inert out of turn (tile and miss)"
	)

	_finish()


func _check(condition: bool, label: String) -> void:
	_total += 1
	if condition:
		print("PASS ", label)
	else:
		_any_fail = true
		print("FAIL ", label)


func _finish() -> void:
	print("CloudOnePcDebug tests: %d checks" % _total)
	if _any_fail:
		print("FAIL")
		quit(1)
	else:
		print("PASS")
		quit(0)
