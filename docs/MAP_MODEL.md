# Empire of Minds — Domain map model (Phase 1.2)

Hex cell addressing uses axial coordinates; see [HEX_COORDINATES.md](HEX_COORDINATES.md) for `(q, r)` and neighbor directions. This document only describes the **map container** in Phase 1.2.

## Representation

- **`HexMap`** (domain, `class_name` in [game/domain/hex_map.gd](../game/domain/hex_map.gd)) holds a **finite** set of hexes that exist in play.
- **API boundary:** queries use [HexCoord](HEX_COORDINATES.md) (`q`, `r`).
- **Storage:** internal dictionary keys are `Vector2i(q, r)` (value-typed) → terrain enum value. This avoids identity-based lookup bugs with `RefCounted` keys.

## Terrain (tag-only in Phase 1.2)

`HexMap.Terrain` is a minimal inline enum: `PLAINS`, `WATER`. Values are **tags** only. There are no movement costs, line-of-sight, resources, or ownership in this phase. Gameplay rules that interpret terrain come in later phases, with updated steering as needed.

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
- `make_tiny_test_map()` — static factory for the table above.

## Layer boundary

Code under `game/domain/` must not depend on Godot scene nodes, rendering, UI, input, networking, or LLMs; see [game/domain/README.md](../game/domain/README.md).

## Explicitly deferred

- A dedicated **cell** or **terrain** type with gameplay fields (owner, resources, move cost, etc.)
- **Fog of war** and **visibility**
- **Distance / range / line / path** queries on the map
- **World / screen / pixel** layout (Phase 1.3+)
- **Serialization** of maps and terrain for save / replay (with schema versioning, per architecture)
