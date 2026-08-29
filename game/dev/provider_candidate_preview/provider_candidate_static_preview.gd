# Development-only visual comparison: source humanoid at rest vs static export.
#
# THIS SCENE IS THE HUMAN CHECKPOINT. Everything the exporter can prove about the
# candidate is numerical, and numbers cannot answer the question that decides
# whether the candidate is worth a paid provider call: does it LOOK like the same
# character, in a pose an auto-rigger can work with, with hands whose fingers are
# separated. Nothing here claims that. It shows both surfaces under one camera and
# one light so a person can decide.
#
# Run from the Godot editor: open the scene and press F6, or:
#   godot --path game res://assets/prototype/3d/units/warrior/provider_candidate_static_preview.tscn
#
# WHY THE CANDIDATE IS LOADED AT RUNTIME. It lives in an ignored artifact folder
# OUTSIDE the Godot project, on purpose: a generated calibration probe must not sit
# among committed runtime assets where a scene could pick it up by accident. So it
# is parsed here with GLTFDocument instead of through the import pipeline, which
# also means what is shown is the FILE, not an editor-side reimport of it.
extends Node3D

const Bake := preload("res://presentation/assetgen/rest_pose_static_bake.gd")

const SOURCE_SCENE_PATH := "res://assets/prototype/3d/units/warrior/warrior_3d.glb"

## Repo-relative, resolved against the project folder's parent at runtime.
const CANDIDATE_RELATIVE := "../artifacts/assetgen/provider_candidates/warrior_3d__static_unrigged.glb"
const PROVENANCE_RELATIVE := (
	"../artifacts/assetgen/provider_candidates/warrior_3d__static_unrigged.provenance.json"
)
const PLAN_RELATIVE := "../artifacts/assetgen/plans/warrior_3d_static_calibration.plan.json"

const CLASSIFICATION_BANNER := "MORPHOLOGY CALIBRATION ONLY — NOT PRODUCTION BATCH EVIDENCE"

## Side-by-side separation in metres. Wide enough that the two silhouettes do not
## touch at the default framing, narrow enough that both fit one camera.
const SIDE_OFFSET_X := 0.85

const MODE_SIDE_BY_SIDE := 0
const MODE_OVERLAY := 1

## Fixed camera presets, so two runs frame the model identically and a difference
## on screen is a difference in the geometry.
const VIEWS := [
	{"name": "FRONT", "yaw_deg": 0.0, "pitch_deg": -8.0},
	{"name": "THREE-QUARTER", "yaw_deg": 35.0, "pitch_deg": -12.0},
	{"name": "SIDE", "yaw_deg": 90.0, "pitch_deg": -8.0},
	{"name": "BACK", "yaw_deg": 180.0, "pitch_deg": -8.0},
	{"name": "HANDS (close)", "yaw_deg": 20.0, "pitch_deg": -2.0, "distance": 1.1, "height": 1.0},
]

var _original_root: Node3D = null
var _static_root: Node3D = null
var _original_holder: Node3D = null
var _static_holder: Node3D = null
var _camera: Camera3D = null
var _hud: RichTextLabel = null
var _status: Label = null
var _rest_token: Dictionary = {}

var _mode: int = MODE_SIDE_BY_SIDE
var _view_index: int = 0
var _distance := 3.0
var _height := 0.85
var _yaw_offset_deg := 0.0
var _show_original := true
var _show_static := true

var _facts: Dictionary = {}
var _original_measurement: Dictionary = {}


func _ready() -> void:
	_build_environment()
	_facts = _gather_facts()
	_build_original()
	_build_static()
	_build_hud()
	_apply_mode()
	_apply_view()
	_refresh_hud()

	# Headless there is nothing to look at, so the only useful thing the scene can
	# do is state its facts on stdout. Keeps the checkpoint inspectable from a
	# terminal without turning the HUD into a second, drifting implementation.
	if DisplayServer.get_name() == "headless":
		print(_hud.get_parsed_text())
		print(_status.text)
		get_tree().quit(0)


