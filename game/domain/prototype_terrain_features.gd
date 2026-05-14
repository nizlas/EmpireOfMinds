# Prototype-only terrain feature data for the hand-authored play disk (Phase 5.1.16c).
# **Woods** hexes are domain truth for **HexMap.has_woods**; presentation re-exports this list for forest overlay.
# See docs/CITIES.md, docs/MAP_MODEL.md
class_name PrototypeTerrainFeatures
extends RefCounted

## Phase 5.1.16g.2 **polish:** **PLAINS** terrain only (flat + hills); **broken-up** woods — isolates, thin belts, W/NW **groves** on dry land (**never** lake-strait / bay keys), no mega-blob.
## Skips **(0,0)**, **(1,0)**, **(3,0)**, **(9,5)**, **(8,-2)** hill-city fixture, **forest-debug** overlay hexes, **(-1,0)** strait.
const PROTOTYPE_WOODS_HEXES: Array[Vector2i] = [
	Vector2i(-6, 0),
	Vector2i(-5, -1),
	Vector2i(-5, 1),
	Vector2i(-4, -2),
	Vector2i(-4, 0),
	Vector2i(-4, 1),
	Vector2i(-3, 1),
	Vector2i(-2, 2),
	Vector2i(0, -3),
	Vector2i(1, -1),
	Vector2i(1, -2),
	Vector2i(1, -3),
	Vector2i(2, -3),
	Vector2i(2, 3),
	Vector2i(3, -3),
	Vector2i(3, 2),
	Vector2i(4, -3),
	Vector2i(2, -2),
	Vector2i(5, -3),
	Vector2i(5, 4),
	Vector2i(0, 4),
	Vector2i(6, 4),
	Vector2i(7, -2),
	Vector2i(7, 0),
	Vector2i(7, 1),
	Vector2i(7, 5),
	Vector2i(8, -1),
	Vector2i(8, 1),
	Vector2i(8, 4),
	Vector2i(4, 1),
	Vector2i(10, 2),
	Vector2i(10, 5),
	Vector2i(10, 6),
	Vector2i(11, 2),
	Vector2i(11, 4),
	Vector2i(11, 6),
	Vector2i(12, 6),
	Vector2i(12, 8),
	Vector2i(13, 6),
	Vector2i(13, 7),
]


static func prototype_woods_set() -> Dictionary:
	var d: Dictionary = {}
	for v in PROTOTYPE_WOODS_HEXES:
		d[v] = true
	return d
