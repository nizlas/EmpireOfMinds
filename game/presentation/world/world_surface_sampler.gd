# N7f presentation-only top-surface sampler for transient unit-locomotion
# visuals (height/normal under a moving character).
#
# Contract (locked):
# - Samples ONLY the rendered top surface: one short vertical raycast per
#   call against the N3c.4 TerrainCollision StaticBody3D, accepting hits on
#   the top-surface shape exclusively (shape index 0 = TopSurfaceCollision).
#   Cliff walls (shape index 1) never contribute — a wall-first hit is a
#   miss. Never a full-mesh scan.
# - The result is transient VISUAL correction data only. It is never
#   gameplay authority and never feeds legality (N3c.4 boundary: collision
#   is derived presentation data; the authoritative WorldMap and the N4
#   anchors stay the only gameplay placement sources).
# - Any miss (no body, wall hit, off-surface ray) returns ok=false and the
#   caller falls back to anchor-height interpolation — no guessing.
class_name WorldSurfaceSampler
extends RefCounted

const TerrainCollisionScript = preload("res://presentation/terrain_collision.gd")

# Ray window around the caller's height hint (anchor heights span ~0.4–3.0
# world units on the reference map; the window is map-independent).
const RAY_UP := 8.0
const RAY_DOWN := 24.0

var _body: StaticBody3D = null


func _init(collision_body: StaticBody3D = null) -> void:
	_body = collision_body


# Resolves the built TerrainWorld's collision body (child named per the
# N3c.4 contract). Returns a sampler that misses cleanly when absent.
# (Untyped return: the class_name is not registered in headless --script
# runs, so the factory uses the implicit self-class constructor.)
static func for_terrain_world(world: Node):
	var body: StaticBody3D = null
	if world != null:
		body = world.get_node_or_null(TerrainCollisionScript.BODY_NAME) as StaticBody3D
	return new(body)


# Samples the rendered top surface at world (x, z). y_hint centers the ray
# window (callers pass their current interpolated height). Returns
# {"ok": bool, "height": float, "normal": Vector3}.
func sample(x: float, z: float, y_hint: float) -> Dictionary:
	var miss := {"ok": false, "height": y_hint, "normal": Vector3.UP}
	if _body == null or not _body.is_inside_tree():
		return miss
	var world_3d := _body.get_world_3d()
	if world_3d == null:
		return miss
	var space := world_3d.direct_space_state
	if space == null:
		return miss
	var params := PhysicsRayQueryParameters3D.create(
		Vector3(x, y_hint + RAY_UP, z), Vector3(x, y_hint - RAY_DOWN, z)
	)
	var hit: Dictionary = space.intersect_ray(params)
	if hit.is_empty() or hit.get("collider", null) != _body:
		return miss
	if int(hit.get("shape", -1)) != 0:
		return miss
	return {
		"ok": true,
		"height": (hit["position"] as Vector3).y,
		"normal": (hit["normal"] as Vector3).normalized(),
	}
