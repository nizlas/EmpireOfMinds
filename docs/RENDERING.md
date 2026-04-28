# Empire of Minds — Rendering (Phase 1.3+)

## Presentation boundary

- **`game/presentation/`** may use Godot `Node2D` / `CanvasItem` and drawing APIs. It must **not** own authoritative game rules or mutable domain objects as the long-term source of truth.
- **`game/domain/`** remains the home of `HexMap`, `HexCoord`, and other rule-state types. The presentation layer **reads the domain** (e.g. `coords()`, `terrain_at()`) to decide what to draw. **Rendered** geometry is a **derived view**; `HexMap` is still the source of which cells exist and what terrain they have.

## Phase 1.3 approach

- A single **[MapView](../game/presentation/map_view.gd)** `Node2D` overrides **`_draw()`** to fill the screen with the map.
- **`MapView.compute_draw_items(map, layout)`** is a **pure** static helper: it takes a `HexMap` and a [HexLayout](../game/presentation/hex_layout.gd), iterates **`map.coords()`** (the domain list of `HexCoord`), and returns draw lists with world position, hex corners, and colors. It does **not** use a hand-authored coordinate list and does not read `HexMap` internal storage.
- **HexLayout** implements **pointy-top** axial \((q, r) \to\) `Vector2` and six vertex positions for a hex of circumradius 32. See [HEX_COORDINATES.md](HEX_COORDINATES.md) for domain axial meaning; layout orientation is a presentation choice.

## Map-driven coordinates

- Rendered cell positions and counts **derive from** `map.coords()`. The tiny test map from `HexMap.make_tiny_test_map()` is the same domain object used in tests; **no** duplicate fixture list in the view.

## Placeholder terrain palette (Phase 1.3)

- `HexMap.Terrain.PLAINS` — flat greenish `Color(0.50, 0.78, 0.47)`.
- `HexMap.Terrain.WATER` — flat blue `Color(0.20, 0.45, 0.80)`.
- Unknown terrain (should not happen for current enums) — magenta `Color(1, 0, 1)` for visibility.

This is not final art, branding, or a committed palette for release.

## Optional labels (Phase 1.3)

- Coordinate text on tiles is **optional**; the first implementation may draw **polygons only** to stay robust across Godot versions. If labels are added later, they remain presentation-only and must not become gameplay state.

## Explicitly deferred

- `Camera2D` (pan / zoom), parallax, fit-to-screen.
- **Input** beyond Phase 1.5 unit pick / clear (menus, camera drag, global shortcuts), **hover**, tooltips.
- **TileMap** / `TileSet`, atlases, custom meshes, particles.
- **Animation** (`Tween` / `AnimationPlayer`) for map cells.
- **Theme**, custom **fonts** (other than default).
- Shipped **art** and a **final** terrain palette and accessibility contrast review.

## Phase 1.4b — Unit markers

- **[UnitsView](../game/presentation/units_view.gd)** is a **`Node2D`** **sibling** of **MapView** under **`Main`** in [main.tscn](../game/main.tscn). **Draw order:** **MapView** → **SelectionView** (Phase 1.5) → **UnitsView**, so terrain is bottom, selection overlays mid, markers top. **[main.gd](../game/main.gd)** creates **`GameState`** over the initial **`Scenario`**, **`HexLayout`**, and **`SelectionState`**, assigns **`scenario.map`** and **`layout`** to **MapView**, `scenario` / `layout` / `selection` to **SelectionView** and **UnitsView**, and wires **SelectionController** with **`game_state`**, **`units_view`**, **`selection_view`**, **`layout`**, **`selection`** — so views can follow **`game_state.scenario`** after Phase 1.6 moves (see [ACTIONS.md](ACTIONS.md)).
- **MapView** still derives which hexes to draw and terrain colors from **`HexMap`** (via `coords()` / `terrain_at()`). **UnitsView** derives marker positions, colors, and count **only** from **`Scenario.units()`** through the static **`UnitsView.compute_marker_items(scenario, layout)`** — not from a hand-authored coordinate list. Markers are **simple filled circles** with a thin **`draw_arc` outline**; **owner_id** maps to a **placeholder** warm yellow / red / magenta via **`_owner_to_color`**. Markers are a **derived view**; **`Unit` / `Scenario` remain the source of truth** for which units exist and where.
- **Not in Phase 1.4b:** movement, **animation**, **sprites**, the warrior asset, **labels**, health bars, an asset pipeline, a final owner palette, or any **gameplay rules** (input and **presentation-only** selection arrive in Phase 1.5; see [SELECTION.md](SELECTION.md)).

## Phase 1.5 — Selection overlay

