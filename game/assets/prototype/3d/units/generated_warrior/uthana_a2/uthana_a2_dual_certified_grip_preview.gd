# Development preview for the A2.13b VISUAL gate: the SAME humanoid, delivered
# twice, gripping the same club through the same generic certified path.
#
# WHY A SECOND PREVIEW EXISTS. The A2 walking preview shows one delivery and was
# the scene the accepted A2.7 grip was eyeballed in. A2.13b's claim is that the
# compiled thumb surface is a property of the humanoid rather than of the
# delivery, and that claim cannot be inspected in a scene that can only show one
# delivery. This scene runs BOTH through the real certification authority and
# lets F6 flip between them with an unchanged camera, club and pose, so the two
# hands can be compared directly rather than from memory.
#
# WHAT IT IS NOT. It is not a gate and it is not part of any acceptance chain. It
# also uses NO authored oracle fixture: each side shown here is the certificate
# the authority minted from that delivery's own geometry seconds earlier, so a
# hand that looks right here looks right because the pipeline produced it.
#
# CONTROLS
#   A   switch delivery (re-runs the whole chain on the other one)
#   C   switch view: grip close-up / body overview
#
# BOTH VIEWS SHOW THE CLUB, DELIBERATELY. Neither view hides the weapon, so a
# frame without a club in it means the attachment failed and not that the scene
# chose to hide it. That distinction matters here: the overview camera used to
# stand on a fixed side of the scene, which put the torso between it and the
# gripped club, and an occluded club is indistinguishable from a missing one.
# Both cameras are now placed relative to the club the assembler actually built,
# so both stand on the weapon's side of the body.
extends Node3D

const Authority = preload(
	"res://presentation/equipment/hand_fixture_certification_authority.gd"
)
const CompiledFixture = preload("res://presentation/equipment/compiled_hand_fixture.gd")
const Skinning = preload("res://presentation/equipment/skinned_mesh_geometry.gd")
const Native = preload(
	"res://assets/prototype/3d/units/generated_warrior/uthana_a1/uthana_a1_native_import.gd"
)

const CLUB_GLB := "res://assets/prototype/3d/equipment/wooden_club/wooden_club.glb"
const POLICY_ID := "power_grip_1h_v1"
const RAW_GLB := (
	"res://assets/prototype/3d/units/generated_warrior/uthana_a0"
	+ "/generated_warrior_3d_uthana_rigged.glb"
)

## Both deliveries of the one humanoid. `id` is a label for the HUD only.
const DELIVERIES: Array[Dictionary] = [
	{"id": "a0 (raw delivery)", "glb": RAW_GLB},
	{"id": "a1 (retargeted delivery)", "glb": ""},
]

## The two framings `C` cycles, in order. Both are declared to show the weapon.
const VIEWS: Array[Dictionary] = [
	{"id": "grip close-up", "shows_weapon": true},
	{"id": "body overview", "shows_weapon": true},
]

## Shown when the achieved-geometry step produced no reading at all. It is not a
## patch name and can never be mistaken for one: an absent measurement must look
## absent rather than borrow the value the gate expects.
const NO_ACHIEVED_READING := "unavailable (no achieved-geometry reading)"

var _index := 0
var _view := 0
var _stage: Node3D = null
var _body_camera: Camera3D = null
var _hand_camera: Camera3D = null
var _hud: Label = null
var _report: Dictionary = {}
var _busy := false


func _ready() -> void:
	_build_lighting()
	_build_ground()
	_build_hud()
	await _show(_index)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not (event as InputEventKey).pressed:
		return
	match (event as InputEventKey).keycode:
		KEY_A:
			if not _busy:
				await _show((_index + 1) % DELIVERIES.size())
		KEY_C:
			select_view(_view + 1)


func _delivery_path(i: int) -> String:
	var glb: String = str((DELIVERIES[i] as Dictionary).get("glb", ""))
	# The retargeted delivery's path is owned by its own import module.
	return glb if not glb.is_empty() else Native.UTHANA_TARGET_GLB


