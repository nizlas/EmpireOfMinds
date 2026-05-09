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
- Expected **49** scripts, all **PASS**, exit **0**
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
- Expected **49** scripts, all **PASS**, exit **0**

## Phase 4 — Visual identity and presentation foundation

Goal:
**Art direction** and **presentation** quality: map **readability**, **terrain** and **unit** and **city** reads, **UI** style, **camera** feel, **perspective** experiments (e.g. fake-isometric), **animation** principles.

Must not (roadmap):

- embed **final balance** or new **win conditions** inside art milestones
- bypass **domain** truth for “looks-only” authoritative game state

Note:
**Placeholders** from **Phase 2.x** / **Phase 3.x** may remain until replaced here; **Phase 4** owns **coherent visual identity**.

**Phase 4 asset workflow:** Non-trivial prototype assets should use the **Asset Request Pack** workflow in **[VISUAL_DIRECTION.md](VISUAL_DIRECTION.md)** (section **Asset request workflow**). Phase implementation must **not** silently generate or add visual assets **outside** approved scope; trivial programmatic placeholders remain allowed when **explicitly in scope** (see **VISUAL_DIRECTION.md**).

### Phase 4.0 — Visual direction checkpoint (implemented; documentation-only)

Goal:

- Lock **look-and-feel** pillars (palette intent, readability, tone, prototype vs final boundary) before heavier visual slices — via **[VISUAL_DIRECTION.md](VISUAL_DIRECTION.md)**.

Shipped:

- **`docs/VISUAL_DIRECTION.md`** — prototype visual direction for **4.1–4.5**; **RENDERING.md** remains implementation state.
- Steering updates: **`PHASE_PLAN.md`** (this block), **`DECISION_LOG.md`**, **`FACTION_IDENTITY.md`** (cross-reference only).

Must not:

- **No** code, **no** `game/**`, **no** `scripts/**`, **no** assets, **no** tests, **no** scenes, **no** UI implementation work in **4.0**.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1`
- Expected **49** scripts, all **PASS**, exit **0** (regression-only).

### Phase 4.0a — Prototype asset workflow checkpoint (implemented; documentation-only)

Goal:

- Define a **request-first** workflow for **non-trivial** prototype art before **4.1+**, so visual scope stays **reviewable** and **provenance-friendly**.

Shipped:

- **`docs/VISUAL_DIRECTION.md`** — **Asset request workflow** and **Asset Request Pack** checklist; **who may create** trivial vs non-trivial assets.
- **`docs/PHASE_PLAN.md`** — **Phase 4 asset workflow** note (this section + intro note above).
- **`docs/DECISION_LOG.md`** — dated **asset workflow** decision.

Must not:

- **No** code, **no** assets, **no** **`RENDERING.md`** changes, **no** expansion of **4.1–4.5** feature scope beyond documenting workflow expectations.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1`
- Expected **49** scripts, all **PASS**, exit **0** (regression-only).

### Phase 4.1 — Terrain visual style (implemented)

Goal:

- Terrain **readability** and clearer **land vs water** read; **parchment-map**-aligned prototype palette per **[VISUAL_DIRECTION.md](VISUAL_DIRECTION.md)** — **Terrain direction for 4.1**.

Shipped:

- **`game/presentation/map_view.gd`** — **`MapView._terrain_to_color`**: warmer muted **PLAINS**, calmer slate-teal **WATER**; still **flat polygon fills** only (**no** textures, **no** imports).
- **`docs/RENDERING.md`** — **Terrain fill colors** section documents current prototype RGB and pre-4.1 reference.

Must not:

- **No** new terrain types, **no** **`HexMap`** / **`MovementRules`** / domain / content changes, **no** imported or generated terrain art.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1`
- Expected **49** scripts, all **PASS**, exit **0**

### Phase 4.1c — Prototype painterly terrain textures (implemented)

Goal:

- **Import** and wire **prototype** painterly **PNG** terrain fills for **PLAINS** and **WATER** only — presentation-only; **no** domain terrain model expansion.

Shipped:

- **`game/assets/prototype/terrain/plains_painterly.png`**, **`water_painterly.png`** — already in repo; **`PROVENANCE.md`** in that folder.
- **`game/presentation/map_view.gd`** — load/cache textures in **`_ready()`**; **`_draw()`** uses **`draw_colored_polygon(..., uvs, tex)`** per hex when loaded; else **4.1** flat **`_terrain_to_color`** fill.
- **`docs/RENDERING.md`**, **`docs/PHASE_PLAN.md`**, **`docs/DECISION_LOG.md`**

Must not:

- **No** new terrain types, **no** **`HexMap`** / **`MovementRules`** / **`TerrainRuleDefinitions`** changes, **no** hit-test or **`HexLayout`** changes, **no** unit/city ratio or marker drawing changes.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1`
- Expected **49** scripts, all **PASS**, exit **0**

### Phase 4.1d — Terrain texture UV polish (implemented)

Goal:

- **World-anchored** terrain **UVs** so prototype textures read more **continuous** across hexes — **no** per-hex **AABB** full-texture stamp; **MapView** only.

Shipped:

- **`game/presentation/map_view.gd`** — **`_world_anchored_corner_uvs`**, **`terrain_texture_world_scale`** (default **512**), **`texture_repeat = TEXTURE_REPEAT_ENABLED`**
- **`docs/RENDERING.md`**, **`docs/PHASE_PLAN.md`**, **`docs/DECISION_LOG.md`**

Must not:

- **No** domain / **`HexLayout.SIZE`** / viewport / marker / new assets / coast blending / shaders beyond this UV + repeat change.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1`
- Expected **49** scripts, all **PASS**, exit **0**

### Phase 4.1e — Terrain detail overlay prototype (implemented)

Goal:

- **Subtle** **presentation-only** terrain **life** for **PLAINS** / **WATER** — **deterministic** procedural overlay; **no** new **HexMap** types or **cover** system.

Shipped:

- **`game/presentation/map_view.gd`** — **`_terrain_detail_hash`**, **`_draw_plains_detail`** / **`_draw_water_detail`** / **`_draw_terrain_detail_overlay`** after base hex fill.
- **`docs/RENDERING.md`**, **`docs/PHASE_PLAN.md`**, **`docs/DECISION_LOG.md`**, **`docs/VISUAL_DIRECTION.md`** (future **2.5D** note only)

Must not:

- **No** domain / **movement** / map-gen / **viewport** / **MAP_LAYER_ORIGIN** / markers / **.import** changes; **no** **terrain-aware** unit **occlusion**.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1`
- Expected **49** scripts, all **PASS**, exit **0**

### Phase 4.2 — Unit visual style (implemented)

Goal:

