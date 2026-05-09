# Minimal HUD: city production options derived from LegalActions only (no content registries).
# See docs/CITIES.md, docs/RENDERING.md
class_name CityProductionPanel
extends VBoxContainer

const LegalActionsScript = preload("res://domain/legal_actions.gd")
const SetCityProductionScript = preload("res://domain/actions/set_city_production.gd")

var game_state
var selection
var cities_view
var turn_label
var log_view

var _header_label: Label
var _status_label: Label
var _btn_container: VBoxContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_header_label = Label.new()
	_status_label = Label.new()
	_btn_container = VBoxContainer.new()
	add_child(_header_label)
	add_child(_status_label)
	add_child(_btn_container)


static func _human_project_suffix(project_id: String) -> String:
	var s = project_id.strip_edges()
	var pos = s.rfind(":")
	if pos >= 0:
		s = s.substr(pos + 1)
	if s.is_empty():
		return project_id
	return s.capitalize()


static func compute_view_model(game_state, selection) -> Dictionary:
	var vm = {
		"visible": false,
		"header": "",
		"status": "",
		"options": [],
	}
	if game_state == null or selection == null:
		return vm
	if not selection.has_city():
		return vm
	var cid = selection.city_id
	var city = game_state.scenario.city_by_id(cid)
	if city == null:
		return vm
	var cp = game_state.turn_state.current_player_id()
	vm["visible"] = true
	vm["header"] = "City %d" % cid
	if city.owner_id != cp:
		vm["status"] = "Not your city (owner is player %d)." % city.owner_id
		vm["options"] = []
		return vm
	if city.current_project == null:
		vm["status"] = "Idle — choose a project."
	else:
		if typeof(city.current_project) != TYPE_DICTIONARY:
			vm["status"] = "Production active."
		else:
			var pd = city.current_project as Dictionary
			var pid = str(pd.get("project_id", ""))
			var prog = int(pd.get("progress", 0))
			var cost = int(pd.get("cost", 0))
			var ready = bool(pd.get("ready", false))
			var hn = _human_project_suffix(pid)
			if ready:
				vm["status"] = "%s — ready (awaiting delivery tick)." % hn
			else:
				vm["status"] = "%s — progress %d / %d" % [hn, prog, cost]
	var legal = LegalActionsScript.for_current_player(game_state)
	var opts: Array = []
	var li = 0
	while li < legal.size():
		var a = legal[li]
		if typeof(a) != TYPE_DICTIONARY:
			li = li + 1
			continue
		var ad = a as Dictionary
		if str(ad.get("action_type", "")) != SetCityProductionScript.ACTION_TYPE:
			li = li + 1
			continue
		if int(ad.get("city_id", -1)) != cid:
			li = li + 1
			continue
		var proj_id = str(ad.get("project_id", ""))
		opts.append(
			{
				"label": "Produce: %s" % _human_project_suffix(proj_id),
				"action": ad.duplicate(true),
			}
		)
		li = li + 1
	vm["options"] = opts
	return vm


func refresh() -> void:
	if _header_label == null:
		return
	var vm = compute_view_model(game_state, selection)
	visible = bool(vm.get("visible", false))
	if not visible:
		_header_label.text = ""
		_status_label.text = ""
		_clear_buttons()
		return
	_header_label.text = str(vm.get("header", ""))
	_status_label.text = str(vm.get("status", ""))
	_clear_buttons()
	var opts = vm.get("options", []) as Array
	var oi = 0
	while oi < opts.size():
		var entry = opts[oi] as Dictionary
		var btn = Button.new()
		btn.text = str(entry.get("label", ""))
		var act = entry.get("action", {}) as Dictionary
		btn.pressed.connect(_on_production_button_pressed.bind(act))
		_btn_container.add_child(btn)
		oi = oi + 1


func _clear_buttons() -> void:
	if _btn_container == null:
		return
	var k = _btn_container.get_child_count()
	while k > 0:
		k = k - 1
		var ch = _btn_container.get_child(k)
		_btn_container.remove_child(ch)
		ch.free()


func _on_production_button_pressed(action: Dictionary) -> void:
	if game_state == null:
		return
	var result = game_state.try_apply(action)
	if result["accepted"]:
		if cities_view != null:
			cities_view.scenario = game_state.scenario
			cities_view.queue_redraw()
		if turn_label != null:
			turn_label.refresh()
		if log_view != null:
			log_view.refresh()
		refresh()
	else:
		push_warning("SetCityProduction rejected: %s" % result["reason"])
