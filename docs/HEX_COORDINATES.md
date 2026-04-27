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

The names E / NE / … are **labels for the six directions** in axial space. Whether “east” lines up with screen +X for a pointy-top vs flat-top layout is a **rendering** decision (see Phase 1.3+). The domain layer does not encode pointy vs flat, pixel size, or world basis vectors.

## Layer boundary (`game/domain/`)

Code under `game/domain/` (e.g. `hex_coord.gd`) must not reference Godot scene nodes, UI, input, or drawing. It may use language-level types and `RefCounted` for domain objects. This keeps a path toward server-authoritative rules and non-Godot tests later, per architecture principles.

## Explicitly deferred (not in Phase 1.1)

- **Cube coordinates** and `to_cube()` / `from_cube()` (useful for distance and line-drawing later).
- **Distance**, **range**, **line of sight**, **pathfinding**.
- **Pixel / world / screen** mapping, tile size, origin, and layout orientation.
- **Serialization** of coordinates (action log, save games): schema and versioning come with those features.

Add these only when a later phase needs them, with validation and docs updated accordingly.
