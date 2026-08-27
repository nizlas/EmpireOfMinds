# One reusable application order for rigid equipment + finger grip (A2.9:
# the actual runtime owner for the accepted right-hand preview). A rigid
# weapon has exactly one transform owner (the owner hand's socket).
# secondary_grip is an interface only — no two-handed IK.
#
# ALL family/asset/weapon/engine choices are INJECTED via
# configure_dependencies(); the generic core has no silent asset defaults
# and fails closed with named error classes when a dependency is missing.
# A composition root outside the core (e.g. the Uthana A2 one) selects the
# concrete family, fixture, weapon and engine.
#
# The socket mapping and the hard preconditions belong to the resolved
# interaction POLICY, not to this file: a future policy is a new policy
# script (optionally injected as `policies`), never an edit here.
extends Node

const HandProfile = preload("res://presentation/equipment/humanoid_hand_profile.gd")
const GripGeom = preload("res://presentation/equipment/equipment_grip_geometry.gd")
const Policy = preload("res://presentation/equipment/grip_interaction_profile.gd")
const Solver = preload("res://presentation/equipment/hand_grip_solver.gd")
const DefaultSkinning = preload("res://presentation/equipment/skinned_mesh_geometry.gd")
const CompiledFixture = preload("res://presentation/equipment/compiled_hand_fixture.gd")

const SOCKET_OFFSET_NAME := "SocketOffset"

## The environment gate for the test-only reference fixture (A2.12). A shipped
## runtime never sets it, so the development oracle self-fail-closes outside a
## test harness even if a caller asks for reference mode.
const REFERENCE_MODE_ENV := "EOM_ALLOW_REFERENCE_FIXTURE"
const REFERENCE_MODE_ENV_VALUE := "1"

var _skeleton: Skeleton3D = null
var _character: Node3D = null
var _profile = null
var _side: String = "right"
var _policy_id: String = Policy.POLICY_POWER_GRIP_1H
## The resolved policy SCRIPT that owns the socket mapping and the hard
## preconditions for `_policy_id`. Never a hardcoded choice in this file.
var _policy: Script = null
var _club_socket: Node3D = null
var _club_instance: Node3D = null
var _shape: Dictionary = {}
var _geometry: Dictionary = {}
var _invariants: Dictionary = {}
var _volar: Dictionary = {}
var _mesh_binding: Dictionary = {}
var _grip_local: Transform3D = Transform3D.IDENTITY
var _grip: SkeletonModifier3D = null
var _humanoid_height: float = 0.0
## Full result of the semantic-landmark height measurement for the last
## assemble: which bones were used, in which space, and why it failed.
var _height_measurement: Dictionary = {}
var _club_path_override: String = ""
var _last_result: Dictionary = {}
## Injected dependencies: family, fixture, weapon_scene or weapon_path,
## weapon_node_name, engines {policy_id: Script}, optional skinning,
## optional policies {policy_id: Script} overriding the registry.
var _deps: Dictionary = {}


func configure_dependencies(deps: Dictionary) -> void:
	_deps = deps.duplicate()


func dependencies() -> Dictionary:
	return _deps.duplicate()


## Test hook (smoke tests only): broken paths still fail closed.
func set_club_path_override(path: String) -> void:
	_club_path_override = path


func owner_side() -> String:
	return _side


## The policy script that actually owned the socket mapping and the hard
## preconditions for the last assemble.
func policy_script() -> Script:
	return _policy


## The injected fixture that supplied the surface evidence for the last
## assemble. Diagnostics read provenance off this rather than guessing which
## fixture the composition chose.
func fixture_script():
	return _deps.get("fixture", null)


func last_result() -> Dictionary:
	return _last_result.duplicate(true)


func club_socket() -> Node3D:
	return _club_socket


func club_instance() -> Node3D:
	return _club_instance


func grip_modifier() -> SkeletonModifier3D:
	return _grip


func has_club() -> bool:
	return _club_socket != null and is_instance_valid(_club_socket)


func grip_shape() -> Dictionary:
	return _shape.duplicate(true)


func hand_profile():
	return _profile


func marker_metadata() -> Dictionary:
	return (_geometry.get("metadata", {}) as Dictionary).duplicate(true)


