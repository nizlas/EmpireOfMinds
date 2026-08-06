# Headless: godot --headless --path game -s res://cloud/tests/test_world_interaction_state.gd
#
# N7d interaction state (game/cloud/world_play/world_interaction_state.gd):
# deterministic, network-free coverage of the locked contracts —
# - pick/selection semantics: own-unit tile selects, miss clears, cliff
#   leaves selection unchanged; OUT OF TURN every pick — including an empty
#   miss — is completely inert; enemy or empty tiles clear on the own turn;
# - served legality only: destination tiles and submissions map one-to-one
#   to the EXACT served move_unit rows (never client-derived; end_turn is
#   never constructed client-side);
# - independent summary/selection served state: both slots bound to the
#   current revision, usable at the same time, arriving in either order;
#   accepting one never clears the other; a newer snapshot clears both;
#   selection changes refetch only selection legality while a fresh
#   same-revision summary row stays usable;
# - locked freshness: responses bound to request serial + returned revision
#   + actor + requested selection mode (echoed selected_unit_id verified —
#   null for summary, the exact unit for selection); mismatched or stale
#   responses discarded unrendered; no submission across revisions;
# - End Turn gating on the summary-mode submit-ready row + revision match,
#   re-enabled from a NEWLY served summary row after an accepted move while
#   the moved unit stays selected;
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


func _selection_response(rev: int, unit_id, rows: Array, actor_id: int = 0) -> Dictionary:
	return {
		"match_id": "m_state",
		"revision": rev,
		"schema_version": 1,
		"actor_id": actor_id,
		"is_current_player": true,
		"selected_unit_id": unit_id,
		"selected_city_id": null,
		"selection_error": null,
		"actions": rows,
	}


