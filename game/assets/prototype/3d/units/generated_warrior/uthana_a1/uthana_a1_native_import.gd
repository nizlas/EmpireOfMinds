# A1 native Godot import-time humanoid retarget helpers.
# Custom baked rest-delta path is FAILED and must not feed acceptance.
extends RefCounted

const ORIG_MESHY_GLB := "res://assets/prototype/3d/units/generated_warrior/generated_warrior_3d.glb"
const ORIG_UTHANA_GLB := (
	"res://assets/prototype/3d/units/generated_warrior/uthana_a0/generated_warrior_3d_uthana_rigged.glb"
)
const A1_DIR := "res://assets/prototype/3d/units/generated_warrior/uthana_a1/"
const IMPORT_SOURCES_DIR := A1_DIR + "import_sources/"
const MESHY_SOURCE_GLB := IMPORT_SOURCES_DIR + "a1_meshy_walking_source.glb"
const UTHANA_TARGET_GLB := IMPORT_SOURCES_DIR + "a1_uthana_target.glb"
const SOURCE_BONEMAP_PATH := A1_DIR + "meshy_source_bonemap.tres"
const TARGET_BONEMAP_PATH := A1_DIR + "uthana_target_bonemap.tres"
## Extracted Walking library saved after native import (canonical shared clip).
const WALKING_LIBRARY_PATH := A1_DIR + "a1_native_walking.res"
const NOTES_PATH := A1_DIR + "A1_RETARGET_NOTES.md"

const WALKING_CLIP := "Walking"
const PREVIEW_MODEL_SCALE := 0.30
const PREVIEW_MODEL_YAW := 0.0
## Acceptance path: Godot import-time SkeletonProfileHumanoid retarget.
const RETARGET_METHOD := "godot_import_humanoid_retarget"
## Failed forensic path — do not use for acceptance.
const FAILED_CUSTOM_METHOD := "global_hierarchical_rest_delta"
const GROUND_CONTACT_TOLERANCE := 0.04

const SKELETON_NODE_KEY := "PATH:Armature/Skeleton3D"
const GENERAL_SKELETON_NAME := "GeneralSkeleton"

const MESHY_PROFILE_MAP: Dictionary = {
	"Hips": "Hips",
	"Spine": "Spine02",
	"Chest": "Spine01",
	"UpperChest": "Spine",
	"Neck": "neck",
	"Head": "Head",
	"LeftShoulder": "LeftShoulder",
	"LeftUpperArm": "LeftArm",
	"LeftLowerArm": "LeftForeArm",
	"LeftHand": "LeftHand",
	"RightShoulder": "RightShoulder",
	"RightUpperArm": "RightArm",
	"RightLowerArm": "RightForeArm",
	"RightHand": "RightHand",
	"LeftUpperLeg": "LeftUpLeg",
	"LeftLowerLeg": "LeftLeg",
	"LeftFoot": "LeftFoot",
	"LeftToes": "LeftToeBase",
	"RightUpperLeg": "RightUpLeg",
	"RightLowerLeg": "RightLeg",
	"RightFoot": "RightFoot",
	"RightToes": "RightToeBase",
}

const UTHANA_PROFILE_MAP: Dictionary = {
	"Hips": "mixamorig_Hips",
	"Spine": "mixamorig_Spine",
	"Chest": "mixamorig_Spine1",
	"UpperChest": "mixamorig_Spine2",
	"Neck": "mixamorig_Neck",
	"Head": "mixamorig_Head",
	"LeftShoulder": "mixamorig_LeftShoulder",
	"LeftUpperArm": "mixamorig_LeftArm",
	"LeftLowerArm": "mixamorig_LeftForeArm",
	"LeftHand": "mixamorig_LeftHand",
	"RightShoulder": "mixamorig_RightShoulder",
	"RightUpperArm": "mixamorig_RightArm",
	"RightLowerArm": "mixamorig_RightForeArm",
	"RightHand": "mixamorig_RightHand",
	"LeftUpperLeg": "mixamorig_LeftUpLeg",
	"LeftLowerLeg": "mixamorig_LeftLeg",
	"LeftFoot": "mixamorig_LeftFoot",
	"LeftToes": "mixamorig_LeftToeBase",
	"RightUpperLeg": "mixamorig_RightUpLeg",
	"RightLowerLeg": "mixamorig_RightLeg",
	"RightFoot": "mixamorig_RightFoot",
	"RightToes": "mixamorig_RightToeBase",
}

