# Empire of Minds — Phase Plan

## Phase 0 — Steering Foundation

Goal:
Create the documentation and agent constraints before implementation.

Outputs:

- docs/PROJECT_BRIEF.md
- docs/ARCHITECTURE_PRINCIPLES.md
- docs/IMPLEMENTATION_GUIDE.md
- docs/PHASE_PLAN.md
- docs/AI_DESIGN.md
- docs/CLOUD_PLAY.md
- docs/LICENSE_STRATEGY.md
- docs/VALIDATION_CHECKLIST.md
- docs/DECISION_LOG.md
- Cursor rules/skill

Exit criteria:

- documents exist
- non-negotiable architecture principles are explicit
- Phase 1 scope is narrow and testable
- implementation agent has clear constraints

## Phase 1 — Local Playable Prototype

Goal:
Tiny playable local vertical slice.

Features:

- Godot project
- hex grid
- static or generated test map
- camera movement
- unit selection
- legal unit movement
- end turn
- simple rule-based AI turn
- deterministic action log

Exit criteria:

- player can select a unit and move it legally
- illegal movement is rejected
- end turn advances to AI
- AI performs at least one legal action and ends turn
- action log records turn sequence
- game can be replayed or inspected at basic level
- core rules are not hidden inside rendering nodes

## Phase 1.0 — Godot Skeleton

Goal:
Create a blank runnable Godot project.

Must not:

- implement map
- implement units
- implement AI
- introduce gameplay state

Validation:

- project opens/runs
- no external dependencies

## Phase 1.1 — Domain Hex Coordinates

Goal:
Implement the smallest domain representation of hex coordinates and neighbor queries.

Must not:

- render map yet
- implement pathfinding
- implement units

Validation:

- coordinate neighbor tests pass
- coordinate system is documented

## Phase 1.2 — Domain Map Model

Goal:
Represent a tiny fixed map in domain state.

Must not:

- procedural generation
- resources
- fog of war

Validation:

- map has known size
- terrain can be queried by coordinate

## Phase 1.3 — Render Map From Domain State

Goal:
Render the domain map in Godot.

Must not:

- let rendered tiles own map truth
- implement movement

Validation:

- rendered tiles match domain map
- coordinate labels optional but useful

## Phase 1.4 — Unit Domain Model

Goal:
Add one or more units to domain state.

Must not:

- animate movement yet
- implement combat
- implement production

Validation:

- unit has owner, id, and hex coordinate
- renderer displays unit from domain state

## Phase 1.4b — Render Unit Markers

Goal:
Render simple markers for units that exist in domain state.

Must not:

- implement selection, movement, or input
- implement animation, sprites, or an art/asset pipeline
- make rendered markers the source of truth for unit positions (markers must derive from `Scenario.units()`)

Validation:

- the renderer shows markers **derived from** `Scenario.units()`; the map (terrain) remains the same as Phase 1.3 visually aside from the added markers
- unit identity and position remain in domain; markers are a derived view only

## Phase 1.5 — Selection and Legal Movement Query

Goal:
Allow selecting a unit and querying legal movement.

Must not:

- move unit yet
- implement pathfinding beyond adjacent/simple range
- add `MoveUnit` actions validation/application or action log
- mutate `Unit` or `Scenario` from selection or overlays

Validation:

- selected unit is clear from **presentation** `SelectionState` (not stored on domain objects)
- legal destinations come from **`MovementRules`** (domain query only)
- overlays are **derived** from scenario + selection; **not** a source of truth
- **no** unit movement and **no** actions in this phase

## Phase 1.6 — MoveUnit Action

Goal:
Implement structured MoveUnit action, validation, and application.

Must not:

- let UI directly mutate unit coordinates
- implement AI movement yet
- add EndTurn, current-player enforcement, save/load, cloud, or animation

Validation:

- legal move succeeds via **`GameState.try_apply`** (new **`Scenario`**, immutable **`Unit`** replacement)
- illegal move is rejected with a stable **`reason`**; **`scenario`** and **`ActionLog`** unchanged
- **`ActionLog`** records **accepted** **`MoveUnit`** entries only (deep-copied); rejections are not logged in 1.6
- presentation refreshes **`UnitsView`** / **`SelectionView`** from **`game_state.scenario`** after accept; selection **cleared**

## Phase 1.7 — EndTurn Action / Turn Controller

Goal:
Implement turn advancement.

Must not:

- implement diplomacy
- implement production
- implement cloud

Validation:

- **`TurnState`** advances on accepted **`end_turn`**; **`turn_number`** increments only when play returns to the first **`players`** index.
- **`GameState.try_apply`** rejects **`move_unit`** and **`end_turn`** with **`not_current_player`** when **`actor_id` ≠** **`turn_state.current_player_id()`**, and **`malformed_action`** when **`actor_id`** is missing or not an **int** (see [TURNS.md](TURNS.md), [ACTIONS.md](ACTIONS.md)).
- Headless tests cover **`TurnState`**, **`EndTurn`**, **`GameState`** gating, **`TurnLabel.compute_text`**, and prior phases unchanged.

## Phase 1.8 — RuleBasedAIPlayer

Goal:
Implement simple AI that chooses from legal actions.

Must not:

- introduce LLM
- bypass validation
- add strategic planner yet

Validation:

- **`LegalActions`**, **`RuleBasedAIPlayer`**, **`AITurnController`**, and headless tests as documented in [AI_LAYER.md](AI_LAYER.md).
- Run **`.\scripts\run-godot-tests.ps1`**: every test listed there must **`PASS`**; runner exits **0** (do not rely on **`godot`** on **`PATH`** alone).
- **Editor (F5):** AI **`KEY_A`** walkthrough per [AI_LAYER.md](AI_LAYER.md). Mouse and **Space** unchanged.

