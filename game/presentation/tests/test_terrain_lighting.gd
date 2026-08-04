# Headless test: godot --headless --path game -s res://presentation/tests/test_terrain_lighting.gd
#
# N3c.7 production terrain lighting rig (game/presentation/world/terrain_lighting.gd):
# - structural: the rig is one named node with exactly SunLight (shadowed
#   key), FillLight (shadowless counter fill) and WorldEnvironment;
# - deterministic configuration: every rig property comes from the locked
#   constants; two independently built rigs are identical; the only input
#   (terrain AABB) affects the shadow range only, map-relatively;
# - shared-scene reuse: the runtime terrain world contains exactly one rig
#   built by this module and no lights/environments anywhere else;
# - non-regression: terrain construction counts and picking are unchanged
#   with the rig in place.
#
# Requires the built GDExtension (from repo root): .\scripts\build-native.ps1
# This test must FAIL (not fall back) when the extension is unavailable.
extends SceneTree

const TerrainLighting = preload("res://presentation/world/terrain_lighting.gd")
const TerrainWorldScript = preload("res://presentation/world/terrain_world.gd")
const TerrainPicker = preload("res://presentation/terrain_picker.gd")
const MapContentLoader = preload("res://domain/world/map_content_loader.gd")
const Ts08HeightSolver = preload("res://domain/world/ts08_height_solver.gd")

const DESCRIPTOR_PATH := "res://bin/eom_native.gdextension"

const REFERENCE_AABB := AABB(Vector3(-1.0, -0.1, -1.0), Vector3(19.0, 2.2, 24.5))

const EXPECTED_COUNTS := {
	"nodes": 74129,
	"top_triangles": 145152,
	"wall_faces": 936,
	"collision_top_triangles": 145152,
	"collision_wall_triangles": 1852,
}

var _total := 0
var _any_fail := false


func _init() -> void:
	_run()


func _run() -> void:
	_run_structure_checks()
	_run_determinism_checks()
	await _run_shared_world_checks()
	_finish()


