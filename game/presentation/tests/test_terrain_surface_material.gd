# Headless test: godot --headless --path game -s res://presentation/tests/test_terrain_surface_material.gd
#
# N3c.3a terrain top-surface splatting material:
# - world-anchored UV values and continuity (never normalized per map/chunk/hex);
# - tangent validity for tangent-space normal maps on the planar world UV;
# - required texture and shader binding (nine locked prototype maps);
# - deterministic, locked mask inputs (baseline parameters incl. fixed seed);
# - debug stage selection (final / ash_mask / stone_mask / albedo).
extends SceneTree

const TerrainSurfaceMaterial = preload("res://presentation/terrain_surface_material.gd")

# Locked baseline expectations, duplicated independently from the module so a
# silent retune of either side fails the test (mirrors the approved
# APPROVED_BLENDER_PORTING_BASELINE in
# tools/blender/terrain/generate_terrain_single_patch_pbr_ground_stone_ash_prototype.py).
const EXPECTED_LOCKED_PARAMETERS := {
	"world_uv_scale": 0.35,
	"ground_base_color": Vector3(0.08, 0.11, 0.045),
	"ground_albedo_tint_strength": 0.15,
	"ground_normal_strength": 0.65,
	"ground_roughness_multiplier": 1.0,
	"ground_roughness_variation_strength": 0.08,
	"ash_normal_strength": 0.55,
	"ash_roughness_multiplier": 1.0,
	"stone_albedo_multiplier": 0.55,
	"stone_normal_strength": 0.65,
	"stone_roughness_multiplier": 1.0,
	"large_noise_scale": 0.18,
	"large_noise_detail": 4.0,
	"large_noise_roughness": 0.45,
	"large_factor_from_min": 0.35,
	"large_factor_from_max": 0.65,
	"ash_breakup_noise_scale": 0.75,
	"ash_breakup_noise_detail": 2.0,
	"ash_breakup_noise_roughness": 0.55,
	"ash_breakup_min": 0.35,
	"ash_breakup_max": 0.75,
	"ash_breakup_strength": 0.75,
	"ash_weight_input_min": 0.30,
	"ash_weight_input_max": 0.95,
	"slope_blend_start": 0.96,
	"slope_blend_end": 0.90,
	"stone_breakup_noise_scale": 2.0,
	"stone_breakup_noise_detail": 1.0,
	"stone_breakup_noise_roughness": 1.0,
	"stone_breakup_strength": 0.080,
	"fine_noise_scale": 2.8,
	"fine_noise_detail": 8.0,
	"fine_noise_roughness": 0.55,
	"bump_strength": 0.12,
	"bump_distance": 0.02,
	"noise_seed": 0.0,
}

var _total := 0
var _any_fail := false


func _init() -> void:
	_test_world_uv_values()
	_test_world_uv_continuity()
	_test_tangents()
	_test_texture_and_shader_binding()
	_test_locked_parameters()
	_test_debug_stages()
	_test_deterministic_creation()
	_finish()


func _test_world_uv_values() -> void:
	print("--- world-anchored UV values ---")
	_check(
		is_equal_approx(TerrainSurfaceMaterial.WORLD_UV_SCALE, 0.35),
		"world UV scale locked at 0.35"
	)
	_check(
		TerrainSurfaceMaterial.world_uv(Vector3.ZERO) == Vector2.ZERO,
		"origin maps to UV (0, 0)"
	)
	var uv := TerrainSurfaceMaterial.world_uv(Vector3(1.0, 5.0, 2.0))
	_check(
		uv.is_equal_approx(Vector2(0.35, -0.7)),
		"(x, z) = (1, 2) maps to (0.35, -0.7); height ignored"
	)
	# Reference-map-scale coordinates leave [0, 1]: UV repeats via sampler,
	# it is never normalized to the map extent.
	var far_uv := TerrainSurfaceMaterial.world_uv(Vector3(20.0, 0.0, -14.0))
	_check(
		far_uv.is_equal_approx(Vector2(7.0, 4.9)),
		"map-scale coordinates produce UVs far outside [0, 1] (no normalization)"
	)

	var positions := PackedVector3Array([
		Vector3(0.0, 0.0, 0.0),
		Vector3(1.0, 3.0, 2.0),
		Vector3(-4.5, 0.2, 7.25),
	])
	var uvs := TerrainSurfaceMaterial.build_world_uv_array(positions)
	var array_ok := uvs.size() == positions.size()
	for i in positions.size():
		if not uvs[i].is_equal_approx(TerrainSurfaceMaterial.world_uv(positions[i])):
			array_ok = false
	_check(array_ok, "UV array matches the per-vertex formula")


