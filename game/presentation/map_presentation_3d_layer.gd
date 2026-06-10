# Map-aligned 3D city presentation via transparent SubViewport composite (above 2D terrain).
class_name MapPresentation3DLayer
extends Node2D

const MapCameraScript = preload("res://presentation/map_camera.gd")
const Warrior3DExperimentScript = preload("res://presentation/warrior_3d_unit_experiment.gd")
const City3DWorldViewScript = preload("res://presentation/city_3d_world_view.gd")
const RESIZE_FIX_VERSION: String = "2026-06-10b"

## When true (and EMPIRE_USE_3D_MODELS=1), cities use **City3DWorldView** scene instances.
@export var real_3d_city_enabled: bool = true
## When true alongside real 3D, **City3DMarkersView** SubViewport blit still draws (reference/fallback).
@export var city_blit_fallback_enabled: bool = false
@export var map_layer_origin: Vector2 = Vector2(400.0, 428.0)
@export var world_camera_height: float = 520.0
@export var world_camera_distance: float = 380.0
@export var world_camera_offset_x: float = -95.0
@export var world_ortho_size: float = 1400.0

var scenario
var layout
var map_camera

var _viewport_container: SubViewportContainer
var _viewport: SubViewport
var _world_pan_root: Node3D
var _world_camera: Camera3D
var _city_world_view: City3DWorldView
var _logged_render_mode: bool = false
var _logged_render_order_once: bool = false
var _logged_composite_diag_once: bool = false
var _logged_resize_pre_assign_once: bool = false
var _logged_hierarchy_audit_once: bool = false
var _auto_blit_fallback_warned: Dictionary = {}
var _last_container_pos: Vector2 = Vector2(-999999.0, -999999.0)
var _last_container_size: Vector2 = Vector2(-1.0, -1.0)
var _last_subviewport_size: Vector2i = Vector2i(-1, -1)


func _ready() -> void:
	print("[MapPresentation3D] resize_fix_version=%s" % RESIZE_FIX_VERSION)
	if Warrior3DExperimentScript.env_real_3d_city_disabled():
		real_3d_city_enabled = false
	if Warrior3DExperimentScript.env_city_blit_fallback_enabled():
		city_blit_fallback_enabled = true
	position = map_layer_origin
	_setup_viewport_composite()
	_update_active_state()
	_log_render_order_once()
	_audit_composite_hierarchy_once()


func uses_real_3d_city() -> bool:
	return (
		real_3d_city_enabled
		and Warrior3DExperimentScript.should_render_city_as_3d()
		and _city_world_view != null
	)


func uses_city_blit_fallback() -> bool:
	if not Warrior3DExperimentScript.should_render_city_as_3d():
		return false
	if not real_3d_city_enabled:
		return true
	if city_blit_fallback_enabled:
		return true
	return false


## True when a live GLB instance exists for **city_id** (used for auto blit fallback).
func is_city_active_in_real_3d(city_id: int) -> bool:
	if not uses_real_3d_city() or _city_world_view == null:
		return false
	if city_id < 0:
		return _city_world_view.get_active_city_count() > 0
	return _city_world_view.has_ready_city_instance(city_id)


func is_composite_viewport_ready() -> bool:
	if _viewport_container == null or _viewport == null:
		return false
	if _viewport_container.size.x <= 0.0 or _viewport_container.size.y <= 0.0:
		return false
	if _viewport.size.x <= 0 or _viewport.size.y <= 0:
		return false
	return true


func should_auto_blit_for_city(city_id: int) -> bool:
	if uses_city_blit_fallback():
		return true
	if not uses_real_3d_city():
		return true
	if not is_composite_viewport_ready():
		return true
	return not is_city_active_in_real_3d(city_id)


func prepare_for_draw() -> void:
	if not uses_real_3d_city():
		return
	_resize_viewport_container()
	if _city_world_view != null:
		_city_world_view.prepare_for_draw()
	_log_render_mode_once()


func sync_from_scenario() -> void:
	if _city_world_view != null:
		_city_world_view.scenario = scenario
		_city_world_view.layout = layout
		if uses_real_3d_city():
			_city_world_view.sync_from_scenario()
	_update_active_state()