func _run_structure_checks() -> void:
	var rig: Node3D = TerrainLighting.build_rig(REFERENCE_AABB)
	_check(rig.name == StringName(TerrainLighting.RIG_NAME), "rig node named TerrainLighting")
	_check(rig.get_child_count() == 3, "rig contains exactly three nodes")

	var sun := rig.get_node_or_null(TerrainLighting.SUN_NAME) as DirectionalLight3D
	var fill := rig.get_node_or_null(TerrainLighting.FILL_NAME) as DirectionalLight3D
	var env_node := rig.get_node_or_null(TerrainLighting.ENVIRONMENT_NAME) as WorldEnvironment
	_check(sun != null and fill != null and env_node != null,
		"SunLight, FillLight and WorldEnvironment present with locked names")
	if sun == null or fill == null or env_node == null:
		rig.free()
		return

	# Light properties are float32 in the engine, so the locked float64
	# GDScript constants are compared approximately (config still exact:
	# the A/B determinism check below is hash-identical).
	_check(
		sun.rotation_degrees.is_equal_approx(TerrainLighting.SUN_ROTATION_DEGREES)
		and sun.light_color == TerrainLighting.SUN_COLOR
		and is_equal_approx(sun.light_energy, TerrainLighting.SUN_ENERGY)
		and is_equal_approx(sun.light_angular_distance, TerrainLighting.SUN_ANGULAR_DISTANCE_DEG),
		"sun uses the locked key-light constants"
	)
	_check(
		sun.shadow_enabled
		and is_equal_approx(sun.shadow_bias, TerrainLighting.SHADOW_BIAS)
		and is_equal_approx(sun.shadow_normal_bias, TerrainLighting.SHADOW_NORMAL_BIAS)
		and sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		and sun.directional_shadow_blend_splits,
		"sun shadows: PSSM 4 blended splits with the locked bias tuning"
	)
	_check(
		is_equal_approx(
			sun.directional_shadow_max_distance,
			TerrainLighting.SHADOW_MAX_DISTANCE_FACTOR * 24.5
		),
		"shadow range map-relative from the terrain AABB extent"
	)
	_check(
		fill.rotation_degrees.is_equal_approx(TerrainLighting.FILL_ROTATION_DEGREES)
		and fill.light_color == TerrainLighting.FILL_COLOR
		and is_equal_approx(fill.light_energy, TerrainLighting.FILL_ENERGY)
		and not fill.shadow_enabled
		and fill.light_specular == 0.0,
		"fill light shadowless, specular-free, locked constants"
	)

	# The ACCEPTED N3c.7 production gameplay lighting — literal values, so
	# any drift (e.g. moving the light to chase the decorative sky disc)
	# fails loudly.
	_check(
		TerrainLighting.SUN_ROTATION_DEGREES == Vector3(-50.0, -32.5, 0.0)
		and TerrainLighting.SUN_ENERGY == 1.55
		and TerrainLighting.FILL_ROTATION_DEGREES == Vector3(-38.0, 147.5, 0.0)
		and TerrainLighting.FILL_ENERGY == 0.45,
		"accepted production light values restored (sun -50/-32.5 @ 1.55, fill -38/147.5 @ 0.45)"
	)
	var azimuth_opposition := fposmod(
		TerrainLighting.FILL_ROTATION_DEGREES.y - TerrainLighting.SUN_ROTATION_DEGREES.y,
		360.0
	)
	_check(
		absf(azimuth_opposition - 180.0) <= 1.0,
		"fill azimuth opposes the sun azimuth (shadow-side lift preserved)"
	)

	var environment: Environment = env_node.environment
	_check(environment != null, "environment resource assigned")
	if environment != null:
		var sky_material := _sky_material(environment)
		_check(
			environment.background_mode == Environment.BG_SKY and sky_material != null,
			"backdrop is a procedural sky"
		)
		if sky_material != null:
			_check(
				sky_material.sky_top_color == TerrainLighting.SKY_TOP_COLOR
				and sky_material.sky_horizon_color == TerrainLighting.SKY_HORIZON_COLOR
				and is_equal_approx(sky_material.sky_curve, TerrainLighting.SKY_CURVE),
				"sky gradient: muted medium blue above, lighter blue-grey horizon"
			)
			_check(
				sky_material.ground_bottom_color == TerrainLighting.GROUND_BOTTOM_COLOR
				and sky_material.ground_horizon_color == TerrainLighting.GROUND_HORIZON_COLOR
				and is_equal_approx(sky_material.ground_curve, TerrainLighting.GROUND_CURVE),
				"below-horizon sky uses the locked blue-grey constants"
			)
			# Interim daytime character (structure, not final art
			# direction): blue-dominant gradient, an exactly seamless
			# hemisphere boundary, and a gradual below-horizon fade so no
			# line or ring shows around the floating map.
			var top: Color = TerrainLighting.SKY_TOP_COLOR
			var horizon: Color = TerrainLighting.SKY_HORIZON_COLOR
			_check(
				top.b > top.r and top.b > top.g and horizon.b > horizon.r,
				"sky gradient blue-dominant (not white-grey haze)"
			)
			_check(
				sky_material.sky_horizon_color == sky_material.ground_horizon_color
				and TerrainLighting.SKY_HORIZON_COLOR == TerrainLighting.GROUND_HORIZON_COLOR,
				"upper and lower horizon colors exactly equal (no hemisphere seam)"
			)
			var bottom: Color = TerrainLighting.GROUND_BOTTOM_COLOR
			var shared: Color = TerrainLighting.GROUND_HORIZON_COLOR
			_check(
				bottom.r < shared.r and bottom.g < shared.g and bottom.b < shared.b
				and is_equal_approx(TerrainLighting.GROUND_CURVE, 0.02),
				"broad below-horizon fade toward the subdued dark bottom (curve 0.02)"
			)
			_check(
				is_equal_approx(sky_material.sun_angle_max, TerrainLighting.SUN_ANGLE_MAX_DEG)
				and is_equal_approx(sky_material.sun_curve, TerrainLighting.SUN_CURVE),
				"contained sun glow (locked angle/curve)"
			)
		_check(
			environment.ambient_light_source == Environment.AMBIENT_SOURCE_COLOR
			and environment.ambient_light_color == TerrainLighting.AMBIENT_COLOR
			and is_equal_approx(environment.ambient_light_energy, TerrainLighting.AMBIENT_ENERGY),
			"ambient stays the locked flat color (not sky-sampled)"
		)
		_check(
			environment.reflected_light_source == Environment.REFLECTION_SOURCE_DISABLED,
			"sky is backdrop only: reflected light disabled (material look preserved)"
		)
		_check(
			environment.tonemap_mode == Environment.TONE_MAPPER_FILMIC
			and environment.tonemap_exposure == TerrainLighting.TONEMAP_EXPOSURE
			and environment.tonemap_white == TerrainLighting.TONEMAP_WHITE,
			"Filmic tonemap with the locked exposure/white"
		)
	rig.free()