- **Markers** (not sprites), **owner** clarity, legible **type** hint, **selected** unit emphasis — per **[VISUAL_DIRECTION.md](VISUAL_DIRECTION.md)** — **Unit direction for 4.2**.

Shipped:

- **`game/presentation/units_view.gd`** — **`type_id`** on **`compute_marker_items`**; stronger **owner** fills; **dark rim** ring; **`ThemeDB.fallback_font`** **glyph** (first letter of **`type_id`**); optional **white selection halo** when **`selection`** matches **`unit_id`**.
- **`game/main.gd`** — assigns **`units_view.selection`**.
- **`game/presentation/selection_controller.gd`** — **`units_view.queue_redraw()`** when selection changes by click / clear / empty founder (presentation sync only).

Must not:

- **No** sprites, **no** imported art, **no** **`Unit`** / **`UnitDefinitions`** / gameplay changes.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1`
- Expected **49** scripts, all **PASS**, exit **0**

### Phase 4.2a — Map display scale readability (implemented)

Goal:

- **2×** larger **on-screen** hex grid for readability by scaling **presentation** `HexLayout` only — **no** camera zoom, **no** pan, **no** domain / movement / map-gen changes.

Shipped:

- **`game/presentation/hex_layout.gd`** — **`SIZE`** **32.0 → 64.0** (circumradius); **`hex_to_world`** / **`hex_corners`** scale together.
- **`game/presentation/map_view.gd`** — **`hex_tile_size`** default **64.0** (editor hint only; draw path uses **`layout`**).
- **`docs/RENDERING.md`** — documents **64**-unit circumradius and **4.2a** scope.

Must not:

- **No** zoom controls, **`Camera2D`** UX, **`project.godot`** changes, **no** gameplay or **`HexMap`** coordinate semantics changes.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1`
- Expected **49** scripts, all **PASS**, exit **0**

### Phase 4.3 — City visual style

Goal:
Cities **read** at a glance; scale with zoom. *(Direction: [VISUAL_DIRECTION.md](VISUAL_DIRECTION.md) — City direction for 4.3.)*

**Phase 4.3a (documentation):** Approved **prototype map marker icon** request pack (city + settler + warrior) — **[ASSET_REQUEST_PACKS/PHASE_4_3A_MARKER_SET.md](ASSET_REQUEST_PACKS/PHASE_4_3A_MARKER_SET.md)**.

### Phase 4.3b — Prototype map marker icons wired (implemented)

Goal:

- **Import** (external PNGs) and **wire** **static map marker icons** for **city**, **`settler`**, and **`warrior`** — presentation only.

Shipped:

- **`game/assets/prototype/map_markers/`** — **`city_marker.png`**, **`unit_settler_marker.png`**, **`unit_warrior_marker.png`** + **`PROVENANCE.md`**
- **`game/presentation/cities_view.gd`** — **`load()`** city texture; **draw** owner ring → **texture** → outline; **diamond fallback** if **load** fails
- **`game/presentation/units_view.gd`** — **`type_id`**-mapped textures with **Phase 4.2** **fallback**; layered **owner under-circle**, **selection halo**, **rim**
- **`docs/RENDERING.md`** — **Phase 4.3b** + **Phase 1.4b** / **2.1** updates

Must not:

- **No** domain / content / **`UnitDefinitions`** / hit-test radius changes; **no** animated **sprites** / **sprite** sheets.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1`
- Expected **49** scripts, all **PASS**, exit **0**

### Phase 4.3c — Map scale + marker alpha repair (implemented)

Goal:

- **Global** on-screen hex grid larger (shared **`HexLayout.SIZE`**), not icon-ratio-only tuning; **RGB** marker PNGs blend without opaque **white** squares.

Shipped:

- **`game/presentation/hex_layout.gd`** — **`SIZE`** **64.0 → 128.0** (presentation circumradius; **4×** original **32.0** baseline).
- **`game/presentation/map_view.gd`** — **`hex_tile_size`** default **128.0**.
- **`game/presentation/marker_texture_util.gd`** — **`load_marker_icon`**: **RGBA** + top-left **background** colour keyed transparent (epsilon); prefer replacing assets with **true** **PNG** **alpha** later.
- **`game/presentation/cities_view.gd`** / **`units_view.gd`** — use **`MarkerTextureUtil`** for marker paths (**4.3i**: **direct** **`ResourceLoader.load`** **`Texture2D`** for **RGBA** assets; util **legacy** for those three).
- **`docs/RENDERING.md`**, **`docs/DECISION_LOG.md`** — **4.3c** notes.

Must not:

- **No** camera zoom/pan; **no** domain/content changes; **no** independent icon-ratio change as the **primary** scale fix.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1`
- Expected **49** scripts, all **PASS**, exit **0**

### Phase 4.3d — Viewport fit + marker size polish (implemented)

Goal:

- Larger **default window** so **`HexLayout.SIZE` 128** maps are not clipped; slightly larger **marker icon** defaults for detail — **no** **`SIZE`** change, **no** camera/zoom.

Shipped:

- **`game/project.godot`** — **`display/window/size/viewport_width` 1600**, **`viewport_height` 1000**
- **`game/presentation/units_view.gd`** — **`unit_icon_height_ratio`** default **0.60**
- **`game/presentation/cities_view.gd`** — **`city_icon_height_ratio`** default **0.80**
- **`docs/RENDERING.md`**, **`docs/PHASE_PLAN.md`**, **`docs/DECISION_LOG.md`**

Must not:

- **No** **`HexLayout.SIZE`** change; **no** **`Camera2D`**; **no** domain/content/gameplay changes.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1`
- Expected **49** scripts, all **PASS**, exit **0**

### Phase 4.3f — Play-area size + marker detail polish (implemented)

Goal:

- **1.5×** default **viewport** vs **4.3d** (**1600×1000 → 2400×1500**); larger **marker** ratios; **clean** icons (**no** rings / **no** unit selection halo); **`HexLayout.SIZE` 128** unchanged.

Shipped:

- **`game/project.godot`** — **`viewport_width` 2400**, **`viewport_height` 1500**
- **`game/presentation/units_view.gd`** — **`unit_icon_height_ratio`** **0.70**; textured path = **texture only**; fallback disk + glyph **no** rim
- **`game/presentation/cities_view.gd`** — **`city_icon_height_ratio`** **0.90**; textured path = **texture only**
- **`docs/RENDERING.md`**, **`docs/PHASE_PLAN.md`**, **`docs/DECISION_LOG.md`**

Must not:

- **No** **`HexLayout.SIZE`** change; **no** **`Camera2D`**; **no** gameplay/domain changes.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1`
- Expected **49** scripts, all **PASS**, exit **0**

### Phase 4.3g — Map origin / top padding (implemented)

Goal:

