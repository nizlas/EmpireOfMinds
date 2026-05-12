# Prototype-only terrain feature data for the hand-authored play disk (Phase 5.1.16c).
# **Woods** hexes are domain truth for **HexMap.has_woods**; presentation re-exports this list for forest overlay.
# See docs/CITIES.md, docs/MAP_MODEL.md
class_name PrototypeTerrainFeatures
extends RefCounted

## Prototype / visual-review only: axial `Vector2i` keys that carry **woods** for **v0 city yields** on the prototype play map.
## Textually identical to the former **`plains_forest_decoration.gd`** list.
const PROTOTYPE_WOODS_HEXES: Array[Vector2i] = [
	# SW PLAINS flat (12) — stays below r=-1 corridor so (0,-3) singles do not touch this blob.
	Vector2i(-3, -2), Vector2i(-6, -1), Vector2i(-6, 0), Vector2i(-5, -1), Vector2i(-5, -2),
	Vector2i(-4, -1), Vector2i(-4, -2), Vector2i(-4, -3), Vector2i(-3, -3), Vector2i(-3, -4),
	Vector2i(-2, -5), Vector2i(-2, -4), Vector2i(-1, -5),
	# NW PLAINS flat (6) — r>=2 band; one r gap before the r=5 patch so SW never meets NW.
	Vector2i(-7, 2), Vector2i(-7, 3), Vector2i(-6, 2), Vector2i(-5, 2), Vector2i(-5, 3), Vector2i(-4, 3),
	# NW PLAINS flat (3).
	Vector2i(-7, 5), Vector2i(-6, 5), Vector2i(-6, 4),
	# PLAINS hills (6 + 3).
	Vector2i(1, -1), Vector2i(2, -2), Vector2i(3, -3), Vector2i(4, -4), Vector2i(4, -5), Vector2i(3, -5),
	Vector2i(5, -5), Vector2i(5, -6), Vector2i(6, -6),
	# PLAINS flat pair (2).
	Vector2i(0, -4), Vector2i(1, -5),
	# Singles (2) — PLAINS only; third single is expensive on a hex grid without merging (see test thresholds).
	Vector2i(0, -3), Vector2i(-3, 1),
]


static func prototype_woods_set() -> Dictionary:
	var d: Dictionary = {}
	for v in PROTOTYPE_WOODS_HEXES:
		d[v] = true
	return d
