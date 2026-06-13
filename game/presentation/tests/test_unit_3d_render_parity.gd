# Headless: Niclas + Bronze-Armed Warrior share real-3D composite AA/filter/scale path with Warrior/Settler.
extends SceneTree

const Experiment = preload("res://presentation/warrior_3d_unit_experiment.gd")
const MapLayerScript = preload("res://presentation/map_presentation_3d_layer.gd")
const UnitWorldScript = preload("res://presentation/unit_3d_world_view.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const MapCameraScript = preload("res://presentation/map_camera.gd")
const MapPlaneProjectionScript = preload("res://presentation/map_plane_projection.gd")

const MAP_LAYER_ORIGIN: Vector2 = Vector2(400.0, 428.0)
const UNIT_TYPES: Array[String] = ["warrior", "settler", "niclas", "bronze_armed_warrior"]
const WARRIOR_GLB_IMPORT: String = (
	"res://assets/prototype/3d/units/warrior/warrior_3d_animations.glb.import"
)
const WARRIOR_TEX_IMPORT: String = (
	"res://assets/prototype/3d/units/warrior/warrior_3d_animations_texture_0.png.import"
)

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	OS.set_environment(Experiment.ENV_FLAG, "1")
	OS.set_environment(Experiment.ENV_REAL_3D_UNITS, "1")
	call_deferred("_run")


func _run() -> void:
	_test_routing_flags()
	_test_import_metadata_parity()
	await _test_composite_render_path()
	if _failures > 0:
		push_error("test_unit_3d_render_parity: %d failures / %d checks" % [_failures, _checks])
		quit(1)
	print("test_unit_3d_render_parity: %d checks, all ok" % _checks)
	quit(0)


func _test_routing_flags() -> void:
	for type_id in UNIT_TYPES:
		_check(
			Experiment.uses_real_3d_composite_for_type(type_id),
			"%s uses real 3D composite when flags on" % type_id,
		)
		_check(
			not Experiment.animated_scene_path_for_type(type_id).is_empty(),
			"%s has GLB scene path" % type_id,
		)


func _test_import_metadata_parity() -> void:
	var warrior_glb: String = _read_text(WARRIOR_GLB_IMPORT)
	var warrior_tex: String = _read_text(WARRIOR_TEX_IMPORT)
	var asset_pairs: Array = [
		[
			"niclas",
			"res://assets/prototype/3d/units/niclas/niclas_3d.glb.import",
			"res://assets/prototype/3d/units/niclas/niclas_3d_texture_0.png.import",
		],
		[
			"bronze_armed_warrior",
			"res://assets/prototype/3d/units/bronze_armed_warrior/bronze_armed_warrior_3d.glb.import",
			(
				"res://assets/prototype/3d/units/bronze_armed_warrior/"
				+ "bronze_armed_warrior_3d_texture_0.png.import"
			),
		],
	]
	for pair in asset_pairs:
		var label: String = str(pair[0])
		var glb_text: String = _read_text(str(pair[1]))
		var tex_text: String = _read_text(str(pair[2]))
		_check(glb_text.contains("meshes/generate_lods=true"), "%s GLB LOD enabled" % label)
		_check(
			glb_text.contains("meshes/force_disable_compression=false"),
			"%s GLB mesh compression not forced off" % label,
		)
		_check(tex_text.contains("mipmaps/generate=true"), "%s albedo mipmaps enabled" % label)
		_check(
			tex_text.contains("compress/mode=2") == warrior_tex.contains("compress/mode=2"),
			"%s texture VRAM compress mode matches warrior" % label,
		)
		_check(
			tex_text.contains("vram_texture: true") == warrior_tex.contains("vram_texture: true"),
			"%s vram_texture flag matches warrior" % label,
		)
		_check(
			tex_text.contains("detect_3d/compress_to=0")
				== warrior_tex.contains("detect_3d/compress_to=0"),
			"%s detect_3d/compress_to matches warrior" % label,
		)
		_check(
			glb_text.contains("gltf/embedded_image_handling=1")
				== warrior_glb.contains("gltf/embedded_image_handling=1"),
			"%s embedded image handling matches warrior" % label,
		)
	_test_material_override_parity()


func _test_material_override_parity() -> void:
	var unit_world = UnitWorldScript.new()
	for type_id in UNIT_TYPES:
		var scene_path: String = Experiment.animated_scene_path_for_type(type_id)
		var packed: PackedScene = load(scene_path) as PackedScene
		_check(packed != null, "%s GLB loads for material audit" % type_id)
		if packed == null:
			continue
		var model: Node = packed.instantiate()
		_check(model != null, "%s GLB instantiates" % type_id)
		if model == null:
			continue
		unit_world._apply_material_override(model)
		var mats: Array = _collect_standard_materials(model)
		_check(mats.size() > 0, "%s has StandardMaterial3D surfaces" % type_id)
		for mat in mats:
			var sm: StandardMaterial3D = mat as StandardMaterial3D
			_check(sm.albedo_texture != null, "%s override keeps albedo texture" % type_id)
			_check(
				sm.texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS,
				"%s override keeps linear+mipmap filter" % type_id,
			)
			_check(
				absf(sm.metallic - UnitWorldScript.UNIT_MAT_OVERRIDE_METALLIC) < 0.001,
				"%s matte metallic override" % type_id,
			)
		model.free()
	unit_world.free()


func _test_composite_render_path() -> void:
	var root := Node.new()
	get_root().add_child(root)
	var layout = HexLayoutScript.new()
	var scenario = ScenarioScript.with_debug_character_units(
		ScenarioScript.make_tiny_test_scenario()
	)
	var layer = MapLayerScript.new()
	root.add_child(layer)
	layer.real_3d_units_enabled = true
	layer.layout = layout
	layer.scenario = scenario
	layer.map_layer_origin = MAP_LAYER_ORIGIN
	var projection = MapPlaneProjectionScript.new()
	projection.vanishing_pres = (get_root().get_visible_rect().size * 0.5) - MAP_LAYER_ORIGIN
	var map_camera = MapCameraScript.new()
	map_camera.projection = projection
	layer.map_camera = map_camera
	await process_frame
	layer.sync_from_scenario()
	layer.prepare_for_draw()
	await process_frame
	var unit_world = layer._unit_world_view
	_check(unit_world != null, "Unit3DWorldView under WorldPanRoot")
	_check(
		layer._world_pan_root.get_node_or_null("Unit3DWorldView") == unit_world,
		"Unit3DWorldView is child of WorldPanRoot in shared SubViewport",
	)
	_check(
		layer._world_pan_root.get_node_or_null("DebugCharacter3DTestView") == null,
		"no DebugCharacter3DTestView duplicate viewport path",
	)
	var subvp: SubViewport = layer._viewport
	_check(subvp != null, "shared composite SubViewport exists")
	if subvp != null:
		_check(subvp.msaa_3d == Viewport.MSAA_2X, "composite msaa_3d=MSAA_2X")
		_check(
			subvp.screen_space_aa == Viewport.SCREEN_SPACE_AA_FXAA,
			"composite screen_space_aa=FXAA",
		)
		_check(subvp.get_parent().stretch == false, "composite container stretch=false")
		_check(subvp.size.x > 0 and subvp.size.y > 0, "composite 1:1 subviewport size assigned")
	var unit_ids: Dictionary = {
		"settler": 1,
		"warrior": 2,
		"niclas": ScenarioScript.DEBUG_NICLAS_UNIT_ID,
		"bronze_armed_warrior": ScenarioScript.DEBUG_BRONZE_UNIT_ID,
	}
	for type_id in UNIT_TYPES:
		var unit_id: int = int(unit_ids[type_id])
		_check(unit_world.has_ready_unit_instance(unit_id), "%s instance in Unit3DWorldView" % type_id)
		_check(
			not layer.should_auto_blit_for_unit(unit_id, type_id),
			"%s skips per-unit blit when composite ready" % type_id,
		)
		var inst: Node3D = unit_world._instance_by_unit_id.get(unit_id) as Node3D
		if inst == null:
			continue
		var world_2d: Vector2 = layout.hex_to_world(
			int(_unit_at(scenario, unit_id).position.q),
			int(_unit_at(scenario, unit_id).position.r),
		)
		var expected_scale: float = UnitWorldScript.effective_scale_at_world(
			map_camera,
			unit_world._base_scale_for_type(type_id),
			unit_world._reference_world_y_for_type(type_id),
			world_2d,
		)
		_check(
			absf(inst.scale.x - expected_scale) < 0.05,
			"%s uses effective_scale_at_world (%.3f)" % [type_id, expected_scale],
		)
		_check(
			inst.get_viewport() == subvp,
			"%s renders in shared composite SubViewport" % type_id,
		)
	root.free()


func _collect_standard_materials(model: Node) -> Array:
	var out: Array = []
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_inst: MeshInstance3D = node as MeshInstance3D
		var mesh: Mesh = mesh_inst.mesh
		if mesh == null:
			continue
		var si: int = 0
		while si < mesh.get_surface_count():
			var mat: Material = mesh_inst.get_surface_override_material(si)
			if mat is StandardMaterial3D:
				out.append(mat)
			si += 1
	return out


func _unit_at(scenario, unit_id: int):
	var ulist: Array = scenario.units()
	var i: int = 0
	while i < ulist.size():
		if int(ulist[i].id) == unit_id:
			return ulist[i]
		i += 1
	return null


func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("ok: %s" % msg)
	else:
		_failures += 1
		push_error("FAIL: %s" % msg)