const REQUIRED_PROFILE_BONES: Array[String] = [
	"Hips",
	"Spine",
	"Chest",
	"UpperChest",
	"Neck",
	"Head",
	"LeftShoulder",
	"LeftUpperArm",
	"LeftLowerArm",
	"LeftHand",
	"RightShoulder",
	"RightUpperArm",
	"RightLowerArm",
	"RightHand",
	"LeftUpperLeg",
	"LeftLowerLeg",
	"LeftFoot",
	"RightUpperLeg",
	"RightLowerLeg",
	"RightFoot",
]

## Canonical profile bone names after Bone Renamer (acceptance skeleton).
const CANONICAL_BONES: Dictionary = {
	"hips": "Hips",
	"left_upper_leg": "LeftUpperLeg",
	"left_lower_leg": "LeftLowerLeg",
	"left_foot": "LeftFoot",
	"left_toes": "LeftToes",
	"right_upper_leg": "RightUpperLeg",
	"right_lower_leg": "RightLowerLeg",
	"right_foot": "RightFoot",
	"right_toes": "RightToes",
	"left_hand": "LeftHand",
	"right_hand": "RightHand",
	"left_upper_arm": "LeftUpperArm",
	"right_upper_arm": "RightUpperArm",
}

const FOOT_BONE_CANDIDATES: Array[String] = [
	"LeftToes",
	"RightToes",
	"LeftFoot",
	"RightFoot",
	"mixamorig_LeftToeBase",
	"mixamorig_RightToeBase",
	"mixamorig_LeftFoot",
	"mixamorig_RightFoot",
]

const SoleGround = preload(
	"res://assets/prototype/3d/units/generated_warrior/uthana_a1/uthana_a1_skinned_sole_ground.gd"
)


static func build_bonemap(profile_to_skeleton: Dictionary) -> BoneMap:
	var bone_map := BoneMap.new()
	bone_map.profile = SkeletonProfileHumanoid.new()
	for profile_name in profile_to_skeleton.keys():
		bone_map.set_skeleton_bone_name(
			StringName(str(profile_name)), StringName(str(profile_to_skeleton[profile_name]))
		)
	return bone_map


static func make_source_bonemap() -> BoneMap:
	return build_bonemap(MESHY_PROFILE_MAP)


static func make_target_bonemap() -> BoneMap:
	return build_bonemap(UTHANA_PROFILE_MAP)


static func _meshy_skeleton_node_settings() -> Dictionary:
	# Source: shared AnimationLibrary pipeline (docs retargeting_3d_skeletons).
	# Measured on Godot 4.6.2: Remove Tracks / Except Bone Transform triggers track-index
	# OOB errors and collapses Walking rotation keys to 1 — leave it OFF for this asset.
	return {
		"retarget/bone_map": make_source_bonemap(),
		"retarget/bone_renamer/rename_bones": true,
		"retarget/bone_renamer/unique_node/make_unique": true,
		"retarget/bone_renamer/unique_node/skeleton_name": GENERAL_SKELETON_NAME,
		"retarget/remove_tracks/except_bone_transform": false,
		"retarget/remove_tracks/unimportant_positions": true,
		# 1 = Remove unmapped bone tracks (safe here; preserves multi-key rotations)
		"retarget/remove_tracks/unmapped_bones": 1,
		"retarget/rest_fixer/apply_node_transforms": true,
		"retarget/rest_fixer/normalize_position_tracks": true,
		"retarget/rest_fixer/reset_all_bone_poses_after_import": true,
		# 1 = Overwrite Axis
		"retarget/rest_fixer/retarget_method": 1,
		"retarget/rest_fixer/keep_global_rest_on_leftovers": true,
		"retarget/rest_fixer/fix_silhouette/enable": true,
		"retarget/rest_fixer/fix_silhouette/filter": [],
		"retarget/rest_fixer/fix_silhouette/threshold": 15.0,
		"retarget/rest_fixer/fix_silhouette/base_height_adjustment": 0.0,
	}


