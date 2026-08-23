# Headless: godot --headless --path game -s res://presentation/tests/test_generated_warrior_equipment.gd
extends SceneTree

const GeneratedWarriorEquipmentScript = preload(
	"res://presentation/world/generated_warrior_equipment.gd"
)
const OneHandedWeaponNormalizeScript = preload(
	"res://presentation/world/one_handed_weapon_normalize.gd"
)
const PalmFrameScript = preload("res://presentation/world/one_handed_palm_frame.gd")
const Profile = preload("res://presentation/world/one_handed_weapon_equipment_profile.gd")
const WorldUnitsViewScript = preload("res://presentation/world/world_units_view.gd")
const Warrior3DAnimationRemapScript = preload("res://presentation/warrior_3d_animation_remap.gd")

const ANCHORS := {
	Vector2i(2, 0): Vector3(3.0, 1.5, 0.2),
	Vector2i(2, 1): Vector3(3.25, 1.6, -0.75),
}

var _total := 0
var _any_fail := false


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	OS.set_environment(OneHandedWeaponNormalizeScript.ENV_DEBUG, "1")

	_check(
		ResourceLoader.exists(GeneratedWarriorEquipmentScript.CLUB_GLB_PATH),
		"club GLB exists at wooden_club/wooden_club.glb"
	)
	var packed: PackedScene = load(GeneratedWarriorEquipmentScript.CLUB_GLB_PATH) as PackedScene
	_check(packed != null, "club PackedScene loads")
	var club_inst: Node3D = packed.instantiate() as Node3D
	root.add_child(club_inst)
	await process_frame
	_check(club_inst.get_child_count() >= 1, "club hierarchy has mesh child")
	var probe_target := 0.225
	var analysis: Dictionary = OneHandedWeaponNormalizeScript.analyze(club_inst, probe_target)
	_check(bool(analysis.get("ok", false)), "club analyze ok")
	_check(str(analysis.get("principal_axis_name", "")) == "Y", "principal length axis is Y")
	_check(
		is_equal_approx(float(analysis.get("length", 0.0)), 1.0),
		"authored club length is 1.0 along Y"
	)
	OneHandedWeaponNormalizeScript.apply_normalize(club_inst, analysis)
	var grip_a: Vector3 = analysis["grip"]
	var upper_a: Vector3 = analysis["upper"]
	var lower_a: Vector3 = analysis["lower"]
	var grip_c: Vector3 = club_inst.transform * grip_a
	var upper_c: Vector3 = club_inst.transform * upper_a
	var lower_c: Vector3 = club_inst.transform * lower_a
	_check(grip_c.length() < 1e-4, "normalized grip lands at origin")
	_check(upper_c.y > grip_c.y + 0.05, "normalized head is above grip on +Y")
	_check(lower_c.y < grip_c.y - 0.01, "normalized lower endpoint below grip")
	_check(
		is_equal_approx(upper_c.distance_to(lower_c), probe_target),
		"normalized length equals supplied target_length"
	)
	_check(
		is_equal_approx(float(analysis.get("grip_fraction", -1.0)), Profile.PRIMARY_GRIP_FRACTION),
		"grip fraction comes from equipment profile"
	)
	club_inst.queue_free()

	var view = WorldUnitsViewScript.new()
	root.add_child(view)
	view.set_tile_anchors(ANCHORS)
	view.apply_snapshot_units(
		[{"id": 5, "owner_id": 0, "position": [2, 0], "type_id": "generated_warrior"}]
	)
	GeneratedWarriorEquipmentScript.sync_units_view(view)
	var unit_root: Node3D = view.root_for_unit(5)
	var equipment = GeneratedWarriorEquipmentScript.find_controller(unit_root)
	_check(equipment != null and equipment.has_club(), "club equipped on generated_warrior")
	_check(equipment.has_shield(), "shield still equips (unchanged path)")

	var model = unit_root.get_node("ModelRoot").get_child(0)
	var skel: Skeleton3D = GeneratedWarriorEquipmentScript.find_skeleton(model)
	var bones: PackedStringArray = GeneratedWarriorEquipmentScript.list_skeleton_bone_names(skel)
	_check(bones.has("RightHand"), "wrist/hand bone RightHand present")
	_check(bones.has("LeftHand"), "LeftHand present")
	var finger_hits := 0
	for b in bones:
		var low: String = str(b).to_lower()
		if (
			"index" in low
			or "middle" in low
			or "ring" in low
			or "pinky" in low
			or "little" in low
			or "thumb" in low
			or "finger" in low
		):
			finger_hits += 1
	_check(finger_hits == 0, "rig has no finger/thumb bones (grip pose not available)")

	var palm: Dictionary = equipment.palm_frame()
	_check(bool(palm.get("ok", false)), "palm frame computed")
	_check(not bool(palm.get("has_fingers", true)), "palm frame reports no finger roots")
	_check(bool(palm.get("estimated", false)), "palm centre estimated without fingers")
	var height: float = float(palm.get("humanoid_height", 0.0))
	_check(height > 0.4 and height < 0.7, "humanoid height in equipped space (got %.4f)" % height)
	var club_a: Dictionary = equipment.club_analysis()
	var target_len: float = float(club_a.get("target_length", 0.0))
	var expected_len: float = height * Profile.TARGET_LENGTH_RATIO
	_check(
		is_equal_approx(target_len, expected_len),
		"club target length = height * %.2f (%.4f)" % [Profile.TARGET_LENGTH_RATIO, expected_len]
	)
	_check(
		is_equal_approx(float(club_a.get("length", 0.0)), 1.0),
		"original authored club length recorded as 1.0"
	)
	_check(not equipment.has_finger_grip_pose(), "no finger grip pose claimed")

	var wrist: Vector3 = palm["wrist"]
	var palm_c: Vector3 = palm["palm_centre"]
	var knuckle: Vector3 = palm["knuckle_centre"]
	_check(
		wrist.distance_to(palm_c) > 0.005,
		"palm centre is offset from wrist (dist=%.4f)" % wrist.distance_to(palm_c)
	)
	_check(
		palm_c.distance_to(knuckle) > 0.001,
		"palm centre lies before knuckle centre"
	)

	# Socket at palm: grip coincides with palm centre; shaft along palm +Y.
	for semantic in ["Idle_3", "Walking", "Running", "Left_Slash"]:
		await _assert_palm_grip_and_axis(view, equipment, semantic)

	var offset: Node3D = equipment.get_node("WeaponSocket_R/SocketOffset") as Node3D
	_check(
		offset.transform.is_equal_approx(Transform3D.IDENTITY),
		"weapon-class SocketOffset stays identity (no club-specific guess)"
	)

	OS.set_environment(OneHandedWeaponNormalizeScript.ENV_DEBUG, "")
	view.queue_free()
	_finish()


