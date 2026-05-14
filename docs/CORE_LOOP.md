# Empire of Minds — Core loop (Phase 2.x checkpoint)

## Status

Phase **2.x** core loop is **feature-frozen** as a baseline. **Phase 3** extends the **content foundation** (definitions, unit types, terrain rules, project data); this document describes what already works today—not the full Phase 3 roadmap. Phase **3** replaces placeholders such as **fixed `produce_unit` cost** through **content definitions** per [CONTENT_MODEL.md](CONTENT_MODEL.md) **without changing the loop’s shape** (same actions, `try_apply`, and AI pipeline). **Phase 3.1** already gates **`FoundCity`** by **`Unit.type_id`** / **`UnitDefinitions`** (see [UNITS.md](UNITS.md)).

**Phase 3.4a:** [PROGRESSION_MODEL.md](PROGRESSION_MODEL.md) records **Phase 3.4a** as the preliminary documentation checkpoint before progression code landed; subsequent **Phase 3.4b–h** and **5.1.x** slices shipped progression/science work there—not “future sciences only”.  
The movement / founding / production / **`end_turn`** / **`ProductionDelivery`** spine is unchanged **in spirit**; **Phase 5.1** overlays **science accumulation**, **`controlled_fire`** completion on the prototype map, and **`produce_unit:settler`** on the same **`try_apply`** path.

**Phase 3.4b:** **`ProgressDefinitions`** ([progress_definitions.gd](../game/domain/content/progress_definitions.gd)) adds **metadata-only** seed sciences — the **playable loop** is **unchanged**; no gating or new player-facing rules.

**Phase 3.4c:** **`GameState`** seeds **`ProgressState`** so **initial players** have **`city_project` / `produce_unit:warrior`** and **`city_project` / `produce_unit:settler`** unlocked (**Phase 5.1.12d** aligns defaults)—the core movement / founding / production / **`end_turn`** / **`ProductionDelivery`** loop stays recognizable without rewriting **`RuleBasedAIPlayer`**.

**Phase 3.4e:** **`complete_progress`** is a **domain** action (**`GameState.try_apply`**) with **no** **`LegalActions`** enumeration and **no** **AI** use.

**Phase 3.4f:** **`KEY_G`** in **`SelectionController`** is a **manual** debug path that submits **`CompleteProgress`** for **`foraging_systems`** (**not** **`LegalActions`**, **not** **AI**); on **accept** it refreshes **`LogView`** (and **`TurnLabel`**) only.

**Phase 3.4g:** **`ProgressDetector`** ([progress_detector.gd](../game/domain/progress_detector.gd)) is a **domain** **read-only** helper that can **propose** **`CompleteProgress`** candidates from the **log**; **by itself** it does **not** change runtime; **Phase 3.4h** **`KEY_H`** is the **manual** path that consumes those suggestions for the **current player**.

**Phase 3.4h:** **`ProgressCandidateFilter`** + **`KEY_H`** in **`SelectionController`** manually apply the **first** **`ProgressDetector`** candidate **for the current player** via **`try_apply`**. This is **orthogonal** to automatic **`controlled_fire`** progress from **`ScienceTick`** during **`EndTurn`** (see [PROGRESSION_MODEL.md](PROGRESSION_MODEL.md)).

- **Mouse**: click a unit to select; click a **legal destination** (tinted hex) to move via `MoveUnit` through `GameState.try_apply`.
- **F**: `FoundCity` for the **selected unit** on its current tile (presentation path in `SelectionController`). **Only settler-type units** (`UnitDefinitions.can_found_city`) succeed; others are rejected. Rejected actions surface as warnings; only accepted actions append to the log.
- **P**: `SetCityProduction` with **`project_id`** **`produce_unit:warrior`** for the **lowest-id** **current-player** city whose `current_project == null` (debug path in `SelectionController`).
- **G**: debug-**complete** **`foraging_systems`** for the **current player** (**`CompleteProgress`** via **`SelectionController`**). **One-shot** per player; a later press rejects with **`progress_already_completed`** until a fuller UI/debug cycling mechanism exists.
- **H**: debug-apply the **first** **`ProgressDetector`** candidate for the **current player** (**`ProgressCandidateFilter.for_current_player`** then **`try_apply`**) — e.g. **`controlled_fire`** after an accepted **`found_city`** for that player. Warns when **no** filtered candidate or when **`try_apply`** rejects.
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
- **Water** hexes remain **blocked** for **one-step** moves via **`TerrainRuleDefinitions`**; **no** movement points, **no** multi-hex pathfinding, **no** application of **`movement_cost`** to range yet.
- **`produce_unit:warrior`** and **`produce_unit:settler`** carry **`cost` 2** in **`CityProjectDefinitions`** (**Phase 5.1.2** onward); **`ProductionDelivery`** spawns **`warrior`** / **`settler`** units from **`project_id`** (**AI** prefers warrior first via **`LegalActions`** ordering unless steering changes policy).
- **City** and **unit** markers are **placeholder** geometry and palettes (not final art).
- **Stacking** on the city hex is **allowed** when a produced unit spawns.
- **No** combat resolution, **no** save/load, **no** fog of war, **no** workbook-scale branching **tech catalog** (**Ancient v0 embryo** exposes a **small gated science slice** instead), **no** faction **trait** layer beyond **`UnitDefinitions`** IDs and **`Unit.type_id`**.