func weapon_analysis() -> Dictionary:
	return (_geometry.get("analysis", {}) as Dictionary).duplicate(true)


func invariants() -> Dictionary:
	return _invariants.duplicate(true)


func volar_verification() -> Dictionary:
	return _volar.duplicate(true)


func set_grip_enabled(enabled: bool) -> void:
	if _grip != null and is_instance_valid(_grip):
		(_grip as Object).set_grip_enabled(enabled)
		if enabled:
			(_grip as Object).apply_now()


func is_grip_enabled() -> bool:
	if _grip == null or not is_instance_valid(_grip):
		return false
	return bool((_grip as Object).is_grip_enabled())


func _skinning():
	return _deps.get("skinning", DefaultSkinning)


## Result of the mandatory live-mesh binding for the last assemble.
func mesh_binding() -> Dictionary:
	return _mesh_binding.duplicate(true)


## Bind the injected fixture to the RIGGED MESH this assembler will pose.
##
## A2.12 — VERIFICATION IS NOT OPT-IN. Until A2.12 this probed
## `fixture.has_method("verify_against_mesh")` and treated absence as
## "unbound but fine", so any fixture could skip identity verification simply
## by not implementing it — including the hand-authored A2.7 oracle, which
## assembled with `verified: false`. The assembler now dispatches on an
## explicitly DECLARED contract:
##
##   * `certified_runtime_v1`     — must verify against the live rig, and a
##     failed or unverified result is a refusal.
##   * `test_only_reference_v1`   — the development oracle. Reachable only when
##     reference mode is explicitly enabled AND the environment allows it, so a
##     production composition or a normal preview cannot activate it.
##   * anything else, or no contract at all — `FIXTURE_BINDING_UNSUPPORTED`.
func _verify_fixture_binding(fixture, character: Node3D, family) -> Dictionary:
	var contract: String = _fixture_contract(fixture)
	if contract.is_empty():
		return {
			"ok": false,
			"error_class": "FIXTURE_BINDING_UNSUPPORTED",
			"detail": "the injected fixture declares no verification contract",
		}
	if contract == CompiledFixture.CONTRACT_TEST_ONLY_REFERENCE:
		return _reference_fixture_binding(contract)
	if contract != CompiledFixture.CONTRACT_CERTIFIED_RUNTIME:
		return {
			"ok": false,
			"error_class": "FIXTURE_BINDING_UNSUPPORTED",
			"detail": "unknown fixture verification contract '%s'" % contract,
		}
	if not (fixture as Object).has_method("verify_against_rig"):
		# A fixture that claims the certified contract but cannot honour it is
		# a broken fixture, never an unverified pass.
		return {
			"ok": false,
			"error_class": "FIXTURE_VERIFICATION_REQUIRED",
			"detail": "the certified contract requires verify_against_rig",
		}
	var mi: MeshInstance3D = _skinning().find_skinned_mesh(character)
	if mi == null or mi.mesh == null:
		return {"ok": false, "error_class": "FIXTURE_LIVE_MESH_MISSING"}
	var r: Dictionary = fixture.verify_against_rig(mi, _skeleton)
	if not bool(r.get("ok", false)):
		return r
	# An `ok` result that does not actually claim verification is treated as a
	# refusal, so "verified: false" can never reach a pose.
	if not bool(r.get("verified", false)):
		return {
			"ok": false,
			"error_class": "FIXTURE_VERIFICATION_REQUIRED",
			"detail": "the fixture did not report a verified binding",
		}
	# The fixture was certified FOR a family id + version. Cross-check it
	# against the family actually injected here: a certificate for another
	# family version may not drive this rig even if the rig hash matches.
	var fam_check: Dictionary = _verify_certified_family(fixture, family)
	if not bool(fam_check.get("ok", false)):
		return fam_check
	# The fixture was also certified UNDER a grip policy + policy version, and
	# the achieved-geometry gate that accepted it is that policy's gate
	# (A2.13a). Assembling it under another policy, or under a retuned version
	# of the same policy, would reuse an acceptance that was never measured for
	# what is about to be posed.
	var pol_check: Dictionary = _verify_certified_policy(fixture)
	if not bool(pol_check.get("ok", false)):
		return pol_check
	return {
		"ok": true,
		"binding": "certified_bound",
		"policy_id": str(pol_check.get("policy_id", "")),
		"policy_version": str(pol_check.get("policy_version", "")),
		"contract": contract,
		"verified": true,
		"geometry_sha256": str(r.get("geometry_sha256", "")),
		"rig_sha256": str(r.get("rig_sha256", "")),
		"certification_hash": str(r.get("certification_hash", "")),
		"family_id": str(fam_check.get("family_id", "")),
		"family_version": str(fam_check.get("family_version", "")),
		"mesh_node": str(mi.name),
	}