func _exit_tree() -> void:
	# The preview holds the source at rest for as long as it is on screen; the
	# scene it borrowed is put back the way it arrived.
	Bake.release_rest_pose(_rest_token)
	_rest_token = {}


# ----------------------------------------------------------------- scene setup


func _build_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.09, 0.10, 0.12)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.58, 0.65)
	environment.ambient_light_energy = 0.45
	var world_environment := WorldEnvironment.new()
	world_environment.name = "PreviewEnvironment"
	world_environment.environment = environment
	add_child(world_environment)

	# One light for both sides. Two lights would make a shading difference look
	# like a geometry difference.
	var key := DirectionalLight3D.new()
	key.name = "KeyLight"
	key.light_energy = 1.15
	key.shadow_enabled = true
	key.rotation_degrees = Vector3(-42.0, -35.0, 0.0)
	add_child(key)

	var fill := DirectionalLight3D.new()
	fill.name = "FillLight"
	fill.light_energy = 0.35
	fill.shadow_enabled = false
	fill.rotation_degrees = Vector3(-18.0, 145.0, 0.0)
	add_child(fill)

	var ground := MeshInstance3D.new()
	ground.name = "GroundReference"
	var plane := PlaneMesh.new()
	plane.size = Vector2(8.0, 8.0)
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.16, 0.17, 0.19)
	ground.material_override = ground_material
	add_child(ground)

	_camera = Camera3D.new()
	_camera.name = "PreviewCamera"
	_camera.fov = 45.0
	add_child(_camera)


func _build_original() -> void:
	_original_holder = Node3D.new()
	_original_holder.name = "OriginalAtRest"
	add_child(_original_holder)

	if not ResourceLoader.exists(SOURCE_SCENE_PATH):
		push_error("provider_candidate_static_preview: missing source %s" % SOURCE_SCENE_PATH)
		return
	var packed: PackedScene = load(SOURCE_SCENE_PATH) as PackedScene
	if packed == null:
		push_error("provider_candidate_static_preview: %s is not a scene" % SOURCE_SCENE_PATH)
		return
	var instance: Node = packed.instantiate()
	_original_root = instance as Node3D
	_original_holder.add_child(instance)
	# The source is rigged and animated. Rest pose, not frame zero of a clip:
	# frame zero is a pose an animator chose, and it is not what was baked.
	_rest_token = Bake.hold_rest_pose(instance)
	# Evaluated once, only to MEASURE the deformed extent for the HUD. What is
	# displayed on the left remains the live skinned mesh, so the two sides are a
	# rig-versus-static comparison rather than two bakes agreeing with each other.
	var evaluated: Dictionary = Bake.bake(instance, _original_holder)
	if bool(evaluated.get("ok", false)):
		_original_measurement = Bake.measure(evaluated["surfaces"])


func _build_static() -> void:
	_static_holder = Node3D.new()
	_static_holder.name = "StaticUnriggedExport"
	add_child(_static_holder)

	var path := _globalize(CANDIDATE_RELATIVE)
	if not FileAccess.file_exists(path):
		return
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_file(path, state, 0, path.get_base_dir())
	if error != OK:
		push_error("provider_candidate_static_preview: cannot parse candidate (%d)" % error)
		return
	var generated: Node = document.generate_scene(state)
	if generated == null:
		push_error("provider_candidate_static_preview: candidate produced no scene")
		return
	_static_root = generated as Node3D
	_static_holder.add_child(generated)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "PreviewHud"
	add_child(layer)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 12.0
	panel.offset_top = 12.0
	panel.custom_minimum_size = Vector2(560.0, 0.0)
	layer.add_child(panel)

	_hud = RichTextLabel.new()
	_hud.bbcode_enabled = true
	_hud.fit_content = true
	_hud.custom_minimum_size = Vector2(540.0, 0.0)
	_hud.scroll_active = false
	panel.add_child(_hud)

	_status = Label.new()
	_status.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_status.offset_left = 14.0
	_status.offset_top = -34.0
	layer.add_child(_status)


# ---------------------------------------------------------------- facts on disk


