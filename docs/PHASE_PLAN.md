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

## Direction checkpoint — Cloud play, authority, and AI (documentation only)

**Purpose:** Lock **long-term** steering so later slices stay coherent. **No** new gameplay implementation phases; **no** networking or backend work implied by this checkpoint.

**Canonical document:** [CLOUD_PLAY_DIRECTION.md](CLOUD_PLAY_DIRECTION.md) — async-first cloud play, server-authoritative rules in cloud mode, **action / intention** submissions (not client-resolved outcomes), local–server **conceptual** parity of rules/actions, persistence direction (action log + snapshots; delta sync + snapshot recovery at a high level), and **labeled** roadmap stages (**v0**–**v4**) for async, live-feel updates, AI assignment, and optional LLM-assisted AI—**without** prescribing protocols, matchmaking, or technology choices here.

**Alignment:** [ARCHITECTURE_PRINCIPLES.md](ARCHITECTURE_PRINCIPLES.md) (deterministic-first, **EffectiveRules** direction, **no** special-case AI gameplay path), [CLOUD_PLAY.md](CLOUD_PLAY.md), [AI_DESIGN.md](AI_DESIGN.md). Implementation backlog remains in subsequent sections of this file; when cloud or sync work is added, it should cite **CLOUD_PLAY_DIRECTION.md** and avoid realtime-first assumptions unless a phase explicitly requires them.

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

- **[progress_detector.gd](../game/domain/progress_detector.gd)** — **`ProgressDetector.suggested_complete_progress_actions(game_state)`** returns **`Dictionary`** values shaped like **`CompleteProgress.make`**; **rule (Phase 5.1.8a):** when **`scenario.lightning_tree_hex`** is set, **`controlled_fire`** is proposed for each player who has **not** completed it and has an **accepted `move_unit`** whose **`to`** cell is **on or adjacent** to that hex; **`turn_state.players`** order; defensive **null** / **non-int** handling. **`lightning_tree_hex`** is **`null`** on most scenarios (e.g. **`make_tiny_test_scenario`**) so **no** candidate is proposed from this rule alone.
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

**Current-target note (2026-08):** The **Phase 4.x** slices below built the **current implemented presentation** — a 2D/2.5D projected map. They remain valid history and the running game still uses them. The **approved presentation target** is now **Godot 3D terrain** (see the milestone **Fixed-grid Godot 3D terrain parity** below and [TERRAIN_SURFACE_TARGET.md](TERRAIN_SURFACE_TARGET.md)); the 2D map presentation is no longer the end-state visual direction. Nothing in Phase 4.x is retroactively invalidated by this note.

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

### Phase 5.1.2 — Settler city project + controlled_fire unlock

Goal:

- Mint curated **`produce_unit:settler`** in **`CityProjectDefinitions`**, wire **`controlled_fire`** **`concrete_unlocks`** to **`city_project` / produce_unit:settler**, and enumerate **`[warrior, settler]`** in **`LegalActions`** through the existing **`EffectiveRules.is_city_project_supported`** and **`ProgressState.has_unlocked_target`** gates. **`GameState.try_apply`** already rejects locked **`SetCityProduction`** with **`project_not_unlocked`**; **do not** change that path or **`SetCityProduction.validate` / `apply`**.

Shipped:

- **`produce_unit:settler`** row; **`controlled_fire`** third **`concrete_unlocks`** entry; **`PROJECT_ID_PRODUCE_UNIT_SETTLER`** on **`SetCityProduction`**; **`LegalActions`** per-city ordered candidates; headless **`test_settler_unlock_flow.gd`**; runner **56** scripts.

Must not:

- **No** action **`schema_version`** bumps; **no** new player action types; **no** **`EffectiveRules`** API expansion; **no** auto-apply; **no** city panel/menu; **no** AI strategy change; **no** **`ProductionDelivery`** tests for settler; **no** generated worlds, save/load, cloud, or LLM work.
- **No** **`GameState`**, **`ProgressState`**, **`ProductionTick`**, **`ProductionDelivery`**, AI, or presentation code changes. **`ProgressUnlockResolver`** is exercised by data and existing behavior only — **no** structural code changes to the resolver in this slice (the existing **`concrete_unlocks`** row shape is already supported).
- **No** **`docs/player/**`** or **`.cursor/**`** edits.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1`
- Exit **0**; log line **`All 56 headless tests passed.`**

### Phase 5.1.3 — Settler production and delivery proof

Goal:

- Prove end-to-end through **`GameState.try_apply`** that **`produce_unit:settler`** ticks to ready via **`ProductionTick`**, delivers a **`settler`** unit via **`ProductionDelivery`** on a later **`EndTurn`**, and the delivered settler can **`MoveUnit`** then **`FoundCity`** without changing production engine code.

Shipped:

- **`game/domain/tests/test_settler_production_flow.gd`** (+ **`.uid`**); runner **57** scripts; **no production game code changes** (only new domain test file and docs).

Must not:

- **No** changes to **`game/domain/*.gd`** production scripts (root), **`game/domain/content/**`**, **`game/domain/actions/**`**, **`game/domain/legal_actions.gd`**, **`game/domain/production_tick.gd`**, **`game/domain/production_delivery.gd`**, **`game/domain/game_state.gd`**, **`game/ai/**`**, **`game/presentation/**`**, scenes, assets, **`project.godot`**, or **`.import`**.
- **No** new content rows; **no** schema bumps; **no** new action types; **no** **`EffectiveRules`** or **`LegalActions`** changes; **no** auto-apply; **no** UI / AI / save-load / cloud / LLM work.
- **No** **`docs/player/**`** or **`.cursor/**`** edits.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1`
- Exit **0**; log line **`All 57 headless tests passed.`**

### Phase 5.1.4 — Minimal city production panel

Goal:

- When the player selects a **city** (hex click after unit pass), show a small **HUD** with city id, **production status** from **`City.current_project`**, and **buttons** for each legal **`SetCityProduction`** the domain already enumerates for that city via **`LegalActions.for_current_player`**. **Clicks** apply **`GameState.try_apply`** (same pattern as **`SelectionController`**); **no** separate rules engine in UI. **`mouse_filter`** stops clicks from falling through to the map.

Shipped:

- **`game/presentation/city_production_panel.gd`** (+ **`.uid`**), **`SelectionState.city_id`**, **`SelectionController`** city hex pick (before unit pick) and **`city_production_panel.refresh()`** hook; **`HudCanvas`** **`CanvasLayer`** in **`main.tscn`** for viewport-anchored HUD; **`EndTurnController`** / **`AITurnController`** **`selection.clear_unit()`** on **`EndTurn`** accept; **shared city / own-unit hex:** repeated clicks alternate **city** then **current-player unit** (**`plan_shared_hex_pick`**); **`test_city_production_panel.gd`**, **`test_main_hud_city_panel.gd`**, **`test_selection_shared_hex_pick.gd`**, expanded **`test_selection_state.gd`**; runner **63** scripts; docs below.

Must not:

- **No** domain / content / action / schema / **`GameState`** / **`LegalActions`** / **`EffectiveRules`** behavior edits; **no** new actions; **no** clear-production control; **no** AI policy change; **no** auto-apply; **no** full city screen, economy, camera/terrain polish, save/load, cloud, or LLM.
- **No** **`docs/player/**`** or **`.cursor/**`** edits.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1`
- Exit **0**; log line **`All 63 headless tests passed.`**

### Phase 5.1.5 — City production panel visual polish

Goal:

- Improve **readability** and **prototype** presentation of **`CityProductionPanel`** without expanding scope (no city screen, no new mechanics, no domain/UI architecture churn).

Shipped:

- **`city_production_panel.gd`**: **`PanelContainer`** + inner **`VBox`**, **parchment** **`StyleBoxFlat`**, **separators**, structured labels, **Train …** buttons; copy for idle / producing / ready / empty actions; **[main.tscn](../game/main.tscn)** panel bounds tweak.

Must not:

- **No** domain / **LegalActions** / **EffectiveRules** / new **HUD** systems / assets / fonts.

Validation:

- Same runner count as **5.1.4**; **`test_city_production_panel*.gd`** assertions updated only for status text.

### Phase 5.1.6 — Unlock feedback cue (presentation-only)

Goal:

- When **`complete_progress`** grants a **`city_project` / `produce_unit:*`** unlock (e.g. **Train Settler** after **`controlled_fire`**), show a short player-facing cue in **`LogView`** without popups or domain changes.

Shipped:

- **[log_view.gd](../game/presentation/log_view.gd)**: **`format_entry`** for **`complete_progress`** — `"[<idx>] P<id> <Humanized progress> completed"` plus optional lines **`       Unlocked: Train <Suffix>`** (**exactly seven spaces** before **`Unlocked`**) for each **`unlocked_targets`** row with **`target_type` `city_project`** and **`target_id`** prefixed **`produce_unit:`**; other target types omitted in this slice. **[test_log_view.gd](../game/presentation/tests/test_log_view.gd)** assertions updated; runner count **unchanged** (**63**).

Must not:

- **No** **`game/domain/**`** edits; **no** new HUD; **no** registry reads for legality.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1` → **`All 63 headless tests passed.`**

### Phase 5.1.7 — Discovery unlock popup (presentation-only)

Goal:

- After **accepted** **`CompleteProgress`** when the new **log** entry would show at least one **`city_project` / `produce_unit:*`** line under **5.1.6** rules, present a **dismissible** **HUD** panel (**no** queue) with curated copy for **`controlled_fire`** and a generic fallback for other **`progress_id`** values that still list train unlocks.

Shipped:

- **[discovery_popup.gd](../game/presentation/discovery_popup.gd)** — **`PanelContainer`** on **`HudCanvas`**, **`compute_view_model(log_entry)`** takes an **untyped** argument (**`Variant`**) and returns **`visible: false`** when **`typeof(log_entry) != TYPE_DICTIONARY`**, when the dict is empty, when it is not a **`complete_progress`** entry, or when **no** qualifying train unlocks exist; otherwise **`maybe_show_for_log_index(index)`** reads **`game_state.log.get_entry(index)`** and applies the view model. **`OK`** hides the panel; **`MOUSE_FILTER_IGNORE` / `STOP`** mirrors **`CityProductionPanel`** visibility. **[main.tscn](../game/main.tscn)** + **[main.gd](../game/main.gd)** wiring; **`SelectionController`** calls **`maybe_show_for_log_index(int(result["index"]))`** after **accepted** **`KEY_G`** / **`KEY_H`** only. **[test_discovery_popup.gd](../game/presentation/tests/test_discovery_popup.gd)**, **[test_main_hud_discovery_popup.gd](../game/presentation/tests/test_main_hud_discovery_popup.gd)**; runner **65** scripts.

Must not:

- **No** **`game/domain/**`** edits; **no** **`LogView`** / **`CityProductionPanel`** / **`EndTurnController`** / **`AITurnController`** edits; **no** **`ProgressDefinitions`** / registry imports in this slice; **no** popup queue.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1` → **`All 65 headless tests passed.`**

### Phase 5.1.8a — Lightning-Scarred Tree observation gate (`controlled_fire` detector)

Goal:

- Replace **found_city-only** **`ProgressDetector`** gating with a **prototype map observation**: the **player** must first end a **legal `move_unit`** on the **Lightning-Scarred Tree** hex or an **adjacent** hex (deterministic optional landmark on **`make_prototype_play_scenario`** only). **No** weather, **no** random lightning, **no** resource / feature catalogue — a **single optional `Scenario.lightning_tree_hex`** (nullable).

Shipped:

- **[scenario.gd](../game/domain/scenario.gd)** — optional **`lightning_tree_hex`** (constructor **untyped** sixth parameter, **`null`** default); **`make_tiny_test_scenario`** keeps **`null`**; **`make_prototype_play_scenario`** sets **`(3, 0)`** (open **GRASSLAND**, **not** prototype forest-cluster decoration; Phase **5.1.8c**); field **preserved** through **every** **`ScenarioScript.new(...)`** rebuild (**`MoveUnit`**, **`FoundCity`**, **`SetCityProduction`**, **`ProductionTick`**, **`ProductionDelivery`**).
- **[progress_detector.gd](../game/domain/progress_detector.gd)** — proposes **`controlled_fire`** when **`lightning_tree_hex != null`**, player has **not** completed it, and the **accepted `move_unit` log** for that **`actor_id`** has **`to`** on or adjacent to the tree.
- **[test_lightning_tree_trigger.gd](../game/domain/tests/test_lightning_tree_trigger.gd)** + rewritten **`test_progress_detector`**, **`test_progress_candidate_filter`**; runner **66** scripts.

Must not:

- **No** presentation / **`main.tscn`** / **`HudCanvas`** in this slice; **no** **`try_apply`** shape change; **no** new action types; **no** **`ProgressDefinitions`** edits.

### Phase 5.1.8b — Lightning-Scarred Tree marker + Discovery HUD panel

Goal:

- Make the **5.1.8a** prototype landmark **visible** on the map and offer **Controlled Fire** completion through the HUD (not only **`KEY_H`**), using the existing **`CompleteProgress`** action and **`DiscoveryPopup`** flow.

Shipped:

- **[lightning_tree_view.gd](../game/presentation/lightning_tree_view.gd)** — **`Node2D`** draws **`scarred_tree_stump.png`** at **`scenario.lightning_tree_hex`** (reads **`game_state.scenario`** when wired); conservative **magenta** chroma + prototype fallbacks via **`Image.load`** (Phase **5.1.8c** adjusts scale / open-terrain placement — see **5.1.8c**).
- **[discovery_action_panel.gd](../game/presentation/discovery_action_panel.gd)** — **`PanelContainer`** under **`HudCanvas`**; **`compute_view_model(game_state)`** uses **`ProgressCandidateFilter.for_current_player`**; **Complete Discovery** calls **`try_apply`**; **`call_deferred("refresh")`** after accept; **`maybe_show_for_log_index`** on **`DiscoveryPopup`**.
- **[main.tscn](../game/main.tscn)** / **[main.gd](../game/main.gd)** — sibling order **MapView → … → TerrainForegroundView → LightningTreeView** (same **`z_index`** as **TFV** so the stump paints **above** forest); **`DiscoveryActionPanel`** top-left under **`HudCanvas`**; map redraw includes **`LightningTreeView`**.
- **[selection_controller.gd](../game/presentation/selection_controller.gd)** — **`discovery_action_panel`** refreshed in lockstep with **`city_production_panel`** via **`_refresh_discovery_action_panel`**.
- **[end_turn_controller.gd](../game/presentation/end_turn_controller.gd)** / **[ai_turn_controller.gd](../game/presentation/ai_turn_controller.gd)** — null-safe **`discovery_action_panel.refresh()`** next to city panel.
- Tests: **[test_lightning_tree_view_draw.gd](../game/presentation/tests/test_lightning_tree_view_draw.gd)**, **[test_discovery_action_panel.gd](../game/presentation/tests/test_discovery_action_panel.gd)**, **[test_discovery_action_panel_button_deferred.gd](../game/presentation/tests/test_discovery_action_panel_button_deferred.gd)**, **[test_main_hud_discovery_action_panel.gd](../game/presentation/tests/test_main_hud_discovery_action_panel.gd)**; **[test_main_tscn_map_layer_sibling_order.gd](../game/presentation/tests/test_main_tscn_map_layer_sibling_order.gd)** updated; baseline **+4** vs prior runner (see **5.1.8c** for current total).

Must not:

- **No** new actions, **no** **`try_apply`** / detector / progression-definition changes; **no** **`docs/player/**`** edits; **no** weather / resource / feature-registry fiction.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1` — after **5.1.8c** → **`All 71 headless tests passed.`**

### Phase 5.1.8c — Lightning tree open-terrain placement + stump scale

Goal:

- **Smaller** stump (**~half** prior screen height) and a prototype **`lightning_tree_hex`** on **visually open** **PLAINS/GRASSLAND** (**not** **prototype forest-cluster** overlay / **PROVENANCE** list cell), **not** adjacent to **starting units**.

Shipped:

- **[scenario.gd](../game/domain/scenario.gd)** — **`make_prototype_play_scenario`** **`lightning_tree_hex`** **`(3, 0)`**.
- **[lightning_tree_view.gd](../game/presentation/lightning_tree_view.gd)** — **`STUMP_HEIGHT_HEX_FRAC`** **0.50**.
- **[plains_forest_decoration.gd](../game/presentation/plains_forest_decoration.gd)** — **`is_prototype_foreground_forest_hex(q, r)`**.
- **[test_prototype_lightning_tree_hex.gd](../game/domain/tests/test_prototype_lightning_tree_hex.gd)** + updates to **`test_scenario`**, **`test_lightning_tree_trigger`**, **`test_lightning_tree_view_draw`**; runner **71** scripts.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1` → **`All 71 headless tests passed.`**

### Phase 5.1.9 — Single-target science loop (`controlled_fire` auto-complete)

Goal:

- **First real science accumulation loop** for **`controlled_fire`** only: per-owned-city yield on the owner’s **EndTurn**, optional one-time **Lightning-Scarred Tree** observation bonus on **accepted MoveUnit** (after the move log entry), **auto-completion** at threshold via **`ProgressUnlockResolver.complete_progress`**, engine log entries **`science_progress`** / **`science_completed`**, and a **`ScienceCompletedPopup`** driven only by **`ActionLog`**. **`DiscoveryActionPanel`** stays in the scene but **filters out** **`controlled_fire`** (reserved for future non-science discoveries).

Shipped:

- **[progress_state.gd](../game/domain/progress_state.gd)** — **`science_progress`**, **`science_observation_flags`** on owner rows; **`science_progress_for`**, **`with_science_progress_added`**, **`has_observation_bonus_granted`**, **`with_observation_bonus_granted`**; preserved across **`with_progress_id_completed`** / **`with_target_unlocked`**.
- **[science_tick.gd](../game/domain/science_tick.gd)** — **`ScienceTick`**: per-turn science from **`CityYields.science_for_player`** (**5.1.16c**); **`OBSERVATION_BONUS` = 4**; idempotent when **`has_completed_progress`**; **`apply_for_player`**, **`add_observation_bonus_if_eligible`**.
- **[game_state.gd](../game/domain/game_state.gd)** — after **MoveUnit** log append, observation bonus events; after **ProductionTick** on **EndTurn** and **before** **`turn_state.advance`**, science yield events.
- **[science_completed_popup.gd](../game/presentation/science_completed_popup.gd)** + **[main.tscn](../game/main.tscn)** / **[main.gd](../game/main.gd)** — **`ScienceCompletedPopup`** under **`HudCanvas`**; curated copy for **`controlled_fire`** only (**no** **`ProgressDefinitions`** import).
- **[discovery_action_panel.gd](../game/presentation/discovery_action_panel.gd)** — skips **`progress_id == controlled_fire`** candidates.
- **[selection_controller.gd](../game/presentation/selection_controller.gd)** / **[end_turn_controller.gd](../game/presentation/end_turn_controller.gd)** / **[ai_turn_controller.gd](../game/presentation/ai_turn_controller.gd)** — after accepted **`try_apply`**, scan new log slice for **`science_completed`** → **`maybe_show_for_log_index`**.
- Tests: **`test_progress_state_science_progress`**, **`test_science_tick`**, **`test_end_turn_science_flow`**, **`test_move_unit_science_observation_bonus`**, **`test_science_completed_popup`**, **`test_main_hud_science_completed_popup`**; updates **`test_end_turn_production_flow`**, **`test_discovery_action_panel*`**; runner **77** scripts.

Must not:

- **No** **`SelectScience`**, science tree UI, **`ProgressDefinitions`** schema changes, **`LegalActions`**, or **AI** changes; **no** **`docs/player/**`** edits.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1` → **`All 77 headless tests passed.`**

### Phase 5.1.10 — Lightning tree science bonus feedback (`science_bonus` + `DiscoveryPopup`)

Goal:

- When **`ScienceTick`** grants the **one-time** **Lightning-Scarred Tree** observation bonus toward **`controlled_fire`**, append an engine log row **`action_type: science_bonus`** (with **`bonus_id: lightning_scarred_tree`**, **`delta`**, **`total`**, **`cost`**) **before** the existing **`science_progress`** / **`science_completed`** rows from that grant. Show a **`DiscoveryPopup`** on first new **`science_bonus`** after accepted **`try_apply`**; if the same apply batch also introduces **`science_completed`**, show **`DiscoveryPopup`** first and chain **`ScienceCompletedPopup`** after **OK** (no overlapping modals).

Shipped:

- **[science_tick.gd](../game/domain/science_tick.gd)** — prepended **`science_bonus`** event only when the bonus is **actually applied** (**not** repeat visits; **not** when **`controlled_fire`** already completed).
- **[discovery_popup.gd](../game/presentation/discovery_popup.gd)** — **`compute_view_model`** branch for **`science_bonus`** + **`lightning_scarred_tree`**; **`practical_line`**; **`run_engine_popups_after_apply`** + log scan helpers; **`arm_science_completed_chain`** / **`OK`** handoff.
- **[selection_controller.gd](../game/presentation/selection_controller.gd)** / **[end_turn_controller.gd](../game/presentation/end_turn_controller.gd)** / **[ai_turn_controller.gd](../game/presentation/ai_turn_controller.gd)** / **[main.gd](../game/main.gd)** — wire **`discovery_popup`** for turn/AI controllers; post-apply **`run_engine_popups_after_apply`**.
- Tests: updates **`test_science_tick`**, **`test_move_unit_science_observation_bonus`**, **`test_discovery_popup`**; add **`test_discovery_popup_run_engine_popups`**; runner **78** scripts.

Must not:

- **No** new discovery action, **no** **`Complete Discovery`** for this path, **no** **`ProgressDefinitions`** / resolver changes, **no** **`docs/player/**`** edits.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1` → **`All 78 headless tests passed.`**

### Phase 5.1.11 — Unit nameplates / ownership banners

Goal:

- **Code-drawn** nameplates above each **unit marker**: **`UnitDefinitions`** **display_name** (or humanized **type_id**), **muted owner accent** (teal / burgundy + stable fallbacks), parchment-styled banner. **Presentation-only** — **no** input, **no** **`CanvasItem`** hit-test role; **`HudCanvas`** popups/panels remain above the map layer.

Shipped:

- **[unit_nameplate_view.gd](../game/presentation/unit_nameplate_view.gd)** — **`Node2D`**; **`scenario`**, **`layout`**, **`camera`**, **`units_view`** (marker-top alignment); **`_draw`** + static helpers for tests.
- **[main.tscn](../game/main.tscn)** / **[main.gd](../game/main.gd)** — sibling **after** **`LightningTreeView`**, **`z_index` 2**, **`MAP_LAYER_ORIGIN`**, **`_redraw_map_layers`**, wires **`SelectionController`** / **`EndTurnController`** / **`AITurnController`** to **`queue_redraw`** when scenario moves.
- Tests: **`test_unit_nameplate_view`**, update **`test_main_tscn_map_layer_sibling_order`**; runner **79** scripts.

Must not:

- **No** **`game/domain/**`** edits; **no** **`docs/player/**`** edits; **no** faction system.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1` → **`All 79 headless tests passed.`**

### Phase 5.1.12 — Ancient science tree (definitions, targeting, Settler baseline)

**5.1.12** splits **progression** work into four sub-slices so **`ProgressDefinitions`**, **`ProgressState`**, **`ScienceTick`**, and **Settler** defaults stay reviewable. See **[PROGRESSION_MODEL.md](PROGRESSION_MODEL.md)** Phase **5.1.12** for the **19-science** tree, **cost** / **prerequisites** contracts, **`ScienceAvailability`**, **`SetCurrentResearch`**, and **Controlled Fire** bundle correction.

#### 5.1.12a — Ancient science tree documentation checkpoint

**Status:** **Shipped** by this slice (**docs only**).

Goal:

- Record the **Ancient** **19-science** tree (columns, **costs** **6** / **10** / **14** / **18**, **prerequisites**, dependency rules) and the **model contracts** for **`ProgressDefinitions`** row extensions, **`ProgressState.current_research_id`**, planned **`ScienceAvailability`**, planned **`SetCurrentResearch`**, **`ScienceTick`** promotion, **`CompleteProgress`** **`prerequisites_not_met`**, and **5.1.12d** **Settler-baseline** repair — **no** code or registry edits.

Shipped:

- **[PROGRESSION_MODEL.md](PROGRESSION_MODEL.md)** — Phase **5.1.12** section (table + contracts).
- **[PHASE_PLAN.md](PHASE_PLAN.md)** — this block.
- **[DECISION_LOG.md](DECISION_LOG.md)** — **5.1.12a** decisions.
- Optional contract line in **[CONTENT_MODEL.md](CONTENT_MODEL.md)** — **`ProgressDefinitions`** row-shape note.

Must not:

- **No** edits under **`game/**`**, **`scripts/**`**, **`docs/player/**`**; **no** changes to **`docs/RENDERING.md`** or **`docs/CITIES.md`** for this slice.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1` → **exit 0**; **same** headless test count as before (**docs-only** — expect **no** new or removed tests).

#### 5.1.12b — ProgressDefinitions cost/prerequisites + ScienceAvailability

**Status:** **Shipped.**

Goal:

- **`ProgressDefinitions`**: **19** Ancient sciences with **`cost`** and **`prerequisites`**; **`cost(id)`**, **`prerequisites(id)`**, **`is_science(id)`**; **`ids()`** column order (**`available_for`** preserves it for auto-target; **`locked_for`** / **`completed_for`** alphabetical).
- **`ScienceAvailability`**: derived **`available_for`** / **`locked_for`** / **`completed_for`** / **`is_available`** (**no** stored availability on **`ProgressState`**).
- **`CompleteProgress.validate`**: **`prerequisites_not_met`** when a **science**’s prerequisites are not all completed (non-science rows unaffected if added later).
- **`ScienceTick`**: **`science_progress`** / **`science_bonus`** / **`science_completed`** **`cost`** from **`ProgressDefinitions.cost`**; **at 5.1.12b ship** the tick target remained **fixed** to **`controlled_fire`** (**5.1.12c** replaces that with explicit / auto routing).

Shipped:

- **[progress_definitions.gd](../game/domain/content/progress_definitions.gd)** — curated **19** rows + helpers.
- **[science_availability.gd](../game/domain/science_availability.gd)** — **`class_name ScienceAvailability`**.
- **[complete_progress.gd](../game/domain/actions/complete_progress.gd)** — prerequisite gate.
- **[science_tick.gd](../game/domain/science_tick.gd)** — dynamic **cost** lookup.
- Tests: **`test_progress_definitions.gd`**, **`test_science_availability.gd`**, updates **`test_science_tick`**, **`test_complete_progress`**, **`test_complete_progress_flow`**, **`test_move_unit_science_observation_bonus`**; runner **`scripts/run-godot-tests.ps1`** (+**1** script → **80** total).

Must not (this slice):

- **No** **`current_research_id`**, **`SetCurrentResearch`**, or **auto-target** (**5.1.12c**).
- **No** **Settler** baseline move off **`controlled_fire`** (**5.1.12d**).
- **No** **`LegalActions`**, **AI**, **EffectiveRules**, or tech-tree **UI**.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1` → **`All 80 headless tests passed.`**

#### 5.1.12c — current_research_id + SetCurrentResearch + ScienceTick auto-target

**Status:** **Shipped.**

Goal:

- **`ProgressState`**: **`current_research_id`** per owner (**`""`** = explicit unset / **auto-target**); **`current_research_for`**, **`with_current_research`**; all **`with_*`** mutators preserve it.
- **`SetCurrentResearch`**: player **`Dictionary`** action; **`GameState.try_apply`** + log **`set_current_research`**; validate **`unknown_science`**, **`not_a_science`**, **`already_completed`**, **`prerequisites_not_met`**; **`science_id` `""`** clears explicit target.
- **`ScienceTick.apply_for_player`**: resolve target = explicit id if **available**, else **first** **`ScienceAvailability.available_for`** (tree order); **`science_no_target`** when **none**; **`add_observation_bonus_if_eligible`** always **`controlled_fire`**.
- **No** overflow carry-over; **`SciencePanel`** (**5.1.13**) is presentation-only — **no** **5.1.12d** **Settler** move in **5.1.12c**.

Shipped:

- **[progress_state.gd](../game/domain/progress_state.gd)** — **`current_research_id`** + **`_inner_copy`** preservation.
- **[set_current_research.gd](../game/domain/actions/set_current_research.gd)** — **`class_definition SetCurrentResearch`**.
- **[game_state.gd](../game/domain/game_state.gd)** **`try_apply`** branch.
- **[science_tick.gd](../game/domain/science_tick.gd)** — **`LIGHTNING_BONUS_PROGRESS_ID`**, **`_resolve_tick_target`**, **`science_no_target`**.
- Tests: **`test_progress_state_current_research.gd`**, **`test_set_current_research.gd`**, **`test_science_tick.gd`** updates; runner **82** scripts.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1` → **`All 82 headless tests passed.`**

#### 5.1.12d — Settler baseline + Controlled Fire reward correction

**Status:** **Shipped.**

- Default **`ProgressState`** unlocks include **`city_project` / `produce_unit:settler`** from turn **1**; **`controlled_fire`** **`concrete_unlocks`** / **`systemic_effects`** use the hearth / camp / survival **metadata bundle** only (no **Settler**); **`ScienceCompletedPopup`** copy no longer references **Train Settler**.

Shipped:

- **[progress_state.gd](../game/domain/progress_state.gd)** — **`with_default_unlocks_for_players`** includes **`produce_unit:settler`**.
- **[progress_definitions.gd](../game/domain/content/progress_definitions.gd)** — **`controlled_fire`** reward rows.
- **[science_completed_popup.gd](../game/presentation/science_completed_popup.gd)** — curated **Controlled Fire** body / practical line; **visible** when **`science_completed`** has **no** **`city_project`** train rows.
- Tests: **`test_progress_state`**, **`test_settler_unlock_flow`**, **`test_settler_production_flow`**, **`test_progress_definitions`**, **`test_science_tick`**, **`test_end_turn_science_flow`**, **`test_legal_actions_progress_gating`**, **`test_game_state_progress_state`**, **`test_complete_progress_flow`**, **`test_city_production_panel`**, **`test_science_completed_popup`**, **`test_log_view`**, **`test_discovery_popup`**.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1` → **`All 82 headless tests passed.`**

#### 5.1.13 — Minimal science selection panel

**Status:** **Shipped.**

Goal:

- **`SciencePanel`** (**[science_panel.gd](../game/presentation/science_panel.gd)**): left **`HudCanvas`** panel — **current / effective** research (same resolution as **`ScienceTick`** for display), **progress / cost**, **available** science buttons; submits **`SetCurrentResearch`** only via **`GameState.try_apply`**.
- **`compute_view_model(game_state)`** for tests; **`ProgressDefinitions`** + **`ScienceAvailability`** read-only for **display** (popups remain log-driven without **`ProgressDefinitions`**).

Shipped:

- **`main.tscn`** / **`main.gd`** — **`HudCanvas/SciencePanel`**; refresh alongside **`CityProductionPanel`** / **`DiscoveryActionPanel`** via **`SelectionController`**, **`EndTurnController`**, **`AITurnController`**; **`DiscoveryActionPanel`** also **`call_deferred("refresh")`** on **`SciencePanel`** after accepted panel **Complete Discovery**.
- Tests: **`test_science_panel.gd`**, **`test_science_panel_button.gd`**, **`test_main_hud_science_panel.gd`**; runner **85** scripts.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1` → **`All 85 headless tests passed.`**

#### 5.1.14 — SciencePanel locked-science hints

**Status:** **Shipped.**

Goal:

- **`SciencePanel`** shows **`ScienceAvailability.locked_for`** as a compact **muted** list: each row is **`<Science Name> — Requires: …`** listing **only prerequisites not yet completed**, in **`ProgressDefinitions`** prerequisite order — **no** tech-tree graph, **no** queue, **no** scrolling.
- **`compute_view_model`** exposes **`locked_rows`** + **`locked_more_count`**; UI shows the first **`LOCKED_ROW_DISPLAY_MAX`** rows and **`+N more locked sciences`** when clipped.

Shipped:

- **[science_panel.gd](../game/presentation/science_panel.gd)** — locked section, view-model fields, label-only locked rows (**no** **`try_apply`**).
- Tests: **`test_science_panel.gd`**, **`test_science_panel_button.gd`**; runner still **85** scripts.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1` → **`All 85 headless tests passed.`**

#### 5.1.15 — City name banners

**Status:** **Shipped.**

Goal:

- **`City.city_name`** domain field set by **`FoundCity`** (**`Capital`** first per owner, then **`Settlement <n>`**); preserved across **`SetCityProduction`**, **`ProductionTick`**, **`ProductionDelivery`** rebuilds.
- **`CityNameplateView`** — parchment banner + **`UnitNameplateView`** owner strip palette; **`5.1.15b`** reorders [main.tscn](../game/main.tscn) so **unit** nameplates stack above city banners on shared hexes; **`CityProductionPanel`** title uses name when set.

Shipped:

- **[city.gd](../game/domain/city.gd)**, **[found_city.gd](../game/domain/actions/found_city.gd)**, **[set_city_production.gd](../game/domain/actions/set_city_production.gd)**, **[production_tick.gd](../game/domain/production_tick.gd)**, **[production_delivery.gd](../game/domain/production_delivery.gd)** — name threading.
- **[city_nameplate_view.gd](../game/presentation/city_nameplate_view.gd)**, **[main.tscn](../game/main.tscn)** / **[main.gd](../game/main.gd)** — wiring + redraw; **[city_production_panel.gd](../game/presentation/city_production_panel.gd)** — header; controllers sync **`city_nameplate_view`**.
- Tests: **`test_city.gd`**, **`test_found_city.gd`**, **`test_set_city_production.gd`**, **`test_city_production_panel.gd`**, **`test_city_nameplate_view.gd`**, **`test_main_tscn_map_layer_sibling_order.gd`**; runner **86** scripts.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1` → **`All 86 headless tests passed.`**

#### 5.1.15b — City/banner overlap polish

**Status:** **Shipped.**

Goal:

- City banners **closer** to markers, **larger** type; **unit** nameplates **above** city banners on shared hexes via **scene-tree order** (**`CityNameplateView`** before **`UnitNameplateView`**, same **`z_index`**).

Shipped:

- **[city_nameplate_view.gd](../game/presentation/city_nameplate_view.gd)** — gap + font; **[main.tscn](../game/main.tscn)** / **[main.gd](../game/main.gd)** — sibling order + redraw order; tests **`test_city_nameplate_view.gd`**, **`test_main_tscn_map_layer_sibling_order.gd`**.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1` → **`All 86 headless tests passed.`**

#### 5.1.15c — Shared city/unit hex readability (markers + banner)

**Status:** **Shipped.**

Goal:

- **Unit** markers paint **in front of** **city** markers on the **same** hex (depth-merge / marker pass). City banners **offset** when a **unit** occupies the city tile so the parchment does not cross the **unit** sprite; **unit** nameplates remain **top** among code-drawn banners (**`main.tscn`** order unchanged).

Shipped:

- **[terrain_foreground_view.gd](../game/presentation/terrain_foreground_view.gd)** — **`_fg_depth_merge_item_lt`** same-hex **city→unit** merge rule; **[city_nameplate_view.gd](../game/presentation/city_nameplate_view.gd)** — **`city_hex_has_units`**; **5.1.15e** — **`draw_city_banner_on_canvas_item`** in **TFV** for shared hex; tests **`test_tfv_depth_merge_city_unit_sort_keys.gd`** (microfloat case), **`test_city_nameplate_shared_hex_banner.gd`**; docs **`RENDERING.md`**, **`DECISION_LOG.md`**.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1` → **`All 87 headless tests passed.`**

#### 5.1.15d — Shared city/unit hex banner below marker (**superseded by 5.1.15e**)

**Status:** **Superseded** (layering fix replaces below-marker geometry).

Goal:

- When a **unit** shares the city hex, place the **city name banner below** the **city marker** (not a small **x/y** nudge) so it **clears** the **unit** PNG; **marker** order remains **city** then **unit** in **`TerrainForegroundView`**.

Shipped:

- **[city_nameplate_view.gd](../game/presentation/city_nameplate_view.gd)** — **`_marker_bottom_presentation_y`**, **`CITY_BANNER_SHARED_UNIT_BELOW_GAP_PX`**, **`compute_city_banner_rect(..., marker_bottom_y)`**, default-off **`debug_log_shared_hex_banner`**; **[terrain_foreground_view.gd](../game/presentation/terrain_foreground_view.gd)** — **`debug_log_shared_hex_marker_order`**; tests **`test_city_nameplate_shared_hex_banner.gd`**, **`test_city_nameplate_shared_hex_runtime_clearance.gd`**; docs.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1` → **`All 88 headless tests passed.`**

#### 5.1.15e — Shared city/unit hex: normal banner position + TFV layering

**Status:** **Shipped.**

Goal:

- Keep the city banner **near** the **normal above-marker** position when a **unit** shares the hex (**no** large downward offset). **Draw order:** terrain foreground context → **city marker** → **city banner** → **unit** marker → **`UnitNameplateView`** on top.

Shipped:

- **[city_nameplate_view.gd](../game/presentation/city_nameplate_view.gd)** — unified **`compute_city_banner_rect`**, **`terrain_foreground_view`**, **`draw_city_banner_on_canvas_item`**, **`compute_all_city_banner_rects(..., omit_cities_with_units_on_hex)`**; **[terrain_foreground_view.gd](../game/presentation/terrain_foreground_view.gd)** — shared-hex banner in depth-merge + pass 2; **`debug_log_shared_hex_layer_order`**; **[main.gd](../game/main.gd)** — wires **`CityNameplateView.terrain_foreground_view`**; tests **`test_city_nameplate_shared_hex_banner.gd`**, **`test_city_nameplate_shared_hex_runtime_clearance.gd`**; docs **`RENDERING.md`**, **`DECISION_LOG.md`**.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1` → **`All 88 headless tests passed.`**

#### 5.1.16c — City economy foundation (domain): woods overlay, **CityYields**, capital **Palace**

**Status:** **Shipped.**

Goal:

- Move prototype **woods** hex keys into **domain** (**`PrototypeTerrainFeatures`**, **`HexMap.has_woods`**, **`make_prototype_play_map`**); presentation forest decoration **re-exports** the same list.
- Introduce **`CityYields`** (domain-only): terrain / city-center / **Palace** vectors; summed **science** per player for **`ScienceTick`** (replaces flat **`PER_CITY_YIELD`**).
- **`City`**: **`is_capital`**, **`building_ids`**; **`FoundCity`** gives first city per owner **capital** + **`["palace"]`**; **`ProductionTick`**, **`ProductionDelivery`**, **`SetCityProduction`** preserve these fields on rebuilds.

Shipped:

- **[prototype_terrain_features.gd](../game/domain/prototype_terrain_features.gd)**, **[city_yields.gd](../game/domain/city_yields.gd)**; **[hex_map.gd](../game/domain/hex_map.gd)**, **[city.gd](../game/domain/city.gd)**, **[found_city.gd](../game/domain/actions/found_city.gd)**, **[science_tick.gd](../game/domain/science_tick.gd)**, **[production_tick.gd](../game/domain/production_tick.gd)**, **[production_delivery.gd](../game/domain/production_delivery.gd)**, **[set_city_production.gd](../game/domain/actions/set_city_production.gd)**; **[plains_forest_decoration.gd](../game/presentation/plains_forest_decoration.gd)** — domain alias; tests **`test_hex_map_woods.gd`**, **`test_city_yields.gd`**, **`test_prototype_woods_presentation_domain_agreement.gd`** + updates; docs **[CITIES.md](CITIES.md)**, **[PROGRESSION_MODEL.md](PROGRESSION_MODEL.md)**, **[DECISION_LOG.md](DECISION_LOG.md)**.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1` → **`All 91 headless tests passed.`** (prior baseline **88** + **3** new scripts.)

#### 5.1.16d — **ProductionTick** reads **`CityYields`** **production**

**Status:** **Shipped.**

Goal:

- Replace the fixed **+1** **`produce_unit`** **`progress`** step with **`CityYields.city_total_yield(scenario, city)["production"]`** (**Palace** still **no** **production**). **Founding** terrain / **woods** / **center** rules affect **production** pacing; **zero** **production** skips advancement without error.

Shipped:

- **[production_tick.gd](../game/domain/production_tick.gd)** — **`_production_per_turn`**; **`CityYields`** preload; **`PRODUCTION_PER_TURN`** removed (deprecated comment only). Tests **`test_production_tick`**, **`test_production_delivery`**, **`test_end_turn_production_flow`**, **`test_city_yields`** updates; docs **[CITIES.md](CITIES.md)**, **[PHASE_PLAN.md](PHASE_PLAN.md)**, **[DECISION_LOG.md](DECISION_LOG.md)**, **[PROGRESSION_MODEL.md](PROGRESSION_MODEL.md)**.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1` → **`All 91 headless tests passed.`**

#### 5.1.16e — **CityProductionPanel** shows **CityYields** summary

**Status:** **Shipped.**

Goal:

- Surface domain **`CityYields.city_total_yield`** in **`CityProductionPanel`** (**Food**, **Production**, **Science**, **Coin**) so **5.1.16c–d** economy is visible; **no** terrain duplication in the panel; **no** domain edits.

Shipped:

- **[city_production_panel.gd](../game/presentation/city_production_panel.gd)** — **`compute_view_model`** keys **`show_yields`**, **`yields`**, **`yields_line`**; yields **`Label`** in **`refresh()`**; tests **`test_city_production_panel.gd`**; docs **[RENDERING.md](RENDERING.md)**, **[CITIES.md](CITIES.md)**, **[DECISION_LOG.md](DECISION_LOG.md)**.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1` → **`All 91 headless tests passed.`**

#### 5.1.16f — **TileYieldOverlayView**: map-anchored **CityYields** icons + **Yields** HUD toggle

**Status:** **Shipped.**

Goal:

- **Prototype** map overlay: stable-order **food** / **production** / **science** / **coin** icons per hex, **map-anchored** (**`MapCamera`** / **`HexLayout`**) so pan/zoom track the grid; **city** hexes use **`CityYields.city_total_yield`**; **non-city** land uses **`CityYields.raw_terrain_yield`**; **no** domain edits; **no** new resource system. **Readability polish:** **`YIELD_ICON_*`** constants (~**2×** first-pass icon size; **`compute_icon_metrics` only**). **Scaling polish:** same **`CanvasItem`** filter + **mipmapped** imports as **unit/city** markers.

Shipped:

- **[tile_yield_overlay_view.gd](../game/presentation/tile_yield_overlay_view.gd)** (polish: **`YIELD_ICON_*`** size + **`TEXTURE_FILTER_LINEAR_WITH_MIPMAPS`** / mipmapped **`yield_icons`** like **`map_markers/`**), **[yield_overlay_toggle.gd](../game/presentation/yield_overlay_toggle.gd)**; **[main.tscn](../game/main.tscn)** (**`TileYieldOverlayView`** sibling **`z_index` 1** **after** **`LightningTreeView`**; **`CityTerritoryView`** **`z_index` 0** **after** **`MapView`** — **below** foreground / **yields**); **`HudCanvas`** **`YieldsToggle`** **CheckButton**; **`KEY_Y`** + button stay synced via **`YieldOverlayToggle`**; **`SelectionController`** / **`EndTurnController`** / **`AITurnController`** redraw + **`scenario`** refresh; tests **`test_tile_yield_overlay_view.gd`**, **`test_main_hud_yields_toggle.gd`**, **`test_main_tscn_map_layer_sibling_order`** update; docs **[RENDERING.md](RENDERING.md)**, **[CITIES.md](CITIES.md)**, **[DECISION_LOG.md](DECISION_LOG.md)**.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1` → **`All 93 headless tests passed.`** (overlay icon sizing assertions live in **`test_tile_yield_overlay_view`**.)

#### 5.1.16g — City territory foundation (`City.owned_tiles`)

**Status:** **Shipped.**

Goal:

- Domain-only **city territory**: **`City.owned_tiles`** (**center +** valid **radius-1** map hexes on **`FoundCity`**, including **water**); **no** duplicate tile ownership; **`FoundCity`** rejects **`tile_already_owned`**; **`Scenario`** query helpers + construction asserts; preserve **`owned_tiles`** on **`ProductionTick`** / **`ProductionDelivery`** / **`SetCityProduction`** rebuilds.
- **No** change to **`CityYields.city_total_yield`**, **`ProductionTick`** yield math, **`ScienceTick`**, **`TileYieldOverlayView`**, or **`CityProductionPanel`** yield display (**owned** ring hexes do **not** add yields until **5.1.16h**).

Shipped:

- **[city.gd](../game/domain/city.gd)** — **`owned_tiles`**, constructor semantics; **[scenario.gd](../game/domain/scenario.gd)** — **`tile_owner_city_id`**, **`city_owning_tile`**, **`tile_is_owned`**, **`tiles_owned_by_city`**, ownership invariants; **[found_city.gd](../game/domain/actions/found_city.gd)** — initial claim + validation; **[production_tick.gd](../game/domain/production_tick.gd)**, **[production_delivery.gd](../game/domain/production_delivery.gd)**, **[set_city_production.gd](../game/domain/actions/set_city_production.gd)** — pass-through; tests **`test_city`**, **`test_scenario_city_territory`**, **`test_found_city`**, **`test_city_yields`** (regression), rebuild tests; docs **[CITIES.md](CITIES.md)**, **[DECISION_LOG.md](DECISION_LOG.md)**, **[PHASE_PLAN.md](PHASE_PLAN.md)** (this section), **[PROGRESSION_MODEL.md](PROGRESSION_MODEL.md)**, **[CONTENT_MODEL.md](CONTENT_MODEL.md)**.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1` → **`All 94 headless tests passed.`**

#### 5.1.16g.2 — Ancient prototype map **correction** (g.1 lineage + extensions + full island read)

**Status:** **Shipped (rework).**

Goal:

- **Redo** the rejected **macro-banana / sector-paint** pass: preserve **5.1.16g.1** **identity** (strait + bays + curated feel), **~1.5–2×** **playable** land, clear **NE / up-right** **tongue**, **full** **WATER** **halo** (no “open” **perimeter** gaps), **grass-forward** **mix** with **small** **plains** / **hill** **pockets**, **distributed** **woods** clusters — **still** **no** **worldgen** / **no** **CityYields** or economy pacing edits; **`make_tiny_test_map()`** unchanged.

Shipped:

- **[hex_map.gd](../game/domain/hex_map.gd)** — **`_proto_g1_core_candidates`** (R=**6** shell + thinning) **+** **`_proto_island_extension_hexes()`** **+** layered **terrain** paints **+** **`_proto_add_full_water_ring`**; **`prototype_terrain_features.gd`** **woods** retuned; **[forest_debug_clusters.gd](../game/presentation/forest_debug_clusters.gd)** coords aligned with **PLAINS** **debug** strips; **`test_prototype_play_map_distribution.gd`** **island-closure**, **grass-vs-plains**, **woods** **anti-blob** checks; **`test_city_production_panel.gd`** non-capital grass fixture moved to **`(-1,4)`** (avoids **PLAINS** **(2,0)** pocket).

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1` → **`All 94 headless tests passed.`**

**Follow-up polish (same phase, shipped):** second pass on **`PROTOTYPE_WOODS_HEXES`** + **`_proto_paint_land_terrain()`** only — **fragment** forest decoration into **smaller** connected components (cap **~9** hexes / component in tests), add **grass-break** **plains** / **hill** **speckles**; **`test_prototype_forest_clusters.gd`** now asserts **structural** mix (**no** mandatory **10+** hex **carpet**). **Island** silhouette, **scenario** starts, rules **unchanged**.

#### 5.1.16g.1 — Curated **Ancient** prototype play map (hand-authored island fixture)

**Status:** **Shipped.**

**Note:** **Island footprint** / **scenario** **starts** here were **superseded** by **5.1.16g.2** (**corrected** **g.1+extensions** island; **P1** **`(9,5)`**). Kept as **history** for the first curated replacement of the **formula** disk.

Goal:

- Replace the legacy **visual-review** axial disk with a **deterministic**, **playtest-dense** **island / micro-continent** map: **irregular** **water** halo, **grass / plains / hills / prototype woods** placement, **4–6** plausible **city** anchors, **P0 / P1** starts that avoid **immediate** **territory** blocking, **without** changing **CityYields**, **ProductionTick**, **ScienceTick**, **TileYieldOverlayView**, **CityProductionPanel**, **movement**, **AI**, **`make_tiny_test_map()`**, or **terrain** enum scope.

Shipped:

- **[hex_map.gd](../game/domain/hex_map.gd)** — **`make_prototype_play_map()`** curated land mask + paints + water ring (see **[MAP_MODEL.md](MAP_MODEL.md)**).
- **[prototype_terrain_features.gd](../game/domain/prototype_terrain_features.gd)** — **`PROTOTYPE_WOODS_HEXES`** re-listed for **on-map PLAINS** cells only (incl. **peninsula** isolates for cluster-shape tests).
- **[scenario.gd](../game/domain/scenario.gd)** — **`make_prototype_play_scenario()`** **P1** **settler** at **`(-3,4)`**; **`lightning_tree_hex`** **`(3,0)`** (open **GRASSLAND**, no woods).
- **[forest_debug_clusters.gd](../game/presentation/forest_debug_clusters.gd)** — debug cluster coords on the new fixture.
- Tests: **[test_prototype_play_map_distribution.gd](../game/domain/tests/test_prototype_play_map_distribution.gd)** (structural coast / woods / founding / overlay / tree assertions), hill-city / forest-cluster / lightning / production panel anchors; docs **MAP_MODEL**, **RENDERING**, **DECISION_LOG**, optional **CITIES** note.

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1` → **`All 94 headless tests passed.`**

#### 5.1.16i — **CityTerritoryView**: selected-city territory outline (presentation)

**Status:** **Shipped**; **2026-05-14** — **axial** **half-edge** **loops** traced in **layout** space, drawn as **closed** **`Line2D`** (**continuous** joins; **no** default **joint** **dots**); **`MapCamera`** affects **projected** **points** + **width** only.

Goal:

- **Presentation-only** visualization when a **city** is **selected**: **owner-colored** **outer** perimeter from **`Scenario.tiles_owned_by_city`** (**water** included); **map-anchored**; **below** units, cities, **TerrainForegroundView** / **LightningTreeView**, **`TileYieldOverlayView`**, and nameplates; **no** domain edits; **no** all-cities **always-on** mode.

Shipped:

- **[city_territory_view.gd](../game/presentation/city_territory_view.gd)** — **Perimeter** **half-edges** from **axial** **adjacency**; **closed** **loops** by **corner-key** **walk** (**no** **screen** **sort**); **closed** **`Line2D`** **outer** (**owner**) + **`Line2D`** **inner** (**indigo**, **inward-averaged** **corners**); **optional** **debug** **`draw_circle`** caps only; **`MapCamera`** → projection + thickness **only**; **[main.tscn](../game/main.tscn)** / **[main.gd](../game/main.gd)** — **`CityTerritoryView`** after **`MapView`**, **`z_index` 0**; **`SelectionController`** / **`EndTurnController`** / **`AITurnController`** unchanged in intent; tests **`test_city_territory_view.gd`**, **`test_city_territory_main_wiring.gd`**, **`test_main_tscn_map_layer_sibling_order.gd`**; docs **RENDERING**, **CITIES**, **DECISION_LOG**, **PHASE_PLAN**.

**Follow-up (2026-05-14):** Early **presentation-space** loop assembly caused **zoom/pan** artifacts — **superseded**. **Vertex** **join** **disks** **superseded** by **hex-traced** **`Line2D`** **loops** (**DECISION_LOG**).

Validation:

- `powershell -ExecutionPolicy Bypass -File .\scripts\run-godot-tests.ps1` → all headless tests pass (count in script output).

#### 5.1.17a — Population + deterministic auto-worked tiles (domain embryo)

**Status:** **Shipped.**

- **`City.population`** (**`FoundCity`** sets **`1`**; preserved on **`SetCityProduction`** / **`ProductionTick`** / **`ProductionDelivery`** rebuilds). **Phase 5.1.19b** (**`FoodGrowthTick`**) may increase **`population`** when **`food_stored`** crosses **`growth_threshold(pop)`**.
- **`CityYields`**: **`worked_tiles_for_city`** / **`worked_tiles_yield`**; **`city_total_yield`** = center + buildings + worked **raw terrain** from **non-center** **`owned_tiles`** (deterministic ordering; capped by **`population`**). Through **5.1.17a** assignments were **not** stored on **`City`** (**5.1.18a** adds **`manual_worked_tiles`**).
- **No** manual assignment UI through **5.1.17a** (**5.1.18a**: PLANNING click embryo).

Docs/tests: **[CITIES.md](CITIES.md)**, **`test_city_population.gd`**, **`test_city_yields_worked_tiles.gd`**, **`scripts/run-godot-tests.ps1`** registration.

#### 5.1.18a — Manual worked-tile assignment embryo (`set_city_worked_tiles`)

**Status:** **Shipped.**

- **`City.manual_worked_tiles`**: **`Array`** of **`HexCoord`** (constructor-normalized: owned, non-center, deduped **`q,r`**). **`City.worked_tiles_mode`**: **`auto`** (default, **`FoundCity`**) vs **`manual`** (after any accepted **`SetCityWorkedTiles`**). **`CityYields.worked_tiles_for_city`**: **`auto`** → deterministic fill up to **`population`** (ignores **`manual_worked_tiles`**); **`manual`** → only valid **`manual_worked_tiles`**, **no** auto-fill; **`[]`** → no worked-tile raw yield.
- Domain action **`set_city_worked_tiles`** (**`SetCityWorkedTiles`**, schema **1**): payload **`tiles: [[q,r], ...]`**; applying always sets **`worked_tiles_mode`** to **`manual`**; **`[]`** means idle citizens (**not** revert **`auto`** in this slice).
- **`LegalActions.for_current_player`**: v0 deterministic enumeration per current-player city — one action per eligible owned non-center tile (nonzero raw terrain yield, **`q`** asc then **`r`** asc), plus **`tiles: []`** when **`worked_tiles_mode`** is **`manual`** and **`manual_worked_tiles`** is non-empty.
- **Presentation:** **`SelectionController`** — only in **PLANNING**; **`SelectionController.planning_manual_worked_tiles_payload`** ( **5.1.19d** ): click owned non-center tile with nonzero raw yield **or** already manual — **toggle** (remove in place), **append** (when **`manual_worked_tiles.size() < population`**), or **replace last** manual slot (when at capacity); submits **`set_city_worked_tiles`** via **`try_apply`**; **`[]`** all idle (**manual** mode). Refreshes **`city_worked_tiles_view`**, **`city_production_panel`**, **`TurnViewSync`** views (yield overlay), **`log_view`**. **No** new marker assets, drag/drop, or territory border work.

**Out of scope:** specialists, inter-city tile swaps, save/load schema, starvation / **settler pop cost** / housing beyond **5.1.19b**'s minimal **FoodGrowthTick**.

Docs/tests: **[ACTIONS.md](ACTIONS.md)**, **[CITIES.md](CITIES.md)**, **[CURRENT_ARCHITECTURE.md](CURRENT_ARCHITECTURE.md)**, **`test_set_city_worked_tiles.gd`**, **`test_city.gd`**, **`test_city_yields_worked_tiles.gd`**, **`test_legal_actions.gd`**, **`test_production_tick.gd`**, **`test_city_worked_tiles_view.gd`**.

#### 5.1.19a — City growth pacing analysis (planning)

**Status:** **Shipped (analysis / planning record).**

- Prototype-capital pacing and **manual vs auto** worked-tile food tradeoffs reviewed toward a minimal **food → stockpile → population** loop.
- **No code deliverable** in **5.1.19a**; implementation deferred to **5.1.19b** (**FoodGrowthTick** + **`City.food_stored`**).

#### 5.1.19b — Food growth embryo (`FoodGrowthTick` + hub growth line)

**Status:** **Shipped.**

- **`City.food_stored`** (`int`, default **`0`**, clamped **`>= 0`**) — threaded through **`FoundCity`** (**`0`**), **`SetCityProduction`**, **`SetCityWorkedTiles`**, **`ProductionTick`**, **`ProductionDelivery`** rebuilds.
- **`FoodGrowthTick`** ([food_growth_tick.gd](../game/domain/food_growth_tick.gd)): on accepted **`end_turn`**, per ending player, after **`ProductionTick`**, before **`ScienceTick`** / **`EndTurn.apply`** — **`surplus = city_total_yield.food − population×2`**; if **`surplus > 0`**, bank into **`food_stored`**; at **`growth_threshold(pop)`**, **`population += 1`** and subtract threshold (carry remainder). **`surplus ≤ 0`**: no drain, no starvation, no events (v0).
- **`CityProductionPanel`**: read-only **`growth_line`** for the current player’s selected city (**`Growth: stored / threshold (+N/turn)`**, **`N` clamped to `0`** when surplus **≤ 0**).
- Tests: **`test_food_growth_tick.gd`**, **`test_end_turn_growth_flow.gd`**, updates to **`test_city.gd`**, **`test_city_production_panel.gd`**; **`scripts/run-godot-tests.ps1`** registration.
- Docs: **`CITIES.md`**, **`CURRENT_ARCHITECTURE.md`**, this plan.

**Still out of scope:** starvation, **settler** population cost, housing, tile ownership swaps, save/load for **`food_stored`**.

#### 5.1.19c — Growth / play loop smoke (validation slice)

**Status:** **Shipped.**

- **Scope:** narrow **smoke / validation** only — **no** balance edits, **no** new rules, **no** map or registry changes.
- Headless **`test_growth_play_loop_smoke.gd`**: **`Scenario.make_prototype_play_scenario`**, **`GameState.try_apply`** only (found capital → warrior → settler → second **`FoundCity`** → growth milestones + **manual worked-tile** probe). Asserts **EndTurn** log pipeline order on this fixture (production → food growth → end_turn → delivery where present), monotonic log growth, **capital** **`population >= 2`** with **`city_grew`**, second city **`food_growth_progress`** with **`surplus >= 1`**, **P0** owns two cities.
- Manual checklist: **[VALIDATION_CHECKLIST.md](VALIDATION_CHECKLIST.md)** (**Phase 5.1.19c** section).
- Runner: **`scripts/run-godot-tests.ps1`** includes the new test.

#### 5.1.19d — Multi-manual PLANNING clicks (`manual_worked_tiles` up to **population**)

**Status:** **Shipped.**

- **`SelectionController.planning_manual_worked_tiles_payload`**: in **PLANNING** with a **current-player** city selected, **`set_city_worked_tiles`** payloads preserve manual **list order** — **remove** clicked tile if present (in place); else **append** when **`manual_worked_tiles.size() < population`**; else **replace the last** manual entry with the clicked tile (deterministic one-click reassignment at cap). Assigning a **new** tile still requires **nonzero** raw terrain yield (**existing** guard); **removing** a manual entry does **not** re-check yield on that hex.
- Domain: **`City.worked_tiles_mode`** + **`CityYields`** split (**superseded** by **5.1.19e** — idle citizens, **no** post-removal auto-fill while **`manual`**).
- Tests/doc touch: **`test_set_city_worked_tiles.gd`**, **`test_city_yields_worked_tiles.gd`**, **`test_city_worked_tiles_view.gd`**; **`CITIES.md`**, **`CITY_UX.md`**, this plan.

Validation: **`scripts/run-godot-tests.ps1`**; manual **`main.tscn`**: grow to **pop 2**, **Manage Citizens**, two **worked** markers; see **5.1.19e** for idle behavior after toggle-off.

#### 5.1.19e — Manual worked mode + idle citizens (no hidden auto-fill)

**Status:** **Shipped.**

- **`City.WORKED_TILES_MODE_AUTO`** / **`WORKED_TILES_MODE_MANUAL`** on **`City`** (default **`auto`** on **`FoundCity`**). **`SetCityWorkedTiles.apply`** always sets **`manual`**; payload **`tiles: []`** ⇒ **`manual_worked_tiles` empty** ⇒ **no** worked-tile **raw** yield from citizens until the player assigns again (**idle**, not revert **`auto`**; **no** visible **Auto** control in this slice).
- **`CityYields.worked_tiles_for_city`**: **`auto`** ignores **`manual_worked_tiles`** and uses the prior deterministic auto picker up to **`population`**; **`manual`** uses only validated **`manual_worked_tiles`** (no auto-fill of free slots).
- Preserved on **`ProductionTick`**, **`ProductionDelivery`**, **`SetCityProduction`**, **`FoodGrowthTick`** rebuilds.
- Tests: **`test_city.gd`**, **`test_set_city_worked_tiles.gd`**, **`test_city_yields_worked_tiles.gd`**, **`test_legal_actions.gd`**, **`test_production_tick.gd`**, **`test_city_worked_tiles_view.gd`**; docs **`CITIES.md`**, **`CITY_UX.md`**, **5.1.18a** bullets here.

Validation: **`scripts/run-godot-tests.ps1`**; manual: **pop 2**, **Manage Citizens**, two **worked**; click one **worked** tile — marker drops with **no** replacement **worked** on another ring tile; assign from **dim** again; hub yields/growth refresh.

#### 5.1.19f — Turn status HUD (**`TurnStatusPanel`**; presentation-only)

**Status:** **Shipped** (hotseat wording + **UnitNameplateView** accent alignment — **2026** correction).

- **`TurnStatusPanel`** ([turn_status_panel.gd](../game/presentation/turn_status_panel.gd)) — small **`PanelContainer`** under **`HudCanvas`**, **lower-right**, **above** **`CityProductionPanel`**; reads **`GameState.turn_state`** only. **Prototype / local hotseat:** title **`Player N's turn`** (who is playing **in this app**); **no** “Waiting for …” / remote-server semantics in this slice. **Orb + panel tint + border** derive from **`UnitNameplateView.owner_nameplate_accent_color(N)`** — same owner accent source as **`EmpireBorderView`** / nameplate strips (**not** **`UnitsView.owner_to_color`** marker disks). **`local_player_id`** export remains for future remote-seat UX; **ignored** for copy in hotseat mode.
- **`TurnLabel.after_refresh`** chains **`TurnStatusPanel.refresh`** so HUD stays in sync wherever **`turn_label.refresh()`** runs; **no** **`EndTurn`** / turn-order rule changes.
- Tests: **`test_turn_status_panel.gd`**, **`test_main_hud_city_panel.gd`**; **`scripts/run-godot-tests.ps1`**; **[CURRENT_ARCHITECTURE.md](CURRENT_ARCHITECTURE.md)**, **[VALIDATION_CHECKLIST.md](VALIDATION_CHECKLIST.md)** (manual turn HUD).

Validation: **`scripts/run-godot-tests.ps1`** green; **`main.tscn`**: panel always visible; **`Player N's turn`** + **nameplate/empire** accent colors track **`current_player`** (**End Turn** / hotseat). **[VALIDATION_CHECKLIST.md](VALIDATION_CHECKLIST.md)** — Phase **5.1.19f** manual HUD checks.

#### 5.2.0 — Local hotseat / debug-mode checkpoint

**Status:** **Shipped (documentation only).**

- **Canonical mode name:** **local hotseat prototype** — one **Godot** app instance; **`TurnState.current_player_id()`** rotates on **`EndTurn`**; a **single local user** may submit actions for **whichever player is current** (shared control). The domain still requires **`actor_id == current_player_id()`** on every accepted action via **`GameState.try_apply`**.
- **Out of scope today:** **server / cloud multiplayer**, networking, lobby, accounts, **fog-of-war / privacy**, **remote-seat** “waiting for …” copy, and **authoritative** backends — all **explicitly future** (see **[CLOUD_PLAY.md](CLOUD_PLAY.md)**, **[ARCHITECTURE_PRINCIPLES.md](ARCHITECTURE_PRINCIPLES.md)**).
- Steering updates: **[CURRENT_ARCHITECTURE.md](CURRENT_ARCHITECTURE.md)** (turn control / hotseat), **[VALIDATION_CHECKLIST.md](VALIDATION_CHECKLIST.md)** (Phase **5.2.0** readiness), **[CLOUD_PLAY.md](CLOUD_PLAY.md)** (current state), **[player/PLAYTEST_GUIDE.md](player/PLAYTEST_GUIDE.md)** (hotseat keybinds), **[AI_DESIGN.md](AI_DESIGN.md)** (manual AI trigger).

**Follow-up:** **5.2.1** — hotseat selection clear on **`EndTurn`** — **shipped**; see **5.2.1** below.

Validation: manual read of **5.2.0** docs; automated coverage for the **5.2.1** behavior is **`test_hotseat_endturn_selection_clear.gd`** (see **5.2.1**).

#### 5.2.1 — Hotseat: clear city selection on accepted **`EndTurn`** (`EndTurnController` / **`AITurnController`**)

**Status:** **Shipped** (presentation-only).

- **`EndTurnController`** ([end_turn_controller.gd](../game/presentation/end_turn_controller.gd)): after **`DiscoveryPopup`** sequencing on **accepted** **`EndTurn`**, calls **`apply_hotseat_clear_after_accepted_end_turn`** — **`selection.clear_unit()`**, **`city_production_panel.city_view_state.reset_to_normal()`** when wired, **`selection.clear_city()`**, then existing **`TurnViewSync.refresh_map_views_and_hud_after_try_apply_turn_controllers`** (**`CityProductionPanel.refresh()`** hides hub when no city selected).
- **`AITurnController`** ([ai_turn_controller.gd](../game/presentation/ai_turn_controller.gd)): same clear **only** when the accepted action is **`end_turn`**; non-**`end_turn`** AI actions still **`clear_unit()`** only (prior behavior).
- Tests: **`test_hotseat_endturn_selection_clear.gd`**; **`scripts/run-godot-tests.ps1`**.

Validation: **`scripts/run-godot-tests.ps1`** green; **`main.tscn`**: select capital → **Manage Citizens** → **Space** — **City Hub** closes, planning exits, **TurnStatusPanel** shows **P1**; citizen markers hide when not in **PLANNING**.

#### 5.2.2 — Player / contact strip v0 (**`PlayerContactStrip`**; presentation-only)

**Status:** **Shipped.**

- **`PlayerContactStrip`** ([player_contact_strip.gd](../game/presentation/player_contact_strip.gd)) — **`HudCanvas`**, **upper-right** compact strip: one chip per **`TurnState.players`**; **current** seat **highlight** (border + fill); **`P0` / `P1`** short labels + **`Player N`** tooltip; accent from **`UnitNameplateView.owner_nameplate_accent_color`** (same as **`TurnStatusPanel`** / empire / nameplates). **`contact_state: known`** placeholder per entry for future **unknown / remote / diplomacy** — **no** contact or fog logic yet. **`MOUSE_FILTER_IGNORE`**. **`main.gd`** chains **`TurnLabel.after_refresh`** with **`TurnStatusPanel`** so the strip updates on **`EndTurn`** / HUD turn refresh.
- Tests: **`test_player_contact_strip.gd`**; **`scripts/run-godot-tests.ps1`**.
- Docs: **[CURRENT_ARCHITECTURE.md](CURRENT_ARCHITECTURE.md)**, **[VALIDATION_CHECKLIST.md](VALIDATION_CHECKLIST.md)**, **[RENDERING.md](RENDERING.md)**.

Validation: **`scripts/run-godot-tests.ps1`** green; **`main.tscn`**: strip shows **P0**/**P1**; **Space** moves highlight; colors match lower-right turn strip family; strip does not use **“Waiting for …”** in local hotseat.

