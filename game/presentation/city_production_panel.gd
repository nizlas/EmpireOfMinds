# Selected-city HUD hub: yields + breakdown + **LegalActions** production only (no content registries).
# Phase 5.1.5: restrained parchment-style presentation; behavior unchanged.
# Phase 5.1.16e: read-only **CityYields** summary + **5.1.17d** breakdown line (no terrain rules in this file).
# Phase 5.1.17g: **City Hub** header (name, pop), lower-right anchoring in **main.tscn**; **Manage Citizens** + **Close** (clears city selection).
# Phase **5.1.17i**: **CityViewState** **PLANNING** from **Manage Citizens**; **Done** exits planning; **Close** resets submode + clears city.
# File remains **city_production_panel.gd** / **CityProductionPanel** — see **[CITY_UX.md](../../docs/CITY_UX.md)**.
# See docs/CITIES.md, docs/RENDERING.md
class_name CityProductionPanel
extends PanelContainer

const LegalActionsScript = preload("res://domain/legal_actions.gd")
const SetCityProductionScript = preload("res://domain/actions/set_city_production.gd")
const CityYieldsScript = preload("res://domain/city_yields.gd")
const FoodGrowthTickScript = preload("res://domain/food_growth_tick.gd")

const HUB_BRAND: String = "City Hub"
const MANAGE_CITIZENS_LABEL: String = "Manage Citizens"
const DONE_PLANNING_LABEL: String = "Done"
const PLANNING_BANNER: String = "Planning mode — worked tiles highlighted (read-only)."
const CLOSE_LABEL: String = "Close"

var game_state
var selection
var city_view_state = null
var cities_view
var turn_label
var log_view
var city_nameplate_view
## Wired from **main.gd** so **Close** redraws territory / worked-tile overlays without new selection architecture.
var selection_view
var city_territory_view
var city_worked_tiles_view
## Slice C8: **CityProductionPanel** applies **set_city_production** via FastAPI when true.
var use_cloud_server: bool = false
var cloud_play_host = null
## Entries: `{ "city_id": int, "label": String, "action": Dictionary }` from server legal-actions.
var cloud_production_options: Array = []

var _root_vbox: VBoxContainer
var _title_label: Label
var _identity_label: Label
var _subheader_label: Label
var _yields_label: Label
var _breakdown_label: Label
var _growth_label: Label
var _planning_banner_label: Label
var _hub_actions_row: HBoxContainer
var _manage_citizens_btn: Button
var _done_planning_btn: Button
var _close_btn: Button
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
	_identity_label = Label.new()
	_subheader_label = Label.new()
	_status_label = Label.new()
	_planning_banner_label = Label.new()
	_style_muted_label(_planning_banner_label)
	_planning_banner_label.visible = false

	_hub_actions_row = HBoxContainer.new()
	_hub_actions_row.add_theme_constant_override("separation", 10)
	_manage_citizens_btn = Button.new()
	_manage_citizens_btn.focus_mode = Control.FOCUS_NONE
	_manage_citizens_btn.pressed.connect(_on_manage_citizens_pressed)
	_done_planning_btn = Button.new()
	_done_planning_btn.focus_mode = Control.FOCUS_NONE
	_done_planning_btn.pressed.connect(_on_done_planning_pressed)
	_style_production_button(_done_planning_btn)
	_close_btn = Button.new()
	_close_btn.focus_mode = Control.FOCUS_NONE
	_close_btn.pressed.connect(_on_hub_close_pressed)
	_actions_block = VBoxContainer.new()
	_actions_block.add_theme_constant_override("separation", 8)
	_actions_heading_label = Label.new()
	_actions_empty_label = Label.new()
	_btn_container = VBoxContainer.new()
	_btn_container.add_theme_constant_override("separation", 6)

	_style_title_label(_title_label)
	_style_subheader_label(_identity_label)
	_style_subheader_label(_subheader_label)
	_style_body_label(_status_label)
	_style_section_heading(_actions_heading_label)
	_style_muted_label(_actions_empty_label)
	_style_production_button(_manage_citizens_btn)
	_style_production_button(_close_btn)

	_root_vbox.add_child(_title_label)
	_root_vbox.add_child(_planning_banner_label)
	_root_vbox.add_child(_identity_label)
	_root_vbox.add_child(_subheader_label)
	_yields_label = Label.new()
	_style_body_label(_yields_label)
	_yields_label.visible = false
	_root_vbox.add_child(_yields_label)
	_breakdown_label = Label.new()
	_style_muted_label(_breakdown_label)
	_breakdown_label.visible = false
	_root_vbox.add_child(_breakdown_label)
	_growth_label = Label.new()
	_style_muted_label(_growth_label)
	_growth_label.visible = false
	_root_vbox.add_child(_growth_label)
	_root_vbox.add_child(HSeparator.new())
	_hub_actions_row.add_child(_manage_citizens_btn)
	_hub_actions_row.add_child(_done_planning_btn)
	_hub_actions_row.add_child(_close_btn)
	_root_vbox.add_child(_hub_actions_row)
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
	var parts = s.split("_")
	var out = ""
	var pi = 0
	while pi < parts.size():
		var seg: String = str(parts[pi])
		if not seg.is_empty():
			if out.length() > 0:
				out = out + " "
			out = out + seg.capitalize()
		pi = pi + 1
	return out if out.length() > 0 else s.capitalize()


