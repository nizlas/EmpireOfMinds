# Per-generated-asset compiled hand data for the current Uthana warrior.
# Triangle IDs, UV centroids, rest normals and the A2.7 calibrated thumb
# pose stay HERE — never in generic solver/policy code. A future generated
# unit must compile or load its own fixture and fail closed when confidence
# is insufficient.
extends RefCounted

const Family = preload("res://presentation/equipment/mixamo_52_hand_family.gd")

## Versioned evidence for THIS generated asset — not generic solver constants.
const SCHEMA_VERSION := "uthana_hand_fixture_v1"
const ASSET_ID := "uthana_warrior_a1_target"
const FAMILY_ID := Family.FAMILY_ID
const GLB_PATH := (
	"res://assets/prototype/3d/units/generated_warrior/uthana_a1/import_sources/a1_uthana_target.glb"
)
## SHA-256 of the imported GLB bytes (A2.6 audit identity; recompute if the
## source GLB is replaced — a future unit must compile its own fixture).
const GLB_SHA256 := "ADFE53DB59FE21D95456A69F1843F8D51CDD7C8DECAB08C02D06493032CD77BE"
## Bind-sanity required by `_bind_patches` on the A2 modifier: ≥2 of 3
## vertices dominant on Thumb3, remainder Thumb2; UV centroid match;
## rest-anchored winding maps authored cross product onto imported normals.
const PATCH_BIND_THUMB3_MIN := 2
const PATCH_WINDING_FLIP := -1.0
const PATCH_REST_NAIL_PAD_DOT_RIGHT := -0.02

## A2.7 texture/topology-verified RIGHT distal patches (audit A2.6).
const RIGHT_NAIL_TRIS: Array[Dictionary] = [
	{"si": 0, "i": [5486, 3302, 3301], "uvc": Vector2(0.923572, 0.030563), "flip": -1.0},
	{"si": 0, "i": [5486, 5488, 3302], "uvc": Vector2(0.930995, 0.032087), "flip": -1.0},
	{"si": 0, "i": [3302, 5488, 5489], "uvc": Vector2(0.933836, 0.033164), "flip": -1.0},
	{"si": 0, "i": [3302, 5489, 5484], "uvc": Vector2(0.936114, 0.033419), "flip": -1.0},
]
const RIGHT_PAD_TRIS: Array[Dictionary] = [
	{"si": 0, "i": [5480, 5481, 5482], "uvc": Vector2(0.932028, 0.013940), "flip": -1.0},
	{"si": 0, "i": [5480, 5482, 5483], "uvc": Vector2(0.928115, 0.010751), "flip": -1.0},
	{"si": 0, "i": [5482, 3301, 5483], "uvc": Vector2(0.920574, 0.017876), "flip": -1.0},
	{"si": 0, "i": [5482, 5481, 5485], "uvc": Vector2(0.931609, 0.020589), "flip": -1.0},
	{"si": 0, "i": [3300, 5485, 5481], "uvc": Vector2(0.934737, 0.021865), "flip": -1.0},
	{"si": 0, "i": [5486, 3301, 5482], "uvc": Vector2(0.922155, 0.023965), "flip": -1.0},
	{"si": 0, "i": [5486, 5482, 5485], "uvc": Vector2(0.929277, 0.023490), "flip": -1.0},
	{"si": 0, "i": [5487, 5485, 3300], "uvc": Vector2(0.934695, 0.024450), "flip": -1.0},
	{"si": 0, "i": [5486, 5485, 5488], "uvc": Vector2(0.930595, 0.026941), "flip": -1.0},
	{"si": 0, "i": [5487, 5488, 5485], "uvc": Vector2(0.932885, 0.026626), "flip": -1.0},
]
const RIGHT_NAIL_NORMAL_LOCAL := Vector3(0.844382, -0.028367, -0.534991)
const RIGHT_PAD_NORMAL_LOCAL := Vector3(0.50628, -0.186105, 0.84205)
const RIGHT_REST_NAIL_PAD_DOT := -0.02
const RIGHT_PAD_MARKER_LOCAL := Vector3(0.010229, -0.00161, 0.006254)

