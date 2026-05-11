# HUD panel: first ProgressCandidateFilter suggestion for current player (CompleteProgress actions only).
# Phase 5.1.8b — parchment style matches CityProductionPanel; submits via GameState.try_apply only.
# See docs/RENDERING.md, docs/PROGRESSION_MODEL.md
class_name DiscoveryActionPanel
extends PanelContainer

const ProgressCandidateFilterScript = preload("res://domain/progress_candidate_filter.gd")

var game_state
var turn_label
var log_view
var city_production_panel
var science_panel
var discovery_popup

var _root_vbox: VBoxContainer
var _title_label: Label
var _heading_label: Label
var _body_label: Label
var _complete_button: Button


static func _hidden_view_model() -> Dictionary:
	return {
		"visible": false,
		"title": "",
		"heading": "",
		"body": "",
		"button_label": "",
		"action": {},
	}


static func _humanize_progress_id(raw: String) -> String:
	var s = raw.strip_edges()
	if s.is_empty():
		return ""
	var parts = s.split("_")
	var out: String = ""
	var pi: int = 0
	while pi < parts.size():
		var seg: String = str(parts[pi])
		if not seg.is_empty():
			if out.length() > 0:
				out = out + " "
			out = out + seg.capitalize()
		pi = pi + 1
	return out


static func compute_view_model(p_game_state) -> Dictionary:
	if p_game_state == null:
		return _hidden_view_model()
	var cands: Array = ProgressCandidateFilterScript.for_current_player(p_game_state)
	var filtered: Array = []
	var fi = 0
	while fi < cands.size():
		var item = cands[fi]
		if typeof(item) != TYPE_DICTIONARY:
			fi = fi + 1
			continue
		var cd = item as Dictionary
		if str(cd.get("progress_id", "")) == "controlled_fire":
			fi = fi + 1
			continue
		filtered.append(item)
		fi = fi + 1
	if filtered.is_empty():
		return _hidden_view_model()
	if typeof(filtered[0]) != TYPE_DICTIONARY:
		return _hidden_view_model()
	var action: Dictionary = (filtered[0] as Dictionary).duplicate(true)
	var pid: String = str(action.get("progress_id", ""))
	return {
		"visible": true,
		"title": "Discovery available",
		"heading": _humanize_progress_id(pid),
		"body": "Your people have found a tree split by lightning.",
		"button_label": "Complete Discovery",
		"action": action,
	}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_panel_style()

	_root_vbox = VBoxContainer.new()
	_root_vbox.add_theme_constant_override("separation", 10)
	add_child(_root_vbox)

	_title_label = Label.new()
	_heading_label = Label.new()
	_body_label = Label.new()
	_complete_button = Button.new()

	_style_title_label(_title_label)
	_style_heading_label(_heading_label)
	_style_body_label(_body_label)
	_style_complete_button(_complete_button)

	_root_vbox.add_child(_title_label)
	_root_vbox.add_child(_heading_label)
	_root_vbox.add_child(_body_label)
	_root_vbox.add_child(_complete_button)

	_complete_button.pressed.connect(_on_complete_pressed)
	visible = false
	_complete_button.disabled = true


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


func _style_heading_label(l: Label) -> void:
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Color(0.18, 0.16, 0.14, 1.0))


func _style_body_label(l: Label) -> void:
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color(0.36, 0.32, 0.28, 1.0))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _style_complete_button(btn: Button) -> void:
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


func refresh() -> void:
	if _title_label == null:
		return
	var vm: Dictionary = compute_view_model(game_state)
	var show_panel: bool = bool(vm.get("visible", false))
	visible = show_panel
	mouse_filter = Control.MOUSE_FILTER_STOP if show_panel else Control.MOUSE_FILTER_IGNORE
	if not show_panel:
		_title_label.text = ""
		_heading_label.text = ""
		_body_label.text = ""
		_complete_button.text = ""
		_complete_button.disabled = true
		return
	_title_label.text = str(vm.get("title", ""))
	_heading_label.text = str(vm.get("heading", ""))
	_body_label.text = str(vm.get("body", ""))
	_complete_button.text = str(vm.get("button_label", ""))
	_complete_button.disabled = false


func _on_complete_pressed() -> void:
	if game_state == null:
		return
	var vm_now: Dictionary = compute_view_model(game_state)
	if not bool(vm_now.get("visible", false)):
		return
	var action: Dictionary = vm_now.get("action", {}) as Dictionary
	var result: Dictionary = game_state.try_apply(action)
	if result["accepted"]:
		if turn_label != null:
			turn_label.refresh()
		if log_view != null:
			log_view.refresh()
		if city_production_panel != null:
			city_production_panel.refresh()
		if science_panel != null:
			science_panel.call_deferred("refresh")
		if discovery_popup != null:
			discovery_popup.maybe_show_for_log_index(int(result["index"]))
		call_deferred("refresh")
	else:
		push_warning("CompleteDiscovery (panel) rejected: %s" % result["reason"])
