# Headless: godot --headless --path game -s res://cloud/tests/test_world_city_ui_components.gd
#
# N8R focused city UI components: the Found City button and the production
# panel render EXCLUSIVELY from the interaction state's served rows (no
# local founding/production legality, no client-built payloads), report
# choices only through their signals, and disable while a request is busy.
# Also guards the world-play composition: the scene script wires the
# extracted components instead of rebuilding N8 UI inline, and the active
# world path never touches the deprecated local production tick/delivery.
extends SceneTree

const WorldInteractionStateScript = preload("res://cloud/world_play/world_interaction_state.gd")
const WorldCitySelectionUiScript = preload("res://cloud/world_play/world_city_selection_ui.gd")
const WorldCityProductionPanelScript = preload("res://cloud/world_play/world_city_production_panel.gd")

var _total := 0
var _any_fail := false
var _chosen: Array = []
var _found_requests := 0


func _snapshot(rev: int, units: Array, cities: Array) -> Dictionary:
	return {
		"match_id": "m_n8r",
		"schema_version": 3,
		"match_kind": "world_map",
		"map": {"map_id": "handdrawn_test_map_full_01", "schema_version": 1, "content_hash": "x"},
		"revision": rev,
		"turn_state": {"players": [0, 1], "current_index": 0, "turn_number": 1},
		"units": units,
		"cities": cities,
		"next_city_id": cities.size() + 1,
	}


func _settler() -> Array:
	return [
		{"id": 1, "owner_id": 0, "position": [1, 1], "type_id": "settler", "current_hp": 100, "has_attacked": false},
	]


func _city(project = null) -> Dictionary:
	return {"id": 1, "owner_id": 0, "position": [2, 2], "name": "Capital", "current_project": project}


func _found_row() -> Dictionary:
	return {"schema_version": 1, "action_type": "found_city", "actor_id": 0, "unit_id": 1, "position": [1, 1]}


func _prod_row(project_id: String) -> Dictionary:
	return {"schema_version": 2, "action_type": "set_city_production", "actor_id": 0, "city_id": 1, "project_id": project_id}


func _selection_response(rev: int, unit_id, city_id, rows: Array) -> Dictionary:
	return {
		"match_id": "m_n8r",
		"revision": rev,
		"schema_version": 1,
		"actor_id": 0,
		"is_current_player": true,
		"selected_unit_id": unit_id,
		"selected_city_id": city_id,
		"selection_error": null,
		"actions": rows,
	}


func _init() -> void:
	_run()


func _run() -> void:
	_test_production_panel_renders_served_rows_only()
	_test_production_panel_busy_and_signal()
	_test_found_city_button_served_row_only()
	_test_scene_composes_extracted_components()
	_test_world_play_never_imports_local_production_loop()
	_finish()


func _panel_buttons(panel: Node) -> Array:
	var out: Array = []
	for child in panel.get_children():
		if child is Button:
			out.append(child)
	return out


func _test_production_panel_renders_served_rows_only() -> void:
	var st = WorldInteractionStateScript.new(0)
	st.apply_snapshot(_snapshot(0, [], [_city()]))
	st.select_city(1)
	var panel = WorldCityProductionPanelScript.new()
	root.add_child(panel)

	# City selected but NO served rows: visible status, zero choice buttons —
	# the component never invents production legality locally.
	panel.refresh(st, false)
	_check(panel.visible, "panel visible for a selected own city")
	_check(_panel_buttons(panel).is_empty(), "no buttons without served rows")

	var serial: int = st.begin_selection_fetch()
	st.accept_selection_legal_actions(
		serial,
		_selection_response(0, null, 1, [_prod_row("produce_unit:settler"), _prod_row("produce_unit:warrior")]),
	)
	panel.refresh(st, false)
	# queue_free()d stale buttons are still children until the frame ends —
	# count only the freshly built (non-queued) ones via names.
	var btns := _panel_buttons(panel)
	_check(btns.size() == 2, "exactly the served rows become buttons")
	_check(str(btns[0].name) == "Prod_produce_unit_settler", "button per served project id")
	_check(btns[0].text == "Train Settler" and btns[1].text == "Train Warrior", "display naming applied")
	_check(not btns[0].disabled and not btns[1].disabled, "fresh served rows enabled")

	# Deselect: the panel empties (no stale production UI).
	st.clear_selection()
	panel.refresh(st, false)
	_check(not panel.visible, "panel hides without a selected city")
	panel.queue_free()