func _summary_response(rev: int, echoed_selection = null, actor_id: int = 0) -> Dictionary:
	return {
		"match_id": "m_state",
		"revision": rev,
		"schema_version": 1,
		"actor_id": actor_id,
		"is_current_player": true,
		"selected_unit_id": echoed_selection,
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
	var directives: Dictionary = st.apply_snapshot(_snapshot(0, 0, _units()))
	_check(st.is_my_turn(), "actor 0 is current on the initial snapshot")
	_check(
		directives == {"summary": true, "selection": false},
		"initial own-turn apply directs a summary refetch only"
	)

	var waiting = WorldInteractionStateScript.new(1)
	_check(
		waiting.apply_snapshot(_snapshot(0, 0, _units())) == {"summary": false, "selection": false},
		"out-of-turn apply directs no refetch"
	)
	_check(waiting.should_poll(false), "out-of-turn seated state polls")
	_check(not waiting.should_poll(true), "no poll while a request is in flight")
	_check(not st.should_poll(false), "no poll during own turn")
	var unseated = WorldInteractionStateScript.new(-1)
	unseated.apply_snapshot(_snapshot(0, 0, _units()))
	_check(not unseated.should_poll(false), "no poll without a seat identity")

	# --- pick/selection semantics (own turn) ---
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
	_check(st.classify_pick({}) == {"kind": "clear"}, "miss clears on the own turn")
	_check(
		st.classify_pick(_tile_pick(2, 14)) == {"kind": "clear"},
		"enemy-unit tile pick clears (never selects a foreign unit)"
	)
	_check(
		st.classify_pick(_tile_pick(5, 5)) == {"kind": "clear"},
		"empty tile pick clears"
	)

	# --- REGRESSION: every out-of-turn pick is completely inert ---
	_check(
		waiting.classify_pick(_tile_pick(2, 14)) == {"kind": "none"},
		"out-of-turn own-unit pick is inert"
	)
	_check(
		waiting.classify_pick({}) == {"kind": "none"},
		"out-of-turn MISS is inert (turn ownership checked before miss-clear)"
	)
	_check(
		waiting.classify_pick({"kind": "cliff", "edge": [], "tiles": []}) == {"kind": "none"},
		"out-of-turn cliff pick is inert"
	)

	# --- REGRESSION: summary + selection in either order, both usable ---
	# Order A: selection first, then summary.
	var rows := [
		_move_row(1, [1, 1], [2, 1]),
		_move_row(1, [1, 1], [0, 1]),
		_move_row(1, [1, 1], [1, 0]),
	]
	var sel_serial: int = st.begin_selection_fetch()
	var sum_serial: int = st.begin_summary_fetch()
	_check(
		st.accept_selection_legal_actions(sel_serial, _selection_response(0, 1, rows)),
		"selection response accepted (selection-first order)"
	)
	_check(
		st.accept_summary_legal_actions(sum_serial, _summary_response(0)),
		"summary response accepted after the selection response"
	)
	_check(
		st.destination_tiles() == [Vector2i(2, 1), Vector2i(0, 1), Vector2i(1, 0)]
			and st.can_submit_end_turn(),
		"selection-first order: markers AND End Turn usable together"
	)
	# Order B: summary first, then selection — accepting one never clears
	# the other.
	var st_b = WorldInteractionStateScript.new(0)
	st_b.apply_snapshot(_snapshot(0, 0, _units()))
	st_b.select_unit(1)
	var b_sum: int = st_b.begin_summary_fetch()
	var b_sel: int = st_b.begin_selection_fetch()
	_check(
		st_b.accept_summary_legal_actions(b_sum, _summary_response(0)),
		"summary response accepted (summary-first order)"
	)
	_check(
		st_b.accept_selection_legal_actions(b_sel, _selection_response(0, 1, rows)),
		"selection response accepted after the summary response"
	)
	_check(
		st_b.can_submit_end_turn() and not st_b.destination_tiles().is_empty(),
		"summary-first order: End Turn AND markers usable together"
	)
	_check(st_b.end_turn_row == _end_turn_row(), "summary slot stores the exact served end_turn row")
	_check(
		st_b.move_row_for_tile(Vector2i(0, 1)) == rows[1],
		"submission row is the exact served row (deep equality)"
	)
	_check(
		st_b.classify_pick(_tile_pick(0, 1)) == {"kind": "submit_move", "action": rows[1]},
		"picking a marked destination submits that exact served row"
	)

	# --- selection change keeps the fresh same-revision summary row ---
	st_b.select_unit(2)
	_check(
		st_b.can_submit_end_turn(),
		"selection change retains the fresh same-revision summary end_turn row"
	)
	_check(st_b.destination_tiles().is_empty(), "selection change clears only the selection slot")

	# --- REGRESSION: accepted move -> newer revision -> refreshed markers
	# --- plus End Turn re-enabled from a NEWLY served summary row while the
	# --- moved unit stays selected ---
	var st_c = WorldInteractionStateScript.new(0)
	st_c.apply_snapshot(_snapshot(0, 0, _units()))
	st_c.select_unit(1)
	var c_sum: int = st_c.begin_summary_fetch()
	var c_sel: int = st_c.begin_selection_fetch()
	st_c.accept_summary_legal_actions(c_sum, _summary_response(0))
	st_c.accept_selection_legal_actions(c_sel, _selection_response(0, 1, rows))
	_check(st_c.can_submit_end_turn(), "pre-move: End Turn available")
	# Accepted move: unit 1 moved to (2, 1) hmm occupied by 2 — use (0, 1).
	var moved := _units()
	(moved[0] as Dictionary)["position"] = [0, 1]
	var post_move := _snapshot(1, 0, moved)
	_check(st_c.is_newer_snapshot(post_move), "accepted-move snapshot is newer")
	directives = st_c.apply_snapshot(post_move)
	_check(
		directives == {"summary": true, "selection": true},
		"post-move apply directs BOTH summary and selection refetches"
	)
	_check(st_c.selected_unit_id == 1, "moved unit stays selected")
	_check(
		st_c.destination_tiles().is_empty() and not st_c.can_submit_end_turn(),
		"newer snapshot clears BOTH served slots immediately"
	)
	var c_sum2: int = st_c.begin_summary_fetch()
	var c_sel2: int = st_c.begin_selection_fetch()
	var rows2 := [_move_row(1, [0, 1], [1, 1])]
	_check(
		st_c.accept_summary_legal_actions(c_sum2, _summary_response(1)),
		"post-move summary refetch accepted at the new revision"
	)
	_check(
		st_c.accept_selection_legal_actions(c_sel2, _selection_response(1, 1, rows2)),
		"post-move selection refetch accepted at the new revision"
	)
	_check(
		st_c.destination_tiles() == [Vector2i(1, 1)] and st_c.can_submit_end_turn(),
		"post-move: refreshed markers AND End Turn re-enabled while the unit stays selected"
	)

	# --- REGRESSION: mismatched echoed selection is discarded ---
	var st_d = WorldInteractionStateScript.new(0)
	st_d.apply_snapshot(_snapshot(0, 0, _units()))
	st_d.select_unit(1)
	var d_sum: int = st_d.begin_summary_fetch()
	_check(
		not st_d.accept_summary_legal_actions(d_sum, _summary_response(0, 1)),
		"summary response echoing a unit selection is discarded"
	)
	_check(not st_d.can_submit_end_turn(), "discarded summary response stores nothing")
	var d_sel: int = st_d.begin_selection_fetch()
	_check(
		not st_d.accept_selection_legal_actions(d_sel, _selection_response(0, 2, rows)),
		"selection response echoing the WRONG unit is discarded"
	)
	var d_sel2: int = st_d.begin_selection_fetch()
	_check(
		not st_d.accept_selection_legal_actions(d_sel2, _selection_response(0, null, rows)),
		"selection response echoing null (summary shape) is discarded"
	)
	_check(st_d.destination_tiles().is_empty(), "discarded selection responses render nothing")

	# --- freshness: actor binding ---
	var d_sum2: int = st_d.begin_summary_fetch()
	_check(
		not st_d.accept_summary_legal_actions(d_sum2, _summary_response(0, null, 1)),
		"response for a different actor is discarded"
	)

	# --- freshness: stale serial ---
	var e1: int = st_d.begin_selection_fetch()
	var e2: int = st_d.begin_selection_fetch()
	_check(
		not st_d.accept_selection_legal_actions(e1, _selection_response(0, 1, rows)),
		"a superseded selection request serial is discarded"
	)
	_check(
		st_d.accept_selection_legal_actions(e2, _selection_response(0, 1, rows)),
		"the newest selection request serial is accepted"
	)
	var e3: int = st_d.begin_summary_fetch()
	var e4: int = st_d.begin_summary_fetch()
	_check(
		not st_d.accept_summary_legal_actions(e3, _summary_response(0)),
		"a superseded summary request serial is discarded"
	)
	_check(
		st_d.accept_summary_legal_actions(e4, _summary_response(0)),
		"the newest summary request serial is accepted"
	)

	# --- freshness: revision mismatch + selection changed in flight ---
	var f1: int = st_d.begin_selection_fetch()
	_check(
		not st_d.accept_selection_legal_actions(f1, _selection_response(7, 1, rows)),
		"a selection response for a different revision is discarded"
	)
	var f2: int = st_d.begin_summary_fetch()
	_check(
		not st_d.accept_summary_legal_actions(f2, _summary_response(7)),
		"a summary response for a different revision is discarded"
	)
	var f3: int = st_d.begin_selection_fetch()
	st_d.select_unit(2)
	_check(
		not st_d.accept_selection_legal_actions(f3, _selection_response(0, 1, rows)),
		"a selection response for a superseded selection is discarded"
	)
	_check(st_d.destination_tiles().is_empty(), "no stale rows are ever rendered")
	_check(
		st_d.can_submit_end_turn(),
		"selection churn never invalidates the independent summary slot"
	)
	_check(
		st_d.move_row_for_tile(Vector2i(0, 1)).is_empty(),
		"a row bound to another revision/selection can never be submitted"
	)

	# --- selection invalidated by the newer snapshot ---
	var killed := _units()
	killed.remove_at(0)
	st_d.select_unit(1)
	directives = st_d.apply_snapshot(_snapshot(2, 0, killed))
	_check(st_d.selected_unit_id == -1, "selection clears when the unit no longer exists")
	_check(
		directives == {"summary": true, "selection": false},
		"cleared selection directs a summary-only refetch on the own turn"
	)

	# --- turn change clears selection and stops action input ---
	var st2 = WorldInteractionStateScript.new(0)
	st2.apply_snapshot(_snapshot(0, 0, _units()))
	st2.select_unit(2)
	directives = st2.apply_snapshot(_snapshot(1, 1, _units()))
	_check(st2.selected_unit_id == -1, "selection clears when the turn passes to the opponent")
	_check(
		directives == {"summary": false, "selection": false},
		"no refetch out of turn"
	)
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