func _run_determinism_checks() -> void:
	var rig_a: Node3D = TerrainLighting.build_rig(REFERENCE_AABB)
	var rig_b: Node3D = TerrainLighting.build_rig(REFERENCE_AABB)
	_check(
		_rig_config(rig_a).hash() == _rig_config(rig_b).hash(),
		"two independently built rigs configured identically"
	)
	rig_a.free()
	rig_b.free()

	var small := TerrainLighting.shadow_max_distance_for(
		AABB(Vector3.ZERO, Vector3(4.0, 1.0, 5.0))
	)
	var large := TerrainLighting.shadow_max_distance_for(
		AABB(Vector3.ZERO, Vector3(40.0, 1.0, 50.0))
	)
	_check(
		is_equal_approx(small, TerrainLighting.SHADOW_MAX_DISTANCE_FACTOR * 5.0)
		and is_equal_approx(large, TerrainLighting.SHADOW_MAX_DISTANCE_FACTOR * 50.0),
		"shadow range scales with the map extent (X/Z maximum)"
	)


# Full runtime world: exactly one rig owned by the shared component, no
# competing lights, and construction/picking unchanged with the rig live.
func _run_shared_world_checks() -> void:
	if not _require_native_extension():
		return
	var world_map = MapContentLoader.load_reference_world_map()
	_check(world_map != null, "caller-side WorldMap loads")
	if world_map == null:
		return

	var world = TerrainWorldScript.new()
	world.name = "TerrainWorld"
	root.add_child(world)
	var ok: bool = world.build(world_map, Ts08HeightSolver.BACKEND_NATIVE)
	_check(ok, "runtime world builds with the production rig (native backend)")
	if not ok:
		return

	var rig = world.get_node_or_null(TerrainLighting.RIG_NAME)
	_check(rig is Node3D, "runtime world contains the TerrainLighting rig")
	var lights_and_envs: Array = []
	_collect_lighting_nodes(world, lights_and_envs)
	var all_inside_rig := lights_and_envs.size() == 3
	for node in lights_and_envs:
		if node.get_parent() != rig:
			all_inside_rig = false
	_check(
		all_inside_rig,
		"every light/environment in the world lives inside the shared rig"
	)
	var sun = rig.get_node_or_null(TerrainLighting.SUN_NAME) if rig != null else null
	var expected_distance: float = TerrainLighting.shadow_max_distance_for(
		world.get_node("TopSurface").mesh.get_aabb()
	)
	_check(
		sun is DirectionalLight3D and sun.shadow_enabled
		and is_equal_approx(sun.directional_shadow_max_distance, expected_distance),
		"in-world sun shadow range derived from the generated mesh AABB"
	)

	var counts_ok := true
	for key in EXPECTED_COUNTS:
		if int(world.counts.get(key, -1)) != int(EXPECTED_COUNTS[key]):
			counts_ok = false
	_check(counts_ok, "terrain construction counts unchanged (non-regression)")

	await physics_frame
	await physics_frame
	var pick: Dictionary = world.pick_at_screen_position(root.get_visible_rect().size / 2.0)
	_check(
		pick.get("kind", "") in [TerrainPicker.KIND_TILE, TerrainPicker.KIND_CLIFF],
		"picking unchanged with the rig in place (non-regression)"
	)
	print("center pick with production rig = %s" % str(pick))
	root.remove_child(world)
	world.free()


