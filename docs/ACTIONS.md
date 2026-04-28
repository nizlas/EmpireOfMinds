# Empire of Minds — Actions and local session (Phase 1.6+)

## Overview

Gameplay changes are expressed as **explicit actions** (see [ARCHITECTURE_PRINCIPLES.md](ARCHITECTURE_PRINCIPLES.md)), not as ad-hoc mutation from UI or AI:

```text
intent
  -> validation
  -> application (domain)
  -> structured log append (accepted only)
  -> presentation reflects new Scenario
```

**Phase 1.6** introduces **`move_unit`**, **`GameState`**, and **`ActionLog`**. **Phase 1.7** adds **`TurnState`**, **`end_turn`**, and a **common current-player gate** in **`GameState.try_apply`** (see [TURNS.md](TURNS.md)).

## MoveUnit schema (Dictionary)

Actions are plain **`Dictionary`** values with **primitive** fields so they stay **easy to serialize** later for save/load and cloud.

| Field | Type | Meaning |
|--------|------|--------|
| `schema_version` | `int` | Currently `1` (`MoveUnit.SCHEMA_VERSION`). |
| `action_type` | `String` | Must be `"move_unit"` (`MoveUnit.ACTION_TYPE`). |
| `actor_id` | `int` | **Owner** of the unit (`unit.owner_id`); must match **`GameState.turn_state.current_player_id()`** when **`try_apply`** runs (common gate). |
| `unit_id` | `int` | Unit to move. |
| `from` | `Array` of two `int` | `[q, r]` must match the unit’s current `position`. |
| `to` | `Array` of two `int` | `[q, r]` destination; must be in **`MovementRules.legal_destinations`** for that unit. |

Built with **`MoveUnit.make(actor_id, unit_id, from_q, from_r, to_q, to_r)`** in [game/domain/actions/move_unit.gd](../game/domain/actions/move_unit.gd).

## Validation

**`MoveUnit.validate(scenario, action) -> { "ok": bool, "reason": String }`** runs checks in a **fixed order** (stable, testable reasons):

1. `scenario_null`
2. `wrong_action_type`
3. `unsupported_schema_version`
4. `malformed_action`
5. `unknown_unit`
6. `actor_not_owner`
7. `from_does_not_match_unit_position`
8. `destination_not_legal` — uses **`MovementRules.legal_destinations`** and **`HexCoord.equals`**.

## Application

**`MoveUnit.apply(scenario, action)`** may run only when **`validate`** returned **`ok`**.

- **Does not** mutate the input **`Unit`** or **`Scenario`**.
- Builds a **new** **`Unit`** for the moved id with the new **`HexCoord`**, copies other unit references from **`scenario.units()`**, and returns **`Scenario.new(scenario.map, new_units)`**.

## EndTurn schema (Phase 1.7)

| Field | Type | Meaning |
|--------|------|--------|
| `schema_version` | `int` | `1` (`EndTurn.SCHEMA_VERSION`). |
| `action_type` | `String` | `"end_turn"`. |
| `actor_id` | `int` | Must equal **`turn_state.current_player_id()`** at **`try_apply`** (enforced in **`GameState`**, not in **`EndTurn.validate`**). |

Built with **`EndTurn.make(actor_id)`** in [end_turn.gd](../game/domain/actions/end_turn.gd). **`EndTurn.validate`** is structural only; **`not_current_player`** is returned only from **`GameState.try_apply`**.

**`EndTurn.apply(turn_state, action)`** returns **`turn_state.advance()`** (new **`TurnState`**).

## GameState

**[game_state.gd](../game/domain/game_state.gd)** (`class_name GameState`, `RefCounted`):

- **`var scenario`** — current authoritative **`Scenario`**.
- **`var turn_state`** — immutable **`TurnState`** snapshot; replaced when **`end_turn`** applies.
- **`var log`** — **`ActionLog`**.

**`try_apply(action) -> { "accepted": bool, "reason": String, "index": int }`**

- **`action`** must be a **`Dictionary`** with string **`action_type`** **`move_unit`** or **`end_turn`**; otherwise **`unknown_action_type`** (also **`null`** / non-dict / missing **`action_type`** / non-string **`action_type`**).
- **Common gate** (both action types): **`actor_id`** must be present and **`TYPE_INT`**; **`actor_id == turn_state.current_player_id()`** or **`malformed_action`** / **`not_current_player`**.
- **`move_unit`**: **`MoveUnit.validate` → apply →** log entry as in Phase 1.6.
- **`end_turn`**: **`EndTurn.validate` → apply →** log entry includes **`turn_number_before`**, **`next_player_id`**, **`result: "accepted"`**.

On **reject**: **`accepted: false`**, **`index: -1`**, no log append, **`scenario` / `turn_state` / `log`** unchanged (except where only validation failed after gate — still no mutation).

On **accept**: updates **`scenario`** and/or **`turn_state`**, appends **deep-copied** log entry, returns **`index`**.

## ActionLog

**[action_log.gd](../game/domain/action_log.gd)** stores **accepted** **`move_unit`** and **`end_turn`** actions (Phase 1.6+).

- **`append(entry)`** stores **`entry.duplicate(true)`** and sets **`index`** on the stored copy.
- **`get_entry`** and **`entries()`** each return **duplicates** so callers cannot corrupt history.

**Rejected** moves are **not** logged (return reason only); rejection logging / replay of failures is deferred.

## Presentation boundary

- **[selection_controller.gd](../game/presentation/selection_controller.gd)** submits **`MoveUnit`** via **`try_apply`** on **left-click**. **[end_turn_controller.gd](../game/presentation/end_turn_controller.gd)** submits **`EndTurn`** on **Space**. Neither assigns **`unit.position`** or re-builds **`Scenario`** outside **`try_apply`**.
- After an **accepted** **`MoveUnit`**, **`SelectionController`** re-points **`selection_view.scenario`**, **`units_view.scenario`**, and its optional **`scenario`** mirror to **`game_state.scenario`**, **clears selection**, **`queue_redraw()`**, and **`turn_label.refresh()`** when **`turn_label`** is wired.
- After an **accepted** **`EndTurn`**, **`EndTurnController`** **clears selection**, re-points **`selection_view` / `units_view`**, **`queue_redraw()`**, **`turn_label.refresh()`**.

## Explicitly deferred

- Turn **phases** (movement vs production), **lobby / seating**, **async** turn submission.
- **AI** choosing actions — Phase 1.8+ (still must call **`try_apply`**).
- **Save/load**, JSON/binary serialization, network transport — later phases.
- **Animation** of movement; units **teleport** in Phase 1.6.
- **Combat, production, cities**, multi-hex pathfinding, movement points, stacking rules.
- **Undo / redo**, replay UI, structured rejection log.