static func _uthana_skeleton_node_settings() -> Dictionary:
	# Target: same canonical rests; no Fix Silhouette (already T-pose).
	return {
		"retarget/bone_map": make_target_bonemap(),
		"retarget/bone_renamer/rename_bones": true,
		"retarget/bone_renamer/unique_node/make_unique": true,
		"retarget/bone_renamer/unique_node/skeleton_name": GENERAL_SKELETON_NAME,
		"retarget/remove_tracks/except_bone_transform": false,
		"retarget/remove_tracks/unimportant_positions": true,
		"retarget/remove_tracks/unmapped_bones": 0,
		"retarget/rest_fixer/apply_node_transforms": true,
		"retarget/rest_fixer/normalize_position_tracks": true,
		"retarget/rest_fixer/reset_all_bone_poses_after_import": true,
		"retarget/rest_fixer/retarget_method": 1,
		"retarget/rest_fixer/keep_global_rest_on_leftovers": true,
		"retarget/rest_fixer/fix_silhouette/enable": false,
		"retarget/rest_fixer/fix_silhouette/filter": [],
		"retarget/rest_fixer/fix_silhouette/threshold": 15.0,
		"retarget/rest_fixer/fix_silhouette/base_height_adjustment": 0.0,
	}


static func write_import_files() -> Dictionary:
	var meshy_ok := _write_source_animation_library_import()
	var uthana_ok := _write_target_packed_scene_import()
	return {"ok": meshy_ok and uthana_ok, "meshy": meshy_ok, "uthana": uthana_ok}


static func _write_source_animation_library_import() -> bool:
	var import_path := ProjectSettings.globalize_path(MESHY_SOURCE_GLB) + ".import"
	var cfg := ConfigFile.new()
	# Keep / create remap section fields Godot expects; UID regenerated on first import if missing.
	if FileAccess.file_exists(import_path):
		cfg.load(import_path)
	cfg.set_value("remap", "importer", "scene")
	cfg.set_value("remap", "importer_version", 1)
	# Prefer AnimationLibrary; Godot 4.6.2 headless --import may rewrite to PackedScene.
	# Walking is then extracted to a1_native_walking.res either way.
	cfg.set_value("remap", "type", "PackedScene")
	cfg.set_value("deps", "source_file", MESHY_SOURCE_GLB)
	_set_common_scene_params(cfg)
	# Retarget can leave some bones near-rest; dropping "immutable" tracks wrecks gait.
	cfg.set_value("params", "animation/remove_immutable_tracks", false)
	var sub := {"nodes": {SKELETON_NODE_KEY: _meshy_skeleton_node_settings()}}
	cfg.set_value("params", "_subresources", sub)
	cfg.set_value("params", "gltf/naming_version", 2)
	cfg.set_value("params", "gltf/embedded_image_handling", 1)
	var err := cfg.save(import_path)
	return err == OK


static func _write_target_packed_scene_import() -> bool:
	var import_path := ProjectSettings.globalize_path(UTHANA_TARGET_GLB) + ".import"
	var cfg := ConfigFile.new()
	if FileAccess.file_exists(import_path):
		cfg.load(import_path)
	cfg.set_value("remap", "importer", "scene")
	cfg.set_value("remap", "importer_version", 1)
	cfg.set_value("remap", "type", "PackedScene")
	cfg.set_value("deps", "source_file", UTHANA_TARGET_GLB)
	_set_common_scene_params(cfg)
	var sub := {"nodes": {SKELETON_NODE_KEY: _uthana_skeleton_node_settings()}}
	cfg.set_value("params", "_subresources", sub)
	cfg.set_value("params", "gltf/naming_version", 2)
	cfg.set_value("params", "gltf/embedded_image_handling", 1)
	var err := cfg.save(import_path)
	return err == OK


