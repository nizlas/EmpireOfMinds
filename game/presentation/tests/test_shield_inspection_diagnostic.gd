# C1 shield inspection diagnostic gate.
#
# The scene exists so a human can judge the shield tomorrow. A test that only
# checked "the script parses" would not prove that: the scene must actually
# instantiate, load the shield, and expose the review affordances. It must also
# NOT drag in any grip/hand-pose code, because C1 implements no hand pose.
extends SceneTree

const DIAGNOSTIC_SCENE := "res://presentation/diagnostics/shield_inspection_diagnostic.tscn"
const DIAGNOSTIC_SCRIPT := "res://presentation/diagnostics/shield_inspection_diagnostic.gd"
const SHIELD_GLB := "res://assets/prototype/3d/equipment/wooden_shield/wooden_shield.glb"

var _total := 0
var _any_fail := false


func _init() -> void:
	_run()


func _run() -> void:
	# The scene tree root only exists after the first frame, and the diagnostic
	# builds its camera and asset in _ready(), so the instance has to be added
	# to a live tree before anything can be asserted about it.
	await process_frame
	await _inspect()
	print("Checks run: %d" % _total)
	if _any_fail:
		printerr("test_shield_inspection_diagnostic FAILED")
		quit(1)
	else:
		print("test_shield_inspection_diagnostic PASSED")
		quit(0)


func _inspect() -> void:
	_check(ResourceLoader.exists(DIAGNOSTIC_SCENE), "diagnostic scene resource exists")
	_check(ResourceLoader.exists(SHIELD_GLB), "shield GLB under inspection exists")

	var packed: PackedScene = load(DIAGNOSTIC_SCENE) as PackedScene
	_check(packed != null, "diagnostic scene loads as a PackedScene")
	if packed == null:
		return

	var instance: Node = packed.instantiate()
	_check(instance is Node3D, "diagnostic root is a Node3D")
	root.add_child(instance)
	await process_frame

	_check(instance.is_inside_tree(), "diagnostic scene entered the tree without error")

	var camera: Camera3D = _find_first(instance, "Camera3D") as Camera3D
	_check(camera != null, "an inspection camera was created")

	var asset_root: Node = instance.get_node_or_null("ShieldUnderInspection")
	_check(asset_root != null, "shield asset root node exists")
	var meshes: Array = _collect_meshes(asset_root) if asset_root != null else []
	# Rotating and zooming an empty scene would look like a working review tool
	# while showing nothing, so the mesh itself has to be present.
	_check(not meshes.is_empty(), "shield geometry is actually instantiated (%d mesh instance(s))" % meshes.size())

	var probe: Node = instance.get_node_or_null("HandClearanceProbe")
	_check(probe != null, "hand-clearance probe exists for measuring by eye")
	if probe != null:
		_check(
			probe.get_node_or_null("HandCrossSection") != null,
			"probe carries a real hand cross-section reference"
		)
		_check(
			probe.get_node_or_null("ReferenceGripDiameter") != null,
			"probe carries a reference grip diameter"
		)

	_check(
		instance.get_node_or_null("SuggestedMarkers") != null,
		"suggested-marker container exists (populated only from a structural report)"
	)

	var checklist: Array = instance.visual_checklist()
	_check(checklist.size() >= 6, "visual checklist enumerates what a human must judge")
	var joined := " ".join(checklist).to_lower()
	_check(
		joined.contains("painted") or joined.contains("embossed"),
		"checklist explicitly asks whether the grip is merely painted/embossed"
	)
	_check(joined.contains("clearance") or joined.contains("empty space"), "checklist asks about clearance")
	_check(joined.contains("remesh"), "checklist asks whether the remesh preserved the grip")

	_check_no_hand_pose_dependency()

	instance.queue_free()


## C1 must not smuggle in the A2.9 hand architecture. The diagnostic scene is
## allowed to display a shield and nothing else.
func _check_no_hand_pose_dependency() -> void:
	var source := FileAccess.get_file_as_string(DIAGNOSTIC_SCRIPT)
	_check(source != "", "diagnostic script is readable")
	var forbidden := [
		"hand_grip_solver",
		"power_grip",
		"equipment_assembler",
		"grip_interaction_profile",
		"Skeleton3D",
	]
	for token in forbidden:
		_check(
			not source.contains(token),
			"diagnostic does not depend on %s (no hand pose in C1)" % token
		)


func _find_first(node: Node, class_name_wanted: String) -> Node:
	if node.is_class(class_name_wanted):
		return node
	for child in node.get_children():
		var found := _find_first(child, class_name_wanted)
		if found != null:
			return found
	return null


func _collect_meshes(node: Node) -> Array:
	var found: Array = []
	if node is MeshInstance3D:
		found.append(node)
	for child in node.get_children():
		found.append_array(_collect_meshes(child))
	return found


func _check(cond: bool, label: String) -> void:
	_total += 1
	if cond:
		print("PASS: %s" % label)
	else:
		_any_fail = true
		printerr("FAIL: %s" % label)
