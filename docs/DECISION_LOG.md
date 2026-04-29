# Empire of Minds — Decision Log

## 2026-04-29 — Phase 2.6: core loop frozen; CORE_LOOP.md + smoke test

Decision:
Phase **2.x** core loop is **frozen** as the baseline immediately before Phase **3** content foundation. **[CORE_LOOP.md](CORE_LOOP.md)** is the human-readable summary of what the prototype does today (playable loop, log order, placeholders, F5 checklist, validation command). **`game/ai/tests/test_core_loop_ai_smoke.gd`** is the headless **end-to-end** guard: AI drives **`GameState.try_apply`** until **`unit_produced`** appears and turn number reaches **2+**, without choosing engine log types.

Rationale:
Entering Phase **3** with only scattered docs and partial tests risks drift between “what we think works” and the **actual** loop. One short checkpoint doc plus one smoke test keeps **documentation and behavior aligned** at low cost.

Caveat:
**2.6** is **not** UI/HUD polish, not final balance, and not a replacement for Phase **4** presentation quality.

## 2026-04-28 — Phase 2.5: city actions in LegalActions + rule-based AI

Decision:
**`FoundCity`** and **`SetCityProduction`** are enumerated in **`LegalActions.for_current_player`** (legality-only; deterministic order after **`MoveUnit`** entries), and **`RuleBasedAIPlayer.decide`** selects them before the existing one-**`move_unit`**-per-segment / **`end_turn`** policy when the scenario calls for it.

Rationale:
The rule-based AI can drive the core **found → set production → move → end** loop using existing action schemas and **`GameState.try_apply`** only, without new types or engine-event “actions.”

Caveat:
Policy stays deterministic and shallow (no scoring, planning, or LLM). **`LegalActions`** lists every validator-legal city action; it does not encode “only one city” or other strategic cuts.

## 2026-04-27 — Initial Engine Direction

Decision:
Use Godot as the initial prototyping engine.

Rationale:
- permissive MIT license
- good fit for 2D/strategy prototyping
- low licensing risk
- fast iteration
- no revenue share/runtime fee

Caveat:
The architecture must not make core rules inseparable from Godot scenes.

## 2026-04-27 — AI Direction

Decision:
Start with deterministic rule-based AI.

Rationale:
- debuggable
- testable
- works offline
- creates legal-action interface needed for future LLM AI

Caveat:
LLM adapters may be explored later, but must choose from generated legal actions.

## 2026-04-27 — Cloud Direction

Decision:
Design for asynchronous play-by-cloud, but do not build official hosting first.

Rationale:
- async turns fit 4X gameplay
- avoids early operational burden
- enables Bring Your Own Server / Private Cloud

Caveat:
Server-authoritative architecture must be preserved for future cloud mode.

## 2026-04-27 — Scripting language for Godot (Phase 1.x)

Decision:
Phase 1.x uses Godot 4.x with GDScript as the default scripting language; C# is deferred to avoid introducing a .NET dependency during early prototyping.

Rationale:
- GDScript ships with Godot; no separate .NET SDK or Mono build required on the machine or in the repo for contributors to open and run the project.

Caveat:
C# may be reconsidered later only with an explicit steering decision to accept the .NET dependency.

## 2026-04-27 — Axial hex coordinates (Phase 1.1)

Decision:
Phase 1.1 uses axial (q, r) hex coordinates in the domain layer; cube conversion is deferred; distance-style helpers are deferred until a later phase needs them.

Rationale:
- Minimal representation, simple neighbor lookup, orientation-neutral at the domain layer, and compatible with later cube math for distance, line, and range.

Caveat:
Later phases may add `to_cube()`, `distance()`, or range helpers when movement or other rules need them; the steering documents should be updated when that happens.

## 2026-04-27 — Domain map model (Phase 1.2)

Decision:
Phase 1.2 introduces **`HexMap`**: a finite set of cells stored as `Dictionary[Vector2i -> int]`, with **public queries taking `HexCoord`**. `Terrain` is a minimal inline enum (`PLAINS`, `WATER`) with no gameplay effects in 1.2. A single canonical 7-hex test map is provided by the static `HexMap.make_tiny_test_map()`.

