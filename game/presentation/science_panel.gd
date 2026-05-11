# Minimal HUD: current / effective research, progress, SetCurrentResearch buttons, locked-science hints.
# Phase 5.1.13 — selection; 5.1.14 — compact locked list (missing prerequisites only).
# Not a tech tree; reads ProgressDefinitions + ScienceAvailability for labels only.
# See docs/RENDERING.md
class_name SciencePanel
extends PanelContainer

const ProgressDefinitionsScript = preload("res://domain/content/progress_definitions.gd")
const ScienceAvailabilityScript = preload("res://domain/science_availability.gd")
const SetCurrentResearchScript = preload("res://domain/actions/set_current_research.gd")

## Max locked rows before a "+N more" line (view model still lists all locked ids).
const LOCKED_ROW_DISPLAY_MAX: int = 6

var game_state
var turn_label
var log_view


static func _humanize_id(raw: String) -> String:
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


static func _comma_join(parts: Array) -> String:
	var out: String = ""
	var ji: int = 0
	while ji < parts.size():
		if ji > 0:
			out = out + ", "
		out = out + str(parts[ji])
		ji = ji + 1
	return out


static func _missing_prerequisite_entries(progress_state, owner_id: int, science_id: String) -> Dictionary:
	var ids: Array = []
	var labels: Array = []
	var raw_req = ProgressDefinitionsScript.prerequisites(science_id)
	var qi: int = 0
	while qi < raw_req.size():
		var prid: String = str(raw_req[qi])
		if not progress_state.has_completed_progress(owner_id, prid):
			ids.append(prid)
			labels.append(science_display_name(prid))
		qi = qi + 1
	return {"ids": ids, "labels": labels}


static func science_display_name(science_id: String) -> String:
	var sid = science_id.strip_edges()
	if sid.is_empty() or not ProgressDefinitionsScript.has(sid):
		return _humanize_id(sid)
	var def = ProgressDefinitionsScript.get_definition(sid)
	if def == null or typeof(def) != TYPE_DICTIONARY:
		return _humanize_id(sid)
	if def.has("display_name"):
		return str(def["display_name"])
	return _humanize_id(sid)


static func _effective_research_id(progress_state, owner_id: int) -> String:
	if progress_state == null:
		return ""
	var explicit: String = progress_state.current_research_for(owner_id)
	if (
		explicit.strip_edges() != ""
		and ScienceAvailabilityScript.is_available(progress_state, owner_id, explicit)
	):
		return explicit
	var avail: Array = ScienceAvailabilityScript.available_for(progress_state, owner_id)
	if avail.is_empty():
		return ""
	return str(avail[0])