func _test_world_uv_continuity() -> void:
	print("--- world-anchored UV continuity ---")
	# The mapping is a single global linear function of world position, so the
	# UV delta between any two points depends only on their offset — including
	# across hex boundaries (hex radius 1.0) and chunk-scale distances. That is
	# exactly "continuous across the entire mesh, never normalized per map,
	# chunk, or hex".
	var offsets := [
		Vector3(1.0, 0.0, 0.0),        # crosses a hex boundary
		Vector3(0.0, 0.0, 1.0),
		Vector3(1.7320508, 0.4, -1.5), # arbitrary diagonal with height change
		Vector3(12.0, -2.0, 9.0),      # chunk-scale offset
	]
	var bases := [
		Vector3.ZERO,
		Vector3(0.5, 0.0, -0.8660254), # hex corner region
		Vector3(-7.25, 1.2, 3.5),
	]
	var continuous := true
	for base: Vector3 in bases:
		for offset: Vector3 in offsets:
			var expected := Vector2(
				offset.x * TerrainSurfaceMaterial.WORLD_UV_SCALE,
				-offset.z * TerrainSurfaceMaterial.WORLD_UV_SCALE
			)
			var actual := (
				TerrainSurfaceMaterial.world_uv(base + offset)
				- TerrainSurfaceMaterial.world_uv(base)
			)
			if actual.distance_to(expected) > 1e-6:
				continuous = false
	_check(continuous, "UV deltas depend only on the world offset (no restart anywhere)")