#### 5.2.3 — Map visibility / fog v0 (**`PlayerVisibilityState`** domain + **`MapVisibilityView`** parchment overlay)

**Status:** **Shipped.**

- **Domain:** **[`PlayerVisibilityState`](../game/domain/player_visibility_state.gd)** — immutable per-player explored-tile memory (**`Dictionary[Vector2i, true]`** per owner, same shape as **`ProgressState`** owner maps). **`UNIT_SIGHT_RADIUS`** / **`CITY_SIGHT_RADIUS`** = **2**; **`recompute_for_actor`** unions prior explored set for that owner only with sight from owned units and owned city centers + **`City.owned_tiles`** (clamped to **`scenario.map`** cells via **`map.coords()`** only). **`GameState`** (**[`game_state.gd`](../game/domain/game_state.gd)**) seeds **`visibility_state`** after initial **`ProductionDelivery`** for all **`TurnState.players`**; **`try_apply`** recomputes on accepted **`move_unit`**, **`found_city`**, and **`end_turn`** (after delivery for the **new** **`current_player_id`**). **No** enemy hiding, **no** “currently visible” vs memory, **no** AI / **`LegalActions`** changes.
- **Presentation:** **[`MapVisibilityView`](../game/presentation/map_visibility_view.gd)** — **`Node2D`** sibling **after** **`TerrainForegroundView`**, **before** **`LightningTreeView`** / nameplates / **`HudCanvas`**; draws **`unexplored_parchment_overlay_prototype.png`** with **`MapView._world_anchored_corner_uvs`** so the fog reads as **one** continuous layer with **holes** at explored hexes for **`turn_state.current_player_id()`** (local hotseat). **`TurnViewSync`** passes **`game_state`** + **`queue_redraw`** from **`SelectionController`** / **`EndTurnController`** / **`AITurnController`**.
- Tests: **`test_player_visibility_state.gd`**, **`test_player_visibility_reveal.gd`**, **`test_map_visibility_view.gd`**, **`test_hex_coord.gd`** (distance), updates **`test_main_tscn_map_layer_sibling_order.gd`**, **`test_turn_view_sync.gd`**; **`scripts/run-godot-tests.ps1`**.
- Docs: **[CURRENT_ARCHITECTURE.md](CURRENT_ARCHITECTURE.md)**, **[MAP_MODEL.md](MAP_MODEL.md)**, **[RENDERING.md](RENDERING.md)**, **[VALIDATION_CHECKLIST.md](VALIDATION_CHECKLIST.md)**.

