# N8b city-production presentation component (extracted from the world-play
# scene in N8R so composition and gameplay presentation stay separate).
#
# Renders the minimal selected-city production panel for the ACTIVE world
# path: the authoritative selected-city status line (snapshot name/project/
# progress via the interaction state) plus one button per SERVED
# set_city_production row. Presentation only — this component never builds
# an action payload, never computes production legality (button set ==
# exactly the fresh served rows), and never talks to the server: a chosen
# row is reported through `production_row_chosen` and the scene submits the
# exact served row. Progress ticking stays server-side (N8c); the deprecated
# local production_tick/production_delivery loop is never consulted.
extends VBoxContainer

# The scene submits the exact served row for this project_id.
signal production_row_chosen(project_id: String)

var _status_label: Label = null
var _buttons: Array = []


func _init() -> void:
	name = "CityProductionPanel"
	visible = false
	_status_label = Label.new()
	_status_label.name = "ProductionStatusLabel"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	_status_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	_status_label.add_theme_constant_override("outline_size", 4)
	add_child(_status_label)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = 16.0
	offset_top = -200.0
	offset_right = 280.0
	offset_bottom = -16.0


# Display naming is presentation-only sugar over the served project ids —
# unknown ids fall back to the literal id (never hidden, never re-mapped).
static func display_text_for_project_id(project_id: String) -> String:
	if project_id == "none":
		return "Clear production"
	if project_id == "produce_unit:warrior":
		return "Train Warrior"
	if project_id == "produce_unit:settler":
		return "Train Settler"
	return project_id


# Recomputes the whole panel from the current interaction state: visible
# only while a city is selected; one button per fresh served row (a stale
# or missing row disables its button through the interaction's freshness
# rules on the pressed path as well).
func refresh(p_interaction, p_request_busy: bool) -> void:
	for btn_variant in _buttons:
		if btn_variant is Node and is_instance_valid(btn_variant):
			(btn_variant as Node).queue_free()
	_buttons = []

	var city_selected: bool = p_interaction != null and p_interaction.selected_city_id >= 0
	visible = city_selected
	if not city_selected:
		if _status_label != null:
			_status_label.text = ""
		return

	if _status_label != null:
		_status_label.text = p_interaction.selected_city_status_line()

	var rows: Array = p_interaction.production_rows()
	for row_variant in rows:
		if typeof(row_variant) != TYPE_DICTIONARY:
			continue
		var pid := str((row_variant as Dictionary).get("project_id", ""))
		var btn := Button.new()
		btn.name = "Prod_%s" % pid.replace(":", "_")
		btn.text = display_text_for_project_id(pid)
		btn.disabled = (
			p_request_busy or p_interaction.production_row_for_project_id(pid).is_empty()
		)
		btn.pressed.connect(_on_button_pressed.bind(pid))
		add_child(btn)
		_buttons.append(btn)


func _on_button_pressed(project_id: String) -> void:
	production_row_chosen.emit(project_id)