func _assert_palm_grip_and_axis(view, equipment, semantic: String) -> void:
	var unit_id := 5
	var type_id := "generated_warrior"
	var player: AnimationPlayer = null
	var model = view.root_for_unit(unit_id).get_node("ModelRoot").get_child(0)
	for n in model.find_children("*", "AnimationPlayer", true, false):
		player = n as AnimationPlayer
		break
	_check(player != null, "%s: AnimationPlayer present" % semantic)
	if player == null:
		return
	var clip: String = Warrior3DAnimationRemapScript.glb_clip_for_visual(semantic, true, type_id)
	_check(player.has_animation(clip), "%s: clip '%s' exists" % [semantic, clip])
	player.play(clip)
	for _i in 8:
		await process_frame
		equipment._process(0.016)
		player.advance(0.05)
	var skel: Skeleton3D = GeneratedWarriorEquipmentScript.find_skeleton(model)
	var hand_i: int = skel.find_bone("RightHand")
	var hand_ortho: Transform3D = PalmFrameScript.ortho_global_pose(skel, hand_i)
	var socket: Node3D = equipment.get_node("WeaponSocket_R") as Node3D
	var offset_n: Node3D = socket.get_node("SocketOffset") as Node3D
	var grip_world: Vector3 = offset_n.global_position
	var palm_world: Vector3 = socket.global_position
	_check(
		grip_world.distance_to(palm_world) < 1e-4,
		"%s: grip coincides with WeaponSocket_R / palm centre" % semantic
	)
	var wrist_world: Vector3 = hand_ortho.origin
	_check(
		grip_world.distance_to(wrist_world) > 0.005,
		"%s: grip not glued to wrist origin (dist=%.4f)"
		% [semantic, grip_world.distance_to(wrist_world)]
	)
	var target_len: float = float(equipment.club_analysis().get("target_length", 0.0))
	var head_local := Vector3(
		0.0,
		(1.0 - Profile.PRIMARY_GRIP_FRACTION) * target_len,
		0.0
	)
	var head_world: Vector3 = offset_n.to_global(head_local)
	var shaft: Vector3 = (head_world - grip_world).normalized()
	var socket_y: Vector3 = socket.global_transform.basis.y.normalized()
	var align: float = shaft.dot(socket_y)
	_check(
		align > 0.85,
		"%s: club points grip→head along palm +Y (dot=%.3f)" % [semantic, align]
	)
	# Handle should sit ahead of the wrist along palm longitudinal (through palm).
	var along_palm: float = socket_y.dot(grip_world - wrist_world)
	_check(
		along_palm > 0.0,
		"%s: palm centre lies along finger direction from wrist (proj=%.4f)"
		% [semantic, along_palm]
	)


func _check(cond: bool, label: String) -> void:
	_total += 1
	if cond:
		print("PASS: %s" % label)
	else:
		_any_fail = true
		printerr("FAIL: %s" % label)


func _finish() -> void:
	print(
		"test_generated_warrior_equipment: %d checks, %s"
		% [_total, "FAIL" if _any_fail else "OK"]
	)
	quit(1 if _any_fail else 0)
