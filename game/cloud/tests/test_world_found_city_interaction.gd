# Headless: godot --headless --path game -s res://cloud/tests/test_world_found_city_interaction.gd
#
# N8a client founding/selection: served found_city availability + submission
# of the exact row, authoritative snapshot reconciliation (settler consumed,
# city appears), safe selection clear when the selected settler vanishes,
# and the locked shared-tile unit↔city selection cycle. No optimistic city
# create or settler consume.
extends SceneTree

const WorldInteractionStateScript = preload("res://cloud/world_play/world_interaction_state.gd")

var _total := 0
var _any_fail := false


func _snapshot(rev: int, units: Array, cities: Array = [], current_index: int = 0) -> Dictionary:
	return {
		"match_id": "m_n8a",
		"schema_version": 3,
		"match_kind": "world_map",
		"map": {"map_id": "handdrawn_test_map_full_01", "schema_version": 1, "content_hash": "x"},
		"revision": rev,
		"turn_state": {"players": [0, 1], "current_index": current_index, "turn_number": 1},
		"units": units,
		"cities": cities,
		"next_city_id": cities.size() + 1,
	}


func _spawn_units() -> Array:
	return [
		{"id": 1, "owner_id": 0, "position": [1, 1], "type_id": "settler", "current_hp": 100, "has_attacked": false},
		{"id": 2, "owner_id": 0, "position": [2, 1], "type_id": "warrior", "current_hp": 100, "has_attacked": false},
	]


func _found_row(unit_id: int = 1, pos: Array = [1, 1]) -> Dictionary:
	return {
		"schema_version": 1,
		"action_type": "found_city",
		"actor_id": 0,
		"unit_id": unit_id,
		"position": pos,
	}


func _selection_response(rev: int, unit_id, rows: Array) -> Dictionary:
	return {
		"match_id": "m_n8a",
		"revision": rev,
		"schema_version": 1,
		"actor_id": 0,
		"is_current_player": true,
		"selected_unit_id": unit_id,
		"selected_city_id": null,
		"selection_error": null,
		"actions": rows,
	}


func _city_selection_response(rev: int, city_id: int) -> Dictionary:
	return {
		"match_id": "m_n8a",
		"revision": rev,
		"schema_version": 1,
		"actor_id": 0,
		"is_current_player": true,
		"selected_unit_id": null,
		"selected_city_id": city_id,
		"selection_error": null,
		"actions": [],
	}


func _tile_pick(q: int, r: int) -> Dictionary:
	return {"kind": "tile", "tile": Vector2i(q, r)}


func _init() -> void:
	_run()


func _run() -> void:
	_test_found_city_served_row_and_submit()
	_test_snapshot_reconcile_consumes_settler_and_clears_selection()
	_test_shared_tile_selection_cycle()
	_test_city_only_selection_and_status()
	_test_no_optimistic_found_city_construction()
	_test_foreign_city_pick_clears_never_selects()
	_test_own_unit_on_enemy_city_never_cycles_to_city()
	_test_lost_city_ownership_clears_selection()
	_test_one_pc_actor_switch_clears_previous_city_selection()
	_finish()


func _test_found_city_served_row_and_submit() -> void:
	var st = WorldInteractionStateScript.new(0)
	st.apply_snapshot(_snapshot(0, _spawn_units()))
	st.select_unit(1)
	var serial: int = st.begin_selection_fetch()
	_check(
		st.accept_selection_legal_actions(
			serial,
			_selection_response(0, 1, [_found_row(), {"schema_version": 1, "action_type": "move_unit", "actor_id": 0, "unit_id": 1, "from": [1, 1], "to": [1, 0]}]),
		),
		"selection response with found_city accepted"
	)
	_check(st.can_submit_found_city(), "Found City available from served row")
	var row: Dictionary = st.found_city_row()
	_check(row == _found_row(), "found_city_row is the exact served payload")
	# Stale revision clears submitability.
	st.apply_snapshot(_snapshot(1, _spawn_units()))
	st.select_unit(1)
	_check(not st.can_submit_found_city(), "stale found_city row never submits after revision advance")


func _test_snapshot_reconcile_consumes_settler_and_clears_selection() -> void:
	var st = WorldInteractionStateScript.new(0)
	st.apply_snapshot(_snapshot(0, _spawn_units()))
	st.select_unit(1)
	_check(st.selected_unit_id == 1, "settler selected before founding")
	var serial: int = st.begin_selection_fetch()
	st.accept_selection_legal_actions(serial, _selection_response(0, 1, [_found_row()]))
	_check(st.can_submit_found_city(), "served found_city ready before accept")

	# Authoritative post-founding snapshot: settler gone, city present.
	var after_units := [
		{"id": 2, "owner_id": 0, "position": [2, 1], "type_id": "warrior", "current_hp": 100, "has_attacked": false},
	]
	var after_cities := [
		{"id": 1, "owner_id": 0, "position": [1, 1], "name": "Capital"},
	]
	var directives: Dictionary = st.apply_snapshot(_snapshot(1, after_units, after_cities))
	_check(st.selected_unit_id == WorldInteractionStateScript.NO_SELECTION, "consumed settler selection cleared safely")
	_check(st.cities.size() == 1, "authoritative city mirrored into interaction state")
	_check(st.city_by_id(1).get("name", "") == "Capital", "city name from snapshot")
	_check(st.unit_by_id(1).is_empty(), "consumed settler absent from units mirror")
	_check(not st.can_submit_found_city(), "found_city unavailable after consume")
	_check(bool(directives.get("summary", false)), "own-turn summary refetch after founding")
	_check(not bool(directives.get("selection", false)), "no selection refetch when unit selection cleared")