- Shift **all** map layers + **pointer** mapping **down** by a shared **Y** offset so top hexes are not clipped — **no** **`SIZE`**, **viewport**, marker ratio, or **camera** changes.

Shipped:

- **`game/main.gd`** — **`MAP_LAYER_ORIGIN`** **`(400, 428)`**; **`_ready()`** assigns to **MapView**, **CitiesView**, **SelectionView**, **UnitsView**, **SelectionController**
- **`game/main.tscn`** — matching default **`position`** on those five nodes
- **`docs/RENDERING.md`**, **`docs/PHASE_PLAN.md`**, **`docs/DECISION_LOG.md`**

Must not:

- **No** **`HexLayout.SIZE`** / **viewport** / marker-ratio edits; **no** zoom/pan/**`Camera2D`**.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1`
- Expected **49** scripts, all **PASS**, exit **0**

### Phase 4.3h — Marker texture filtering polish (implemented)

Goal:

- **Smoother** downscaled **city** / **unit** marker PNGs via **linear** **`CanvasItem.texture_filter`** — **presentation-only**; **no** size, ratio, asset, or terrain changes.

Shipped:

- **`game/presentation/units_view.gd`**, **`game/presentation/cities_view.gd`** — **`TEXTURE_FILTER_LINEAR`** in **`_ready()`**
- **`docs/RENDERING.md`**, **`docs/PHASE_PLAN.md`**, **`docs/DECISION_LOG.md`**

Must not:

- **No** **`unit_icon_height_ratio`** / **`city_icon_height_ratio`** / **`HexLayout.SIZE`** / viewport / **MapView** UV edits; **no** global texture defaults.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1`
- Expected **49** scripts, all **PASS**, exit **0**

### Phase 4.3i — True-alpha marker adoption + sharp downscale (implemented)

Goal:

- **RGBA** **512×512** map markers loaded **directly**; **remove** runtime **background-keying** for city/settler/warrior; **scoped** import **mipmaps** + **`LINEAR_WITH_MIPMAPS`** for cleaner minification.

Shipped:

- **`game/presentation/units_view.gd`**, **`game/presentation/cities_view.gd`** — **`ResourceLoader.load`** **`Texture2D`**; **`TEXTURE_FILTER_LINEAR_WITH_MIPMAPS`**
- **`game/presentation/marker_texture_util.gd`** — documented **legacy** (unused for those three paths)
- **`game/assets/prototype/map_markers/*.png.import`** (three files) — **`mipmaps/generate=true`**
- **`game/assets/prototype/map_markers/PROVENANCE.md`**, **`docs/RENDERING.md`**, **`docs/PHASE_PLAN.md`**, **`docs/DECISION_LOG.md`**

Must not:

- **No** marker ratio / **`SIZE`** / viewport / terrain / domain changes; **no** new assets; **no** global texture defaults.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1`
- Expected **49** scripts, all **PASS**, exit **0**

### Phase 4.3j — Prototype asset import quality standard (implemented; documentation-only)

Goal:

- Preserve **4.3i** lessons as **default steering** for future **scaled** prototype rasters — **true RGBA**, **direct** load, **scoped** import/filter, **no** preferred runtime keying.

Shipped:

- **`docs/VISUAL_DIRECTION.md`** — **Prototype raster import quality standard** (default policy, verification, exceptions).
- **`docs/RENDERING.md`** — **Phase 4.3j** practical expectations + cross-reference.
- **`docs/ASSET_REQUEST_PACKS/PHASE_4_3A_MARKER_SET.md`** — approved **delivery format** note (markers).
- **`docs/PHASE_PLAN.md`**, **`docs/DECISION_LOG.md`**

Must not:

- **No** code, **no** assets, **no** **`.import`**, **no** **`project.godot`**.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1`
- Expected **49** scripts, all **PASS**, exit **0**

### Phase 4.4a — Debug log clear of map hexes (implemented)

Goal:

- Reposition **`LogView`** so the **action log** **does not** paint over **map** **hexes** — **presentation-only**; **no** log semantics or **Gameplay** changes.

Shipped:

- **`game/main.tscn`** — **`LogView`** **`Label`** rect moved to **lower** viewport band (**y ~1220–1475**, **2400×1500** default).
- **`docs/RENDERING.md`**, **`docs/PHASE_PLAN.md`**, **`docs/DECISION_LOG.md`**

Must not:

- **No** **`MAP_LAYER_ORIGIN`** / **`HexLayout.SIZE`** / viewport / domain / **`log_view.gd`** **compute** changes.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1`
- Expected **49** scripts, all **PASS**, exit **0**

### Phase 4.4 — UI / HUD style

Goal:
**HUD**, panels, **typography** — consistent with **Phase 6** copy where applicable. *(Direction: [VISUAL_DIRECTION.md](VISUAL_DIRECTION.md) — HUD / feedback direction for 4.4.)*

### Phase 4.5a — Faux perspective map tilt + unit foot anchoring (implemented; projection superseded by 4.5c)

Goal:

- **Presentation-only** faux perspective: shared **Y** scale on map layers so the board reads slightly “tilted” without changing **domain** or **`HexLayout`**.
- **Unit** marker art sits on the **hex** more naturally by anchoring **textured** icons by **foot/base**; **cities** stay **center-centered**.

Shipped (historical):

- **`game/main.gd`** — previously **`MAP_LAYER_TILT_Y`** + **`Node2D`** **`scale`** (**4.5c** replaces with **`MapPlaneProjection`**). **`unit_icon_foot_offset_ratio`** semantics **retained**.
- **`game/main.tscn`** — previously mirrored **`scale`** (**removed** in **4.5c**).
- **`game/presentation/units_view.gd`** — **`unit_icon_foot_offset_ratio`** **`0.20`**; foot in layout space.
- **`docs/RENDERING.md`**, **`docs/PHASE_PLAN.md`**, **`docs/DECISION_LOG.md`**

Must not:

- **No** **`HexLayout.SIZE`** / **`MAP_LAYER_ORIGIN`** / viewport / terrain / marker import / domain changes; **no** `Camera2D`, zoom, pan, occlusion, new assets; **no** per-layer **offset** hacks — **`SelectionController`** and drawn layers share **`MapPlaneProjection`** (**4.5c**).

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1`
- Expected **49** scripts, all **PASS**, exit **0**

### Phase 4.5b — Map-plane projection (documentation-only design checkpoint)

**Status:** **Design checkpoint only** — **no** implementation in this phase; **no** code, scenes, assets, imports, or gameplay/domain/content changes.

**Documented intent:**

- **Preserve** **`4.5a`** **unit foot anchoring** in **layout / world** space; treat **`MAP_LAYER_TILT_Y`** as **temporary** **vertical flattening**, **not** true perspective.
- **Future implementation** should introduce a **shared** **map-plane projection** with **forward** mapping (layout → presentation draw space) and **inverse** mapping (**`SelectionController`** / **hit-testing**), **one** canonical math path for **terrain**, **selection**, **units**, **cities**, and **picking**.
- **Terrain** and **selection** geometry **projected consistently**; **unit** icons **preferably** **upright billboards** **without** map-plane **squash**; **cities** **may** stay **center**-anchored or get a **later** rule.
- **Future stack** (not gated on **4.5b**): **terrain base** → **unit billboard** → **optional** foreground **occluder**; **no** **forest/cover** implementation in **4.5b**.

**Shipped (this checkpoint):**

- **`docs/RENDERING.md`**, **`docs/VISUAL_DIRECTION.md`**, **`docs/PHASE_PLAN.md`**, **`docs/DECISION_LOG.md`**

Must not (checkpoint):

- **No** **`Camera2D`** **zoom/pan**, **real 3D**, **`HexLayout`**, or **domain** changes as part of **4.5b**.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1`
- Expected **49** scripts, all **PASS**, exit **0** (**documentation-only**; behaviour unchanged)

### Phase 4.5c — Shared map-plane projection (implemented)

Goal:

- Replace **`4.5a`** uniform **`Node2D`** **Y-scale** with a **shared invertible affine** **map-plane** projection (**shear** + **vertical scale**) for a **receding-board** read.
- **Terrain** and **selection** polygons use **projected** corners; **UVs** remain **layout**-anchored (**4.1d**). **Unit** **foot** and **city** **centers** in **layout** space, then **projected**; **marker** textures **upright** (**axis-aligned** rects). **Picking** uses **`to_layout(to_local(mouse))`**.

Shipped:

- **`game/presentation/map_plane_projection.gd`** — **`to_presentation`** / **`to_layout`**; introduced **`plane_y_scale`** **`0.82`**, **`shear_x_per_world_y`** **`0.12`** (**4.5d** tunes shear to **`-0.10`** — see **4.5d**).
- **`game/main.gd`**, **`game/main.tscn`** — **`MapPlaneProjection`** instance; **`MAP_LAYER_ORIGIN`**; **`scale`** **`(1,1)`**; **no** **`MAP_LAYER_TILT_Y`**
- **`game/presentation/map_view.gd`**, **`selection_view.gd`**, **`units_view.gd`**, **`cities_view.gd`**, **`selection_controller.gd`**
- **`game/presentation/tests/test_map_plane_projection.gd`**; **`scripts/run-godot-tests.ps1`** lists **49** scripts
- **`docs/RENDERING.md`**, **`docs/PHASE_PLAN.md`**, **`docs/DECISION_LOG.md`**, **`docs/VISUAL_DIRECTION.md`**

Must not:

- **No** domain / **`HexLayout.SIZE`** / viewport / terrain types / assets / imports / **`Camera2D`** zoom-pan / **3D** / foreground occlusion.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1`
- Expected **49** scripts, all **PASS**, exit **0**

### Phase 4.5d — Map-plane projection tuning: away direction (implemented)

Goal:

- Tune **4.5c** **`MapPlaneProjection`** **defaults** so the board reads **receding** rather than **sideways-sheared**; **architecture** unchanged.

Shipped:

- **`game/presentation/map_plane_projection.gd`** — **`shear_x_per_world_y`** **`0.12` → `-0.10`**; **`plane_y_scale`** **`0.82`** unchanged; **`MAP_LAYER_ORIGIN`** unchanged.
- **`game/presentation/tests/test_map_plane_projection.gd`** — asserts match new default
- **`docs/RENDERING.md`**, **`docs/PHASE_PLAN.md`**, **`docs/DECISION_LOG.md`**

Must not:

- **No** API change, **no** **`SelectionController`** / inverse / foot / billboard / **`HexLayout`** / domain / viewport / UV logic changes beyond **export default**.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1`
- Expected **49** scripts, all **PASS**, exit **0**

### Phase 4.5e — Projective map-plane perspective (implemented)

Goal:

- Replace **affine** **`MapPlaneProjection`** with **invertible** **projective** (**perspective divide**) so the map **recedes** toward the **viewport center**, not only **shear**.

Shipped:

- **`game/presentation/map_plane_projection.gd`** — **`w`**, **`scale = 1/w`**, **`vanishing_pres`**, **`depth_strength`**, **`near_world_y`**; **`shear_x_per_world_y`** **removed**; **closed-form** **`to_layout`**
- **`game/main.gd`** — **`projection.vanishing_pres = (get_viewport_rect().size * 0.5) - MAP_LAYER_ORIGIN`**
- **`game/presentation/tests/test_map_plane_projection.gd`**
- **`docs/RENDERING.md`**, **`docs/PHASE_PLAN.md`**, **`docs/DECISION_LOG.md`**, **`docs/VISUAL_DIRECTION.md`** (cross-ref)

Must not:

- **No** **`HexLayout`**, domain, viewport size, assets, marker ratios, foot ratio, **`Camera2D`**, **3D**, shaders, occlusion.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1`
- Expected **49** scripts, all **PASS**, exit **0**

### Phase 4.5f — Perspective tuning + hit-test usability + anchor polish (implemented)

Goal:

- **Softer** **4.5e** **depth**; **forgiving** **picks** aligned to **drawn** **hexes**; **foot** / **city** **anchor** polish.

Shipped:

- **`game/presentation/map_plane_projection.gd`** — **`depth_strength`** **`0.0010`**
- **`game/presentation/selection_controller.gd`** — **`projected_hex_contains`** (**`Geometry2D.is_point_in_polygon`**)
- **`game/presentation/units_view.gd`** — **`unit_icon_foot_offset_ratio`** **`0.24`**
- **`game/presentation/cities_view.gd`** — **`city_marker_center_y_offset_ratio`** **`0.05`**
- **`docs/RENDERING.md`**, **`docs/PHASE_PLAN.md`**, **`docs/DECISION_LOG.md`**, **`docs/SELECTION.md`**

Must not:

- **No** **affine** **revert**, **no** domain / **`HexLayout`** / viewport / assets.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1`
- Expected **49** scripts, all **PASS**, exit **0**

### Phase 4.5g — Civ6-like mild perspective + marker scale/centroid (implemented)

Goal:

- **Much** milder **projective** read (**almost** top-down, **subtle** recession); **less** tabletop **shear**; **perspective-matched** billboards. **Marker** centroid **anchoring** was **superseded** by **4.5h** (projected **layout** **hex** **center**).

Shipped:

- **`game/presentation/map_plane_projection.gd`** — **`depth_strength`** **`0.0004`**, **`plane_y_scale`** **`0.90`**; **`perspective_scale_at`** (**`projected_hex_centroid_pres`** added then **removed** in **4.5h**)
- **`game/presentation/units_view.gd`**, **`game/presentation/cities_view.gd`** — **`perspective_scale_at`** on **`icon_side`**; **4.5h** corrects **anchor** to **`to_presentation(hex_to_world)`**
- **`game/presentation/tests/test_map_plane_projection.gd`**
- **`docs/RENDERING.md`**, **`docs/PHASE_PLAN.md`**, **`docs/DECISION_LOG.md`**, **`docs/SELECTION.md`**

Must not:

- **No** domain / **`HexLayout.SIZE`** / **`MAP_LAYER_ORIGIN`** / viewport / **`project.godot`** / assets / **`Camera2D`**; **no** change to **polygon** picking math beyond **API** **survival**.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1`
- Expected **49** scripts, all **PASS**, exit **0**

### Phase 4.5h — Projected top-view hex center marker anchoring (implemented)

Goal:

- **Correct** marker **placement** under **projective** map: **`projection(layout hex center)`** ≠ **centroid** of **projected** hex **polygon**.

Shipped:

- **`game/presentation/units_view.gd`**, **`game/presentation/cities_view.gd`** — **`anchor_pres = projection.to_presentation(layout.hex_to_world(q, r))`**; **`perspective_scale_at(world_center)`** unchanged
- **`game/presentation/map_plane_projection.gd`** — **`projected_hex_centroid_pres`** **removed**
- **`docs/RENDERING.md`**, **`docs/PHASE_PLAN.md`**, **`docs/DECISION_LOG.md`**, **`docs/SELECTION.md`**

Must not:

- **No** change to **projection** **constants** / **formulas**, **polygon** **picking**, **terrain** **draw**, domain, **`HexLayout.SIZE`**, **`MAP_LAYER_ORIGIN`**, viewport, assets, **`Camera2D`**.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1`
- Expected **49** scripts, all **PASS**, exit **0**

### Phase 4.5i — Unit marker foot-pivot anchoring (implemented)

Goal:

- **Hex** **center** **in** **presentation** stays **`to_presentation(hex_to_world)`**; **textured** **unit** **sprite** **pivot** matches **painted** **feet** (**not** **rect** **bottom**).

Shipped:

- **`game/presentation/units_view.gd`** — **`unit_marker_pivot_x_ratio`**, **`unit_marker_pivot_y_ratio`**; **`Rect2(anchor_pres.x - side*pivot_x, anchor_pres.y - side*pivot_y, side, side)`**
- **`docs/RENDERING.md`**, **`docs/PHASE_PLAN.md`**, **`docs/DECISION_LOG.md`**, **`docs/SELECTION.md`**

Must not:

- **No** projection **constant**/**formula**/**`perspective_scale_at`** changes; **no** **polygon** picking / **terrain** / **city** placement / domain / assets / **`Camera2D`**.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1`
- Expected **49** scripts, all **PASS**, exit **0**

### Phase 4.5j — Per–type_id unit marker pivot overrides (implemented)

Goal:

- **Default** **`unit_marker_pivot_*`** **for** **most** **units**; **sparse** **overrides** **only** **for** **marker** **assets** **with** **different** **foot/contact** (**e.g.** **`settler`**).

Shipped:

- **`game/presentation/units_view.gd`** — **`_UNIT_MARKER_PIVOT_BY_TYPE`**, **`_resolved_marker_pivot(type_id)`**
- **`docs/RENDERING.md`**, **`docs/PHASE_PLAN.md`**, **`docs/DECISION_LOG.md`**, **`docs/SELECTION.md`**

Must not:

- **No** projection / **`perspective_scale_at`** / scaling / **city** / **terrain** / **picking** / domain / assets / **`Camera2D`**.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1`
- Expected **49** scripts, all **PASS**, exit **0**

### Phase 4.5k — Settler pivot override fine-tune (implemented)

Goal:

- **Lower** **settler** **marker** **slightly** (**`pivot_y`** **`0.88` → `0.86`**).

Shipped:

- **`game/presentation/units_view.gd`** — **`_UNIT_MARKER_PIVOT_BY_TYPE["settler"]`**
- **`docs/RENDERING.md`**, **`docs/PHASE_PLAN.md`**, **`docs/DECISION_LOG.md`**, **`docs/SELECTION.md`**

Must not:

- **No** changes **beyond** **settler** **pivot** **Y** **in** **code**; **no** projection / picking / **city** / domain.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1`
- Expected **49** scripts, all **PASS**, exit **0**

### Phase 4.5l — Larger prototype map + right-drag pan (implemented; pan mechanics superseded by **4.5m**)

Goal:

- **Wider** **play** **map** **for** **perspective** **testing**; **simple** **right-drag** **pan** **(no** **`Camera2D`**, **no** **zoom** **in** **this** **phase**).

Shipped:

- **`game/domain/hex_map.gd`** — **`make_prototype_play_map()`** (**R**=**5**, **91** **cells**)
- **`game/domain/scenario.gd`** — **`make_prototype_play_scenario()`**
- **`game/main.gd`** — **prototype** **scenario**; **historical:** **`_map_layer_pos`**, **screen-space** **`_input`** pan, **`vanishing_pres`** tied to **`_map_layer_pos`**
- **`docs/RENDERING.md`**, **`docs/PHASE_PLAN.md`**, **`docs/DECISION_LOG.md`**, **`docs/SELECTION.md`**

Must not:

- **No** **movement** / **rules** **changes**; **tests** **keep** **`make_tiny_test_*`**.

Validation (at **4.5l** ship):

- **`49`** **headless** **scripts** **PASS** (**before** **`test_map_camera.gd`**).

### Phase 4.5m — Plane-space pan (**MapCamera**; implemented)

Goal:

- **Replace** **4.5l** **screen-space** **layer** **translation** with **plane-space** **`camera_world_offset`** **before** **`MapPlaneProjection`**, so **pan** **re-projects** the **map** instead of **sliding** a **flat** **bitmap**-like **composite**.

Shipped:

- **`game/presentation/map_camera.gd`**, **`game/presentation/tests/test_map_camera.gd`**, **`scripts/run-godot-tests.ps1`** (**+1** **script**).
- **`game/main.gd`** — **`_map_camera`**, **constant** **layer** **positions**, **`_redraw_map_layers`**, **`_input`** **plane** **pan** **math**.
- **`game/presentation/map_view.gd`**, **`cities_view.gd`**, **`selection_view.gd`**, **`units_view.gd`**, **`terrain_foreground_view.gd`**, **`selection_controller.gd`** — **`var camera`**, **`MapCamera`** **fallbacks** in **`_draw`** / **pick**.
- **`docs/RENDERING.md`**, **`docs/PHASE_PLAN.md`**, **`docs/DECISION_LOG.md`**, **`docs/SELECTION.md`**

Must not:

- **No** **`MapPlaneProjection`** **formula** / **export** **edits**; **no** **`Camera2D`** / **domain** / **`main.tscn`** **order** **changes**.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1`
- Expected **50** scripts, all **PASS**, exit **0**

### Phase 4.5n — Center-anchored **MapCamera** zoom (**wheel**; implemented)

Goal:

- **Uniform** **layer-local** **zoom** **around** **`vanishing_pres`**, **Civ-like** **visible**-**center** **stability**, **no** **cursor**-**anchored** **zoom**.

Shipped:

- **`game/presentation/map_camera.gd`** — **`zoom`**, **`set_zoom_clamped`**, **`to_presentation` / `to_layout` / `perspective_scale_at`** **semantics**
- **`game/main.gd`** — **`ZOOM_STEP`**, **`InputEventMouseButton`** **wheel** in **`_input`**
- **`game/presentation/tests/test_map_camera.gd`** — **zoom** **invariants** (**no** **new** **runner** **scripts**)
- **`docs/RENDERING.md`**, **`docs/PHASE_PLAN.md`**, **`docs/DECISION_LOG.md`**, **`docs/SELECTION.md`**

Must not:

- **No** **per-view** **draw** **edits**; **no** **`MapPlaneProjection`** **math** **edits**; **no** **mouse-anchored** **zoom**; **no** **`Camera2D`** / **animation** / **inertia**

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1`
- Expected **50** scripts, all **PASS**, exit **0**

### Phase 4.6a — Terrain layering + forest visual model (design checkpoint; documentation only)

Goal:

- **Checkpoint** the **terrain layering** and **forest visual** model in **docs** after the **4.5l** presentation baseline — **no** implementation churn.

Shipped:

- **`docs/RENDERING.md`** — current **verified** map stack vs **intended** terrain-aware stack (**`TerrainForegroundView`** **planned** **between** **`UnitsView`** and **`SelectionController`**); **4.6b** boundary.
- **`docs/VISUAL_DIRECTION.md`** — **4.6** / **forest** direction (**painterly**, **clustered**, **readability**).
- **`docs/PHASE_PLAN.md`** — **this** **subsection**.
- **`docs/DECISION_LOG.md`** — **4.6a** entry.

Must not:

- **No** **`game/**`**, **assets**, **`project.godot`**, **tests**, **scenes**, **domain/content**, or **`Terrain.FOREST`** — **documentation** **only**.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1`
- Expected **49** scripts, all **PASS**, exit **0**

### Phase 4.6b — Visual-only prototype forest overlays on PLAINS (implemented)

Goal:

- **Presentation-only** prototype: **forest**-**styled** **clusters** on **`HexMap.Terrain.PLAINS`** hexes — **visual** **decoration** **only**; **not** **`Terrain.FOREST`**, **not** gameplay **forest**.

Shipped:

- **`game/presentation/plains_forest_decoration.gd`** — deterministic **PLAINS** decoration gate + **`cell_mix`** (shared by **MapView** and **`TerrainForegroundView`**).
- **`game/presentation/map_view.gd`** — **`forest_density_ratio`**; **back** canopy / stroke clumps after **4.1e** detail.
- **`game/presentation/terrain_foreground_view.gd`** — foreground bush clumps; **`forest_density_ratio`**, **`forest_front_opacity`**.
- **`game/main.tscn`**, **`game/main.gd`** — **`TerrainForegroundView`** after **`UnitsView`**, before **`SelectionController`**; pan / projection wiring.
- **`docs/RENDERING.md`**, **`docs/PHASE_PLAN.md`**, **`docs/DECISION_LOG.md`**, **`docs/VISUAL_DIRECTION.md`**

Must not:

- **No** **`HexMap.Terrain.FOREST`** / **`Terrain.FOREST`** **enum** value.
- **No** **movement** / **combat** / **vision** **terrain** **rules** tied to overlays.
- **No** **resources** or **economy** hooks from visuals.
- **No** **domain** / **content** / **scenario** changes **for** **forest** semantics.
- **No** **asset** **imports** in **4.6b** (procedural **only**); **later** rasters **must** follow **Phase** **4.3j** (true **RGBA** **PNG**, transparent background, scoped import/filtering, mipmaps where appropriate, provenance).
- **No** **changes** to **projection**, **right-drag** **panning**, or **projected** **polygon** **picking** unless a **separate** **phase** **explicitly** **scopes** that work.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1`
- Expected **49** scripts, all **PASS**, exit **0**

### Phase 4.6b-debug — Forest overlay readability (implemented)

Goal:

- **Prototype** forest marks **visible** in **editor** play; **foreground** uses the **same** **`MapPlaneProjection`** as **`MapView`** (**pan** / **`vanishing_pres`** aligned).

Shipped:

- **`game/main.gd`** — **`$TerrainForegroundView.projection = _map_projection`** (was missing).
- **`game/presentation/map_view.gd`** — **`forest_back_opacity`**; **higher-contrast** **back** clumps.
- **`game/presentation/terrain_foreground_view.gd`** — **higher-contrast** **foreground** clumps; optional **`forest_debug_log_counts_once`**.
- **`docs/RENDERING.md`**, **`docs/PHASE_PLAN.md`**, **`docs/DECISION_LOG.md`**

Must not:

- Same **bounds** as **4.6b** — **no** **domain/rules/enum/assets**; **no** edits to **`MapPlaneProjection`** **math** (only **shared instance** wiring).

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1`
- Expected **49** scripts, all **PASS**, exit **0**

### Phase 4.6b-polish — Forest silhouette read (implemented)

Goal:

- Forest **reads** as **fewer**, **larger** **layered** **clumps** (back **canopy** vs **front** **bush**), **less** **speckle**; **default** **`forest_density_ratio`** **0.25** **(was** **0.30**).

Shipped:

- **`game/presentation/map_view.gd`** — **2–3** **canopy** **clusters** / hex; **overlapping** **circles** + optional **quad** **silhouette**; no **thin** **line** **noise**.
- **`game/presentation/terrain_foreground_view.gd`** — **1–2** **chunky** **front** **masses** (circles + **triangle**); **`forest_front_opacity`** default **0.72**.
- **`docs/RENDERING.md`**, **`docs/PHASE_PLAN.md`**, **`docs/DECISION_LOG.md`**

Must not:

- Same **bounds** as **4.6b** / **4.6b-debug** (**presentation** **tuning** **only**).

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1`
- Expected **49** scripts, all **PASS**, exit **0**

### Phase 4.6c — Unit-aware foreground forest occluder (implemented)

Goal:

- **Visual-only** test: **forest** **foreground** **mass** **scaled**/ **placed** from **unit** **marker** **geometry** on **decorated** **PLAINS** (**no** **city** on hex), to validate **2.5D** **in-front-of-unit** read — **not** **`Terrain.FOREST`**, **not** **rules**.

