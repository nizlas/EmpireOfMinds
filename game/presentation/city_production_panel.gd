# Minimal HUD: city production options derived from LegalActions only (no content registries).
# Phase 5.1.5: restrained parchment-style presentation; behavior unchanged.
# See docs/CITIES.md, docs/RENDERING.md
class_name CityProductionPanel
extends PanelContainer

const LegalActionsScript = preload("res://domain/legal_actions.gd")
const SetCityProductionScript = preload("res://domain/actions/set_city_production.gd")

var game_state
var selection
var cities_view
var turn_label
var log_view

var _root_vbox: VBoxContainer
var _title_label: Label
var _subheader_label: Label
var _status_label: Label
var _actions_block: VBoxContainer
var _actions_heading_label: Label
var _actions_empty_label: Label
var _btn_container: VBoxContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_panel_style()

	_root_vbox = VBoxContainer.new()
	_root_vbox.add_theme_constant_override("separation", 10)
	add_child(_root_vbox)

	_title_label = Label.new()
	_subheader_label = Label.new()
	_status_label = Label.new()
	_actions_block = VBoxContainer.new()
	_actions_block.add_theme_constant_override("separation", 8)
	_actions_heading_label = Label.new()
	_actions_empty_label = Label.new()
	_btn_container = VBoxContainer.new()
	_btn_container.add_theme_constant_override("separation", 6)

	_style_title_label(_title_label)
	_style_subheader_label(_subheader_label)
	_style_body_label(_status_label)
	_style_section_heading(_actions_heading_label)
	_style_muted_label(_actions_empty_label)

	_root_vbox.add_child(_title_label)
	_root_vbox.add_child(_subheader_label)
	_root_vbox.add_child(HSeparator.new())
	_root_vbox.add_child(_status_label)
	_root_vbox.add_child(HSeparator.new())
	_actions_block.add_child(_actions_heading_label)
	_actions_block.add_child(_actions_empty_label)
	_actions_block.add_child(_btn_container)
	_root_vbox.add_child(_actions_block)


func _apply_panel_style() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.91, 0.86, 0.78, 0.97)
	sb.border_color = Color(0.44, 0.37, 0.29, 1.0)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(5)
	sb.shadow_color = Color(0, 0, 0, 0.12)
	sb.shadow_size = 2
	sb.shadow_offset = Vector2(0, 1)
	add_theme_stylebox_override("panel", sb)


func _style_title_label(l: Label) -> void:
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", Color(0.12, 0.11, 0.1, 1.0))


func _style_subheader_label(l: Label) -> void:
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(0.36, 0.32, 0.28, 1.0))


func _style_body_label(l: Label) -> void:
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(0.14, 0.13, 0.11, 1.0))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _style_section_heading(l: Label) -> void:
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color(0.18, 0.16, 0.14, 1.0))


func _style_muted_label(l: Label) -> void:
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color(0.38, 0.34, 0.3, 1.0))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _style_production_button(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.82, 0.74, 0.62, 1.0)
	normal.border_color = Color(0.48, 0.41, 0.33, 1.0)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(4)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.87, 0.8, 0.68, 1.0)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.72, 0.65, 0.54, 1.0)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_color_override("font_color", Color(0.14, 0.12, 0.1, 1.0))
	btn.add_theme_font_size_override("font_size", 15)


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
		"header_title": "",
		"subheader": "",
		"status": "",
		"show_production_section": false,
		"actions_heading": "",
		"actions_empty": "",
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
	vm["header_title"] = "City"
	vm["header"] = "City"
	vm["subheader"] = "#%d · Owner %d" % [cid, city.owner_id]
	if city.owner_id != cp:
		vm["status"] = "Not your city (owner is player %d)." % city.owner_id
		vm["show_production_section"] = false
		vm["options"] = []
		return vm
	vm["show_production_section"] = true
	vm["actions_heading"] = "Available production"
	if city.current_project == null:
		vm["status"] = "No active project."
	else:
		if typeof(city.current_project) != TYPE_DICTIONARY:
			vm["status"] = "Production in progress."
		else:
			var pd = city.current_project as Dictionary
			var pid = str(pd.get("project_id", ""))
			var prog = int(pd.get("progress", 0))
			var cost = int(pd.get("cost", 0))
			var ready = bool(pd.get("ready", false))
			var hn = _human_project_suffix(pid)
			if ready:
				vm["status"] = "Ready: %s — awaiting delivery tick." % hn
			else:
				vm["status"] = "Producing: %s — %d / %d" % [hn, prog, cost]
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
		var hn_opt = _human_project_suffix(proj_id)
		opts.append(
			{
				"label": "Train %s" % hn_opt,
				"action": ad.duplicate(true),
			}
		)
		li = li + 1
	vm["options"] = opts
	if opts.is_empty():
		if city.current_project != null:
			vm["actions_empty"] = "Production is already in progress."
		else:
			vm["actions_empty"] = "No available projects."
	else:
		vm["actions_empty"] = ""
	return vm


func refresh() -> void:
	if _title_label == null:
		return
	var vm = compute_view_model(game_state, selection)
	var show_panel = bool(vm.get("visible", false))
	visible = show_panel
	mouse_filter = Control.MOUSE_FILTER_STOP if show_panel else Control.MOUSE_FILTER_IGNORE
	if not show_panel:
		_title_label.text = ""
		_subheader_label.text = ""
		_status_label.text = ""
		_actions_heading_label.text = ""
		_actions_empty_label.text = ""
		_actions_empty_label.visible = false
		_actions_heading_label.visible = false
		_actions_block.visible = false
		_clear_buttons()
		return
	_title_label.text = str(vm.get("header_title", ""))
	_subheader_label.text = str(vm.get("subheader", ""))
	_status_label.text = str(vm.get("status", ""))
	var show_prod = bool(vm.get("show_production_section", false))
	_actions_block.visible = show_prod
	_actions_heading_label.visible = show_prod
	if show_prod:
		_actions_heading_label.text = str(vm.get("actions_heading", ""))
	else:
		_actions_heading_label.text = ""
	_clear_buttons()
	var opts = vm.get("options", []) as Array
	var empty_msg = str(vm.get("actions_empty", ""))
	_actions_empty_label.text = empty_msg
	var oi = 0
	while oi < opts.size():
		var entry = opts[oi] as Dictionary
		var btn = Button.new()
		btn.text = str(entry.get("label", ""))
		_style_production_button(btn)
		var act = entry.get("action", {}) as Dictionary
		btn.pressed.connect(_on_production_button_pressed.bind(act))
		_btn_container.add_child(btn)
		oi = oi + 1
	_actions_empty_label.visible = show_prod and opts.is_empty() and empty_msg.length() > 0


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
		# Defer: refresh() frees dynamic Buttons; cannot rebuild during the emitting pressed callback.
		call_deferred("refresh")
	else:
		push_warning("SetCityProduction rejected: %s" % result["reason"])
