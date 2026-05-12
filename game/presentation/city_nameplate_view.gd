# Phase 5.1.15 — Code-drawn city name banners above city markers (owner strip = unit nameplates).
# Phase 5.1.15b — Tighter vertical gap + larger type; draw **before** unit nameplates in scene order so units read on top on shared hex.
# Phase 5.1.15e — Shared city/unit hex: same banner placement as normal (near marker). Banner draws inside **TerrainForegroundView**
# after the city marker and before the unit sprite so the unit paints over the parchment; **UnitNameplateView** stays topmost.
# Presentation-only; no input / hit-testing. See docs/RENDERING.md
class_name CityNameplateView
extends Node2D

const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const UnitNameplateViewScript = preload("res://presentation/unit_nameplate_view.gd")
## **4.3f** default textured city height ratio — must match **CitiesView** default when **`cities_view` null** for fallback geometry.
const _FALLBACK_CITY_ICON_HEIGHT_RATIO: float = 0.90

## Slightly larger than **UnitNameplateView** (**12**) for city readability; keep compact vs a full city bar.
const CITY_BANNER_FONT_SIZE: int = 16
const _BANNER_BORDER_PX: float = 1.0
const _PAD_AFTER_STRIP_PX: float = 8.0
const _PAD_TEXT_END_PX: float = 8.0
const _PAD_Y_PX: float = 5.0

## **5.1.15e:** default-off logs when shared-hex banner is skipped here (drawn by **TerrainForegroundView** instead).


@export var debug_log_shared_hex_banner: bool = false


## Same width as **UnitNameplateView** owner strip.
static func owner_strip_width_px() -> float:
	return UnitNameplateViewScript.owner_strip_width_px()


var scenario
var layout
var camera
var cities_view
## When set (main wires **TerrainForegroundView**), shared-hex banners are drawn by TFV for correct depth vs unit markers.
var terrain_foreground_view


static func display_label_for_city(city) -> String:
	if city == null:
		return ""
	var raw: String = str(city.city_name).strip_edges()
	if raw != "":
		return raw
	return "City %d" % int(city.id)


## Presentation-only: **true** when any **unit** shares the city’s **hex** (uses **`Scenario.units_at`**).
static func city_hex_has_units(p_scenario, city) -> bool:
	if p_scenario == null or city == null:
		return false
	return p_scenario.units_at(city.position).size() > 0


func delegates_shared_hex_banners_to_foreground() -> bool:
	return terrain_foreground_view != null and is_instance_valid(terrain_foreground_view)


static func _marker_top_presentation_y(anchor_pres: Vector2, pscale: float, a_cities_view) -> float:
	if a_cities_view == null:
		var hex_h: float = HexLayoutScript.SIZE * 2.0
		return anchor_pres.y - hex_h * 0.42 * pscale
	var rect: Rect2 = a_cities_view.city_marker_texture_rect_presentation(anchor_pres, pscale)
	if rect.size.x > 0.0:
		return rect.position.y
	var hex_h2: float = HexLayoutScript.SIZE * 2.0
	return anchor_pres.y - hex_h2 * 0.42 * pscale


static func _eom_debug_shared_hex_banner_env() -> bool:
	return OS.get_environment("EOM_DEBUG_SHARED_HEX_BANNER") == "1"


static func compute_city_banner_rect(
	anchor_pres: Vector2,
	marker_top_y: float,
	pscale: float,
	label: String,
	font: Font,
	font_size: int
) -> Rect2:
	# Small **presentation px** gap between banner bottom and city marker top (5.1.15b: closer than 8–10px band).
	var gap: float = 3.0 + 1.0 * clamp(pscale, 0.8, 1.25)
	var bw: float = _BANNER_BORDER_PX
	var strip_w: float = owner_strip_width_px()
	var sz: Vector2 = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var inner_row_w: float = strip_w + _PAD_AFTER_STRIP_PX + sz.x + _PAD_TEXT_END_PX
	var w: float = inner_row_w + 2.0 * bw
	var inner_h: float = max(float(font_size) + _PAD_Y_PX * 2.0, 22.0)
	var h: float = inner_h + 2.0 * bw
	var cy: float = marker_top_y - gap - h * 0.5
	return Rect2(anchor_pres.x - w * 0.5, cy - h * 0.5, w, h)


## When **`omit_cities_with_units_on_hex`** is **true**, skips cities where **units** share the hex (**TFV** draws those banners in **main**).
static func compute_all_city_banner_rects(
	p_scenario,
	p_layout,
	p_camera,
	p_cities_view,
	omit_cities_with_units_on_hex: bool = false
) -> Array:
	var out: Array = []
	if p_scenario == null or p_layout == null or p_camera == null:
		return out
	var font: Font = ThemeDB.fallback_font
	var fs: int = CITY_BANNER_FONT_SIZE
	var clist = p_scenario.cities()
	var i: int = 0
	while i < clist.size():
		var cty = clist[i]
		if omit_cities_with_units_on_hex and city_hex_has_units(p_scenario, cty):
			i = i + 1
			continue
		var wc = p_layout.hex_to_world(cty.position.q, cty.position.r)
		var anchor = p_camera.to_presentation(wc)
		var pscale: float = p_camera.perspective_scale_at(wc)
		var top_y = _marker_top_presentation_y(anchor, pscale, p_cities_view)
		var label = display_label_for_city(cty)
		out.append(compute_city_banner_rect(anchor, top_y, pscale, label, font, fs))
		i = i + 1
	return out


