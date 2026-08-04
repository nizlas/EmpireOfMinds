# N3c.7 production terrain lighting rig (presentation/integration-side).
#
# The single deterministic lighting/environment implementation for the shared
# runtime terrain world (terrain_world.gd). Every entry that shows the
# terrain — the dev runtime harness, the dev inspection preview, and the
# future server-fed gameplay world — receives this exact rig through
# TerrainWorld; dev scenes must never add their own competing lights or
# environments.
#
# Rig design (all values locked constants; the only input is the generated
# terrain AABB, used for the map-relative shadow range — same pattern as the
# orbit camera's map-relative zoom):
# - SunLight: warm key DirectionalLight3D with PSSM shadows. Elevation
#   50 deg is the ACCEPTED gameplay lighting (terrain brightness, shadow
#   direction and strategic readability) — never move this light to make
#   the sky's decorative sun disc visible (the disc may sit high or outside
#   normal framing; that is fine for the interim sky). Blended 4 splits +
#   slight angular size soften the cascade edges; bias/normal-bias are
#   tuned down from the Godot defaults for the ~1-unit hex scale (defaults
#   visibly detach small terrain shadows).
# - FillLight: cool shadowless fill opposing the sun azimuth so
#   sun-shadowed faces and away-facing cliff walls stay readable (never
#   crushed to ambient black); specular 0 so there is exactly one visible
#   highlight direction.
# - WorldEnvironment: INTERIM daytime ProceduralSkyMaterial backdrop (not
#   a final art-direction lock): muted natural blue above, lighter blue at
#   the horizon, friendlier than the old dark-grey backdrop. The upper and
#   lower hemispheres share EXACTLY the same horizon color (single
#   HORIZON_COLOR constant) so the mathematical hemisphere boundary has no
#   seam from any camera pitch; below it the backdrop fades gradually
#   (wide ground curve) to the earlier subdued dark tone. Terrain lighting
#   itself keeps the accepted N3c.7 mix: flat cool ambient (NOT
#   sky-sampled, so the material appearance does not shift with the
#   backdrop) and Filmic tonemapping so the summed key+fill+ambient light
#   rolls off instead of clipping the bright ash splat layer to white.
#   Known engine behavior: the procedural sky draws a glow for every
#   DirectionalLight3D, so the shadowless fill contributes a faint smudge;
#   SUN_ANGLE_MAX_DEG keeps both glows tight and the fill one negligible.
#
# Deliberately NOT here: cloud assets/shaders, sky textures, volumetric
# fog/fog, weather, time-of-day, SSAO/SSIL, glow, per-map tuning, or any
# gameplay/overlay concern.
extends RefCounted

const RIG_NAME := "TerrainLighting"
const SUN_NAME := "SunLight"
const FILL_NAME := "FillLight"
const ENVIRONMENT_NAME := "WorldEnvironment"

# Key light (sun): the accepted N3c.7 production values.
const SUN_ROTATION_DEGREES := Vector3(-50.0, -32.5, 0.0)
const SUN_COLOR := Color(1.0, 0.972, 0.925)
const SUN_ENERGY := 1.55
const SUN_ANGULAR_DISTANCE_DEG := 0.75
const SHADOW_BIAS := 0.03
const SHADOW_NORMAL_BIAS := 1.2
# Shadow range is map-relative: covers the whole map from the farthest
# orbit-camera zoom (3.0 x extent) plus the far map half, with headroom.
const SHADOW_MAX_DISTANCE_FACTOR := 3.6

# Fill light (sky-side counter light, no shadows, no specular). Azimuth
# opposes the sun (-32.5 + 180 = 147.5) so shadowed faces keep their lift.
const FILL_ROTATION_DEGREES := Vector3(-38.0, 147.5, 0.0)
const FILL_COLOR := Color(0.82, 0.87, 0.95)
const FILL_ENERGY := 0.45