Shipped:

- **`game/presentation/terrain_foreground_view.gd`** — **`scenario`**, **`_draw_unit_forest_occluder`**, exports **`unit_occluder_*`**, **`foreground_unit_reference_height_ratio`**.
- **`game/main.gd`** — **`scenario`** + height ratio wiring; **`terrain_foreground_view`** on **`SelectionController`**, **`EndTurnController`**, **`AITurnController`**.
- **`game/presentation/selection_controller.gd`**, **`end_turn_controller.gd`**, **`ai_turn_controller.gd`** — optional **`terrain_foreground_view`**; **redraw**/**scenario** sync (**picking** unchanged).
- **`docs/RENDERING.md`**, **`docs/PHASE_PLAN.md`**, **`docs/DECISION_LOG.md`**

Must not:

- **No** **domain** / **enum** / **rules** / **`MapPlaneProjection`** **math** / **UnitsView** **pivots** / **marker** **placement** changes.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1`
- Expected **49** scripts, all **PASS**, exit **0**

### Phase 4.6d — Terrain-owned foreground preserved when units occupy hex (implemented)

Goal:

- **Bug:** **Unit** on **decorated** hex **replaced** terrain **foreground** with **only** the **unit** occluder **path** → **bushes** **vanished**. **Fix:** **always** draw **`_draw_plains_forest_front`**; **`enable_unit_occlusion_test`** gates **additive** **`_draw_unit_forest_occluder`** only.

Shipped:

- **`game/presentation/terrain_foreground_view.gd`** — **`enable_unit_occlusion_test`**; draw-order **general** **then** **optional** **unit** overlay.
- **`docs/RENDERING.md`**, **`docs/PHASE_PLAN.md`**, **`docs/DECISION_LOG.md`**

Must not:

- **Presentation** **only**; **no** **domain** / **picking** / **projection** changes.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1`
- Expected **49** scripts, all **PASS**, exit **0**

### Phase 4.6e — Hex-owned forest foreground composition (implemented)

Goal:

- **Foreground** vegetation is **hex-owned** and **identical** with or without **units**; **sizes**/**positions** scale with **`perspective_scale_at`** and **anchor** at **`to_presentation(hex_to_world)`** (**foot-contact** **convention**). **Larger** muted **masses** overlap **feet**/ **lower** **legs** without anchoring to **texture** **bottom** or **extreme** **hex** **front**. **City** hexes: **skip** **main** **clump**, keep optional **secondary**.