## The declared contract, or "" when the fixture declares none.
func _fixture_contract(fixture) -> String:
	var obj: Object = fixture as Object
	if obj == null:
		return ""
	if not obj.has_method("fixture_verification_contract"):
		return ""
	return str(obj.call("fixture_verification_contract"))


## The test-only reference oracle. Two independent gates, both required: the
## caller must ask for reference mode, and the environment must permit it. A
## production composition never sets the first; a shipped runtime never sets
## the second.
func _reference_fixture_binding(contract: String) -> Dictionary:
	if not bool(_deps.get("reference_fixture_mode", false)):
		return {
			"ok": false,
			"error_class": "FIXTURE_NOT_CERTIFIED",
			"detail": "a test-only reference fixture is not a certified runtime fixture",
		}
	if OS.get_environment(REFERENCE_MODE_ENV) != REFERENCE_MODE_ENV_VALUE:
		return {
			"ok": false,
			"error_class": "FIXTURE_REFERENCE_MODE_FORBIDDEN",
			"detail": "reference mode requires %s=%s in the environment"
				% [REFERENCE_MODE_ENV, REFERENCE_MODE_ENV_VALUE],
		}
	return {
		"ok": true,
		"binding": "test_only_reference",
		"contract": contract,
		"verified": false,
		"reference_mode": true,
	}


## The policy + policy version the fixture was certified under must be the
## policy this assemble is running. The version comes from the resolved policy
## SCRIPT, never from the fixture, so a certificate cannot vouch for itself.
func _verify_certified_policy(fixture) -> Dictionary:
	var obj: Object = fixture as Object
	if not obj.has_method("certified_policy"):
		return {
			"ok": false,
			"error_class": "FIXTURE_VERIFICATION_REQUIRED",
			"detail": "the certified contract requires certified_policy",
		}
	var certified: Dictionary = obj.call("certified_policy")
	if str(certified.get("policy_id", "")) != _policy_id:
		return {
			"ok": false,
			"error_class": "FIXTURE_POLICY_MISMATCH",
			"detail": "fixture certified for policy '%s', assembling with '%s'"
				% [certified.get("policy_id", ""), _policy_id],
		}
	if _policy == null:
		return {"ok": false, "error_class": "POLICY_NOT_IMPLEMENTED", "detail": _policy_id}
	var want_version := str(_policy.POLICY_VERSION)
	if want_version.strip_edges().is_empty():
		return {
			"ok": false,
			"error_class": "FIXTURE_POLICY_VERSION_MISMATCH",
			"detail": "the resolved policy declares no POLICY_VERSION",
		}
	if str(certified.get("policy_version", "")) != want_version:
		return {
			"ok": false,
			"error_class": "FIXTURE_POLICY_VERSION_MISMATCH",
			"detail": "fixture certified for policy version '%s', assembling with '%s'"
				% [certified.get("policy_version", ""), want_version],
		}
	return {
		"ok": true,
		"policy_id": _policy_id,
		"policy_version": want_version,
	}


