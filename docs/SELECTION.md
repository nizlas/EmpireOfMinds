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

1. If **selection is not empty**: compute **`MovementRules.legal_destinations(game_state.scenario, selection.unit_id)`**. **Phase 4.5f:** if the click lies **inside** the **projected** **hex** **polygon** of a legal destination (**`Geometry2D.is_point_in_polygon`** on **`projection.to_presentation`** of **`layout.hex_corners`** — same **layer-local** space as **`to_local(mouse)`**), build **`MoveUnit.make(u.owner_id, ...)`** and call **`game_state.try_apply(action)`**. **Return** after this block (accepted or rejected). On **accept**: assign **`selection_view.scenario`**, **`units_view.scenario`**, and controller **`scenario`** to **`game_state.scenario`**, **clear selection**, **`queue_redraw()`** both views, **`turn_label.refresh()`** if wired. On **reject**: **`push_warning`** with reason (**`not_current_player`** when it is not that player’s turn).  
   **This order runs before unit-marker hit-testing** so clicking a highlighted destination that overlaps another unit’s marker still moves the **selected** unit.

2. Else: **unit hex hit-test** on **`game_state.scenario.units()`** — **Phase 4.5f:** pointer in **layer-local** presentation space vs **projected** **hex** **polygon** (**`Geometry2D.is_point_in_polygon`** on **`projection.to_presentation`** corners; aligns with **drawn** terrain). **Phase 4.5h:** **`anchor_pres = projection.to_presentation(layout.hex_to_world(q,r))`** for markers (**layout** **hex** **center**). **Phase 4.5i** / **4.5j** / **4.5k:** **textured** **units** align **`anchor_pres`** to **resolved** **pivot** (**defaults** **`unit_marker_pivot_*`**, **plus** **`_UNIT_MARKER_PIVOT_BY_TYPE`** **for** **specific** **`type_id`** **e.g.** **`settler`**, **`pivot`** **`Y`** **`0.86`**); **fallback** circle/glyph stays **on** **`anchor_pres`**. **`marker_hit_radius_ratio`** remains on **`SelectionController`** for scene compatibility but is **not** used for this path.

3. Else: **`selection.clear()`**, **`selection_view.queue_redraw()`**.

Highlights remain **derived** from **`(scenario, layout, selection)`**; they are not authoritative. After a move, **`scenario`** on the views is the **current** snapshot from **`game_state`**.

## Explicitly deferred

- Hover, tooltips, keyboard selection, multi-select.
- Hiding or disabling selection for units not owned by the current player (only move rejection exists in Phase 1.7).
- Animations, sounds, selection VFX beyond simple draw.
