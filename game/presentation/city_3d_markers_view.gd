# Experimental SubViewport-based 3D city markers (ancient_village) on the map plane (presentation only).
class_name City3DMarkersView
extends Node2D

const Warrior3DExperimentScript = preload("res://presentation/warrior_3d_unit_experiment.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const MapCameraScript = preload("res://presentation/map_camera.gd")

const VIEWPORT_PX_MIN: int = 128
const VIEWPORT_PX_MAX: int = 768
const VIEWPORT_SIZE_QUANTIZE: int = 32
## Meshy GLB import defaults (metallic 1.0) read as porcelain; matte override for map markers.
const CITY_MAT_OVERRIDE_METALLIC: float = 0.0
const CITY_MAT_OVERRIDE_ROUGHNESS: float = 0.85
const CITY_MAT_OVERRIDE_SPECULAR: float = 0.3

## City-only SubViewport yaw on **ModelRoot** (independent of warrior/settler). Negative = clockwise on map.
@export var model_yaw_degrees: float = -67.0
@export var model_pitch_degrees: float = 0.0
## Vertical offset of the model root inside the SubViewport 3D scene (world Y). Framing only — lifts or lowers the GLB in the render, not map hex position.
@export var model_offset_y: float = 0.0
## Scale of the GLB inside the SubViewport 3D scene (not screen pixels). GLB bind AABB height ~0.12; tune for hex-diorama read.
@export var model_scale: float = 5.5
## Optional map blit offset as a fraction of icon side. Prefer **`screen_offset_*`** for centering.
@export var blit_offset_x_ratio: float = 0.0
@export var blit_offset_y_ratio: float = 0.0
## Final 2D blit placement offset in presentation px at **pscale = 1** (multiplied by **pscale**). Negative **screen_offset_y** moves the marker **up** on the map.
@export var screen_offset_x: float = 0.0
@export var screen_offset_y: float = -68.0
## Depth-sort anchor as fraction from the **top** of the icon rect (0 = top, 1 = bottom). Lower values sort earlier (behind); tune building silhouette occlusion vs units.
@export var depth_sort_anchor_y_ratio: float = 0.72
@export var camera_offset_x: float = -0.58
@export var camera_height: float = 2.35
@export var camera_distance: float = 1.65
@export var camera_look_y: float = 0.55
@export var camera_ortho_size: float = 2.05
@export var viewport_bottom_pad_ratio: float = 0.18

var scenario
var layout
var camera
var cities_view
var terrain_foreground_view

var _city_scene: PackedScene
var _slot_by_city_id: Dictionary = {}
var _blit_via_terrain_foreground: bool = false
var _sync_markers_frame: int = -1
var _logged_scene_load: bool = false
var _logged_slot_create_fail: bool = false
var _logged_yaw_runtime_once: bool = false


func _ready() -> void:
	Warrior3DExperimentScript.log_flag_state_once()
	_load_city_scene()
	visible = Warrior3DExperimentScript.should_render_city_as_3d()


func _load_city_scene() -> void:
	if not Warrior3DExperimentScript.should_render_city_as_3d():
		return
	if _city_scene != null:
		return
	var scene_path: String = Warrior3DExperimentScript.city_scene_path()
	if not _logged_scene_load:
		_logged_scene_load = true
		print(
			"[City3D] load scene_path='%s' exists=%s"
			% [scene_path, str(ResourceLoader.exists(scene_path))]
		)
	if scene_path.is_empty():
		push_warning("City3DMarkersView: city_scene_path empty")
		return
	_city_scene = (
		ResourceLoader.load(scene_path, "", ResourceLoader.CACHE_MODE_REUSE) as PackedScene
	)
	if _city_scene == null:
		push_warning("City3DMarkersView: failed to load %s" % scene_path)
	else:
		print("[City3D] load ok scene_path='%s'" % scene_path)


func set_blit_via_terrain_foreground(enabled: bool) -> void:
	_blit_via_terrain_foreground = enabled


func prepare_markers_for_draw() -> void:
	_sync_markers_once_per_frame()


func draw_city_marker_at(
	canvas: CanvasItem,
	anchor_pres: Vector2,
	pscale: float,
	city_id: int,
	_owner_id: int,
) -> void:
	try_draw_city_marker_at(canvas, anchor_pres, pscale, city_id, _owner_id)


## Returns **true** only when a non-null SubViewport texture was blitted.
func try_draw_city_marker_at(
	canvas: CanvasItem,
	anchor_pres: Vector2,
	pscale: float,
	city_id: int,
	_owner_id: int,
) -> bool:
	if not Warrior3DExperimentScript.should_render_city_as_3d():
		return false
	_sync_markers_once_per_frame()
	var rect: Rect2 = marker_display_rect(anchor_pres, pscale)
	if rect.size.x <= 0.0:
		_log_blit_fail_once(city_id, "rect_empty")
		return false
	var slot: Node2D = _slot_by_city_id.get(city_id) as Node2D
	if slot == null:
		if not _logged_slot_create_fail:
			_logged_slot_create_fail = true
			var scen_city_count: int = 0
			var city_id_in_scenario: bool = false
			if scenario != null:
				var clist: Array = scenario.cities()
				scen_city_count = clist.size()
				var ci: int = 0
				while ci < clist.size():
					if int(clist[ci].id) == city_id:
						city_id_in_scenario = true
						break
					ci += 1
			print(
				(
					"[City3D blit] city_id=%d failed no slot "
					+ "(scenario=%s layout=%s scene=%s slots=%d "
					+ "scenario_cities=%d city_id_in_scenario=%s)"
				)
				% [
					city_id,
					str(scenario != null),
					str(layout != null),
					str(_city_scene != null),
					_slot_by_city_id.size(),
					scen_city_count,
					str(city_id_in_scenario),
				]
			)
		return false
	var viewport: SubViewport = _viewport_for_slot(slot)
	if viewport == null:
		_log_blit_fail_once(city_id, "viewport_null")
		return false
	# Re-apply immediately before texture read so yaw/export edits affect this blit.
	_apply_slot_model_framing(slot)
	_log_yaw_at_blit_if_changed(slot, city_id)
	_apply_viewport_size_for_blit(slot, viewport, rect)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var tex: Texture2D = viewport.get_texture()
	if tex == null:
		_log_blit_fail_once(city_id, "texture_null")
		return false
	var prev_filter: CanvasItem.TextureFilter = canvas.texture_filter
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	canvas.draw_texture_rect(tex, rect, false, Color(1.0, 1.0, 1.0, 1.0))
	canvas.texture_filter = prev_filter
	if not bool(slot.get_meta(&"eom_city_blit_ok_logged", false)):
		slot.set_meta(&"eom_city_blit_ok_logged", true)
		_log_slot_framing_once(slot, city_id, rect, anchor_pres, pscale)
		print(
			(
				"[City3D blit] city_id=%d succeeded rect=%s anchor=%s "
				+ "model_yaw=%.1f screen_offset=(%.1f,%.1f) depth_anchor=%s tex_size=%s "
				+ "vp_transparent_bg=%s (CityDrawDiag expects path=3d_ancient_village)"
			)
			% [
				city_id,
				str(rect),
				str(anchor_pres),
				model_yaw_degrees,
				screen_offset_x * pscale,
				screen_offset_y * pscale,
				str(depth_sort_anchor_pres(anchor_pres, pscale)),
				str(tex.get_size()),
				str(viewport.transparent_bg),
			]
		)
	return true


func marker_display_rect(anchor_pres: Vector2, pscale: float) -> Rect2:
	var marker_rect: Rect2 = _marker_rect_presentation(anchor_pres, pscale)
	if marker_rect.size.x <= 0.0 or marker_rect.size.y <= 0.0:
		return Rect2()
	var bottom_pad: float = viewport_bottom_pad_ratio
	var display_size := Vector2(
		marker_rect.size.x,
		marker_rect.size.y * (1.0 + bottom_pad),
	)
	return Rect2(marker_rect.position, display_size)


## Presentation-space depth-sort anchor for TFV marker ordering (building silhouette, not hex center).
func depth_sort_anchor_pres(anchor_pres: Vector2, pscale: float) -> Vector2:
	var marker_rect: Rect2 = _marker_rect_presentation(anchor_pres, pscale)
	if marker_rect.size.x <= 0.0 or marker_rect.size.y <= 0.0:
		return anchor_pres
	return Vector2(
		marker_rect.position.x + marker_rect.size.x * 0.5,
		marker_rect.position.y + marker_rect.size.y * depth_sort_anchor_y_ratio,
	)


func _marker_rect_presentation(anchor_pres: Vector2, pscale: float) -> Rect2:
	var height_ratio: float = 0.90
	if cities_view != null:
		height_ratio = cities_view.city_icon_height_ratio
	var hex_h: float = HexLayoutScript.SIZE * 2.0
	var side: float = hex_h * height_ratio * pscale
	var blit_x: float = side * blit_offset_x_ratio + screen_offset_x * pscale
	var blit_y: float = -side * blit_offset_y_ratio + screen_offset_y * pscale
	return Rect2(
		anchor_pres.x - side * 0.5 + blit_x,
		anchor_pres.y - side * 0.5 + blit_y,
		side,
		side,
	)


func _sync_markers_once_per_frame() -> void:
	var frame: int = Engine.get_frames_drawn()
	if _sync_markers_frame == frame:
		return
	_sync_markers_frame = frame
	_sync_markers()


func _sync_markers() -> void:
	if scenario == null or layout == null:
		return
	_load_city_scene()
	if _city_scene == null:
		return
	if camera == null:
		camera = MapCameraScript.new()
	var active_ids: Dictionary = {}
	var clist: Array = scenario.cities()
	var i: int = 0
	while i < clist.size():
		var city = clist[i]
		var city_id: int = int(city.id)
		active_ids[city_id] = true
		var slot: Node2D = _slot_by_city_id.get(city_id) as Node2D
		if slot == null:
			slot = _create_slot()
			add_child(slot)
			_slot_by_city_id[city_id] = slot
		_apply_slot_model_framing(slot)
		slot.set_meta(&"eom_city_id", city_id)
		slot.position = Vector2.ZERO
		if not _blit_via_terrain_foreground:
			var world_center: Vector2 = layout.hex_to_world(city.position.q, city.position.r)
			var anchor_pres: Vector2 = camera.to_presentation(world_center)
			var pscale: float = camera.perspective_scale_at(world_center)
			slot.position = marker_display_rect(anchor_pres, pscale).position
		i += 1
	var stale_ids: Array = _slot_by_city_id.keys()
	var si: int = 0
	while si < stale_ids.size():
		var stale_id: int = int(stale_ids[si])
		if not active_ids.has(stale_id):
			var stale_slot: Node = _slot_by_city_id[stale_id] as Node
			if stale_slot != null:
				stale_slot.queue_free()
			_slot_by_city_id.erase(stale_id)
		si += 1


func _log_blit_fail_once(city_id: int, reason: String) -> void:
	var key: String = "%d:%s" % [city_id, reason]
	var logged: Dictionary = {}
	if has_meta(&"eom_city_blit_fail_logged"):
		logged = get_meta(&"eom_city_blit_fail_logged") as Dictionary
	if bool(logged.get(key, false)):
		return
	logged[key] = true
	set_meta(&"eom_city_blit_fail_logged", logged)
	print("[City3D blit] city_id=%d failed %s" % [city_id, reason])


func _log_slot_framing_once(
	slot: Node2D, city_id: int, rect: Rect2, anchor_pres: Vector2, pscale: float
) -> void:
	var viewport: SubViewport = _viewport_for_slot(slot)
	if viewport == null:
		return
	var model_root: Node3D = viewport.find_child("ModelRoot", true, false) as Node3D
	var cam: Camera3D = viewport.get_child(0) as Camera3D
	if model_root != null:
		var glb_rot: String = "n/a"
		if model_root.get_child_count() > 0:
			var glb_child: Node3D = model_root.get_child(0) as Node3D
			if glb_child != null:
				glb_rot = str(glb_child.rotation_degrees)
		print(
			(
				"[City3D framing] city_id=%d export_yaw=%.1f model_root_rot=%s "
				+ "glb_child_rot=%s pos=%s scale=%s children=%d rect=%s icon_rect=%s vp_size=%s"
			)
			% [
				city_id,
				model_yaw_degrees,
				str(model_root.rotation_degrees),
				glb_rot,
				str(model_root.position),
				str(model_root.scale),
				model_root.get_child_count(),
				str(rect),
				str(_marker_rect_presentation(anchor_pres, pscale)),
				str(viewport.size),
			]
		)
	if cam != null:
		print(
			"[City3D framing] city_id=%d camera pos=%s ortho_size=%.3f current=%s"
			% [city_id, str(cam.position), cam.size, str(cam.current)]
		)


func _create_slot() -> Node2D:
	var root := Node2D.new()
	var viewport := SubViewport.new()
	viewport.size = _default_viewport_pixel_size()
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = camera_ortho_size
	cam.position = Vector3(camera_offset_x, camera_height, camera_distance)
	cam.current = true
	viewport.add_child(cam)
	cam.look_at_from_position(
		cam.position, Vector3(0.0, camera_look_y, 0.0), Vector3.UP
	)
	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-48.0, 32.0, 0.0)
	key_light.light_energy = 1.1
	viewport.add_child(key_light)
	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(18.0, -128.0, 0.0)
	fill_light.light_energy = 0.35
	viewport.add_child(fill_light)
	var model_root := Node3D.new()
	model_root.name = "ModelRoot"
	if _city_scene != null:
		var model: Node = _city_scene.instantiate()
		if model == null:
			push_warning("City3DMarkersView: instantiate returned null for city scene")
		else:
			_apply_experimental_city_material_override(model)
			model_root.add_child(model)
			print("[City3D] slot model instantiated children=%d" % model.get_child_count())
	else:
		push_warning("City3DMarkersView: _create_slot without loaded city scene")
	_apply_model_root_framing(model_root)
	viewport.add_child(model_root)
	root.add_child(viewport)
	root.set_meta("viewport", viewport)
	return root