## SUPERSEDED A2.5 constants — false-positive regression only.
const SUPERSEDED_A25_NAIL_NORMAL_LOCAL := Vector3(-0.158876, -0.048808, -0.986091)
const SUPERSEDED_A25_PAD_NORMAL_LOCAL := Vector3(-0.417165, -0.33319, 0.845552)
const SUPERSEDED_A25_PAD_MARKER_LOCAL := Vector3(0.011303, 0.002786, 0.00061)

## Rejected A2.6 pose (this warrior): over-pronated CMC compensating for
## mislabeled A2.5 plates. Kept as evidence — not a solver default.
const REJECTED_A26_THUMB_ANAT := {
	"sigma": 25.0,
	"phi": 0.0,
	"tau": -90.0,
	"flex_mcp": 0.0,
	"flex_ip": 90.0,
}
## Accepted A2.7 right-hand anatomical pose (this warrior). CMC tau is
## opposition/pronation; MCP/IP stay pure flexion. Not universal.
const CANON_THUMB_ANAT := {
	"sigma": 20.0,
	"phi": 0.0,
	"tau": -60.0,
	"flex_mcp": 10.0,
	"flex_ip": 80.0,
}
const ACCEPTED_A27_THUMB_ANAT := CANON_THUMB_ANAT
## Left-hand CMC compiled on this asset (A2.8). Same MCP/IP flexion *policy*
## as the right; the numbers are independently derived. The left rest thumb
## sits further toward the head, so phi is abducted to keep the pad in the
## finger slab. Not a negated copy of the right Euler numbers. Full left
## assemble still fail-closes T2 contour — these numbers are not a PASS.
const CANON_THUMB_ANAT_LEFT := {
	"sigma": 19.0,
	"phi": -110.0,
	"tau": -80.0,
	"flex_mcp": 10.0,
	"flex_ip": 80.0,
}
const CANON_FLEX_DEG := {
	"index": [60.0, 71.0, 35.0],
	"middle": [63.0, 75.0, 37.0],
	"ring": [69.0, 81.0, 40.0],
	"pinky": [71.0, 83.0, 43.0],
}

## LEFT distal patches compiled independently from the same GLB (A2.6 audit
## §2 UV islands + A2.8 rest-pose census). Nail = high-U dorsal island
## (~0.94, 0.86); pad = volar tip island (~0.15, 0.66). Not a topological
## copy of the right IDs — correspondence was not assumed.
const LEFT_NAIL_TRIS: Array[Dictionary] = [
	{"si": 0, "i": [5053, 5054, 5055], "uvc": Vector2(0.9402, 0.8666), "flip": -1.0},
	{"si": 0, "i": [5053, 5055, 3027], "uvc": Vector2(0.9448, 0.8628), "flip": -1.0},
	{"si": 0, "i": [5055, 5056, 3027], "uvc": Vector2(0.9437, 0.8559), "flip": -1.0},
	{"si": 0, "i": [5053, 3027, 5057], "uvc": Vector2(0.9487, 0.8641), "flip": -1.0},
	{"si": 0, "i": [5055, 3028, 5056], "uvc": Vector2(0.9398, 0.8547), "flip": -1.0},
	{"si": 0, "i": [5055, 5054, 3028], "uvc": Vector2(0.9379, 0.8612), "flip": -1.0},
	{"si": 0, "i": [5053, 5057, 1980], "uvc": Vector2(0.9488, 0.8689), "flip": -1.0},
	{"si": 0, "i": [5058, 3028, 5054], "uvc": Vector2(0.9343, 0.8638), "flip": -1.0},
]
## Rest-compiled LEFT plate references (A2.8 census + CPU skin at rest).
## Independent of the right constants — topology is not a proven mirror.
const LEFT_NAIL_NORMAL_LOCAL := Vector3(0.678238, 0.198379, 0.707558)
const LEFT_PAD_NORMAL_LOCAL := Vector3(-0.981665, 0.171935, -0.082291)
const LEFT_REST_NAIL_PAD_DOT := -0.68992
const LEFT_PAD_MARKER_LOCAL := Vector3(-0.004999, 0.004626, -0.000526)