static func _set_common_scene_params(cfg: ConfigFile) -> void:
	cfg.set_value("params", "nodes/root_type", "")
	cfg.set_value("params", "nodes/root_name", "")
	cfg.set_value("params", "nodes/root_script", null)
	cfg.set_value("params", "nodes/apply_root_scale", true)
	cfg.set_value("params", "nodes/root_scale", 1.0)
	cfg.set_value("params", "nodes/import_as_skeleton_bones", false)
	cfg.set_value("params", "nodes/use_name_suffixes", true)
	cfg.set_value("params", "nodes/use_node_type_suffixes", true)
	cfg.set_value("params", "meshes/ensure_tangents", true)
	cfg.set_value("params", "meshes/generate_lods", true)
	cfg.set_value("params", "meshes/create_shadow_meshes", true)
	cfg.set_value("params", "meshes/light_baking", 1)
	cfg.set_value("params", "meshes/lightmap_texel_size", 0.2)
	cfg.set_value("params", "meshes/force_disable_compression", false)
	cfg.set_value("params", "skins/use_named_skins", true)
	cfg.set_value("params", "animation/import", true)
	cfg.set_value("params", "animation/fps", 30)
	cfg.set_value("params", "animation/trimming", false)
	cfg.set_value("params", "animation/remove_immutable_tracks", true)
	cfg.set_value("params", "animation/import_rest_as_RESET", false)
	cfg.set_value("params", "import_script/path", "")
	cfg.set_value("params", "materials/extract", 0)
	cfg.set_value("params", "materials/extract_format", 0)
	cfg.set_value("params", "materials/extract_path", "")


static func find_skeleton(root: Node) -> Skeleton3D:
	if root == null:
		return null
	var found: Array = root.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return null
	return found[0] as Skeleton3D


static func find_animation_player(root: Node) -> AnimationPlayer:
	if root == null:
		return null
	var found: Array = root.find_children("*", "AnimationPlayer", true, false)
	if found.is_empty():
		return null
	return found[0] as AnimationPlayer


static func resolve_bone(sk: Skeleton3D, canonical: String, mixamo_fallback: String = "") -> int:
	if sk == null:
		return -1
	var idx := sk.find_bone(canonical)
	if idx >= 0:
		return idx
	if not mixamo_fallback.is_empty():
		return sk.find_bone(mixamo_fallback)
	return -1


static func list_finger_bones(sk: Skeleton3D) -> PackedStringArray:
	var out: PackedStringArray = []
	if sk == null:
		return out
	for i in sk.get_bone_count():
		var n := sk.get_bone_name(i)
		var nl := n.to_lower()
		if (
			"thumb" in nl
			or "index" in nl
			or "middle" in nl
			or "ring" in nl
			or "pinky" in nl
			or "little" in nl
		):
			# Exclude whole-hand bones.
			if n.ends_with("Hand") or n == "LeftHand" or n == "RightHand":
				continue
			if n.ends_with("Hand") == false:
				out.append(n)
	return out


static func measure_forward_xz(sk: Skeleton3D) -> Vector3:
	var left_toe := resolve_bone(sk, "LeftToes", "mixamorig_LeftToeBase")
	var right_toe := resolve_bone(sk, "RightToes", "mixamorig_RightToeBase")
	var left_foot := resolve_bone(sk, "LeftFoot", "mixamorig_LeftFoot")
	var right_foot := resolve_bone(sk, "RightFoot", "mixamorig_RightFoot")
	var hips := resolve_bone(sk, "Hips", "mixamorig_Hips")
	if left_toe < 0 or right_toe < 0 or hips < 0:
		return Vector3.ZERO
	var toe_mid: Vector3 = (
		sk.get_bone_global_rest(left_toe).origin + sk.get_bone_global_rest(right_toe).origin
	) * 0.5
	var foot_mid: Vector3 = toe_mid
	if left_foot >= 0 and right_foot >= 0:
		foot_mid = (
			sk.get_bone_global_rest(left_foot).origin + sk.get_bone_global_rest(right_foot).origin
		) * 0.5
	var hips_o: Vector3 = sk.get_bone_global_rest(hips).origin
	var fwd := Vector3(toe_mid.x - hips_o.x, 0.0, toe_mid.z - hips_o.z)
	if fwd.length_squared() < 1e-8:
		fwd = Vector3(foot_mid.x - hips_o.x, 0.0, foot_mid.z - hips_o.z)
	return fwd.normalized() if fwd.length_squared() > 1e-8 else Vector3.ZERO