Validation: **`scripts/run-godot-tests.ps1`** green; manual **`main.tscn`**: starting area for **P0** clear, rest parchment; move warrior extends clear disk; **Space** switches overlay to **P1**’s explored memory; found city clears center + owned + radius-2; parchment tiles continuously in world space.

#### 5.2.5 — Per-turn movement points v0 (`max_movement` / `remaining_movement`; flat cost **1**)

**Status:** **Shipped.**

- **Domain:** **`Unit`** carries **`max_movement`** (from **`UnitDefinitions`**) and **`remaining_movement`**. **`MoveUnit`** spends **1** per accepted step (terrain **`movement_cost`** in **`TerrainRuleDefinitions`** is still **not** consumed for legality). **`MovementRules.legal_destinations`** returns **`[]`** when **`remaining_movement < 1`**. **`Scenario.with_refreshed_movement_for_owner`** rebuilds that owner’s units at full MP; **`GameState.try_apply`** runs it after initial **`ProductionDelivery`** for the opening **`current_player_id`**, and after accepted **`end_turn`** once **`ProductionDelivery`** has run for the **new** current player (hotseat: the seat that **ended** does **not** get an immediate re-refresh for itself).
- **Definitions:** **`settler`** and **`warrior`** — **`max_movement` = `2`** in **`UnitDefinitions`**; **`max_movement_for_type`** helper for caps.
- **Tests:** **`test_unit_movement_points_v0.gd`**, updates to **`test_move_unit.gd`**, **`test_movement_rules.gd`**, **`test_unit.gd`**, **`test_move_unit_preserves_scenario_state.gd`**, **`test_unit_definitions.gd`**; **`scripts/run-godot-tests.ps1`**.
- **Docs:** **[CURRENT_ARCHITECTURE.md](CURRENT_ARCHITECTURE.md)**, **[MOVEMENT_RULES.md](MOVEMENT_RULES.md)**, **[UNITS.md](UNITS.md)**, **[MAP_MODEL.md](MAP_MODEL.md)**, **[VALIDATION_CHECKLIST.md](VALIDATION_CHECKLIST.md)**.

**Out of scope (explicit):** terrain- or feature-based movement costs, roads, embarkation / water movement, pathfinding redesign beyond enforcing MP, AI policy changes beyond **`LegalActions`**, combat/production changes except MP field initialization.

Validation: **`scripts/run-godot-tests.ps1`** green; manual **`main.tscn`**: each unit moves at most **two** **`MoveUnit`** steps per turn; third click does nothing / rejects; **Space** gives the **next** player full MP; cycle back restores the first player’s MP; fog/reveal after valid moves unchanged.

#### 5.1.17f — City interaction UX direction doc

**Status:** **Shipped (documentation).**

- **[CITY_UX.md](CITY_UX.md)** — concise orientation: **`CityHubPanel`** lower-right on city selection; **opt-in** **CityPlanningMode** via **Manage Citizens** (presentation-only until mechanics); **always-on empire borders** vs **selection-driven** city/worked overlays; roadmap slices + explicit **out of scope**.
- Steering pointers: **[CURRENT_ARCHITECTURE.md](CURRENT_ARCHITECTURE.md)**, **[RENDERING.md](RENDERING.md)** (**layering direction** note).

Validation:

- Docs-only; **`scripts/run-godot-tests.ps1`** unchanged in intent.

#### 5.1.17g — Selected-city **City Hub** panel skeleton (**city_production_panel.gd**)

**Status:** **Shipped.**

- **`CityProductionPanel`** — lower-right **`HudCanvas`** anchor in **`main.tscn`**; visible header **City Hub** + **identity** (**name · Pop** **`City.population`**) + **`#id · Owner`** + yields / breakdown / **`LegalActions`** production; **Manage Citizens** (**enters** **`CityViewState`** **PLANNING** for **current-player** cities), **Done** (**exits PLANNING**, keeps city selected), **Close** (**`CityViewState.reset_to_normal()`** + **`selection.clear_city()`** + territory / worked-tile / panel refresh); **`main.gd`** wires **`city_view_state`**, **`selection_view`**, **`city_territory_view`**, **`city_worked_tiles_view`**. (**Hub skeleton:** **5.1.17g**; **planning toggle:** **5.1.17i**.)
- **`compute_view_model`** — **`hub_brand`**, **`identity_line`**, **`manage_citizens_*`**, **`planning_*`**, **`done_planning_*`**, **`close_button_text`** ( **`header_title`** unchanged for city name).
- Tests: **`test_city_production_panel.gd`**, **`test_city_view_state.gd`**, **`test_main_hud_city_panel.gd`**; **`scripts/run-godot-tests.ps1`**.

Validation:

- **`scripts/run-godot-tests.ps1`** green.

#### 5.1.17h — **`EmpireBorderView`** (always-on owner **union** border)

**Status:** **Shipped** (**5.1.17h** prototype + **5.1.17h.1** strength / layering correction).

- **`game/presentation/empire_border_view.gd`** — **`Node2D`**, **`scenario` / `layout` / `MapCamera`** only (**no** **`SelectionState`**); unions **`City.owned_tiles`** per **`owner_id`**; outer perimeter (**`CityTerritoryView`** topology helpers). **Dual** **`Line2D`** rim — **owner-colored** outer + **indigo** inner (**same alpha / width fractions** as legacy **`CityTerritoryView`** territory emphasis); selection-independent appearance.
- **`CityTerritoryView`** — **`_draw`** **dormant** in normal play (**no** second rim; **selection-independent** **`EmpireBorderView`** unchanged when a city is selected). Node + **`SelectionController`** wiring retained for future slices. **Forward UX:** city-owned tiles → **citizen/head** markers, **not** perimeter strokes.
- **`main.tscn` / `main.gd`** — sibling **after** **`MapView`**, **`z_index` 0**, **before** **`CityTerritoryView`** (slot above empire for future planning-only emphasis).
- **`TurnViewSync`** + **`SelectionController`** / **`EndTurnController`** / **`AITurnController`** — **`empire_border_view`** redraw alongside terrain when **`Scenario`** updates.
- Tests: **`test_empire_border_view.gd`**, **`test_main_tscn_map_layer_sibling_order.gd`**, **`test_turn_view_sync.gd`**, **`test_city_territory_main_wiring.gd`**; **`scripts/run-godot-tests.ps1`**.