func _model_root_for_slot(slot: Node2D) -> Node3D:
	var viewport: SubViewport = _viewport_for_slot(slot)
	if viewport == null:
		return null
	return viewport.find_child("ModelRoot", true, false) as Node3D


func _apply_model_root_framing(model_root: Node3D) -> void:
	model_root.rotation_degrees = Vector3(model_pitch_degrees, model_yaw_degrees, 0.0)
	model_root.position = Vector3(0.0, model_offset_y, 0.0)
	model_root.scale = Vector3.ONE * model_scale


func _apply_slot_model_framing(slot: Node2D) -> void:
	var model_root: Node3D = _model_root_for_slot(slot)
	if model_root == null:
		return
	_apply_model_root_framing(model_root)
	if not _logged_yaw_runtime_once:
		_logged_yaw_runtime_once = true
		_log_yaw_runtime_state(model_root, "first_sync")


func _log_yaw_at_blit_if_changed(slot: Node2D, city_id: int) -> void:
	var last_yaw: float = float(slot.get_meta(&"eom_blit_yaw", -9999.0))
	if is_equal_approx(last_yaw, model_yaw_degrees):
		return
	slot.set_meta(&"eom_blit_yaw", model_yaw_degrees)
	var model_root: Node3D = _model_root_for_slot(slot)
	if model_root == null:
		return
	_log_yaw_runtime_state(model_root, "blit city_id=%d" % city_id)


