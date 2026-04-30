# F1 debug overlay: shows prototype faction banners for FactionDefinitions debug rows only. No gameplay effect.
class_name FactionBannerGallery
extends CanvasLayer

const FactionDefinitionsScript = preload("res://domain/content/faction_definitions.gd")
const FactionAssetPathsScript = preload("res://presentation/faction_asset_paths.gd")

## Built in _ready; one column per faction id in FactionDefinitions.ids().
var banner_row: HBoxContainer


func _ready() -> void:
	visible = false
	layer = 128
	_build_ui()


func toggle_visible() -> void:
	visible = not visible


static func resolve_banner_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if not ResourceLoader.exists(path):
		return null
	var res = ResourceLoader.load(path)
	if res is Texture2D:
		return res as Texture2D
	return null


func _build_ui() -> void:
	var root_margin := MarginContainer.new()
	root_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_margin.add_theme_constant_override("margin_left", 16)
	root_margin.add_theme_constant_override("margin_right", 16)
	root_margin.add_theme_constant_override("margin_top", 16)
	root_margin.add_theme_constant_override("margin_bottom", 16)
	add_child(root_margin)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_margin.add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)

	banner_row = HBoxContainer.new()
	banner_row.name = "BannerRow"
	banner_row.add_theme_constant_override("separation", 24)
	scroll.add_child(banner_row)

	var ids: Array = FactionDefinitionsScript.ids()
	var i: int = 0
	while i < ids.size():
		var id_str: String = str(ids[i])
		banner_row.add_child(_make_faction_column(id_str))
		i = i + 1


func _make_faction_column(faction_id: String) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	var title := Label.new()
	title.text = FactionDefinitionsScript.display_name(faction_id)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(title)

	var path_str: String = FactionAssetPathsScript.banner_path(faction_id)
	var tex: Texture2D = resolve_banner_texture(path_str)
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = Vector2(200, 200)
		col.add_child(tr)
	else:
		var ph := PanelContainer.new()
		ph.custom_minimum_size = Vector2(200, 200)
		var ph_lbl := Label.new()
		ph_lbl.text = "Placeholder\n(missing or unloadable image)"
		ph_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ph_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ph.add_child(ph_lbl)
		col.add_child(ph)

	return col