Validation:

- **`scripts/run-godot-tests.ps1`** green.

#### 5.1.17i — **`CityViewState`** (**NORMAL** / **PLANNING**) + hub toggle shell

**Status:** **Shipped.**

- **`game/presentation/city_view_state.gd`** — presentation **`RefCounted`**; **`enter_planning`**, **`exit_planning`**, **`reset_to_normal`**, **`is_planning`**; **no** domain / **`try_apply`** / log.
- **`game/main.gd`** — one **`CityViewState`** beside **`SelectionState`**; wired to **`CityProductionPanel`**, **`CityWorkedTilesView`**, **`SelectionController`**.
- **`city_production_panel.gd`** — **Manage Citizens** enables for **current-player** selected city; enters **PLANNING**; **Done** exits planning (**city** stays selected); **Close** **`reset_to_normal`** + **`selection.clear_city()`**; planning banner line on hub.
- **`city_worked_tiles_view.gd`** — **5.1.17j** / **5.1.17j.1**: citizen **`dim` / `worked`** prototype textures; **`_draw`** and **`compute_draw_marker_items`** run **only** in **`CityViewState`** **PLANNING** — city select shows **hub** without map markers.
- **`selection_controller.gd`** — **ESC** exits planning (**normal** behavior unchanged otherwise); clears planning when selection changes (**different city**, **unit**, **clear**).
- **`CityTerritoryView`** untouched (**dormant**).
- Tests: **`test_city_view_state.gd`**, updates **`test_city_production_panel.gd`**, **`test_city_worked_tiles_view.gd`**; **`scripts/run-godot-tests.ps1`**.
- **5.1.17i.1 (historical):** aquamarine inset markers **PLANNING-only** — **removed** by **5.1.17j** citizen PNGs; **5.1.17j.1** restores **PLANNING-only** draw after a brief **NORMAL**-marker regression.

Validation:

- **`scripts/run-godot-tests.ps1`** green.

#### 5.1.17j — Selected-city **citizen markers** (prototype **`dim` / `worked`** assets)

**Status:** **Shipped** (draw semantics finalized in **5.1.17j.1**).

- **`game/presentation/city_worked_tiles_view.gd`** — class/file **`CityWorkedTilesView`** unchanged for wiring: loads **`res://assets/prototype/map_markers/city_citizens/citizen_marker_dim.png`** and **`citizen_marker_worked.png`** (**`ResourceLoader.load`**, **`TEXTURE_FILTER_LINEAR_WITH_MIPMAPS`**); **`draw_texture_rect`** at projected hex center + **`perspective_scale_at`**; **non-center** **`City.owned_tiles`** only; **`kind`** **`dim`** vs **`worked`** from **`CityYields.yield_breakdown_for_city`(..).`worked_tiles`**. **`compute_worked_marker_items`** exposes the logical list (tests); **`compute_draw_marker_items`** / **`_draw`** gated by **`CityViewState`** **PLANNING** (**5.1.17j.1**). Deterministic item order: **`q`** asc, **`r`** asc.
- **Assets:** **`.import`** **`mipmaps/generate=true`**. Fresh checkout: **`godot --path game --import --headless`** if imports missing.
- Tests: **`test_city_worked_tiles_view.gd`**; **`scripts/run-godot-tests.ps1`** green.

Validation:

- **`scripts/run-godot-tests.ps1`** green.

#### 5.1.17j.1 — Citizen markers **PLANNING-only** (hub vs management visualization)

**Status:** **Shipped** (UX correction).

- **Intent:** Selecting a city shows **City Hub** only — **no** citizen/head markers on the map until **Manage Citizens** enters **PLANNING**. **Done** / **ESC** exits planning (markers off, city stays selected); **Close** clears selection and markers.
- **`city_worked_tiles_view.gd`:** **`_draw`** returns immediately unless **`city_view_state.is_planning()`**; **`planning_marker_draw_style()`** applies **only** on this path (scale/alpha multipliers for citizen-management mode).

Validation:

- **`scripts/run-godot-tests.ps1`** green; manual **`main.tscn`**: city select → **hub, no markers**; **Manage Citizens** → **dim/worked** markers; **Done**/**ESC** → markers off; **Close** → hub off; **`EmpireBorderView`** unchanged; **`CityTerritoryView`** still no rim.

#### 5.1.17k — Terrain **edge blend** (**PLAINS ↔ GRASSLAND**; presentation-only)

**Status:** **Shipped**.

- **`game/presentation/terrain_edge_blend_view.gd`** — **`TerrainEdgeBlendView`**, **`Node2D`**: reads **`HexMap`** / **`HexLayout`** / **`MapCamera`** only (**no** `Scenario` on node); **`compute_blend_items(p_map)`** (**canonical edges**, **deterministic** sort); **`_draw`** = low-alpha **`draw_colored_polygon`** ribbons straddling shared edges (**lerp** of local terrain fallback RGB). **v1:** **PLAINS–GRASSLAND** adjacency **only** — **no** **WATER** / coast, **no** **woods**/forest, **no** **shaders**, **no** new PNGs, **no** **`TerrainForegroundView`** / **`MapView`** rewrites.
- **`main.tscn`**: sibling order **`MapView` → `TerrainEdgeBlendView` → `EmpireBorderView` → …**; **`z_index` 0** on blend ( **above** base terrain, **below** empire + later map chrome).
- **`main.gd`**, **`turn_view_sync.gd`**, **`SelectionController`**, **`EndTurnController`**, **`AITurnController`**: **`map`** assign + **`queue_redraw`** with existing sync (**no** bus/registry).
- Tests: **`test_terrain_edge_blend_view.gd`**; updates **`test_main_tscn_map_layer_sibling_order.gd`**, **`test_turn_view_sync.gd`**; **`scripts/run-godot-tests.ps1`**.

Validation:

- **`scripts/run-godot-tests.ps1`** green; manual **`main.tscn`**: **PLAINS/GRASSLAND** seams slightly softer; empire border crisp; no extra “hex grid” stroke look from blend; water/forest seams unchanged in **v1** scope.

#### 5.1.16h — Population auto-works owned tiles (planned)

**Status:** Planned (forward umbrella). **Embryo:** **5.1.17a**.

Goal:

- **`City.population`**, deterministic auto-assignment of **worked** tiles drawn from **`owned_tiles`** (non-center); **`CityYields.city_total_yield`** includes worked-tile contribution; production / science / overlay reflect the expanded totals.

#### 5.1.16a — Player guide: Early City Economy tutorial (docs/player)

**Status:** **Shipped (documentation).**

Goal:

- Player-facing **HTML** tutorial under **`docs/player/`** describing the **intended** early city economy: worked-tile yields (v0 table), city-center normalization, capital **Palace** baseline (**Science** + **Coin**), **Coin** as era-flexible economic yield, and the principle that **science** is not automatically duplicated from every new city on turn one.

Shipped:

- **[player/city-economy.html](player/city-economy.html)** — **Early City Economy** page; **[player/index.html](player/index.html)** — tutorial card + nav; **[player/playtest.html](player/playtest.html)** — nav link; **[player/style.css](player/style.css)** — tables + cards; **[DECISION_LOG.md](DECISION_LOG.md)** — decision entry; optional cross-ref **[CITIES.md](CITIES.md)**.

Validation:

- Manual: open **`docs/player/index.html`** in a browser; follow **Early City Economy**; no JavaScript required.

## Milestone — Fixed-grid Godot 3D terrain parity (approved next terrain milestone)

**Status:** approved direction; **N0 documentation complete (2026-08)**; runtime implementation **in progress** — N1, N3a, N3b (visually approved 2026-08), the native cg_plain solver backend (N3b.1a/N3b.1b), N3c.1 (domain surface-geometry builder: top surface + Stage-3a cliff walls, dev-preview only), N3c.2 (interactive terrain-inspection preview: orbit camera, dev HUD, backend selector), N3c.3a (top-surface three-layer PBR splatting port, shown in the inspection preview), N3c.3b (Stage-3a cliff-wall stone PBR port with wall-local UVs, shown in the inspection preview), N3c.4 (deterministic terrain collision derived from the N3c.1 surface geometry, in the inspection preview), N3c.5 (deterministic tile/cliff-edge picking via that collision, in the inspection preview), N3c.6 (shared runtime terrain world component + dev terrain runtime harness; locked dual-entry direction), and N3c.7 (deterministic production lighting rig owned by the shared runtime world; visually approved 2026-08 as an **interim daytime environment** — final sky art direction/clouds are a separate future slice) are done — **N3 terrain construction is complete (2026-08)**; **N4** (world anchors + projected screen-space UI on the shared runtime world, dev-harness integration only) is **done (2026-08, visually approved)**; **N5** (server logical `WorldMap` foundation + canonical content packaging) is **done (2026-08)**; **N6** (snapshot v3 + server-fed client world bootstrap: opt-in `world_map` match kind, identity-only snapshot v3, strict client content-hash verification, kind-routed `cloud_world_play` production scene) is **done (2026-08)**; **N7a–N7c** (server-authoritative world units + `move_unit`/`end_turn`, served world `legal-actions`, client unit rendering at the N4 anchors) are **done (2026-08)**. The rest of the N track is subdivided and planned: **N7d–N7g** (client world interaction loop, N7 verification checkpoint, unit locomotion presentation, world Combat 0.1) then **N8a–N8d** (minimal world cities, flat yields v2 + production selection, authoritative production processing + deterministic spawn, first complete two-player `WorldMap` gameplay loop checkpoint) — see **“Planned N7d–N8d”** below; **N9** (full cutover + legacy removal) is unchanged. This milestone is decoupled from the Phase 5.x gameplay numbering: it is presentation/terrain work and does not change gameplay rules until the new match core lands (N7+).

Goal:
Reproduce the accepted **TS-08** Blender reference terrain (see [TERRAIN_SURFACE_TARGET.md](TERRAIN_SURFACE_TARGET.md) and the canonical section of [TERRAIN_MODEL.md](TERRAIN_MODEL.md)) as **Godot-native runtime terrain construction** from the **fixed hand-authored logical hex grid** (`handdrawn_test_map_full_01`). Blender remains a development/reference implementation only — never a runtime dependency.

**Reference contract.** Parity is validated against the reference contract as a whole: the canonical logical grid (authoritative input), the TS-08 algorithm and parameters, a deterministic reference dataset (derived golden for audit — not the production source), the audit chain, and the visually accepted Blender result. The committed Stage 3a `.blend` is one artifact within that contract, not the sole authority.

**Terrain authority (locked):**

| Role | What | Notes |
|------|------|-------|
| **Authoritative input** | Canonical 2D logical map + height-level grid (`content/maps/`) → **`WorldMap`** | Sole source for terrain construction |
| **Production path** | TS-08-equivalent solver run on that input | Godot-only terrain pipeline: solving and geometry generation happen exclusively in Godot; the server owns only the logical map (tiles, elevation, derived edges) and never solves terrain or generates geometry |
| **N2 reference dataset** | Pre-solved Stage-2 export (`content/terrain/reference/`) | Derived golden for parity testing/audit; **does not replace the solver** |
| **N3 checkpoint (optional)** | Load N2 pre-solved dataset for early visible 3D world | Temporary visual-parity checkpoint only — **not target architecture** |
| **Never authoritative** | Mesh, collision, sampled heights, N2 JSON, `.blend` | Presentation derivatives only |

**3D Map and World Integration slices (N0–N9):**