func _log_yaw_runtime_state(model_root: Node3D, context: String) -> void:
	var glb_rot: String = "n/a"
	var glb_name: String = "n/a"
	if model_root.get_child_count() > 0:
		var glb_child: Node3D = model_root.get_child(0) as Node3D
		if glb_child != null:
			glb_rot = str(glb_child.rotation_degrees)
			glb_name = glb_child.name
	print(
		(
			"[City3D yaw runtime] %s export_yaw=%.1f ModelRoot.rotation_degrees=%s "
			+ "glb_child=%s glb_rot=%s (yaw on ModelRoot; main.tscn has no yaw override)"
		)
		% [context, model_yaw_degrees, str(model_root.rotation_degrees), glb_name, glb_rot]
	)


func _apply_experimental_city_material_override(model: Node) -> void:
	var surface_count: int = 0
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_inst: MeshInstance3D = node as MeshInstance3D
		var mesh: Mesh = mesh_inst.mesh
		if mesh == null:
			continue
		var si: int = 0
		while si < mesh.get_surface_count():
			var src_mat: Material = mesh_inst.get_surface_override_material(si)
			if src_mat == null:
				src_mat = mesh.surface_get_material(si)
			if src_mat is StandardMaterial3D:
				var override_mat: StandardMaterial3D = src_mat.duplicate() as StandardMaterial3D
				override_mat.metallic = CITY_MAT_OVERRIDE_METALLIC
				override_mat.roughness = CITY_MAT_OVERRIDE_ROUGHNESS
				override_mat.metallic_specular = CITY_MAT_OVERRIDE_SPECULAR
				mesh_inst.set_surface_override_material(si, override_mat)
				surface_count += 1
			si += 1
	if surface_count > 0:
		print(
			(
				"[City3D material override] asset=%s surfaces=%d metallic=%.1f roughness=%.2f"
			)
			% [
				Warrior3DExperimentScript.city_scene_path(),
				surface_count,
				CITY_MAT_OVERRIDE_METALLIC,
				CITY_MAT_OVERRIDE_ROUGHNESS,
			]
		)