func _test_shared_tile_selection_cycle() -> void:
	var units := [
		{"id": 2, "owner_id": 0, "position": [1, 1], "type_id": "warrior", "current_hp": 100, "has_attacked": false},
	]
	var cities := [
		{"id": 1, "owner_id": 0, "position": [1, 1], "name": "Capital"},
	]
	var st = WorldInteractionStateScript.new(0)
	st.apply_snapshot(_snapshot(0, units, cities))

	var d1: Dictionary = st.classify_pick(_tile_pick(1, 1))
	_check(str(d1.get("kind", "")) == WorldInteractionStateScript.PICK_SELECT_UNIT, "first shared-tile pick selects unit")
	_check(int(d1.get("unit_id", -1)) == 2, "first pick unit id is the warrior")
	st.select_unit(2)

	var d2: Dictionary = st.classify_pick(_tile_pick(1, 1))
	_check(str(d2.get("kind", "")) == WorldInteractionStateScript.PICK_SELECT_CITY, "second pick cycles to city")
	_check(int(d2.get("city_id", -1)) == 1, "second pick city id")
	st.select_city(1)
	_check(st.selected_unit_id == WorldInteractionStateScript.NO_SELECTION, "city select clears unit")
	_check(st.selected_city_id == 1, "city selected")

	var d3: Dictionary = st.classify_pick(_tile_pick(1, 1))
	_check(str(d3.get("kind", "")) == WorldInteractionStateScript.PICK_SELECT_UNIT, "third pick cycles back to unit")
	st.select_unit(2)

	# Clear resets the cycle — next pick is unit again.
	st.clear_selection()
	var d4: Dictionary = st.classify_pick(_tile_pick(1, 1))
	_check(str(d4.get("kind", "")) == WorldInteractionStateScript.PICK_SELECT_UNIT, "after clear, first pick is unit again")


func _test_city_only_selection_and_status() -> void:
	var cities := [
		{"id": 1, "owner_id": 0, "position": [1, 1], "name": "Capital"},
	]
	var st = WorldInteractionStateScript.new(0)
	st.apply_snapshot(_snapshot(0, [], cities))
	var d: Dictionary = st.classify_pick(_tile_pick(1, 1))
	_check(str(d.get("kind", "")) == WorldInteractionStateScript.PICK_SELECT_CITY, "city-only tile selects city")
	st.select_city(1)
	_check(st.selected_tile() == Vector2i(1, 1), "selected city tile for highlight")
	_check(
		st.selected_city_status_line().contains("Capital"),
		"status line shows authoritative city name"
	)
	var serial: int = st.begin_selection_fetch()
	_check(
		st.accept_selection_legal_actions(serial, _city_selection_response(0, 1)),
		"city selection legal-actions (empty until N8b) accepted"
	)
	_check(not st.can_submit_found_city(), "city selection never enables Found City")


func _test_no_optimistic_found_city_construction() -> void:
	var st = WorldInteractionStateScript.new(0)
	st.apply_snapshot(_snapshot(0, _spawn_units()))
	st.select_unit(1)
	# Without a served row, Found City stays unavailable — client never builds one.
	_check(st.found_city_row().is_empty(), "no client-built found_city without served row")
	_check(not st.can_submit_found_city(), "Found City disabled without served row")
	_check(st.cities.is_empty(), "cities mirror stays empty until snapshot carries them")


func _test_foreign_city_pick_clears_never_selects() -> void:
	# Enemy city remains in the cities mirror (visibility) but picking its
	# tile follows the established foreign/empty clear path — never selects.
	var cities := [
		{"id": 1, "owner_id": 1, "position": [3, 3], "name": "Enemy Capital"},
	]
	var st = WorldInteractionStateScript.new(0)
	st.apply_snapshot(_snapshot(0, [], cities))
	_check(st.cities.size() == 1, "foreign city stays visible in the cities mirror")
	_check(
		st.city_id_at(Vector2i(3, 3)) == WorldInteractionStateScript.NO_SELECTION,
		"city_id_at ignores foreign cities (own-only, like units)"
	)
	var d: Dictionary = st.classify_pick(_tile_pick(3, 3))
	_check(
		str(d.get("kind", "")) == WorldInteractionStateScript.PICK_CLEAR,
		"enemy-city-only tile clears like foreign/empty (never selects)"
	)
	_check(st.selected_city_id == WorldInteractionStateScript.NO_SELECTION, "no city selected after foreign pick")


