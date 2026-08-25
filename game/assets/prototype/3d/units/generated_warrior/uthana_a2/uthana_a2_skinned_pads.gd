# A2 compatibility shell (A2.9): skinned finger-pad sampling is owned by
# res://presentation/equipment/skinned_mesh_geometry.gd. This shell only
# keeps the legacy right-hand Mixamo tip-bone defaults for the accepted
# A2.7 path; the generic engine always injects per-side tip bones.
extends RefCounted

const Skinning = preload("res://presentation/equipment/skinned_mesh_geometry.gd")

const TIP_BONES: Dictionary = {
	"thumb": "mixamorig_RightHandThumb3",
	"index": "mixamorig_RightHandIndex3",
	"middle": "mixamorig_RightHandMiddle3",
	"ring": "mixamorig_RightHandRing3",
	"pinky": "mixamorig_RightHandPinky3",
}

const WEIGHT_MIN := Skinning.PAD_WEIGHT_MIN


static func tip_bone_index(
	skeleton: Skeleton3D, finger: String, tip_bones: Dictionary = {}
) -> int:
	var names: Dictionary = TIP_BONES if tip_bones.is_empty() else tip_bones
	return Skinning.tip_bone_index(skeleton, finger, names)


static func bind_pad_locals(
	character: Node, skeleton: Skeleton3D, palm_normal_world: Vector3,
	tip_bones: Dictionary = {}
) -> Dictionary:
	var names: Dictionary = TIP_BONES if tip_bones.is_empty() else tip_bones
	return Skinning.bind_pad_locals(character, skeleton, palm_normal_world, names)


static func pad_world(
	skeleton: Skeleton3D, finger: String, pad_local: Vector3, tip_bones: Dictionary = {}
) -> Vector3:
	var names: Dictionary = TIP_BONES if tip_bones.is_empty() else tip_bones
	return Skinning.pad_world(skeleton, finger, pad_local, names)