static func sample_ground_contact(
	skeleton: Skeleton3D, player: AnimationPlayer, clip_id: String, samples: int = 21
) -> Dictionary:
	## Backward-compatible bone-origin probe (diagnostic comparison only).
	var lowest := INF
	var highest := -INF
	var hips_min := INF
	var hips_max := -INF
	if skeleton == null or player == null or not player.has_animation(clip_id):
		return {"ok": false, "reason": "missing"}
	var anim: Animation = player.get_animation(clip_id)
	var hip_i := resolve_bone(skeleton, "Hips", "mixamorig_Hips")
	var foot_indices: Array[int] = []
	for name in FOOT_BONE_CANDIDATES:
		var bi := skeleton.find_bone(name)
		if bi >= 0 and not foot_indices.has(bi):
			foot_indices.append(bi)
	if foot_indices.is_empty():
		return {"ok": false, "reason": "no_feet"}
	player.play(clip_id)
	for si in samples:
		var t: float = (float(si) / float(maxi(samples - 1, 1))) * anim.length
		player.seek(t, true)
		skeleton.force_update_all_bone_transforms()
		for bi in foot_indices:
			var y: float = skeleton.to_global(skeleton.get_bone_global_pose(bi).origin).y
			lowest = minf(lowest, y)
			highest = maxf(highest, y)
		if hip_i >= 0:
			var hy: float = skeleton.to_global(skeleton.get_bone_global_pose(hip_i).origin).y
			hips_min = minf(hips_min, hy)
			hips_max = maxf(hips_max, hy)
	return {
		"ok": true,
		"method": "bone_origins",
		"lowest_foot_y": lowest,
		"highest_foot_y": highest,
		"foot_span": highest - lowest,
		"hips_span": hips_max - hips_min,
		"ground_offset_y": -lowest,
		"constant_placement": true,
	}


static func sample_sole_ground_contact(
	character_root: Node,
	skeleton: Skeleton3D,
	player: AnimationPlayer,
	clip_id: String,
	samples: int = 33
) -> Dictionary:
	## Acceptance grounding: skinned foot/sole mesh vertices (not bone origins).
	return SoleGround.sample_skinned_sole_contact(
		character_root, skeleton, player, clip_id, samples
	)


static func extract_and_save_walking_library() -> Dictionary:
	## Load natively retargeted Meshy AnimationLibrary and persist Walking only.
	if not ResourceLoader.exists(MESHY_SOURCE_GLB):
		return {"ok": false, "reason": "meshy_source_missing"}
	var loaded: Resource = load(MESHY_SOURCE_GLB)
	var walk: Animation = null
	var src_lib: AnimationLibrary = null
	if loaded is AnimationLibrary:
		src_lib = loaded as AnimationLibrary
		if src_lib.has_animation(WALKING_CLIP):
			walk = src_lib.get_animation(WALKING_CLIP)
		else:
			# Some imports nest under empty library name differently.
			for n in src_lib.get_animation_list():
				if String(n) == WALKING_CLIP or String(n).ends_with("/" + WALKING_CLIP):
					walk = src_lib.get_animation(n)
					break
	elif loaded is PackedScene:
		var root: Node = (loaded as PackedScene).instantiate()
		var ap := find_animation_player(root)
		if ap != null and ap.has_animation(WALKING_CLIP):
			walk = ap.get_animation(WALKING_CLIP)
		root.free()
	if walk == null:
		return {"ok": false, "reason": "walking_missing_after_import"}
	var out := AnimationLibrary.new()
	out.add_animation(WALKING_CLIP, walk.duplicate(true))
	var err := ResourceSaver.save(out, WALKING_LIBRARY_PATH)
	if err != OK:
		return {"ok": false, "reason": "save_failed_%d" % err}
	return {"ok": true, "path": WALKING_LIBRARY_PATH, "tracks": walk.get_track_count(), "length": walk.length}


