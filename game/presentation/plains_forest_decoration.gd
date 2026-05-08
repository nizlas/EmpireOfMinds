# Presentation-only: deterministic PLAINS forest *decoration* gate (Phase 4.6b).
# Not HexMap.Terrain.FOREST; no gameplay semantics. See docs/RENDERING.md.
extends RefCounted

const SALT_FOREST_DENSITY_GATE: int = 402010697

## Prototype / visual-review only: when non-empty, **only** these hexes (axial `Vector2i`) may show
## MapView back-forest + matching TFV decoration, instead of hash `forest_density_ratio`.
## This is **not** a gameplay forest biome, not production worldgen, and not authoritative domain state.
## Keep empty outside `main.gd` wiring for the prototype play map. See `prototype_forest_cluster_set()`.
const PROTOTYPE_FOREST_DECORATION_HEXES: Array[Vector2i] = [
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

static func cell_mix(q: int, r: int, salt: int) -> int:
	# Same polynomial family as MapView._terrain_detail_hash — deterministic, no RNG.
	return (q * 374761393 + r * 668265263 + salt * 1442695041) & 0x7FFFFFFF

static func is_plains_forest_decorated(q: int, r: int, density_ratio: float) -> bool:
	if density_ratio <= 0.0:
		return false
	if density_ratio >= 1.0:
		return true
	var h: int = cell_mix(q, r, SALT_FOREST_DENSITY_GATE)
	return float(h) / 2147483647.0 < density_ratio


static func is_plains_forest_decorated_with_override(
	q: int, r: int, density_ratio: float, override_set
) -> bool:
	# When override_set is null or empty, behavior matches is_plains_forest_decorated (production path).
	if override_set != null and override_set is Dictionary and override_set.size() > 0:
		return override_set.has(Vector2i(q, r))
	return is_plains_forest_decorated(q, r, density_ratio)


## Build a fast lookup dict for prototype-only wiring. Not used for gameplay rules.
static func prototype_forest_cluster_set() -> Dictionary:
	var d: Dictionary = {}
	for v in PROTOTYPE_FOREST_DECORATION_HEXES:
		d[v] = true
	return d


static func prototype_forest_decoration_hexes() -> Array[Vector2i]:
	return PROTOTYPE_FOREST_DECORATION_HEXES.duplicate()
