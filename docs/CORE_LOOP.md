# Empire of Minds — Core loop (Phase 2.x checkpoint)

## Status

Phase **2.x** core loop is **feature-frozen** as a baseline. **Phase 3** extends the **content foundation** (definitions, unit types, terrain rules, project data); this document describes what already works today—not the full Phase 3 roadmap. Phase **3** replaces placeholders such as **fixed `produce_unit` cost** through **content definitions** per [CONTENT_MODEL.md](CONTENT_MODEL.md) **without changing the loop’s shape** (same actions, `try_apply`, and AI pipeline). **Phase 3.1** already gates **`FoundCity`** by **`Unit.type_id`** / **`UnitDefinitions`** (see [UNITS.md](UNITS.md)).

## Current playable loop

- **Mouse**: click a unit to select; click a **legal destination** (tinted hex) to move via `MoveUnit` through `GameState.try_apply`.
- **F**: `FoundCity` for the **selected unit** on its current tile (presentation path in `SelectionController`). **Only settler-type units** (`UnitDefinitions.can_found_city`) succeed; others are rejected. Rejected actions surface as warnings; only accepted actions append to the log.
- **P**: `SetCityProduction` with `produce_unit` for the **lowest-id** **current-player** city whose `current_project == null` (debug path in `SelectionController`).
- **Space**: `EndTurn` for the current player (`EndTurnController`).
- **A**: one rule-based AI step: `LegalActions.for_current_player(game_state)` → `RuleBasedAIPlayer.decide(game_state, legal_actions)` → `GameState.try_apply(choice)` (`AITurnController`).

Canonical rules and schemas live in [ACTIONS.md](ACTIONS.md), [CITIES.md](CITIES.md), and related domain docs. The **tiny test map / scenario** gives **each** player **one** **settler** and **one** **warrior** so the **Phase 2** AI loop shape (found → produce → move → end turn) stays intact without changing **`RuleBasedAIPlayer`**.

## Event / log order

On an **accepted** `end_turn`:

- The engine runs **`ProductionTick`** for the **ending** player and appends **`production_progress`** entries first (zero or more).
- Then **`GameState`** appends the **`end_turn`** log entry.
- Then **`ProductionDelivery`** runs for the **new** current player and appends **`unit_produced`** entries for pending ready production (zero or more).

**`GameState.try_apply(end_turn)`** returns **`accepted: true`** with **`index`** pointing at the **`end_turn`** entry—not at engine lines that follow.

Engine lines are **not** `try_apply` player actions and **must not** appear in `LegalActions`. Details: [ACTIONS.md](ACTIONS.md), [TURNS.md](TURNS.md).

## AI loop summary

From [AI_LAYER.md](AI_LAYER.md):

- If the current player owns **no** cities, the AI picks the first **`found_city`** in the legal list (if any).
- Else if the current player has **any** city with **`current_project == null`**, the AI picks the first **`set_city_production`** in the legal list (if any).
- Else the **Phase 1.8b** policy applies: at most one **`move_unit`** per turn segment (since the last log **`end_turn`**); after a move, **`end_turn`**; otherwise first **`move_unit`**, else **`end_turn`**.

`FoundCity` and `SetCityProduction` do **not** count as movement for that policy.

## Intentionally still placeholder

- **No** combat stats, **no** movement cost by **`type_id`**, **no** distinct **unit** **silhouettes** in presentation (markers unchanged).
- **`produce_unit`** uses **`cost`** **2** in the default project shape from `SetCityProduction` apply; **`ProductionDelivery`** spawns units with **`type_id`** **`"warrior"`** until **Phase 3.3** project definitions.
- **City** and **unit** markers are **placeholder** geometry and palettes (not final art).
- **Stacking** on the city hex is **allowed** when a produced unit spawns.
- **No** combat resolution, **no** save/load, **no** fog of war, **no** tech tree, **no** faction **trait** layer beyond **`UnitDefinitions`** **IDs** and **`Unit.type_id`**.

Presentation: [RENDERING.md](RENDERING.md), [SELECTION.md](SELECTION.md) (editor wiring for keys and views).

## Manual F5 checklist

1. **F5** — Map loads; units and terrain render; **Turn** HUD shows current turn and player.
2. Press **A** once — **Player 0** should **`found_city`** (unit removed, city marker visible if CitiesView is wired); log shows `found_city`.
3. Press **A** again — **Player 0** should **`set_city_production`** (`produce_unit`); log shows `set_city_production`.
4. Continue **A** — AI **moves** (if legal) and **ends turn**; on **accepted** `end_turn`, **`production_progress`** lines appear **before** the **`end_turn`** line for that step; **`unit_produced`** appears **after** that **`end_turn`** when the **recipient** becomes current (may take until a later turn boundary).
5. Confirm **`LogView`** (or structured log via tests): engine `action_type` values are visible but **never** chosen as AI legal actions—AI only emits `found_city`, `set_city_production`, `move_unit`, or `end_turn`.

Exact formatting of log lines is defined in `game/presentation/log_view.gd` (read-only helper).

## Headless validation

From the **repository root**, run **exactly**:

```text
powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1
```

Do **not** invoke `godot` directly for CI-style checks; the script resolves the executable and runs every listed headless test. Exit code **0** means all tests passed.

End-to-end loop guard: **`game/ai/tests/test_core_loop_ai_smoke.gd`** (AI drives the loop through at least one **`unit_produced`** delivery in bounded steps).

## Cross-references

- [ACTIONS.md](ACTIONS.md) — actions, `try_apply`, engine log types, legal enumeration.
- [CITIES.md](CITIES.md) — cities, founding, production projects.
- [AI_LAYER.md](AI_LAYER.md) — `LegalActions`, `RuleBasedAIPlayer`, policy.
- [TURNS.md](TURNS.md) — `TurnState`, turn order.
- [RENDERING.md](RENDERING.md) — views, draw order, debug keys at a high level.