## Run the REAL acceptance chain and keep the nodes it built. Nothing here
## assembles the club or poses the hand: the authority's own assembler step does,
## exactly as it does during ingestion.
func _show(i: int) -> void:
	# One chain at a time: a second request must not free the nodes the first is
	# still measuring.
	while _busy:
		await get_tree().process_frame
	_busy = true
	_index = i
	if _stage != null:
		_stage.queue_free()
		_stage = null
		await get_tree().process_frame
	_stage = Node3D.new()
	_stage.name = "Delivery"
	_stage.scale = Vector3.ONE * Native.PREVIEW_MODEL_SCALE
	_stage.rotation = Vector3(0.0, Native.PREVIEW_MODEL_YAW, 0.0)
	add_child(_stage)
	var authority := Authority.new()
	_report = await authority.run({
		"host": _stage,
		"tree": get_tree(),
		"glb": _delivery_path(i),
		"staging_path": "user://a213b_preview_evidence.tres",
		"sides": ["right"],
		"required_sides": ["right"],
		"policy_id": POLICY_ID,
		"weapon_path": CLUB_GLB,
		"asset_id": "a213b_preview",
		"keep_nodes": true,
	})
	_frame_views()
	select_view(_view)
	_refresh_hud()
	_busy = false


## Same framing for both deliveries, derived from the assembled club and the
## resolved skeleton rather than from per-asset constants, so the two hands are
## compared at the same size and both cameras stand on the club's side of the
## body however the delivery happens to be oriented or scaled.
func _frame_views() -> void:
	if _body_camera == null or _hand_camera == null:
		return
	var target := Vector3(0.0, 0.28, 0.05)
	var asm = _report.get("assembler", null)
	if asm != null and asm.has_method("club_socket"):
		var socket: Node3D = asm.club_socket()
		if socket != null:
			target = socket.global_transform.origin
	# The close-up framing is the one the A2.13b visual check was accepted in and
	# is left exactly as it was.
	_hand_camera.look_at_from_position(
		target + Vector3(0.12, 0.06, 0.14), target, Vector3.UP
	)
	var body: AABB = _skeleton_bounds()
	var centre: Vector3 = body.get_center()
	var span: float = maxf(body.size.y, 0.001)
	# Outward = from the body's own vertical axis towards the gripped club, so the
	# overview camera can never end up with the torso in the way.
	var outward := Vector3(target.x - centre.x, 0.0, target.z - centre.z)
	if outward.length_squared() < 1e-12:
		outward = Vector3.BACK
	outward = outward.normalized()
	_body_camera.look_at_from_position(
		centre + outward * (span * 1.5) + Vector3.UP * (span * 0.18),
		centre.lerp(target, 0.35),
		Vector3.UP
	)


## The humanoid's world extent, taken from the posed bones of the skeleton the
## authority resolved. Skinned mesh AABBs are authored in mesh space and do not
## report the deformed extent, so the bones are the honest measure here.
func _skeleton_bounds() -> AABB:
	var skeleton: Skeleton3D = _report.get("skeleton", null)
	if skeleton == null or skeleton.get_bone_count() <= 0:
		return AABB(Vector3.ZERO, Vector3.ONE)
	var out := AABB()
	for i in skeleton.get_bone_count():
		var p: Vector3 = (skeleton.global_transform * skeleton.get_bone_global_pose(i)).origin
		out = AABB(p, Vector3.ZERO) if i == 0 else out.expand(p)
	return out


## Activate one of `VIEWS`. Public so the same entry point serves `C` and a
## headless check of both framings.
func select_view(i: int) -> void:
	_view = i % VIEWS.size()
	if _hand_camera == null or _body_camera == null:
		return
	_hand_camera.current = _view == 0
	_body_camera.current = _view != 0
	_refresh_hud()