static func compute_view_model(p_game_state) -> Dictionary:
	if p_game_state == null:
		return {
			"visible": false,
			"current_player_id": -1,
			"explicit_research_id": "",
			"effective_research_id": "",
			"effective_research_label": "",
			"target_heading": "",
			"progress": 0,
			"cost": 0,
			"progress_text": "—",
			"available_rows": [],
			"locked_rows": [],
			"locked_more_count": 0,
		}
	var pid: int = p_game_state.turn_state.current_player_id()
	var ps = p_game_state.progress_state
	var explicit: String = ps.current_research_for(pid)
	var explicit_ok: bool = (
		explicit.strip_edges() != ""
		and ScienceAvailabilityScript.is_available(ps, pid, explicit)
	)
	var effective_id: String = _effective_research_id(ps, pid)
	var effective_label: String = (
		science_display_name(effective_id) if effective_id != "" else ""
	)
	var target_heading: String
	if explicit_ok:
		target_heading = "Researching: %s" % science_display_name(explicit)
	elif effective_id != "":
		target_heading = "Auto: %s" % effective_label
	else:
		target_heading = "No available research"
	var prog: int = 0
	var cost: int = 0
	var progress_text: String = "—"
	if effective_id != "":
		prog = ps.science_progress_for(pid, effective_id)
		cost = ProgressDefinitionsScript.cost(effective_id)
		progress_text = "%d / %d" % [prog, cost]
	var avail: Array = ScienceAvailabilityScript.available_for(ps, pid)
	var rows: Array = []
	var ri: int = 0
	while ri < avail.size():
		var sid: String = str(avail[ri])
		var sprog: int = ps.science_progress_for(pid, sid)
		var scost: int = ProgressDefinitionsScript.cost(sid)
		var row: Dictionary = {
			"id": sid,
			"label": science_display_name(sid),
			"progress": sprog,
			"cost": scost,
			"is_explicit_current": explicit_ok and sid == explicit,
			"is_auto_current": (not explicit_ok) and sid == effective_id and effective_id != "",
		}
		rows.append(row)
		ri = ri + 1
	var locked_ids: Array = ScienceAvailabilityScript.locked_for(ps, pid)
	var locked_rows: Array = []
	var li: int = 0
	while li < locked_ids.size():
		var lid: String = str(locked_ids[li])
		var miss: Dictionary = _missing_prerequisite_entries(ps, pid, lid)
		var mids: Array = miss["ids"] as Array
		var mlabs: Array = miss["labels"] as Array
		var req_text: String = _comma_join(mlabs)
		var disp: String
		if req_text.strip_edges() == "":
			disp = science_display_name(lid)
		else:
			disp = "%s — Requires: %s" % [science_display_name(lid), req_text]
		locked_rows.append(
			{
				"id": lid,
				"label": science_display_name(lid),
				"missing_prerequisites": mids,
				"missing_prerequisite_labels": mlabs,
				"display": disp,
			}
		)
		li = li + 1
	var locked_more_count: int = 0
	if locked_rows.size() > LOCKED_ROW_DISPLAY_MAX:
		locked_more_count = locked_rows.size() - LOCKED_ROW_DISPLAY_MAX
	return {
		"visible": true,
		"current_player_id": pid,
		"explicit_research_id": explicit,
		"effective_research_id": effective_id,
		"effective_research_label": effective_label,
		"target_heading": target_heading,
		"progress": prog,
		"cost": cost,
		"progress_text": progress_text,
		"available_rows": rows,
		"locked_rows": locked_rows,
		"locked_more_count": locked_more_count,
	}


var _root_vbox: VBoxContainer
var _title_label: Label
var _target_label: Label
var _progress_label: Label
var _available_heading: Label
var _available_container: VBoxContainer
var _locked_heading: Label
var _locked_container: VBoxContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_panel_style()
	_root_vbox = VBoxContainer.new()
	_root_vbox.add_theme_constant_override("separation", 8)
	add_child(_root_vbox)
	_title_label = Label.new()
	_target_label = Label.new()
	_progress_label = Label.new()
	_available_heading = Label.new()
	_available_container = VBoxContainer.new()
	_available_container.add_theme_constant_override("separation", 6)
	_style_title(_title_label)
	_style_body(_target_label)
	_style_body(_progress_label)
	_style_subheading(_available_heading)
	_title_label.text = "Science"
	_available_heading.text = "Available sciences"
	_root_vbox.add_child(_title_label)
	_root_vbox.add_child(_target_label)
	_root_vbox.add_child(_progress_label)
	_root_vbox.add_child(_available_heading)
	_root_vbox.add_child(_available_container)
	_locked_heading = Label.new()
	_locked_container = VBoxContainer.new()
	_locked_container.add_theme_constant_override("separation", 4)
	_style_subheading(_locked_heading)
	_locked_heading.text = "Locked sciences"
	_root_vbox.add_child(_locked_heading)
	_root_vbox.add_child(_locked_container)
	_locked_heading.visible = false
	_locked_container.visible = false


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


func _style_title(l: Label) -> void:
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", Color(0.12, 0.11, 0.1, 1.0))


func _style_subheading(l: Label) -> void:
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(0.22, 0.19, 0.16, 1.0))