func _test_tangents() -> void:
	print("--- top-surface tangents (non-flat coverage) ---")
	# Smooth normals of height surfaces sloped in X only, Z only, both, and
	# flat: N ∝ (-h_x, 1, -h_z). A flat-only test is insufficient — the
	# tangent must stay orthogonal to the normal on every slope direction.
	var slopes := [
		Vector2(0.0, 0.0),    # flat
		Vector2(0.8, 0.0),    # X slope
		Vector2(-1.5, 0.0),   # steep negative X slope
		Vector2(0.0, 0.7),    # Z slope
		Vector2(0.0, -2.0),   # steep negative Z slope
		Vector2(0.9, -1.1),   # diagonal slope
		Vector2(-0.4, 0.3),   # diagonal slope
	]
	var normals := PackedVector3Array()
	for slope: Vector2 in slopes:
		normals.append(Vector3(-slope.x, 1.0, -slope.y).normalized())

	var tangents := TerrainSurfaceMaterial.build_top_surface_tangents(normals)
	_check(tangents.size() == normals.size() * 4, "four floats per vertex")

	var all_finite := true
	var all_unit := true
	var all_orthogonal := true
	var all_handed := true
	var all_dpdu := true
	for i in normals.size():
		var n := normals[i]
		var t := Vector3(tangents[4 * i], tangents[4 * i + 1], tangents[4 * i + 2])
		var w := tangents[4 * i + 3]
		if not (t.is_finite() and is_finite(w)):
			all_finite = false
		if absf(t.length() - 1.0) > 1e-6:
			all_unit = false
		if absf(t.dot(n)) > 1e-6:
			all_orthogonal = false
		# Handedness: w = +1, and the reconstructed binormal cross(N, T) * w
		# must point along the true dP/dv ∝ (0, nz/ny, -1) direction.
		var dpdv := Vector3(0.0, n.z / n.y, -1.0)
		if w != 1.0 or Vector3(n).cross(t).dot(dpdv) <= 0.0:
			all_handed = false
		# The tangent must be the true dP/du ∝ (1, -nx/ny, 0) of the locked
		# planar mapping on this slope (not a skewed constant axis).
		var dpdu := Vector3(1.0, -n.x / n.y, 0.0).normalized()
		if not t.is_equal_approx(dpdu):
			all_dpdu = false
	_check(all_finite, "tangents finite on every slope")
	_check(all_unit, "tangents unit length on every slope")
	_check(all_orthogonal, "tangents orthogonal to the smooth normal (<= 1e-6)")
	_check(all_handed, "w = +1 and binormal matches dP/dv on every slope")
	_check(all_dpdu, "tangent equals the true dP/du of the locked UV mapping")

	var again := TerrainSurfaceMaterial.build_top_surface_tangents(normals)
	_check(again == tangents, "tangent build is deterministic (bit-identical)")

	var degenerate := TerrainSurfaceMaterial.build_top_surface_tangents(
		PackedVector3Array([Vector3(0.0, 0.0, 1.0)])
	)
	var dt := Vector3(degenerate[0], degenerate[1], degenerate[2])
	_check(
		dt.is_finite() and absf(dt.length() - 1.0) <= 1e-6 and absf(dt.z) <= 1e-6,
		"degenerate ±Z normal falls back to a finite unit tangent"
	)


func _test_texture_and_shader_binding() -> void:
	print("--- texture and shader binding ---")
	_check(TerrainSurfaceMaterial.TEXTURE_PATHS.size() == 9, "nine texture maps declared")
	var files_exist := true
	for param: String in TerrainSurfaceMaterial.TEXTURE_PATHS.keys():
		var path: String = TerrainSurfaceMaterial.TEXTURE_PATHS[param]
		if not FileAccess.file_exists(path):
			files_exist = false
			print("missing texture: %s" % path)
	_check(files_exist, "all nine source PNGs exist (unmoved prototype assets)")

	var material := TerrainSurfaceMaterial.create_material()
	_check(material != null, "material creates")
	if material == null:
		return
	_check(
		material.shader != null
		and material.shader.resource_path == TerrainSurfaceMaterial.SHADER_PATH,
		"shader bound from %s" % TerrainSurfaceMaterial.SHADER_PATH
	)
	var all_bound := true
	var all_mipmapped := true
	for param: String in TerrainSurfaceMaterial.TEXTURE_PATHS.keys():
		var texture: Variant = material.get_shader_parameter(param)
		if not (texture is Texture2D) or texture.get_width() <= 0:
			all_bound = false
			continue
		var image: Image = texture.get_image()
		if image == null or not image.has_mipmaps():
			all_mipmapped = false
	_check(all_bound, "all nine texture uniforms bound to loaded textures")
	_check(all_mipmapped, "textures carry generated mipmaps for mipmapped sampling")

	# The shader must sample albedo as sRGB and offer repeating mipmapped
	# sampling; normal/roughness stay linear (no source_color).
	var code: String = material.shader.code
	for albedo_param in ["ground_albedo_tex", "ash_albedo_tex", "stone_albedo_tex"]:
		_check(
			code.contains("uniform sampler2D %s : source_color, repeat_enable, filter_linear_mipmap;" % albedo_param),
			"%s sampled as sRGB with repeat + mipmaps" % albedo_param
		)
	for linear_param in [
		"ground_normal_tex", "ground_roughness_tex",
		"ash_normal_tex", "ash_roughness_tex",
		"stone_normal_tex", "stone_roughness_tex",
	]:
		_check(
			code.contains("uniform sampler2D %s : repeat_enable, filter_linear_mipmap;" % linear_param),
			"%s sampled as linear data with repeat + mipmaps" % linear_param
		)


