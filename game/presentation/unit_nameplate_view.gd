# Phase 5.1.11 — Compact code-drawn nameplates above unit markers (type + owner accent).
# Presentation-only; no input, no hit-testing. See docs/RENDERING.md
class_name UnitNameplateView
extends Node2D

const UnitDefinitionsScript = preload("res://domain/content/unit_definitions.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")

## Shared with main: parchment map layer uses linear mipmaps for markers.
const _NAMEPLATE_FONT_SIZE: int = 12
## **StyleBoxFlat** border drawn inside **banner_r**; inset geometry uses this thickness.
const _BANNER_BORDER_PX: float = 1.0
## Owner/nation accent: **visible** vertical strip inside the border (**presentation px**, ~22–28).
const _OWNER_STRIP_WIDTH_PX: float = 25.0
## Horizontal padding: gap after strip, and inset before the right inner edge (text centered in the text column).
const _PAD_AFTER_STRIP_PX: float = 8.0
const _PAD_TEXT_END_PX: float = 8.0
const _PAD_Y_PX: float = 3.0


## Width of the **left** owner-color strip (screen-space px in map layer coordinates).
static func owner_strip_width_px() -> float:
	return _OWNER_STRIP_WIDTH_PX

var scenario
var layout
var camera
## Used to align banner Y with PNG marker top (same geometry as TerrainForegroundView marker pass).
var units_view


static func _humanize_type_id(raw: String) -> String:
	var s = raw.strip_edges()
	if s.is_empty():
		return "Unit"
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
	return "Unit"


## Prefer **UnitDefinitions** **display_name** when present; else prototype ids; else humanize. Presentation-only.
static func display_name_for_type_id(type_id: String) -> String:
	var tid = type_id.strip_edges()
	if tid.is_empty():
		return "Unit"
	if UnitDefinitionsScript.has(tid):
		var def = UnitDefinitionsScript.get_definition(tid)
		if def != null and def.has("display_name"):
			var dn = str(def["display_name"]).strip_edges()
			if not dn.is_empty():
				return dn
	if tid == "warrior":
		return "Warrior"
	if tid == "settler":
		return "Settler"
	return _humanize_type_id(tid)


## Muted prototype palette (distinct from **UnitsView** marker disk colors). Stable per **owner_id**.
static func owner_nameplate_accent_color(owner_id: int) -> Color:
	if owner_id == 0:
		return Color(0.38, 0.56, 0.62, 1.0)
	if owner_id == 1:
		return Color(0.58, 0.32, 0.36, 1.0)
	if owner_id == 2:
		return Color(0.44, 0.50, 0.38, 1.0)
	if owner_id == 3:
		return Color(0.52, 0.44, 0.58, 1.0)
	var seed = int(abs(owner_id * 1103515245 + 12345)) % 100000
	var hue = float(seed % 360) / 360.0
	return Color.from_hsv(hue, 0.35, 0.55, 1.0)


static func _marker_top_presentation_y(
	anchor_pres: Vector2,
	pscale: float,
	type_id: String,
	a_units_view
) -> float:
	if a_units_view == null:
		var hex_h: float = HexLayoutScript.SIZE * 2.0
		return anchor_pres.y - hex_h * 0.35 * pscale
	var rect: Rect2 = a_units_view.unit_marker_texture_rect_presentation(anchor_pres, pscale, type_id)
	if rect.size.x > 0.0:
		return rect.position.y
	var hex_h2: float = HexLayoutScript.SIZE * 2.0
	var r_disk: float = hex_h2 * a_units_view.marker_radius_ratio * pscale
	return anchor_pres.y - r_disk * 1.85