## The achieved `closest_patch`, read out of the certification authority's own
## record of the achieved-geometry step: the value the grip engine measured and
## the acceptance gate compared, carried through the report rather than measured
## again here. Empty when the run never reached that step.
static func achieved_closest_patch(report: Dictionary) -> String:
	var truth: Dictionary = (
		(report.get("diagnostics", {}) as Dictionary).get("grip_ground_truth", {})
	)
	return str(truth.get("closest_patch", ""))


func _refresh_hud() -> void:
	if _hud == null:
		return
	var ok: bool = bool(_report.get("ok", false))
	var diag: Dictionary = _report.get("diagnostics", {})
	var side: Dictionary = (diag.get("sides", {}) as Dictionary).get("right", {})
	var metrics: Dictionary = diag.get("gate_metrics", {})
	var achieved: Dictionary = metrics.get("achieved", {})
	var limits: Dictionary = metrics.get("limits", {})
	var owner_id := "none"
	var cert: Dictionary = _report.get("certification", {})
	if not cert.is_empty():
		owner_id = "%s %s" % [
			str(cert.get("compiler_version", "?")),
			str(cert.get("acceptance_authority_id", "?")),
		]
	var achieved_patch: String = achieved_closest_patch(_report)
	var lines: Array[String] = [
		"A2.13b DUAL CERTIFIED GRIP PREVIEW   [A] delivery   [C] view",
		"delivery      : %s" % str((DELIVERIES[_index] as Dictionary).get("id", "?")),
		"view          : %s (club shown in both views)" % str(
			(VIEWS[_view] as Dictionary).get("id", "?")
		),
		"certified     : %s" % ("YES" if ok else "NO"),
		"fixture owner : %s" % owner_id,
		"gate verdict  : %s" % (
			"ACCEPTED" if ok
			else "REFUSED %s at %s" % [
				str(_report.get("error_class", "?")), str(_report.get("stage", "?"))
			]
		),
		"nail / pad    : %d / %d triangles" % [
			_patch_count(side, "nail_tris"), _patch_count(side, "pad_tris"),
		],
		"approach      : axial %.4f (limit %.2f)   radial %.4f (limit %.2f)" % [
			float(achieved.get("approach_axial_fraction", NAN)),
			float(limits.get("THUMB_APPROACH_AXIAL_FRAC_MAX", NAN)),
			float(achieved.get("approach_radial_radii", NAN)),
			float(limits.get("THUMB_APPROACH_RADIAL_MAX_RADII", NAN)),
		],
		"closest patch : %s" % (
			achieved_patch if not achieved_patch.is_empty() else NO_ACHIEVED_READING
		),
		"club          : %s" % _club_state(),
		"no authored oracle fixture is loaded by this scene",
	]
	_hud.text = "\n".join(lines)


## Whether the club the assembler built is attached AND actually in frame, said
## plainly. Neither view hides the weapon on purpose, so "not in frame" is a
## defect report and never a design note.
func _club_state() -> String:
	var d: Dictionary = view_diagnostics()
	if not bool(d.get("attached", false)):
		return "NOT ATTACHED by the assembler"
	if not bool(d.get("visible_meshes", false)):
		return "attached but its meshes are hidden - this is a defect"
	if not bool(d.get("in_frame", false)):
		return "attached but OUT OF FRAME in this view - this is a defect"
	return "attached and in frame (%.3f m from camera)" % float(d.get("camera_distance", 0.0))