const LEFT_PAD_TRIS: Array[Dictionary] = [
	{"si": 0, "i": [3882, 3879, 3881], "uvc": Vector2(0.1461, 0.6557), "flip": -1.0},
	{"si": 0, "i": [3882, 3881, 3315], "uvc": Vector2(0.1455, 0.6649), "flip": -1.0},
	{"si": 0, "i": [3883, 3881, 3880], "uvc": Vector2(0.1550, 0.6594), "flip": -1.0},
	{"si": 0, "i": [3885, 3315, 3881], "uvc": Vector2(0.1464, 0.6684), "flip": -1.0},
	{"si": 0, "i": [3883, 3885, 3881], "uvc": Vector2(0.1509, 0.6657), "flip": -1.0},
	{"si": 0, "i": [3886, 3315, 3885], "uvc": Vector2(0.1453, 0.6760), "flip": -1.0},
	{"si": 0, "i": [3889, 3886, 3885], "uvc": Vector2(0.1483, 0.6755), "flip": -1.0},
	{"si": 0, "i": [3888, 3886, 3889], "uvc": Vector2(0.1503, 0.6764), "flip": -1.0},
]
static var _left_cache: Dictionary = {}


static func right_surface() -> Dictionary:
	return {
		"nail_tris": RIGHT_NAIL_TRIS,
		"pad_tris": RIGHT_PAD_TRIS,
		"nail_normal_local": RIGHT_NAIL_NORMAL_LOCAL,
		"pad_normal_local": RIGHT_PAD_NORMAL_LOCAL,
		"rest_nail_pad_dot": RIGHT_REST_NAIL_PAD_DOT,
		"pad_marker_local": RIGHT_PAD_MARKER_LOCAL,
		# Historical superseded references: false-positive diagnostic only,
		# never gated (see A2.6 ground-truth audit).
		"superseded_nail_normal_local": SUPERSEDED_A25_NAIL_NORMAL_LOCAL,
		"superseded_pad_normal_local": SUPERSEDED_A25_PAD_NORMAL_LOCAL,
		"compiled": true,
		"source": "a27_audit",
	}


## Canonical authored finger flexion for this warrior (A2.3 calibration on
## the EoM 52-bone profile). Consumed by the engine through the profile.
static func finger_flex() -> Dictionary:
	return CANON_FLEX_DEG.duplicate(true)


