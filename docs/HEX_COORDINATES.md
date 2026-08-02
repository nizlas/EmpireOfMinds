# Empire of Minds — Hex coordinates (domain)

## Representation

Phase 1.1 uses **axial coordinates** \((q, r)\) with integer components. One pair identifies one hex cell. This is the smallest domain-level encoding for a hex grid.

## Direction table

Neighbor offsets are fixed in this order, matching `HexCoord.Direction` (E through SE):

| Direction | \((\Delta q, \Delta r)\) |
|----------|-------------------------|
| E        | \((+1, 0)\)             |
| NE       | \((+1, -1)\)            |
| NW       | \((0, -1)\)             |
| W        | \((-1, 0)\)             |
| SW       | \((-1, +1)\)            |
| SE       | \((0, +1)\)             |

`neighbor(direction)` returns the cell at \((q, r) + (\Delta q, \Delta r)\).

## Orientation neutrality

The names E / NE / … are **labels for the six directions** in axial space. Whether a direction aligns with screen or world axes is an **embedding** concern — see the normative coordinate contract in [WORLD_COORDINATES.md](WORLD_COORDINATES.md). The **`HexWorldProjection`** module (N1 foundation) implements world-axis embedding and elevation conversion; full 3D presentation remains planned (N3+).

This document describes the existing **`HexCoord`** utility and historical domain context. [WORLD_COORDINATES.md](WORLD_COORDINATES.md) is the normative contract for the 3D world integration phase.

## Axial distance (implemented)

**`HexCoord.axial_distance(a, b)`** ([game/domain/hex_coord.gd](../game/domain/hex_coord.gd)) returns the hex-grid distance between two cells using the cube-coordinate metric internally. This is **current repository behavior**, used for sight radii and related domain queries (e.g. `PlayerVisibilityState`).

## Layer boundary (`game/domain/`)

Code under `game/domain/` (e.g. `hex_coord.gd`) must not reference Godot scene nodes, UI, input, or drawing. It may use language-level types and `RefCounted` for domain objects. This keeps a path toward server-authoritative rules and non-Godot tests later, per architecture principles.

## Explicitly deferred (not in Phase 1.1)

- **Cube coordinates** and public `to_cube()` / `from_cube()` helpers (useful for line-drawing later; distance already uses cube math internally).
- **Range**, **line of sight**, **pathfinding** (beyond the existing distance primitive).
- **Pixel / world / screen** mapping, tile size, origin, and layout orientation — normative contract: [WORLD_COORDINATES.md](WORLD_COORDINATES.md); **`HexWorldProjection`** implements the approved world embedding (N1 foundation). Screen/presentation layout remains future work (N3+).
- **Serialization** of coordinates (action log, save games): schema and versioning come with those features.

Add these only when a later phase needs them, with validation and docs updated accordingly.
