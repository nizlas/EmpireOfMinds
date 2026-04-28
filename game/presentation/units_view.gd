# Draws unit markers in world space from a Scenario. Domain is read-only; markers are derived, not owned as gameplay state.
# See docs/RENDERING.md
class_name UnitsView
extends Node2D

const ScenarioScript = preload("res://domain/scenario.gd")
const UnitScript = preload("res://domain/unit.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")

var scenario
var layout
@export var marker_radius_ratio: float = 0.35

static func _owner_to_color(owner_id: int) -> Color:
	if owner_id == 0:
		return Color(0.95, 0.85, 0.20)
	if owner_id == 1:
		return Color(0.85, 0.20, 0.20)
	return Color(1.0, 0.0, 1.0)

static func compute_marker_items(a_scenario, a_layout) -> Array:
	assert(UnitScript != null)
	assert(HexCoordScript != null)
	if a_scenario == null or a_layout == null:
		return []
	var out = []
	var ulist = a_scenario.units()
	var i = 0
	while i < ulist.size():
		var u = ulist[i]
		var w = a_layout.hex_to_world(u.position.q, u.position.r)
		var d = {
			"unit_id": u.id,
			"owner_id": u.owner_id,
			"coord": u.position,
			"world": w,
			"color": _owner_to_color(u.owner_id),
		}
		out.append(d)
		i = i + 1
	return out

func _ready() -> void:
	if scenario == null:
		scenario = ScenarioScript.make_tiny_test_scenario()
	if layout == null:
		layout = HexLayoutScript.new()
	queue_redraw()

func _draw() -> void:
	var items = UnitsView.compute_marker_items(scenario, layout)
	var r = HexLayoutScript.SIZE * marker_radius_ratio
	var outline = Color(0.0, 0.0, 0.0, 0.6)
	var j = 0
	while j < items.size():
		var item = items[j]
		var world = item["world"] as Vector2
		var col = item["color"] as Color
		draw_circle(world, r, col)
		draw_arc(world, r, 0.0, TAU, 24, outline, 1.0)
		j = j + 1
