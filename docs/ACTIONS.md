# Empire of Minds — Actions and local session (Phase 1.6)

## Overview

Gameplay changes are expressed as **explicit actions** (see [ARCHITECTURE_PRINCIPLES.md](ARCHITECTURE_PRINCIPLES.md)), not as ad-hoc mutation from UI or AI:

```text
intent
  -> validation
  -> application (domain)
  -> structured log append (accepted only)
  -> presentation reflects new Scenario
```

**Phase 1.6** introduces the first action type, **`move_unit`**, plus **`GameState`** (authoritative **`Scenario`** + **`ActionLog`**) and **`MoveUnit`** helpers under `game/domain/actions/`.

## MoveUnit schema (Dictionary)

Actions are plain **`Dictionary`** values with **primitive** fields so they stay **easy to serialize** later for save/load and cloud.

| Field | Type | Meaning |
|--------|------|--------|
| `schema_version` | `int` | Currently `1` (`MoveUnit.SCHEMA_VERSION`). |
| `action_type` | `String` | Must be `"move_unit"` (`MoveUnit.ACTION_TYPE`). |
| `actor_id` | `int` | **Owner** of the unit (`unit.owner_id`). Reserved for future turn checking. |
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

## GameState

**[game_state.gd](../game/domain/game_state.gd)** (`class_name GameState`, `RefCounted`):

- **`var scenario`** — current authoritative **`Scenario`**.
- **`var log`** — **`ActionLog`**.

**`try_apply(action) -> { "accepted": bool, "reason": String, "index": int }`**

- Dispatches on **`action_type`** (Phase 1.6: only **`move_unit`**).
- On **reject**: returns **`accepted: false`**, **`index: -1`**, **`scenario` and `log` unchanged**.
- On **accept**: assigns **`scenario = MoveUnit.apply(...)`**, appends a **deep-copied** entry to the log with **`result: "accepted"`**, returns **`index`**.

Invalid or unknown action types return **`unknown_action_type`** without log mutation.

## ActionLog

**[action_log.gd](../game/domain/action_log.gd)** stores **accepted** actions only in Phase 1.6.

- **`append(entry)`** stores **`entry.duplicate(true)`** and sets **`index`** on the stored copy.
- **`get_entry`** and **`entries()`** each return **duplicates** so callers cannot corrupt history.

**Rejected** moves are **not** logged (return reason only); rejection logging / replay of failures is deferred.

## Presentation boundary

- **[selection_controller.gd](../game/presentation/selection_controller.gd)** is the **only** gameplay input path in 1.6: it calls **`game_state.try_apply`**. It **does not** assign **`unit.position`** or re-build **`Scenario`** itself.
- After an **accepted** move, the controller re-points **`selection_view.scenario`**, **`units_view.scenario`**, and its optional **`scenario`** mirror to **`game_state.scenario`**, **clears selection**, and **`queue_redraw()`**.

## Explicitly deferred

- **EndTurn**, turn ownership, “only current player may move” — Phase 1.7+.
- **AI** choosing actions — Phase 1.8+ (still must call **`try_apply`**).
- **Save/load**, JSON/binary serialization, network transport — later phases.
- **Animation** of movement; units **teleport** in Phase 1.6.
- **Combat, production, cities**, multi-hex pathfinding, movement points, stacking rules.
- **Undo / redo**, replay UI, structured rejection log.
