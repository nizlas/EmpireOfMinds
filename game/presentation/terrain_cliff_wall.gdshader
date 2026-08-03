// N3c.3b cliff-wall stone PBR (presentation-side).
//
// Godot port of the accepted TS-08 Stage-3a cliff-wall stone material
// (TS08_Cliff_Wall_Stone) in
// tools/blender/terrain/eom_terrain_ts08_cliff_wall_stone_material.py.
// Locked baseline values are exposed as uniforms with the Blender defaults;
// game/presentation/terrain_cliff_wall_material.gd sets them explicitly so
// tests can verify the locked baseline.
//
// Structure (locked, mirroring the Blender node graph):
// - the three existing stone prototype textures sample the wall-local UV
//   baked into the mesh (U = dot(world XZ, wall tangent) * 0.35,
//   V = world Y * 0.35; repeat + mipmapped sampling via sampler hints;
//   never normalized or restarted per face);
// - albedo = stone albedo * 0.55 (MixColor MULTIPLY with a 0.55 gray, factor
//   1.0, multiplied in linear space after the sRGB decode — same as Blender);
// - roughness = sampled stone roughness map (the Blender Principled default
//   of 0.88 is the unlinked-socket fallback; the map is always linked/bound,
//   so the fallback uniform is declared for the locked contract but inert,
//   exactly like the Blender node default);
// - tangent-space normal map with strength 0.55 (Blender Normal Map node
//   semantics: mix toward the flat tangent-space up vector, then normalize —
//   the same port used by the accepted N3c.3a top-surface shader);
// - Metallic 0, Specular IOR Level 0.25.
//
// Reported implementation differences vs Blender (no visual retune):
// - Blender's "Specular IOR Level" maps linearly to F0 (0.08 * level, so
//   0.25 -> 0.02); Godot's SPECULAR maps quadratically (0.16 * s^2, so
//   0.25 -> 0.01). The locked 0.25 value is preserved as-is.
// - Blender's implicit color->float conversion for the roughness link
//   averages RGB; the stone roughness map is grayscale, so sampling .r is
//   equivalent (same note as the N3c.3a top-surface port).
// - Blender renders with mikktspace tangents from the wall UV layer; the
//   mesh bakes the exact per-face dP/du orthogonalized against the flat face
//   normal (equivalent up to the mikktspace approximation).
//
// Debug stages stay synchronized with the top-surface material:
// 0 final (wall stone PBR), 1 ash_mask (walls black), 2 stone_mask (walls
// white, lighting-independent), 3 albedo (wall albedo only).
shader_type spatial;
render_mode cull_disabled;

// Three locked stone maps (the same prototype textures the top surface
// uses, in place). Albedo is sRGB; normal and roughness data are linear.
uniform sampler2D stone_albedo_tex : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D stone_normal_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D stone_roughness_tex : repeat_enable, filter_linear_mipmap;

// Debug stage selector, synchronized with terrain_top_surface.gdshader.
uniform int debug_stage = 0;

// --- Locked Stage-3a baseline (eom_terrain_ts08_cliff_wall_stone_material) ---
// UV scales are baked into the mesh UVs; declared here as the locked contract.
uniform float wall_uv_u_scale = 0.35;
uniform float wall_uv_v_scale = 0.35;
uniform float wall_albedo_multiplier = 0.55;
uniform float wall_normal_strength = 0.55;
uniform float wall_metallic = 0.0;
uniform float wall_specular_ior_level = 0.25;
// Blender Principled Roughness default; overridden by the always-linked map.
uniform float wall_roughness_fallback = 0.88;


void fragment() {
	// Wall-local UV baked into the mesh (never re-normalized per face).
	vec2 uv = UV;

	vec3 albedo = texture(stone_albedo_tex, uv).rgb * wall_albedo_multiplier;
	float rough = clamp(texture(stone_roughness_tex, uv).r, 0.0, 1.0);
	vec3 n_ts = normalize(mix(
		vec3(0.0, 0.0, 1.0), texture(stone_normal_tex, uv).xyz * 2.0 - 1.0,
		wall_normal_strength
	));

	METALLIC = wall_metallic;
	SPECULAR = wall_specular_ior_level;
	if (debug_stage == 1) {
		// Ash mask stage: walls carry no ash — render black.
		ALBEDO = vec3(0.0);
		ROUGHNESS = 1.0;
		EMISSION = vec3(0.0);
	} else if (debug_stage == 2) {
		// Stone mask stage: walls are pure stone — lighting-independent white.
		ALBEDO = vec3(0.0);
		ROUGHNESS = 1.0;
		EMISSION = vec3(1.0);
	} else if (debug_stage == 3) {
		// Albedo-only: multiplied wall albedo, flat normal, uniform roughness.
		ALBEDO = albedo;
		ROUGHNESS = 1.0;
	} else {
		ALBEDO = albedo;
		ROUGHNESS = rough;
		mat3 tbn = mat3(normalize(TANGENT), normalize(BINORMAL), normalize(NORMAL));
		NORMAL = normalize(tbn * n_ts);
	}
}
