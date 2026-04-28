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

## 2026-04-27 — Map rendering (Phase 1.3)

Decision:
**Phase 1.3** draws the **tiny test** `HexMap` using a single **`MapView` (`Node2D`)** and **`_draw()`**. A pure static helper **`MapView.compute_draw_items(map, layout)`** turns domain state into polygon colors and corner lists. `compute_draw_items` iterates **`map.coords()`** and **`terrain_at(coord)`**; it does **not** use a hand-duplicated coordinate list. **[HexLayout](../game/presentation/hex_layout.gd)** encodes pointy-top axial-to-world layout with `SIZE` 32. Placeholder terrain colors and scope are documented in [RENDERING.md](RENDERING.md).

Rationale:
One `Node2D` plus `_draw()` is minimal; derived drawing from `coords()` matches the “rendering reflects domain” rule. Pointy-top layout is a common default; the domain remains orientation-neutral in [HEX_COORDINATES.md](docs/HEX_COORDINATES.md).

Caveat:
**Orientation, tile size, palette, camera, input, and TileMap** are **not** locked for production; a future phase or steering pass may revise them.

## 2026-04-27 — Unit domain and Scenario (Phase 1.4)

Decision:
**Phase 1.4** introduces an immutable **`Unit`** and **`Scenario`** in `game/domain/`: a `Unit` is `(id, owner_id, position)` as `RefCounted` data; a **`Scenario`** holds a `HexMap` and a fixed list of units, validated at construction (positions on the map, unique unit ids), with read-only query APIs and **`make_tiny_test_scenario()`** as the canonical three-unit, two-owner fixture on PLAINS only, with `(-1,0)` WATER unoccupied.

Rationale:
**Smallest viable** representation: integers for **unit and owner ids** without a `Player` class; a single **`Scenario`** bundle unblocks **Phase 1.5** and later rules without entangling `Node` or global state.

Caveat:
**Rendering, selection, movement, actions, a `Player` type, owner palette, and stacking / ZoC rules** remain **deferred**; this phase does not define gameplay loops or presentation.

## 2026-04-28 — Unit markers in presentation (Phase 1.4b)

Decision:
**Phase 1.4b** introduces **`UnitsView`**, a separate **`Node2D`** **sibling** of **`MapView`**, both parented by **`Main`** in [main.tscn](../game/main.tscn) with [main.gd](../game/main.gd) as the only wiring: **`Main` owns a single `Scenario` instance and a single `HexLayout`**, passing **`scenario.map`** and **`layout`** to **`MapView`**, and **`scenario`** and **`layout`** to **`UnitsView`**. **`UnitsView` derives** marker positions, count, and placeholder **owner** colors from **`Scenario.units()`** only (via static **`compute_marker_items`**); markers are **simple drawn circles** with a thin outline.

Rationale:
Keeps **terrain** and **units** as two presentation concerns; one **`Scenario` + one `HexLayout`** prevent map/units/geometry from drifting. Derived drawing matches the “rendering reflects state, not owns it” rule from [ARCHITECTURE_PRINCIPLES.md](ARCHITECTURE_PRINCIPLES.md).

Caveat:
**Selection, movement, input, animation, sprites, the warrior asset, text labels, health bars, a final owner palette, and gameplay rules** remain **deferred**; 1.4b is read-only display only.

## 2026-04-28 — Selection and legal destinations (Phase 1.5)

Decision:
**Phase 1.5** adds **`MovementRules.legal_destinations(scenario, unit_id)`** in [game/domain/movement_rules.gd](../game/domain/movement_rules.gd) (neighbor-only, on-map, **not WATER**, **not occupied**). Presentation adds **`SelectionState`** ( **`RefCounted`**, `unit_id` only), **`SelectionController`** (**`_unhandled_input`**, hit-test markers, **no `UnitsView` reference**), and **`SelectionView`** ( **`compute_overlay_items`** + **`_draw`** ring via **`PackedVector2Array`** closed polyline, destination fills). **`Main`** wires one **`Scenario`**, **`HexLayout`**, and **`SelectionState`** to views. **`HexMap` / `Terrain`** stay tag-only; WATER-as-impassable is documented in [MOVEMENT_RULES.md](MOVEMENT_RULES.md).

Rationale:
Keeps **rules** in a small static domain API; keeps **selection** as **non-authoritative** client state; overlays **derive** from domain + selection so highlights are never truth.

Caveat:
**Actual movement**, **`MoveUnit`**, **validators**, **action log**, **turn ownership**, **AI**, **save/load**, and **final UX** for selection remain **deferred**.

## 2026-04-28 — MoveUnit, GameState, ActionLog (Phase 1.6)

Decision:
**Phase 1.6** adds **`MoveUnit`** ([game/domain/actions/move_unit.gd](../game/domain/actions/move_unit.gd)) as a versioned **`Dictionary`** schema, **`GameState.try_apply`** ([game_state.gd](../game/domain/game_state.gd)) as the sole local mutation entry point, and **`ActionLog`** ([action_log.gd](../game/domain/action_log.gd)) with **deep-duplicated** stored and returned entries. **`MoveUnit.apply`** returns a **new `Scenario`** with a **replaced `Unit`**, preserving the **`HexMap`** reference. **`MovementRules.legal_destinations`** remains the legality oracle inside **`MoveUnit.validate`**. **[SelectionController](../game/presentation/selection_controller.gd)** submits moves only via **`try_apply`**; **destination** hit-test precedes **unit-marker** hit-test; on accept it re-points **`units_view`** / **`selection_view`** and **clears** selection.

Rationale:
Matches [ARCHITECTURE_PRINCIPLES.md](ARCHITECTURE_PRINCIPLES.md) action pipeline; keeps **`Unit`/`Scenario`** immutable per instance; **`try_apply`** is the future cloud-shaped boundary.

Caveat:
**Turn order**, **AI**, **persistence**, **structured rejection log**, **replay UI**, and **movement animation** remain **deferred**.
