# Headless: godot --headless --path game -s res://cloud/tests/test_world_interaction_state.gd
#
# N7d interaction state (game/cloud/world_play/world_interaction_state.gd):
# deterministic, network-free coverage of the locked contracts —
# - pick/selection semantics: own-unit tile selects, miss clears, cliff
#   leaves selection unchanged, out-of-turn picks change nothing, enemy or
#   empty tiles clear;
# - served legality only: destination tiles and submissions map one-to-one
#   to the EXACT served move_unit rows (never client-derived);
# - locked freshness: responses bound to serial + revision + still-current
#   selection; stale responses discarded; newer snapshots clear served rows
#   immediately and direct a refetch; no submission when the served rows'
#   revision differs from the held snapshot revision;
# - End Turn gating on the summary-mode submit-ready row + revision match;
# - conservative out-of-turn poll gating.
extends SceneTree

const WorldInteractionStateScript = preload("res://cloud/world_play/world_interaction_state.gd")
const CloudTurnOwnershipScript = preload("res://cloud/cloud_turn_ownership.gd")
const CloudPlayerIdentityScript = preload("res://cloud/cloud_player_identity.gd")

var _total := 0
var _any_fail := false


func _snapshot(rev: int, current_index: int, units: Array) -> Dictionary:
	return {
		"match_id": "m_state",
		"schema_version": 3,
		"match_kind": "world_map",
		"map": {"map_id": "handdrawn_test_map_full_01", "schema_version": 1, "content_hash": "x"},
		"revision": rev,
		"turn_state": {"players": [0, 1], "current_index": current_index, "turn_number": 1},
		"units": units,
	}


func _units() -> Array:
	return [
		{"id": 1, "owner_id": 0, "position": [1, 1], "type_id": "settler"},
		{"id": 2, "owner_id": 0, "position": [2, 1], "type_id": "warrior"},
		{"id": 3, "owner_id": 1, "position": [2, 14], "type_id": "settler"},
		{"id": 4, "owner_id": 1, "position": [2, 13], "type_id": "warrior"},
	]


func _move_row(unit_id: int, from: Array, to: Array) -> Dictionary:
	return {
		"schema_version": 1,
		"action_type": "move_unit",
		"actor_id": 0,
		"unit_id": unit_id,
		"from": from,
		"to": to,
	}


func _end_turn_row() -> Dictionary:
	return {"schema_version": 1, "action_type": "end_turn", "actor_id": 0}


func _selection_response(rev: int, unit_id: int, rows: Array) -> Dictionary:
	return {
		"match_id": "m_state",
		"revision": rev,
		"schema_version": 1,
		"actor_id": 0,
		"is_current_player": true,
		"selected_unit_id": unit_id,
		"selected_city_id": null,
		"selection_error": null,
		"actions": rows,
	}


func _summary_response(rev: int) -> Dictionary:
	return {
		"match_id": "m_state",
		"revision": rev,
		"schema_version": 1,
		"actor_id": 0,
		"is_current_player": true,
		"selected_unit_id": null,
		"selected_city_id": null,
		"selection_error": null,
		"actions": [_end_turn_row()],
		"unit_summaries": [
			{"unit_id": 1, "legal_action_count": 4},
			{"unit_id": 2, "legal_action_count": 3},
		],
		"city_summaries": [],
	}


func _tile_pick(q: int, r: int) -> Dictionary:
	return {"kind": "tile", "tile": Vector2i(q, r)}