## Everything the HUD states, read from the artefacts the export produced. The
## preview measures the scene for itself where it can, and quotes the provenance
## where the fact is about the file rather than about the scene.
func _gather_facts() -> Dictionary:
	var provenance: Dictionary = _read_json(_globalize(PROVENANCE_RELATIVE))
	var plan: Dictionary = _read_json(_globalize(PLAN_RELATIVE))
	return {"provenance": provenance, "plan": plan}


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}


# ------------------------------------------------------------------- measuring


## What the scene tree actually contains on each side. Measured here rather than
## quoted from the provenance: the HUD's "rig present" row must describe the nodes
## in front of the viewer, or it is just repeating a claim.
##
## `evaluated` overrides the measured extent for a SKINNED side, and it has to.
## A skinned mesh's AABB is the undeformed mesh in its own space, while what the
## renderer draws is that mesh pushed through the bone poses and then through the
## node chain — for this asset those disagree by the factor of 100 a Blender
## armature carries, and reading the AABB reported a 1.62 m character as 0.0162 m.
## The extent of a deformed surface comes from evaluating the deformation.
func _describe(root: Node3D, evaluated: Dictionary = {}) -> Dictionary:
	if root == null:
		return {"present": false}
	var meshes: Array = root.find_children("*", "MeshInstance3D", true, false)
	var skeletons: Array = root.find_children("*", "Skeleton3D", true, false)
	var players: Array = root.find_children("*", "AnimationPlayer", true, false)
	var triangles := 0
	var surfaces := 0
	var materials: Array = []
	var textured := 0
	var low := INF
	var high := -INF
	var has_skin := false
	for m in meshes:
		var mi: MeshInstance3D = m as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		if mi.skin != null:
			has_skin = true
		var box: AABB = mi.global_transform * mi.get_aabb()
		low = minf(low, box.position.y)
		high = maxf(high, box.position.y + box.size.y)
		for s in mi.mesh.get_surface_count():
			surfaces += 1
			var arrays: Array = mi.mesh.surface_get_arrays(s)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			triangles += int((indices.size() if indices.size() > 0 else verts.size()) / 3)
			var material: Material = mi.get_active_material(s)
			materials.append("" if material == null else material.resource_name)
			if material is BaseMaterial3D:
				var albedo: Texture2D = (material as BaseMaterial3D).albedo_texture
				if albedo != null:
					textured += 1

	var clips: Array = []
	for p in players:
		clips.append_array(Array((p as AnimationPlayer).get_animation_list()))

	var height := (high - low) if high > low else 0.0
	var ground := low if low < INF else 0.0
	if not evaluated.is_empty():
		height = float(evaluated.get("height_y", height))
		ground = float(evaluated.get("ground_min_y", ground))

	return {
		"present": true,
		"triangles": triangles,
		"surfaces": surfaces,
		"height": height,
		"ground": ground,
		"extent_source": "rest-pose evaluation" if not evaluated.is_empty() else "mesh bounds",
		"rig": not skeletons.is_empty() or has_skin,
		"skeleton_count": skeletons.size(),
		"animations": clips,
		"materials": materials,
		"textured_surfaces": textured,
	}


# ------------------------------------------------------------------------- HUD


