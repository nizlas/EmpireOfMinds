# Headless: godot --headless --path game -s res://cloud/tests/test_world_city_production_interaction.gd
#
# N8b client production selection: choices come exclusively from served
# set_city_production rows, clicks submit the exact served payload, status
# shows snapshot progress/cost, snapshot reconcile is authoritative (no
# optimistic project changes), and stale rows clear on revision / selection /
# actor change.
extends SceneTree

const WorldInteractionStateScript = preload("res://cloud/world_play/world_interaction_state.gd")

var _total := 0
var _any_fail := false


func _snapshot(rev: int, cities: Array, current_index: int = 0) -> Dictionary:
	return {
		"match_id": "m_n8b",
		"schema_version": 3,
		"match_kind": "world_map",
		"map": {"map_id": "handdrawn_test_map_full_01", "schema_version": 1, "content_hash": "x"},
		"revision": rev,
		"turn_state": {"players": [0, 1], "current_index": current_index, "turn_number": 1},
		"units": [],
		"cities": cities,
		"next_city_id": cities.size() + 1,
	}


func _city(
	id: int = 1,
	owner_id: int = 0,
	project = null,
) -> Dictionary:
	return {
		"id": id,
		"owner_id": owner_id,
		"position": [1, 1],
		"name": "Capital",
		"current_project": project,
	}


func _prod_row(project_id: String, city_id: int = 1, actor_id: int = 0) -> Dictionary:
	return {
		"schema_version": 2,
		"action_type": "set_city_production",
		"actor_id": actor_id,
		"city_id": city_id,
		"project_id": project_id,
	}


func _city_selection_response(rev: int, city_id: int, rows: Array) -> Dictionary:
	return {
		"match_id": "m_n8b",
		"revision": rev,
		"schema_version": 1,
		"actor_id": 0,
		"is_current_player": true,
		"selected_unit_id": null,
		"selected_city_id": city_id,
		"selection_error": null,
		"actions": rows,
	}


func _init() -> void:
	_run()


func _run() -> void:
	_test_served_rows_only_and_exact_submit()
	_test_progress_cost_display_from_snapshot()
	_test_snapshot_reconcile_no_optimistic_project()
	_test_stale_rows_clear_on_revision_selection_actor()
	_finish()


func _test_served_rows_only_and_exact_submit() -> void:
	var st = WorldInteractionStateScript.new(0)
	st.apply_snapshot(_snapshot(0, [_city()]))
	st.select_city(1)
	_check(st.production_rows().is_empty(), "no production rows without a served response")
	var serial: int = st.begin_selection_fetch()
	var warrior := _prod_row("produce_unit:warrior")
	var settler := _prod_row("produce_unit:settler")
	_check(
		st.accept_selection_legal_actions(
			serial,
			_city_selection_response(0, 1, [settler, warrior]),
		),
		"city selection response with production rows accepted"
	)
	var rows: Array = st.production_rows()
	_check(rows.size() == 2, "exactly the served production rows are exposed")
	_check(rows[0] == settler and rows[1] == warrior, "served order preserved (legacy none/sorted)")
	var exact: Dictionary = st.production_row_for_project_id("produce_unit:warrior")
	_check(exact == warrior, "production_row_for_project_id returns the exact served payload")
	_check(st.can_submit_production_row(exact), "exact served row is submittable")
	_check(
		not st.can_submit_production_row(_prod_row("produce_unit:warrior")),
		"a client-built lookalike row is never submittable"
	)
	_check(
		st.production_row_for_project_id("none").is_empty(),
		"unserved project_id yields no row"
	)


func _test_progress_cost_display_from_snapshot() -> void:
	var idle = WorldInteractionStateScript.new(0)
	idle.apply_snapshot(_snapshot(0, [_city()]))
	idle.select_city(1)
	_check(
		idle.selected_city_status_line().contains("production: none"),
		"idle city status shows production none"
	)

	var producing = WorldInteractionStateScript.new(0)
	producing.apply_snapshot(
		_snapshot(
			0,
			[
				_city(
					1,
					0,
					{"project_id": "produce_unit:settler", "progress": 1, "cost": 2},
				)
			]
		)
	)
	producing.select_city(1)
	var line: String = producing.selected_city_status_line()
	_check(line.contains("produce_unit:settler"), "status shows authoritative project_id")
	_check(line.contains("1/2"), "status shows snapshot progress/cost")