static func _compact_yield_tokens(y: Dictionary) -> String:
	return "%dF %dP %dS %dC" % [
		CityYieldsScript.get_yield(y, "food"),
		CityYieldsScript.get_yield(y, "production"),
		CityYieldsScript.get_yield(y, "science"),
		CityYieldsScript.get_yield(y, "coin"),
	]


static func _breakdown_line_from_breakdown(brk: Dictionary) -> String:
	if brk == null or typeof(brk) != TYPE_DICTIONARY or brk.is_empty():
		return ""
	if not brk.has("center") or not brk.has("buildings") or not brk.has("worked"):
		return ""
	var c = brk["center"] as Dictionary
	var b = brk["buildings"] as Dictionary
	var w = brk["worked"] as Dictionary
	return "Center %s + Buildings %s + Worked %s" % [
		_compact_yield_tokens(c),
		_compact_yield_tokens(b),
		_compact_yield_tokens(w),
	]


static func compute_view_model(game_state, selection, city_view_state = null) -> Dictionary:
	var vm = {
		"visible": false,
		"header": "",
		"header_title": "",
		"hub_brand": "",
		"identity_line": "",
		"subheader": "",
		"manage_citizens_button_text": MANAGE_CITIZENS_LABEL,
		"manage_citizens_disabled": true,
		"done_planning_visible": false,
		"done_planning_button_text": DONE_PLANNING_LABEL,
		"planning_banner_text": "",
		"planning_active": false,
		"close_button_text": CLOSE_LABEL,
		"show_yields": false,
		"yields": {},
		"yields_line": "",
		"breakdown_line": "",
		"growth_line": "",
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
	if game_state.scenario != null:
		var yt: Dictionary = CityYieldsScript.city_total_yield(game_state.scenario, city)
		var fd: int = CityYieldsScript.get_yield(yt, "food")
		var pd: int = CityYieldsScript.get_yield(yt, "production")
		var sd: int = CityYieldsScript.get_yield(yt, "science")
		var cd: int = CityYieldsScript.get_yield(yt, "coin")
		vm["show_yields"] = true
		vm["yields"] = {"food": fd, "production": pd, "science": sd, "coin": cd}
		vm["yields_line"] = "Yields: %d Food · %d Production · %d Science · %d Coin" % [fd, pd, sd, cd]
		var brk: Dictionary = CityYieldsScript.yield_breakdown_for_city(game_state.scenario, city)
		vm["breakdown_line"] = _breakdown_line_from_breakdown(brk)
	var cp = game_state.turn_state.current_player_id()
	vm["visible"] = true
	var planning_now: bool = city_view_state != null and city_view_state.is_planning()
	vm["planning_active"] = planning_now
	vm["planning_banner_text"] = PLANNING_BANNER if planning_now else ""
	var cname: String = str(city.city_name).strip_edges()
	var title: String = cname if cname != "" else "City"
	vm["header_title"] = title
	vm["header"] = title
	vm["hub_brand"] = HUB_BRAND
	vm["identity_line"] = "%s · Pop %d" % [title, city.population]
	vm["subheader"] = "#%d · Owner %d" % [cid, city.owner_id]
	if city.owner_id != cp:
		vm["status"] = "Not your city (owner is player %d)." % city.owner_id
		vm["show_production_section"] = false
		vm["options"] = []
		vm["manage_citizens_disabled"] = true
		vm["done_planning_visible"] = false
		vm["growth_line"] = ""
		return vm
	vm["manage_citizens_disabled"] = planning_now
	vm["done_planning_visible"] = planning_now
	if bool(vm.get("show_yields", false)):
		var y_g: Dictionary = CityYieldsScript.city_total_yield(game_state.scenario, city)
		var food_tot: int = CityYieldsScript.get_yield(y_g, "food")
		var surplus_raw: int = food_tot - city.population * 2
		var surplus_disp: int = maxi(0, surplus_raw)
		var thr: int = FoodGrowthTickScript.growth_threshold(city.population)
		vm["growth_line"] = "Growth: %d / %d (+%d/turn)" % [city.food_stored, thr, surplus_disp]
	vm["show_production_section"] = true
	vm["actions_heading"] = "Available production"
	if city.current_project == null:
		vm["status"] = "No active project."
	else:
		if typeof(city.current_project) != TYPE_DICTIONARY:
			vm["status"] = "Production in progress."
		else:
			var cproj = city.current_project as Dictionary
			var pid = str(cproj.get("project_id", ""))
			var prog = int(cproj.get("progress", 0))
			var cost = int(cproj.get("cost", 0))
			var ready = bool(cproj.get("ready", false))
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
		var label_prefix = "Train "
		if proj_id.begins_with("build:"):
			label_prefix = "Build "
		opts.append(
			{
				"label": "%s%s" % [label_prefix, hn_opt],
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
	var vm = compute_view_model(game_state, selection, city_view_state)
	if use_cloud_server:
		vm["manage_citizens_disabled"] = true
		vm["done_planning_visible"] = false
		vm["planning_active"] = false
		vm["planning_banner_text"] = ""
		if bool(vm.get("show_production_section", false)) and selection.has_city() and cloud_production_options.size() > 0:
			var cid = selection.city_id
			var opts_cloud: Array = []
			var pi = 0
			while pi < cloud_production_options.size():
				var row = cloud_production_options[pi]
				pi += 1
				if typeof(row) != TYPE_DICTIONARY:
					continue
				var rd = row as Dictionary
				if int(rd.get("city_id", -2)) != cid:
					continue
				opts_cloud.append(
					{"label": str(rd.get("label", "")), "action": rd.get("action", {})}
				)
			if opts_cloud.size() > 0:
				vm["options"] = opts_cloud
				vm["actions_empty"] = ""
	var show_panel = bool(vm.get("visible", false))
	visible = show_panel
	mouse_filter = Control.MOUSE_FILTER_STOP if show_panel else Control.MOUSE_FILTER_IGNORE
	if not show_panel:
		_title_label.text = ""
		if _planning_banner_label != null:
			_planning_banner_label.text = ""
			_planning_banner_label.visible = false
		if _identity_label != null:
			_identity_label.text = ""
		_subheader_label.text = ""
		if _hub_actions_row != null:
			_hub_actions_row.visible = false
		if _yields_label != null:
			_yields_label.text = ""
			_yields_label.visible = false
		if _breakdown_label != null:
			_breakdown_label.text = ""
			_breakdown_label.visible = false
		if _growth_label != null:
			_growth_label.text = ""
			_growth_label.visible = false
		_status_label.text = ""
		_actions_heading_label.text = ""
		_actions_empty_label.text = ""
		_actions_empty_label.visible = false
		_actions_heading_label.visible = false
		_actions_block.visible = false
		_clear_buttons()
		return
	_title_label.text = str(vm.get("hub_brand", HUB_BRAND))
	if _planning_banner_label != null:
		var pb: String = str(vm.get("planning_banner_text", ""))
		_planning_banner_label.text = pb
		_planning_banner_label.visible = pb.length() > 0
	if _identity_label != null:
		_identity_label.text = str(vm.get("identity_line", ""))
	_subheader_label.text = str(vm.get("subheader", ""))
	if _hub_actions_row != null:
		_hub_actions_row.visible = true
	if _manage_citizens_btn != null:
		_manage_citizens_btn.text = str(vm.get("manage_citizens_button_text", MANAGE_CITIZENS_LABEL))
		_manage_citizens_btn.disabled = bool(vm.get("manage_citizens_disabled", true))
	if _done_planning_btn != null:
		var dv: bool = bool(vm.get("done_planning_visible", false))
		_done_planning_btn.visible = dv
		_done_planning_btn.disabled = not dv
		_done_planning_btn.text = str(vm.get("done_planning_button_text", DONE_PLANNING_LABEL))
	if _close_btn != null:
		_close_btn.text = str(vm.get("close_button_text", CLOSE_LABEL))
		_close_btn.disabled = false
	if _yields_label != null:
		var show_y: bool = bool(vm.get("show_yields", false))
		if show_y:
			_yields_label.text = str(vm.get("yields_line", ""))
			_yields_label.visible = _yields_label.text.length() > 0
		else:
			_yields_label.text = ""
			_yields_label.visible = false
	if _breakdown_label != null:
		var show_br: bool = bool(vm.get("show_yields", false))
		if show_br:
			_breakdown_label.text = str(vm.get("breakdown_line", ""))
			_breakdown_label.visible = _breakdown_label.text.length() > 0
		else:
			_breakdown_label.text = ""
			_breakdown_label.visible = false
	if _growth_label != null:
		var show_gr: bool = bool(vm.get("show_yields", false))
		if show_gr:
			_growth_label.text = str(vm.get("growth_line", ""))
			_growth_label.visible = _growth_label.text.length() > 0
		else:
			_growth_label.text = ""
			_growth_label.visible = false
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
	if use_cloud_server and cloud_play_host != null:
		if (
			cloud_play_host.has_method("cloud_blocks_gameplay_actions")
			and cloud_play_host.cloud_blocks_gameplay_actions()
		):
			return
		cloud_play_host.call_deferred("cloud_post_action_async_entry", action.duplicate(true))
		return
	var result = game_state.try_apply(action)
	if result["accepted"]:
		if cities_view != null:
			cities_view.scenario = game_state.scenario
			cities_view.queue_redraw()
		if city_nameplate_view != null:
			city_nameplate_view.scenario = game_state.scenario
			city_nameplate_view.queue_redraw()
		if turn_label != null:
			turn_label.refresh()
		if log_view != null:
			log_view.refresh()
		# Defer: refresh() frees dynamic Buttons; cannot rebuild during the emitting pressed callback.
		call_deferred("refresh")
	else:
		push_warning("SetCityProduction rejected: %s" % result["reason"])


func _refresh_hub_overlay_views() -> void:
	if selection_view != null:
		selection_view.queue_redraw()
	if city_territory_view != null:
		city_territory_view.queue_redraw()
	if city_worked_tiles_view != null:
		city_worked_tiles_view.queue_redraw()


func _on_manage_citizens_pressed() -> void:
	if city_view_state == null or selection == null or not selection.has_city():
		return
	city_view_state.enter_planning()
	_refresh_hub_overlay_views()
	refresh()


func _on_done_planning_pressed() -> void:
	if city_view_state == null:
		return
	city_view_state.exit_planning()
	_refresh_hub_overlay_views()
	refresh()


func _on_hub_close_pressed() -> void:
	if selection == null:
		return
	if city_view_state != null:
		city_view_state.reset_to_normal()
	selection.clear_city()
	if selection_view != null:
		selection_view.queue_redraw()
	if city_territory_view != null:
		city_territory_view.queue_redraw()
	if city_worked_tiles_view != null:
		city_worked_tiles_view.queue_redraw()
	refresh()
