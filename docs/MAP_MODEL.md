# Empire of Minds — Domain map model (Phase 1.2)

Hex cell addressing uses axial coordinates; see [HEX_COORDINATES.md](HEX_COORDINATES.md) for `(q, r)` and neighbor directions. This document only describes the **map container** in Phase 1.2.

## Representation

- **`HexMap`** (domain, `class_name` in [game/domain/hex_map.gd](../game/domain/hex_map.gd)) holds a **finite** set of hexes that exist in play.
- **API boundary:** queries use [HexCoord](HEX_COORDINATES.md) (`q`, `r`).
- **Storage:** internal dictionary keys are `Vector2i(q, r)` (value-typed) → terrain enum value. This avoids identity-based lookup bugs with `RefCounted` keys.

## Terrain (tag-only in Phase 1.2)

`HexMap.Terrain` is a minimal inline enum: `PLAINS`, `WATER`. Values are **tags** only in **`HexMap`** (no per-cell gameplay fields here). **Phase 3.2:** **[TerrainRuleDefinitions](../game/domain/content/terrain_rule_definitions.gd)** holds **passability** and **`movement_cost`** metadata keyed by stable ids **`plains`** / **`water`** mapped from this enum. **`movement_cost`** does **not** expand move range yet—still one step per [MOVEMENT_RULES.md](MOVEMENT_RULES.md).

## Fixed tiny test map

`HexMap.make_tiny_test_map()` is the **canonical 7-hex** fixture: center cell `(0,0)` plus all six neighbors, as below.

| (q, r) | Terrain |
|--------|---------|
| (0, 0) | PLAINS |
| (1, 0) | PLAINS (E) |
| (1, -1) | PLAINS (NE) |
| (0, -1) | PLAINS (NW) |
| (-1, 0) | WATER (W) |
| (-1, 1) | PLAINS (SW) |
| (0, 1) | PLAINS (SE) |

Direction names in the table are **labels** for axial neighbors; see [HEX_COORDINATES.md](HEX_COORDINATES.md) for orientation neutrality.

## Query API (Phase 1.2)

- `has(HexCoord)` — whether the coordinate is on the map.
- `terrain_at(HexCoord)` — terrain tag; **only valid** when `has` is true (asserts otherwise).
- `size()` — number of cells.
- `coords()` — read-only list of all cells as `HexCoord` instances. Does not expose `Vector2i` keys. **Order is unspecified** in Phase 1.2; a future phase may document deterministic ordering if required (e.g. for replay or UI).
- `make_tiny_test_map()` — static factory for the table above.

## Layer boundary

Code under `game/domain/` must not depend on Godot scene nodes, rendering, UI, input, networking, or LLMs; see [game/domain/README.md](../game/domain/README.md).

## Phase 1.5 note (terrain vs movement rules)

**`HexMap`** and **`Terrain`** remain **unchanged** in Phase 1.5: terrain values are still **tags** with no movement semantics baked into the map type. The first interpretation that **WATER is impassable** for unit movement lives in **[MOVEMENT_RULES.md](MOVEMENT_RULES.md)** (`MovementRules.legal_destinations`), not in new `HexMap` APIs.

**`HexMap`** storage stays **enum-backed**: no string **`terrain_id`** in **`_cells`** and **no** save/load migration in **3.2**. **`TerrainRuleDefinitions.terrain_id_for_hex_map_value`** projects **`HexMap.Terrain`** values onto content ids. Unknown enum values map to an **empty** id and are treated as **impassable** in movement rules.

**Phase 3.2 (implemented):** Terrain **semantics** for **movement** are read through **`TerrainRuleDefinitions`** per [CONTENT_MODEL.md](CONTENT_MODEL.md); **`HexMap`** API and storage are **unchanged**.

## Explicitly deferred

- A dedicated **cell** or **terrain** type with gameplay fields (owner, resources, move cost, etc.)
- **Fog of war** and **visibility**
- **Distance / range / line / path** queries on the map
- **World / screen / pixel** layout (Phase 1.3+)
- **Serialization** of maps and terrain for save / replay (with schema versioning, per architecture)