func _verify_certified_family(fixture, family) -> Dictionary:
	if family == null:
		return {"ok": false, "error_class": "FAMILY_REQUIRED"}
	var obj: Object = fixture as Object
	if not obj.has_method("certified_family"):
		return {
			"ok": false,
			"error_class": "FIXTURE_VERIFICATION_REQUIRED",
			"detail": "the certified contract requires certified_family",
		}
	var certified: Dictionary = obj.call("certified_family")
	var want_id := str(family.FAMILY_ID)
	var want_version := str(family.FAMILY_VERSION)
	if want_version.strip_edges().is_empty():
		return {
			"ok": false,
			"error_class": "FIXTURE_FAMILY_VERSION_MISMATCH",
			"detail": "the injected family declares no FAMILY_VERSION",
		}
	if str(certified.get("family_id", "")) != want_id:
		return {
			"ok": false,
			"error_class": "FIXTURE_FAMILY_MISMATCH",
			"detail": "fixture certified for family '%s', assembling with '%s'"
				% [certified.get("family_id", ""), want_id],
		}
	if str(certified.get("family_version", "")) != want_version:
		return {
			"ok": false,
			"error_class": "FIXTURE_FAMILY_VERSION_MISMATCH",
			"detail": "fixture certified for family version '%s', assembling with '%s'"
				% [certified.get("family_version", ""), want_version],
		}
	return {"ok": true, "family_id": want_id, "family_version": want_version}


