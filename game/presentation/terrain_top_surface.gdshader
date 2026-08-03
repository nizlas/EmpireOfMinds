// N3c.3a terrain top-surface three-layer PBR splatting (presentation-side).
//
// Godot port of the approved Blender porting baseline (2026-06-15) in
// tools/blender/terrain/generate_terrain_single_patch_pbr_ground_stone_ash_prototype.py
// (see the "Approved Blender porting baseline" section of
// tools/blender/terrain/README.md). Locked parameters are exposed as uniforms
// with the baseline defaults; game/presentation/terrain_surface_material.gd
// sets them explicitly so tests can verify the locked values.
//
// Structure (locked):
// - all nine textures sample one shared world-anchored UV
//   (u, v) = (x * 0.35, -z * 0.35), continuous across the whole mesh,
//   never normalized per map/chunk/hex (UV attribute baked by presentation
//   mesh assembly; repeat + mipmapped sampling via sampler hints);
// - masks are world-anchored: noise fields sample the world position mapped
//   to Blender object coordinates (x_b, y_b, z_b) = (x, -z, y);
// - ash chain: broad regional noise (scale 0.18, linear 0.35/0.65 remap)
//   -> medium breakup (scale 0.75, smootherstep 0.35/0.75 remap, strength
//   0.75) -> final smootherstep 0.30/0.95 ash-weight remap;
// - stone chain: smooth-geometry-normal slope mask (linear 0.96/0.90
//   thresholds) with breakup strength 0.080 perturbing the normal's up
//   component; applied after the ground/ash blend;
// - the same layer weight drives albedo, normal, and roughness;
// - fine-detail albedo modulation stays disabled (USE_FINE_DETAIL = false in
//   the baseline; no such path exists in this shader). The fine noise field
//   only feeds ground roughness variation and the procedural bump, as in the
//   baseline graph.
//
// Reported implementation differences vs Blender (structure/scales/seed kept,
// no visual retune):
// - Blender's Noise Texture hash cannot be reproduced exactly; this shader
//   uses a deterministic hash-based 3D Perlin fBm with Blender's
//   fractal_noise octave/roughness/lacunarity-2 structure and one fixed seed
//   shared by all four noise fields (Blender likewise has a single implicit
//   seed). Fields are world-anchored and deterministic but not bit-identical
//   to Blender's.
// - Blender's Bump node derivatives are ported with screen-space
//   derivatives (dFdx/dFdy) of the same world-anchored height field.
// - Blender's implicit color->float conversion averages RGB; the roughness
//   maps are grayscale, so sampling .r is equivalent.
shader_type spatial;
render_mode cull_disabled;

// Nine locked texture maps. Albedo is sRGB (source_color); normal and
// roughness data are linear. Repeating mipmapped sampling per the baseline.
uniform sampler2D ground_albedo_tex : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D ground_normal_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D ground_roughness_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D ash_albedo_tex : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D ash_normal_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D ash_roughness_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D stone_albedo_tex : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D stone_normal_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D stone_roughness_tex : repeat_enable, filter_linear_mipmap;

// Debug stage selector (dev preview): 0 final, 1 ash mask, 2 stone mask,
// 3 albedo-only (blended albedo, flat geometry normal, roughness 1).
// Masks render as lighting-independent emission grayscale.
uniform int debug_stage = 0;

// --- Locked baseline parameters (APPROVED_BLENDER_PORTING_BASELINE) ---
uniform float world_uv_scale = 0.35;
uniform vec3 ground_base_color = vec3(0.08, 0.11, 0.045);
uniform float ground_albedo_tint_strength = 0.15;
uniform float ground_normal_strength = 0.65;
uniform float ground_roughness_multiplier = 1.0;
uniform float ground_roughness_variation_strength = 0.08;
uniform float ash_normal_strength = 0.55;
uniform float ash_roughness_multiplier = 1.0;
uniform float stone_albedo_multiplier = 0.55;
uniform float stone_normal_strength = 0.65;
uniform float stone_roughness_multiplier = 1.0;
// Regional ash source: large noise -> linear 0.35/0.65 remap.
uniform float large_noise_scale = 0.18;
uniform float large_noise_detail = 4.0;
uniform float large_noise_roughness = 0.45;
uniform float large_factor_from_min = 0.35;
uniform float large_factor_from_max = 0.65;
// Ash breakup: medium noise -> smootherstep 0.35/0.75 remap, strength mix.
uniform float ash_breakup_noise_scale = 0.75;
uniform float ash_breakup_noise_detail = 2.0;
uniform float ash_breakup_noise_roughness = 0.55;
uniform float ash_breakup_min = 0.35;
uniform float ash_breakup_max = 0.75;
uniform float ash_breakup_strength = 0.75;
// Final ash-weight remap (smootherstep, approved 0.30/0.95).
uniform float ash_weight_input_min = 0.30;
uniform float ash_weight_input_max = 0.95;
// Stone slope mask thresholds on the smooth-normal up component.
uniform float slope_blend_start = 0.96;
uniform float slope_blend_end = 0.90;
uniform float stone_breakup_noise_scale = 2.0;
uniform float stone_breakup_noise_detail = 1.0;
uniform float stone_breakup_noise_roughness = 1.0;
uniform float stone_breakup_strength = 0.080;
// Fine noise: ground roughness variation + procedural bump height only.
uniform float fine_noise_scale = 2.8;
uniform float fine_noise_detail = 8.0;
uniform float fine_noise_roughness = 0.55;
uniform float bump_strength = 0.12;
uniform float bump_distance = 0.02;
// Single fixed seed shared by all noise fields (deterministic, world-anchored).
uniform float noise_seed = 0.0;