func _refresh_hud() -> void:
	var provenance: Dictionary = _facts.get("provenance", {})
	var plan: Dictionary = _facts.get("plan", {})
	var original: Dictionary = _describe(_original_root, _original_measurement)
	var static_side: Dictionary = _describe(_static_root)

	var lines: Array[String] = []
	lines.append("[b]%s[/b]" % CLASSIFICATION_BANNER)
	lines.append("")

	if not static_side.get("present", false):
		lines.append("[color=#ff8080]The static candidate is not on disk.[/color]")
		lines.append("Generate it offline, then reopen this scene:")
		lines.append(
			"  [code]python -m tools.assetgen static-export "
			+ "game/assets/prototype/3d/units/warrior/warrior_3d.glb[/code]"
		)
		lines.append("")

	lines.append(_columns("", "ORIGINAL (rest pose)", "STATIC EXPORT"))
	lines.append(
		_columns(
			"hash",
			_short(str(_section(provenance, "source").get("sha256", ""))),
			_short(str(_section(provenance, "output").get("sha256", ""))),
		)
	)
	lines.append(
		_columns("triangles", _count(original, "triangles"), _count(static_side, "triangles"))
	)
	lines.append(
		_columns("surfaces", _count(original, "surfaces"), _count(static_side, "surfaces"))
	)
	lines.append(
		_columns("height (m)", _metres(original), _metres(static_side))
	)
	lines.append(
		_columns("  measured from", _extent_source(original), _extent_source(static_side))
	)
	lines.append(
		_columns("rig present", _yes_no(original.get("rig", false)), _yes_no(static_side.get("rig", false)))
	)
	lines.append(
		_columns(
			"animations present",
			_yes_no(not (original.get("animations", []) as Array).is_empty()),
			_yes_no(not (static_side.get("animations", []) as Array).is_empty()),
		)
	)
	lines.append(_columns("materials", _materials(original), _materials(static_side)))
	lines.append("")

	lines.append("[b]Automated verdicts (from the export's own provenance)[/b]")
	lines.append("  unrigged structure : %s" % _verdict(provenance, "structural_validation"))
	lines.append("  geometry equivalence: %s" % _verdict(provenance, "geometry_comparison"))
	lines.append("  godot re-import    : %s" % _verdict(provenance, "godot_reimport"))
	lines.append("  deterministic bytes : %s" % _determinism(provenance))
	lines.append("")

	lines.append("[b]Provider preflight[/b]")
	lines.append("  plan executable   : %s" % _plan_executable(plan))
	for row in _confirmations(plan):
		lines.append("  %s" % row)
	lines.append("")
	lines.append(
		"[i]Visual equivalence is NOT asserted by this scene. It is what you are here"
		+ " to judge.[/i]"
	)

	_hud.text = "\n".join(lines)
	_status.text = (
		"[1-5] view: %s   [Tab] layout: %s   [O] original: %s   [P] static: %s   "
		+ "[A/D] orbit   [W/S] zoom   [R] reset"
	) % [
		str(VIEWS[_view_index]["name"]),
		"SIDE BY SIDE" if _mode == MODE_SIDE_BY_SIDE else "OVERLAY",
		"ON" if _show_original else "OFF",
		"ON" if _show_static else "OFF",
	]


func _section(source: Dictionary, key: String) -> Dictionary:
	var value = source.get(key)
	return value if value is Dictionary else {}


func _columns(label: String, left: String, right: String) -> String:
	return "%-20s %-22s %s" % [label, left, right]


func _count(side: Dictionary, key: String) -> String:
	return "-" if not side.get("present", false) else str(side.get(key, 0))


func _metres(side: Dictionary) -> String:
	if not side.get("present", false):
		return "-"
	return "%.4f (ground %+.4f)" % [float(side.get("height", 0.0)), float(side.get("ground", 0.0))]


func _extent_source(side: Dictionary) -> String:
	return "-" if not side.get("present", false) else str(side.get("extent_source", "-"))


func _materials(side: Dictionary) -> String:
	if not side.get("present", false):
		return "-"
	var names: Array = side.get("materials", [])
	return "%d slot(s), %d textured" % [names.size(), int(side.get("textured_surfaces", 0))]


func _yes_no(value: bool) -> String:
	return "YES" if value else "NO"


func _short(digest: String) -> String:
	return "(unknown)" if digest.is_empty() else digest.substr(0, 12)


func _verdict(provenance: Dictionary, key: String) -> String:
	var section = provenance.get(key)
	if not (section is Dictionary):
		return "not available"
	var row: Dictionary = section
	if row.has("performed") and not bool(row.get("performed", false)):
		return "not performed"
	if bool(row.get("passed", false)):
		return "PASS"
	var failed: Array = row.get("failed_checks", [])
	return "FAIL %s" % str(failed)


func _determinism(provenance: Dictionary) -> String:
	var section = provenance.get("determinism")
	if not (section is Dictionary) or not bool((section as Dictionary).get("performed", false)):
		return "not proven in this export"
	var row: Dictionary = section
	if not bool(row.get("byte_identical", false)):
		return "FAIL: contexts produced different bytes"
	return "PASS across %d fresh processes" % int(row.get("process_count", 0))