func _test_production_panel_busy_and_signal() -> void:
	var st = WorldInteractionStateScript.new(0)
	st.apply_snapshot(_snapshot(0, [], [_city()]))
	st.select_city(1)
	var serial: int = st.begin_selection_fetch()
	st.accept_selection_legal_actions(
		serial, _selection_response(0, null, 1, [_prod_row("produce_unit:warrior")])
	)
	var panel = WorldCityProductionPanelScript.new()
	root.add_child(panel)
	panel.refresh(st, true)
	var busy_btns := _panel_buttons(panel)
	_check(busy_btns.size() == 1 and busy_btns[0].disabled, "buttons disabled while a request is busy")

	panel.refresh(st, false)
	_chosen.clear()
	panel.production_row_chosen.connect(func(pid: String) -> void: _chosen.append(pid))
	var live: Array = []
	for b in _panel_buttons(panel):
		if not b.disabled:
			live.append(b)
	_check(live.size() == 1, "one live button after busy clears")
	(live[0] as Button).pressed.emit()
	_check(_chosen == ["produce_unit:warrior"], "press reports the served project_id via signal only")
	panel.queue_free()


func _test_found_city_button_served_row_only() -> void:
	var st = WorldInteractionStateScript.new(0)
	st.apply_snapshot(_snapshot(0, _settler(), []))
	st.select_unit(1)
	var button = WorldCitySelectionUiScript.new()
	root.add_child(button)

	button.refresh(st, false)
	_check(not button.visible and button.disabled, "hidden/disabled without a served found_city row")

	var serial: int = st.begin_selection_fetch()
	st.accept_selection_legal_actions(serial, _selection_response(0, 1, null, [_found_row()]))
	button.refresh(st, false)
	_check(button.visible and not button.disabled, "visible/enabled from the served row only")
	button.refresh(st, true)
	_check(button.disabled, "disabled while a request is busy")

	button.refresh(st, false)
	_found_requests = 0
	button.found_city_requested.connect(func() -> void: _found_requests += 1)
	button.pressed.emit()
	_check(_found_requests == 1, "press reports found_city_requested via signal only")
	button.queue_free()


# Composition guard: the world-play scene script builds the EXTRACTED
# components (preloads + wiring) and no longer owns an inline production
# panel builder — N8 presentation stays out of the composition monolith.
func _test_scene_composes_extracted_components() -> void:
	var src: String = (load("res://cloud/world_play/cloud_world_play.gd") as Script).source_code
	_check(
		src.contains("world_city_selection_ui.gd") and src.contains("world_city_production_panel.gd"),
		"cloud_world_play composes the extracted city UI components"
	)
	_check(
		not src.contains("func _refresh_production_panel"),
		"cloud_world_play no longer owns an inline production panel builder"
	)
	_check(
		src.contains("production_row_chosen.connect") and src.contains("found_city_requested.connect"),
		"scene submits served rows reported by component signals"
	)


# Dependency guard: the active world path never touches the deprecated
# client-local production loop (production_tick/production_delivery belong
# to the frozen Scenario runtime; world production is server-authoritative).
func _test_world_play_never_imports_local_production_loop() -> void:
	for path in [
		"res://cloud/world_play/cloud_world_play.gd",
		"res://cloud/world_play/world_interaction_state.gd",
		"res://cloud/world_play/world_city_selection_ui.gd",
		"res://cloud/world_play/world_city_production_panel.gd",
	]:
		var src: String = (load(path) as Script).source_code
		_check(
			not src.contains("production_tick.gd") and not src.contains("production_delivery.gd"),
			"%s stays clear of the deprecated local production loop" % path
		)
		_check(
			not src.contains("res://domain/scenario.gd") and not src.contains("res://domain/hex_map.gd"),
			"%s stays clear of deprecated Scenario/HexMap state" % path
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
		print("test_world_city_ui_components: FAILED (%d checks)" % _total)
		quit(1)
	print("test_world_city_ui_components: OK (%d checks)" % _total)
	quit(0)