varying vec3 v_world_pos;
varying vec3 v_world_smooth_normal;


// Deterministic hash -> gradient in [-1, 1]^3 (seeded, world-anchored).
vec3 eom_hash33(vec3 p, float seed) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973) + seed);
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx) * 2.0 - 1.0;
}


// 3D gradient Perlin noise with quintic fade; output roughly in [-1, 1].
float eom_perlin(vec3 p, float seed) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float n000 = dot(eom_hash33(i + vec3(0.0, 0.0, 0.0), seed), f - vec3(0.0, 0.0, 0.0));
	float n100 = dot(eom_hash33(i + vec3(1.0, 0.0, 0.0), seed), f - vec3(1.0, 0.0, 0.0));
	float n010 = dot(eom_hash33(i + vec3(0.0, 1.0, 0.0), seed), f - vec3(0.0, 1.0, 0.0));
	float n110 = dot(eom_hash33(i + vec3(1.0, 1.0, 0.0), seed), f - vec3(1.0, 1.0, 0.0));
	float n001 = dot(eom_hash33(i + vec3(0.0, 0.0, 1.0), seed), f - vec3(0.0, 0.0, 1.0));
	float n101 = dot(eom_hash33(i + vec3(1.0, 0.0, 1.0), seed), f - vec3(1.0, 0.0, 1.0));
	float n011 = dot(eom_hash33(i + vec3(0.0, 1.0, 1.0), seed), f - vec3(0.0, 1.0, 1.0));
	float n111 = dot(eom_hash33(i + vec3(1.0, 1.0, 1.0), seed), f - vec3(1.0, 1.0, 1.0));
	return mix(
		mix(mix(n000, n100, u.x), mix(n010, n110, u.x), u.y),
		mix(mix(n001, n101, u.x), mix(n011, n111, u.x), u.y),
		u.z
	);
}


// Blender fractal_noise structure: lacunarity 2, per-octave amplitude
// `roughness`, fractional final octave blended by the detail remainder.
float eom_fractal_noise(vec3 p, float detail, float noise_roughness, float seed) {
	float fscale = 1.0;
	float amp = 1.0;
	float maxamp = 0.0;
	float sum = 0.0;
	float octaves = clamp(detail, 0.0, 15.0);
	int n = int(octaves);
	for (int i = 0; i <= n; i++) {
		sum += eom_perlin(fscale * p, seed) * amp;
		maxamp += amp;
		amp *= noise_roughness;
		fscale *= 2.0;
	}
	float rmd = octaves - floor(octaves);
	if (rmd > 0.0) {
		float sum2 = sum + eom_perlin(fscale * p, seed) * amp;
		return mix(sum / maxamp, sum2 / (maxamp + amp), rmd);
	}
	return sum / maxamp;
}


// Blender Noise Texture Fac output (normalized to [0, 1]).
float eom_noise_fac(vec3 p, float scale, float detail, float noise_roughness, float seed) {
	return 0.5 + 0.5 * eom_fractal_noise(p * scale, detail, noise_roughness, seed);
}


// Blender Map Range (LINEAR, clamped).
float eom_map_linear(float v, float from_min, float from_max, float to_min, float to_max) {
	float t = clamp((v - from_min) / (from_max - from_min), 0.0, 1.0);
	return mix(to_min, to_max, t);
}


// Blender Map Range (SMOOTHERSTEP, clamped) — used by both ash remaps.
float eom_map_smootherstep(float v, float from_min, float from_max, float to_min, float to_max) {
	float t = clamp((v - from_min) / (from_max - from_min), 0.0, 1.0);
	t = t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
	return mix(to_min, to_max, t);
}


void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_smooth_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
}