## Phase 1.8b — Deterministic AI turn policy (one move per turn)

Goal:
Make the rule-based AI complete a turn deterministically without indefinite **`MoveUnit`** chains on the canonical map.

Must not:

- change **`LegalActions`**, **`GameState.try_apply`**, action schemas, **`AITurnController`**, or add **`_process`** / automation
- introduce movement points, global mutable AI state, or LLM

Validation:

- **`RuleBasedAIPolicy.has_actor_moved_this_turn`** derives from **`ActionLog`** only (**newest-first** scan; **`end_turn`** boundary).
- **`RuleBasedAIPlayer.decide`** consults the policy; one **`KEY_A`** press still applies **one** action.
- **`test_rule_based_ai_policy`**, extended **`test_rule_based_ai_player`**, and **`test_ai_turn_flow`** (no manual **`EndTurn`** fallback; **`MAX_AI_STEPS`** guard; exact **`move_unit`** / **`end_turn`** counts) pass.
- Run **`.\scripts\run-godot-tests.ps1`**: every test in the runner **`PASS`**; exit **0**.

## Phase 1.9 — Action log debug surfacing (read-only)

Goal:
Expose the **accepted** **`ActionLog`** in the local prototype for debugging (not replay execution).

Must not:

- replay, undo, or redo actions from the UI
- mutate **`ActionLog`** or action schemas from presentation
- add **`ActionLog`** APIs beyond existing **`size()`** / **`get_entry`**
- poll or automate refresh (**no** **`_process`** on **`LogView`**)

Validation:

- **`LogView`** ([log_view.gd](../game/presentation/log_view.gd)): **`Label`**, last **`N`** entries (**`MAX_ENTRIES` = 10**), newest at bottom, **`compute_text`** / **`format_entry`** covered by [test_log_view.gd](../game/presentation/tests/test_log_view.gd).
- **`SelectionController`**, **`EndTurnController`**, **`AITurnController`**: **`log_view.refresh()`** after each **accepted** action (**`log_view`** optional / null-safe).
- Run **`.\scripts\run-godot-tests.ps1`**: every test in the runner **`PASS`**; exit **0**.
- **Editor (F5):** **`LogView`** empty at start; after moves / **Space** / **`A`**, lines append; with more than **`MAX_ENTRIES`** accepts, only the tail is visible.

## Roadmap framing (Phases 2–7)

Phases **2–7** below are **roadmap-level**: goals and boundaries are fixed here, but **Must not** and **Validation** will be refined as **Phase 2** implementation is planned.

**Visual placeholders** (e.g. distinct marker shapes, city markers) may land in **Phase 2.x** or **Phase 3.x** for playability; **full visual identity** (art direction, cohesive shipped-quality presentation) is owned by **Phase 4**.

**Phase 3** establishes **content and rules definitions**, not **final balance** — tuning belongs in **Phase 7**.

This roadmap **separates** core **systems** (Phase 2), **content model** (Phase 3), **presentation / visual identity** (Phase 4), **strategic dynamics** (Phase 5), **worldbuilding and non-Civ identity** (Phase 6), and **balance iteration** (Phase 7) to reduce **scope bleed**.

## Phase 2 — Core 4X loop

Goal:
Minimal playable **4X** loop: **cities**, **production**, **founding**, **producing units**, **basic economy**.

Features (roadmap):

- city placement / ownership in domain state
- founding and production rules (versioned actions where applicable)
- basic resources feeding production
- economy small enough to validate headlessly where possible

Must not (roadmap):

- treat this phase alone as **complete** combat, fog of war, diplomacy, or **save/load** — those may follow in later tranches or be steered separately
- commit to **final** art or **Phase 4** visual identity

Note:
**Phase 2.x** may include **rendering cities as placeholder markers** (derived from domain; same layering as **`UnitsView`**-style markers). **Full city visuals** belong to **Phase 4.3**.

### Phase 2.1 — City domain model and placeholder rendering (implemented)

Goal:
Immutable **`City`** type, **`Scenario.cities`**, replay-safe **`peek_next_unit_id` / `peek_next_city_id`**, and **`CitiesView`** placeholder markers. No actions, no **`try_apply`** changes.

Must not:

- add **`FoundCity`**, production, or economy rules
- mutate domain from presentation; **`CitiesView`** is derived-only

Validation:

- Headless: **`test_city`**, **`test_scenario_cities`**, **`test_cities_view_draw`** (see [CITIES.md](CITIES.md), [RENDERING.md](RENDERING.md)).
- Run **`.\scripts\run-godot-tests.ps1`**: every test **`PASS`**; exit **0**.
- **Editor (F5):** canonical scenario shows **no** city markers; **`CitiesView`** is wired. **Map / selection / units / AI** unchanged.

### Phase 2.2b — FoundCity action (implemented)

Goal:
Versioned **`FoundCity`** **`Dictionary`** action routed through **`GameState.try_apply`**; **consumes** the founder **unit**; **appends** a **`City`** with **`city_id = peek_next_city_id()`** and increments **`peek_next_city_id()`** by **1** in the returned **`Scenario`**; **F-key** path in **`SelectionController`** + **`LogView`** formatting; **headless** tests.

Must not:

- add **`found_city`** to **`LegalActions`** or change **AI** / **RuleBasedAIPlayer** (Phase **2.6**)
- add **production**, **SetCityProduction**, **economy**, or **`GameState`** behavior changes beyond **`found_city`** dispatch
- change **`game/main.tscn`**, **`project.godot`**, or **domain** types **denied** by the phase slice (see task steering)

Validation:

