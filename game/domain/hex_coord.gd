# Domain-only hex cell identity in axial coordinates. No map, no rendering, no world space.
# Spec (repo, outside Godot res://): docs/HEX_COORDINATES.md. Layer: res://domain/README.md
class_name HexCoord
extends RefCounted

## Axial (q, r) directions in fixed E..SE order. Names are labels only; orientation is a rendering concern.
enum Direction { E, NE, NW, W, SW, SE }

const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(1, -1),
	Vector2i(0, -1),
	Vector2i(-1, 0),
	Vector2i(-1, 1),
	Vector2i(0, 1),
]

var q: int
var r: int

func _init(p_q: int = 0, p_r: int = 0) -> void:
	q = p_q
	r = p_r

func equals(other: HexCoord) -> bool:
	if other == null:
		return false
	return q == other.q and r == other.r

func neighbor(direction: int) -> HexCoord:
	var o: Vector2i = DIRECTIONS[direction]
	return HexCoord.new(q + o.x, r + o.y)

func neighbors() -> Array:
	var out: Array[HexCoord] = []
	for d in range(6):
		out.append(neighbor(d))
	return out
