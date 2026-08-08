# N8a city-selection presentation component (extracted from the world-play
# scene in N8R so composition and gameplay presentation stay separate).
#
# Owns the Found City button for the ACTIVE world path: visible and enabled
# only while the interaction state holds a FRESH served found_city row for
# the selected eligible settler. Presentation only — founding legality is
# server-decided (the served row IS the legality); pressing reports
# `found_city_requested` and the scene submits the exact served row.
extends Button

# The scene submits the interaction state's exact served found_city row.
signal found_city_requested


func _init() -> void:
	name = "FoundCityButton"
	text = "Found City"
	visible = false
	disabled = true
	pressed.connect(func() -> void: found_city_requested.emit())


func _ready() -> void:
	set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	offset_left = -140.0
	offset_top = -116.0
	offset_right = -16.0
	offset_bottom = -80.0


# Recomputes button state from the interaction state's served-row freshness.
func refresh(p_interaction, p_request_busy: bool) -> void:
	var can_found: bool = p_interaction != null and p_interaction.can_submit_found_city()
	visible = can_found
	disabled = p_request_busy or not can_found
