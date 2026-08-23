# Headless A2 preview RUNTIME smoke gate: loads the exact F6 scene
# (uthana_a2_walking_preview.tscn), lets it initialize in a live SceneTree,
# and verifies the club actually exists, renders, and sits in the hand.
# Grip math being green is NOT enough — this gates the real user-facing scene.
# godot --headless --path game -s res://presentation/tests/test_uthana_a2_preview_runtime.gd
extends SceneTree

const PREVIEW_SCENE := (
	"res://assets/prototype/3d/units/generated_warrior/uthana_a2/uthana_a2_walking_preview.tscn"
)
const ATTACHMENT_NAME := "UthanaA2ClubAttachment"
const CLUB_PATH_IN_ATTACHMENT := "WeaponSocket_R/SocketOffset/WoodenClub"
const INIT_MAX_FRAMES := 240

var _total := 0
var _any_fail := false


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame

	# --- Load + instantiate the EXACT scene the user opens with F6 ----------
	_check(ResourceLoader.exists(PREVIEW_SCENE), "preview .tscn exists")
	var packed: PackedScene = ResourceLoader.load(PREVIEW_SCENE) as PackedScene
	_check(packed != null, "preview .tscn loads as PackedScene")
	if packed == null:
		_finish()
		return
	var preview: Node3D = packed.instantiate() as Node3D
	_check(preview != null, "preview instantiates")
	_check(
		preview.get_script() != null
		and str((preview.get_script() as Script).resource_path).ends_with(
			"uthana_a2_walking_preview.gd"
		),
		"A2 preview script attached to scene root"
	)
	root.add_child(preview)
	var ready: bool = await _wait_for_init(preview)
	_check(ready, "preview initialization completed within %d frames" % INIT_MAX_FRAMES)

	# 1. No initialization error.
	var init_err: String = str(preview.init_error())
	_check(init_err.is_empty(), "no init error (got: '%s')" % init_err)
	var equip: Dictionary = preview.equip_result()
	_check(bool(equip.get("ok", false)), "equip result ok (%s)" % equip.get("reason", ""))

	# 2. Club instance under the correct socket chain.
	var attachment: Node = preview.get_node_or_null(ATTACHMENT_NAME)
	_check(attachment != null, "attachment node present")
	if attachment == null:
		_finish()
		return
	var club: Node3D = attachment.get_node_or_null(CLUB_PATH_IN_ATTACHMENT) as Node3D
	_check(
		club != null,
		"club node at %s/%s" % [ATTACHMENT_NAME, CLUB_PATH_IN_ATTACHMENT]
	)
	if club == null:
		_finish()
		return
	print("CLUB_NODE_PATH %s" % club.get_path())
	print("CLUB_RESOURCE %s" % str(equip.get("club_path", "")))
	_check(ResourceLoader.exists(str(equip.get("club_path", ""))), "club resource path loads")

	# 3. Renderable MeshInstance3D under the club.
	var meshes: Array = club.find_children("*", "MeshInstance3D", true, false)
	var renderable: Array[MeshInstance3D] = []
	for m in meshes:
		var mi: MeshInstance3D = m as MeshInstance3D
		if mi != null and mi.mesh != null:
			renderable.append(mi)
	_check(renderable.size() >= 1, "club has %d renderable MeshInstance3D" % renderable.size())
	if renderable.is_empty():
		_finish()
		return

	# 4. Visible in tree.
	_check(club.is_visible_in_tree(), "club is_visible_in_tree")
	for mi in renderable:
		_check(mi.is_visible_in_tree(), "club mesh visible in tree")
		_check(mi.transparency < 0.99, "club mesh not fully transparent")

	# 5-7. AABB, scale, transform.
	var merged := AABB()
	var first := true
	for mi in renderable:
		var world_aabb: AABB = mi.global_transform * mi.mesh.get_aabb()
		merged = world_aabb if first else merged.merge(world_aabb)
		first = false
	_check(_aabb_finite(merged), "transformed club AABB finite")
	_check(merged.size.length() > 1e-5, "transformed club AABB non-empty (%.4f)" % merged.size.length())
	print("CLUB_AABB pos=(%.4f, %.4f, %.4f) size=(%.4f, %.4f, %.4f)" % [
		merged.position.x, merged.position.y, merged.position.z,
		merged.size.x, merged.size.y, merged.size.z,
	])
	var club_scale: Vector3 = club.global_transform.basis.get_scale()
	for axis in 3:
		_check(
			club_scale[axis] > 1e-5 and club_scale[axis] < 10.0,
			"club global scale axis %d sane (%.5f)" % [axis, club_scale[axis]]
		)
	_check(_xform_finite(club.global_transform), "club global transform finite")
	print("CLUB_GLOBAL pos=(%.4f, %.4f, %.4f) scale=(%.5f, %.5f, %.5f)" % [
		club.global_position.x, club.global_position.y, club.global_position.z,
		club_scale.x, club_scale.y, club_scale.z,
	])

	# 8. Near the right palm — never at origin or off-world.
	var frame: Dictionary = attachment.live_hand_frame()
	_check(bool(frame.get("ok", false)), "live hand frame ok")
	var palm: Vector3 = frame.get("palm_centre", Vector3.ZERO)
	var hand_length: float = float(frame.get("hand_length", 0.0))
	var grip_pos: Vector3 = attachment.primary_grip_world()
	var palm_dist: float = grip_pos.distance_to(palm)
	print("CLUB_TO_PALM %.5f (hand_length %.5f)" % [palm_dist, hand_length])
	_check(hand_length > 1e-4, "hand length positive")
	_check(
		palm_dist <= hand_length * 1.0,
		"primary grip within one hand length of palm (%.5f <= %.5f)" % [palm_dist, hand_length]
	)
	_check(grip_pos.length() > 1e-4, "club not at world origin")
	_check(merged.get_center().distance_to(palm) < 0.5, "club AABB near the warrior, not off-world")

	# 9. Reasonable rendered size relative to the warrior.
	var height: float = float(attachment.humanoid_height())
	var longest: float = maxf(merged.size.x, maxf(merged.size.y, merged.size.z))
	_check(height > 1e-4, "humanoid height positive")
	_check(
		longest / height > 0.25 and longest / height < 0.75,
		"club length %.2f of warrior height in [0.25, 0.75]" % (longest / height)
	)

	# Camera cull mask must include the club layers for the CURRENT camera.
	var viewport_cam: Camera3D = preview.get_viewport().get_camera_3d()
	_check(viewport_cam != null, "active camera present")
	if viewport_cam != null:
		for mi in renderable:
			_check(
				(viewport_cam.cull_mask & mi.layers) != 0,
				"active camera cull mask renders club layers"
			)

	# 10. G toggles finger pose but never removes or hides the club.
	var grip = attachment.grip_modifier()
	_check(grip != null, "grip modifier present")
	var poses_on: Dictionary = _finger_poses(preview, grip)
	_press_key(KEY_G)
	await process_frame
	_check(not attachment.is_grip_enabled(), "G turned grip OFF")
	var poses_off: Dictionary = _finger_poses(preview, grip)
	_check(not _poses_eq(poses_on, poses_off), "G changed finger poses")
	_check(is_instance_valid(club) and club.is_inside_tree(), "club survives grip OFF")
	_check(club.is_visible_in_tree(), "club visible with grip OFF")
	_press_key(KEY_G)
	await process_frame
	_check(attachment.is_grip_enabled(), "G turned grip back ON")
	_check(club.is_visible_in_tree(), "club visible with grip ON")

	# 11. H cycles all camera views; club always visible to the active camera.
	for i in 5:
		_press_key(KEY_H)
		await process_frame
		await process_frame
		var cam: Camera3D = preview.get_viewport().get_camera_3d()
		_check(cam != null, "view %d has an active camera" % i)
		_check(is_instance_valid(club) and club.is_visible_in_tree(), "view %d keeps club visible" % i)
		if cam != null:
			for mi in renderable:
				_check((cam.cull_mask & mi.layers) != 0, "view %d cull mask includes club" % i)

	preview.queue_free()
	await process_frame
	await process_frame

	# 12. Broken club resource must be a loud explicit failure, never a
	# silent weaponless preview.
	var broken: Node3D = packed.instantiate() as Node3D
	broken.debug_club_path_override = (
		"res://assets/prototype/3d/equipment/wooden_club/does_not_exist.glb"
	)
	root.add_child(broken)
	var broken_done: bool = await _wait_for_init(broken)
	_check(broken_done, "broken-club preview finished initializing")
	var broken_err: String = str(broken.init_error())
	_check(not broken_err.is_empty(), "broken club reports explicit init error")
	_check(broken_err.contains("club_missing"), "error names the real cause (got: '%s')" % broken_err)
	var broken_attachment: Node = broken.get_node_or_null(ATTACHMENT_NAME)
	var broken_club: Node = (
		broken_attachment.get_node_or_null(CLUB_PATH_IN_ATTACHMENT)
		if broken_attachment != null
		else null
	)
	_check(broken_club == null, "broken case adds no club node")
	broken.queue_free()
	await process_frame

	_finish()


