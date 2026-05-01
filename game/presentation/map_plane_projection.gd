# Projective map-plane transform: HexLayout / hex_to_world space <-> map-layer local presentation offset.
# Presentation-only; Phase 4.5e–4.5g (mild perspective band); 4.5h marker anchors = projected hex center. See docs/RENDERING.md.
class_name MapPlaneProjection
extends RefCounted

## Vertical compression factor applied to layout Y before perspective scaling. 4.5g: milder flattening for strategic readability.
@export var plane_y_scale: float = 0.90
## Perspective rate: larger values strengthen convergence toward [vanishing_pres](#). 4.5g: **0.0003–0.0005** targets a mild Civ6-like receding plane; default **0.0004**.
@export var depth_strength: float = 0.0004
## Layout/world Y where w = 1.0 (front row, no shrink toward vanishing point along that row’s depth cue).
@export var near_world_y: float = 192.0
## Vanishing / convergence center in **map-layer local** presentation space (same frame as pre-projection draw coords, origin at MAP_LAYER_ORIGIN). Typically set from viewport center minus MAP_LAYER_ORIGIN in main.gd.
@export var vanishing_pres: Vector2 = Vector2(800.0, 322.0)

## Same divisor as [member to_presentation] uses for perspective scale along the map plane (billboard sizing).
func perspective_scale_at(world: Vector2) -> float:
	var ww: float = 1.0 + depth_strength * (near_world_y - world.y)
	return 1.0 / ww

func to_presentation(world: Vector2) -> Vector2:
	var ww: float = 1.0 + depth_strength * (near_world_y - world.y)
	var sc: float = 1.0 / ww
	return Vector2(
		vanishing_pres.x + (world.x - vanishing_pres.x) * sc,
		vanishing_pres.y + (world.y * plane_y_scale - vanishing_pres.y) * sc
	)

## Closed-form inverse: layer-local presentation offset back to layout / hex_to_world space. Singularity when `plane_y_scale + dy * depth_strength == 0`; at default constants this lies outside normal map-layer coordinates.
func to_layout(pres: Vector2) -> Vector2:
	var dx: float = pres.x - vanishing_pres.x
	var dy: float = pres.y - vanishing_pres.y
	var wy: float = (
		(vanishing_pres.y + dy * (1.0 + depth_strength * near_world_y))
		/ (plane_y_scale + dy * depth_strength)
	)
	var ww: float = 1.0 + depth_strength * (near_world_y - wy)
	var wx: float = vanishing_pres.x + dx * ww
	return Vector2(wx, wy)
