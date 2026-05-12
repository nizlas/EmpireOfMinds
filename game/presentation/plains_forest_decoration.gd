# Presentation-only: deterministic PLAINS forest *decoration* gate (Phase 4.6b).
# Not HexMap.Terrain.FOREST; prototype woods overlay is **domain** truth via **PrototypeTerrainFeatures**.
# See docs/RENDERING.md
extends RefCounted

const _PrototypeTerrainFeatures = preload("res://domain/prototype_terrain_features.gd")

const SALT_FOREST_DENSITY_GATE: int = 402010697

## Prototype / visual-review only: axial `Vector2i` keys that may show MapView back-forest + TFV decoration.
## Alias of **PrototypeTerrainFeatures.PROTOTYPE_WOODS_HEXES** (same sequence as historical `plains_forest_decoration.gd`).
const PROTOTYPE_FOREST_DECORATION_HEXES: Array[Vector2i] = _PrototypeTerrainFeatures.PROTOTYPE_WOODS_HEXES

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


## Build a fast lookup dict for prototype-only wiring; mirrors domain **prototype_woods_set**.
static func prototype_forest_cluster_set() -> Dictionary:
	return _PrototypeTerrainFeatures.prototype_woods_set()


## True when **(q,r)** is listed in [member PROTOTYPE_FOREST_DECORATION_HEXES].
static func is_prototype_foreground_forest_hex(q: int, r: int) -> bool:
	return prototype_forest_cluster_set().has(Vector2i(q, r))


static func prototype_forest_decoration_hexes() -> Array[Vector2i]:
	return _PrototypeTerrainFeatures.PROTOTYPE_WOODS_HEXES.duplicate()