static func draw_city_banner_on_canvas_item(
	target: CanvasItem,
	p_layout,
	p_camera,
	p_cities_view,
	city
) -> void:
	if target == null or p_layout == null or p_camera == null or city == null:
		return
	var wc: Vector2 = p_layout.hex_to_world(city.position.q, city.position.r)
	var anchor: Vector2 = p_camera.to_presentation(wc)
	var pscale: float = p_camera.perspective_scale_at(wc)
	var top_y: float = _marker_top_presentation_y(anchor, pscale, p_cities_view)
	var label: String = display_label_for_city(city)
	var font: Font = ThemeDB.fallback_font
	var fs: int = CITY_BANNER_FONT_SIZE
	var banner_r: Rect2 = compute_city_banner_rect(anchor, top_y, pscale, label, font, fs)
	_draw_city_banner_primitives(target, banner_r, label, int(city.owner_id), font, fs)


static func _draw_city_banner_primitives(
	target: CanvasItem,
	banner_r: Rect2,
	label: String,
	owner_id: int,
	font: Font,
	fs: int
) -> void:
	var bw: float = _BANNER_BORDER_PX
	var inner := Rect2(
		banner_r.position.x + bw,
		banner_r.position.y + bw,
		banner_r.size.x - 2.0 * bw,
		banner_r.size.y - 2.0 * bw
	)
	var strip_w: float = owner_strip_width_px()
	var accent: Color = UnitNameplateViewScript.owner_nameplate_accent_color(owner_id)
	var strip_r := Rect2(inner.position.x, inner.position.y, strip_w, inner.size.y)
	var body_sb := StyleBoxFlat.new()
	body_sb.bg_color = Color(0.90, 0.84, 0.74, 0.94)
	body_sb.border_color = Color(0.42, 0.36, 0.30, 0.92)
	body_sb.set_border_width_all(int(bw))
	body_sb.set_corner_radius_all(4)
	target.draw_style_box(body_sb, banner_r)
	target.draw_rect(strip_r, Color(accent.r, accent.g, accent.b, 0.92))
	var sep_x: float = inner.position.x + strip_w
	target.draw_line(
		Vector2(sep_x, inner.position.y + 1.0),
		Vector2(sep_x, inner.position.y + inner.size.y - 1.0),
		Color(0.42, 0.36, 0.30, 0.40),
		1.0
	)
	var thin_line_y0: float = banner_r.position.y + banner_r.size.y - bw
	target.draw_line(
		Vector2(banner_r.position.x + bw, thin_line_y0),
		Vector2(banner_r.position.x + banner_r.size.x - bw, thin_line_y0),
		Color(accent.r * 0.72, accent.g * 0.72, accent.b * 0.72, 0.50),
		1.0
	)
	var text_left: float = sep_x + _PAD_AFTER_STRIP_PX
	var text_right: float = inner.position.x + inner.size.x - _PAD_TEXT_END_PX
	var tw: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var text_x: float = text_left + max(0.0, (text_right - text_left - tw) * 0.5)
	var text_baseline: float = (
		inner.position.y + (inner.size.y - float(fs)) * 0.5 + font.get_ascent(fs) * 0.88
	)
	target.draw_string(
		font,
		Vector2(text_x, text_baseline),
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		fs,
		Color(0.12, 0.10, 0.09, 0.95)
	)


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	queue_redraw()


func _draw() -> void:
	if scenario == null or layout == null or camera == null:
		return
	var clist = scenario.cities()
	if clist.is_empty():
		return
	var font: Font = ThemeDB.fallback_font
	var fs: int = CITY_BANNER_FONT_SIZE
	var log_banner: bool = debug_log_shared_hex_banner or _eom_debug_shared_hex_banner_env()
	var i: int = 0
	while i < clist.size():
		var cty = clist[i]
		if delegates_shared_hex_banners_to_foreground() and city_hex_has_units(scenario, cty):
			if log_banner:
				print(
					(
						"[EOM_DEBUG_SHARED_HEX_BANNER] city_id=%d hex=(%d,%d) banner_delegated_to_tfv"
						% [int(cty.id), int(cty.position.q), int(cty.position.r)]
					)
				)
			i = i + 1
			continue
		var wc = layout.hex_to_world(cty.position.q, cty.position.r)
		var anchor = camera.to_presentation(wc)
		var pscale: float = camera.perspective_scale_at(wc)
		var top_y = _marker_top_presentation_y(anchor, pscale, cities_view)
		var label = display_label_for_city(cty)
		var banner_r: Rect2 = compute_city_banner_rect(anchor, top_y, pscale, label, font, fs)
		_draw_city_banner_primitives(self, banner_r, label, int(cty.owner_id), font, fs)
		i = i + 1
