# Headless: godot --headless --path game -s res://cloud/tests/test_cloud_routing_pick.gd
extends SceneTree

const SelectionControllerScript = preload("res://presentation/selection_controller.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const MapPlaneProjectionScript = preload("res://presentation/map_plane_projection.gd")
const MapCameraScript = preload("res://presentation/map_camera.gd")
const CloudClientScript = preload("res://cloud/cloud_client.gd")

var _total = 0
var _any_fail = false


func _pres_centroid(layout, camera, q: int, r: int) -> Vector2:
	var w = layout.hex_to_world(q, r)
	var corners = layout.hex_corners(w)
	var sx = 0.0
	var sy = 0.0
	var i = 0
	while i < corners.size():
		var p = camera.to_presentation(corners[i])
		sx += p.x
		sy += p.y
		i += 1
	var n = float(corners.size())
	return Vector2(sx / n, sy / n)


func _init() -> void:
	var scen = ScenarioScript.make_tiny_test_scenario()
	var layout = HexLayoutScript.new()
	var proj = MapPlaneProjectionScript.new()
	proj.vanishing_pres = Vector2(400.0, 322.0)
	var cam = MapCameraScript.new()
	cam.projection = proj
	var pt0 = _pres_centroid(layout, cam, 0, 0)
	var picked0 = SelectionControllerScript.pick_map_hex_at_point(scen, layout, cam, pt0)
	_check(picked0 != null, "pick hex 0,0")
	_check(int(picked0.q) == 0 and int(picked0.r) == 0, "coords 0,0")
	var k0 = CloudClientScript.hex_action_key(0, 0)
	var dm: Dictionary = {}
	dm[k0] = {"action_type": "move_unit", "to": [0, 0]}
	var pk = CloudClientScript.hex_action_key(int(picked0.q), int(picked0.r))
	_check(dm.has(pk), "dict lookup matches picked key")
	var pt1 = _pres_centroid(layout, cam, 1, 0)
	var picked1 = SelectionControllerScript.pick_map_hex_at_point(scen, layout, cam, pt1)
	_check(picked1 != null and int(picked1.q) == 1 and int(picked1.r) == 0, "pick 1,0")
	if _any_fail:
		call_deferred("quit", 1)
	else:
		print("PASS %d/%d" % [_total, _total])
		call_deferred("quit", 0)


func _check(cond, message) -> void:
	_total = _total + 1
	if cond:
		return
	_any_fail = true
	var line = "FAIL: %s" % message
	print(line)
	push_error(line)
