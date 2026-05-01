# Pointy-top hex layout: axial (q, r) to world/screen space. Presentation-only; no domain or gameplay state.
# See docs/RENDERING.md
class_name HexLayout
extends RefCounted

## Circumradius in world units; presentation-only (Phase 4.2a: 2×; Phase 4.3c: +2× for live readability — 4× pre-4.2a baseline of 32).
const SIZE: float = 128.0

func hex_to_world(q: int, r: int) -> Vector2:
	var x: float = SIZE * sqrt(3.0) * (float(q) + float(r) / 2.0)
	var y: float = SIZE * 1.5 * float(r)
	return Vector2(x, y)

func hex_corners(center: Vector2) -> PackedVector2Array:
	var out = PackedVector2Array()
	# Pointy-top hex: vertex directions (degrees) from +X.
	var degs: Array = [30, 90, 150, 210, 270, 330]
	for i in range(6):
		var rad: float = deg_to_rad(float(degs[i]))
		var corner: Vector2 = center + Vector2(cos(rad) * SIZE, sin(rad) * SIZE)
		out.append(corner)
	return out