func _test_locked_parameters() -> void:
	print("--- locked baseline parameters (deterministic mask inputs) ---")
	var material := TerrainSurfaceMaterial.create_material()
	if material == null:
		_check(false, "material creates for parameter checks")
		return
	_check(
		TerrainSurfaceMaterial.BASELINE_PARAMETERS.size() == EXPECTED_LOCKED_PARAMETERS.size(),
		"baseline parameter set is complete"
	)
	for param: String in EXPECTED_LOCKED_PARAMETERS.keys():
		var expected: Variant = EXPECTED_LOCKED_PARAMETERS[param]
		var actual: Variant = material.get_shader_parameter(param)
		var matches: bool
		if expected is Vector3:
			matches = actual is Vector3 and actual.is_equal_approx(expected)
		else:
			matches = actual != null and is_equal_approx(float(actual), float(expected))
		_check(matches, "locked parameter %s = %s" % [param, str(expected)])
	# USE_FINE_DETAIL = false is locked: the shader must not modulate albedo
	# with the fine noise (fine noise feeds only roughness variation + bump).
	var code: String = material.shader.code
	_check(
		not code.contains("fine_tint") and not code.contains("fine_detail"),
		"no fine-detail albedo path in the shader (USE_FINE_DETAIL locked false)"
	)


func _test_debug_stages() -> void:
	print("--- debug stages ---")
	var expected_stages := {"final": 0, "ash_mask": 1, "stone_mask": 2, "albedo": 3}
	_check(
		TerrainSurfaceMaterial.DEBUG_STAGES == expected_stages,
		"stage set: final, ash_mask, stone_mask, albedo"
	)
	var material := TerrainSurfaceMaterial.create_material()
	if material == null:
		_check(false, "material creates for stage checks")
		return
	for stage: String in expected_stages.keys():
		var ok := TerrainSurfaceMaterial.set_debug_stage(material, stage)
		_check(
			ok and int(material.get_shader_parameter("debug_stage")) == expected_stages[stage],
			"stage '%s' sets debug_stage = %d" % [stage, expected_stages[stage]]
		)
	_check(
		not TerrainSurfaceMaterial.set_debug_stage(material, "nonsense"),
		"unknown stage is rejected"
	)
	var stage_material := TerrainSurfaceMaterial.create_material("stone_mask")
	_check(
		stage_material != null
		and int(stage_material.get_shader_parameter("debug_stage")) == 2,
		"create_material honors the requested stage"
	)


func _test_deterministic_creation() -> void:
	print("--- deterministic creation ---")
	var a := TerrainSurfaceMaterial.create_material()
	var b := TerrainSurfaceMaterial.create_material()
	if a == null or b == null:
		_check(false, "both materials create")
		return
	var params_equal := true
	for param: String in TerrainSurfaceMaterial.BASELINE_PARAMETERS.keys():
		if a.get_shader_parameter(param) != b.get_shader_parameter(param):
			params_equal = false
	_check(params_equal, "two independent materials carry identical mask inputs")
	var textures_shared := true
	for param: String in TerrainSurfaceMaterial.TEXTURE_PATHS.keys():
		if a.get_shader_parameter(param) != b.get_shader_parameter(param):
			textures_shared = false
	_check(textures_shared, "texture cache returns the same texture instances")


func _check(condition: bool, label: String) -> void:
	_total += 1
	if condition:
		print("PASS ", label)
	else:
		_any_fail = true
		print("FAIL ", label)


func _finish() -> void:
	print("TerrainSurfaceMaterial tests: %d checks" % _total)
	if _any_fail:
		print("FAIL")
		quit(1)
	else:
		print("PASS")
		quit(0)
