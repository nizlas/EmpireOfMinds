# Dismissible HUD popup after accepted CompleteProgress when the log entry unlocks
# city_project produce_unit:* (same filter as LogView Phase 5.1.6). Presentation-only.
# See docs/RENDERING.md, docs/PHASE_PLAN.md (Phase 5.1.7).
class_name DiscoveryPopup
extends PanelContainer

const CompleteProgressScript = preload("res://domain/actions/complete_progress.gd")
const ScienceCompletedPopupScript = preload("res://presentation/science_completed_popup.gd")

var game_state

var _followup_science_popup = null
var _pending_science_completed_log_index: int = -1

var _title_label: Label
var _heading_label: Label
var _body_label: Label
var _practical_label: Label
var _unlock_label: Label
var _ok_button: Button


static func _hidden_view_model() -> Dictionary:
	return {
		"visible": false,
		"title": "",
		"heading": "",
		"body": "",
		"practical_line": "",
		"unlock_block": "",
	}


static func _humanize_progress_id(raw: String) -> String:
	var s = raw.strip_edges()
	if s.is_empty() or s == "?":
		return "Progress"
	var parts = s.split("_")
	var out = ""
	var pi = 0
	while pi < parts.size():
		var seg = parts[pi]
		if not seg.is_empty():
			if out.length() > 0:
				out = out + " "
			out = out + seg.capitalize()
		pi = pi + 1
	if out.length() > 0:
		return out
	return "Progress"


static func _train_label_from_city_project_target_id(target_id: String) -> String:
	var tid = target_id.strip_edges()
	if tid.is_empty():
		return ""
	var pos = tid.rfind(":")
	var suffix = ""
	if pos >= 0:
		suffix = tid.substr(pos + 1)
	else:
		suffix = tid
	suffix = suffix.strip_edges()
	if suffix.is_empty():
		suffix = tid
	return suffix.capitalize()


static func _train_unlock_labels_from_entry(entry: Dictionary) -> Array:
	var out: Array = []
	if not entry.has("unlocked_targets"):
		return out
	if typeof(entry["unlocked_targets"]) != TYPE_ARRAY:
		return out
	var ut = entry["unlocked_targets"] as Array
	var ui = 0
	while ui < ut.size():
		var raw_row = ut[ui]
		if typeof(raw_row) != TYPE_DICTIONARY:
			ui = ui + 1
			continue
		var row = raw_row as Dictionary
		if str(row.get("target_type", "")) != "city_project":
			ui = ui + 1
			continue
		var tid = str(row.get("target_id", ""))
		if not tid.begins_with("produce_unit:"):
			ui = ui + 1
			continue
		var train_name = _train_label_from_city_project_target_id(tid)
		if train_name.is_empty():
			ui = ui + 1
			continue
		out.append("Train %s" % train_name)
		ui = ui + 1
	return out


static func _format_unlock_block(labels: Array) -> String:
	if labels.is_empty():
		return ""
	var lines: Array = ["Unlocked:"]
	var li = 0
	while li < labels.size():
		lines.append("• " + str(labels[li]))
		li = li + 1
	return _join_lines(lines)


static func _join_lines(parts: Array) -> String:
	var out = ""
	var i = 0
	while i < parts.size():
		if i > 0:
			out = out + "\n"
		out = out + str(parts[i])
		i = i + 1
	return out


## First new log index in [prev_log_size, size) with [param action_type], or [code]-1[/code].
static func first_new_log_index_for_action(game_state, prev_log_size: int, action_type: String) -> int:
	if game_state == null or game_state.log == null:
		return -1
	var lg = game_state.log
	var i = prev_log_size
	while i < lg.size():
		var e = lg.get_entry(i)
		if typeof(e) == TYPE_DICTIONARY and str((e as Dictionary).get("action_type", "")) == action_type:
			return i
		i = i + 1
	return -1


## After accepted [method GameState.try_apply]: show [DiscoveryPopup] for [code]science_bonus[/code] first; chain [ScienceCompletedPopup] on OK when both appear in the new slice.
static func run_engine_popups_after_apply(
	game_state,
	discovery_popup,
	science_completed_popup,
	prev_log_size: int
) -> void:
	var bonus_idx = first_new_log_index_for_action(game_state, prev_log_size, "science_bonus")
	var completed_idx = first_new_log_index_for_action(game_state, prev_log_size, "science_completed")
	if bonus_idx >= 0 and discovery_popup != null:
		discovery_popup.arm_science_completed_chain(science_completed_popup, completed_idx)
		discovery_popup.maybe_show_for_log_index(bonus_idx)
	else:
		ScienceCompletedPopupScript.show_first_new_science_completed(
			game_state,
			science_completed_popup,
			prev_log_size
		)


