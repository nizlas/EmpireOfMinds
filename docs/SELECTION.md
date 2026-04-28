# Empire of Minds — Selection (Phase 1.5+)

## What selection is

**Selection** is **client/UI state**: which unit the player has **focused** to inspect legal moves. It is **not** authoritative gameplay state and **must not** be stored on **`Unit`**, **`Scenario`**, or **`HexMap`**.

## Components (presentation only)

| Piece | Role |
|--------|------|
| **`SelectionState`** ([selection_state.gd](../game/presentation/selection_state.gd)) | `RefCounted` holder of **`unit_id: int`** (`NONE = -1`). `select`, `clear`, `is_empty`, `equals`. |
| **`SelectionController`** ([selection_controller.gd](../game/presentation/selection_controller.gd)) | `Node2D` with **`_unhandled_input`**: see **Interaction** below. Holds **`game_state`**, **`units_view`**, **`turn_label`** (optional), **`selection_view`**, **`layout`**, **`selection`**, optional **`scenario`** mirror. **Does not** mutate **`Unit`** / **`Scenario`** directly — only **`game_state.try_apply`**. |
| **`SelectionView`** ([selection_view.gd](../game/presentation/selection_view.gd)) | `Node2D` **`_draw`**: derives ring + destination overlays via **`compute_overlay_items(scenario, layout, selection)`** and **`MovementRules.legal_destinations`**. **No** input. |

## Wiring

**[main.gd](../game/main.gd)** builds **`GameState`**, **`HexLayout`**, **`SelectionState`**, assigns **`scenario.map`** / **`layout`** to **`MapView`**, **`scenario`** / **`layout`** / **`selection`** to **`SelectionView`** and **`UnitsView`**, wires **`SelectionController`** ( **`game_state`**, **`units_view`**, **`turn_label`**, **`selection_view`**, **`layout`**, **`selection`** ), **`TurnLabel.game_state`**, **`refresh()`**, and **`EndTurnController`**. See [TURNS.md](TURNS.md).

Scene order under **`Main`**: **`TurnLabel`** (HUD) → **`MapView`** → **`SelectionView`** → **`UnitsView`** → **`SelectionController`** → **`EndTurnController`** (last for input, position **`(0,0)`**).

**Phase 1.7:** Any unit may be **selected** (marker hit-test); **`MoveUnit`** is rejected with **`not_current_player`** if the unit’s **`owner_id`** does not match **`turn_state.current_player_id()`** ( **`SelectionController`** passes **`u.owner_id`** as **`actor_id`**). **Space** → **`EndTurn`** clears selection on accept (see **`EndTurnController`**). **Deferred:** restricting selection UI to owned units only.

## Interaction

On **left mouse pressed**, **`SelectionController`** (see [ACTIONS.md](ACTIONS.md)):

1. If **selection is not empty**: compute **`MovementRules.legal_destinations(game_state.scenario, selection.unit_id)`**. If the click is within **`HexLayout.SIZE * 0.85`** of a legal hex **center**, build **`MoveUnit.make(u.owner_id, ...)`** and call **`game_state.try_apply(action)`**. **Return** after this block (accepted or rejected). On **accept**: assign **`selection_view.scenario`**, **`units_view.scenario`**, and controller **`scenario`** to **`game_state.scenario`**, **clear selection**, **`queue_redraw()`** both views, **`turn_label.refresh()`** if wired. On **reject**: **`push_warning`** with reason (**`not_current_player`** when it is not that player’s turn).  
   **This order runs before unit-marker hit-testing** so clicking a highlighted destination that overlaps another unit’s marker still moves the **selected** unit.

2. Else: **unit-marker hit-test** on **`game_state.scenario.units()`** (radius **`marker_hit_radius_ratio * SIZE`**) → **`selection.select`**, **`selection_view.queue_redraw()`**, return.

3. Else: **`selection.clear()`**, **`selection_view.queue_redraw()`**.

Highlights remain **derived** from **`(scenario, layout, selection)`**; they are not authoritative. After a move, **`scenario`** on the views is the **current** snapshot from **`game_state`**.

## Explicitly deferred

- Hover, tooltips, keyboard selection, multi-select.
- Hiding or disabling selection for units not owned by the current player (only move rejection exists in Phase 1.7).
- Animations, sounds, selection VFX beyond simple draw.
