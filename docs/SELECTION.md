# Empire of Minds — Selection (Phase 1.5+)

## What selection is

**Selection** is **client/UI state**: which unit the player has **focused** to inspect legal moves. It is **not** authoritative gameplay state and **must not** be stored on **`Unit`**, **`Scenario`**, or **`HexMap`**.

## Components (presentation only)

| Piece | Role |
|--------|------|
| **`SelectionState`** ([selection_state.gd](../game/presentation/selection_state.gd)) | `RefCounted` holder of **`unit_id`** and **`city_id`** (**`NONE = -1`**), **mutually exclusive** focus: **`select(unit)`** clears **`city_id`**; **`select_city(city)`** clears **`unit_id`**. **`clear_unit()`** / **`clear_city()`**; **`clear()`** clears both. **`has_city()`**; **`is_empty()`** is **`unit_id == NONE`** (so **city-only** focus still counts as “empty” for **unit** shortcuts such as **F** / move). **`equals`**. |
| **`SelectionController`** ([selection_controller.gd](../game/presentation/selection_controller.gd)) | `Node2D` with **`_unhandled_input`**: see **Interaction** below. Holds **`game_state`**, **`units_view`**, **`turn_label`** (optional), **`selection_view`**, **`layout`**, **`selection`**, optional **`scenario`** mirror, optional **`city_production_panel`**. **Does not** mutate **`Unit`** / **`Scenario`** directly — only **`game_state.try_apply`**. |
| **`SelectionView`** ([selection_view.gd](../game/presentation/selection_view.gd)) | `Node2D` **`_draw`**: derives ring + destination overlays via **`compute_overlay_items(scenario, layout, selection)`** and **`MovementRules.legal_destinations`**. **No** input. |

## Wiring

**[main.gd](../game/main.gd)** builds **`GameState`**, **`HexLayout`**, **`SelectionState`**, assigns **`scenario.map`** / **`layout`** to **`MapView`**, **`scenario`** / **`layout`** / **`selection`** to **`SelectionView`** and **`UnitsView`**, wires **`SelectionController`** ( **`game_state`**, **`units_view`**, **`turn_label`**, **`selection_view`**, **`layout`**, **`selection`**, **`city_production_panel`** ), **`TurnLabel.game_state`**, **`refresh()`**, **`EndTurnController`**, **`CityProductionPanel`**, and **`AITurnController`**. See [TURNS.md](TURNS.md).

Scene order under **`Main`**: **`TurnLabel`** → **`HudCanvas`** (**`CityProductionPanel`**) → **`MapView`** → **`CitiesView`** → **`SelectionView`** → **`UnitsView`** → **`TerrainForegroundView`** → **`SelectionController`** → **`EndTurnController`** / **`AITurnController`** / **`LogView`** (see **[main.tscn](../game/main.tscn)**).

**Phase 1.7:** Any unit may be **selected** (marker hit-test); **`MoveUnit`** is rejected with **`not_current_player`** if the unit’s **`owner_id`** does not match **`turn_state.current_player_id()`** ( **`SelectionController`** passes **`u.owner_id`** as **`actor_id`**). **Space** → **`EndTurn`** clears **unit** selection only (**`selection.clear_unit()`**) on accept so a **focused city** (if any) **stays selected** for the production HUD; **`CityProductionPanel.refresh()`** runs after **Space** / **AI** accept so status stays in sync. **Deferred:** restricting selection UI to owned units only.

## Interaction

**Phase 4.5m / 4.5n:** **`[main.gd](../game/main.gd)`** **`_input`** handles **right-drag** **pan** (**`MapCamera.camera_world_offset`**) and **mouse-wheel** **zoom** (**`set_zoom_clamped`**, **center** = **`viewport * 0.5 - MAP_LAYER_ORIGIN`**; **not** **cursor**-**anchored** **zoom**). **`SelectionController`** remains **left-button** only for **moves** / **selection** **[ACTIONS.md](ACTIONS.md)**; **`vanishing_pres`** is set **once** in **`_ready`**; **picking** uses **`camera.to_presentation`** like **`MapView`** at any **zoom**.

On **left mouse pressed**, **`SelectionController`** (see [ACTIONS.md](ACTIONS.md)):

1. If **selection is not empty**: compute **`MovementRules.legal_destinations(game_state.scenario, selection.unit_id)`**. **Phase 4.5f:** if the click lies **inside** the **projected** **hex** **polygon** of a legal destination (**`Geometry2D.is_point_in_polygon`** on **`camera.to_presentation`** of **`layout.hex_corners`** — same **layer-local** space as **`to_local(mouse)`**), build **`MoveUnit.make(u.owner_id, ...)`** and call **`game_state.try_apply(action)`**. **Return** after this block (accepted or rejected). On **accept**: assign **`selection_view.scenario`**, **`units_view.scenario`**, and controller **`scenario`** to **`game_state.scenario`**, **clear selection**, **`queue_redraw()`** both views, **`turn_label.refresh()`** if wired. On **reject**: **`push_warning`** with reason (**`not_current_player`** when it is not that player’s turn).  
   **This order runs before unit-marker hit-testing** so clicking a highlighted destination that overlaps another unit’s marker still moves the **selected** unit.

2. Else: **city** hex hit-test (same **projected** hex **polygon**). **Lowest** **`city.id`** when several cities match the cursor (rare). Let **(q,r)** be that city’s tile.

   - If **any** **current-player** unit occupies **(q,r)** (**shared** tile): use **click alternation** in **`SelectionController`** (see **`plan_shared_hex_pick`**): **first** click **(after** focus moves to another hex, **selection.clear**, **successful MoveUnit**, or **selecting** a unit on a tile **without** a city hit**)** → **`select_city`**; **second** click same **(q,r)** → **`select`** the **lowest-id** current-player unit on that tile; **third** → **city** again; repeats.

   - Else (**city-only** tile): **`selection.select_city`**.

3. Else: **unit** hex hit-test on **`scenario.units()`** (same **polygon** rules as before).

4. Else: **`selection.clear()`**, redraw, **`city_production_panel.refresh()`** when wired.

Highlights remain **derived** from **`(scenario, layout, selection)`**; they are not authoritative. After a move, **`scenario`** on the views is the **current** snapshot from **`game_state`**.

## Explicitly deferred

- Per-hex **unit** round-robin when **several** **own** units share a **city** tile (**lowest unit id** only on the **unit** step today).
- Hover, tooltips, keyboard selection, multi-select.
- Hiding or disabling selection for units not owned by the current player (only move rejection exists in Phase 1.7).
- Animations, sounds, selection VFX beyond simple draw.