Shipped:

- **`game/presentation/terrain_foreground_view.gd`** — **`_draw_plains_forest_front_hex_owned`**, **`_should_skip_main_clump_for_city`**, salts **4000–4099**, **`forest_front_opacity`** default **0.62**, **`enable_unit_occlusion_test`** default **false**.
- **`game/presentation/map_view.gd`** — **`forest_back_opacity`** default **0.85** only.
- **`docs/RENDERING.md`**, **`docs/PHASE_PLAN.md`**, **`docs/DECISION_LOG.md`**, **`docs/VISUAL_DIRECTION.md`**

Must not:

- **`game/domain/**`**, **`HexMap.Terrain`**, rules, **`MapCamera`** / **`MapPlaneProjection`** / picking, **`UnitsView`** / **`CitiesView`** markers, **`main.tscn`** order, new assets, **`project.godot`**.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1`
- Expected **50** scripts, all **PASS**, exit **0**

### Phase 4.6f — Forest foreground visibility calibration (implemented)

Goal:

- **Live** review: **4.6e** geometry was **hard** to **judge** because **foreground** was **too** **subtle** vs **terrain**. **Raise** default **`forest_front_opacity`** and **slightly** **raise** per-primitive **alpha** multipliers (**muted** palette **unchanged**) so **clump** **shape**, **placement**, and **overlap** with **feet**/ **legs** / **selection** / **cities** can be **evaluated**. **Final** art may **tune** **down** again or **replace** procedural **draw** with **assets**.

Shipped:

- **`game/presentation/terrain_foreground_view.gd`** — **`forest_front_opacity`** default **0.85**; per-primitive **alpha** band **wider** (**no** **geometry** / **salt** / **density** / **city**-**skip** changes).
- **`docs/RENDERING.md`**, **`docs/PHASE_PLAN.md`**, **`docs/DECISION_LOG.md`**

Must not:

- **`game/domain/**`**, rules, **`MapCamera`** / **projection** / **picking**, markers, **`forest_back_opacity`** (stay **0.85** unless **small** tweak **only** — **prefer** **unchanged**).

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1`
- Expected **50** scripts, all **PASS**, exit **0**

### Phase 4.6g — Forest raster overlay assets (implemented)

Goal:

- **Primary** **visual** for **decorated** **PLAINS** forest: **RGBA** **PNG** **clumps** in **`MapView`** (back) and **`TerrainForegroundView`** (front), **hex-owned** / **`pscale`**-aware like **4.6e**; **procedural** **retained** when **`use_forest_asset_overlays`** is **false** (**per-node** export; **toggle** **both** for **full** **fallback**). **No** **`Terrain.FOREST`**, **no** domain/rules/camera/picking/marker changes.

Shipped:

- **`game/assets/prototype/terrain/forest/*.png`** + **`.import`** (**`mipmaps/generate=true`**).
- **`game/presentation/map_view.gd`** — **`_draw_plains_forest_back_asset`**, **`forest_back_asset_opacity`**, **`use_forest_asset_overlays`**, **`TEXTURE_FILTER_LINEAR_WITH_MIPMAPS`**, salt **4100** for **01**/ **02**.
- **`game/presentation/terrain_foreground_view.gd`** — **`_draw_plains_forest_front_asset`**, **`forest_front_asset_opacity`**, **`use_forest_asset_overlays`**, salts **4110–4112**; **city** hexes **skip** **front** **raster** ( **procedural** **secondary** only ).
- **`docs/RENDERING.md`**, **`docs/PHASE_PLAN.md`**, **`docs/DECISION_LOG.md`**, **`docs/VISUAL_DIRECTION.md`**