## What the active view is actually showing, for the HUD and for a headless check
## that neither framing loses the weapon. Reports geometry, never a verdict about
## how the grip looks.
func view_diagnostics() -> Dictionary:
	var out := {
		"view": str((VIEWS[_view] as Dictionary).get("id", "?")),
		"view_index": _view,
		"declares_weapon_shown": bool((VIEWS[_view] as Dictionary).get("shows_weapon", false)),
		"attached": false,
		"visible_meshes": false,
		"in_frame": false,
		"camera_distance": 0.0,
		"body_axis_distance": 0.0,
		"nearer_than_body_axis": false,
	}
	var asm = _report.get("assembler", null)
	if asm == null or not asm.has_method("has_club") or not bool(asm.has_club()):
		return out
	out["attached"] = true
	var meshes: Array = _visual_meshes(asm.club_instance())
	if meshes.is_empty():
		return out
	var bounds := AABB()
	var shown := false
	for i in meshes.size():
		var mi: VisualInstance3D = meshes[i]
		var world: AABB = mi.global_transform * mi.get_aabb()
		bounds = world if i == 0 else bounds.merge(world)
		if mi.is_visible_in_tree():
			shown = true
	out["visible_meshes"] = shown
	out["club_centre"] = bounds.get_center()
	var cam: Camera3D = _hand_camera if _view == 0 else _body_camera
	if cam == null:
		return out
	var centre: Vector3 = bounds.get_center()
	var view_space: Vector3 = cam.global_transform.affine_inverse() * centre
	out["camera_distance"] = view_space.length()
	# In frame = in front of the near plane and inside the projected rect. The
	# viewport size differs between a window and a headless run, so the test is
	# on the normalised position rather than on pixels.
	var rect: Vector2 = cam.get_viewport().get_visible_rect().size
	var on_screen := false
	if not cam.is_position_behind(centre) and rect.x > 0.0 and rect.y > 0.0:
		var p: Vector2 = cam.unproject_position(centre)
		on_screen = p.x >= 0.0 and p.y >= 0.0 and p.x <= rect.x and p.y <= rect.y
	out["in_frame"] = on_screen
	# Occlusion proxy: the club must be nearer to the camera than the body's own
	# vertical axis is, or the torso is between the two and the club is hidden.
	var axis: Vector3 = _skeleton_bounds().get_center()
	axis.y = centre.y
	out["body_axis_distance"] = (cam.global_transform.affine_inverse() * axis).length()
	out["nearer_than_body_axis"] = out["camera_distance"] < out["body_axis_distance"]
	return out


func _visual_meshes(node) -> Array:
	var out: Array = []
	if node == null or not (node is Node):
		return out
	if node is VisualInstance3D:
		out.append(node)
	for c in (node as Node).get_children():
		out.append_array(_visual_meshes(c))
	return out


## The per-side record reports a count; older shapes carried the triangle list.
func _patch_count(side: Dictionary, key: String) -> int:
	var v = side.get(key, 0)
	return (v as Array).size() if v is Array else int(v)


func _build_lighting() -> void:
	var light := DirectionalLight3D.new()
	light.name = "KeyLight"
	light.rotation_degrees = Vector3(-40.0, 35.0, 0.0)
	light.shadow_enabled = true
	add_child(light)
	var fill := DirectionalLight3D.new()
	fill.name = "FillLight"
	fill.rotation_degrees = Vector3(-20.0, -50.0, 0.0)
	fill.light_energy = 0.35
	add_child(fill)
	_body_camera = Camera3D.new()
	_body_camera.name = "BodyCamera"
	add_child(_body_camera)
	_body_camera.current = false
	_hand_camera = Camera3D.new()
	_hand_camera.name = "HandCloseupCamera"
	add_child(_hand_camera)
	_hand_camera.current = true


func _build_ground() -> void:
	var ground := MeshInstance3D.new()
	ground.name = "GroundPlane"
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.6, 1.6)
	ground.mesh = plane
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.22, 0.24, 0.26)
	ground.material_override = gmat
	add_child(ground)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "A213bPreviewHud"
	layer.layer = 100
	add_child(layer)
	_hud = Label.new()
	_hud.name = "Status"
	_hud.position = Vector2(12, 12)
	_hud.add_theme_font_size_override("font_size", 16)
	_hud.modulate = Color(0.92, 0.95, 0.85, 1.0)
	layer.add_child(_hud)


## Test hook: the HUD text a headless check can assert on without a window.
func hud_text() -> String:
	return _hud.text if _hud != null else ""


func last_report() -> Dictionary:
	return _report