Rationale:
- `Vector2i` keys are value-based and work correctly with `has()`; `HexCoord` remains the domain identity at the API.
- Two terrain values are enough to exercise `terrain_at` without pre-committing to a full 4X terrain taxonomy.
- One factory method keeps the fixture consistent for later rendering and rules phases.

Caveat:
Later phases will likely introduce a `Cell` or richer `Terrain` model (costs, ownership, etc.); that will require an explicit steering update before implementation.

## 2026-04-27 — HexMap.read_coords (Phase 1.2 follow-up for Phase 1.3)

Decision:
`HexMap` adds **`coords()`** — a read-only list of all occupied cells as `HexCoord` instances, without exposing the internal `Vector2i` dictionary keys. **Iteration order is unspecified** in Phase 1.2.

Rationale:
Presentation (e.g. rendering) must **derive** what to draw from domain state, not hand-duplicate a coordinate list. `coords()` gives a single source of truth for “which cells exist” without mutating the map or returning raw storage types.

Caveat:
If a future system needs a stable order (e.g. deterministic serialisation), the steering documents and API must be updated to specify it.

## 2026-04-27 — Map rendering (Phase 1.3)

Decision:
**Phase 1.3** draws the **tiny test** `HexMap` using a single **`MapView` (`Node2D`)** and **`_draw()`**. A pure static helper **`MapView.compute_draw_items(map, layout)`** turns domain state into polygon colors and corner lists. `compute_draw_items` iterates **`map.coords()`** and **`terrain_at(coord)`**; it does **not** use a hand-duplicated coordinate list. **[HexLayout](../game/presentation/hex_layout.gd)** encodes pointy-top axial-to-world layout with `SIZE` 32. Placeholder terrain colors and scope are documented in [RENDERING.md](RENDERING.md).

Rationale:
One `Node2D` plus `_draw()` is minimal; derived drawing from `coords()` matches the “rendering reflects domain” rule. Pointy-top layout is a common default; the domain remains orientation-neutral in [HEX_COORDINATES.md](docs/HEX_COORDINATES.md).

Caveat:
**Orientation, tile size, palette, camera, input, and TileMap** are **not** locked for production; a future phase or steering pass may revise them.

## 2026-04-27 — Unit domain and Scenario (Phase 1.4)

Decision:
**Phase 1.4** introduces an immutable **`Unit`** and **`Scenario`** in `game/domain/`: a `Unit` is `(id, owner_id, position)` as `RefCounted` data; a **`Scenario`** holds a `HexMap` and a fixed list of units, validated at construction (positions on the map, unique unit ids), with read-only query APIs and **`make_tiny_test_scenario()`** as the canonical three-unit, two-owner fixture on PLAINS only, with `(-1,0)` WATER unoccupied.

Rationale:
**Smallest viable** representation: integers for **unit and owner ids** without a `Player` class; a single **`Scenario`** bundle unblocks **Phase 1.5** and later rules without entangling `Node` or global state.

Caveat:
**Rendering, selection, movement, actions, a `Player` type, owner palette, and stacking / ZoC rules** remain **deferred**; this phase does not define gameplay loops or presentation.

## 2026-04-28 — Unit markers in presentation (Phase 1.4b)

Decision:
**Phase 1.4b** introduces **`UnitsView`**, a separate **`Node2D`** **sibling** of **`MapView`**, both parented by **`Main`** in [main.tscn](../game/main.tscn) with [main.gd](../game/main.gd) as the only wiring: **`Main` owns a single `Scenario` instance and a single `HexLayout`**, passing **`scenario.map`** and **`layout`** to **`MapView`**, and **`scenario`** and **`layout`** to **`UnitsView`**. **`UnitsView` derives** marker positions, count, and placeholder **owner** colors from **`Scenario.units()`** only (via static **`compute_marker_items`**); markers are **simple drawn circles** with a thin outline.

Rationale:
Keeps **terrain** and **units** as two presentation concerns; one **`Scenario` + one `HexLayout`** prevent map/units/geometry from drifting. Derived drawing matches the “rendering reflects state, not owns it” rule from [ARCHITECTURE_PRINCIPLES.md](ARCHITECTURE_PRINCIPLES.md).

Caveat:
**Selection, movement, input, animation, sprites, the warrior asset, text labels, health bars, a final owner palette, and gameplay rules** remain **deferred**; 1.4b is read-only display only.