func _default_viewport_pixel_size() -> Vector2i:
	return _quantized_viewport_size(Vector2(float(VIEWPORT_PX_MIN), float(VIEWPORT_PX_MIN)))


func _quantized_viewport_size(display_size: Vector2) -> Vector2i:
	var q: int = maxi(VIEWPORT_SIZE_QUANTIZE, 1)
	var w: int = clampi(int(ceil(display_size.x)), VIEWPORT_PX_MIN, VIEWPORT_PX_MAX)
	var h: int = clampi(int(ceil(display_size.y)), VIEWPORT_PX_MIN, VIEWPORT_PX_MAX)
	w = int(ceil(float(w) / float(q))) * q
	h = int(ceil(float(h) / float(q))) * q
	return Vector2i(w, h)


func _apply_viewport_size_for_blit(slot: Node2D, viewport: SubViewport, rect: Rect2) -> void:
	var target: Vector2i = _quantized_viewport_size(rect.size)
	var prev: Vector2i = slot.get_meta(&"eom_vp_size", Vector2i.ZERO)
	if prev == target:
		return
	viewport.size = target
	slot.set_meta(&"eom_vp_size", target)


func _viewport_for_slot(slot: Node2D) -> SubViewport:
	if slot.has_meta("viewport"):
		return slot.get_meta("viewport") as SubViewport
	return slot.get_child(0) as SubViewport
