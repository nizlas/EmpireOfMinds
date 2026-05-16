# Phase **5.1.19f** — lower-right **current player** strip (hotseat / local prototype). **Not** the city hub.
# Reads **`GameState.turn_state`** only. **Wording** describes **who is playing now** in this app (shared hotseat), not remote “waiting”.
# **Colors** reuse **`UnitNameplateView.owner_nameplate_accent_color`** — same owner accent source as **`EmpireBorderView`** / city+unit nameplate strips (see **`empire_border_view.gd`**).
class_name TurnStatusPanel
extends PanelContainer

const UnitNameplateViewScript = preload("res://presentation/unit_nameplate_view.gd")
const PlaytestPlayerDisplayScript = preload("res://presentation/playtest_player_display.gd")

var game_state = null
## Reserved for a future **remote seat** slice; **ignored** for copy/styling in local hotseat mode (**`compute_view_model`** takes it for a stable call signature / **`refresh`** wiring).
@export var local_player_id: int = 0

var _orb: ColorRect
var _title: Label
var _detail: Label
var _style: StyleBoxFlat


static func _colors_for_current_player(owner_id: int) -> Dictionary:
	var accent: Color = UnitNameplateViewScript.owner_nameplate_accent_color(owner_id)
	var orb := Color(accent.r, accent.g, accent.b, 1.0)
	var panel_bg: Color = Color(0.07, 0.08, 0.10, 0.94).lerp(
		Color(accent.r, accent.g, accent.b, 1.0),
		0.24
	)
	var border := Color(
		clampf(accent.r * 1.08, 0.0, 1.0),
		clampf(accent.g * 1.08, 0.0, 1.0),
		clampf(accent.b * 1.08, 0.0, 1.0),
		0.98
	)
	return {"orb_color": orb, "panel_bg": panel_bg, "border_color": border}


## **`_local_id`** is currently unused (hotseat); kept so **`refresh()`** / callers stay stable.
static func compute_view_model(gs, _local_id: int = 0) -> Dictionary:
	if gs == null or gs.turn_state == null:
		return {
			"title": "—",
			"detail": "",
			"orb_color": Color(0.42, 0.42, 0.48),
			"panel_bg": Color(0.09, 0.09, 0.11, 0.92),
			"border_color": Color(0.28, 0.28, 0.34),
		}
	var cur: int = int(gs.turn_state.current_player_id())
	var tnum: int = int(gs.turn_state.turn_number)
	var cols: Dictionary = _colors_for_current_player(cur)
	var pname: String = PlaytestPlayerDisplayScript.display_name_for_player_id(cur)
	return {
		"title": "%s's turn" % pname,
		"detail": "Turn %d" % tnum,
		"orb_color": cols["orb_color"],
		"panel_bg": cols["panel_bg"],
		"border_color": cols["border_color"],
	}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(196, 56)
	_style = StyleBoxFlat.new()
	_style.set_corner_radius_all(6)
	_style.set_border_width_all(2)
	add_theme_stylebox_override("panel", _style)

	var outer := MarginContainer.new()
	outer.add_theme_constant_override("margin_left", 10)
	outer.add_theme_constant_override("margin_top", 8)
	outer.add_theme_constant_override("margin_right", 10)
	outer.add_theme_constant_override("margin_bottom", 8)
	add_child(outer)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	outer.add_child(hbox)

	_orb = ColorRect.new()
	_orb.custom_minimum_size = Vector2(22, 22)
	_orb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(_orb)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(vbox)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(_title)

	_detail = Label.new()
	_detail.add_theme_font_size_override("font_size", 12)
	_detail.modulate = Color(0.88, 0.88, 0.93)
	vbox.add_child(_detail)


func refresh() -> void:
	if _title == null or _orb == null or _style == null:
		return
	var vm: Dictionary = compute_view_model(game_state, local_player_id)
	_title.text = str(vm.get("title", ""))
	_detail.text = str(vm.get("detail", ""))
	_orb.color = vm.get("orb_color", Color.GRAY) as Color
	_style.bg_color = vm.get("panel_bg", Color(0.1, 0.1, 0.1)) as Color
	_style.border_color = vm.get("border_color", Color(0.3, 0.3, 0.3)) as Color
