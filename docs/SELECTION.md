# Empire of Minds — Selection (Phase 1.5)

## What selection is

**Selection** is **client/UI state**: which unit the player has **focused** to inspect legal moves. It is **not** authoritative gameplay state and **must not** be stored on **`Unit`**, **`Scenario`**, or **`HexMap`**.

## Components (presentation only)

| Piece | Role |
|--------|------|
| **`SelectionState`** ([selection_state.gd](../game/presentation/selection_state.gd)) | `RefCounted` holder of **`unit_id: int`** (`NONE = -1`). `select`, `clear`, `is_empty`, `equals`. |
| **`SelectionController`** ([selection_controller.gd](../game/presentation/selection_controller.gd)) | `Node2D` with **`_unhandled_input`**: left-click hit-test against **unit marker positions** (`HexLayout.hex_to_world` + radius); updates **`SelectionState`**; **`selection_view.queue_redraw()`** only. **Does not** reference **`UnitsView`**. |
| **`SelectionView`** ([selection_view.gd](../game/presentation/selection_view.gd)) | `Node2D` **`_draw`**: derives ring + destination overlays via **`SelectionView.compute_overlay_items(scenario, layout, selection)`** and **`MovementRules.legal_destinations`**. **No** input. |

## Wiring

**[main.gd](../game/main.gd)** builds one **`Scenario`**, **`HexLayout`**, and **`SelectionState`**, assigns them to **`MapView`**, **`UnitsView`**, **`SelectionView`**, and **`SelectionController`**. Scene order under **`Main`**: **`MapView`** → **`SelectionView`** → **`UnitsView`** (overlays between terrain and markers) → **`SelectionController`** (invisible input node).

## Interaction (Phase 1.5)

- **Click** a unit marker → **`selection.select(unit_id)`**; overlays show **selected hex ring** and **legal destination** fills.
- **Click** empty space → **`selection.clear()`**; overlays clear.
- **No** movement, **no** actions, **no** logging, **no** turn checks.

Highlights are **purely derived** from **`(scenario, layout, selection)`**; they are **never** a source of truth for positions or legality.

## Explicitly deferred

- Hover, tooltips, keyboard selection, multi-select.
- Clicking a **destination** hex to move (Phase 1.6 **`MoveUnit`**).
- “Current player may only select own units” (Phase 1.7+).
- Animations, sounds, selection VFX beyond simple draw.