## 2026-04-28 — Selection and legal destinations (Phase 1.5)

Decision:
**Phase 1.5** adds **`MovementRules.legal_destinations(scenario, unit_id)`** in [game/domain/movement_rules.gd](../game/domain/movement_rules.gd) (neighbor-only, on-map, **not WATER**, **not occupied**). Presentation adds **`SelectionState`** ( **`RefCounted`**, `unit_id` only), **`SelectionController`** (**`_unhandled_input`**, hit-test markers, **no `UnitsView` reference**), and **`SelectionView`** ( **`compute_overlay_items`** + **`_draw`** ring via **`PackedVector2Array`** closed polyline, destination fills). **`Main`** wires one **`Scenario`**, **`HexLayout`**, and **`SelectionState`** to views. **`HexMap` / `Terrain`** stay tag-only; WATER-as-impassable is documented in [MOVEMENT_RULES.md](MOVEMENT_RULES.md).

Rationale:
Keeps **rules** in a small static domain API; keeps **selection** as **non-authoritative** client state; overlays **derive** from domain + selection so highlights are never truth.

Caveat:
**Actual movement**, **`MoveUnit`**, **validators**, **action log**, **turn ownership**, **AI**, **save/load**, and **final UX** for selection remain **deferred**.

## 2026-04-28 — MoveUnit, GameState, ActionLog (Phase 1.6)

Decision:
**Phase 1.6** adds **`MoveUnit`** ([game/domain/actions/move_unit.gd](../game/domain/actions/move_unit.gd)) as a versioned **`Dictionary`** schema, **`GameState.try_apply`** ([game_state.gd](../game/domain/game_state.gd)) as the sole local mutation entry point, and **`ActionLog`** ([action_log.gd](../game/domain/action_log.gd)) with **deep-duplicated** stored and returned entries. **`MoveUnit.apply`** returns a **new `Scenario`** with a **replaced `Unit`**, preserving the **`HexMap`** reference. **`MovementRules.legal_destinations`** remains the legality oracle inside **`MoveUnit.validate`**. **[SelectionController](../game/presentation/selection_controller.gd)** submits moves only via **`try_apply`**; **destination** hit-test precedes **unit-marker** hit-test; on accept it re-points **`units_view`** / **`selection_view`** and **clears** selection.

Rationale:
Matches [ARCHITECTURE_PRINCIPLES.md](ARCHITECTURE_PRINCIPLES.md) action pipeline; keeps **`Unit`/`Scenario`** immutable per instance; **`try_apply`** is the future cloud-shaped boundary.

Caveat:
**Turn order**, **AI**, **persistence**, **structured rejection log**, **replay UI**, and **movement animation** remain **deferred**.

## 2026-04-28 — TurnState, EndTurn, current-player gate (Phase 1.7)

Decision:
**Phase 1.7** adds immutable **`TurnState`** ([turn_state.gd](../game/domain/turn_state.gd)) with **`advance()`**, **`EndTurn`** ([end_turn.gd](../game/domain/actions/end_turn.gd)) as a versioned **Dictionary**, and **`GameState.turn_state`** updated only through **`try_apply`**. A **common gate** in **`GameState.try_apply`** enforces **`actor_id`** presence/type and **`actor_id == current_player_id()`** for both **`move_unit`** and **`end_turn`**. **`EndTurn.validate`** is **structural only**; **`not_current_player`** is **not** a **`EndTurn.validate`** reason. Accepted **`end_turn`** log entries include **`turn_number_before`** and **`next_player_id`**. Presentation adds **`TurnLabel`** and **`EndTurnController`** ( **Space** ); **`SelectionController`** refreshes the label after accepted moves. Selection may still target any unit; illegal-owner moves are rejected at **`try_apply`**.

Rationale:
Keeps turn truth in the domain next to **`Scenario`**; one gate avoids duplicating “whose turn” checks in every action validator; **`EndTurn`** stays easy to serialize like **`MoveUnit`**.

Caveat:
**Phased turns** (movement vs production), **AI end-turn**, **restricting selection to current player**, and **online turn order** remain **deferred**.

## 2026-04-28 — Legal actions + rule-based AI (Phase 1.8)