static func _sky_material(environment: Environment) -> ProceduralSkyMaterial:
	if environment.sky == null:
		return null
	return environment.sky.sky_material as ProceduralSkyMaterial


static func _collect_lighting_nodes(node: Node, out: Array) -> void:
	if node is Light3D or node is WorldEnvironment:
		out.append(node)
	for child in node.get_children():
		_collect_lighting_nodes(child, out)


# Serializes every rig property this slice locks, for exact A/B comparison.
static func _rig_config(rig: Node3D) -> Dictionary:
	var sun: DirectionalLight3D = rig.get_node(TerrainLighting.SUN_NAME)
	var fill: DirectionalLight3D = rig.get_node(TerrainLighting.FILL_NAME)
	var environment: Environment = rig.get_node(TerrainLighting.ENVIRONMENT_NAME).environment
	return {
		"sun_rotation": sun.rotation_degrees,
		"sun_color": sun.light_color,
		"sun_energy": sun.light_energy,
		"sun_angular": sun.light_angular_distance,
		"sun_shadow": sun.shadow_enabled,
		"sun_bias": sun.shadow_bias,
		"sun_normal_bias": sun.shadow_normal_bias,
		"sun_shadow_mode": sun.directional_shadow_mode,
		"sun_blend_splits": sun.directional_shadow_blend_splits,
		"sun_shadow_distance": sun.directional_shadow_max_distance,
		"fill_rotation": fill.rotation_degrees,
		"fill_color": fill.light_color,
		"fill_energy": fill.light_energy,
		"fill_specular": fill.light_specular,
		"fill_shadow": fill.shadow_enabled,
		"bg_mode": environment.background_mode,
		"sky_top": _sky_material(environment).sky_top_color,
		"sky_horizon": _sky_material(environment).sky_horizon_color,
		"sky_curve": _sky_material(environment).sky_curve,
		"ground_bottom": _sky_material(environment).ground_bottom_color,
		"ground_horizon": _sky_material(environment).ground_horizon_color,
		"ground_curve": _sky_material(environment).ground_curve,
		"sun_angle_max": _sky_material(environment).sun_angle_max,
		"sun_curve": _sky_material(environment).sun_curve,
		"ambient_source": environment.ambient_light_source,
		"ambient_color": environment.ambient_light_color,
		"ambient_energy": environment.ambient_light_energy,
		"tonemap": environment.tonemap_mode,
		"tonemap_exposure": environment.tonemap_exposure,
		"tonemap_white": environment.tonemap_white,
	}


func _require_native_extension() -> bool:
	if not FileAccess.file_exists(DESCRIPTOR_PATH):
		_check(false, "native GDExtension descriptor present (build it first)")
		return false
	if not GDExtensionManager.is_extension_loaded(DESCRIPTOR_PATH):
		if GDExtensionManager.load_extension(DESCRIPTOR_PATH) != GDExtensionManager.LOAD_STATUS_OK:
			_check(false, "native GDExtension loads")
			return false
	if not ClassDB.can_instantiate(&"EomTerrainNative"):
		_check(false, "EomTerrainNative instantiable")
		return false
	return true


func _check(condition: bool, label: String) -> void:
	_total += 1
	if condition:
		print("PASS ", label)
	else:
		_any_fail = true
		print("FAIL ", label)


func _finish() -> void:
	print("TerrainLighting tests: %d checks" % _total)
	if _any_fail:
		print("FAIL")
		quit(1)
	else:
		print("PASS")
		quit(0)