Presentation: [RENDERING.md](RENDERING.md), [SELECTION.md](SELECTION.md) (editor wiring for keys and views).

## Manual F5 checklist

1. **F5** — Map loads; units and terrain render; **Turn** HUD shows current turn and player.
2. Press **A** once — **Player 0** should **`found_city`** (unit removed, city marker visible if CitiesView is wired); log shows `found_city`.
3. Press **A** again — **Player 0** should **`set_city_production`** (**`produce_unit:warrior`**); log shows `set_city_production` with that **project id**.
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

## Phase 5.1 Ancient embryo (shipped + what stays out-of-scope)

The **baseline** **`try_apply`** / **`LegalActions`** / **`EndTurn`** / **`ProductionTick`** pipeline **above** stays current. **Phase 5.1** delivered a **curated Ancient embryo** on top—not a roadmap-only placeholder.

**Player-visible embryo (mostly implemented):**

1. Found with a **settler** (**`found_city`**; unchanged path).
2. **Science accumulation** toward **`controlled_fire`** on the prototype map (**`ScienceTick`** on **`EndTurn`**, lightning-tree observation bonus, **`controlled_fire`** completion + **`ScienceCompletedPopup`**) plus **`DiscoveryPopup`** / HUD panels (see [PROGRESSION_MODEL.md](PROGRESSION_MODEL.md)). Manual **`CompleteProgress`** via **`KEY_H`** (**`ProgressDetector`** / **`ProgressCandidateFilter`**) remains a **parallel** tooling path.
3. **`SetCurrentResearch`** and **`SciencePanel`** for choosing **next** curated science (**not** enumerated in **`LegalActions`** / **AI**).
4. **`produce_unit:settler`** trains through **`ProductionTick`** / **`ProductionDelivery`** like warriors (**`CityProjectDefinitions`** row; **`CityYields`** / capital overlay per **[CITIES.md](CITIES.md)**).
5. Delivered settlers **expand** with another **`found_city`** (cycle repeats).

**Still explicitly out-of-scope for this narrative:** generated worlds; alternate **`RuleSet`** snapshots beyond architecture direction in **[CONTENT_MODEL.md](CONTENT_MODEL.md)**; a full workbook-scale science graph; richer **spatial** detectors; **AI** proposing **`CompleteProgress`** without an explicit future phase; **LLM-produced rules** — tracked in **[PHASE_PLAN.md](PHASE_PLAN.md)** and **[CONTENT_MODEL.md](CONTENT_MODEL.md)**.

**Regression guard:** **`test_settler_production_flow.gd`** proves **`produce_unit:settler`** runs through **`EndTurn`** → **`ProductionTick`** → **`ProductionDelivery`** and the delivered **`settler`** may **`MoveUnit`** then **`FoundCity`** again.

## Cross-references

- [ACTIONS.md](ACTIONS.md) — actions, `try_apply`, engine log types, legal enumeration.
- [CITIES.md](CITIES.md) — cities, founding, production projects.
- [AI_LAYER.md](AI_LAYER.md) — `LegalActions`, `RuleBasedAIPlayer`, policy.
- [TURNS.md](TURNS.md) — `TurnState`, turn order.
- [RENDERING.md](RENDERING.md) — views, draw order, debug keys at a high level.