Decision:
**Phase 1.8** adds **`LegalActions.for_current_player`** ([legal_actions.gd](../game/domain/legal_actions.gd)) — deterministic **`MoveUnit`** enumeration from **`MovementRules`** plus trailing **`EndTurn`** — **`RuleBasedAIPlayer.decide`** ([rule_based_ai_player.gd](../game/ai/rule_based_ai_player.gd)) under **`game/ai/`**, and **`AITurnController`** ([ai_turn_controller.gd](../game/presentation/ai_turn_controller.gd)) on **`KEY_A`**. AI submission is only via **`GameState.try_apply`**; **`decide`** returns **`{}`** defensively on empty or unrecognized **`legal_actions`**. One key press applies at most one action; no **`_process`** automation. Topic doc: [AI_LAYER.md](AI_LAYER.md).

Rationale:
Matches [ARCHITECTURE_PRINCIPLES.md](ARCHITECTURE_PRINCIPLES.md): legal generation stays domain-shaped; AI choice stays in an **`ai/`** module; Godot input stays in presentation. **`try_apply`** remains the single mutation gate for cloud-shaped futures.

Caveat:
**Multi-action plans**, **LLM adapters**, **planner AI**, **auto-run to end of turn**, and **AI identity per seat** remain **deferred**.

## 2026-04-28 — ActionLog-derived one-move-per-turn AI policy (Phase 1.8b)

Decision:
**Phase 1.8b** adds **`RuleBasedAIPolicy.has_actor_moved_this_turn(action_log, actor_id)`** ([rule_based_ai_policy.gd](../game/ai/rule_based_ai_policy.gd)): **newest-first** scan of **`ActionLog`**; first **`end_turn`** ⇒ “not moved this segment”; first matching **`move_unit`** ⇒ “moved”. **`RuleBasedAIPlayer.decide`** consults this helper and returns **`EndTurn`** when the current player already moved, else keeps the Phase 1.8 move preference. **`LegalActions`**, **`GameState`**, schemas, and **`AITurnController`** are unchanged.

Rationale:
Avoids infinite **`MoveUnit`** chains on the tiny map without movement points, without **`LegalActions` lying about legality**, without schema bumps, and without hidden mutable AI state — **pure derive-from-log** stays replay-shaped.

Caveat:
**Flexible budgets** (N moves per turn), **phase sub-steps**, and **AI that differs from human caps** remain **deferred** until explicitly steered.

## 2026-04-28 — ActionLog debug surfacing (Phase 1.9)

Decision:
**Phase 1.9** adds **`LogView`** ([log_view.gd](../game/presentation/log_view.gd)) — **`extends Label`**, **`MAX_ENTRIES` = 10**, **`compute_text`** / **`format_entry`** static helpers, **tail-only** display (**newest at bottom**). It reads **`game_state.log`** only via **`size()`** and **`get_entry(i)`**; **no** **`ActionLog`** API changes and **no** mutation of **`GameState`** or entries. **`main.gd`** wires **`LogView`** and passes it to **`SelectionController`**, **`EndTurnController`**, and **`AITurnController`**, each calling **`if log_view != null: log_view.refresh()`** after **accepted** **`MoveUnit`**, **`EndTurn`**, or AI steps — **explicit refresh**, **no** polling, **no** replay/undo.

Rationale:
Makes the **append-only** log visible in the prototype while keeping the action pipeline and log semantics identical; optional **`log_view`** on controllers avoids tight coupling for headless or alternate scenes.

Caveat:
**Structured export**, **filter/search**, **rich replay UI**, and **rejected-action logging** remain **deferred**.

## 2026-04-28 — Long-term phase roadmap clarified (Phases 1–7)

Decision:
The forward roadmap in [PHASE_PLAN.md](PHASE_PLAN.md) is restructured into **Phases 2–7** (**core 4X loop**, **game content foundation** with **3.0–3.5**, **visual identity / presentation** with **4.0–4.5**, **strategic dynamics**, **Empire of Minds worldbuilding and identity**, **balance / content iteration**). Prior **cloud** milestones (**Async Cloud**, **Private Cloud / Self-Host**, **Server Manager**) are preserved verbatim in a **Deferred — Cloud / Self-Host roadmap** appendix and **[CLOUD_PLAY.md](CLOUD_PLAY.md)** remains canonical cloud steering — decoupled from gameplay numbering so **Phases 2–7** can be refined without renumbering infrastructure.