func _init() -> void:
	CloudPlayerIdentityScript.clear_registry()

	# --- snapshot apply + refetch directives ---
	var st = WorldInteractionStateScript.new(0)
	var directive: String = st.apply_snapshot(_snapshot(0, 0, _units()))
	_check(st.is_my_turn(), "actor 0 is current on the initial snapshot")
	_check(directive == "summary", "initial apply with no selection directs a summary refetch")

	var waiting = WorldInteractionStateScript.new(1)
	_check(
		waiting.apply_snapshot(_snapshot(0, 0, _units())) == "",
		"out-of-turn apply directs no refetch"
	)
	_check(waiting.should_poll(false), "out-of-turn seated state polls")
	_check(not waiting.should_poll(true), "no poll while a request is in flight")
	_check(not st.should_poll(false), "no poll during own turn")
	var unseated = WorldInteractionStateScript.new(-1)
	unseated.apply_snapshot(_snapshot(0, 0, _units()))
	_check(not unseated.should_poll(false), "no poll without a seat identity")

	# --- pick/selection semantics ---
	_check(
		st.classify_pick(_tile_pick(1, 1)) == {"kind": "select_unit", "unit_id": 1},
		"own-unit tile pick selects that unit"
	)
	st.select_unit(1)
	_check(st.selected_tile() == Vector2i(1, 1), "selected tile mirrors the unit position")
	_check(st.classify_pick(_tile_pick(1, 1)) == {"kind": "none"}, "re-picking the selected unit is a no-op")
	_check(
		st.classify_pick({"kind": "cliff", "edge": [], "tiles": []}) == {"kind": "none"},
		"cliff pick leaves selection unchanged"
	)
	_check(st.classify_pick({}) == {"kind": "clear"}, "miss clears")
	_check(
		st.classify_pick(_tile_pick(2, 14)) == {"kind": "clear"},
		"enemy-unit tile pick clears (never selects a foreign unit)"
	)
	_check(
		st.classify_pick(_tile_pick(5, 5)) == {"kind": "clear"},
		"empty tile pick clears"
	)
	_check(
		waiting.classify_pick(_tile_pick(2, 14)) == {"kind": "none"},
		"out-of-turn pick changes nothing (action input disabled)"
	)

	# --- served rows: exact one-to-one mapping ---
	var rows := [
		_move_row(1, [1, 1], [2, 1]),
		_move_row(1, [1, 1], [0, 1]),
		_move_row(1, [1, 1], [1, 0]),
	]
	var serial: int = st.begin_legal_fetch()
	_check(
		st.accept_legal_actions(serial, _selection_response(0, 1, rows)),
		"fresh selection-mode response is accepted"
	)
	_check(
		st.destination_tiles() == [Vector2i(2, 1), Vector2i(0, 1), Vector2i(1, 0)],
		"destination tiles are exactly the served rows' to tiles, in order"
	)
	_check(
		st.move_row_for_tile(Vector2i(0, 1)) == rows[1],
		"submission row is the exact served row (deep equality)"
	)
	_check(st.move_row_for_tile(Vector2i(9, 9)).is_empty(), "unmarked tile has no row")
	_check(
		st.classify_pick(_tile_pick(0, 1)) == {"kind": "submit_move", "action": rows[1]},
		"picking a marked destination submits that exact served row"
	)

	# --- freshness: stale serial ---
	var s1: int = st.begin_legal_fetch()
	var s2: int = st.begin_legal_fetch()
	_check(
		not st.accept_legal_actions(s1, _selection_response(0, 1, rows)),
		"a superseded request serial is discarded"
	)
	_check(
		st.accept_legal_actions(s2, _selection_response(0, 1, rows)),
		"the newest request serial is accepted"
	)

	# --- freshness: revision mismatch ---
	var s3: int = st.begin_legal_fetch()
	_check(
		not st.accept_legal_actions(s3, _selection_response(7, 1, rows)),
		"a response for a different revision is discarded"
	)

	# --- freshness: selection changed while in flight ---
	var s4: int = st.begin_legal_fetch()
	st.select_unit(2)
	_check(
		not st.accept_legal_actions(s4, _selection_response(0, 1, rows)),
		"a response for a superseded selection is discarded"
	)
	_check(st.destination_tiles().is_empty(), "no stale rows are ever rendered")

	# --- freshness: newer snapshot clears rows and directs refetch ---
	st.select_unit(1)
	var s5: int = st.begin_legal_fetch()
	st.accept_legal_actions(s5, _selection_response(0, 1, rows))
	_check(not st.destination_tiles().is_empty(), "rows held before the newer snapshot")
	var moved_units := _units()
	(moved_units[3] as Dictionary)["position"] = [3, 13]
	_check(st.is_newer_snapshot(_snapshot(1, 0, moved_units)), "revision 1 is newer than held 0")
	directive = st.apply_snapshot(_snapshot(1, 0, moved_units))
	_check(st.destination_tiles().is_empty(), "newer snapshot clears served rows immediately")
	_check(directive == "selection", "still-valid selection directs a selection refetch")
	_check(st.selected_unit_id == 1, "still-owned selection survives the newer snapshot")
	_check(
		st.move_row_for_tile(Vector2i(0, 1)).is_empty(),
		"a row bound to revision 0 can never be submitted at revision 1"
	)

	# --- selection invalidated by the newer snapshot ---
	var killed := _units()
	killed.remove_at(0)
	directive = st.apply_snapshot(_snapshot(2, 0, killed))
	_check(st.selected_unit_id == -1, "selection clears when the unit no longer exists")
	_check(directive == "summary", "cleared selection directs a summary refetch on own turn")

	# --- End Turn gating ---
	var s6: int = st.begin_legal_fetch()
	_check(
		st.accept_legal_actions(s6, _summary_response(2)),
		"fresh summary-mode response is accepted"
	)
	_check(st.end_turn_row == _end_turn_row(), "summary mode stores the exact end_turn row")
	_check(st.can_submit_end_turn(), "End Turn submits with a fresh summary row")
	st.apply_snapshot(_snapshot(3, 0, killed))
	_check(
		not st.can_submit_end_turn(),
		"End Turn is blocked when the summary row's revision is stale"
	)

	# --- turn change clears selection and stops action input ---
	var st2 = WorldInteractionStateScript.new(0)
	st2.apply_snapshot(_snapshot(0, 0, _units()))
	st2.select_unit(2)
	directive = st2.apply_snapshot(_snapshot(1, 1, _units()))
	_check(st2.selected_unit_id == -1, "selection clears when the turn passes to the opponent")
	_check(directive == "", "no refetch out of turn")
	_check(st2.should_poll(false), "waiting poll resumes after the turn passes")
	_check(
		st2.classify_pick(_tile_pick(1, 1)) == {"kind": "none"},
		"own-unit pick is inert out of turn"
	)

	# --- status text (existing display-name helpers; no factions registered) ---
	_check(
		st2.status_text().begins_with(CloudTurnOwnershipScript.WAITING_STATUS_TEXT),
		"waiting status reuses the shipped waiting text"
	)
	var st3 = WorldInteractionStateScript.new(0)
	st3.apply_snapshot(_snapshot(0, 0, _units()))
	_check(st3.status_text().begins_with("Your turn"), "own turn status says so")
	_check(
		WorldInteractionStateScript.player_label(0) == "Player 0",
		"player label falls back to Player N without faction registry"
	)
	var st4 = WorldInteractionStateScript.new(-1)
	st4.apply_snapshot(_snapshot(0, 0, _units()))
	_check(
		st4.status_text().begins_with("No seat identity"),
		"missing seat identity is reported instead of silently spectating"
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
	print("WorldInteractionState tests: %d checks" % _total)
	if _any_fail:
		print("FAIL")
		quit(1)
	else:
		print("PASS")
		quit(0)
