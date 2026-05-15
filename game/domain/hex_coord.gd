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


## Cube axial metric on pointy-top axial (q, r); reusable for range, sight, combat.
static func axial_distance(a: HexCoord, b: HexCoord) -> int:
	if a == null or b == null:
		return 0
	var aq: int = a.q
	var ar: int = a.r
	var bq: int = b.q
	var br: int = b.r
	var ac: int = aq
	var ay: int = ar
	var az: int = -aq - ar
	var bc: int = bq
	var by: int = br
	var bz: int = -bq - br
	var dx: int = ac - bc
	var dy: int = ay - by
	var dz: int = az - bz
	return maxi(abs(dx), maxi(abs(dy), abs(dz)))