Rationale:
Separates **core systems**, **content model**, **visual presentation**, **world identity**, and **balance iteration** to limit **scope bleed** and keep each phase narrow enough to validate per [IMPLEMENTATION_GUIDE.md](IMPLEMENTATION_GUIDE.md).

Caveat:
**Phases 2–7** are **roadmap-level**; **Must not** and **Validation** will be refined as **Phase 2** progresses. **Placeholder** rendering may continue in **Phase 2.x / 3.x**; **full visual identity** belongs to **Phase 4**.

## 2026-04-28 — City domain + CitiesView (Phase 2.1)

Decision:
**Phase 2.1** adds **`City`** ([city.gd](../game/domain/city.gd)), extends **`Scenario`** ([scenario.gd](../game/domain/scenario.gd)) with **`cities()`**, **`city_by_id`**, **`cities_at`**, **`cities_owned_by`**, and **replay-safe** **`peek_next_unit_id()` / `peek_next_city_id()`** with **`Scenario.new(map, units)`** backward compatibility and **auto** counters from listed entities when not explicit. **`CitiesView`** ([cities_view.gd](../game/presentation/cities_view.gd)) provides **`compute_marker_items`** placeholder diamonds; [main.tscn](../game/main.tscn) draw order is **MapView → CitiesView → SelectionView → UnitsView**. **No** new actions, **no** **`GameState.try_apply`** changes; **`make_tiny_test_scenario()`** stays city-free.

Rationale:
Establishes cities in the **immutable domain bundle** before **FoundCity**; counters default safely for **two-arg** **`Scenario.new`** while allowing explicit pass-forward for future consumption/removal. Presentation stays **derived-only**.

Caveat:
**`main.gd`** does not re-point **`CitiesView`** after moves; acceptable while the canonical loop has **zero** cities.

## 2026-04-28 — Scenario pass-forward hardening (Phase 2.2a)

Decision:
**`MoveUnit.apply`** now returns **`Scenario.new(map, new_units, cities, peek_next_unit_id, peek_next_city_id)`** read from the input **`Scenario`**, so **cities** and **replay-safe counters** are not dropped on move.

Rationale:
Prevents silent loss of city state and **id** monotonicity before **`FoundCity`** and production; **`apply`** still replaces only the moved **`Unit`** and allocates **no** new ids inside **`apply`**.

Caveat:
Every **future** domain path that constructs a **`Scenario`** from a prior snapshot must **explicitly** pass **`cities`** and **`peek_*`** values (or deliberately document a reset); see [CITIES.md](CITIES.md).

## 2026-04-28 — FoundCity action (Phase 2.2b)

Decision:
**Phase 2.2b** introduces **`FoundCity`** ([found_city.gd](../game/domain/actions/found_city.gd)) as a **versioned** **`Dictionary`** action dispatched only through **`GameState.try_apply`**: structural **`validate`**, **`apply`** returns a **new** **`Scenario`** with the **founding unit removed**, a **new** **`City`** at that **hex** using **`city_id = peek_next_city_id()`**, **`peek_next_city_id()`** advanced by **1**, and **`map` / other units / existing cities / `peek_next_unit_id()`** preserved. **`created_city_id`** is read **before** **`apply`** for **deterministic** **`ActionLog`** entries. **`SelectionController`** uses **`KEY_F`** when a **unit** is **selected**; **`LogView`** formats **`found_city`** lines.

Rationale:
Establishes the **first city-creation** path through the same **validate → apply → log → refresh** pipeline as **`move_unit`** / **`end_turn`**, with **monotonic** **city ids** and **no** hidden **`Scenario`** mutation.

Caveat:
**Any-unit founding** is **temporary**; **`LegalActions`** and **AI** **do not** emit **`found_city`** yet (**Phase 2.6**). **Production**, **economy**, and **settler** eligibility belong in **later** phases (**Phase 3.1** unit definitions).

## 2026-04-28 — SetCityProduction + `City.current_project` (Phase 2.3)