- **`test_found_city`**, **`test_found_city_flow`**, **`test_log_view`** (found_city line), full **`run-godot-tests.ps1`** green.
- **Editor:** select a **unit**, press **F** → **unit** removed, **city** at that **hex**, **selection** cleared, **log** line.

### Phase 2.3 — City production project + SetCityProduction (implemented)

Goal:
**`City.current_project`** (**`null`** or **deep-copied** primitive **`Dictionary`**) and versioned **`SetCityProduction`** via **`GameState.try_apply`**; **no** progress tick, **no** **`ProduceUnit`**, **no** economy; **`KEY_P`** **debug** hook in **`SelectionController`**.

Must not:

- add **`set_city_production`** to **`LegalActions`** or change **AI**
- advance **`progress`**, spawn **units**, or add **yields**
- change **`main.tscn`**, **`project.godot`**, or denylisted domain files

Validation:

- **`test_set_city_production`**, **`test_set_city_production_flow`**, **`test_log_view`** (production line), full **`run-godot-tests.ps1`** green.

### Phase 2.4a — Production progress on EndTurn (implemented)

Goal:
**`ProductionTick`** increments **`current_project.progress`** for **ending-player** cities on each **accepted** **`end_turn`**, deterministic **ascending `city.id`** order, **`production_progress`** log **`0..N`** then **`end_turn`**; **no** clamp, **no** completion, **no** **`ProduceUnit`**.

Must not:

- spawn **units**, allocate **`peek_next_unit_id`**, clear **projects**, or add **`production_progress`** to **`try_apply`** / **`LegalActions`** / **AI**
- change **`main.tscn`**, **`project.godot`**, or denylisted domain files

Validation:

- **`test_production_tick`**, **`test_end_turn_production_flow`**, **`test_log_view`**, **`test_turn_flow`**, full **`run-godot-tests.ps1`** green.

### Phase 2.4b — Production completion marks ready (implemented; delivery timing superseded by 2.4c)

Goal:
**`ProductionTick`** sets **`ready: true`** on **`produce_unit`** when **`progress_after` >= `cost`** during the **ending** player’s tick. **Spawning** and **`unit_produced`** were moved to **`ProductionDelivery`** on **turn transition** in **Phase 2.4c** (this block documents the original **2.4b** intent; **immediate** spawn after each **`production_progress`** is **obsolete**).

### Phase 2.4c — Pending production delivery on turn start (implemented)

Goal:
**`unit_produced`** and **Units** appear **after** **`end_turn`** when **`ProductionDelivery`** runs for the **new** **`current_player_id`**, so the opponent does **not** get a full turn with access to units the owner has not “received” yet. **`GameState._init`** may deliver **`ready`** work for the opening current player. Log order: **`production_progress*` → `end_turn` → `unit_produced*`**.

Must not:

- add **`unit_produced`** as **`try_apply`** type or to **`LegalActions`** / **AI**
- **`ProduceUnit`** player action

Validation:

- **`test_production_tick`**, **`test_production_delivery`**, **`test_end_turn_production_flow`**, **`test_log_view`**, full **`run-godot-tests.ps1`** green.

### Phase 2.5 — LegalActions + RuleBasedAIPlayer city loop (implemented)

Goal:
Enumerate **`found_city`** and **`set_city_production`** in **`LegalActions.for_current_player`** (validators only, deterministic order) so **`RuleBasedAIPlayer`** can run the basic city loop: found first city, set **`produce_unit`**, then existing one-**`move_unit`**-per-segment behavior and **`end_turn`**. **No** engine events in the legal list.

Must not:

- add **new** action **schemas** or **`try_apply`** branches; change **`ProductionTick`**, **`ProductionDelivery`**, **FoundCity** / **SetCityProduction** validators except to fix a surfaced bug (reported explicitly)
- add **`production_progress`**, **`unit_produced`**, or raw production-progress fields to **`LegalActions`**
- mutate domain state outside **`GameState.try_apply`** from AI; change **`main.*`**, **`project.godot`**, presentation controllers, or **denylisted** docs (**`IMPLEMENTATION_GUIDE`**, **`ARCHITECTURE_PRINCIPLES`**, **TURNS**, **UNITS**, **RENDERING**, etc. per task steering)

Validation:

- **`test_legal_actions`**, **`test_rule_based_ai_player`**, **`test_ai_turn_flow`** updated; full **`run-godot-tests.ps1`** green.
- **Editor:** **`KEY_A`** on canonical start → AI **`found_city`**, then **`set_city_production`**, then move/end policy; log shows engine lines only from **`end_turn`**, never as AI-chosen actions.

### Phase 2.6 — Core loop validation / readability checkpoint (implemented)

Goal:
Freeze and validate the Phase **2.x** core loop as a known-good baseline **before** Phase **3** content foundation. Summarize the current playable loop in human-readable form and pin one headless smoke test that proves rule-based AI can drive the loop through **`unit_produced`** delivery within bounded steps.

Must not:

- add gameplay mechanics, new action **schemas**, or changes to **`GameState.try_apply`**, **`ProductionTick`**, **`ProductionDelivery`**, **`LegalActions`**, AI policy, canonical fixtures, presentation, scenes, or controllers
- substitute this checkpoint for Phase **4** UI/HUD or visual identity work

Validation:

- **[CORE_LOOP.md](CORE_LOOP.md)** exists and matches the shipped loop (controls, log order, placeholders, manual checklist, headless command).
- **`test_core_loop_ai_smoke.gd`** passes; full **`run-godot-tests.ps1`** green (exit **0**).

**Final pre-Phase-3 checkpoint:** after **2.6**, Phase **3** owns definitions and content-shaped rules on top of this frozen loop.

## Phase 3 — Game content foundation

Goal:
**Definitions** and **rules** for units, terrain, city projects, early tech/progress, and a first **faction / world** pass — **data- and domain-shaped**, not shipped balance.

