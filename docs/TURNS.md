# Empire of Minds — Turns (Phase 1.7)

## Overview

**Turn order** and **whose actions are accepted** live in the domain as **`TurnState`** ([turn_state.gd](../game/domain/turn_state.gd)): an immutable snapshot with **`players`** (ordered player ids), **`current_index`**, and **`turn_number`**. Advancement is **`TurnState.advance()`**, which returns a **new** instance (**`current_index`** moves with wrap; **`turn_number`** increments only when the index wraps to **0**).

Session state is **`GameState`** ([game_state.gd](../game/domain/game_state.gd)): **`scenario`**, **`turn_state`**, and **`log`**. Only **`try_apply`** mutates **`GameState`**.

## EndTurn action

**`EndTurn`** ([end_turn.gd](../game/domain/actions/end_turn.gd)) is a versioned **`Dictionary`** with **`schema_version`**, **`action_type`: `"end_turn"`**, and **`actor_id`**.

- **`EndTurn.validate(turn_state, action)`** is **structural only**: **`turn_state_null`**, **`wrong_action_type`**, **`unsupported_schema_version`**, **`malformed_action`**. It does **not** compare **`actor_id`** to the current player.
- **`GameState.try_apply`** runs a **common gate** for both **`move_unit`** and **`end_turn`**: **`actor_id`** must exist and be **`int`**, and **`actor_id`** must equal **`turn_state.current_player_id()`**; otherwise **`malformed_action`** or **`not_current_player`**. This gate runs **before** type-specific validation.
- **`EndTurn.apply`** asserts validation then returns **`turn_state.advance()`**.

Accepted **`EndTurn`** entries in **`ActionLog`** include **`turn_number_before`**, **`next_player_id`**, and **`result: "accepted"`** (plus schema, type, **`actor_id`**).

## Presentation

- **[turn_label.gd](../game/presentation/turn_label.gd)** (**`Label`**) sets text from **`compute_text(game_state)`** → **`"Turn N — Player P"`** ( **`N`** = **`turn_number`**, **`P`** = **`current_player_id()`** ). **`refresh()`** assigns **`text`**.
- **[end_turn_controller.gd](../game/presentation/end_turn_controller.gd)** handles **Space**: **`EndTurn.make(current_player_id)`** → **`try_apply`**. On accept: **clear selection**, re-point **`selection_view` / `units_view`**, **`turn_label.refresh()`**.
- **[selection_controller.gd](../game/presentation/selection_controller.gd)** calls **`turn_label.refresh()`** after an accepted **`MoveUnit`**.

## Explicitly deferred

- Simultaneous turns, phase sub-steps, production-only phases, turn timers.
- AI **`EndTurn`** — Phase 1.8+.
- Network sync and server-side turn resolution.