- **[SelectionView](../game/presentation/selection_view.gd)** is a **`Node2D`** sibling **between** **MapView** and **UnitsView** (see [main.tscn](../game/main.tscn)): terrain → **destination tint fills + selected-hex ring** → unit markers. Overlays are computed by **`SelectionView.compute_overlay_items(scenario, layout, selection)`**, which uses **`MovementRules.legal_destinations`**; **no** parallel coordinate list.
- **[SelectionController](../game/presentation/selection_controller.gd)** handles **`_unhandled_input`**: when a unit is selected, **legal-destination** hit-test runs **before** unit-marker hit-test so overlapping markers do not block moves. Submits **`MoveUnit`** via **`GameState.try_apply`**; **`push_warning`** on reject. Re-points **`UnitsView`** / **`SelectionView`** after accept. See [SELECTION.md](SELECTION.md), [ACTIONS.md](ACTIONS.md).
- Destination hexes use a **translucent fill**; the **selected** cell uses a **closed polyline** ring (built from hex corners + closing vertex). **No** animation or shipped assets.

## Phase 1.6 — MoveUnit and refreshed views

- After an **accepted** **`MoveUnit`** via **`GameState.try_apply`**, **`SelectionController`** re-points **`UnitsView.scenario`** and **`SelectionView.scenario`** to **`game_state.scenario`** and **`queue_redraw()`**; markers jump to the new hex (no tween). See [ACTIONS.md](ACTIONS.md) and [SELECTION.md](SELECTION.md).

## Phase 1.7 — Turn label

- **`TurnLabel`** ([turn_label.gd](../game/presentation/turn_label.gd)) is a **`Label`** child of **`Main`** (renamed from the placeholder label in [main.tscn](../game/main.tscn)). Text is **`Turn N — Player P`** from **`compute_text(game_state)`**; **`main.gd`** assigns **`game_state`** and calls **`refresh()`** at startup. **`SelectionController`** and **`EndTurnController`** call **`refresh()`** after accepted actions so the HUD tracks **`TurnState`** (see [TURNS.md](TURNS.md)).

## Phase 1.8 — AI turn trigger

- **`AITurnController`** ([ai_turn_controller.gd](../game/presentation/ai_turn_controller.gd)) is a **`Node2D`** **last** child of **`Main`** (after **`EndTurnController`**) in [main.tscn](../game/main.tscn): **`KEY_A`** (no echo) calls **`LegalActions.for_current_player`**, **`RuleBasedAIPlayer.decide`**, then **`game_state.try_apply`** once. On accept it **clears selection**, re-points **`selection_view.scenario`** and **`units_view.scenario`**, **`queue_redraw()`**, **`turn_label.refresh()`**. See [AI_LAYER.md](AI_LAYER.md), [ACTIONS.md](ACTIONS.md).

## Phase 1.9 — Action log debug view

- **`LogView`** ([log_view.gd](../game/presentation/log_view.gd)) is a **`Label`** child of **`Main`** (placed low on the screen so it does not overlap **`TurnLabel`**). It shows the **last `MAX_ENTRIES` (10)** accepted log lines via **`compute_text(game_state)`**, **oldest at top, newest at bottom**; it reads only **`game_state.log.size()`** and **`game_state.log.get_entry(i)`** and **never mutates** domain state. **`main.gd`** assigns **`game_state`** and calls **`refresh()`** once at startup. **`SelectionController`**, **`EndTurnController`**, and **`AITurnController`** call **`log_view.refresh()`** after each **accepted** action ( **`log_view`** is optional — **null-safe**). This is a **debug** surface only: **no** replay, **no** undo/redo, **no** polling or **`_process`** (see [ACTIONS.md](ACTIONS.md)).

## Phase 2.1 — City placeholder markers

- **`CitiesView`** ([cities_view.gd](../game/presentation/cities_view.gd)) is a **`Node2D`** sibling **after** **`MapView`** and **before** **`SelectionView`** in [main.tscn](../game/main.tscn). **Draw order:** **terrain → cities → selection overlay → unit markers** ( **`UnitsView`** remains topmost among map-layer siblings). Markers are **filled diamonds** derived from **`Scenario.cities()`** via **`compute_marker_items`**, **`owner_id`** → cool placeholder palette; **not** final art.
- The canonical **`make_tiny_test_scenario()`** has **zero** cities; **`CitiesView`** is wired so **Phase 2.2+** can show markers without scene churn. Domain and tests use explicit **`City`** lists where needed (see [CITIES.md](CITIES.md)).
- **No** **`FoundCity`**, **no** **`try_apply`** changes, **no** controller re-point of **`CitiesView`** in this subphase.