func _test_snapshot_reconcile_no_optimistic_project() -> void:
	var st = WorldInteractionStateScript.new(0)
	st.apply_snapshot(_snapshot(0, [_city()]))
	st.select_city(1)
	var serial: int = st.begin_selection_fetch()
	st.accept_selection_legal_actions(
		serial,
		_city_selection_response(0, 1, [_prod_row("produce_unit:warrior")]),
	)
	_check(st.can_submit_production_row(st.production_row_for_project_id("produce_unit:warrior")), "served row ready")
	# Client never mutates cities locally — only an authoritative snapshot does.
	_check(st.city_by_id(1).get("current_project", null) == null, "no optimistic project before snapshot")

	var after := [
		_city(1, 0, {"project_id": "produce_unit:warrior", "progress": 0, "cost": 2}),
	]
	var dirs: Dictionary = st.apply_snapshot(_snapshot(1, after))
	_check(
		st.city_by_id(1).get("current_project", {}).get("project_id", "") == "produce_unit:warrior",
		"snapshot reconcile installs authoritative current_project"
	)
	_check(st.selected_city_id == 1, "still-owned city selection survives")
	_check(bool(dirs.get("selection", false)), "selection refetch directed after project change")
	_check(st.production_rows().is_empty(), "pre-accept served rows cleared by revision advance")


func _test_stale_rows_clear_on_revision_selection_actor() -> void:
	var st = WorldInteractionStateScript.new(0)
	st.apply_snapshot(_snapshot(0, [_city()]))
	st.select_city(1)
	var serial: int = st.begin_selection_fetch()
	st.accept_selection_legal_actions(
		serial,
		_city_selection_response(0, 1, [_prod_row("produce_unit:settler"), _prod_row("produce_unit:warrior")]),
	)
	_check(st.production_rows().size() == 2, "production rows fresh after accept")

	# Selection change clears the selection slot (including production rows).
	st.select_unit(99)  # unit may be missing; clears city + served rows
	_check(st.production_rows().is_empty(), "selection change clears production rows")
	_check(st.selected_city_id == WorldInteractionStateScript.NO_SELECTION, "city cleared on unit select")

	# Restore city selection + rows, then revision advance.
	st.apply_snapshot(_snapshot(0, [_city()]))
	st.select_city(1)
	serial = st.begin_selection_fetch()
	st.accept_selection_legal_actions(
		serial,
		_city_selection_response(0, 1, [_prod_row("produce_unit:warrior")]),
	)
	st.apply_snapshot(_snapshot(1, [_city()]))
	st.select_city(1)
	_check(st.production_rows().is_empty(), "revision advance clears stale production rows")

	# One-PC actor rebind clears previous actor's city selection and rows.
	st.one_pc_debug = true
	st.apply_snapshot(_snapshot(2, [_city(), _city(2, 1)], 0))
	st.select_city(1)
	serial = st.begin_selection_fetch()
	st.accept_selection_legal_actions(
		serial,
		_city_selection_response(2, 1, [_prod_row("produce_unit:warrior")]),
	)
	_check(st.production_rows().size() == 1, "rows present before actor switch")
	var dirs: Dictionary = st.apply_snapshot(_snapshot(3, [_city(), _city(2, 1)], 1))
	_check(st.my_actor_id == 1, "one-PC rebinds to Player 1")
	_check(st.selected_city_id == WorldInteractionStateScript.NO_SELECTION, "previous city selection cleared")
	_check(st.production_rows().is_empty(), "production rows cleared on actor rebind")
	_check(not bool(dirs.get("selection", false)), "no selection refetch for previous actor's city")


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
		print("test_world_city_production_interaction: FAILED (%d checks)" % _total)
		quit(1)
	print("test_world_city_production_interaction: OK (%d checks)" % _total)
	quit(0)
