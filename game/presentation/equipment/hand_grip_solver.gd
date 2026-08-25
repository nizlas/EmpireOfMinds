# Deterministic hand-grip attach step consumed by the assembler. The grip
# engine is INJECTED (A2.9): the solver instantiates the engine script it is
# given, injects the compiled hand profile, applies the pose and runs the
# wrap / contour / surface-truth gates fail-closed. It never preloads an
# engine, a family, a fixture or any asset.
extends RefCounted

const GRIP_NODE_NAME := "PowerGrip1h"


static func attach(
	skeleton: Skeleton3D,
	character: Node,
	club: Node3D,
	shape: Dictionary,
	frame_pose: Dictionary,
	profile,
	engine_script: Script
) -> Dictionary:
	if skeleton == null or character == null or club == null:
		return {"ok": false, "reason": "not_ready"}
	if engine_script == null:
		return {
			"ok": false,
			"reason": "engine_required",
			"error_class": "ENGINE_REQUIRED",
		}
	var existing = skeleton.get_node_or_null(GRIP_NODE_NAME)
	var grip: SkeletonModifier3D
	if existing != null:
		grip = existing as SkeletonModifier3D
	else:
		grip = engine_script.new()
		grip.name = GRIP_NODE_NAME
		skeleton.add_child(grip)
	if grip.has_method("set_hand_profile"):
		grip.set_hand_profile(profile)
	var cfg: Dictionary = (grip as Object).configure(character, club, shape, frame_pose)
	if not bool(cfg.get("ok", false)):
		return cfg
	(grip as Object).set_grip_enabled(true)
	(grip as Object).apply_now()
	var diag: Dictionary = (grip as Object).last_diagnostics()
	var tw_gate: Dictionary = diag.get("thumb_wrap_gate", {})
	if not bool(tw_gate.get("pass", false)):
		return {
			"ok": false,
			"reason": "thumb_opposition_gate_failed",
			"error_class": "THUMB_OPPOSITION_GATE_FAILED",
			"thumb_wrap": diag.get("thumb_wrap", {}),
			"thumb_wrap_failures": tw_gate.get("failures", []),
			"grip": grip,
		}
	var contour_gate: Dictionary = (grip as Object).run_contour_gate(character)
	if not bool(contour_gate.get("pass", false)):
		return {
			"ok": false,
			"reason": "thumb_contour_gate_failed",
			"error_class": "THUMB_CONTOUR_GATE_FAILED",
			"thumb_contour": (grip as Object).last_contour(),
			"thumb_contour_failures": contour_gate.get("failures", []),
			"grip": grip,
		}
	var surface_gate: Dictionary = (grip as Object).run_surface_truth_gate()
	if not bool(surface_gate.get("pass", false)):
		return {
			"ok": false,
			"reason": "thumb_surface_truth_gate_failed",
			"error_class": "THUMB_SURFACE_TRUTH_GATE_FAILED",
			"thumb_surface": (grip as Object).last_surface(),
			"thumb_surface_failures": surface_gate.get("failures", []),
			"grip": grip,
		}
	cfg["grip"] = grip
	cfg["ok"] = true
	return cfg