Must not (roadmap):

- lock **final** numbers (costs, ranges, yields) — reserve tuning for **Phase 7**
- let presentation work **replace** **Phase 4** ownership of final visual identity

Note:
**Phase 3.x** may include **rendering unit types distinctly** (e.g. placeholder marker variation by unit type). **Final unit visuals** are **Phase 4.2**.

### Phase 3.0 — Content model checkpoint (implemented; docs-only)

Goal:
Lock the **content-model envelope** (IDs, registries, state-vs-definition boundary, access patterns) in **[CONTENT_MODEL.md](CONTENT_MODEL.md)** before Phase **3.1+** introduces code. Phase **2.x** core loop behavior remains unchanged.

Must not:

- add code, tests, `game/domain/content/**`, JSON, `.tres`, or registries
- change actions, `GameState.try_apply`, production, AI, fixtures, scenes, or `scripts/run-godot-tests.ps1`

Validation:

- **[CONTENT_MODEL.md](CONTENT_MODEL.md)** exists and matches this phase’s scope.
- Full **`run-godot-tests.ps1`** green (exit **0**); regression-only—no behavior change expected.

### Phase 3.1 — Unit definitions (implemented)

Goal:
**Unit types** (stats, roles, production prerequisites) as **data** + validation, separate from balance polish.

**Must reference [CONTENT_MODEL.md](CONTENT_MODEL.md).**

Shipped in code:

- **`UnitDefinitions`** registry **`settler`** / **`warrior`** (`game/domain/content/unit_definitions.gd`); row lookup via **`get_definition(id)`** ( **`get`** is not a valid method name on **`RefCounted`** in GDScript 4).
- **`Unit.type_id`** on state (**default** **`"warrior"`** for three-arg construction).
- **`FoundCity.validate`** rejects types that cannot found (**`unit_type_cannot_found`**).
- **`ProductionDelivery`** resolves spawned **`Unit.type_id`** via **`CityProjectDefinitions.produces_unit_type(project_id)`** when **`current_project`** carries a supported **`project_id`**; **`"warrior"`** remains the fallback for legacy / unknown ids; **`unit_produced`** shape unchanged.

Must not (this subphase):

- bump **`FoundCity`** / player action **schemas**
- change **`GameState.try_apply`**, **`ProductionTick`**, **`MovementRules`**, **`RuleBasedAIPlayer.decide`**, or **`legal_actions.gd`** except to fix a proven bug
- add combat, movement-by-type, or presentation differentiation

Validation:

- **`run-godot-tests.ps1`** exit **0** (includes **`test_unit_definitions.gd`**).
- Manual **F5** / **A** loop: **P0** **settler** still **founds** first on canonical scenario; **producer** path unchanged.

### Phase 3.2 — Terrain rules and movement costs (implemented)

Goal:
Terrain **passability** (and **cost** as content metadata) lives in a registry; **`MovementRules`** stays the **legality oracle** for **`MoveUnit`** / **`LegalActions`**.

**Must reference [CONTENT_MODEL.md](CONTENT_MODEL.md).**

Shipped in code:

- **`TerrainRuleDefinitions`** **`plains`** / **`water`** in [terrain_rule_definitions.gd](../game/domain/content/terrain_rule_definitions.gd); **`get_definition`**, **`is_passable_hex_map_value`**, enum → id mapping; unknown enum → empty id → **impassable**.
- **`MovementRules.legal_destinations`** uses **`TerrainRuleDefinitions`** instead of inlining **`HexMap.Terrain.WATER`**.
- **`HexMap`** storage and **`FoundCity`** **`tile_is_water`** check **unchanged** (founding consolidation deferred).

Must not (this subphase):

- new terrain types, multi-hex moves, movement points, pathfinding, unit-type passability, presentation or **`MapView`** changes, production / **`try_apply`** / AI **`decide`** changes

Validation:

- **`run-godot-tests.ps1`** exit **0** (**36** scripts including **`test_terrain_rule_definitions.gd`**).

### Phase 3.3 — City project definitions (implemented)

Goal:
**City projects** as content-backed definitions; **`SetCityProduction`** references stable **`project_id`** values while **`current_project`** remains engine-shaped.

**Must reference [CONTENT_MODEL.md](CONTENT_MODEL.md).**

Shipped in code:

- **`CityProjectDefinitions`** in [city_project_definitions.gd](../game/domain/content/city_project_definitions.gd): first row **`produce_unit:warrior`** (**`get_definition`**, **`produces_unit_type`**, **`cost`**, etc.).
- **`SetCityProduction`** **`schema_version` `2`**: **`project_id`** on the action (**no** **`project_type`** field); **`PROJECT_ID_NONE`** clears.
- **`City.current_project`** carries **`project_id`** when set from **`apply`**; **`ProductionTick`** may add optional **`project_id`** to **`production_progress`** events.
- **`ProductionDelivery`** sets **`Unit.type_id`** from **`CityProjectDefinitions.produces_unit_type`** with transitional **`"warrior"`** fallback for legacy / unknown **`project_id`**.
- **`LegalActions`** / **`KEY_P`** use **`PROJECT_ID_PRODUCE_UNIT_WARRIOR`**; **`LogView`** **`set_city_production`** lines print **`project_id`**.

Must not (this subphase):

- **`produce_unit:settler`**, build-queue projects, tech / unlocks / refunds, **`unit_produced`** **`type_id`** field, presentation panels beyond allowed **`LogView`** / **`SelectionController`** touches

Validation:

- **`run-godot-tests.ps1`** exit **0** (**36** scripts including **`test_city_project_definitions.gd`**).
- Manual **F5**: **`set_city_production c\* produce_unit:warrior`** in **`LogView`**; production still completes a **warrior**.

