# power_grip_1h_v1 — the ONE implemented grip interaction policy.
#
# A policy owns everything that is specific to how one interaction maps a
# hand onto a rigid object: the socket construction, the hard anatomical
# preconditions and the semantic acceptance contract. It owns no skeleton
# family data, no per-unit fixture data and no asset paths.
#
# Adding a future policy (two-handed support, shield, bow, crossbow,
# firearm, sling) means adding a sibling file that exposes this same
# surface and registering its id — never editing the solver flow, the
# assembler or this file.
#
# Required policy surface:
#   POLICY_ID: String
#   REQUIRES_SECONDARY: bool
#   build_grip_socket_world(frame, radius_mean) -> Transform3D
#   evaluate_grip_invariants(frame, socket_world, radius_mean) -> Dictionary
extends RefCounted

const POLICY_ID := "power_grip_1h_v1"
## Bumped whenever a number below changes. A certified fixture records the
## policy version it was accepted under (A2.12), so retuning an invariant
## invalidates every certificate rather than silently reinterpreting it.
## 1 = the accepted A2.7 socket mapping and hard preconditions, unchanged.
const POLICY_VERSION := "1"
const REQUIRES_SECONDARY := false

## Socket mapping (canonical power grip). These are THIS policy's numbers.
const KAPPA_DEG := 12.0
const VOLAR_OFFSET_RADII := 1.2
const DISTAL_SHIFT_HAND := 0.15

## Hard anatomical preconditions (dimensionless).
const DOT_DA_MIN := 0.90
const DOT_DL_MAX := 0.35
const DOT_DV_MAX := 0.25
const VOLAR_OFFSET_MIN_RADII := 0.4
const VOLAR_OFFSET_MAX_RADII := 2.2
const CENTRE_ALONG_L_MAX_HAND := 0.5
const CENTRE_ALONG_A_MAX_BREADTH := 0.6
const MCP_SPREAD_MIN_BREADTH := 0.6
const HINGE_DOT_MIN := 0.80
const STATION_REACH_MIN := 0.35
const STATION_REACH_MAX := 0.95

## Semantic contract (acceptance, not solver knobs).
const REQUIRES_FOUR_FINGERS := true
const THUMB_MUST_TOUCH_INDEX := false
const THUMB_REQUIRED := true
const NAIL_FACES_OUT := true
const PAD_FACES_IN := true
const MEASURE_ACHIEVED_SKIN := true
const SIDE_INVARIANT := true


static func build_grip_socket_world(frame: Dictionary, radius_mean: float) -> Transform3D:
	var a: Vector3 = frame["radial"] if frame.has("radial") else frame["across"]
	var l: Vector3 = frame["longitudinal"]
	var v: Vector3 = frame["volar"]
	var d: Vector3 = (a + tan(deg_to_rad(KAPPA_DEG)) * l).normalized()
	var z: Vector3 = (v - d * v.dot(d)).normalized()
	var x: Vector3 = d.cross(z)
	var c: Vector3 = (
		(frame["palm_centre"] as Vector3)
		+ v * (VOLAR_OFFSET_RADII * radius_mean)
		+ l * (DISTAL_SHIFT_HAND * float(frame["hand_length"]))
	)
	return Transform3D(Basis(x, d, z), c)


static func evaluate_grip_invariants(
	frame: Dictionary, socket_world: Transform3D, radius_mean: float
) -> Dictionary:
	var failures: Array[String] = []
	if not bool(frame.get("ok", false)):
		return {"pass": false, "failures": ["hand_frame_invalid"]}
	var a: Vector3 = frame["radial"] if frame.has("radial") else frame["across"]
	var l: Vector3 = frame["longitudinal"]
	var v: Vector3 = frame["volar"]
	var p: Vector3 = frame["palm_centre"]
	var hand_length: float = float(frame["hand_length"])
	var breadth: float = float(frame["knuckle_breadth"])
	var r: float = maxf(radius_mean, 1e-9)
	var det_frame: float = float(frame.get("det", 0.0))
	if det_frame < 0.99:
		failures.append("palm_basis_det")
	var det_socket: float = socket_world.basis.determinant()
	if det_socket < 0.99:
		failures.append("socket_det")
	var d: Vector3 = socket_world.basis.y.normalized()
	var c: Vector3 = socket_world.origin
	var dot_da: float = d.dot(a)
	var dot_dl: float = d.dot(l)
	var dot_dv: float = d.dot(v)
	if absf(dot_da) < DOT_DA_MIN:
		failures.append("shaft_not_transverse")
	if dot_da <= 0.0:
		failures.append("head_side_not_radial")
	if absf(dot_dl) > DOT_DL_MAX:
		failures.append("shaft_along_fingers")
	if absf(dot_dv) > DOT_DV_MAX:
		failures.append("shaft_through_palm")
	var offset_vec: Vector3 = c - p
	var volar_offset: float = offset_vec.dot(v)
	if volar_offset < VOLAR_OFFSET_MIN_RADII * r or volar_offset > VOLAR_OFFSET_MAX_RADII * r:
		failures.append("volar_offset_out_of_band")
	if absf(offset_vec.dot(l)) > CENTRE_ALONG_L_MAX_HAND * hand_length:
		failures.append("centre_outside_hand_longitudinal")
	if absf(offset_vec.dot(a)) > CENTRE_ALONG_A_MAX_BREADTH * breadth:
		failures.append("centre_outside_hand_transverse")
	var mcp: Dictionary = frame["mcp"]
	var hinge: Dictionary = frame["hinge"]
	var chain_length: Dictionary = frame["chain_length"]
	var projections := {}
	var prev := INF
	var monotonic := true
	for finger in ["index", "middle", "ring", "pinky"]:
		var proj: float = (mcp[finger] as Vector3).dot(d)
		projections[finger] = proj
		if proj >= prev:
			monotonic = false
		prev = proj
	if not monotonic:
		failures.append("mcp_projection_not_monotonic")
	var spread: float = float(projections["index"]) - float(projections["pinky"])
	if spread < MCP_SPREAD_MIN_BREADTH * breadth:
		failures.append("mcp_projection_spread")
	var hinge_dots := {}
	var station_reach := {}
	for finger in ["index", "middle", "ring", "pinky"]:
		var hd: float = absf(d.dot(hinge[finger] as Vector3))
		hinge_dots[finger] = hd
		if hd < HINGE_DOT_MIN:
			failures.append("hinge_axis_%s" % finger)
		var w: Vector3 = (mcp[finger] as Vector3) - c
		var radial: Vector3 = w - d * w.dot(d)
		var reach: float = radial.length() / maxf(float(chain_length[finger]), 1e-9)
		station_reach[finger] = reach
		if reach < STATION_REACH_MIN or reach > STATION_REACH_MAX:
			failures.append("station_reach_%s" % finger)
	return {
		"pass": failures.is_empty(),
		"failures": failures,
		"policy": POLICY_ID,
		"det_frame": det_frame,
		"det_socket": det_socket,
		"dot_da": dot_da,
		"dot_dl": dot_dl,
		"dot_dv": dot_dv,
		"volar_offset": volar_offset,
		"volar_offset_radii": volar_offset / r,
		"centre_along_l": offset_vec.dot(l),
		"centre_along_a": offset_vec.dot(a),
		"mcp_projections": projections,
		"mcp_spread": spread,
		"mcp_spread_over_breadth": spread / maxf(breadth, 1e-9),
		"hinge_dots": hinge_dots,
		"station_reach": station_reach,
		"radius_mean": r,
		"hand_length": hand_length,
		"knuckle_breadth": breadth,
	}
