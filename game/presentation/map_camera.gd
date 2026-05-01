# Plane-space camera wrapper: applies [member camera_world_offset] before [member projection] (Phase 4.5m).
# See docs/RENDERING.md — pan updates [member camera_world_offset]; [member MapPlaneProjection] math unchanged.
class_name MapCamera
extends RefCounted

var projection
var camera_world_offset: Vector2 = Vector2.ZERO

func to_presentation(world: Vector2) -> Vector2:
	return projection.to_presentation(world - camera_world_offset)

func to_layout(local_pres: Vector2) -> Vector2:
	return projection.to_layout(local_pres) + camera_world_offset

func perspective_scale_at(world: Vector2) -> float:
	return projection.perspective_scale_at(world - camera_world_offset)

var vanishing_pres: Vector2:
	get:
		if projection == null:
			return Vector2.ZERO
		return projection.vanishing_pres
	set(value):
		if projection != null:
			projection.vanishing_pres = value