### Phase 3.4 — First tech / progress definitions (roadmap)

Roadmap umbrella for **sciences**, **progress**, and **unlocks**. Implementation is **split**: **3.4a** locks the **systematic doc model** only; **3.4b** ships a **metadata-only** **`ProgressDefinitions`** seed; **3.4c** adds **deterministic player unlock state** and **`SetCityProduction`** gating; **3.4d** adds **`ProgressUnlockResolver`** + **`completed_progress_ids`** without authoring a player action; **3.4e** wires a manual **`complete_progress`** action through **`GameState.try_apply`**; **3.4f** adds **`KEY_G`** in **`SelectionController`** for a **hardcoded** **`foraging_systems`** debug **`CompleteProgress`** (still **outside** **`LegalActions`** / **AI**); **3.4g** adds **`ProgressDetector`** as a **read-only** candidate generator; **3.4h** adds **`ProgressCandidateFilter`** + **`KEY_H`** for **manual** **current-player-only** detector consumption (still **no** auto-apply, **no** **`LegalActions`** / **AI**); later subphases may add auto-apply policy, accumulation, and broader consumption.

### Phase 3.4a — Progression model checkpoint (implemented; documentation-only)

Goal:
Define the **vocabulary and separation of concerns** for sciences, breakthroughs, unlock targets, modifiers, effects, conditions, and detection **before** any Phase **3.4** code ([PROGRESSION_MODEL.md](PROGRESSION_MODEL.md)).

Shipped:

- **[PROGRESSION_MODEL.md](PROGRESSION_MODEL.md)** — systematic model; **selected examples** only; workbook / **CONTENT_BACKLOG** treated as **non-canonical** raw material.

Must not (this subphase):

- **No** **`game/**`** edits, registries, JSON, **`.tres`**, breakthrough detectors, unlock gating, **CONTENT_MODEL** / **CONTENT_BACKLOG** edits, new tests, or **`scripts/run-godot-tests.ps1`** changes

Validation:

- **`run-godot-tests.ps1`** exit **0** (still **36** scripts; **no** behavior change expected).

### Phase 3.4b — ProgressDefinitions seed (implemented)

Goal:
Ship a **tiny static** **`ProgressDefinitions`** registry with **five** seed sciences as **metadata only** — validate [PROGRESSION_MODEL.md](PROGRESSION_MODEL.md) row shape **before** unlock enforcement.

Shipped:

- **[progress_definitions.gd](../game/domain/content/progress_definitions.gd)** — **`ProgressDefinitions`**: **`has`**, **`get_definition`**, **`ids`**, **`category`**, **`era_bucket`**, **`concrete_unlocks`**, **`systemic_effects`**, **`future_dependencies`**; **no** preloads; **no** cross-registry validation of **`target_id`**.
- **`test_progress_definitions.gd`** in the headless runner (**37** scripts).

Must not (this subphase):

- **`LegalActions`**, **`GameState`**, **actions**, **`ProductionTick`**, **`ProductionDelivery`**, **AI**, **presentation**, unlock gating, breakthrough detectors, **player progress state**, **`rail_logistics`** row, **JSON** / **`.tres`** / autoloads / Node registries / **CONTENT_MODEL** / **CONTENT_BACKLOG** edits (per steering denylist).

Validation:

- **`run-godot-tests.ps1`** exit **0** (**37** scripts including **`test_progress_definitions.gd`**).

### Phase 3.4c — Unlock state and deterministic gating (implemented)

Goal:
Add **minimal** **player-specific** **`ProgressState`** on **`GameState`** and use it to **gate** **`SetCityProduction`** for **`produce_unit:warrior`** after structural **`validate`** passes — **no** schema bumps, **no** **`ProgressDefinitions`** reads.

Shipped:

- **[progress_state.gd](../game/domain/progress_state.gd)** — **`ProgressState`**: immutable unlock rows per **`owner_id`**, **`with_default_unlocks_for_players`**, **`has_unlocked_target`**, **`with_target_unlocked`**.
- **`GameState`**: optional second **`_init`** argument; default-seeds **warrior** **city_project** unlock for **`turn_state.players`**; **`try_apply`** returns **`project_not_unlocked`** when gated; **`PROJECT_ID_NONE`** never gated; **`progress_state == null`** is **ungated** (synthetic shells).
- **`LegalActions`**: omits enumerated **`SetCityProduction`** when locked; same ordering otherwise.
- Headless tests **`test_progress_state.gd`**, **`test_game_state_progress_state.gd`**, **`test_legal_actions_progress_gating.gd`**.

Must not (this subphase):

- Progress **accumulation**, **`completed_progress_ids`**, breakthrough **detectors**, **LLM**, **save/load**, **UI**, **JSON** / **`.tres`** / **Resources**, **autoloads**, **Node** registries, **signals**, **`_ready`** / **`_process`**, new **content** rows, **`ProgressDefinitions`** consumption, edits to **`game/domain/actions/**`**, **`ProductionTick`**, **`ProductionDelivery`**, **`MovementRules`**, **AI**, **presentation**, **`main` / `project.godot`**, deny-listed docs.

Validation:

- **`run-godot-tests.ps1`** exit **0** (**40** scripts).

**Later (post-3.4c):** see **Phase 3.4d** and [PROGRESSION_MODEL.md](PROGRESSION_MODEL.md) **Phase mapping**.

### Phase 3.4d — Apply progress-definition unlocks (implemented)

Goal:
Provide a **deterministic bridge** from **`ProgressDefinitions`** to **`ProgressState`**: completing a **`progress_id`** records it and adds **`concrete_unlocks`** + **`systemic_effects`** to **`unlocked_targets`**, without **`GameState`**, detectors, or UI.