Decision:
**Phase 2.3** adds **`current_project`** on **`City`** (**`null`** or **`Dictionary`**, stored via **`duplicate(true)`** in **`City._init`** when a **`Dictionary`** is supplied) and **`SetCityProduction`** ([set_city_production.gd](../game/domain/actions/set_city_production.gd)) routed through **`GameState.try_apply`**. **`apply`** replaces only the target **`City`** in a **new** **`Scenario`**; **`map`**, **units**, **non-target** cities, and **`peek_next_*`** are **preserved**. **`project_type`** **`"produce_unit"`** installs **`progress: 0`**, **`cost: 2`**; **`"none"`** clears. **`LogView`** formats **`set_city_production`**. **`SelectionController`** **`KEY_P`** submits **`produce_unit`** for the **lowest-id** eligible **current-player** **city** (debug only).

Rationale:
Establishes **city build state** in the **immutable** domain bundle with the same **validate → apply → log** pipeline; defers **tick** / **`ProduceUnit`** so Phase 2.3 remains **state-only**.

Caveat:
**`LegalActions` / AI** do **not** enumerate **`set_city_production`**. **Production progress on** **`end_turn`** is **Phase 2.4a**; **completion** / **`ProduceUnit`** is **Phase 2.4b**.

## 2026-04-28 — Production progress tick on EndTurn (Phase 2.4a)

Decision:
**Phase 2.4a** adds **`ProductionTick.apply_for_player`** ([production_tick.gd](../game/domain/production_tick.gd)), invoked **only** from **`GameState.try_apply`** on **accepted** **`end_turn`**, **after** **`EndTurn.validate`** and **before** **`TurnState.advance`**. **Ending-player** cities with **`current_project != null`** gain **`progress` += 1**; events logged as **`production_progress`** ( **`source`: `"engine"`** ) in **ascending `city.id` order**, **then** the **`end_turn`** entry. **`progress`** may **exceed** **`cost`**; **no** unit spawn, **no** project clear, **no** counter allocation. **`LogView`** formats **`production`** lines.

Rationale:
Keeps **player** **`action_type`** surface unchanged while making **production** **observable** and **replay-ordered**; defers **completion** / **`ProduceUnit`** to **2.4b**.

Caveat:
**`production_progress`** must **not** become a **`try_apply`** action or **`LegalActions`** entry.

## 2026-04-28 — Production completion on EndTurn (Phase 2.4b)

Decision:
**Phase 2.4b** extends **`ProductionTick.apply_for_player`** ([production_tick.gd](../game/domain/production_tick.gd)) so that when **`progress_after` >= `cost`** and **`project_type`** is **`produce_unit`**, the engine emits **`unit_produced`** immediately after that city’s **`production_progress`**, appends **one** **`Unit`** at **`city.position`**, sets **`current_project`** to **`null`**, increments **`peek_next_unit_id()`** by the number of completions, and leaves **`peek_next_city_id()`** unchanged. **No** overflow carry. **`unit_produced`** is **not** a player action; **`LogView`** formats **`unit_produced`** lines.

Rationale:
Completes the minimal **produce_unit** loop while keeping **`try_apply`** and **`LegalActions`** surfaces unchanged.

Caveat:
**No** production queues or **`ProduceUnit`** **player** action; stacking remains **unlimited** on a hex for this phase.

## 2026-04-28 — Pending production delivery (Phase 2.4c)

Decision:
**Phase 2.4c** splits **completion** from **delivery**: **`ProductionTick`** only increments **`progress`** and sets **`ready: true`** when **`produce_unit`** reaches **`cost`**; **`ProductionDelivery.deliver_pending_for_player`** ([production_delivery.gd](../game/domain/production_delivery.gd)) runs in **`GameState.try_apply`** **after** **`turn_state` advances** and **after** the **`end_turn`** log entry, spawning **Units** and appending **`unit_produced`** for the **incoming** **`current_player_id`**. **`GameState._init`** runs the same delivery for the **opening** current player when the **`Scenario`** already contains **`ready`** projects. There is **no** separate **StartTurn** action.

Rationale:
Prevents the **opponent** from interacting with **newly completed** production **before** the **owner**’s **next** turn.

Caveat:
**Replay** / tools that assumed **`unit_produced`** immediately after **`production_progress`** must update to **post-`end_turn`** ordering.