# Environment: interim daytime procedural sky (deterministic constants,
# NOT a final art-direction lock). Both hemispheres reference the single
# HORIZON_COLOR so the horizon boundary is seamless by construction; below
# it the backdrop shows a broad, clearly visible fade (ground curve 0.02)
# from the light horizon blue through darker blue-grey to the subdued dark
# bottom tone — no line or ring around the small floating map.
const SKY_TOP_COLOR := Color(0.29, 0.45, 0.67)
const HORIZON_COLOR := Color(0.58, 0.68, 0.8)
const SKY_HORIZON_COLOR := HORIZON_COLOR
const GROUND_HORIZON_COLOR := HORIZON_COLOR
const SKY_CURVE := 0.1
const GROUND_BOTTOM_COLOR := Color(0.24, 0.27, 0.31)
const GROUND_CURVE := 0.02
const SUN_ANGLE_MAX_DEG := 8.0
const SUN_CURVE := 0.2

const AMBIENT_COLOR := Color(0.72, 0.76, 0.84)
const AMBIENT_ENERGY := 0.34
const TONEMAP_EXPOSURE := 1.0
const TONEMAP_WHITE := 6.0


# Builds the complete production lighting rig for one terrain world.
# `terrain_aabb` is the generated top-surface mesh AABB (deterministic
# derived data); it only scales the directional shadow range.
static func build_rig(terrain_aabb: AABB) -> Node3D:
	var rig := Node3D.new()
	rig.name = RIG_NAME
	rig.add_child(_build_sun(terrain_aabb))
	rig.add_child(_build_fill())
	rig.add_child(_build_environment())
	return rig


static func shadow_max_distance_for(terrain_aabb: AABB) -> float:
	var extent := maxf(maxf(terrain_aabb.size.x, terrain_aabb.size.z), 1e-3)
	return SHADOW_MAX_DISTANCE_FACTOR * extent


static func _build_sun(terrain_aabb: AABB) -> DirectionalLight3D:
	var sun := DirectionalLight3D.new()
	sun.name = SUN_NAME
	sun.rotation_degrees = SUN_ROTATION_DEGREES
	sun.light_color = SUN_COLOR
	sun.light_energy = SUN_ENERGY
	sun.light_angular_distance = SUN_ANGULAR_DISTANCE_DEG
	sun.shadow_enabled = true
	sun.shadow_bias = SHADOW_BIAS
	sun.shadow_normal_bias = SHADOW_NORMAL_BIAS
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_max_distance = shadow_max_distance_for(terrain_aabb)
	return sun


static func _build_fill() -> DirectionalLight3D:
	var fill := DirectionalLight3D.new()
	fill.name = FILL_NAME
	fill.rotation_degrees = FILL_ROTATION_DEGREES
	fill.light_color = FILL_COLOR
	fill.light_energy = FILL_ENERGY
	fill.light_specular = 0.0
	fill.shadow_enabled = false
	return fill


static func _build_environment() -> WorldEnvironment:
	var world_environment := WorldEnvironment.new()
	world_environment.name = ENVIRONMENT_NAME
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = _build_sky()
	# The sky is a backdrop only and must not retune the accepted N3c.7
	# terrain-material look: ambient stays the locked flat color (not
	# sky-sampled) and reflected light is disabled so the sky radiance does
	# not replace the accepted (near-black backdrop) reflections.
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = AMBIENT_COLOR
	environment.ambient_light_energy = AMBIENT_ENERGY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = TONEMAP_EXPOSURE
	environment.tonemap_white = TONEMAP_WHITE
	world_environment.environment = environment
	return world_environment


static func _build_sky() -> Sky:
	var material := ProceduralSkyMaterial.new()
	material.sky_top_color = SKY_TOP_COLOR
	material.sky_horizon_color = SKY_HORIZON_COLOR
	material.sky_curve = SKY_CURVE
	material.ground_bottom_color = GROUND_BOTTOM_COLOR
	material.ground_horizon_color = GROUND_HORIZON_COLOR
	material.ground_curve = GROUND_CURVE
	material.sun_angle_max = SUN_ANGLE_MAX_DEG
	material.sun_curve = SUN_CURVE
	var sky := Sky.new()
	sky.sky_material = material
	return sky