| Slice | Status | Goal |
|-------|--------|------|
| **N0** | **Done (docs)** | Coordinate contract, `WorldMap` architecture, yield direction, legacy deprecation — [WORLD_COORDINATES.md](WORLD_COORDINATES.md), [MAP_MODEL.md](MAP_MODEL.md) |
| **N1** | **Done (2026-08)** | `WorldMap`, projection, loader, `MapIdentity`, packaging sync, headless tests — **no rendering** |
| **N2** | **Done (2026-08)** | Blender TS-08 reference-dataset export + audit — `content/terrain/reference/handdrawn_test_map_full_01_ts08_stage2_reference_v1.json`; exporter `tools/blender/terrain/export_ts08_reference_dataset.py` |
| **N3** | Planned | First visible 3D world: TS-08-equivalent solver-generated surface (target path), orbit camera, tile/edge picking (camera and picking already delivered inside the inspection preview — N3c.2/N3c.5; N3 integrates them into the runtime world); optional N3 checkpoint may load N2 pre-solved dataset temporarily for visual parity — not target architecture |
| **N3a** | **Done (2026-08)** | Native TS-08 Stage-0 cut-lattice topology from **`WorldMap`** (`Ts08CutLattice`); parity vs N2 via compact digest manifest (counts + SHA-256 stream digests; not runtime content); no height solve, mesh, or rendering |
| **N3b** | **Done (2026-08, visually approved)** | Native TS-08 Stage-2 cut-domain thin-plate CG height solve from **`WorldMap`** + `Ts08CutLattice` (`Ts08HeightSolver`): float64 CSR PCG, Jacobi precond, planar warm start, hard pins by elimination, component/gauge routing (analytic constant/plane, deflated CG + exact post-projection); full-height parity vs N2 via test-only binary height golden; dev-only preview scene (`game/dev/terrain_preview/`) — no mesh/material/collision/runtime integration |
| **N3b.1a** | **Done (2026-08)** | Native C++ GDExtension build-and-load path: `native/` CMake + Ninja + MSVC project with godot-cpp pinned to tag `godot-4.5-stable` (forward-compatible with the project's Godot 4.6.2-stable); `EomTerrainNative` scaffold (intended terrain backend) with float64/`PackedFloat64Array` boundary probes; build-generated descriptor + DLL in gitignored `game/bin/`; headless smoke test `test_native_extension_smoke.gd`; build via `scripts/build-native.ps1` (see `native/README.md`) — **no solver port yet** |
| **N3b.1b** | **Done (2026-08)** | Native port of the rank-3/plain-PCG hot path only (`EomTerrainNative.solve_cg_plain_global`): exact operator/preconditioner/warm-start/tolerance semantics, one GDScript/C++ crossing per solve, explicit opt-in backend (`Ts08HeightSolver.BACKEND_NATIVE`; fails loudly when the DLL is absent — never silent fallback). GDScript stays the verified reference and default; census/analytic/deflated routes stay GDScript. Reference map: heights **bit-identical** to GDScript, same 1526 iterations, golden parity max abs 6.9e-10; native solve **653 ms** vs GDScript 56.1 s (**85.8×**; ~6.2 MB native buffers; build + solve 2.0 s — sub-10 s reached). Tests: `test_native_cg_kernel.gd`, `test_ts08_height_solver_n3b_native.gd` |
| **N3c.1** | **Done (2026-08)** | Domain-only terrain-surface geometry builder (`Ts08SurfaceGeometry`): accepted top surface (solver heights, Y-up triangles, smooth normals) + port of the accepted Stage-3a cliff-wall contract from `eom_terrain_ts08_cliff_walls.py` (walls only on authoritative `WorldMap` cliff edges, duplicated seam nodes, one polygon per non-degenerate segment, crack-tip triangles, deterministic orientation toward the lower tile). Reference map: 74,129 top vertices, 145,152 top triangles, 936 wall faces (916 quads + 20 crack-tip triangles, 0 skipped), wall-face digest parity vs the Python helper via `generate_ts08_n3c_wall_parity_manifest.py`; preview renders walls and gains `--native`. Tests: `test_ts08_surface_geometry_components.gd`, `test_ts08_surface_geometry_n3c.gd` — no production materials, collision, or runtime integration |
| **N3c.2** | **Done (2026-08)** | Dedicated interactive terrain-inspection preview (`game/dev/terrain_preview/`, dev-only): runnable from the editor with F6 (no arguments), orbit camera (360° yaw, bounded pitch that never passes below terrain, map-relative zoom limits, ground-plane panning, reset, deterministic strategic/low-angle presets), compact HUD (backend used, lattice/solve/geometry/mesh timings, topology counts, camera state, controls), editor-configurable backend selector (Auto default = native when available else GDScript; explicit Native fails clearly; explicit GDScript for clean checkouts; `--native` forces Native) — preview-tool behavior only, **not** automatic production backend selection; screenshot mode `--screenshot[=low]` renders reproducible preset PNGs. Runtime chain unchanged: `WorldMap → Ts08CutLattice → Ts08HeightSolver → Ts08SurfaceGeometry → dev ArrayMesh`; never N2 heights. Tests: `game/dev/tests/test_terrain_preview_camera.gd`, `game/dev/tests/test_terrain_preview_smoke.gd` |
| **N3c.3a** | **Done (2026-08)** | Presentation-side Godot port of the approved three-layer ground/ash/stone top-surface PBR splatting baseline (`game/presentation/terrain_top_surface.gdshader` + `game/presentation/terrain_surface_material.gd`; source: `generate_terrain_single_patch_pbr_ground_stone_ash_prototype.py` + the approved porting-baseline section of `tools/blender/terrain/README.md`). World-anchored UV `(u, v) = (x × 0.35, −z × 0.35)` baked into the top mesh with slope-aware orthonormal tangents (exact dP/du of the planar mapping from the smooth normals, `T = normalize(ny, −nx, 0)`, w = +1); nine existing prototype textures consumed in place (runtime-loaded with generated mipmaps, repeat + mipmapped sampling); locked baseline preserved (ash regional→breakup→0.30/0.95 smootherstep remap, stone smooth-normal slope mask 0.96/0.90 + breakup 0.080, shared weight drives albedo/normal/roughness, ground/ash then stone blend order, `USE_FINE_DETAIL` off). Blender's exact noise hash is not reproducible: same fractal chain/scales/fixed seed via deterministic hash-based Perlin fBm (reported difference). Preview renders the material with debug stages (final/ash_mask/stone_mask/albedo; HUD, `M` cycle, `--stage=<name>` CLI screenshots); cliff walls keep the neutral material and lighting is unchanged (wall stone PBR is N3c.3b). Tests: `game/presentation/tests/test_terrain_surface_material.gd`, updated `test_terrain_preview_smoke.gd` |
| **N3c.3b** | **Done (2026-08)** | Presentation-side Godot port of the accepted TS-08 Stage-3a cliff-wall stone material (`game/presentation/terrain_cliff_wall.gdshader` + `game/presentation/terrain_cliff_wall_material.gd`; source: `eom_terrain_ts08_cliff_wall_stone_material.py`). Locked baseline preserved: wall-local UV `U = dot(world XZ, cliff tangent) × 0.35`, `V = world Y × 0.35`, with the deterministic most-horizontal-edge tangent chosen per original wall polygon **before** fan triangulation (quad diagonals share one mapping — no seam; crack-tip triangles use the same rule; UVs never normalized/restarted per face); albedo × 0.55, normal strength 0.55, sampled roughness (inert 0.88 unlinked-socket fallback), metallic 0, specular IOR level 0.25; the three stone prototype textures reused in place (shared instances with the top material). Per-triangle tangents: exact dP/du of the wall UV orthogonalized against the flat face normals (finite/unit/orthogonal/handed, bit-identical determinism). Wall geometry, topology, normals, and the accepted top mesh/material unchanged; preview swaps only the neutral wall material and keeps both shaders synchronized on the debug stages (walls black in ash_mask, white in stone_mask, albedo-only in albedo). Reported semantic differences (no retune): Godot maps `SPECULAR` to F0 quadratically vs Blender's linear specular-IOR level; grayscale roughness sampled as `.r` vs Blender's RGB average. Tests: `game/presentation/tests/test_terrain_cliff_wall_material.gd`, updated `test_terrain_preview_smoke.gd` |
| **N3c.4** | **Done (2026-08)** | Deterministic Godot terrain collision derived from the accepted N3c.1 surface geometry (`game/presentation/terrain_collision.gd`): presentation/integration-side builder consuming `Ts08SurfaceGeometry` output — collision is **derived data only**, never terrain or gameplay authority. Two independently identifiable `ConcavePolygonShape3D` shapes under one `TerrainCollision` StaticBody3D (`TopSurfaceCollision` = exact solver-generated top positions through the accepted top triangles in rendered index order; `CliffWallCollision` = the identical wall vertex stream the renderer bakes, same deterministic fan triangulation — no resampling, approximation, simplification, or topology change; rendered winding kept so single-sided physics normals face up/outward). Reference map: 145,152 top + 1,852 wall triangles (435,456 + 5,556 face vertices, ~5.3 MB float32), build ~160 ms standalone / ~340 ms in preview; bit-identical across builds; raycasts hit the solved surface height (max error ~1.2e-6) and wall planes; inputs proven unmutated. Integrated into the inspection preview (rendering/materials/lighting/camera unchanged). Tests: `game/presentation/tests/test_terrain_collision.gd` + extended preview smoke. No chunking/LOD/optimization, picking, or gameplay integration |
| **N3c.5** | **Done (2026-08)** | Deterministic tile/cliff-edge picking in the terrain inspection preview via the N3c.4 collision (`game/presentation/terrain_picker.gd`): raycast results from the named `TerrainCollision` body resolve to canonical `WorldMap` identities — top hits to `kind = tile` + `Vector2i(q, r)` via `HexWorldProjection.world_xz_to_axial` validated against `WorldMap`; wall hits to `kind = cliff` + the normalized edge key and **both** adjacent tiles (locked rule per [MAP_MODEL.md](MAP_MODEL.md): never silently the lower/upper tile; gameplay legality keeps using `WorldMap` edge data). Wall identity comes from deterministic metadata aligned one-to-one with the 1,852 wall collision triangles (both fan triangles of a quad share one source `WallFace`; crack tips map once); the physics `face_index` is only a presentation lookup index. Miss / foreign collider / invalid face index → no pick, never a positional or nearest-geometry guess. Preview: left-click raycast with the result in the HUD (`Tile: (q,r)` / `Cliff: (q1,r1)–(q2,r2)` / `No terrain hit`) — inspection feedback only, no selection state, overlays, or gameplay. Tests: `game/presentation/tests/test_terrain_picker.gd` + extended preview smoke |
| **N3c.6** | **Done (2026-08)** | Shared runtime 3D terrain world + dev terrain runtime harness; **locked dual-entry direction**. `game/presentation/world/terrain_world.gd` is the single reusable production-side assembly of the accepted N3 chain (caller-supplied authoritative `WorldMap` → lattice → solved surface → rendered top/walls with the N3c.3a/3b materials → N3c.4 collision → orbit camera (moved to `game/presentation/world/orbit_camera.gd`) → N3c.5 picking). Picking is exposed as presentation output (`terrain_picked` signal + `last_pick`) — consumed by the completed N4 projected anchor UI — no selection state or gameplay in the runtime world itself. **Dual entry (locked):** **remote multiplayer** runs against the **remote authoritative server**; the future **one-PC debug mode** runs against a **locally running authoritative server**; both use the **same client-server API/action path** (actions, validation, authoritative rule path) and both feed this same scene an already constructed `WorldMap` — the player may later control both players from one computer; implementation of this server-fed `WorldMap` path is N6 (snapshot v3). The runtime world never constructs gameplay state, never depends on legacy `HexMap`, and never chooses the solver backend (caller-supplied; the dev preview and dev harness own their own Auto policies — no production backend policy established). `game/dev/terrain_runtime_harness/terrain_runtime_harness.tscn` is a **dev-only visual/runtime integration harness**: loads `handdrawn_test_map_full_01` directly (allowed only because it is a dev harness) and displays the runtime world — not a gameplay mode and not the future one-PC debug route. The cloud front door remains the main scene and the legacy playable path is untouched. The dev preview (`game/dev/terrain_preview/`) is now a thin shell around the same component (HUD, screenshots, stage cycling, backend selector stay dev-only — no second terrain implementation). Tests: `test_terrain_world.gd`, `test_terrain_runtime_harness.gd` + updated preview smoke/camera suites |
| **N3c.7** | **Done (2026-08; visually approved as interim daytime environment)** | Production lighting for the shared runtime terrain world (`game/presentation/world/terrain_lighting.gd`): one deterministic rig built by `TerrainWorld` for every entry (dev harness, dev preview, future server-fed gameplay) — dev scenes carry no competing lights. Rig: warm key sun (`rotation (-50°, -32.5°, 0°)`, color `(1.0, 0.972, 0.925)`, energy 1.55, angular size 0.75° — the accepted gameplay lighting; never moved to chase the decorative sky disc, which may sit outside normal framing) with PSSM 4 blended-split shadows (bias 0.03, normal bias 1.2, map-relative shadow range `3.6 × AABB extent`); cool shadowless fill (`rotation (-38°, 147.5°, 0°)` — azimuth opposes the sun, color `(0.82, 0.87, 0.95)`, energy 0.45, specular 0) so shadowed faces/cliff walls stay readable; environment backdrop is an **interim daytime** **ProceduralSkyMaterial** sky (placeholder — friendlier than the old dark-grey backdrop, **not** a final art-direction lock): top `(0.29, 0.45, 0.67)`, sky curve 0.10, and **exactly one shared horizon color `(0.58, 0.68, 0.80)` on both hemispheres** (seamless boundary by construction) with a broad visible fade below it (ground curve 0.02) through darker blue-grey to the subdued dark `(0.24, 0.27, 0.31)` bottom, so no line or ring shows around the small floating map from any pitch; contained sun glow `sun_angle_max 8°`, `sun_curve 0.2` — backdrop only: ambient stays the locked flat `(0.72, 0.76, 0.84)` × 0.34 (not sky-sampled) and **reflected light is disabled** so the sky radiance does not alter the accepted material look; Filmic tonemapping (exposure 1.0, white 6.0) so summed light rolls off instead of clipping the bright ash layer. All values locked constants; only input is the generated mesh AABB (shadow range). Geometry, materials/shader logic, collision, picking, and camera unchanged; no cloud assets/shaders, sky textures, volumetric fog/fog, weather, time-of-day, SSAO, or overlays (subtle clouds are a separate later evaluation). Tests: `game/presentation/tests/test_terrain_lighting.gd` + lighting-ownership checks in the harness and preview suites |
| **N3c+** | **Closed (2026-08)** | N3 terrain construction complete with N3c.7. Final sky art direction, clouds, and richer atmosphere: a separate future slice |
| **N4** | **Done (2026-08, visually approved)** | World anchors + projected screen-space UI. **Anchors:** one deterministic world-space anchor per canonical tile, taken from that tile's ACTUAL center-pin lattice node on the solver-generated terrain (`game/presentation/world/terrain_anchors.gd`; the N3a lattice records exactly one center node per hex and the N3b solver hard-pins its height, so the anchor equals the rendered top-surface vertex at the tile center and — by construction — the canonical rules height). Exposed as `TerrainWorld.tile_anchors` (**permanent authority boundary:** derived presentation data only, never gameplay authority — gameplay reads `WorldMap`, never anchors; never recompute anchors from the axial formula, mesh raycasts, or nearest geometry; no legacy `HexMap` / `unit_3d_world_view` / `city_3d_world_view` anchor path). **Projected UI:** reusable presentation component `game/presentation/world/world_anchor_ui.gd` — consumes the `terrain_picked` output and shows a small provisional marker/label at the projected anchor of the focused tile, re-projected every frame (tracks orbit, pitch, pan, zoom, viewport resize; hidden behind the camera). Locked selection contract: a tile pick focuses that tile; a miss clears the focus; a cliff pick leaves the focus UNCHANGED (a cliff identifies the edge + both adjacent tiles per the N3c.5 contract and never silently selects either neighbor). **Locked input contract (click vs camera gesture):** `TerrainWorld` is the single pick-input boundary and owns click classification — selection is deferred until the complete LMB press-move-release interaction is classified. A press starts a click candidate (Shift+LMB pan is never a candidate); pointer movement beyond 6 px from the press position cancels the candidate for the ENTIRE interaction; only a surviving candidate's release runs the pick raycast (at the release position). Camera manipulation (orbit/pan drags, wherever they start or end — terrain, sky, outside the map, outside the viewport) never counts as selection or miss-clearing; the orbit camera owns only camera movement and carries no competing selection state. Focus is presentation state only — no gameplay selection, actions, or domain writes. Integrated only into the dev terrain runtime harness (with dev-only `--select` / `--screenshot` / `--shot-yaw` review support; `output/` gitignored); the harness stays a visual/runtime integration harness, not Local Player Test Mode. No units, cities, movement, N7+ gameplay, or server work. Tests: `test_terrain_anchors.gd`, `test_world_anchor_ui.gd` + extended terrain-world and harness suites |
| **N5** | **Done (2026-08)** | Server logical `WorldMap` foundation + canonical content packaging. **Model/loader:** `server/app/domain/world_map.py` (Python `WorldMap`/`MapIdentity`/`WorldTile`/`WorldEdge` mirror, separate from frozen legacy `HexMap`) + `server/app/domain/map_content_loader.py` (raw-byte SHA-256 `content_hash`, strict schema v1 validation incl. empty-only `edge_overrides`, locked `edge_rule` derivation via the six canonical neighbor deltas; never imports `tools/blender/`). Content root: `EMPIRE_MAP_CONTENT_DIR` **authoritative when set** (invalid override fails explicitly, no fallback) → `server/content/maps` (packaged; `/app/content/maps` in the image) → repo-root `content/maps`. Discovery rejects duplicate `logical_map.id` (`DuplicateMapIdError`) and origin/folder mismatch; invalid UTF-8 → `InvalidMapContentError`. The loader computes `MapIdentity` and never compares against an expected identity (identity comparison = N6 Godot bootstrap). **Parity goldens (Python == Godot):** content hash `16cc82c3…d8c6`, 168 tiles, 452 edges (78 cliff / 374 smooth), bounds q −7…10 / r 0…15, elevation 1–6, base 1, step 0.4, plus the shared canonical **edge-stream digest** `b3f613b4…40cb7f` pinned in both `server/tests/test_world_map_loader.py` and `game/domain/tests/test_world_map_foundation.gd`. **Packaging:** sync tool writes the second committed byte-identical derived copy `server/content/maps/**` + manifest (dual-destination `check`); `server/Dockerfile` ships `content/`; repo-root `.gitattributes` locks map JSON/manifests `-text` (`git check-attr text` → `text: unset`) for hash stability; `server/tests/test_map_content_packaging.py` asserts three-copy byte equality, manifest hashes, attributes, and packaged-root resolution; sync tool now enforces empty-only `edge_overrides` (validator divergence closed). TS-08 solving and geometry stay Godot-only — the server holds tiles/elevations/edges, never geometry. Not wired into matches (N6); no match kind, snapshot changes, or units |
| **N6** | **Done (2026-08)** | Snapshot v3 + server-fed client world bootstrap (no gameplay). **Server:** opt-in `match_kind: "world_map"` on `POST /v1/matches` (optional `map_id`, default `handdrawn_test_map_full_01`; unknown kind/map → 400) via `server/app/domain/world_match.py`; snapshot v3 = `MapIdentity.to_dict()` (`map`) + `revision` + `turn_state` (+ `player_factions` after auto-start), **no embedded tiles/edges/terrain/geometry**; `match_kind`/`map_id` in meta and lobby rows for world matches only (absent for legacy); staging/auto-start reused unchanged; `actions` and `legal-actions` returned an explicit **409** for `world_map` matches immediately after snapshot load (interim guards — removed when N7a/N7b landed). **Client:** `game/cloud/world_snapshot_bootstrap.gd` loads canonical content by `map_id` (manifest lookup in `map_content_loader.gd`) and verifies schema version + raw-byte `content_hash` against the server identity — mismatch/missing content fails explicitly, never a silent fallback (verified in the Godot bootstrap tests); production scene `game/cloud/world_play/cloud_world_play.tscn` builds the shared `TerrainWorld` + N4 anchor UI; `BootIntent.match_kind` routes all five transitions (env-create, create→staging, lobby join, saved resume, staging→gameplay) — legacy stays on `main.tscn`. Legacy v2 flow untouched; default entry unchanged until N9 |
| **N7a** | **Done (2026-08)** | Server-authoritative world units + actions on the `world_map` match kind: snapshot v3 **`units`** (minimal rows sorted by id, settler/warrior, **no HP or movement points**), server-owned map-keyed spawn table validated against canonical content at creation (exactly two distinct integer `player_ids`; divergence fails creation — never a partial match), world **`move_unit`**/**`end_turn`** with locked first-failure rejection orders, movement v1 legality **exclusively** from the authoritative Python `WorldMap` (adjacency via canonical deltas; smooth edge permits, cliff blocks, missing edge record fails closed; occupancy blocks), **fail-closed map-identity verification** before every world mutation (HTTP 500, no state change), events + `state_hash` as legacy; the interim N6 409 guards removed. No client-side legality, ever ([CLOUD_API_V0.md](CLOUD_API_V0.md), [MOVEMENT_RULES.md](MOVEMENT_RULES.md), [UNITS.md](UNITS.md), [ACTIONS.md](ACTIONS.md)) |
| **N7b** | **Done (2026-08)** | World `legal-actions` (`server/app/domain/world_legal_actions.py`): legacy-shaped read-only envelope for `world_map` matches behind a seat-token credential gate (host token may query that match's players; fails closed without meta); summary mode = submit-ready `end_turn` + per-unit legal-move counts; selected-unit mode = submit-ready `move_unit` rows in canonical `DIRECTIONS` order filtered through the **same N7a validators** — every advertised action submit-ready by construction; strictly read-only |
| **N7c** | **Done (2026-08)** | Client unit projection: `cloud_world_play` renders snapshot units as the existing 3D settler/warrior characters at the N4 `TerrainWorld.tile_anchors` (`game/presentation/world/world_units_view.gd`: one stable root per unit id, snapshot reconciliation without duplicates, no origin fallback, no client-invented unit state); locked matte per-instance unit-render profile + MSAA 2×/FXAA world-viewport AA ([UNITS.md](UNITS.md)). No selection or action submission |
| **N7d** | **Done (2026-08; manual/visual gate passed 2026-08-06)** | Client world interaction loop (client-only, shipped in `cloud_world_play` + `world_interaction_state.gd` + `world_destination_markers.gd`): unit selection from terrain picks, **server-fed** legal destinations/actions rendered as markers (one-to-one with served rows), `move_unit`/End Turn submission of exact served rows under the locked freshness contract, out-of-turn snapshot polling, minimal turn/status + rejection UI, and the dev-only **one-PC debug mode** (`EOM_CLOUD_ONE_PC_DEBUG=1`, world_map + loopback + host token only — one Godot client controls both players in turn per the locked dual-entry direction) — no combat, cities, or movement animation. **Niclas passed the manual/visual gate using one local FastAPI process + one Godot instance in the one-PC debug mode** (genuine two-client/local-and-remote verification is N7e; see **Planned N7d–N8d** below) |
| **N7e** | **Done (2026-08-06)** | N7 verification checkpoint closed (docs-only): coverage audit found every N7 contract point already proven (no new tests); server `slice n7` 86 passed, Godot `slice n7` 6/6 suites, `smoke` 11/11 — no defect. **Local two-client gate PASSED** (one local FastAPI server, two front-door clients `EOM_CLOUD_PROFILE=A/B`, UI create + lobby join, movement and End Turn handoff in both clients). **Hetzner two-client gate WAIVED BY PROJECT OWNER — NOT RUN** (no deploy refresh, reconnect test, or image-content check; explicit decision: automated coverage + the passed local gate accepted for N7e completion — remote validation moves to the next deploy refresh). **N7a–N7e complete; next slice N7f** ([VALIDATION_CHECKLIST.md](VALIDATION_CHECKLIST.md)) |
| **N7f** | **Implemented (2026-08-06; manual/visual gate PENDING)** | Unit locomotion presentation: the authoritative root still snaps to its N4 anchor immediately while the visual glides one straight segment at `LOCOMOTION_SPEED_UNITS_PER_SEC` (1.6 world units/s) with semantic Walking → Idle_3 clip transitions and deterministic yaw-only facing — the body stays UPRIGHT (world +Y) with the locked effective −Z forward along the movement direction (both rigs are authored facing +Z, corrected once by the shared convention-level mount yaw); terrain contact is skeletal (`WorldUnitLegGrounder`: per-foot top-surface targets, joint two-leg pelvis solve with reach-feasibility intervals, analytic two-bone knee bend toward the rig-derived **anatomical pole** — deterministic forward branch, no backward knee or single-frame snap on steep uphill — extension margins, **continuous whole-foot sole alignment** to each foot's own sampled normal with anatomical clamps and swing/contact blending, and pose-derived uphill swing clearance that is zero at takeoff/landing) over top-surface-only sampling (`WorldSurfaceSampler`); third-review follow-up 2026-08-07: **sole-contact calibration** (in contact the ankle target blends to terrain + rest ankle height — the exact contact height on the audited rigs — removing the hover the remapped clips bake in by holding feet above rest) and **stationary foot planting** (feet anchored in ground space while not gliding — position and normal-aligned orientation pinned, idle pelvis motion passes through, smooth release/replant around glides); presentation-only — never a legality/authority change; gates nothing in N7g/N8 (below). Niclas's movement-read approval is outstanding ([VALIDATION_CHECKLIST.md](VALIDATION_CHECKLIST.md)) |
| **N7f.1** | **Implemented (2026-08-07) — one-PC/manual gate PENDING** | Deterministic client **arrival gate** for accepted world-unit moves: entered ONLY after an accepted `move_unit` response with a usable authoritative snapshot, bound to the exact moved unit id + accepted revision (`world_interaction_state.gd`); the snapshot and the authoritative root still apply/snap IMMEDIATELY — only further local input waits. While gated: every terrain gameplay pick is inert, End Turn is disabled, destination rows are hidden/unsubmittable, no summary/selection legality is fetched, the moved-unit selection/highlight is preserved, and camera orbit/pan/zoom + F12 capture stay usable (`_request_busy` remains a separate transport concern). Released ONLY by the gated unit's REAL visual arrival (`WorldUnitsView.unit_arrived`, emitted exactly once per completed glide at the exact final-anchor pose — never for spawn, identical reapply, idle, degenerate settlement, or mid-glide removal), then current-revision summary + still-valid-selection legality is refetched — markers/End Turn return only from those fresh served rows. Safe resolution paths: rejection/transport failure/accepted-without-snapshot (visible failure) never gate; gated-unit removal, turn loss, different-revision snapshots, degenerate settlement, and teardown release without deadlock; reconnect/bootstrap never infers a gate; the mid-glide retarget capability stays for authoritative reconciliation. **Permanent boundary rule ([CLOUD_PLAY.md](CLOUD_PLAY.md)):** the client arrival gate is pacing/visibility only — mandatory future on-entry outcomes must be resolved atomically by the server with movement or as server-owned pending interaction state, never enforced solely by this gate. Niclas's one-PC gate (rapid clicking, hidden controls while walking, re-enable at arrival) is outstanding |
| **N7g** | **In progress — N7g.1 server authority implemented (2026-08-07); N7g.2 legal-actions + N7g.3 client PENDING** | World Combat 0.1: server-authoritative `attack_unit` on world matches with exact Local Combat 0.1 math parity — **warrior-vs-warrior only (locked)**; **additive** snapshot v3 unit `current_hp` + per-turn attacked flag; served attack rows; minimal client feedback — contracts locked by review 2026-08-06 (below). **N7g.1 (implemented):** snapshot combat fields, world `attack_unit` validation/resolution/persistence via the shared pure Local Combat 0.1 core, `unit_already_attacked` move gating, and the end-turn `has_attacked` reset ([CLOUD_API_V0.md](CLOUD_API_V0.md)); attacks are NOT yet served in legal-actions and there is no client combat work |
| **N8a** | Planned | Minimal world cities: world `found_city` (settler consumed), **additive** snapshot `cities` + `next_city_id`, city rendering + selection at anchors — no territory, growth, population, or buildings (below) |
| **N8b** | Planned | Flat yields v2 + production selection: world `set_city_production` (`produce_unit:warrior` / `produce_unit:settler` / `none`, **no unlock gating — locked**), **additive** city `current_project`, **flat per-city production yield** on the existing canonical schema v1 — reads no tile properties, no content-schema expansion (below) |
| **N8c** | Planned | Authoritative production processing + deterministic spawn (**requires N7g**, locked legacy-equivalent timing): world `end_turn` ticks the ending player's production, advances the turn, then **delivers completed units for the player who has just become current** (**additive** `next_unit_id`; producer city tile if unit-unoccupied, else first unit-unoccupied smooth-adjacent tile in `DIRECTIONS` order, else deferred with retained progress); event order `production_progress`* → `end_turn` → `unit_produced`* (below) |
| **N8d** | Planned | **First complete two-player `WorldMap` gameplay loop** checkpoint: deterministic full-loop server integration test + two-client manual gate covering the eight target-loop points; `VALIDATION_CHECKLIST.md` — milestone gate before any N9 work (below) |
| **N9** | Planned | Full cutover + legacy removal: default-entry and `BootIntent` cutover, snapshot v2 retirement, legacy match-creation removal, removal of both Python and GDScript `HexMap`, removal or migration of category-dependent legacy rules, 2D renderer removal |

### Planned N7d–N8d — path to the first complete two-player `WorldMap` gameplay loop

**Target loop (must all hold at the end of N8d):** (1) two clients alternate authoritative turns; (2) units move using server-provided legal actions; (3) warriors can attack, take damage, and eliminate units; (4) settlers can found cities; (5) cities are visible and selectable; (6) a player can choose a minimal production project (Warrior or Settler); (7) production advances through authoritative turn processing; (8) completed units spawn deterministically and enter the continuing game loop.

**Sequencing.** Recommended order: **N7d → N7e → N7f → N7g → N8a → N8b → N8c → N8d**. Hard dependencies: N7d ← N7a–c; N7e ← N7d; N7g ← N7d; N8a ← N7d; N8b ← N8a; **N8c ← N8b + N7g** (produced units require the N7g `current_hp` and `has_attacked` fields); N8d ← N7d/N7e/N7g/N8a–N8c. **N7f depends only on N7d and gates nothing** — it may land any time before N8d without blocking N7g/N8. N7g and N8a are mutually independent (either order works); the recommended order keeps combat inside the N7 unit-action family.

**Standing constraints (every slice below).** Server authority and **served legality only** — clients never compute world legality; deterministic snapshots, `state_hash`, and events through the existing envelope (`canonical_json`); canonical content **schema v1 untouched** — no water, terrain-category, or passability fields (any such change needs a separately justified schema slice); snapshot v3 evolves **additively only**; flat initial yields and deliberately minimal city/production rules; no new terrain, camera, or asset work (existing GLBs/markers/UI patterns reused in place); no new compatibility investment in the deprecated legacy path (`main.tscn`, snapshot v2, `HexMap`); **N9 remains full cutover + legacy removal** and is not pulled forward. **Alpha-store compatibility (locked):** required world snapshot-shape expansions through N8c are **not migrated** — whenever a slice extends the world snapshot shape, affected existing `world_map` matches must be recreated after deployment (dev/alpha store; applies to every shape-extending slice, not only N7g). World-match creation stays env-opt-in (`EOM_CLOUD_MATCH_KIND=world_map`) through N8 — front-door world-creation UI is **not** part of this plan.

#### N7d — Client world interaction loop

**Status: Done (2026-08) — manual/visual gate passed by Niclas on 2026-08-06.** Deterministic coverage: Godot `slice n7d` (state machine, markers, scene wiring) + `slice n7`; server `slice n7` untouched and green.

- **Objective:** first playable server-fed interaction on world matches: select an own unit, see served legal destinations, move, End Turn, follow the opponent's turn. Prereqs: N7a–N7c.
- **Authoritative changes:** none — the server is untouched; the N7a/N7b wire contracts are consumed as-is.
- **Client work (`cloud_world_play` + presentation/world):** unit selection driven by the locked N4 pick contract (`terrain_picked`): a tile pick on a tile holding an own unit selects that unit (presentation state only); a miss clears; a cliff pick leaves selection unchanged; **out of turn every pick — including an empty miss — is completely inert** (turn ownership is checked before miss-clear semantics). On selection, `GET .../legal-actions?selected_unit_id=…`; the served `move_unit` rows are rendered as destination markers at the corresponding `tile_anchors` — the marker set is exactly the served rows, never client-derived. Clicking a marked destination POSTs **that exact served action row**; the accepted response snapshot replaces the held snapshot and units re-render at their new anchors (instant reposition — movement animation is N7f). End Turn control POSTs the summary-mode submit-ready `end_turn`. **Served-legality freshness (locked contract):** the summary-mode `end_turn` row and the selected-unit `move_unit` rows are **two independent served-state slots, each bound to the current revision** — every new own-turn snapshot revision refetches the summary row (and, when a valid selection survives, the selection rows); accepting either response never clears the other; a newer snapshot clears both immediately; a selection change refetches only selection legality while a fresh same-revision summary row stays usable, so after an accepted move End Turn becomes available again from a **newly served** summary row even while the moved unit remains selected. Every response is bound to its request serial, its returned `revision`, the requesting actor, and the **requested selection mode** — the echoed `selected_unit_id` must match the request (null for summary, the exact unit id for selection); stale or mismatched responses are discarded, never rendered; `end_turn` is never constructed client-side and nothing is retained across revisions; a served row is **never submitted** when its bound `revision` differs from the held snapshot `revision` — the client refetches instead. Minimal turn/status UI: current player + own seat identity from `turn_state`/staging identity (reusing the existing display-name helpers), plus rejection/error surfacing. Out-of-turn: action input disabled; conservative revision-based snapshot polling of `GET /v1/matches/{id}` (reusing the shipped poll-gating pattern from the legacy cloud waiting flow — no websockets, no event replay), applying newer revisions to the unit view. **One-PC debug mode (locked dual-entry direction, dev-only):** explicit `EOM_CLOUD_ONE_PC_DEBUG=1` opt-in, valid only for `world_map` against a loopback server (`127.0.0.1`/`localhost`; `EOM_CLOUD_DEBUG` stays logging-only) — a fresh env-driven match is driven to ongoing through the **normal staging APIs** (create → adopt the returned host token → claim both seats with their own returned tokens → assign the first two distinct server-advertised civilizations deterministically → ready both seats → fetch the ongoing snapshot; no server bypasses); during play the effective actor **follows the authoritative snapshot's current player** (an accepted End Turn rebinds to the new current actor, clears selection/markers/both served slots, and fetches that actor's fresh summary legality, so the next player is immediately controllable in the same window); host-token authority is used only in this mode; responses stay bound to actor/revision/mode so previous-actor responses can never render or submit; actions remain exact served rows. Normal seat-token/`EOM_CLOUD_PROFILE` multiplayer semantics are completely unchanged when the flag is absent.
- **Verification:** Godot headless tests — pick→selection mapping (incl. cliff-pick unchanged + miss-clear), served-row→marker mapping with no client legality, exact submitted payloads, poll gating states, End Turn flow, **and the served-legality freshness contract** (stale async legal-actions responses discarded on selection change and on revision change; markers cleared + refetch triggered when a newer snapshot arrives with a still-valid selection; submission blocked when the served rows' revision differs from the held snapshot revision); one-PC debug coverage (activation guards, fresh create → normal staging APIs → ongoing, same-client controllability handoff, actor-change invalidation, previous-actor response discard, unchanged fixed-seat behavior when off); server slice `n7` suites stay green untouched.
- **Manual/visual gate (passed 2026-08-06):** **one local authoritative FastAPI process + ONE Godot instance** in the one-PC debug mode (`EOM_CLOUD_ONE_PC_DEBUG=1`), controlling both players in turn per the locked dual-entry direction. Niclas confirmed selection/movement and End Turn handoff for both players in the same window. Instant reposition and unchanged facing were accepted as expected N7d behavior; locomotion/facing remain N7f. Genuine two-client verification (two `EOM_CLOUD_PROFILE` instances, local and remote authority) belongs to **N7e**, not this gate.
- **Non-goals:** combat, cities, walking animation/facing, camera changes, websockets/SSE, event replay, legal-actions caching, any client-side legality, front-door UI changes.
- **Done / merge boundary:** the one-PC debug client can alternate authoritative turns for both players with all legality served; normal fixed-seat multiplayer semantics remain intact; client-only PR; legacy path untouched.

#### N7e — N7 verification checkpoint (closed 2026-08-06)

- **Objective:** declare the N7 movement/turn core verified before combat and cities build on it. Prereqs: N7d.
- **Scope:** tests + documentation only (a `VALIDATION_CHECKLIST.md` section; TESTING.md slice wiring if missing). Any defect found stops the checkpoint and is reported/fixed as its own slice — no drive-by production changes.
- **Result (2026-08-06):** closed. Deterministic suites green (server `slice n7` 86 passed; Godot `slice n7` 6/6 suites; `smoke` 11/11); coverage audit confirmed every N7 contract point — incl. content-drift HTTP 500 via `EMPIRE_MAP_CONTENT_DIR` (read-only, no mutation) and out-of-turn/cliff-blocked rejection through the real client path — was already proven, no new tests needed. **Local two-client gate PASSED** (two front-door `EOM_CLOUD_PROFILE=A/B` clients against one local FastAPI server: UI create + lobby join, movement + End Turn handoff in both clients). **Hetzner two-client gate (incl. reconnect mid-match) and the post-build image check WAIVED BY PROJECT OWNER — NOT RUN**; explicit decision: automated coverage + the passed local gate accepted for N7e completion, remote validation moves to the next deploy refresh. Exact procedures and results: [VALIDATION_CHECKLIST.md](VALIDATION_CHECKLIST.md).
- **Non-goals:** new gameplay, new endpoints, performance work.
- **Done / merge boundary (met):** checklist section recorded with results; N7a–N7e marked done; docs-only change. **Next slice: N7f.**

#### N7f — Unit locomotion presentation

**Status: implemented 2026-08-06 — manual/visual gate PENDING (not Done).** Clip audit passed before implementation: semantic `Walking`/`Idle_3` resolve through the audited remap to real shipped clips (settler `Running`/`Hit_Reaction_1`, warrior `Idle_02`/`Combat_Stance`; no clip carries non-skeleton root-motion position tracks). Rig audit (2026-08): both shipped rigs are AUTHORED facing +Z (glTF convention; toe-vs-ankle rest direction) — the character instance is mounted with one shared convention-level 180° yaw so the locked EFFECTIVE forward is local −Z; both rigs share the humanoid bone set `Hips` / `Left|RightUpLeg` / `Left|RightLeg` / `Left|RightFoot`. Locomotion layer in `world_units_view.gd` (root snaps to the anchor immediately, visual `ModelRoot` glides at `LOCOMOTION_SPEED_UNITS_PER_SEC = 1.6` world units/s ≈ 1.1 s per tile, yaw-only upright facing), `WorldSurfaceSampler` (top-surface-only raycast sampling, anchor-lerp fallback), `WorldUnitLegGrounder` (SkeletonModifier3D skeletal foot grounding, **uphill-grounding correction 2026-08-07**: joint two-leg pelvis solve via reach-feasibility intervals; analytic two-bone knee with an explicit per-leg anatomical pole from the audited rest toe-forward direction — never the current possibly-straight knee — with extension margins; continuous whole-foot sole alignment to each foot's own sampled normal with anatomical clamps and swing/contact blending; pose-derived bounded uphill-only swing clearance, zero at takeoff/landing; local-pose writes only; **third-review follow-up 2026-08-07:** sole-contact calibration — in contact the ankle target blends to terrain + rest ankle height, the exact contact height because both audited bind-pose soles sit exactly on the plane, removing the hover the remapped clips bake in by holding feet above rest — plus stationary foot planting: each foot of a non-gliding unit is anchored in ground space (position + normal-aligned orientation) with idle pelvis motion passing through and the plant weight blending smoothly around glide begin/arrival), production wiring + one-PC-debug F12 review screenshot in `cloud_world_play.gd`, and the fast `slice n7f` (217 checks incl. both-rig real-clip flat/shallow/medium/steep/downhill sequences and the planting/calibration regressions). Niclas's movement-read approval (pace, grounding, slope behavior) is outstanding — see the N7f section of [VALIDATION_CHECKLIST.md](VALIDATION_CHECKLIST.md).

- **Objective:** replace instant repositioning with readable movement: walking animation between anchors, facing along the movement direction, an upright body, and skeletal foot grounding on the rendered surface. Prereqs: N7d (gates nothing afterwards).
- **Authoritative changes:** none. Anchors remain the placement authority; interpolation between the old and new anchor is transient presentation state; grounding may sample the **rendered** surface/collision for visuals only — never for legality (N3c.4 boundary). The authoritative snapshot is applied immediately; only the visual catches up.
- **Client work:** `world_units_view.gd` locomotion layer using the existing audited GLB clips (walk/idle); deterministic facing rule (upright yaw-only body, locked effective −Z forward along the movement direction — terrain never tilts the whole character); `world_unit_leg_grounder.gd` skeletal grounding (post-animation pose override); no new assets — if a required clip does not exist in the shipped GLBs, the slice stops and reports instead of importing assets.
- **Verification:** headless tests for facing/interpolation math determinism and final-pose equality with the anchor; preview/screenshot support for review.
- **Manual/visual gate:** required — Niclas approves the movement read (pace, grounding, slope behavior).
- **Non-goals:** combat animation, camera follow, path smoothing across multi-step moves, unit variety, new animation assets.
- **Done / merge boundary:** approved visual result with all suites green; client-only PR.

#### N7g — World Combat 0.1

- **Objective:** warriors can attack adjacent enemy warriors with deterministic damage, retaliation, and elimination — target-loop point 3. Prereqs: N7d (N7e recommended first).
- **Status:** sub-sliced 2026-08-07. **N7g.1 — server authority (implemented 2026-08-07):** authoritative state, `attack_unit` validation/resolution/persistence/turn gating exactly per the locked contracts below (literal reasons finalized in [CLOUD_API_V0.md](CLOUD_API_V0.md); resolution extracted into the shared pure `combat_rules.resolve_combat` core consumed by BOTH the legacy Scenario path and `world_actions` — one formula, no drift, no world-to-Scenario adapter). **N7g.2 — served attack rows (PENDING):** the legal-actions bullet below. **N7g.3 — client combat work (PENDING):** the client-work bullet below. N7g overall stays incomplete until all three land plus the manual gate.
- **Placement validated:** combat belongs in the **N7 unit-action family**, not N8 — it depends only on units/adjacency/edges (no yields or cities), and N8 stays purely economic. `N7g — Combat 0.1` is confirmed as the correct boundary.
- **Authoritative state (additive snapshot v3):** unit rows gain **`current_hp`** (int; full = server unit-definitions `max_hp`, today 100 — max stays registry data, not snapshot state) and **`has_attacked`** (bool; reset for all units on every accepted `end_turn`). Existing `world_map` matches affected by the shape expansion are recreated after deployment per the locked alpha-store rule above.
- **Action / legality (locked 2026-08-06):** world **`attack_unit`** with the exact legacy wire shape (`schema_version` 1, `actor_id`, `attacker_id`, `defender_id`). Resolution reuses the **canonical Local Combat 0.1 math verbatim** (`BASE_DAMAGE` 30, `exp((atk−def)/25)` scaling, clamp 1–100, retaliation only if the defender survives, elimination at 0 HP, attacker never advances into the tile) — Combat 0.1 is **warrior-vs-warrior only**: warrior attacker **and** warrior defender; attacks on non-warrior units (e.g. settlers) are **outside N7g by decision**, not an open question. Locked world-specific rules: melee requires a **traversable (smooth) edge** — a cliff or missing edge record blocks the attack fail-closed (single edge-legality source shared with movement); after attacking, the unit can neither move nor attack again until its owner's next turn (`has_attacked` checked in move validation — mirrors the legacy “attack sets `remaining_movement` to 0” without introducing movement points); pre-attack movement stays budget-free (move-then-attack allowed). Planned first-failure order (literal reasons finalized with the implementation in [CLOUD_API_V0.md](CLOUD_API_V0.md)): `wrong_action_type → unsupported_schema_version → malformed_action → not_current_player → unknown_attacker → unknown_defender → actor_not_owner → attacker_not_warrior → defender_not_warrior → cannot_attack_own_unit → attacker_already_attacked → defender_not_adjacent → attack_edge_missing → attack_cliff_blocked`; map identity resolved fail-closed before destination-side checks, as N7a.
- **Snapshot / events / turn processing:** accepted attacks bump `revision`, persist, and append one event with the legacy combat fields (strengths, HP before/after, damage taken, killed flags, `retaliated`); eliminated units leave `units`; `end_turn` apply additionally clears every `has_attacked` flag.
- **Legal-actions (N7g.2, PENDING — not part of N7g.1):** a selected own **warrior** additionally returns submit-ready `attack_unit` rows (adjacent enemy warriors over traversable edges), in canonical `DIRECTIONS` order of the defender tile; summaries count them.
- **Client work (N7g.3, PENDING — not part of N7g.1):** attack-target markers from served rows (distinct from move markers), submission of exact served rows, HP shown minimally (selection/status line), eliminated units disappear on snapshot apply. No clash animation (the legacy `CombatClashBurstView` is not reused).
- **Verification:** server tests — full rejection order, math parity against the legacy `combat_rules` constants, retaliation/elimination/flag-reset invariants, drift-500 read-only (N7g.1 part landed: `server/tests/test_world_combat_v3.py`, in server `slice n7`), legal-actions round trip (every advertised attack accepted on an equivalent match — N7g.2); Godot tests — marker mapping, payloads, HP/elimination rendering (N7g.3); two-client manual combat session.
- **Manual/visual gate:** short two-client combat exchange approved by Niclas.
- **Non-goals:** attacks on non-warrior defenders (locked out of Combat 0.1 — any future warrior-vs-settler rule is a separately approved slice), ranged/city combat, terrain/elevation combat modifiers, movement points, zone of control, combat animation, AI.
- **Done / merge boundary:** all target-loop point-3 behavior server-authoritative and playable by two clients; one PR (server + client + docs).

#### N8a — Minimal world cities + `found_city`

- **Objective:** settlers found cities; cities are visible and selectable — target-loop points 4–5. Prereqs: N7d.
- **Authoritative state (additive snapshot v3):** **`cities`** (deterministic rows sorted by `id`: `{"id", "owner_id", "position": [q, r], "name"}`) and **`next_city_id`**; names reuse the canonical rule (`Capital`, then `Settlement 2`, … per owner). World **`found_city`** (legacy wire shape: `schema_version` 1, `actor_id`, `unit_id`, `position`) consumes the founding settler. Planned first-failure order (literal reasons finalized with the implementation): `wrong_action_type → unsupported_schema_version → malformed_action → not_current_player → unknown_unit → unit_not_owned_by_player → unit_cannot_found_city → unit_not_at_position → tile_already_has_city` (no water/territory reasons — schema v1 has neither; founding legality never reads elevation). **Locked (2026-08-06):** cities do **not** block unit movement (`destination_occupied` stays units-only); N8 has **no minimum city distance** — after the standard action/unit/map validation, an existing city on the founding tile is the **only** city-placement restriction.
- **Events / turn processing:** accepted founding bumps revision, persists, appends a legacy-shaped `found_city` event; no ticks on founding.
- **Legal-actions:** a selected own settler additionally returns the submit-ready `found_city` row when its tile has no city; `city_summaries` lists the actor's cities (empty action lists for city selection until N8b).
- **Client work:** `WorldCitiesView` following the `world_units_view.gd` pattern — one stable root per city id at the tile anchor, reusing an existing city marker/asset in place (no new assets); “Found City” affordance when a served row exists; city selection via tile pick with the **locked (2026-08-06) shared-tile rule**: a tile with only one selectable object selects it directly; when both a selectable unit and a city occupy the tile, the first pick selects the **unit**, and repeated picks on the unchanged tile **alternate deterministically** between city and unit; changing tile or clearing the selection **resets the cycle**; visible feedback must always identify the selected object clearly (reviewed by the N8a manual gate); minimal selected-city status line.
- **Verification:** server tests — rejection order, settler consumption, deterministic ids/names, drift-500, legal-actions round trip; Godot tests — city rendering/reconciliation, selection cycling, found-city submission; two-client founding session.
- **Manual/visual gate:** city marker placement/readability **and** shared-tile selection feedback (unit-vs-city cycling is legible: the player can always tell which of the two is selected) approved.
- **Non-goals:** territory/owned tiles, population/growth/food, buildings, borders, city panels beyond the status line, city combat.
- **Done / merge boundary:** two clients can found and see cities; one PR.

#### N8b — Flat yields v2 + production selection

- **Objective:** a player can choose a minimal production project — target-loop point 6 — and the flat yield base for authoritative processing exists. Prereqs: N8a.
- **Yields v2 (initial instantiation, locked 2026-08-06):** flat production is **1 per city on each accepted owner `end_turn`** — a constant read from server-owned rules data, **reading no tile properties** (works on canonical schema v1 exactly as-is; MAP_MODEL.md layer 9 “flat base yields”). Explicitly a **balance placeholder, not final balance**. No food, science, or coin on the world path in N8; per-tile/worked-tile yields, population, and richer yield content stay N9+ evaluation.
- **Authoritative state (additive):** city rows gain **`current_project`** (`null` or `{"project_id", "progress", "cost"}`); costs come from the existing server `CityProjectDefinitions` registry (`produce_unit:warrior` **2**, `produce_unit:settler` **2** — explicitly balance placeholders, not final balance). World **`set_city_production`** (legacy wire parity: `schema_version` **2**, `project_id` ∈ `produce_unit:warrior` | `produce_unit:settler` | `none`). **Locked (2026-08-06): no unlock gating** — both `produce_unit` projects are **always selectable** in N8; there is no world `progress_state`, science, or unlock system on the `WorldMap` path in N8 (`city_project_not_unlocked` does not exist on the world path). Planned first-failure order (literal reasons finalized with the implementation): `wrong_action_type → unsupported_schema_version → malformed_action → not_current_player → unknown_city → city_not_owned_by_player → unknown_city_project → project_already_set`.
- **Events:** accepted selection bumps revision, persists, appends a legacy-shaped `set_city_production` event; no tick on selection (processing is N8c).
- **Legal-actions:** a selected own city returns submit-ready `set_city_production` rows for the available projects (+ `none` handling per the legacy envelope).
- **Client work:** minimal production UI on the selected own city — project choices from served rows plus a progress/cost line; nothing else.
- **Verification:** server tests — rejection order, project registry reuse, no-unlock-gating behavior, drift-500, round trip; Godot tests — panel rows from served actions only, payloads; two-client selection session.
- **Manual/visual gate:** production-choice UI readability approved (project choices legible on the selected city; the progress/cost line updates correctly as snapshots advance).
- **Non-goals:** science/progress/research on the world path, food/growth, buildings, per-tile yields, worked tiles, yield overlays, balance tuning.
- **Done / merge boundary:** production choices are server-validated and visible to both clients; one PR.

#### N8c — Authoritative production processing + deterministic spawn

- **Objective:** production advances through authoritative turn processing and completed units spawn deterministically into the continuing loop — target-loop points 7–8. Prereqs: **N8b and N7g** (produced units carry the N7g `current_hp` and `has_attacked` fields).
- **Turn processing (locked 2026-08-06 — legacy-equivalent timing):** on an accepted world `end_turn` by player P, in this order inside one apply: **(1) production tick** — for each of P's cities in ascending city-id order with a non-null, **not yet completed** project: `progress += flat production yield` (**`progress >= cost` means completed/ready; completed projects no longer accrue production**); **(2) turn advance** — `turn_state` advances and every `has_attacked` flag clears (N7g rule); **(3) delivery for the player who has just become current** — for each of that player's **ready** cities in ascending city-id order, attempt deterministic placement: the producer city tile if **unit-unoccupied**, otherwise the first unit-unoccupied tile adjacent over a **smooth** edge in canonical `DIRECTIONS` order, with **occupancy updated after every successful spawn** (an earlier spawn in the same delivery pass blocks later ones); only after successful placement is `next_unit_id` allocated (then incremented; **additive** snapshot field introduced here), the unit spawned with full `current_hp` and `has_attacked` false, `unit_produced` emitted, and `current_project` cleared to `null`; if no placement exists, the completed project **and its progress are retained unchanged** and the attempt repeats the next time the owner becomes current — no unit is lost, nothing random. Consequently a produced unit becomes available exactly when its owner gains control and **cannot be attacked during the intervening opponent turn** (it does not exist yet), matching the legacy delivery guarantee.
- **Events (locked order):** `production_progress`* (tick, ending player) → `end_turn` (the accepted action row) → `unit_produced`* (delivery, new current player) — legacy event names, fields mirroring the legacy rows where semantics match. The POST response's primary **`event`** and **`index`** remain the accepted **`end_turn`** row, as on the legacy path.
- **Legal-actions:** unchanged shapes; new units simply appear in summaries/moves.
- **Client work:** none beyond existing snapshot reconciliation (N7c roots handle new unit ids); production progress line updates from the snapshot.
- **Verification:** server tests — accrual/cost determinism, completed-projects-stop-accruing, delivery-on-becoming-current timing (produced unit absent during the intervening opponent turn and not attackable then), occupied-city-tile fallback order with per-spawn occupancy updates across multiple ready cities, deferred-delivery retention and retry, id sequencing, the locked `production_progress* → end_turn → unit_produced*` event order with the `end_turn` response `event`/`index`, drift-500; Godot test — produced unit appears at the correct anchor when its owner becomes current; two-client production round.
- **Non-goals:** production overflow carry-over policy beyond retained progress, build queues, repeat production, purchase/rush, city growth.
- **Done / merge boundary:** a full produce→spawn→act cycle works for both clients; one PR.

#### N8d — First complete two-player `WorldMap` gameplay loop (checkpoint)

- **Objective:** verify the eight-point target loop end-to-end and record the milestone. Prereqs: N7d, N7e, N7g, N8a–N8c (N7f recommended for presentability but not a functional dependency).
- **Scope:** tests + documentation. One deterministic server integration test scripts the whole loop on the reference map (moves, an attack with elimination, founding, production selection, accrual across turns, spawn, and continued play by the spawned unit); Godot suites cover the client sides already landed per slice.
- **Verification:** full relevant slice profiles green (server `n7`/`n8`-family, Godot world-play suites, `smoke`); manual two-client session against the remote authority walking all eight points, recorded in `VALIDATION_CHECKLIST.md`; refreshed deploy validated with the post-build image content check.
- **Manual gate:** Niclas plays one full two-player loop session.
- **Non-goals:** any new gameplay, balance, N9 cutover work, front-door world-creation UI.
- **Done / merge boundary:** checklist milestone recorded — **the first complete two-player `WorldMap` gameplay loop exists**; N9 planning may start afterwards; docs/tests-only PR.

#### Gameplay contracts — locked by review (2026-08-06)

The plan deliberately does **not** silently canonize new gameplay rules; everything not listed here reuses existing canonical contracts (Local Combat 0.1 math, legacy wire shapes, project registry, city naming, event names). **All twelve contracts below are locked — no gameplay contract in this plan remains in proposed state.**

1. **N7g attack gating without movement points:** additive per-unit `has_attacked` flag; a unit that attacked can neither move nor attack again until its owner's next turn; pre-attack movement stays budget-free (move-then-attack allowed). Mirrors the legacy “attack sets MP to 0” using minimal deterministic state instead of importing a movement-point system.
2. **N7g melee edge rule:** attacks require a traversable (smooth) edge; cliff or missing edge record blocks fail-closed. One edge-legality source for movement and melee.
3. **N7g defender restriction:** Combat 0.1 is **warrior-vs-warrior only**. Warrior-vs-settler (or any non-warrior defender) is **explicitly outside N7g** — a future rule would be its own separately approved slice, not an open N7g question.
4. **Alpha-store compatibility (generalized):** required world snapshot-shape expansions **through N8c** are not migrated; affected existing `world_map` matches are recreated after deployment (applies to every shape-extending slice — N7g, N8a, N8b, N8c — not only pre-N7g matches).
5. **N8c delivery timing (legacy-equivalent):** production tick for the ending player **before** turn advance; turn advances; **delivery for the player who has just become current** — a produced unit becomes available when its owner gains control and cannot be attacked during the intervening opponent turn. Event order `production_progress`* → `end_turn` → `unit_produced`*; the POST response's primary `event`/`index` remain the accepted `end_turn`.
6. **N8c deferred delivery:** `progress >= cost` = completed/ready; completed projects no longer accrue; deterministic placement when the owner becomes current (producer city tile if unit-unoccupied, else first unit-unoccupied smooth-adjacent tile in canonical `DIRECTIONS` order); no placement → completed project and progress retained unchanged, retry the next time the owner becomes current; `next_unit_id` allocated, `unit_produced` emitted, and `current_project` cleared **only after successful placement**; ready cities processed in ascending city-id order with occupancy updated after every successful spawn.
7. **Id counters:** additive snapshot `next_unit_id` (N8c) and `next_city_id` (N8a) rather than deriving ids from max-existing (stable under elimination).
8. **N7d served-legality freshness:** summary (`end_turn`) and selection (`move_unit`) legality are two independent served-state slots bound to the current revision — every own-turn revision refetches summary (plus selection when a valid selection survives); accepting one never clears the other; newer snapshots clear both; selection changes refetch only selection legality while a fresh same-revision summary row stays usable (End Turn re-enables from a newly served row after an accepted move even with the unit still selected). Responses are bound to request serial, returned revision, actor, and requested selection mode (echoed `selected_unit_id` verified — null for summary, exact unit for selection); mismatched or stale responses discarded unrendered; nothing retained across revisions; never submit a row whose bound revision differs from the held snapshot revision.
9. **N8a city passability & spacing:** cities do not block unit movement; N8 has no minimum city distance; after the standard action/unit/map validation, an existing city on the founding tile is the **only** city-placement restriction.
10. **N8a shared-tile selection:** a tile with only one selectable object selects it directly; when a selectable unit and a city share the tile, the first pick selects the unit and repeated picks on the unchanged tile alternate deterministically between city and unit; changing tile or clearing selection resets the cycle; visible feedback must always identify the selected object clearly (presentation-only; legibility reviewed by the N8a manual gate).
11. **N8b no unlock gating / no world science in N8:** both `produce_unit:warrior` and `produce_unit:settler` are always selectable; the `WorldMap` path carries no unlock gating, world science, or `progress_state` in N8. Science/research on the world path is a post-N8 decision.
12. **N8b flat yield value:** flat production **1 per city on each accepted owner `end_turn`**; registry costs stay **2** (Warrior) and **2** (Settler) → a unit every second turn. Explicitly **balance placeholders, not final balance**.

Decomposable parity slices (terrain construction track; cross-linked to N2–N4 above):

1. **Canonical logical-map input.** **Done (Slice B+C).** The fixed hand-authored grid is extracted to `content/maps/reference/handdrawn_test_map_full_01.json` (JSON envelope v1; see [MAP_CONTENT.md](MAP_CONTENT.md)). Blender tooling consumes it via `eom_map_content.py`. Godot `WorldMap` loading is **N1**.
2. **Deterministic reference dataset.** **Done (N2, 2026-08).** Exported solved heights / cut-lattice topology from the accepted TS-08 Stage-0/2 chain (bpy-free) to `content/terrain/reference/handdrawn_test_map_full_01_ts08_stage2_reference_v1.json` — a **derived reference golden** for parity testing and audit (not the production terrain source; does not replace the solver). Regenerate/audit: `python tools/blender/terrain/export_ts08_reference_dataset.py export|check`; focused tests under `tools/blender/terrain/tests/`. See `content/terrain/reference/README.md`.
3. **Godot terrain construction.** **N3a done (2026-08):** cut-lattice topology (cliff classification, merge categories, seam identity) engine-native from **`WorldMap`**, parity-locked to N2 via `generate_ts08_n3a_parity_manifest.py` + headless Godot test `test_ts08_cut_lattice_n3a.gd`. **N3b done (2026-08, visually approved):** cut-domain thin-plate CG height solve engine-native (`Ts08HeightSolver`, domain-only, consumes only `WorldMap` + the N3a lattice), full 74,129-height numerical parity vs N2 via the test-only binary height golden (`generate_ts08_n3b_height_golden.py` + `test_ts08_height_solver_n3b.gd`), component/gauge routing per [TERRAIN_SURFACE_TARGET.md](TERRAIN_SURFACE_TARGET.md) (`test_ts08_height_solver_components.gd`), development-only preview scene `game/dev/terrain_preview/terrain_preview.tscn`. **N3c.1 done (2026-08):** domain-only surface geometry (`Ts08SurfaceGeometry`) — top surface plus Stage-3a cliff walls, wall-topology parity vs the accepted Python helper via `generate_ts08_n3c_wall_parity_manifest.py` + `test_ts08_surface_geometry_n3c.gd`; preview renders the walls. **N3c.6 done (2026-08):** first runtime-world integration — the shared runtime terrain world component plus a dev-only terrain runtime harness (dual-entry direction locked: the remote and the future local authoritative server both feed the same runtime world through the same client-server API path; server-fed `WorldMap` = N6). **N3c.7 done (2026-08, visually approved as an interim daytime environment):** deterministic production lighting rig (`game/presentation/world/terrain_lighting.gd`) owned by the shared runtime world; the procedural-sky backdrop is intentionally provisional (final sky/clouds/atmosphere are a separate future slice). **N3 terrain construction complete; N4 (world anchors + projected screen-space UI) done 2026-08; N5 (server `WorldMap` foundation + canonical content packaging), N6 (snapshot v3 + server-fed world bootstrap), and N7a–N7e (server-authoritative world units/movement/actions, served world legal-actions, client unit rendering, the client interaction loop, and the closed N7 verification checkpoint — local two-client gate passed, Hetzner gate waived by project owner) done 2026-08; next planned slice: N7f (unit locomotion presentation) — see “Planned N7d–N8d” above.**
4. **Godot mesh + material + collision.** Mesh from the solver-generated lattice; top-surface and stone cliff-wall materials; collision corresponding to the generated surface. **Top-surface splatting material done (N3c.3a, 2026-08):** `game/presentation/terrain_top_surface.gdshader` + `game/presentation/terrain_surface_material.gd` port the approved Blender three-layer baseline (dev preview consumer). **Cliff-wall stone material done (N3c.3b, 2026-08):** `game/presentation/terrain_cliff_wall.gdshader` + `game/presentation/terrain_cliff_wall_material.gd` port the accepted Stage-3a wall stone baseline with wall-local UVs and per-triangle tangents. **Collision done (N3c.4, 2026-08):** `game/presentation/terrain_collision.gd` derives deterministic top/wall `ConcavePolygonShape3D` collision exactly from the rendered N3c.1 geometry (derived data only — never authority).
5. **Parity audit + static scene.** Numerical and visual parity validation against the N2 golden; a static Godot scene rendering the terrain.

Parity requirements (related but **distinct** validation concerns — not one inseparable target):

- **Geometric surface and topology:** numerical parity against the reference dataset within documented tolerances — bit-identical floating-point output is **not** required. Exact topology comparison applies only where the Blender and Godot representations are deliberately constructed to match; surface-equivalent cliff-wall geometry with different triangulation may be acceptable subject to visual approval.
- **Material and camera:** visual parity judged against the accepted Blender render, not numeric comparison.
- **Collision:** must correspond to the generated surface; identical Blender topology is not required.

Must not (this milestone):

- **No** random/procedural generation of logical map layouts (deferred; the architecture must merely not preclude a future seeded generator).
- **No** gameplay/domain rule changes; the generated mesh never becomes authoritative gameplay state.
- **No** unit height-following movement or 3D unit presentation — that is a **post-parity slice** and is not part of terrain-parity acceptance.
- **No** cliff facade props / fitted cliff panels (the Stage 3b experiment is superseded), **no** water, **no** LOD or performance optimization passes, **no** runtime terrain editing.
- **No** new Blender runtime dependency in the game.

Validation:
Parity audit results per the reference contract; headless test suite stays green per [TESTING.md](TESTING.md).

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