func _plan_executable(plan: Dictionary) -> String:
	if plan.is_empty():
		return "no plan generated"
	if bool(plan.get("executable", false)):
		return "TRUE"
	return "FALSE (%s)" % str(plan.get("not_executable_because", []))


## The facts no tool in this repository can establish. An answered one names the
## person who answered it, so this panel never reads as though the tooling measured
## something it cannot measure.
func _confirmations(plan: Dictionary) -> Array[String]:
	var blockers: Array = plan.get("not_executable_because", []) if not plan.is_empty() else []
	var observed: Dictionary = {}
	for row in (plan.get("human_confirmations", []) if not plan.is_empty() else []):
		if row is Dictionary:
			observed[str(row.get("check", ""))] = row
	var rows: Array[String] = []
	for name in ["bipedal_humanoid", "hands_and_legs_separated", "visual_equivalence"]:
		if plan.is_empty():
			rows.append("%-24s: no plan to read" % name)
		elif observed.has(name):
			var row: Dictionary = observed[name]
			rows.append(
				"%-24s: WAIVED by %s on %s (human observation)"
				% [name, str(row.get("observer", "?")), str(row.get("observed_on", "?"))]
			)
		elif blockers.has(name):
			rows.append("%-24s: HUMAN CONFIRMATION PENDING" % name)
		else:
			rows.append("%-24s: not asked of this candidate" % name)
	return rows


# -------------------------------------------------------------------- controls


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key: int = (event as InputEventKey).keycode
	match key:
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
			_view_index = mini(key - KEY_1, VIEWS.size() - 1)
			_apply_view()
		KEY_TAB:
			_mode = MODE_OVERLAY if _mode == MODE_SIDE_BY_SIDE else MODE_SIDE_BY_SIDE
			_apply_mode()
		KEY_O:
			_show_original = not _show_original
			_apply_mode()
		KEY_P:
			_show_static = not _show_static
			_apply_mode()
		KEY_A:
			_yaw_offset_deg -= 10.0
			_apply_view()
		KEY_D:
			_yaw_offset_deg += 10.0
			_apply_view()
		KEY_W:
			_distance = maxf(0.6, _distance - 0.2)
			_apply_view()
		KEY_S:
			_distance = minf(8.0, _distance + 0.2)
			_apply_view()
		KEY_R:
			_mode = MODE_SIDE_BY_SIDE
			_view_index = 0
			_yaw_offset_deg = 0.0
			_show_original = true
			_show_static = true
			_apply_mode()
			_apply_view()
		KEY_ESCAPE:
			get_tree().quit()
		_:
			return
	_refresh_hud()


## Both sides always carry the SAME transform apart from the side-by-side offset:
## a scale or rotation applied to one side would be a difference the viewer could
## not distinguish from a difference in the geometry.
func _apply_mode() -> void:
	var offset := SIDE_OFFSET_X if _mode == MODE_SIDE_BY_SIDE else 0.0
	if _original_holder != null:
		_original_holder.transform = Transform3D(Basis.IDENTITY, Vector3(-offset, 0.0, 0.0))
		_original_holder.visible = _show_original
	if _static_holder != null:
		_static_holder.transform = Transform3D(Basis.IDENTITY, Vector3(offset, 0.0, 0.0))
		_static_holder.visible = _show_static


func _apply_view() -> void:
	if _camera == null:
		return
	var view: Dictionary = VIEWS[_view_index]
	var distance := float(view.get("distance", _distance))
	var height := float(view.get("height", _height))
	var yaw := deg_to_rad(float(view["yaw_deg"]) + _yaw_offset_deg)
	var pitch := deg_to_rad(float(view["pitch_deg"]))
	var target := Vector3(0.0, height, 0.0)
	var direction := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	_camera.transform = Transform3D(Basis.IDENTITY, target - direction * distance)
	_camera.look_at(target, Vector3.UP)


func _globalize(relative: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join(relative).simplify_path()