## Banner **Rect2** centered on **anchor_pres.x**, sitting above **marker_top_y** (smaller **y** = higher on screen).
static func compute_nameplate_rect(
	anchor_pres: Vector2,
	marker_top_y: float,
	pscale: float,
	label: String,
	font: Font,
	font_size: int
) -> Rect2:
	var gap: float = 6.0 + 2.0 * clamp(pscale, 0.8, 1.25)
	var bw: float = _BANNER_BORDER_PX
	var strip_w: float = owner_strip_width_px()
	var sz: Vector2 = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var inner_row_w: float = strip_w + _PAD_AFTER_STRIP_PX + sz.x + _PAD_TEXT_END_PX
	var w: float = inner_row_w + 2.0 * bw
	var inner_h: float = max(float(font_size) + _PAD_Y_PX * 2.0, 17.0)
	var h: float = inner_h + 2.0 * bw
	var cy: float = marker_top_y - gap - h * 0.5
	return Rect2(anchor_pres.x - w * 0.5, cy - h * 0.5, w, h)


static func compute_all_nameplate_rects(p_scenario, p_layout, p_camera, p_units_view) -> Array:
	var out: Array = []
	if p_scenario == null or p_layout == null or p_camera == null:
		return out
	var font: Font = ThemeDB.fallback_font
	var fs: int = _NAMEPLATE_FONT_SIZE
	var ulist = p_scenario.units()
	var i = 0
	while i < ulist.size():
		var u = ulist[i]
		var wc = p_layout.hex_to_world(u.position.q, u.position.r)
		var anchor = p_camera.to_presentation(wc)
		var pscale: float = p_camera.perspective_scale_at(wc)
		var top_y = _marker_top_presentation_y(anchor, pscale, u.type_id, p_units_view)
		var label = display_name_for_type_id(u.type_id)
		out.append(compute_nameplate_rect(anchor, top_y, pscale, label, font, fs))
		i = i + 1
	return out


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	queue_redraw()


func _draw() -> void:
	if scenario == null or layout == null or camera == null:
		return
	var ulist = scenario.units()
	if ulist.is_empty():
		return
	var font: Font = ThemeDB.fallback_font
	var fs: int = _NAMEPLATE_FONT_SIZE
	var i = 0
	while i < ulist.size():
		var u = ulist[i]
		var wc = layout.hex_to_world(u.position.q, u.position.r)
		var anchor = camera.to_presentation(wc)
		var pscale: float = camera.perspective_scale_at(wc)
		var top_y = _marker_top_presentation_y(anchor, pscale, u.type_id, units_view)
		var label = display_name_for_type_id(u.type_id)
		var banner_r: Rect2 = compute_nameplate_rect(anchor, top_y, pscale, label, font, fs)
		var bw: float = _BANNER_BORDER_PX
		var inner := Rect2(
			banner_r.position.x + bw,
			banner_r.position.y + bw,
			banner_r.size.x - 2.0 * bw,
			banner_r.size.y - 2.0 * bw
		)
		var strip_w: float = owner_strip_width_px()
		var accent: Color = owner_nameplate_accent_color(u.owner_id)
		var strip_r := Rect2(inner.position.x, inner.position.y, strip_w, inner.size.y)
		var body_sb := StyleBoxFlat.new()
		body_sb.bg_color = Color(0.90, 0.84, 0.74, 0.94)
		body_sb.border_color = Color(0.42, 0.36, 0.30, 0.92)
		body_sb.set_border_width_all(int(bw))
		body_sb.set_corner_radius_all(4)
		draw_style_box(body_sb, banner_r)
		draw_rect(strip_r, Color(accent.r, accent.g, accent.b, 0.92))
		var sep_x: float = inner.position.x + strip_w
		draw_line(
			Vector2(sep_x, inner.position.y + 1.0),
			Vector2(sep_x, inner.position.y + inner.size.y - 1.0),
			Color(0.42, 0.36, 0.30, 0.40),
			1.0
		)
		var thin_line_y0: float = banner_r.position.y + banner_r.size.y - bw
		draw_line(
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
		draw_string(
			font,
			Vector2(text_x, text_baseline),
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			fs,
			Color(0.12, 0.10, 0.09, 0.95)
		)
		i = i + 1