void fragment() {
	// Shared world-anchored UV baked into the mesh (never re-normalized).
	vec2 uv = UV;
	// World position in Blender object coordinates (terrain sits at origin).
	vec3 bpos = vec3(v_world_pos.x, -v_world_pos.z, v_world_pos.y);

	// --- Ash weight: regional noise -> medium breakup -> 0.30/0.95 remap ---
	float large_fac = eom_noise_fac(
		bpos, large_noise_scale, large_noise_detail, large_noise_roughness, noise_seed
	);
	float ash_regional = eom_map_linear(
		large_fac, large_factor_from_min, large_factor_from_max, 0.0, 1.0
	);
	float breakup_fac = eom_noise_fac(
		bpos, ash_breakup_noise_scale, ash_breakup_noise_detail,
		ash_breakup_noise_roughness, noise_seed
	);
	float ash_breakup = eom_map_smootherstep(
		breakup_fac, ash_breakup_min, ash_breakup_max, 0.0, 1.0
	);
	float effective_breakup = mix(1.0, ash_breakup, ash_breakup_strength);
	float ash_combined = ash_regional * effective_breakup;
	float ash_w = eom_map_smootherstep(
		ash_combined, ash_weight_input_min, ash_weight_input_max, 0.0, 1.0
	);

	// --- Stone weight: smooth-normal slope mask + breakup (0.96/0.90, 0.080) ---
	// Blender reads the smooth geometry normal's Z (up); Godot up is +Y.
	float smooth_up = normalize(v_world_smooth_normal).y;
	float stone_breakup_fac = eom_noise_fac(
		bpos, stone_breakup_noise_scale, stone_breakup_noise_detail,
		stone_breakup_noise_roughness, noise_seed
	);
	float effective_up = smooth_up + (stone_breakup_fac - 0.5) * 2.0 * stone_breakup_strength;
	float stone_w = eom_map_linear(effective_up, slope_blend_end, slope_blend_start, 1.0, 0.0);

	// --- Albedo: ground/ash blend first, stone applied afterward ---
	vec3 g_albedo = mix(
		texture(ground_albedo_tex, uv).rgb, ground_base_color, ground_albedo_tint_strength
	);
	vec3 a_albedo = texture(ash_albedo_tex, uv).rgb;
	vec3 s_albedo = texture(stone_albedo_tex, uv).rgb * stone_albedo_multiplier;
	vec3 albedo = mix(mix(g_albedo, a_albedo, ash_w), s_albedo, stone_w);

	// --- Roughness: same weights; ground carries the fine-noise variation ---
	float fine_fac = eom_noise_fac(
		bpos, fine_noise_scale, fine_noise_detail, fine_noise_roughness, noise_seed
	);
	float g_rough = clamp(
		texture(ground_roughness_tex, uv).r * ground_roughness_multiplier
			+ (fine_fac - 0.5) * ground_roughness_variation_strength * 2.0,
		0.0, 1.0
	);
	float a_rough = clamp(texture(ash_roughness_tex, uv).r * ash_roughness_multiplier, 0.0, 1.0);
	float s_rough = clamp(
		texture(stone_roughness_tex, uv).r * stone_roughness_multiplier, 0.0, 1.0
	);
	float rough = mix(mix(g_rough, a_rough, ash_w), s_rough, stone_w);

	// --- Normals: per-layer strength (Blender Normal Map node), same weights ---
	vec3 g_n = normalize(mix(
		vec3(0.0, 0.0, 1.0), texture(ground_normal_tex, uv).xyz * 2.0 - 1.0,
		ground_normal_strength
	));
	vec3 a_n = normalize(mix(
		vec3(0.0, 0.0, 1.0), texture(ash_normal_tex, uv).xyz * 2.0 - 1.0,
		ash_normal_strength
	));
	vec3 s_n = normalize(mix(
		vec3(0.0, 0.0, 1.0), texture(stone_normal_tex, uv).xyz * 2.0 - 1.0,
		stone_normal_strength
	));
	vec3 blended_ts = mix(mix(g_n, a_n, ash_w), s_n, stone_w);
	mat3 tbn = mat3(normalize(TANGENT), normalize(BINORMAL), normalize(NORMAL));
	vec3 n_base = normalize(tbn * blended_ts);

	// --- Procedural bump (Blender Bump node, screen-space derivative port) ---
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	float dhdx = dFdx(fine_fac);
	float dhdy = dFdy(fine_fac);
	vec3 r1 = cross(dpdy, n_base);
	vec3 r2 = cross(n_base, dpdx);
	float det = dot(dpdx, r1);
	vec3 surfgrad = dhdx * r1 + dhdy * r2;
	vec3 n_bumped = normalize(abs(det) * n_base - bump_distance * sign(det) * surfgrad);
	vec3 n_final = normalize(mix(n_base, n_bumped, bump_strength));

	METALLIC = 0.0;
	SPECULAR = 0.5;
	if (debug_stage == 1) {
		// Ash mask, lighting-independent (Blender Emission diagnostic style).
		ALBEDO = vec3(0.0);
		ROUGHNESS = 1.0;
		EMISSION = vec3(ash_w);
	} else if (debug_stage == 2) {
		// Stone mask, lighting-independent.
		ALBEDO = vec3(0.0);
		ROUGHNESS = 1.0;
		EMISSION = vec3(stone_w);
	} else if (debug_stage == 3) {
		// Albedo-only: blended albedo, flat geometry normal, uniform roughness.
		ALBEDO = albedo;
		ROUGHNESS = 1.0;
	} else {
		ALBEDO = albedo;
		ROUGHNESS = rough;
		NORMAL = n_final;
	}
}
