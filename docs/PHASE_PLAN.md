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

## Phase 3 — Game content foundation

Goal:
**Definitions** and **rules** for units, terrain, city projects, early tech/progress, and a first **faction / world** pass — **data- and domain-shaped**, not shipped balance.

Must not (roadmap):

- lock **final** numbers (costs, ranges, yields) — reserve tuning for **Phase 7**
- let presentation work **replace** **Phase 4** ownership of final visual identity

Note:
**Phase 3.x** may include **rendering unit types distinctly** (e.g. placeholder marker variation by unit type). **Final unit visuals** are **Phase 4.2**.

### Phase 3.0 — Content model checkpoint

Goal:
Align on how **definitions** live in the **domain** (IDs, registries, immutability, versioning) before expanding content surface.

### Phase 3.1 — Unit definitions

Goal:
**Unit types** (stats, roles, production prerequisites) as **data** + validation, separate from balance polish.

### Phase 3.2 — Terrain rules and movement costs

Goal:
Terrain affects **movement cost** and **legality** beyond Phase 1 neighbor rules; keep **`MovementRules`** (or successor) as the legality oracle.

### Phase 3.3 — City project definitions

Goal:
**City projects** / build-queue elements as structured definitions and actions.

### Phase 3.4 — First tech / progress definitions

Goal:
Minimal **tech** or **civic** **progress** slice: prerequisites and unlocks; full flavor leans on **Phase 6**.

### Phase 3.5 — First faction / world identity pass

Goal:
Early **faction** or **civ** knobs (traits, start-bias stubs) and **world** parameters — **mechanical** first; narrative depth in **Phase 6**.

Validation:
To be detailed per subphase; preserve **domain / presentation** split from [ARCHITECTURE_PRINCIPLES.md](ARCHITECTURE_PRINCIPLES.md).

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