func _style_body(l: Label) -> void:
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color(0.14, 0.13, 0.11, 1.0))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _style_locked_row(l: Label) -> void:
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(0.38, 0.34, 0.3, 1.0))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _style_locked_more(l: Label) -> void:
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(0.48, 0.44, 0.4, 1.0))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _style_choice_button(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.82, 0.74, 0.62, 1.0)
	normal.border_color = Color(0.48, 0.41, 0.33, 1.0)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(4)
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	normal.content_margin_top = 6
	normal.content_margin_bottom = 6
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.87, 0.8, 0.68, 1.0)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.72, 0.65, 0.54, 1.0)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_color_override("font_color", Color(0.14, 0.12, 0.1, 1.0))
	btn.add_theme_font_size_override("font_size", 13)


func refresh() -> void:
	if _target_label == null:
		return
	var vm: Dictionary = compute_view_model(game_state)
	if not bool(vm.get("visible", false)):
		visible = false
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		return
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_target_label.text = str(vm.get("target_heading", ""))
	_progress_label.text = str(vm.get("progress_text", "—"))
	_rebuild_buttons(vm.get("available_rows", []) as Array)
	_rebuild_locked(vm)


func _rebuild_locked(vm: Dictionary) -> void:
	while _locked_container.get_child_count() > 0:
		_locked_container.get_child(0).free()
	var all_locked: Array = vm.get("locked_rows", []) as Array
	if all_locked.is_empty():
		_locked_heading.visible = false
		_locked_container.visible = false
		return
	_locked_heading.visible = true
	_locked_container.visible = true
	var more: int = int(vm.get("locked_more_count", 0))
	var show_n: int = all_locked.size()
	if show_n > LOCKED_ROW_DISPLAY_MAX:
		show_n = LOCKED_ROW_DISPLAY_MAX
	var ki: int = 0
	while ki < show_n:
		var raw_row = all_locked[ki]
		if typeof(raw_row) != TYPE_DICTIONARY:
			ki = ki + 1
			continue
		var rd: Dictionary = raw_row as Dictionary
		var lab := Label.new()
		lab.text = str(rd.get("display", ""))
		_style_locked_row(lab)
		_locked_container.add_child(lab)
		ki = ki + 1
	if more > 0:
		var more_lab := Label.new()
		more_lab.text = "+%d more locked sciences" % more
		_style_locked_more(more_lab)
		_locked_container.add_child(more_lab)


func _rebuild_buttons(rows: Array) -> void:
	while _available_container.get_child_count() > 0:
		_available_container.get_child(0).free()
	var bi: int = 0
	while bi < rows.size():
		var raw = rows[bi]
		if typeof(raw) != TYPE_DICTIONARY:
			bi = bi + 1
			continue
		var row: Dictionary = raw as Dictionary
		var sid: String = str(row.get("id", ""))
		if sid.is_empty():
			bi = bi + 1
			continue
		var label: String = str(row.get("label", sid))
		var pr: int = int(row.get("progress", 0))
		var co: int = int(row.get("cost", 0))
		var mark_explicit: bool = bool(row.get("is_explicit_current", false))
		var mark_auto: bool = bool(row.get("is_auto_current", false))
		var prefix: String = ""
		if mark_explicit or mark_auto:
			prefix = "✓ "
		var btn := Button.new()
		btn.text = "%s%s — %d/%d" % [prefix, label, pr, co]
		btn.set_meta("science_id", sid)
		_style_choice_button(btn)
		btn.pressed.connect(_on_science_button_pressed.bind(sid))
		_available_container.add_child(btn)
		bi = bi + 1


func _on_science_button_pressed(science_id: String) -> void:
	if game_state == null:
		return
	var sid: String = science_id
	var pid: int = game_state.turn_state.current_player_id()
	var result: Dictionary = game_state.try_apply(SetCurrentResearchScript.make(pid, sid))
	if bool(result.get("accepted", false)):
		if turn_label != null:
			turn_label.refresh()
		if log_view != null:
			log_view.refresh()
		call_deferred("refresh")
	else:
		push_warning("SetCurrentResearch rejected: %s" % str(result.get("reason", "?")))