func arm_science_completed_chain(p_popup, log_index: int) -> void:
	_followup_science_popup = p_popup
	_pending_science_completed_log_index = log_index


static func compute_view_model(log_entry) -> Dictionary:
	if typeof(log_entry) != TYPE_DICTIONARY:
		return _hidden_view_model()
	var entry = log_entry as Dictionary
	if entry.is_empty():
		return _hidden_view_model()
	if not entry.has("action_type") or typeof(entry["action_type"]) != TYPE_STRING:
		return _hidden_view_model()
	var at = str(entry.get("action_type", ""))
	if at == "science_bonus":
		if str(entry.get("result", "")) != "accepted":
			return _hidden_view_model()
		if str(entry.get("bonus_id", "")) != "lightning_scarred_tree":
			return _hidden_view_model()
		var dlt = int(entry.get("delta", 0))
		var human = _humanize_progress_id(str(entry.get("progress_id", "controlled_fire")))
		return {
			"visible": true,
			"title": "Discovery",
			"heading": "Lightning-Scarred Tree",
			"body": (
				"Your people have found a tree split by lightning, its heart still warm with hidden embers. "
				+ "The sight teaches them that flame can be carried, guarded, and made useful."
			),
			"practical_line": "Progress toward %s +%d" % [human, dlt],
			"unlock_block": "",
		}
	if at != CompleteProgressScript.ACTION_TYPE:
		return _hidden_view_model()
	var train_labels = _train_unlock_labels_from_entry(entry)
	if train_labels.is_empty():
		return _hidden_view_model()
	var progress_id = str(entry.get("progress_id", ""))
	var heading: String
	var body: String
	if progress_id == "controlled_fire":
		heading = "Controlled Fire"
		body = (
			"Keeping flame where people sleep has turned a wary hazard into a steady tool: "
			+ "hearths hold heat, smoke paths are learned by habit, and small groups can leave the camp "
			+ "knowing they can return to light. That discipline is what lets your cities train pioneers "
			+ "ready to march out and raise new settlements."
		)
	else:
		heading = _humanize_progress_id(progress_id)
		body = (
			"Your people have put new knowledge to work. The following training options are "
			+ "now available in your cities."
		)
	return {
		"visible": true,
		"title": "Discovery completed",
		"heading": heading,
		"body": body,
		"practical_line": "",
		"unlock_block": _format_unlock_block(train_labels),
	}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_apply_panel_style()

	var root = VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	_title_label = Label.new()
	_heading_label = Label.new()
	_body_label = Label.new()
	_practical_label = Label.new()
	_unlock_label = Label.new()
	_ok_button = Button.new()
	_ok_button.text = "OK"

	_style_title(_title_label)
	_style_heading(_heading_label)
	_style_body(_body_label)
	_style_body(_practical_label)
	_style_body(_unlock_label)
	_style_ok(_ok_button)

	root.add_child(_title_label)
	root.add_child(_heading_label)
	root.add_child(HSeparator.new())
	root.add_child(_body_label)
	root.add_child(_practical_label)
	root.add_child(_unlock_label)
	root.add_child(_ok_button)

	_ok_button.pressed.connect(_on_ok_pressed)


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


func _style_heading(l: Label) -> void:
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(0.36, 0.32, 0.28, 1.0))


func _style_body(l: Label) -> void:
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(0.14, 0.13, 0.11, 1.0))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _style_ok(btn: Button) -> void:
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


func _apply_visible_view_model(vm: Dictionary) -> void:
	if _title_label == null:
		return
	_title_label.text = str(vm.get("title", ""))
	_heading_label.text = str(vm.get("heading", ""))
	_body_label.text = str(vm.get("body", ""))
	var pl = str(vm.get("practical_line", ""))
	_practical_label.text = pl
	_practical_label.visible = not pl.is_empty()
	_unlock_label.text = str(vm.get("unlock_block", ""))
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP


func maybe_show_for_log_index(index: int) -> void:
	if game_state == null or game_state.log == null:
		return
	if _title_label == null:
		return
	var log_ref = game_state.log
	if index < 0 or index >= log_ref.size():
		return
	var raw_entry = log_ref.get_entry(index)
	var vm = compute_view_model(raw_entry)
	if not bool(vm.get("visible", false)):
		return
	_apply_visible_view_model(vm)


func _on_ok_pressed() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var idx = _pending_science_completed_log_index
	var follow = _followup_science_popup
	_pending_science_completed_log_index = -1
	_followup_science_popup = null
	if idx >= 0 and follow != null:
		follow.maybe_show_for_log_index(idx)