Shipped:

- **[progress_unlock_resolver.gd](../game/domain/progress_unlock_resolver.gd)** — **`ProgressUnlockResolver.complete_progress`** (`Dictionary` result API).
- **`ProgressState`**: **`completed_progress_ids`** per owner; **`with_progress_id_completed`**, **`completed_progress_ids_for`**, **`has_completed_progress`**; backward-compatible **`_init`** when **`completed_progress_ids`** omitted.
- **`test_progress_unlock_resolver.gd`**, extended **`test_progress_state.gd`**; runner **41** scripts.

Must not (this subphase):

- **`GameState`** / **`LegalActions`** / **actions** / **`ProductionTick`** / **`ProductionDelivery`** / **`MovementRules`** / **AI** / **presentation** changes; new **`ProgressDefinitions`** rows; **`future_dependencies`** applied to **`unlocked_targets`**; breakthrough detectors; progress **accumulation** mechanics; save/load; deny-listed docs.

Validation:

- **`run-godot-tests.ps1`** exit **0** (**41** scripts).

**Later (post-3.4d):** breakthrough **detectors**, additional **progress** mechanics, **`future_dependencies`** semantics; see [PROGRESSION_MODEL.md](PROGRESSION_MODEL.md) **Phase mapping**.

### Phase 3.4e — Manual CompleteProgress action (implemented)

Goal:
Add a **deterministic**, **player-submitted** domain **`complete_progress`** action so **`GameState.try_apply`** can record **`ProgressDefinitions`** completion and apply unlocks via **`ProgressUnlockResolver`**, for **replay**, **tests**, and future **debug/UI/detectors** — **without** changing **`LegalActions`**, **AI**, or **F5** controls.

Shipped:

- **[complete_progress](../game/domain/actions/complete_progress.gd)** — **`schema_version: 1`**; **`validate(progress_state, action)`** (**no** current-player check); **`GameState`** branch calls **`ProgressUnlockResolver.complete_progress`**; **`ActionLog`** entry includes **`unlocked_targets`** delta.
- **`LogView`** formatter for **`complete_progress`** lines.
- **`test_complete_progress.gd`**, **`test_complete_progress_flow.gd`**, additive **`test_log_view.gd`**; runner **43** scripts.

Must not (this subphase):

- **`LegalActions`** enumeration; **`RuleBasedAIPlayer`** / **`RuleBasedAIPolicy`** / **`AITurnController`** changes; **key** bindings; **presentation** controllers beyond **`log_view.gd`**; breakthrough **detectors**; progress **accumulation**; **`future_dependencies`** application; new **`ProgressDefinitions`** rows; **`ProductionTick`** / **`Delivery`** / **`MovementRules`** / **`Scenario`** / **`TurnState`** changes; deny-listed docs.

Validation:

- **`run-godot-tests.ps1`** exit **0** (**43** scripts).

### Phase 3.4f — Manual progress debug input (implemented)

Goal:
Expose a **minimal** **F5 / manual** path to **`CompleteProgress`** for **`foraging_systems`** so the **progression** chain is **exercisable** from the editor **without** **`LegalActions`**, **AI**, detectors, or **`ProgressDefinitions`** cycling.

Shipped:

- **`SelectionController`**: **`KEY_G`** (pressed, non-echo) → **`CompleteProgress.make(current_player_id, "foraging_systems")`** → **`game_state.try_apply`**; on **accept**, **`turn_label.refresh()`** and **`log_view.refresh()`** when wired; on **reject**, **`push_warning`** with **`reason`**; **no** **`scenario`** re-point, **no** view redraws, **no** selection clear.

Must not (this subphase):

- **`LegalActions`** / **AI** / **`AITurnController`** / **`EndTurnController`** / **`main.*`** / **`project.godot`** / **registry** / **action schema** / **`ProgressState`** / **`ProgressUnlockResolver`** / **`ProgressDefinitions`** / **`ProductionTick`** / **`ProductionDelivery`** / **`MovementRules`** / **`Scenario`** / **`TurnState`** / **presentation** beyond **`selection_controller.gd`** / **new** automated tests / **`run-godot-tests.ps1`** churn (count stays **43**); deny-listed docs.

Validation:

- **`run-godot-tests.ps1`** exit **0** (**43** scripts).

### Phase 3.4g — First deterministic progress detector (implemented)

Goal:
Introduce the **first** **deterministic**, **read-only** **progress detector** that **proposes** **`CompleteProgress`** actions from **accepted** **`ActionLog`** patterns — **without** **`GameState`** integration, **without** **`try_apply`**, and **without** hidden side effects.

Shipped:

- **[progress_detector.gd](../game/domain/progress_detector.gd)** — **`ProgressDetector.suggested_complete_progress_actions(game_state)`** returns **`Dictionary`** values shaped like **`CompleteProgress.make`**; **first rule:** **`found_city`** (**`result: accepted`**) ⇒ **`controlled_fire`** if not already completed; **`turn_state.players`** order; defensive **null** / **non-int** handling.
- **`test_progress_detector.gd`**; runner **44** scripts.

Must not (this subphase):

- **`GameState.try_apply`** / **`GameState`** edits; **`LegalActions`** / **AI**; **`actions/**`**; **`ProgressState`** / **`ProgressUnlockResolver`** / **`ProgressDefinitions`** / **`ProductionTick`** / **`ProductionDelivery`** / **`MovementRules`** / **`Scenario`** / **`TurnState`**; **presentation** / **`main` / `project.godot`**; **auto-apply** of suggestions; **UI** / key bindings; **`progress_detectors/`** subdirectory; new **`ProgressDefinitions`** rows; deny-listed docs.

Validation:

- **`run-godot-tests.ps1`** exit **0** (**44** scripts).

### Phase 3.4h — Detector candidate consumption (manual KEY_H, implemented)

Goal:
Allow **F5 / manual** application of **Phase 3.4g** detector **`CompleteProgress`** candidates **for the current player only**, respecting **`GameState.try_apply`**’s **current-player** gate **without** changing **`ProgressDetector`**, **`GameState`**, or **`LegalActions`**.

Shipped:

- **[progress_candidate_filter.gd](../game/domain/progress_candidate_filter.gd)** — **`ProgressCandidateFilter.for_current_player`** filters by **`actor_id == current_player_id()`** only (**no** **`CompleteProgress.validate`** in filter).
- **`SelectionController`**: **`KEY_H`** → **`for_current_player`** → **`try_apply(candidates[0])`**; **`turn_label`** / **`log_view`** on **accept**; **`push_warning`** when empty or rejected.
- **`test_progress_candidate_filter.gd`**; runner **45** scripts.

Must not (this subphase):

- Edit **`progress_detector.gd`**, **`game_state.gd`**, **`legal_actions.gd`**, **`actions/**`**, **`progress_state`**, **`progress_unlock_resolver`**, **`content/**`**, **`ProductionTick`**, **`ProductionDelivery`**, **`MovementRules`**, **`Scenario`**, **`TurnState`**, **`game/ai/**`**, **`main.*`**, **`project.godot`**, or **presentation** beyond **`selection_controller.gd`**; **auto-apply**, queues, engine events, new action schemas, new **`ProgressDefinitions`** rows; deny-listed docs.

Validation:

- **`run-godot-tests.ps1`** exit **0** (**45** scripts).

### Phase 3.5 — First faction / world identity pass

Goal:
Early **faction** or **civ** knobs (traits, start-bias stubs) and **world** parameters — **mechanical** first; narrative depth in **Phase 6**.

**Must reference [CONTENT_MODEL.md](CONTENT_MODEL.md).**

Validation:
To be detailed per subphase; preserve **domain / presentation** split from [ARCHITECTURE_PRINCIPLES.md](ARCHITECTURE_PRINCIPLES.md).

### Phase 3.5a — Faction / custom-civ identity model (implemented; documentation-only)

Goal:

- Define the **docs-only** identity model for **predefined civilisations** and **custom civilisations** before any faction/trait registry or UI exists.

Shipped:

- **[FACTION_IDENTITY.md](FACTION_IDENTITY.md)** — predefined-civ and custom-civ models, balanced trait vocabulary (conceptual), three prototype factions, three non-canonical toy examples, prototype art / generated-asset policy.
- **Predefined-civ model** and **custom-civ profile model** (conceptual fields only).
- **Balanced trait model** (categories + cost **shape**, no numbers).
- **Prototype factions** (Hearthbound, Wayfinders, Forge Compact) and **non-canonical toy examples** (debug/playtest only).

Must not:

- **No** code, **no** registries, **no** `game/**`, **no** `scripts/**`, **no** tests, **no** scenes, **no** assets, **no** generated images, **no** UI, **no** gameplay wiring, **no** deny-listed docs.

Validation:

- **`run-godot-tests.ps1`** exit **0** (**45** scripts — regression-only; count **unchanged**).

### Phase 3.5b — Debug FactionDefinitions seed (implemented)

Goal:

- Ship the smallest **faction-data slice** using the **three non-canonical** toy examples for **demo/playtest identity** without **gameplay wiring**.

Shipped:

- **`game/domain/content/faction_definitions.gd`**
- **`game/domain/tests/test_faction_definitions.gd`**
- **Three** debug ids (`debug_vasterviksjavlarna`, `debug_malmofubikkarna`, `debug_pajasarna_fran_paris`)
- **Helper methods** (`has`, `ids`, `get_definition`, field accessors)
- **No** cross-registry validation (trait ids are forward references only)

Must not:

- **No** trait registry (**`TraitDefinitions`**).
- **No** player / faction assignment.
- **No** AI.
- **No** **`LegalActions`** wiring.
- **No** **`GameState`** wiring.
- **No** Progress wiring.
- **No** UI.
- **No** scenes.
- **No** assets.
- **No** generated images.
- **No** canon promotion of debug rows.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1`
- Expected **46** scripts.
- All **PASS**, exit **0**.

### Phase 3.5d — Prototype faction-banner visual slice (implemented)

Goal:

- **Smallest** visual identity slice for the **three** existing **debug** faction rows (`FactionDefinitions`).

Shipped:

- **Three** prototype banner **PNGs** under `game/assets/prototype/factions/banners/`
- **`game/assets/prototype/README.md`** — prototype / non-final policy
- **`PROVENANCE.md`** next to banners — creation method and **non-final** status
- **`game/presentation/faction_asset_paths.gd`** — **`FactionAssetPaths`**, **pure string** paths (**no** `ResourceLoader`, **no** `load`, **no** `FileAccess`)
- **`game/presentation/faction_banner_gallery.gd`** — **`FactionBannerGallery`**, **F1** debug overlay (**no** gameplay effect)
- **`game/presentation/tests/test_faction_asset_paths.gd`** and **`test_faction_banner_gallery.gd`**
- **`game/main.gd`** — wires gallery + **F1** toggle (**smallest** diff; **no** change to **F** / **P** / **G** / **H** / **A** / **Space**)

Must not:

- **No** terrain, unit, city, **HUD**, or **camera / perspective** art
- **No** player → faction assignment
- **No** gameplay wiring (`GameState`, `Scenario`, `LegalActions`, **AI**, progression)
- **No** final art commitment
- **No** **`ART_DIRECTION.md`**
- **No** full **Phase 4** visual pass (this is a **banner-only** prototype)

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1`
- Expected **48** scripts, all **PASS**, exit **0**
- **Manual** F5: **F1** toggles the gallery; map / turn / actions unchanged

