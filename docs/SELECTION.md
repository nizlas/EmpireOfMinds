# Empire of Minds — Selection (Phase 1.5+)

## What selection is

**Selection** is **client/UI state**: which unit the player has **focused** to inspect legal moves. It is **not** authoritative gameplay state and **must not** be stored on **`Unit`**, **`Scenario`**, or **`HexMap`**.

## Components (presentation only)

| Piece | Role |
|--------|------|
| **`SelectionState`** ([selection_state.gd](../game/presentation/selection_state.gd)) | `RefCounted` holder of **`unit_id: int`** (`NONE = -1`). `select`, `clear`, `is_empty`, `equals`. |
| **`SelectionController`** ([selection_controller.gd](../game/presentation/selection_controller.gd)) | `Node2D` with **`_unhandled_input`**: see **Interaction** below. Holds **`game_state`**, **`units_view`** (to re-point **`scenario`** after an accepted move), **`selection_view`**, **`layout`**, **`selection`**, optional **`scenario`** mirror. **Does not** mutate **`Unit`** / **`Scenario`** directly — only **`game_state.try_apply`**. |
| **`SelectionView`** ([selection_view.gd](../game/presentation/selection_view.gd)) | `Node2D` **`_draw`**: derives ring + destination overlays via **`compute_overlay_items(scenario, layout, selection)`** and **`MovementRules.legal_destinations`**. **No** input. |

## Wiring

**[main.gd](../game/main.gd)** builds **`GameState`** over the initial **`Scenario`**, **`HexLayout`**, **`SelectionState`**, assigns **`scenario.map`** / **`layout`** to **`MapView`**, **`scenario`** / **`layout`** / **`selection`** to **`SelectionView`** and **`UnitsView`**, and wires **`SelectionController`** with **`game_state`**, **`units_view`**, **`selection_view`**, **`layout`**, **`selection`**.

Scene order under **`Main`**: **`MapView`** → **`SelectionView`** → **`UnitsView`** → **`SelectionController`**.

## Interaction

On **left mouse pressed**, **`SelectionController`** (see [ACTIONS.md](ACTIONS.md)):

1. If **selection is not empty**: compute **`MovementRules.legal_destinations(game_state.scenario, selection.unit_id)`**. If the click is within **`HexLayout.SIZE * 0.85`** of a legal hex **center**, build **`MoveUnit.make(...)`** and call **`game_state.try_apply(action)`**. **Return** after this block (accepted or rejected). On **accept**: assign **`selection_view.scenario`**, **`units_view.scenario`**, and controller **`scenario`** to **`game_state.scenario`**, **clear selection**, **`queue_redraw()`** both views. On **reject**: **`push_warning`** with reason.  
   **This order runs before unit-marker hit-testing** so clicking a highlighted destination that overlaps another unit’s marker still moves the **selected** unit.

2. Else: **unit-marker hit-test** on **`game_state.scenario.units()`** (radius **`marker_hit_radius_ratio * SIZE`**) → **`selection.select`**, **`selection_view.queue_redraw()`**, return.

3. Else: **`selection.clear()`**, **`selection_view.queue_redraw()`**.

Highlights remain **derived** from **`(scenario, layout, selection)`**; they are not authoritative. After a move, **`scenario`** on the views is the **current** snapshot from **`game_state`**.

## Explicitly deferred

- Hover, tooltips, keyboard selection, multi-select.
- “Current player may only select/move own units” (Phase 1.7+).
- Animations, sounds, selection VFX beyond simple draw.
