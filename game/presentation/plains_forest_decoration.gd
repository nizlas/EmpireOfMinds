# Presentation-only: deterministic PLAINS forest *decoration* gate (Phase 4.6b).
# Not HexMap.Terrain.FOREST; no gameplay semantics. See docs/RENDERING.md.
extends RefCounted

const SALT_FOREST_DENSITY_GATE: int = 402010697

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