func log_city_visibility_diag_once(city_id: int, city = null) -> void:
	_log_composite_viewport_diag_once()
	if _city_world_view == null:
		return
	_city_world_view.log_visibility_diag_once(
		city_id, city, _world_camera, _viewport, self, map_camera, map_layer_origin
	)


func _process(_delta: float) -> void:
	if not uses_real_3d_city() or map_camera == null or _world_camera == null:
		return
	_resize_viewport_container()
	var off: Vector2 = map_camera.camera_world_offset
	if _world_pan_root != null:
		_world_pan_root.position = Vector3(-off.x, 0.0, -off.y)
	_update_world_camera()
	_sync_debug_city_probe()


## Aligns WorldCamera with the 2D map view: aim at the hex-world point shown at screen
## center (MapCamera.to_layout) and match px-per-world-unit to the 2D zoom.
func _update_world_camera() -> void:
	if _world_camera == null or map_camera == null:
		return
	var screen_size: Vector2 = _last_container_size
	if screen_size.x <= 0.0 or screen_size.y <= 0.0:
		return
	var zoom: float = maxf(map_camera.zoom, 0.001)
	var center_local: Vector2 = screen_size * 0.5 - map_layer_origin
	var center_world: Vector2 = map_camera.to_layout(center_local)
	if not center_world.is_finite():
		return
	# Pan root already shifts by -offset; camera works in the same shifted space.
	var s: Vector2 = center_world - map_camera.camera_world_offset
	var target := Vector3(s.x, 0.0, s.y)
	var arm := Vector3(world_camera_offset_x, world_camera_height, world_camera_distance)
	_world_camera.look_at_from_position(target + arm, target, Vector3.UP)
	# Vertical extent in world units = viewport_height / zoom => px-per-unit matches 2D zoom.
	_world_camera.size = screen_size.y / zoom


func _setup_viewport_composite() -> void:
	_viewport_container = get_node_or_null("City3DViewportContainer") as SubViewportContainer
	if _viewport_container == null:
		_viewport_container = SubViewportContainer.new()
		_viewport_container.name = "City3DViewportContainer"
		_viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_viewport_container)
	# Manual SubViewport.size in _resize_viewport_container — stretch must stay off.
	_viewport_container.stretch = false
	_viewport = _viewport_container.get_node_or_null("City3DSubViewport") as SubViewport
	if _viewport == null:
		_viewport = SubViewport.new()
		_viewport.name = "City3DSubViewport"
		_viewport.transparent_bg = true
		_viewport.own_world_3d = true
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_viewport_container.add_child(_viewport)
	_world_pan_root = _viewport.get_node_or_null("WorldPanRoot") as Node3D
	if _world_pan_root == null:
		_world_pan_root = Node3D.new()
		_world_pan_root.name = "WorldPanRoot"
		_viewport.add_child(_world_pan_root)
	_world_camera = _viewport.get_node_or_null("WorldCamera") as Camera3D
	if _world_camera == null:
		_world_camera = Camera3D.new()
		_world_camera.name = "WorldCamera"
		_viewport.add_child(_world_camera)
	_world_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_world_camera.position = Vector3(
		world_camera_offset_x, world_camera_height, world_camera_distance
	)
	_world_camera.look_at(Vector3.ZERO, Vector3.UP)
	_world_camera.size = world_ortho_size
	_world_camera.current = true
	if _world_pan_root.get_node_or_null("KeyLight") == null:
		var key_light := DirectionalLight3D.new()
		key_light.name = "KeyLight"
		key_light.rotation_degrees = Vector3(-48.0, 32.0, 0.0)
		key_light.light_energy = 1.1
		_world_pan_root.add_child(key_light)
	if _world_pan_root.get_node_or_null("FillLight") == null:
		var fill_light := DirectionalLight3D.new()
		fill_light.name = "FillLight"
		fill_light.rotation_degrees = Vector3(18.0, -128.0, 0.0)
		fill_light.light_energy = 0.35
		_world_pan_root.add_child(fill_light)
	_city_world_view = _world_pan_root.get_node_or_null("City3DWorldView") as City3DWorldView
	if _city_world_view == null:
		_city_world_view = City3DWorldViewScript.new()
		_city_world_view.name = "City3DWorldView"
		_world_pan_root.add_child(_city_world_view)
	_setup_debug_probes()
	_resize_viewport_container()