Must not:

- **`game/domain/**`**, **`HexMap.Terrain`**, rules, **`MapCamera`** / **projection**, picking, **UnitsView** / **CitiesView** / **unit**/**city** **assets**, **`main.gd`** / **`main.tscn`**, **`project.godot`**.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1`
- Expected **50** scripts, all **PASS**, exit **0**

### Phase 4.5 — Camera / perspective / animation pass

Goal:
**Camera** UX, **perspective** experiments, **motion** principles (no gameplay truth hidden in tween-only client state). *(Direction: [VISUAL_DIRECTION.md](VISUAL_DIRECTION.md) — Camera / presentation direction for 4.5.)*

Validation:
Editor and checklist-driven; headless tests only for **pure** layout/formatting helpers if introduced.

## Phase 5 — Strategic dynamics

Phase 5 implementation work consumes the **RuleSet / EffectiveRules** model defined in **Phase 5.0a** (documentation checkpoint). Gameplay must treat **EffectiveRules** as the runtime content boundary once that layer is implemented; see [CONTENT_MODEL.md](CONTENT_MODEL.md) and [ARCHITECTURE_PRINCIPLES.md](ARCHITECTURE_PRINCIPLES.md).

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

### Phase 5.0a — RuleSet / EffectiveRules + playable embryo checkpoint (docs-only)

Goal:

- Define the **ancient-era playable embryo** direction and the **content/rules layer** it will consume.
- **Pause** further **visual polish** while the **gameplay embryo** direction is established.

Shipped:

- Documentation updates in the approved owner docs (**`ARCHITECTURE_PRINCIPLES`**, **`CONTENT_MODEL`**, **`PROGRESSION_MODEL`**, **`AI_DESIGN`**, **`CLOUD_PLAY`**, **`IMPLEMENTATION_GUIDE`**, **`VISUAL_DIRECTION`**, **`DECISION_LOG`**).
- New skeleton player-facing **`docs/player/PLAYTEST_GUIDE.md`**.

Must not:

- No **`game/**`** changes.
- No **`scripts/**`** changes.
- No registry implementation.
- No JSON / `.tres` / autoload content implementation.
- No action, **`GameState`**, **`ProductionTick`**, **`MovementRules`**, **`LegalActions`**, AI, presentation, scene, asset, **`project.godot`**, or **`.import`** changes.
- Do not enumerate concrete **RuleSet** schema fields or pin numeric balance values.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1`
- Exit **0**; observed headless **test script count** must match the **docs-only** baseline (unchanged runner list).

### Phase 5.1 — Ancient mini-game embryo

Goal:

- Grow the **first real gameplay loop** after Phase **2.x–4.x**: players experience civilization **emerging** through **cities**, **production progress**, and **knowledge / unlocks** that open **new** city options, on a **curated** baseline only (no generated worlds yet).

Features (roadmap / intent):

- **EffectiveRules** first read: gameplay consults a thin domain façade wrapping baseline registries before migrating additional reads.
- **Second city project** (producing a **settler**-class unit) reachable only after a **science completion** unlock path (conceptually tied to the existing **`controlled_fire`** row after **`found_city`** in **`ProgressDetector`**).
- Manual **`CompleteProgress`** application (**`KEY_H`**) remains valid in early slices; **auto-apply** of detector candidates is **deferred**.

Must not (roadmap):

- Generated worlds, RuleSet **generation** pipelines, or **LLM** content (**future** per **[Phase 5.0a](CONTENT_MODEL.md)**; **5.1** does not expand those concerns beyond existing steering).
- Full ancient era, combat, diplomacy, trade, civics, happiness, real economy, save/load implementation, or visual architecture churn.

Validation:

- Per subphase; first code slice after **5.1.0** introduces **one** read path through **EffectiveRules** with tests.

### Phase 5.1.0 — Embryo intent + content shortlist (docs-only)

Goal:

- Lock the **player-visible v0 loop intent**, **curated content shortlist** (documentation only), **EffectiveRules first-read pattern**, and explicit **deferrals** before any **5.1.x** code.
- **5.1.0** only documents the **planned** future v0 unlock target (including the working label **`produce_unit:settler`** as a **future** city project id in the **`CityProjectDefinitions`** id family). The **actual registry row**, validation wiring, and any **minted** canonical id in code ship in a **later** implementation slice.

Shipped:

- Documentation updates in **`PHASE_PLAN.md`** (this block), **`CORE_LOOP.md`**, **`CONTENT_MODEL.md`**, **`PROGRESSION_MODEL.md`**, **`CITIES.md`**, **`DECISION_LOG.md`** only.

Must not:

- **No** **`game/**`**, **`scripts/**`**, **`project.godot`**, **`.import`**, scenes, assets, tests, registries, actions, **`GameState`**, **`ProductionTick`**, **`MovementRules`**, **`LegalActions`**, AI, presentation changes.
- **Do not implement, register, validate, or add new canonical IDs in code in this slice.** It is **allowed** to document **`produce_unit:settler`** as the **planned** future v0 unlock target, but **no** registry row, schema change, action change, validator change, or implementation is allowed in **5.1.0**.
- **Do not expand** LLM, generator, save/load, cloud, or networking concerns **beyond references already established in Phase 5.0a**. **5.1.0** stays focused on the **curated** Ancient mini-game embryo and must **not design or implement** those future systems.
- **Do not** edit **`docs/player/**`**, **`.cursor/**`**, or any doc **outside** the six files listed for **5.1.0**.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1`
- Exit **0**; observed headless **test script count** must match the **Phase 5.0a** **docs-only** baseline (unchanged runner list).

### Phase 5.1.1 — EffectiveRules façade + one read path (LegalActions)

Goal:

- Introduce a minimal domain **`EffectiveRules`** façade (**`RefCounted`**, **no** autoload) and route **exactly one** existing gameplay read through it: whether the enumerated **`SetCityProduction`** warrior **`project_id`** is supported before **`LegalActions`** builds that candidate. **Baseline** façade behavior must match **`CityProjectDefinitions`** today so default enumeration stays unchanged.

Shipped:

- **`game/domain/effective_rules.gd`** — **`with_baseline_registries()`**, **`is_city_project_supported(project_id)`**.
- **`game/domain/legal_actions.gd`** — optional second argument **`effective_rules`** (default resolves to baseline façade); warrior production enumeration gated on **`er.is_city_project_supported(...)`** before **`SetCityProduction.make`** / **`validate`** / progress unlock check.
- Headless tests **`test_effective_rules.gd`**, **`test_legal_actions_effective_rules.gd`**; runner lists **55** scripts.

Must not:

- **No** new canonical content rows, registry rows, or **`ProgressDefinitions`** changes.
- **No** **`GameState`** constructor or member changes; **no** schema, save/load, or cloud changes; **no** generated **`RuleSet`** support; **no** visuals; **no** **`docs/player/**` or **`.cursor/**`** edits.
- **Do not** expand **city project** registry rows, **LegalActions** enumeration, or steering in this slice beyond the warrior façade hook — deferred labels remain covered only by prior **5.1.0** documentation.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1`
- Exit **0**; log line **`All 55 headless tests passed.`**

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