## Init is done when there is an explicit error OR the club is equipped.
func _wait_for_init(preview: Node) -> bool:
	for _i in INIT_MAX_FRAMES:
		await process_frame
		if not str(preview.init_error()).is_empty():
			return true
		var att: Node = preview.get_node_or_null(ATTACHMENT_NAME)
		if att != null and att.has_club() and bool(preview.equip_result().get("ok", false)):
			# A couple of extra frames so _process/follow has run.
			await process_frame
			await process_frame
			return true
	return false


func _press_key(keycode: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = true
	Input.parse_input_event(ev)


func _finger_poses(preview: Node, grip) -> Dictionary:
	var character: Node3D = preview.get_node_or_null("ModelRoot/UthanaWarrior")
	if character == null:
		return {}
	var sk: Skeleton3D = null
	for s in character.find_children("*", "Skeleton3D", true, false):
		sk = s as Skeleton3D
		break
	if sk == null:
		return {}
	var d := {}
	for n in grip.bound_finger_names():
		var i: int = sk.find_bone(str(n))
		if i >= 0:
			d[i] = sk.get_bone_pose(i)
	return d


func _poses_eq(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size() or a.is_empty():
		return false
	for k in a.keys():
		if not b.has(k) or not (a[k] as Transform3D).is_equal_approx(b[k]):
			return false
	return true


func _aabb_finite(aabb: AABB) -> bool:
	for axis in 3:
		if not is_finite(aabb.position[axis]) or not is_finite(aabb.size[axis]):
			return false
	return true


func _xform_finite(t: Transform3D) -> bool:
	for i in 3:
		for j in 3:
			if not is_finite(t.basis[i][j]):
				return false
		if not is_finite(t.origin[i]):
			return false
	return absf(t.basis.determinant()) > 1e-8


func _check(cond: bool, label: String) -> void:
	_total += 1
	if cond:
		print("PASS: %s" % label)
	else:
		_any_fail = true
		printerr("FAIL: %s" % label)


func _finish() -> void:
	print(
		"test_uthana_a2_preview_runtime: %d checks, %s"
		% [_total, "FAIL" if _any_fail else "OK"]
	)
	if not _any_fail:
		print("A2 runtime preview club-present gate passed; user F6 grip inspection still required.")
	quit(1 if _any_fail else 0)