static func ensure_walking_library() -> AnimationLibrary:
	if ResourceLoader.exists(WALKING_LIBRARY_PATH):
		return load(WALKING_LIBRARY_PATH) as AnimationLibrary
	var built := extract_and_save_walking_library()
	if not bool(built.get("ok", false)):
		return null
	return load(WALKING_LIBRARY_PATH) as AnimationLibrary


static func write_notes(extra: Dictionary = {}) -> void:
	var text := "# A1 Uthana retarget notes\n\n"
	text += "## Method (acceptance)\n"
	text += "- `%s` -- Godot 4.6.2 import-time SkeletonProfileHumanoid + BoneMap + Rest Fixer\n" % RETARGET_METHOD
	text += "- Docs: https://docs.godotengine.org/en/latest/tutorials/assets_pipeline/retargeting_3d_skeletons.html\n"
	text += "- Custom baked `%s` is FAILED and is not used by acceptance preview/tests.\n\n" % FAILED_CUSTOM_METHOD
	text += "## Isolation\n"
	text += "- Godot cannot attach a second import config to the production GLB paths.\n"
	text += "- A1 uses byte-identical copies under `import_sources/` with separate `.import` files.\n"
	text += "- Original Meshy/Uthana GLBs remain unchanged.\n\n"
	text += "## Paths\n"
	text += "- Meshy original (immutable): `%s`\n" % ORIG_MESHY_GLB
	text += "- Uthana original (immutable): `%s`\n" % ORIG_UTHANA_GLB
	text += "- A1 Meshy source copy: `%s`\n" % MESHY_SOURCE_GLB
	text += "- A1 Uthana target copy: `%s`\n" % UTHANA_TARGET_GLB
	text += "- Canonical Walking library: `%s`\n" % WALKING_LIBRARY_PATH
	text += "- Preview: `%suthana_a1_walking_preview.tscn`\n\n" % A1_DIR
	text += "## Importer settings (source PackedScene -> extract Walking library)\n"
	text += "- Godot rewrites type=AnimationLibrary back to PackedScene on headless import; Walking is extracted to `a1_native_walking.res`.\n"
	text += "- Remove Tracks / Except Bone Transform = false (4.6.2 bug: collapses multi-key rotations)\n"
	text += "- Remove Tracks / Unimportant Positions = true\n"
	text += "- Remove Tracks / Unmapped Bones = Remove\n"
	text += "- animation/remove_immutable_tracks = false\n"
	text += "- Bone Renamer + unique `%s`\n" % GENERAL_SKELETON_NAME
	text += "- Rest Fixer: Apply Node Transform, Normalize Position Tracks, Overwrite Axis\n"
	text += "- Rest Fixer / Fix Silhouette = true (Meshy A-pose); filter/base_height unused (no measured need)\n\n"
	text += "## Importer settings (target PackedScene)\n"
	text += "- Bone Renamer + unique `%s`\n" % GENERAL_SKELETON_NAME
	text += "- Rest Fixer: Apply Node Transform, Normalize Position Tracks, Overwrite Axis\n"
	text += "- Fix Silhouette = false (Uthana already T-pose)\n\n"
	text += "## Scale / orientation\n"
	text += "- Preview ModelRoot scale `%.2f`, yaw `%.1f`\n" % [PREVIEW_MODEL_SCALE, PREVIEW_MODEL_YAW]
	text += "- Ground offset recalculated from natively imported target feet.\n\n"
	if not extra.is_empty():
		text += "## Last extract\n"
		for k in extra.keys():
			text += "- %s: `%s`\n" % [str(k), str(extra[k])]
		text += "\n"
	text += "## Launch\n"
	text += "Open `res://assets/prototype/3d/units/generated_warrior/uthana_a1/uthana_a1_walking_preview.tscn` (F6).\n"
	text += "Automated gate does **not** claim visual PASS -- F6 required.\n"
	text += "Optional diagnostic: `uthana_a1_side_by_side_diagnostic.tscn`.\n"
	var f := FileAccess.open(NOTES_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()