## TEMP DIAG — EOM_CITY3D_DEBUG_PROBE=1: opaque bg + magenta origin cube + cyan city cube.
func _setup_debug_probes() -> void:
	if not Warrior3DExperimentScript.env_city3d_debug_probe_enabled():
		return
	_viewport.transparent_bg = false
	if _world_pan_root.get_node_or_null("DebugOriginProbe") == null:
		_world_pan_root.add_child(_make_debug_probe_cube("DebugOriginProbe", Color(1, 0, 1)))
	if _world_pan_root.get_node_or_null("DebugCityProbe") == null:
		var city_probe := _make_debug_probe_cube("DebugCityProbe", Color(0, 1, 1))
		city_probe.visible = false
		_world_pan_root.add_child(city_probe)
	print(
		"[MapPresentation3D] debug_probe enabled: opaque bg + origin cube (magenta) "
		+ "+ city cube (cyan)"
	)


func _make_debug_probe_cube(probe_name: String, color: Color) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = probe_name
	var box := BoxMesh.new()
	box.size = Vector3(120.0, 600.0, 120.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	box.material = mat
	mesh_inst.mesh = box
	mesh_inst.position = Vector3(0.0, 300.0, 0.0)
	return mesh_inst


func _sync_debug_city_probe() -> void:
	if _world_pan_root == null or _city_world_view == null:
		return
	var probe: MeshInstance3D = _world_pan_root.get_node_or_null("DebugCityProbe") as MeshInstance3D
	if probe == null:
		return
	var inst: Node3D = _city_world_view.first_city_instance()
	if inst == null:
		probe.visible = false
		return
	probe.visible = true
	probe.position = inst.position + Vector3(0.0, 300.0, 0.0)


func _resolve_active_composite_nodes() -> bool:
	var container: SubViewportContainer = (
		get_node_or_null("City3DViewportContainer") as SubViewportContainer
	)
	if container == null:
		_viewport_container = null
		_viewport = null
		return false
	var subvp: SubViewport = container.get_node_or_null("City3DSubViewport") as SubViewport
	_viewport_container = container
	_viewport = subvp
	return subvp != null


func _resize_viewport_container() -> void:
	if not _resolve_active_composite_nodes():
		return
	var vp: Viewport = get_viewport()
	if vp == null:
		return
	var parent_container: SubViewportContainer = _parent_container_for_subviewport(_viewport)
	if parent_container == null:
		push_error(
			(
				"[MapPresentation3D] resize skipped: SubViewport parent is not SubViewportContainer "
				+ "subvp=%s parent=%s"
			)
			% [
				str(_viewport.get_path()),
				str(_viewport.get_parent().get_path() if _viewport.get_parent() != null else "null"),
			]
		)
		return
	_viewport_container = parent_container
	var screen_size: Vector2 = vp.get_visible_rect().size
	var container_pos: Vector2 = -map_layer_origin
	var subvp_size: Vector2i = Vector2i(int(screen_size.x), int(screen_size.y))
	var changed: bool = false
	if not _last_container_pos.is_equal_approx(container_pos):
		parent_container.position = container_pos
		_last_container_pos = container_pos
		changed = true
	if not _last_container_size.is_equal_approx(screen_size):
		parent_container.size = screen_size
		_last_container_size = screen_size
		changed = true
	if _viewport.size != subvp_size:
		if _assign_subviewport_size_guarded(_viewport, subvp_size):
			changed = true
	if changed:
		_log_composite_viewport_diag_once()


func _parent_container_for_subviewport(subvp: SubViewport) -> SubViewportContainer:
	if subvp == null:
		return null
	var actual_parent: Node = subvp.get_parent()
	if actual_parent is SubViewportContainer:
		var container: SubViewportContainer = actual_parent as SubViewportContainer
		container.stretch = false
		return container
	return null


## Sole code path that assigns **SubViewport.size** (guarded stretch-off on actual parent).
func _assign_subviewport_size_guarded(subvp: SubViewport, desired_size: Vector2i) -> bool:
	if subvp == null:
		return false
	var actual_parent: Node = subvp.get_parent()
	var assumed_path: String = (
		str(_viewport_container.get_path()) if _viewport_container != null else "n/a"
	)
	var stretch_before: bool = false
	var stretch_after: bool = false
	var parent_is_container: bool = actual_parent is SubViewportContainer
	if parent_is_container:
		var container: SubViewportContainer = actual_parent as SubViewportContainer
		stretch_before = container.stretch
		container.stretch = false
		stretch_after = container.stretch
		_viewport_container = container
	_log_resize_pre_assign_once(
		subvp, actual_parent, assumed_path, parent_is_container, stretch_before, stretch_after, desired_size
	)
	if not parent_is_container:
		push_error(
			(
				"[MapPresentation3D] SubViewport parent is not SubViewportContainer; "
				+ "skip size assign subvp=%s parent_class=%s parent_path=%s"
			)
			% [
				str(subvp.get_path()),
				actual_parent.get_class() if actual_parent != null else "null",
				str(actual_parent.get_path()) if actual_parent != null else "null",
			]
		)
		return false
	if stretch_after:
		push_error(
			(
				"[MapPresentation3D] stretch still true after enforce=false; "
				+ "skip SubViewport.size assign actual_parent=%s assumed=%s"
			)
			% [str(actual_parent.get_path()), assumed_path]
		)
		return false
	subvp.size = desired_size
	_last_subviewport_size = desired_size
	return true


func _log_resize_pre_assign_once(
	subvp: SubViewport,
	actual_parent: Node,
	assumed_container_path: String,
	parent_is_container: bool,
	stretch_before: bool,
	stretch_after: bool,
	desired_size: Vector2i,
) -> void:
	if _logged_resize_pre_assign_once:
		return
	_logged_resize_pre_assign_once = true
	var actual_parent_path: String = (
		str(actual_parent.get_path()) if actual_parent != null else "null"
	)
	var actual_parent_class: String = (
		actual_parent.get_class() if actual_parent != null else "null"
	)
	var container_size: Vector2 = Vector2.ZERO
	if actual_parent is SubViewportContainer:
		container_size = (actual_parent as SubViewportContainer).size
	print(
		(
			"[MapPresentation3D] resize_pre_assign version=%s subviewport_path=%s "
			+ "actual_parent_path=%s actual_parent_class=%s parent_is_subviewport_container=%s "
			+ "stretch_before=%s stretch_after=%s assumed_container_path=%s "
			+ "parent_differs_from_assumed=%s container_size=%s desired_subviewport_size=%s"
		)
		% [
			RESIZE_FIX_VERSION,
			str(subvp.get_path()),
			actual_parent_path,
			actual_parent_class,
			str(parent_is_container),
			str(stretch_before),
			str(stretch_after),
			assumed_container_path,
			str(actual_parent != null and assumed_container_path != actual_parent_path),
			str(container_size),
			str(desired_size),
		]
	)


func _audit_composite_hierarchy_once() -> void:
	if _logged_hierarchy_audit_once:
		return
	_logged_hierarchy_audit_once = true
	var layer_paths: Array[String] = []
	var container_paths: Array[String] = []
	_collect_nodes_named(get_tree().root, "MapPresentation3DLayer", layer_paths)
	_collect_subviewport_containers(get_tree().root, container_paths)
	var active_container_path: String = (
		str(_viewport_container.get_path()) if _viewport_container != null else "n/a"
	)
	var active_viewport_path: String = str(_viewport.get_path()) if _viewport != null else "n/a"
	var layer_container_lines: Array[String] = []
	var ci: int = 0
	while ci < get_child_count():
		var ch: Node = get_child(ci)
		if ch is SubViewportContainer:
			var container: SubViewportContainer = ch as SubViewportContainer
			var subvp_lines: Array[String] = []
			var si: int = 0
			while si < container.get_child_count():
				var sub_ch: Node = container.get_child(si)
				if sub_ch is SubViewport:
					var subvp: SubViewport = sub_ch as SubViewport
					subvp_lines.append(
						"%s is_resize_parent=%s"
						% [str(subvp.get_path()), str(_viewport != null and subvp == _viewport)]
					)
				si += 1
			layer_container_lines.append(
				"%s stretch=%s subviewports=[%s]"
				% [str(container.get_path()), str(container.stretch), ", ".join(subvp_lines)]
			)
		ci += 1
	print(
		(
			"[MapPresentation3D] hierarchy_audit version=%s layer_count=%d layer_paths=%s "
			+ "container_count=%d container_paths=%s active_container=%s active_subviewport=%s "
			+ "layer_containers=[%s]"
		)
		% [
			RESIZE_FIX_VERSION,
			layer_paths.size(),
			str(layer_paths),
			container_paths.size(),
			str(container_paths),
			active_container_path,
			active_viewport_path,
			", ".join(layer_container_lines),
		]
	)


func _collect_nodes_named(node: Node, node_name: String, out_paths: Array[String]) -> void:
	if node.name == node_name:
		out_paths.append(str(node.get_path()))
	var ci: int = 0
	while ci < node.get_child_count():
		_collect_nodes_named(node.get_child(ci), node_name, out_paths)
		ci += 1


func _collect_subviewport_containers(node: Node, out_paths: Array[String]) -> void:
	if node is SubViewportContainer:
		out_paths.append("%s stretch=%s" % [str(node.get_path()), str((node as SubViewportContainer).stretch)])
	var ci: int = 0
	while ci < node.get_child_count():
		_collect_subviewport_containers(node.get_child(ci), out_paths)
		ci += 1


func _log_composite_viewport_diag_once() -> void:
	if _logged_composite_diag_once:
		return
	_logged_composite_diag_once = true
	var container_size: Vector2 = (
		_viewport_container.size if _viewport_container != null else Vector2.ZERO
	)
	var subvp_size: Vector2i = _viewport.size if _viewport != null else Vector2i.ZERO
	var stretch: bool = _viewport_container.stretch if _viewport_container != null else false
	var transparent_bg: bool = _viewport.transparent_bg if _viewport != null else false
	var camera_current: bool = _world_camera.current if _world_camera != null else false
	var ready_cities: int = (
		_city_world_view.get_active_city_count() if _city_world_view != null else 0
	)
	var render_mode: String = "real_scene_3d_composite"
	if uses_city_blit_fallback():
		render_mode = "real_scene_3d_composite+blit_fallback"
	print(
		(
			"[MapPresentation3D] composite_diag city_render=%s stretch=%s "
			+ "container_size=%s subviewport_size=%s transparent_bg=%s "
			+ "camera_current=%s ready_cities=%d composite_ready=%s"
		)
		% [
			render_mode,
			str(stretch),
			str(container_size),
			str(subvp_size),
			str(transparent_bg),
			str(camera_current),
			ready_cities,
			str(is_composite_viewport_ready()),
		]
	)


func _update_active_state() -> void:
	var active: bool = uses_real_3d_city()
	visible = active
	if _viewport_container != null:
		_viewport_container.visible = active
	if _world_camera != null:
		_world_camera.current = active
	if _city_world_view != null:
		_city_world_view.visible = active


func warn_auto_blit_fallback_once(city_id: int, reason: String) -> void:
	var key: String = "%d:%s" % [city_id, reason]
	if _auto_blit_fallback_warned.has(key):
		return
	_auto_blit_fallback_warned[key] = true
	push_warning(
		"[MapPresentation3D] auto blit fallback city_id=%d reason=%s" % [city_id, reason]
	)


func _log_render_mode_once() -> void:
	if _logged_render_mode:
		return
	_logged_render_mode = true
	var mode: String = "real_scene_3d_composite"
	if uses_city_blit_fallback():
		mode = "real_scene_3d_composite+blit_fallback"
	print(
		(
			"[MapPresentation3D] city_render=%s real_3d_city=%s blit_fallback=%s "
			+ "layer_origin=%s composite=SubViewportContainer"
		)
		% [
			mode,
			str(real_3d_city_enabled),
			str(city_blit_fallback_enabled),
			str(map_layer_origin),
		]
	)


func _log_render_order_once() -> void:
	if _logged_render_order_once:
		return
	_logged_render_order_once = true
	print(
		(
			"[MapPresentation3D] render_order=SubViewportContainer after TerrainForegroundView "
			+ "(prior Node3D-main-viewport path drew behind opaque 2D canvas)"
		)
	)