## Bind-time rest-frame compilation of the LEFT compiled triangle lists.
## Runtime never reads albedo; this only CPU-skins the authored IDs.
static func compile_left_from_mesh(
	character: Node, skeleton: Skeleton3D
) -> Dictionary:
	if not _left_cache.is_empty() and bool(_left_cache.get("compiled", false)):
		return _left_cache.duplicate(true)
	var out := {"compiled": false, "error_class": "LEFT_PATCH_COMPILE_FAILED"}
	if character == null or skeleton == null:
		return out
	var Skinning = load("res://presentation/equipment/skinned_mesh_geometry.gd")
	var mi: MeshInstance3D = Skinning.find_skinned_mesh(character)
	if mi == null or mi.mesh == null or mi.skin == null:
		out["error_class"] = "LEFT_PATCH_NO_MESH"
		return out
	var t3: int = skeleton.find_bone("mixamorig_LeftHandThumb3")
	if t3 < 0:
		out["error_class"] = "LEFT_THUMB_BONES_MISSING"
		return out
	var bind_map := PackedInt32Array()
	bind_map.resize(mi.skin.get_bind_count())
	for bi in mi.skin.get_bind_count():
		var bone_i: int = mi.skin.get_bind_bone(bi)
		if bone_i < 0:
			bone_i = skeleton.find_bone(String(mi.skin.get_bind_name(bi)))
		bind_map[bi] = bone_i
	var arrays: Array = mi.mesh.surface_get_arrays(0)
	var bpv: int = Skinning.bones_per_vertex(
		arrays[Mesh.ARRAY_BONES], (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	)
	var saved: Array = []
	for bn in ["mixamorig_LeftHandThumb1", "mixamorig_LeftHandThumb2", "mixamorig_LeftHandThumb3"]:
		var bi2: int = skeleton.find_bone(bn)
		saved.append([bi2, skeleton.get_bone_pose_rotation(bi2)])
		skeleton.reset_bone_pose(bi2)
	skeleton.force_update_all_bone_transforms()
	var t3_world: Transform3D = (
		skeleton.global_transform * skeleton.get_bone_global_pose(t3)
	)
	var t3_inv: Transform3D = t3_world.affine_inverse()
	var nail_n := _agg_rest_normal(mi, skeleton, LEFT_NAIL_TRIS, t3_inv, Skinning, bind_map, bpv)
	var pad_n := _agg_rest_normal(mi, skeleton, LEFT_PAD_TRIS, t3_inv, Skinning, bind_map, bpv)
	var pad_c := _agg_rest_centroid(mi, skeleton, LEFT_PAD_TRIS, t3_inv, Skinning, bind_map, bpv)
	for pair in saved:
		skeleton.set_bone_pose_rotation(int(pair[0]), pair[1])
	skeleton.force_update_all_bone_transforms()
	# Area-weighted rest normals on this mesh are ~5e-5 before normalize
	# (centimetre-scale distal plates). Fail only on a true zero sum.
	if nail_n.length_squared() < 1e-16 or pad_n.length_squared() < 1e-16:
		out["error_class"] = "LEFT_PATCH_DEGENERATE"
		out["nail_len"] = nail_n.length()
		out["pad_len"] = pad_n.length()
		return out
	_left_cache = {
		"compiled": true,
		"source": "a28_left_census",
		"nail_tris": LEFT_NAIL_TRIS,
		"pad_tris": LEFT_PAD_TRIS,
		"nail_normal_local": nail_n.normalized(),
		"pad_normal_local": pad_n.normalized(),
		"rest_nail_pad_dot": nail_n.normalized().dot(pad_n.normalized()),
		"pad_marker_local": pad_c,
	}
	return _left_cache.duplicate(true)


static func _agg_rest_normal(
	mi: MeshInstance3D, skel: Skeleton3D, tris: Array, t3_inv: Transform3D, Skinning, bind_map: PackedInt32Array, bpv: int
) -> Vector3:
	var acc := Vector3.ZERO
	for rec_v in tris:
		var rec: Dictionary = rec_v
		var idx: Array = rec["i"]
		var si: int = int(rec["si"])
		var p0: Vector3 = Skinning.skinned_vertex_world(mi, skel, si, int(idx[0]), bpv, bind_map)
		var p1: Vector3 = Skinning.skinned_vertex_world(mi, skel, si, int(idx[1]), bpv, bind_map)
		var p2: Vector3 = Skinning.skinned_vertex_world(mi, skel, si, int(idx[2]), bpv, bind_map)
		var ng: Vector3 = (p1 - p0).cross(p2 - p0)
		var area: float = ng.length() * 0.5
		if area <= 1e-14:
			continue
		ng = ng.normalized() * float(rec.get("flip", -1.0))
		acc += (t3_inv.basis * ng) * area
	return acc


static func _agg_rest_centroid(
	mi: MeshInstance3D, skel: Skeleton3D, tris: Array, t3_inv: Transform3D, Skinning, bind_map: PackedInt32Array, bpv: int
) -> Vector3:
	var acc := Vector3.ZERO
	var wsum := 0.0
	for rec_v in tris:
		var rec: Dictionary = rec_v
		var idx: Array = rec["i"]
		var si: int = int(rec["si"])
		var p0: Vector3 = Skinning.skinned_vertex_world(mi, skel, si, int(idx[0]), bpv, bind_map)
		var p1: Vector3 = Skinning.skinned_vertex_world(mi, skel, si, int(idx[1]), bpv, bind_map)
		var p2: Vector3 = Skinning.skinned_vertex_world(mi, skel, si, int(idx[2]), bpv, bind_map)
		var c: Vector3 = (p0 + p1 + p2) / 3.0
		acc += t3_inv * c
		wsum += 1.0
	return acc / maxf(wsum, 1.0)


static func left_surface(character: Node, skeleton: Skeleton3D) -> Dictionary:
	return compile_left_from_mesh(character, skeleton)


static func thumb_anat_for_side(side: String) -> Dictionary:
	if side == "left":
		return CANON_THUMB_ANAT_LEFT.duplicate()
	return CANON_THUMB_ANAT.duplicate()


static func surface_for_side(side: String, character: Node, skeleton: Skeleton3D) -> Dictionary:
	if side == "left":
		return left_surface(character, skeleton)
	return right_surface()