## 1. body animation is assumed already sampled by the caller
## 2. carry overlay: interface only (not applied in this slice)
## 3. attach rigid equipment once through the owner hand + primary_grip
## 4. secondary IK: interface only
## 5. per-hand finger interaction after animation
## 6. update skeleton transforms
## 7. measure achieved skinned geometry
## 8. accept or reject fail-closed
## 9. classified diagnostics
func assemble(
	character: Node3D, side: String = "right", policy_id: String = Policy.POLICY_POWER_GRIP_1H
) -> Dictionary:
	_side = "left" if side == "left" else "right"
	_policy_id = policy_id
	_character = character
	var injected_policies: Dictionary = _deps.get("policies", {})
	if Policy.requires_secondary(policy_id, injected_policies):
		return _fail("secondary_ik_not_implemented", "SECONDARY_IK_NOT_IMPLEMENTED")
	_policy = Policy.resolve(policy_id, injected_policies)
	if _policy == null:
		return _fail("policy_not_implemented", "POLICY_NOT_IMPLEMENTED")
	var family = _deps.get("family", null)
	if family == null:
		return _fail("family_required", "FAMILY_REQUIRED")
	var fixture = _deps.get("fixture", null)
	if fixture == null:
		return _fail("fixture_required", "FIXTURE_REQUIRED")
	var engines: Dictionary = _deps.get("engines", {})
	var engine_script: Script = engines.get(policy_id, null)
	if engine_script == null:
		return _fail("engine_required", "ENGINE_REQUIRED")
	if _club_path_override.is_empty() and not _deps.has("weapon_scene") and str(_deps.get("weapon_path", "")).is_empty():
		return _fail("weapon_source_required", "WEAPON_SOURCE_REQUIRED")
	_skeleton = _skinning().find_skeleton(character)
	if _skeleton == null:
		return _fail("skeleton_missing", "SKELETON_MISSING")
	# MANDATORY rig binding, before the fixture may drive anything. A fixture
	# whose evidence references triangle ids and bone-local markers only means
	# something for the exact rigged mesh it was compiled from, so the identity
	# of what this assembler is about to pose is checked here — ahead of profile
	# compilation, socket construction and geometric bind sanity.
	_mesh_binding = _verify_fixture_binding(fixture, character, family)
	if not bool(_mesh_binding.get("ok", false)):
		return {
			"ok": false,
			"reason": "fixture_mesh_binding_failed",
			"error_class": str(_mesh_binding.get("error_class", "FIXTURE_RIG_HASH_MISMATCH")),
			"mesh_binding": _mesh_binding,
		}
	var compiled: Dictionary = HandProfile.compile(
		_skeleton, character, _side, fixture, family, _skinning()
	)
	if not bool(compiled.get("ok", false)):
		return {
			"ok": false,
			"reason": "hand_profile_failed",
			"error_class": "HAND_PROFILE_FAILED",
			"failures": compiled.get("failures", []),
		}
	_profile = compiled["profile"]
	# Humanoid height from SEMANTIC landmarks the family resolved on this rig
	# (A2.12). "This rig spells its head bone differently" and "this rig has no
	# vertical extent" are two different facts and get two different names.
	var landmarks: Dictionary = HandProfile.family_height_landmarks(family, _skeleton)
	_height_measurement = _skinning().measure_humanoid_height_from_landmarks(
		_skeleton, landmarks
	)
	if not bool(_height_measurement.get("ok", false)):
		var height_class := str(
			_height_measurement.get("error_class", "HUMANOID_HEIGHT_LANDMARKS_UNRESOLVED")
		)
		return {
			"ok": false,
			"reason": height_class.to_lower(),
			"error_class": height_class,
			"height": _height_measurement,
		}
	_humanoid_height = float(_height_measurement["height"])
	var frame_pose: Dictionary = _profile.compute_frame(_skeleton, false)
	if not bool(frame_pose.get("ok", false)):
		return {
			"ok": false,
			"reason": "hand_frame_failed",
			"error_class": frame_pose.get("error_class", "HAND_FRAME_FAILED"),
			"frame": frame_pose,
		}
	_volar = _profile.verify_volar(_skeleton, _character, frame_pose)
	if not bool(_volar.get("ok", false)):
		return {
			"ok": false,
			"reason": "volar_verification_failed",
			"error_class": _volar.get("error_class", "VOLAR_VERIFICATION_FAILED"),
			"volar": _volar,
		}
	var attach_r: Dictionary = _attach_weapon()
	if not bool(attach_r.get("ok", false)):
		return attach_r
	# Secondary reach/IK reserved — a second transform owner is forbidden.
	if _club_instance != null and _club_instance.get_parent() != null:
		var owners := 0
		var n: Node = _club_instance
		while n != null:
			if str(n.name).begins_with("WeaponSocket_"):
				owners += 1
			n = n.get_parent()
		if owners != 1:
			return _fail("weapon_two_transform_owners", "WEAPON_TWO_TRANSFORM_OWNERS")
	var offset: Node3D = _club_socket.get_node(SOCKET_OFFSET_NAME) as Node3D
	_invariants = _policy.evaluate_grip_invariants(
		frame_pose, offset.global_transform, float(_shape.get("radius_mean", 0.01))
	)
	if not bool(_invariants.get("pass", false)):
		_clear_weapon()
		return {
			"ok": false,
			"reason": "grip_frame_preconditions_failed",
			"error_class": "GRIP_FRAME_PRECONDITION_FAILED",
			"invariants": _invariants,
		}
	var grip_ok: Dictionary = Solver.attach(
		_skeleton, _character, _club_instance, _shape, frame_pose, _profile, engine_script
	)
	_grip = grip_ok.get("grip", null)
	_last_result = {
		"ok": bool(grip_ok.get("ok", false)),
		"side": _side,
		"policy": _policy_id,
		"policy_owner": str(_policy.resource_path).get_file(),
		"profile_key": compiled.get("cache_key", ""),
		"mesh_binding": _mesh_binding,
		"shape": _shape,
		"geometry": _geometry,
		"volar": _volar,
		"invariants": _invariants,
		"grip": grip_ok,
		"reason": grip_ok.get("reason", ""),
		"error_class": grip_ok.get("error_class", ""),
		"club_path": _club_source_path(),
		"application_order": [
			"body_animation_sampled",
			"carry_overlay_skipped",
			"owner_hand_primary_grip",
			"secondary_ik_skipped",
			"finger_interaction",
			"skeleton_update",
			"achieved_skinned_measure",
			"fail_closed_accept",
		],
	}
	return _last_result


