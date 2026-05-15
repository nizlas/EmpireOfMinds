# Phase **5.2.2** — compact **player / seat** HUD (local hotseat v0). **Not** diplomacy, contact rules, fog, or networking.
# Reads **`GameState.turn_state`** only (`players`, **`current_player_id()`**). **Accent** = **`UnitNameplateView.owner_nameplate_accent_color`**, same as **`TurnStatusPanel`** / **`EmpireBorderView`** nameplate path.
# Each entry includes **`contact_state`** (**`known`** for v0) for future **unknown / remote / diplomacy** slices — no filtering yet.
class_name PlayerContactStrip
extends Control

const UnitNameplateViewScript = preload("res://presentation/unit_nameplate_view.gd")

var game_state = null
var _hbox: HBoxContainer


static func compute_view_model(gs) -> Dictionary:
	if gs == null or gs.turn_state == null:
		return {"visible": false, "entries": []}
	var ts = gs.turn_state
	var cur: int = int(ts.current_player_id())
	var entries: Array = []
	var i: int = 0
	while i < ts.players.size():
		var pid: int = int(ts.players[i])
		var accent: Color = UnitNameplateViewScript.owner_nameplate_accent_color(pid)
		entries.append({
			"player_id": pid,
			"label_short": "P%d" % pid,
			"label_long": "Player %d" % pid,
			"is_current_turn": pid == cur,
			"accent_color": accent,
			"contact_state": "known",
		})
		i = i + 1
	return {"visible": entries.size() > 0, "entries": entries}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var outer := PanelContainer.new()
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.offset_left = 0.0
	outer.offset_top = 0.0
	outer.offset_right = 0.0
	outer.offset_bottom = 0.0
	var plate := StyleBoxFlat.new()
	plate.set_corner_radius_all(6)
	plate.bg_color = Color(0.06, 0.07, 0.09, 0.72)
	plate.set_border_width_all(1)
	plate.border_color = Color(0.22, 0.23, 0.28, 0.9)
	outer.add_theme_stylebox_override("panel", plate)
	add_child(outer)
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.offset_left = 0.0
	margin.offset_top = 0.0
	margin.offset_right = 0.0
	margin.offset_bottom = 0.0
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 6)
	outer.add_child(margin)
	_hbox = HBoxContainer.new()
	_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hbox.add_theme_constant_override("separation", 8)
	margin.add_child(_hbox)


func refresh() -> void:
	if _hbox == null:
		return
	for c in _hbox.get_children():
		c.free()
	var vm: Dictionary = compute_view_model(game_state)
	var entries: Array = vm.get("entries", []) as Array
	visible = bool(vm.get("visible", false)) and not entries.is_empty()
	if not visible:
		custom_minimum_size = Vector2(48.0, 44.0)
		return
	var ei: int = 0
	while ei < entries.size():
		_hbox.add_child(_make_chip(entries[ei] as Dictionary))
		ei = ei + 1
	custom_minimum_size = Vector2(20.0 + float(entries.size()) * 64.0, 52.0)


func _make_chip(entry: Dictionary) -> Control:
	var pid: int = int(entry.get("player_id", -1))
	var is_cur: bool = bool(entry.get("is_current_turn", false))
	var accent: Color = entry.get("accent_color", Color.GRAY) as Color
	var short_l: String = str(entry.get("label_short", "?"))

	var wrap := PanelContainer.new()
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.custom_minimum_size = Vector2(54, 40)
	var chip := StyleBoxFlat.new()
	chip.set_corner_radius_all(20)
	if is_cur:
		chip.bg_color = Color(accent.r, accent.g, accent.b, 0.88)
		chip.set_border_width_all(3)
		chip.border_color = Color(0.95, 0.96, 0.98, 0.95)
	else:
		chip.bg_color = Color(accent.r, accent.g, accent.b, 0.38)
		chip.set_border_width_all(1)
		chip.border_color = Color(accent.r * 0.55, accent.g * 0.55, accent.b * 0.55, 0.75)
	wrap.add_theme_stylebox_override("panel", chip)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	wrap.add_child(margin)

	var lbl := Label.new()
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.text = short_l
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if is_cur:
		lbl.modulate = Color(0.98, 0.98, 1.0)
	else:
		lbl.modulate = Color(0.82, 0.84, 0.88)
	lbl.add_theme_font_size_override("font_size", 14)
	margin.add_child(lbl)

	wrap.tooltip_text = str(entry.get("label_long", "Player %d" % pid))
	return wrap
