# N3c.3a presentation-side terrain top-surface material (three-layer PBR
# splatting). Reusable by the dev terrain preview and later presentation
# consumers; materials and shaders stay out of the domain layer.
#
# Ports the approved Blender porting baseline (2026-06-15) from
# tools/blender/terrain/generate_terrain_single_patch_pbr_ground_stone_ash_prototype.py
# (see "Approved Blender porting baseline" in tools/blender/terrain/README.md).
# BASELINE_PARAMETERS mirrors APPROVED_BLENDER_PORTING_BASELINE; every value is
# set explicitly on the material so tests can verify the locked baseline.
#
# The nine source textures are the existing prototype assets (unmoved,
# unduplicated, untouched). They are loaded directly from the PNGs with
# generated mipmaps, so no Godot import step or .import churn is required and
# headless test runs work on a clean checkout. Albedo maps are sRGB
# (source_color sampler hint in the shader); normal/roughness maps are linear.
#
# World-anchored UV contract (locked): (u, v) = (x * 0.35, -z * 0.35) in Godot
# world space, continuous across the entire mesh, never normalized per map,
# chunk, or hex. This equals Blender's EOM_WorldUV layer
# (U = x_b * 0.35, V = y_b * 0.35) under the Blender->Godot axis mapping
# (x_b, y_b) = (x, -z).
#
# Tangent basis: the top surface is a height field y = h(x, z) under this
# planar mapping, so the exact UV-gradient tangent is
#   dP/du = (1/s, h_x/s, 0) ∝ (1, h_x, 0),  h_x = -nx/ny
# for the smooth vertex normal N = (nx, ny, nz) (up-facing, ny > 0), i.e.
#   T = normalize(ny, -nx, 0)
# which is exactly orthogonal to N (dot = nx*ny - nx*ny = 0). The bitangent
# dP/dv ∝ (0, nz/ny, -1) satisfies dot(cross(N, T), dP/dv) = 1/ny > 0, so the
# handedness is w = +1 on every up-facing vertex, and Godot's
# BINORMAL = cross(NORMAL, TANGENT) * w reconstructs an orthonormal frame.
# This is the deterministic exact equivalent of SurfaceTool.generate_tangents()
# for this parameterization (MikkTSpace approximates the same dP/du per face,
# then orthogonalizes against the vertex normal) and it preserves vertex order
# and topology.
#
# Fine-detail albedo modulation stays disabled (USE_FINE_DETAIL = false is
# locked in the baseline): the shader has no such path.
extends RefCounted

const SHADER_PATH := "res://presentation/terrain_top_surface.gdshader"

const TEXTURE_BASE := "res://assets/prototype/3d/terrain/prototype_3d_terrain/source/materials"
# Shader sampler parameter -> existing prototype texture (nine maps total).
const TEXTURE_PATHS := {
	"ground_albedo_tex": TEXTURE_BASE + "/ground/ground_albedo.png",
	"ground_normal_tex": TEXTURE_BASE + "/ground/ground_normal.png",
	"ground_roughness_tex": TEXTURE_BASE + "/ground/ground_roughness.png",
	"ash_albedo_tex": TEXTURE_BASE + "/ash/ash_albedo.png",
	"ash_normal_tex": TEXTURE_BASE + "/ash/ash_normal.png",
	"ash_roughness_tex": TEXTURE_BASE + "/ash/ash_roughness.png",
	"stone_albedo_tex": TEXTURE_BASE + "/stone/stone_albedo.png",
	"stone_normal_tex": TEXTURE_BASE + "/stone/stone_normal.png",
	"stone_roughness_tex": TEXTURE_BASE + "/stone/stone_roughness.png",
}

const WORLD_UV_SCALE := 0.35

# Locked baseline shader parameters (Godot port of the approved
# APPROVED_BLENDER_PORTING_BASELINE values). Deterministic mask inputs:
# fixed scales, remaps, strengths, and one fixed noise seed.
const BASELINE_PARAMETERS := {
	"world_uv_scale": WORLD_UV_SCALE,
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

# Preview-selectable material debug stages -> debug_stage uniform value.
const DEBUG_STAGES := {
	"final": 0,
	"ash_mask": 1,
	"stone_mask": 2,
	"albedo": 3,
}

static var _texture_cache: Dictionary = {}


static func create_material(stage: String = "final") -> ShaderMaterial:
	var shader: Shader = load(SHADER_PATH)
	if shader == null:
		push_error("TerrainSurfaceMaterial: failed to load shader at %s" % SHADER_PATH)
		return null
	var material := ShaderMaterial.new()
	material.shader = shader
	for param: String in BASELINE_PARAMETERS.keys():
		material.set_shader_parameter(param, BASELINE_PARAMETERS[param])
	for param: String in TEXTURE_PATHS.keys():
		var texture := load_world_texture(TEXTURE_PATHS[param])
		if texture == null:
			return null
		material.set_shader_parameter(param, texture)
	if not set_debug_stage(material, stage):
		return null
	return material


static func set_debug_stage(material: ShaderMaterial, stage: String) -> bool:
	if not DEBUG_STAGES.has(stage):
		push_error(
			"TerrainSurfaceMaterial: unknown debug stage '%s' (valid: %s)"
			% [stage, ", ".join(DEBUG_STAGES.keys())]
		)
		return false
	material.set_shader_parameter("debug_stage", DEBUG_STAGES[stage])
	return true


# Loads a source PNG directly (no importer dependency) and generates mipmaps
# for the shader's filter_linear_mipmap sampling. Cached per path.
static func load_world_texture(path: String) -> Texture2D:
	if _texture_cache.has(path):
		return _texture_cache[path]
	var global_path := ProjectSettings.globalize_path(path)
	var image := Image.load_from_file(global_path)
	if image == null:
		push_error("TerrainSurfaceMaterial: failed to load texture %s" % path)
		return null
	image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	_texture_cache[path] = texture
	return texture


# Locked world-anchored UV mapping (never normalized per map/chunk/hex).
static func world_uv(position: Vector3) -> Vector2:
	return Vector2(position.x * WORLD_UV_SCALE, -position.z * WORLD_UV_SCALE)


static func build_world_uv_array(positions: PackedVector3Array) -> PackedVector2Array:
	var uvs := PackedVector2Array()
	uvs.resize(positions.size())
	for i in positions.size():
		uvs[i] = world_uv(positions[i])
	return uvs


# Slope-aware orthonormal tangents from the smooth vertex normals: the exact
# dP/du of the locked planar world UV on the height surface,
# T = normalize(ny, -nx, 0), w = +1 (see the tangent-basis derivation in the
# header). Orthogonal to the smooth normal by construction on every vertex,
# including slopes in X and Z. Deterministic: a pure per-vertex function of
# the (deterministic) geometry normals.
static func build_top_surface_tangents(normals: PackedVector3Array) -> PackedFloat32Array:
	var tangents := PackedFloat32Array()
	tangents.resize(normals.size() * 4)
	for i in normals.size():
		var n := normals[i]
		var t := Vector3(n.y, -n.x, 0.0)
		var len_sq := t.length_squared()
		if len_sq > 0.0:
			t /= sqrt(len_sq)
		else:
			# Degenerate (normal along ±Z, so nx = ny = 0; cannot occur on
			# the Y-up top surface): project +X onto the tangent plane.
			t = (Vector3(1.0, 0.0, 0.0) - n * n.x).normalized()
		tangents[4 * i] = t.x
		tangents[4 * i + 1] = t.y
		tangents[4 * i + 2] = t.z
		tangents[4 * i + 3] = 1.0
	return tangents
