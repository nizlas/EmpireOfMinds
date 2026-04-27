# Empire of Minds — Decision Log

## 2026-04-27 — Initial Engine Direction

Decision:
Use Godot as the initial prototyping engine.

Rationale:
- permissive MIT license
- good fit for 2D/strategy prototyping
- low licensing risk
- fast iteration
- no revenue share/runtime fee

Caveat:
The architecture must not make core rules inseparable from Godot scenes.

## 2026-04-27 — AI Direction

Decision:
Start with deterministic rule-based AI.

Rationale:
- debuggable
- testable
- works offline
- creates legal-action interface needed for future LLM AI

Caveat:
LLM adapters may be explored later, but must choose from generated legal actions.

## 2026-04-27 — Cloud Direction

Decision:
Design for asynchronous play-by-cloud, but do not build official hosting first.

Rationale:
- async turns fit 4X gameplay
- avoids early operational burden
- enables Bring Your Own Server / Private Cloud

Caveat:
Server-authoritative architecture must be preserved for future cloud mode.

## 2026-04-27 — Scripting language for Godot (Phase 1.x)

Decision:
Phase 1.x uses Godot 4.x with GDScript as the default scripting language; C# is deferred to avoid introducing a .NET dependency during early prototyping.

Rationale:
- GDScript ships with Godot; no separate .NET SDK or Mono build required on the machine or in the repo for contributors to open and run the project.

Caveat:
C# may be reconsidered later only with an explicit steering decision to accept the .NET dependency.

## 2026-04-27 — Axial hex coordinates (Phase 1.1)

Decision:
Phase 1.1 uses axial (q, r) hex coordinates in the domain layer; cube conversion is deferred; distance-style helpers are deferred until a later phase needs them.

Rationale:
- Minimal representation, simple neighbor lookup, orientation-neutral at the domain layer, and compatible with later cube math for distance, line, and range.

Caveat:
Later phases may add `to_cube()`, `distance()`, or range helpers when movement or other rules need them; the steering documents should be updated when that happens.

## 2026-04-27 — Domain map model (Phase 1.2)

Decision:
Phase 1.2 introduces **`HexMap`**: a finite set of cells stored as `Dictionary[Vector2i -> int]`, with **public queries taking `HexCoord`**. `Terrain` is a minimal inline enum (`PLAINS`, `WATER`) with no gameplay effects in 1.2. A single canonical 7-hex test map is provided by the static `HexMap.make_tiny_test_map()`.

Rationale:
- `Vector2i` keys are value-based and work correctly with `has()`; `HexCoord` remains the domain identity at the API.
- Two terrain values are enough to exercise `terrain_at` without pre-committing to a full 4X terrain taxonomy.
- One factory method keeps the fixture consistent for later rendering and rules phases.

Caveat:
Later phases will likely introduce a `Cell` or richer `Terrain` model (costs, ownership, etc.); that will require an explicit steering update before implementation.

## 2026-04-27 — HexMap.read_coords (Phase 1.2 follow-up for Phase 1.3)

Decision:
`HexMap` adds **`coords()`** — a read-only list of all occupied cells as `HexCoord` instances, without exposing the internal `Vector2i` dictionary keys. **Iteration order is unspecified** in Phase 1.2.

Rationale:
Presentation (e.g. rendering) must **derive** what to draw from domain state, not hand-duplicate a coordinate list. `coords()` gives a single source of truth for “which cells exist” without mutating the map or returning raw storage types.

Caveat:
If a future system needs a stable order (e.g. deterministic serialisation), the steering documents and API must be updated to specify it.
