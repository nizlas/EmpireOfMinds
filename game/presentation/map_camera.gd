# Plane-space camera wrapper: applies [member camera_world_offset] before [member projection] (Phase 4.5m).
# Phase 4.5n: layer-local presentation zoom around [member MapPlaneProjection.vanishing_pres].
# Prefer changing [member zoom] only via [method set_zoom_clamped]; callers should not assign invalid zoom.
# See docs/RENDERING.md — pan updates [member camera_world_offset]; [member MapPlaneProjection] math unchanged.
class_name MapCamera
extends RefCounted

var projection
var camera_world_offset: Vector2 = Vector2.ZERO
var zoom: float = 1.0
var min_zoom: float = 0.5
var max_zoom: float = 2.5

func _init() -> void:
	zoom = 1.0
	min_zoom = 0.5
	max_zoom = 2.5

func set_zoom_clamped(z: float) -> void:
	zoom = clampf(z, min_zoom, max_zoom)

func to_presentation(world: Vector2) -> Vector2:
	var shifted: Vector2 = world - camera_world_offset
	if is_equal_approx(zoom, 1.0):
		return projection.to_presentation(shifted)
	var p: Vector2 = projection.to_presentation(shifted)
	return projection.vanishing_pres + (p - projection.vanishing_pres) * zoom

func to_layout(local_pres: Vector2) -> Vector2:
	if is_equal_approx(zoom, 1.0):
		return projection.to_layout(local_pres) + camera_world_offset
	var safe_zoom: float = max(zoom, 0.0001)
	var unzoomed: Vector2 = (
		projection.vanishing_pres + (local_pres - projection.vanishing_pres) / safe_zoom
	)
	return projection.to_layout(unzoomed) + camera_world_offset

func perspective_scale_at(world: Vector2) -> float:
	return projection.perspective_scale_at(world - camera_world_offset) * zoom

var vanishing_pres: Vector2:
	get:
		if projection == null:
			return Vector2.ZERO
		return projection.vanishing_pres
	set(value):
		if projection != null:
			projection.vanishing_pres = value