func _attach_weapon() -> Dictionary:
	if _club_socket != null and is_instance_valid(_club_socket):
		return {"ok": true, "already": true}
	var packed: PackedScene = null
	if _club_path_override.is_empty() and _deps.has("weapon_scene"):
		packed = _deps.get("weapon_scene") as PackedScene
	else:
		var path: String = _club_source_path()
		if not ResourceLoader.exists(path):
			return _fail("club_missing", "CLUB_MISSING")
		packed = load(path) as PackedScene
	if packed == null:
		return _fail("club_load_failed", "CLUB_LOAD_FAILED")
	var socket := Node3D.new()
	socket.name = "WeaponSocket_L" if _side == "left" else "WeaponSocket_R"
	add_child(socket)
	var offset := Node3D.new()
	offset.name = SOCKET_OFFSET_NAME
	offset.transform = Transform3D.IDENTITY
	socket.add_child(offset)
	var instance: Node3D = packed.instantiate() as Node3D
	if instance == null:
		socket.queue_free()
		return _fail("instantiate_failed", "INSTANTIATE_FAILED")
	instance.name = str(_deps.get("weapon_node_name", "Weapon"))
	offset.add_child(instance)
	_force_visible(instance)
	_geometry = GripGeom.from_normalized_melee(instance, _humanoid_height, _side)
	if not bool(_geometry.get("ok", false)):
		socket.queue_free()
		return {
			"ok": false,
			"reason": "grip_geometry_failed",
			"error_class": "GRIP_GEOMETRY_FAILED",
			"failures": _geometry.get("failures", []),
		}
	_shape = _geometry.get("shape", {})
	var frame_rest: Dictionary = _profile.compute_frame(_skeleton, true)
	if not bool(frame_rest.get("ok", false)):
		socket.queue_free()
		return {
			"ok": false,
			"reason": "rest_frame_failed",
			"error_class": frame_rest.get("error_class", "HAND_FRAME_FAILED"),
		}
	var r_mean: float = float(_shape.get("radius_mean", 0.01))
	var grip_world_rest: Transform3D = _policy.build_grip_socket_world(frame_rest, r_mean)
	var hand_rest: Transform3D = frame_rest["hand_transform"]
	_grip_local = hand_rest.affine_inverse() * grip_world_rest
	_club_socket = socket
	_club_instance = instance
	_follow_weapon_socket()
	set_process(true)
	process_priority = 1000
	return {"ok": true}


func _follow_weapon_socket() -> void:
	if _skeleton == null or _club_socket == null or _profile == null:
		return
	var hand_i: int = _skeleton.find_bone(str(_profile.bones["hand"]))
	if hand_i < 0:
		return
	var hand_world: Transform3D = (
		_skeleton.global_transform * _skeleton.get_bone_global_pose(hand_i)
	)
	hand_world.basis = hand_world.basis.orthonormalized()
	_club_socket.global_transform = hand_world * _grip_local


func _process(_delta: float) -> void:
	_follow_weapon_socket()


func _clear_weapon() -> void:
	if _club_socket != null and is_instance_valid(_club_socket):
		_club_socket.queue_free()
	_club_socket = null
	_club_instance = null


func _club_source_path() -> String:
	if not _club_path_override.is_empty():
		return _club_path_override
	return str(_deps.get("weapon_path", ""))


func _fail(reason: String, error_class: String) -> Dictionary:
	_last_result = {"ok": false, "reason": reason, "error_class": error_class, "side": _side}
	return _last_result


func _force_visible(node: Node) -> void:
	if node is Node3D:
		(node as Node3D).visible = true
	for c in node.get_children():
		_force_visible(c)


func live_hand_frame() -> Dictionary:
	if _profile == null or _skeleton == null:
		return {"ok": false}
	return _profile.compute_frame(_skeleton, false)


## Re-evaluate the hard socket invariants against the CURRENT pose.
func measure_grip_invariants() -> Dictionary:
	if _club_socket == null or _skeleton == null or _profile == null:
		return {"pass": false, "failures": ["no_club"]}
	if _policy == null:
		return {"pass": false, "failures": ["no_policy"]}
	var offset: Node3D = _club_socket.get_node_or_null(SOCKET_OFFSET_NAME) as Node3D
	if offset == null:
		return {"pass": false, "failures": ["no_socket_offset"]}
	return _policy.evaluate_grip_invariants(
		_profile.compute_frame(_skeleton, false),
		offset.global_transform,
		float(_shape.get("radius_mean", 0.01))
	)


func primary_grip_world() -> Vector3:
	if _club_socket == null:
		return Vector3.ZERO
	var offset: Node3D = _club_socket.get_node_or_null(SOCKET_OFFSET_NAME) as Node3D
	if offset == null:
		return _club_socket.global_position
	return offset.global_transform.origin


func humanoid_height() -> float:
	return _humanoid_height


## How the height was measured for the last assemble: landmark bones, the
## declared canonical space, and the named failure when it could not be.
func height_measurement() -> Dictionary:
	return _height_measurement.duplicate(true)