### Phase 3.5e — Faction identity doc scope cleanup (implemented; documentation-only)

Goal:

- Clarify **3.5a** explicit non-goals after **3.5d** shipped prototype assets and **F1** debug presentation — remove apparent contradiction between an older “no assets / no UI” list and intentionally scoped later **3.5** work.

Shipped:

- **`FACTION_IDENTITY.md`** — **§ Explicit non-goals** renamed / scoped to **Phase 3.5a**; short note that later **3.5** subphases may add **prototype** assets or **debug** presentation when **explicitly scoped**; **3.5d** remains the **non-final**, **replaceable** banner + **F1** gallery slice (**no** gameplay pixel dependence; **no Phase 4** broadening; **Phase 6** still owns final lore / art / IP).
- **`DECISION_LOG.md`** entry for **3.5e**.

Must not:

- **No** code, **no** `game/**`, **no** `scripts/**`, **no** assets, **no** tests, **no** gameplay or **UI** implementation changes.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1`
- Expected **48** scripts, all **PASS**, exit **0**

## Phase 4 — Visual identity and presentation foundation

Goal:
**Art direction** and **presentation** quality: map **readability**, **terrain** and **unit** and **city** reads, **UI** style, **camera** feel, **perspective** experiments (e.g. fake-isometric), **animation** principles.

Must not (roadmap):

- embed **final balance** or new **win conditions** inside art milestones
- bypass **domain** truth for “looks-only” authoritative game state

Note:
**Placeholders** from **Phase 2.x** / **Phase 3.x** may remain until replaced here; **Phase 4** owns **coherent visual identity**.

### Phase 4.0 — Visual direction checkpoint

Goal:
Lock **look-and-feel** pillars (palette, readability, tone) before heavy asset work.

### Phase 4.1 — Terrain visual style

Goal:
Terrain **readability** and silhouette; beyond flat debug fills.

### Phase 4.2 — Unit visual style

Goal:
**Sprites** or agreed **markers**, **owner** clarity, hooks for **selection** / **motion**.

### Phase 4.3 — City visual style

Goal:
Cities **read** at a glance; scale with zoom.

### Phase 4.4 — UI / HUD style

Goal:
**HUD**, panels, **typography** — consistent with **Phase 6** copy where applicable.

### Phase 4.5 — Camera / perspective / animation pass

Goal:
**Camera** UX, **perspective** experiments, **motion** principles (no gameplay truth hidden in tween-only client state).

Validation:
Editor and checklist-driven; headless tests only for **pure** layout/formatting helpers if introduced.

## Phase 5 — Strategic dynamics

Goal:
**Combat**, **expansion pressure**, **terrain / value** tradeoffs, **production** tradeoffs, **AI priorities** — still **legal-actions**-driven; **no LLM** required for core play.

Features (roadmap):

- deterministic combat resolution path
- pressure to expand and defend
- AI **prioritization** over existing **enumeration** / **`GameState.try_apply`** pipeline

Must not (roadmap):

- require **LLM** for core loop
- mutate rules state outside **`GameState.try_apply`** (or documented server equivalent)

Validation:
To be detailed; AI must still submit only **validated** actions per [AI_DESIGN.md](AI_DESIGN.md).

## Phase 6 — Empire of Minds worldbuilding and identity

Goal:
**Lore**, **factions**, **aesthetics**, **naming**, **tech tree flavor**, **UI language**, and **explicit non-Civ** identity — aligned with [PROJECT_BRIEF.md](PROJECT_BRIEF.md) **IP boundary**.

Must not (roadmap):

- copy **Civilization** or other commercial IP (names, visuals, text)
- use flavor to **override** **domain** rules without a steered schema change

Validation:
Copy and asset review against **IP** checklist; mechanical content stays versioned.

## Phase 7 — Balance / content iteration

Goal:
**Costs**, **movement ranges**, **production rates**, **unit roles**, **map tuning**, **AI behavior tuning** — after **Phase 3** foundation exists.

Must not (roadmap):

- rebalance **without** regression tests or documented baselines where feasible
- blur **Phase 3** “definition” vs **Phase 7** “tuning” without updating this plan

Validation:
Repeatable scenarios, **`ActionLog`**, and tests for **regressions** where practical.

## Deferred — Cloud / Self-Host roadmap

Canonical steering for asynchronous, server-authoritative play and hosting remains **[CLOUD_PLAY.md](CLOUD_PLAY.md)**. The subsections below preserve the **prior phase-plan forward milestones** for **cloud** work; they are **decoupled** from the **gameplay** numbering **above** so **Phases 2–7** can evolve without **renumbering** infrastructure phases.

### Async Cloud

Goal:
Server-authoritative asynchronous play.

Features:

- backend API
- PostgreSQL
- create/join game
- submit turn actions
- validate actions server-side
- next-player turn flow
- AI worker for AI players

Exit criteria:

- two clients can play asynchronously
- server rejects illegal actions
- server persists game state
- AI turns can be run by worker
- client never owns canonical cloud state

### Private Cloud / Self-Host

Goal:
Make self-hosting practical.

Features:

- Docker Compose server
- backend health check
- connect-to-server UI
- admin token
- backup/export
- setup docs

Exit criteria:

- user can run backend locally or on VPS
- client can connect by URL
- server health check works
- backup/export path exists

### Server Manager

Goal:
Reduce friction for private cloud hosting.

Features:

- SSH installer
- existing VPS setup flow
- later provider integrations

Exit criteria:

- user can configure an existing VPS with guided setup
- provider API integration remains optional
- official cloud is not required