func _test_own_unit_on_enemy_city_never_cycles_to_city() -> void:
	# Own unit sharing an enemy city tile: select the unit, never cycle into
	# the enemy city on repeated picks (cycle is own-unit + own-city only).
	var units := [
		{"id": 2, "owner_id": 0, "position": [3, 3], "type_id": "warrior", "current_hp": 100, "has_attacked": false},
	]
	var cities := [
		{"id": 1, "owner_id": 1, "position": [3, 3], "name": "Enemy Capital"},
	]
	var st = WorldInteractionStateScript.new(0)
	st.apply_snapshot(_snapshot(0, units, cities))
	var d1: Dictionary = st.classify_pick(_tile_pick(3, 3))
	_check(str(d1.get("kind", "")) == WorldInteractionStateScript.PICK_SELECT_UNIT, "shared enemy-city tile selects own unit")
	_check(int(d1.get("unit_id", -1)) == 2, "own warrior selected on enemy city tile")
	st.select_unit(2)
	var d2: Dictionary = st.classify_pick(_tile_pick(3, 3))
	_check(
		str(d2.get("kind", "")) == WorldInteractionStateScript.PICK_NONE,
		"repeat pick on own-unit/enemy-city tile never cycles into the enemy city"
	)
	_check(st.selected_city_id == WorldInteractionStateScript.NO_SELECTION, "enemy city never becomes selection")
	_check(st.selected_unit_id == 2, "own unit selection retained on inert repeat pick")


func _test_lost_city_ownership_clears_selection() -> void:
	var cities := [
		{"id": 1, "owner_id": 0, "position": [1, 1], "name": "Capital"},
	]
	var st = WorldInteractionStateScript.new(0)
	st.apply_snapshot(_snapshot(0, [], cities))
	st.select_city(1)
	_check(st.selected_city_id == 1, "own city selected before ownership change")

	# Same-owner snapshot update: selection survives and selection refetch is directed.
	var same_owner_dirs: Dictionary = st.apply_snapshot(_snapshot(1, [], cities))
	_check(st.selected_city_id == 1, "still-owned city selection survives same-owner snapshot update")
	_check(bool(same_owner_dirs.get("selection", false)), "selection refetch directed for surviving own city")

	# Ownership lost (city still present under the other player): clear.
	var flipped := [
		{"id": 1, "owner_id": 1, "position": [1, 1], "name": "Capital"},
	]
	var lost_dirs: Dictionary = st.apply_snapshot(_snapshot(2, [], flipped))
	_check(
		st.selected_city_id == WorldInteractionStateScript.NO_SELECTION,
		"lost ownership clears selected_city_id (city may still exist)"
	)
	_check(st.cities.size() == 1, "city remains mirrored after ownership loss")
	_check(not bool(lost_dirs.get("selection", false)), "no selection refetch after ownership clear")


func _test_one_pc_actor_switch_clears_previous_city_selection() -> void:
	# One-PC rebinds my_actor_id to the new current player BEFORE selection
	# validation; without an ownership check the previous actor's city would
	# survive and trigger an invalid selection fetch.
	var cities := [
		{"id": 1, "owner_id": 0, "position": [1, 1], "name": "Capital"},
		{"id": 2, "owner_id": 1, "position": [2, 2], "name": "Settlement 2"},
	]
	var st = WorldInteractionStateScript.new(0)
	st.one_pc_debug = true
	st.apply_snapshot(_snapshot(0, [], cities, 0))
	_check(st.my_actor_id == 0, "one-PC starts as Player 0")
	st.select_city(1)
	_check(st.selected_city_id == 1, "Player 0 city selected before End Turn")

	var dirs: Dictionary = st.apply_snapshot(_snapshot(1, [], cities, 1))
	_check(st.my_actor_id == 1, "one-PC rebinds to Player 1 on turn change")
	_check(
		st.selected_city_id == WorldInteractionStateScript.NO_SELECTION,
		"previous actor's city selection cleared on one-PC rebind"
	)
	_check(bool(dirs.get("summary", false)), "new actor summary refetch directed")
	_check(
		not bool(dirs.get("selection", false)),
		"no selection refetch for the previous actor's city after one-PC rebind"
	)
	# New actor may select their own city; foreign city tile still clears.
	var own_pick: Dictionary = st.classify_pick(_tile_pick(2, 2))
	_check(
		str(own_pick.get("kind", "")) == WorldInteractionStateScript.PICK_SELECT_CITY,
		"new actor can select their own city"
	)
	var foreign_pick: Dictionary = st.classify_pick(_tile_pick(1, 1))
	_check(
		str(foreign_pick.get("kind", "")) == WorldInteractionStateScript.PICK_CLEAR,
		"previous actor's city is foreign after one-PC rebind"
	)


func _check(cond: bool, msg: String) -> void:
	_total += 1
	if cond:
		print("PASS: %s" % msg)
	else:
		_any_fail = true
		print("FAIL: %s" % msg)
		push_error("FAIL: %s" % msg)


func _finish() -> void:
	if _any_fail:
		print("test_world_found_city_interaction: FAILED (%d checks)" % _total)
		quit(1)
	print("test_world_found_city_interaction: OK (%d checks)" % _total)
	quit(0)
