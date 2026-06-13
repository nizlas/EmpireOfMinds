# Progression Model

## Status and purpose

- This document defines the **systematic progression model** (sciences, breakthroughs, unlock targets, modifiers, detection) **and** records **implemented** progression/science slices (**Phase 3.4b–h**, **Phase 5.1.x**) alongside **future** design (capability/material roles, workbook-scale catalogs).
- **Phase 3.4a** was the **documentation checkpoint** that preceded registry work it names; **later 3.4 subphases shipped code** summarized in § Phase 3.4b–h below.
- It is **not** a substitute for **`ProgressDefinitions` / domain code** where those are authoritative—this is explanatory + forward design.
- It is **not** a **balance** exercise and does **not** canonicalize full workbook breadth (~200 breakthroughs, ~140 sciences).
- **Empire_of_Minds_Content_Workbook** and **[CONTENT_BACKLOG.md](CONTENT_BACKLOG.md)** are **non-canonical design raw material**, not runtime truth.
- **[CONTENT_MODEL.md](CONTENT_MODEL.md)** remains the **general content envelope** (IDs, registries, **`EffectiveRules`** / **`RuleSet` direction**, state vs definitions).

### Phase 3.4b status (implemented)

- **[ProgressDefinitions](../game/domain/content/progress_definitions.gd)** (`class_name` **`ProgressDefinitions`**) — tiny **metadata-only** registry with **five** seed **sciences** (`category` **`science`**, `era_bucket` **`ancient_foundations`**).
- **No** unlock gating, **no** breakthrough detection, **no** player progress state; `target_type` / `target_id` rows may reference **future** systems not yet implemented.

### Phase 3.4c status (implemented)

- **[ProgressState](../game/domain/progress_state.gd)** (`class_name` **`ProgressState`**) — **immutable** snapshot of **player-specific** **unlocked targets** (`target_type` + **`target_id`** rows; literal gate type **`"city_project"`** for **`SetCityProduction`** in this slice).
- **`GameState`** owns **`progress_state`** (**not** **`Scenario`**). **Default seed:** every **initial** **`turn_state.players`** id gets **`city_project` / `produce_unit:warrior`** and **`city_project` / `produce_unit:settler`** unlocked (**Phase 5.1.12d**); **`GameState.new(scenario)`** (omitted second arg) keeps that default.
- **`GameState.try_apply`**: after **`SetCityProduction.validate`** succeeds, **`set_city_production`** may be rejected with **`project_not_unlocked`** if the **actor** lacks that **`city_project`** unlock; **`SetCityProduction.PROJECT_ID_NONE`** is **never** gated.
- **`LegalActions`** mirrors the same rule when enumerating **`SetCityProduction`** for **`PROJECT_ID_PRODUCE_UNIT_WARRIOR`**. **`progress_state == null`** on a **synthetic shell** (`LegalActions` tests / helpers) keeps **legacy ungated** enumeration.
- **No** progress accumulation tied to **`ProgressDefinitions`**, **no** breakthrough detectors, **no** **`ProgressDefinitions`** consumption for **`SetCityProduction`**, **no** **`SetCityProduction`** schema changes.

### Phase 3.4d status (implemented)

- **[ProgressUnlockResolver](../game/domain/progress_unlock_resolver.gd)** — static **`complete_progress(state, owner_id, progress_id)`**: reads **`ProgressDefinitions`**, records **`completed_progress_ids`** on **`ProgressState`**, merges **`concrete_unlocks`** then **`systemic_effects`** into **`unlocked_targets`** (definition order for the delta list). **`future_dependencies`** are **not** applied to **`unlocked_targets`**.
- **`ProgressState`** holds **`completed_progress_ids`** per owner (sorted, deduped); **no** registry preload on **`ProgressState`**.
- In **3.4d** there was **no** **`GameState`** integration; **3.4e** adds the **`complete_progress`** player action path.

### Phase 3.4e status (implemented)

- **`CompleteProgress`** ([complete_progress.gd](../game/domain/actions/complete_progress.gd)) — player-submitted **`schema_version: 1`** action; **`GameState.try_apply`** validates, calls **`ProgressUnlockResolver.complete_progress`**, replaces **`progress_state`**, logs **`unlocked_targets`** delta.
- **Not** in **`LegalActions`**; **not** in **AI**; **`3.4e`** did **not** add **input-controller** binding; **`LogView`** formats lines for visibility.
- **`future_dependencies`** still **metadata-only**; **no** detectors; **no** progress **accumulation**.

### Phase 3.4f status (implemented)

- **`SelectionController`**: **`KEY_G`** (pressed, non-echo) submits **`CompleteProgress`** for the **current player** with hardcoded **`progress_id`** **`foraging_systems`** via **`GameState.try_apply`**. **No** **`LegalActions`** / **AI** / detectors; **no** cycling **`ProgressDefinitions`**; **`TurnLabel`** + **`LogView`** refresh on **accept** only.

### Phase 3.4g status (implemented)

- **`ProgressDetector`** ([progress_detector.gd](../game/domain/progress_detector.gd)) — read-only, candidate-generating: **`suggested_complete_progress_actions(game_state)`** returns **`CompleteProgress`** action **`Dictionary`** values (**no** **`try_apply`**, **no** mutation). **Rule (Phase 5.1.8a):** when **`scenario.lightning_tree_hex`** is non-null (**prototype play map** carries a deterministic **Lightning-Scarred Tree** landmark cell — **not** a weather system, resource row, or feature catalogue), propose **`controlled_fire`** for a player who has **not** **`has_completed_progress`** and whose **`ActionLog`** contains an **accepted `move_unit`** for that **`actor_id`** whose **`to`** hex equals the tree or is **hex-adjacent** to it. Other scenarios keep **`lightning_tree_hex == null`** so this rule stays inert. **Not** invoked by **`GameState`**, **`LegalActions`**, **AI**, UI, or controllers.

### Phase 3.4h status (implemented)

- **`ProgressCandidateFilter`** ([progress_candidate_filter.gd](../game/domain/progress_candidate_filter.gd)) — **`for_current_player(game_state)`** returns detector candidates whose **`actor_id`** equals **`turn_state.current_player_id()`** only (**no** **`CompleteProgress.validate`** — **`GameState.try_apply`** stays authoritative). **`SelectionController`**: **`KEY_H`** submits the **first** filtered candidate via **`try_apply`**; **no** auto-apply, **no** **`LegalActions`** / **AI**; **`TurnLabel`** / **`LogView`** refresh on **accept** only.

## Capability and material roles (Phase 5.0a)

**Forward-looking design.** This subsection does **not** define `ProgressDefinitions` rows or tooling; rather it constrains future worlds so generators and RuleSets avoid hardwired historical-material assumptions.

- The engine must **not** assume fixed historical materials such as **iron**, **bronze**, or **steel** always exist in every world.
- The engine must **not** assume those materials always sit on **one fixed dependency chain**.
- **Role abstractions** at the **model** level (examples only, not registry rows): **`primary_edge_material`**, **`primary_armor_material`**, **`smelting_capability`**, **`metallurgy_tier`**.
- **Sciences**, **breakthroughs**, **unlocks**, **units**, **city projects**, and **material paths** should be able to reference **roles** rather than hardcoded material names where appropriate.
- **Curated** worlds may bind concrete materials to roles in familiar ways.
- **Generated** worlds may bind roles differently, alter **rarity**, change **costs**, or provide **alternate dependencies**.
- This supports worlds where e.g. **iron** is absent or unimportant while other material systems become strategically central.

## Phase 5.1 Ancient-era embryo — shipped vs remaining

**Shipped:** a **curated Ancient v0 embryo** exists in running code: **`ProgressDefinitions`**, **`ProgressState`** (including unlocks + science accumulation + **`current_research_id`**), **`CompleteProgress`** / **`ProgressDetector`** (lightning tree), **`ScienceTick`**, **`SetCurrentResearch`**, HUD popups (**`DiscoveryPopup`**, **`ScienceCompletedPopup`**, science panel wiring), **`controlled_fire`** completion on the **prototype play** map ( **`lightning_tree_hex`**, observation bonus, **`science_completed`** / **`science_bonus`** logs), **`CityProjectDefinitions`** **`produce_unit:settler`** with **default-unlock alongside warrior**, and **`LegalActions`** / **`EffectiveRules`** gating aligned with **[CONTENT_MODEL.md](CONTENT_MODEL.md)**. Operational detail and slice numbering remain in **[PHASE_PLAN.md](PHASE_PLAN.md)** and domain tests.

**Not shipped / deliberately later:** **`RuleSet`** as a persisted match snapshot type, **generated** worlds with divergent EffectiveRules graphs, workbook-scale breakthrough coverage, richer **spatial** detectors beyond this seed, **AI** proposing **`CompleteProgress`**, eliminating manual **`KEY_G`/`KEY_H`** tooling without an explicit UX phase, **LLM** packaging of rules, and systemic **alternate material** binds beyond the **[Phase 5.0a](#capability-and-material-roles-phase-50a)** design notes.

The following bullets remain **behavioral reference** for **prototype-play** **`controlled_fire`** (they describe what the shipped slice aims to do—not a docs-only backlog):

**Prototype lightning tree + `controlled_fire` (reference):**

- On the **prototype play** scenario, optional **`Scenario.lightning_tree_hex`** marks a **Lightning-Scarred Tree** cell (**fixture only** — not weather/random resource simulation). Terrain/placement polish was tuned so the landmark reads as **open** land relative to authored forest decoration (see **[PHASE_PLAN.md](PHASE_PLAN.md)** / **[MAP_MODEL.md](MAP_MODEL.md)**). **`ProgressDetector`** may still surface a **`controlled_fire`** **`CompleteProgress`** candidate for **`ProgressCandidateFilter`** / **`KEY_H`**. Accumulation toward **`controlled_fire`** is **automatic** via **`ScienceTick`**—per owned city toward cost on **EndTurn**, plus a **one-time observation bonus** after an accepted **`move_unit`** onto/adjacent to **`lightning_tree_hex`**. **`DiscoveryActionPanel`** hides **`controlled_fire`** (reserved for richer breakthrough UX). Manual **`CompleteProgress`** remains available via **`KEY_H`** when filtered candidates exist.
- **`controlled_fire`** completion applies **`ProgressDefinitions`** reward rows through **`ProgressUnlockResolver`** (**buildings/modifiers/action hooks** bundle per registry). **`produce_unit:settler`** is **not** that reward—it is **default-unlocked from turn one** beside **`produce_unit:warrior`**.

See [CORE_LOOP.md](CORE_LOOP.md) **Phase 5.1 Ancient embryo**, [ACTIONS.md](ACTIONS.md) for **`try_apply`** detail.

## Core separation

Four conceptual layers:

1. **Science / Knowledge Node**
   - A **knowledge platform**, not a single one-off unlock.
   - Can unlock **concrete objects**, **systemic effects**, and **future dependencies**.

2. **Breakthrough**
   - An **experiential trigger** — something the player or world “does” or endures.
   - Origin may include: player actions, game state, repeated patterns, crises, observations, cultural contact.
   - Can **grant progress toward sciences** and/or **direct unlocks**.

3. **UnlockTarget**
   - A **typed** target that becomes **available** or **affected**.
   - **Not** free-text gameplay prose — IDs and `target_type` discipline.

4. **Modifier / Effect / Condition**
   - **Structured** consequences and circumstances (bonuses, restrictions, efficiencies, behavior changes).
   - Consumed by **future** rule systems once those systems exist.

## Science as knowledge platform

**Design heuristic** (not a hard validator — exceptions allowed if called out explicitly):

- A **Science** should **rarely** unlock **only one** thing.
- A **strong** Science usually provides:
  - **one** concrete unlock (building, unit, improvement, …),
  - **one** systemic effect (modifier, system knob, …),
  - **one** future dependency hook (child sciences or pipelines).

This keeps sciences from becoming isolated **one-off boxes** without forcing every row to match a formula.

### Example: `rail_logistics`

- **Concrete unlocks**
  - `tile_improvement`: `railroad`
  - `building`: `freight_station`
- **Systemic effects**
  - `modifier`: `faster_strategic_troop_movement`
  - `modifier`: `extra_trade_route_capacity`
- **Future dependency hooks**
  - `science`: `public_rail_timetables`
  - `science`: `industrial_management`
  - `science`: `advanced_logistics_software`

## ScienceDefinition draft shape

**Future-oriented illustration only** — not an implemented GDScript schema or file format.

```json
{
  "id": "rail_logistics",
  "display_name": "Rail Logistics",
  "era_bucket": "industrial",
  "category": "science",
  "role": "strategic_mobility_and_trade_capacity",
  "concrete_unlocks": [
    { "target_type": "tile_improvement", "target_id": "railroad" },
    { "target_type": "building", "target_id": "freight_station" }
  ],
  "systemic_effects": [
    { "target_type": "modifier", "target_id": "faster_strategic_troop_movement" },
    { "target_type": "modifier", "target_id": "extra_trade_route_capacity" }
  ],
  "future_dependencies": [
    { "target_type": "science", "target_id": "public_rail_timetables" },
    { "target_type": "science", "target_id": "industrial_management" },
    { "target_type": "science", "target_id": "advanced_logistics_software" }
  ]
}
```

- **`target_type` + `target_id`** avoids stacking semantic namespaces into double-colon IDs like `project:produce_unit:warrior`.
- **`target_id`** follows the **owning registry’s** ID convention when that registry exists.
- A **future** implementation might **normalize** these lists into one `unlocks` array; the **design model** keeps **concrete** / **systemic** / **dependencies** separate for clarity and review.

## Unlock target taxonomy

**Allowed / candidate** `target_type` values (forward-declared from workbook-aligned thinking):

- `building`
- `district`
- `tile_improvement`
- `unit`
- `support_unit`
- `specialist`
- `material`
- `good`
- `equipment`
- `unit_upgrade`
- `action`
- `project`
- `modifier`
- `system`
- `science`
- `doctrine`
- `resource_visibility`

**Also** (example-driven forward candidate):

- `map_feature` — e.g. landmark / note affordances; may later fold into `system` or another owner.

**Rules**

- Categories may exist in **design** before the **gameplay system** exists.
- A target is **enforceable** only when its **owning registry** and **rule system** exist.
- Some IDs may **move category** (e.g. dockyard as `building`, `district`, or `project`) — migrations are explicit subphase work, not silent renames.

## Normalize unlocks into typed catalog objects

**Rule:** Unlock lists should **not** rely on **free-form effect text** when the same intent can be a **typed object** with an **`id`**.

**Examples**

- `"+food from forests/berries"` → `modifier`: `forest_food_bonus`
- `"faster healing outside borders"` → `modifier`: `outside_borders_healing`
- `"bronze tools"` → `material`: `bronze_tools`
- `"armory"` → `building`: `armory`
- `"basic melee equipment"` → `unit_upgrade`: `basic_melee_equipment`
- `"trade capacity"` → `modifier` **or** `system`: `trade_capacity` (pick one owner when implementing)
- `"ethical tension"` → `system`: `ethics_stability_pressure`

**Guidance**

- **Prose** belongs in **`notes`**, **`display_name`**, or design docs — not as a stand-in for machine-readable unlock rows.
- **Unlock targets** should be **typed** and **ID-based** once past brainstorming.

## Breakthrough model

**Breakthrough** = a **candidate experiential trigger**:

- Not guaranteed **automatically implementable**.
- Not necessarily **deterministic** yet in design.
- May **grant progress** (e.g. science buckets / partial progress) and/or **direct unlocks** (typed targets).

**Decomposition required** for each breakthrough design row:

1. **Design idea** — what it *means* in player terms.
2. **Operational interpretation** — what *must be true* in game terms.
3. **Detection model** — how we *might* observe that (deterministic, deferred, LLM-advisory-only, …).

**Draft field set**

- `id`
- `display_name`
- `trigger_family`
- `detection_difficulty`
- `detector_status`
- `candidate_interpretation`
- `possible_deterministic_detector`
- `grants_progress`
- `direct_unlocks`
- `notes`

**Draft shape (illustration)**

```json
{
  "id": "forced_two_front_defense",
  "display_name": "Forced Two-Front Defense",
  "trigger_family": "strategic_pressure",
  "detection_difficulty": "hard",
  "detector_status": "deferred",
  "candidate_interpretation": "Player faces simultaneous hostile pressure in two separated border regions.",
  "possible_deterministic_detector": "Two enemy threat clusters within N hexes of player-owned cities or borders, separated by at least M hexes, while the player has defensive units committed near both clusters within K turns.",
  "grants_progress": [
    { "target_type": "science", "target_id": "strategic_reserves", "amount": 20 }
  ],
  "direct_unlocks": [],
  "notes": "Front definition requires a later territorial/threat model."
}
```

## Breakthrough detection classes

Families for **how** we might detect a breakthrough (design vocabulary — not shipped code).

### `simple_counter`

- **What:** repeated training, repeated build, completed routes count, etc.
- **State / log:** tallies from actions, completions, production events.
- **Early deterministic:** often **yes**, if definitions are crisp.

### `spatial_pattern`

- **What:** river mouths, chokepoints, coastal geometry, mountain passes.
- **State / log:** map features, positions, terrain tags.
- **Early deterministic:** **partial** — needs stable map semantics.

### `combat_pattern`

- **What:** flanking, combined arms, defensive wins, loss ratios.
- **State / log:** combat resolution events (not in core loop today).
- **Early deterministic:** **no** until combat model exists.

### `economic_state`

- **What:** low treasury, trade disruption, surplus/shortage.
- **State / log:** economy tick, trade events, yields.
- **Early deterministic:** **partial** once economy registers exist.

### `multi_city_coordination`

- **What:** several cities feeding one logical effort.
- **State / log:** shared-project graph, contributor lists.
- **Early deterministic:** **after** shared-project subsystem.

### `strategic_pressure`

- **What:** two-front defense, surprise attack, resource denial.
- **State / log:** threat clusters, fronts, diplomatic/military posture.
- **Early deterministic:** **hard** — needs threat/front model.

### `cultural_contact`

- **What:** trade or contact with foreign / advanced neighbors.
- **State / log:** diplomacy, trade routes, visibility.
- **Early deterministic:** **medium** once contact rules exist.

### `systems_insight`

- **What:** repeated player style or cross-system interactions.
- **State / log:** aggregated behavior signatures (privacy / scope TBD).
- **Early deterministic:** **speculative** — careful with scope creep.

## Detection difficulty and detector status

**`detection_difficulty`**

- `easy`
- `medium`
- `hard`
- `speculative`

**`detector_status`**

- `implemented`
- `deterministic_candidate`
- `needs_more_game_state`
- `deferred`
- `llm_advisory_candidate`

**Guidance**

- Most workbook breakthroughs start as **`deferred`** or **`deterministic_candidate`**.
- **`hard`** / **`speculative`** items **must not** block adopting this model or shipping smaller slices.

## Deterministic-first rule

**Core progression** and **replay-critical unlocks** must be **deterministic-first**:

- Same inputs, same **authoritative** game state evolution, same unlock outcome for legal play.

**LLMs** (if explored later) are limited to **non-authoritative** roles only, for example:

- **Advisory interpretation** of ambiguous signals (never sole gate for a competitive unlock).
- **Narrative summaries** or tooltips.
- **Candidate breakthrough suggestions** for designers.
- **Design tooling** (clustering, labeling drafts).
- **Optional** single-player assist (explicitly off for ranked / replay truth).

**LLMs must not** be the authoritative rules engine for **core replay**, **scoring**, **legality**, or **deterministic unlock state**.

## Example breakthrough interpretations

### 1. “Tvingas evakuera arbetare från fronten”

- **Design idea:** forced civilian / worker evacuation from a threatened frontier.
- **Operational interpretation:** a civilian-class unit **retreats** from a tile after **enemy threat** enters a nearby radius.
- **Possible detector:** worker / settler / civilian **moves away** from hostile unit or threatened tile within **X** turns of enemy entering radius **N**.
- **Possible progress:** `civil_defense`, `escort_protocols`, `emergency_logistics`.
- **Possible unlocks:** `action`: `civilian_evacuation`, `modifier`: `safer_civilian_withdrawal`.
- **Difficulty:** `medium`.

### 2. “Ha tre enheter från olika vapenslag i samma operation”

- **Design idea:** combined arms in one operation.
- **Operational interpretation:** three friendly units with **distinct** `unit_class` values engaged near the **same** objective / enemy within a **rolling window**.
- **Possible detector:** three `unit_class` values within radius **R** of same enemy / city / objective during **K** turns.
- **Possible progress:** `operational_coordination`, `combined_arms_practice`.
- **Difficulty:** `medium`–`hard` depending on operation / combat model.

### 3. “Låt flera städer bidra till samma projekt”

- **Design idea:** intercity coordination on one production or megaproject.
- **Operational interpretation:** a **shared** project records **contributions** from **≥ 2** city IDs before completion.
- **Possible detector:** contributor map / set size **≥ 2** before completion event.
- **Possible progress:** `intercity_coordination`, `grand_project_management`, `networked_production`.
- **Possible unlocks:** `system`: `shared_projects`, `modifier`: `intercity_project_efficiency`.
- **Difficulty:** `medium`; requires **shared-project** subsystem.

### 4. “Tvingas försvara två fronter”

- **Design idea:** two-front defense (same thematic lane as **`forced_two_front_defense`**).
- **Operational interpretation:** hostile pressure in **two separated regions** concurrently.
- **Possible detector:** two enemy **threat clusters** near owned territory, separated by ≥ **M**, with friendly defensive posture near **both** within **K** turns.
- **Possible progress:** `strategic_reserves`, `defensive_depth`, `emergency_mobilization`.
- **Difficulty:** `hard`; **`deferred`** until **threat / front** model exists.

## Modifier / Effect / Condition shapes

**Future draft only** — no runtime schema commitment.

**ModifierDefinition (illustration)**

```json
{
  "id": "infantry_rested_march",
  "display_name": "Rested March",
  "category": "modifier",
  "scope": "player",
  "applies_to": [
    { "target_type": "unit_class", "target_id": "foot_infantry" }
  ],
  "conditions": [
    { "type": "unit_resting_previous_turn" }
  ],
  "effects": [
    { "type": "movement_bonus", "value": 1 }
  ]
}
```

**Effect** (conceptual)

- `type`
- `value`
- optional target / filter
- optional duration
- optional stacking rule

**Condition** (conceptual)

- `type`
- parameters
- evaluation scope
- required game state
- deterministic requirement (must be explicit before gating progression)

**Guidance**

- Prefer **structured** condition types over **free-string** predicates.
- Use **arrays** for `conditions` and `effects` even when length is 1.

## Canonical Ancient / Foundation unlock bundles

**Registry truth:** [science_unlocks.gd](../game/domain/content/science_unlocks.gd) (**`ScienceUnlocks`**) — **21** sciences (**20** Ancient/Foundation + **`exoplanet_expedition`**). Each row has **`title`**, **`era`**, typed **`unlocks`** (`id`, `type`, `name`, `summary`, optional `metadata`), and optional **`flags`**.

**Tech-tree preview copy (presentation only):**

- **Card title** — science **`title`** from **`ScienceUnlocks`**.
- **Card bullets** — **unit / support_unit / naval_unit** **`name`** only when that science unlocks trainable units; otherwise **no** bullets on the card.
- **`exoplanet_expedition`** — keeps manual victory copy (not derived from unlock rows).

**Trainable unit display names on tech cards today:**

**Baseline producerable units** ([starting_units.gd](../game/domain/content/starting_units.gd)): **`unit_settler`** (Settler), **`unit_warrior`** (Warrior). City View labels source **`Baseline`**. Default city projects **`produce_unit:settler`** and **`produce_unit:warrior`** ship via **`ProgressState.with_default_unlocks_for_players`**.

| Science id | Unit bullet(s) |
| --- | --- |
| `stone_tools` | Worker, Slinger |
| `animal_tracking` | Tracker Scout |
| `pastoral_herding` | Mounted Scout |
| `fishing_methods` | Reed Boat |
| `timber_working` | Archer, War Canoe |
| `bronze_alloying` | Bronze-Armed Warrior |
| `wheelwrighting` | Cart Support Unit |
| `simple_levers` | Siege Precursor |

**Science-unlocked unit ids:** `unit_worker`, `unit_slinger`, `unit_tracker_scout`, `unit_mounted_scout_precursor`, `unit_reed_boat`, `unit_archer`, `unit_war_canoe`, `unit_bronze_armed_warrior`, `unit_cart_support`, `unit_siege_precursor`.

**Unit marker assets:** [unit_unlock_assets.gd](../game/domain/content/unit_unlock_assets.gd) maps each **`unit_*`** unlock id to **`res://assets/prototype/map_markers/`** PNGs for City View details and future presentation use.

**Removed:** `unit_raft` is not an active producerable unit unlock.

**Inspection UIs** (e.g. **City View prototype**, unlock details) read full **`unlocks`** from **`ScienceUnlocks`** — not the shortened tech-card bullet list.

**Gameplay costs / prerequisites** for the playable loop remain in **`ProgressDefinitions`** until a later slice merges or cross-links both registries. Do **not** duplicate unlock definitions in this doc.

## Phase 5.1.12 — Ancient science tree (documentation checkpoint)

**Status:** **Phase 5.1.12a** (this section) is **documentation-only**. No registry rows, **`ProgressState`**, **`ScienceTick`**, or presentation changes ship in **5.1.12a**. Implementation is sequenced in **[PHASE_PLAN.md](PHASE_PLAN.md)** sub-slices **5.1.12b** / **5.1.12c** / **5.1.12d**.

**Intent:** Replace the prototype **single-target** **`controlled_fire`** loop with a **real ancient science tree**: **19** sciences with **`cost`** (**int**) and **`prerequisites`** (science id strings), **bundle rewards** (`concrete_unlocks` / `systemic_effects`), **per-player current research target**, **deterministic availability** from prerequisites, and **city-per-turn yield** routed to the active target. **Discoveries** (e.g. lightning-tree bonus) remain **bonuses toward a specific science**, not mandatory gates. **No** full tech-tree visual UI in **5.1.12**; **auto-target** keeps play moving until a future **SciencePanel** slice.

### Ancient tree (IDs, costs, prerequisites)

Dependency rules for this doc table:

- Every listed prerequisite is **real** (the parent science exists in this tree).
- **No** decorative or **dead** prerequisites.
- A science with **no outgoing edges** in this view (**no** later science lists it as a prerequisite) is a **leaf** in this curated view.
- **`counting_marks`** feeds **`glyphic_records`** only — it is **not** a global convergence hub for unrelated branches.
- **`textile_work`** is unlocked by **`foraging_systems`** alone (travel / material-support branch; avoids a Column 2 science with no inbound edge).

| Science id | Cost | Prerequisites | Notes |
| --- | --- | --- | --- |
| **Column 1 — starting sciences** | | | |
| `foraging_systems` | 6 | _(none)_ | |
| `stone_tools` | 6 | _(none)_ | |
| `controlled_fire` | 6 | _(none)_ | **5.1.12d (shipped):** metadata **bundle** only — no **`produce_unit:settler`** in **`concrete_unlocks`**. |
| `oral_surveying` | 6 | _(none)_ | |
| **Column 2 — early specializations** | | | |
| `animal_tracking` | 10 | `foraging_systems`, `oral_surveying` | |
| `seasonal_calendars` | 10 | `foraging_systems`, `controlled_fire` | |
| `pottery_craft` | 10 | `controlled_fire` | |
| `textile_work` | 10 | `foraging_systems` | |
| `basic_mining` | 10 | `stone_tools` | |
| `timber_working` | 10 | `stone_tools`, `controlled_fire` | |
| **Column 3 — settled economy / administration** | | | |
| `agrarian_practice` | 14 | `pottery_craft`, `seasonal_calendars` | |
| `counting_marks` | 14 | `pottery_craft`, `oral_surveying` | Admin / writing branch toward **`glyphic_records`**. |
| `mudbrick_construction` | 14 | `timber_working` | |
| `simple_levers` | 14 | `stone_tools` | |
| **Column 4 — later locked paths** | | | |
| `pastoral_herding` | 18 | `animal_tracking` | **Leaf** in this view. |
| `river_irrigation` | 18 | `seasonal_calendars` | **Leaf** in this view. |
| `bronze_alloying` | 18 | `basic_mining` | **Leaf** in this view. |
| `wheelwrighting` | 18 | `timber_working` | **Leaf** in this view. |
| `glyphic_records` | 18 | `counting_marks` | **Leaf**; display / lore may read as **Glyphic Records / Formal Writing**. |

### Model contracts (5.1.12 rollout)

1. **`ProgressDefinitions`** row extension (science rows): **`cost`**: **`int`** and **`prerequisites`**: **`Array[String]`** — **shipped in 5.1.12b** with **`cost(id)`**, **`prerequisites(id)`**, **`is_science(id)`** (ordered prerequisite lists in data; validators require all completed).
2. **`ProgressState`** (**5.1.12c** **shipped**): **`current_research_id`**: **`String`** per **`owner_id`** (**`""`** = auto-target); helpers **`current_research_for`**, **`with_current_research`**; **`ScienceTick`** uses explicit id when set **and** **`ScienceAvailability.is_available`**, else **first** **`available_for`**.
3. **`ScienceAvailability`** (**5.1.12b**): **`available_for`**, **`locked_for`**, **`completed_for`**, **`is_available`** — **pure** domain helper; **`available_for`** follows **`ProgressDefinitions.ids()`** tree order (auto-target uses **first** entry); **`locked_for`** / **`completed_for`** sorted **alphabetically** for stable display. **Availability** is **derived** from **`completed_progress_ids`**, not stored separately on **`ProgressState`**.
4. **`SetCurrentResearch`** (**5.1.12c** **shipped** — **`set_current_research`**): validates registry id, **science** row, **not** completed, **available**; **`science_id` `""`** clears explicit target; **`GameState.try_apply`** logs **`result`:** **`accepted`**. **5.1.13**–**5.1.14:** **`SciencePanel`** (**presentation**) submits this action and shows **available** + **locked** prerequisite hints; **not** in **`LegalActions`** / **AI**.
5. **`CompleteProgress.validate`** (**5.1.12b**): rejection **`prerequisites_not_met`** when a **science**’s prerequisites are not all in **`completed_progress_ids`** (**`try_apply`** surfaces this reason).
6. **`ScienceTick`** (**5.1.12b**–**c** **shipped**; **5.1.16c** **yield source**): **`apply_for_player`** resolves dynamic **`progress_id`**, applies **`CityYields.science_for_player`** as the **per-turn science delta** (capital **Palace** and future buildings — **not** a flat per-city constant), reads **`ProgressDefinitions.cost`**, completes via **`ProgressUnlockResolver`** at threshold (**no** overflow); emits **`science_progress`** / **`science_completed`** for that id; **`science_no_target`** when **zero** available sciences; **`add_observation_bonus_if_eligible`** uses **`controlled_fire`** only (**independent** of **`current_research_id`**).
7. **Settler baseline** (**5.1.12d** **shipped**): **`ProgressState.with_default_unlocks_for_players`** includes **`city_project` / `produce_unit:settler`** from turn **1** (with **`produce_unit:warrior`**). **Gameplay-enforced Ancient building rewards (v0):** **`controlled_fire`** → **`building` / `hearth`** (**`build:hearth`**, **+1 Production**); **`pottery_craft`** → **`building` / `pottery_workshop`** (**`build:pottery_workshop`**, **+1 Food**); **`seasonal_calendars`** → **`building` / `storage_hall`** (**`build:storage_hall`**, **+1 Food**); **`textile_work`** → **`building` / `weaver_hut`** (**`build:weaver_hut`**, **+2 Coin**); **`mudbrick_construction`** → **`building` / `mudbrick_housing`** (**`build:mudbrick_housing`**, **+2 Housing** recorded only); **`counting_marks`** → **`building` / `storehouse_ledger`** (**`build:storehouse_ledger`**, **+2 Coin**); **`glyphic_records`** → **`building` / `archive_hut`** (**`build:archive_hut`**, **+2 Science**); **`bronze_alloying`** → **`building` / `armory`** (**`build:armory`**, **+1 Production**). Completed building yield ints live in **`BuildingDefinitions.yield_effects`**; **`CityYields`** applies food/production/science/coin generically from **`City.building_ids`**; **`housing`** is reported via **`yield_breakdown_for_city`(..).`housing`** and **`building_housing_total`** only (**no** growth/capacity effect yet). Other science targets (**`camp_clearing`**, **`tally_ledger`**, modifiers, **`granary_capacity_bonus`**, etc.) remain **metadata-only** until later phases.
8. **Science bundles:** every science row should declare **at least one** **`concrete_unlock`** **or** **`systemic_effect`**. **Placeholder** targets are acceptable until gameplay systems exist; unknown **`target_type`** rows may remain **metadata-only** in **`ProgressState.unlocked_targets`** without enforcement.
9. **Discoveries / landmarks:** **bonus progress** toward a **named** science id, **not** mandatory gates on completing that science.
10. **`ScienceCompletedPopup`:** remains **log-driven**; **no** **`ProgressDefinitions`** import in presentation — copy and bullet lists derive from **log** **`progress_id`**, **`unlocked_targets`**, and related fields only.
11. **UI:** **no** tech-tree canvas in **5.1.12**; **auto-target** preserves a playable loop; **Phase 5.1.13**–**5.1.14** ship a **minimal** **`SciencePanel`** (available targets + compact **locked** **Requires:** hints); a **full** tree / queue / graph remains **deferred**.
12. **City territory (**5.1.16g** shipped):** **`City.owned_tiles`** records which map hexes a city controls (**`FoundCity`** → center + valid radius **1**, including water; no cross-city overlap). **`CityYields.city_total_yield`** does **not** read **`owned_tiles`** in **5.1.16g**; **5.1.16h** (**population** / **auto-worked** tiles) will attach ring production to yields.

## Relationship to existing docs

- **[CONTENT_MODEL.md](CONTENT_MODEL.md)** — general **content contract** (registries, IDs, duplication rules).
- **[CONTENT_BACKLOG.md](CONTENT_BACKLOG.md)** & workbook — **non-canonical** raw lists and brainstorms.
- **`PROGRESSION_MODEL.md`** (this file) — **systematic model** for progression / unlocks / detection vocabulary.
- **Implemented registries today:** `UnitDefinitions`, `TerrainRuleDefinitions`, `CityProjectDefinitions`, **`ProgressDefinitions`** (**Phase 3.4b** — costs/prerequisites for the playable loop), and **`ScienceUnlocks`** (canonical Ancient/Foundation unlock bundles + tech-tree preview copy rules above).
- **Implemented session state:** **`GameState.progress_state`** (**Phase 3.4c**) — player-specific **`unlocked_targets`** (**Phase 5.1.12d:** baseline **`city_project` / `produce_unit:warrior`** and **`produce_unit:settler`**) and **`completed_progress_ids`** (**Phase 3.4d**); **Phase 5.1.9** adds **`science_progress`** and **`science_observation_flags`**; **Phase 5.1.12c** adds **`current_research_id`** (**`""`** = auto-target) and **`SetCurrentResearch`** through **`try_apply`**; **`ScienceTick.apply_for_player`** routes **summed city science** from **`CityYields.science_for_player`** to **explicit** target when set **and** available, else **first** **`ScienceAvailability.available_for`** (tree order), with **`science_no_target`** when none remain; lightning **`science_bonus`** remains **`controlled_fire`**-only; **Phase 5.1.16d** **`ProductionTick`** advances **`produce_unit`** **`progress`** by **`CityYields.city_total_yield`** **production**; **deterministic** **`SetCityProduction`** gating (**`project_not_unlocked`** in **`try_apply`**); **`complete_progress`** (**Phase 3.4e**) applies definition unlocks via **`ProgressUnlockResolver`**; **Phase 3.4f** adds **`KEY_G`** in **`SelectionController`** for **manual** **`CompleteProgress`** (**still** **outside** **`LegalActions`** / **AI**); **Phase 3.4g** adds **`ProgressDetector`** (**read-only** candidates from **`ActionLog`**; **Phase 5.1.8a** gates **`controlled_fire`** detector on optional **`scenario.lightning_tree_hex`** + observation); **Phase 3.4h** adds **`ProgressCandidateFilter`** + **`KEY_H`** (**still** **outside** **`LegalActions`** / **AI**).
- **[FACTION_IDENTITY.md](FACTION_IDENTITY.md)** defines the predefined/custom civilisation **identity layer** that may later **bias** progression **interpretation**, **presentation**, and trait-driven tuning; in **3.5a** it is **documentation-only** and **does not modify** the progression model.
- **Phase 3.4a** changes **no** gameplay behavior.

## Phase mapping

- **3.4a** — documentation-only progression model checkpoint (**this file**).
- **3.4b** — **`ProgressDefinitions`** registry seed ([progress_definitions.gd](../game/domain/content/progress_definitions.gd)): **five** ancient/foundations sciences, **metadata-only**, **no** gating.
- **3.4c** — **`ProgressState`** on **`GameState`**; **default** **`city_project` / `produce_unit:warrior`** and **`produce_unit:settler`** for initial players (**5.1.12d**); **`try_apply`** + **`LegalActions`** **`SetCityProduction`** gate (**`project_not_unlocked`**); **`ProgressDefinitions`** still **not** consumed in **`GameState`**.
- **3.4d** — **`ProgressUnlockResolver`** static helper applies a completed definition’s **`concrete_unlocks`** + **`systemic_effects`** into **`ProgressState`**; **`future_dependencies`** remain **metadata-only**; **no** detectors in **3.4d** alone.
- **3.4e** — **`CompleteProgress`** player action through **`GameState.try_apply`**; **not** **`LegalActions`** / **AI**; uses **`ProgressUnlockResolver`**; logs **`unlocked_targets`** delta.
- **3.4f** — **`KEY_G`** in **`SelectionController`**: manual **`CompleteProgress`** for **`foraging_systems`** only; **no** detectors, **no** **`LegalActions`**, **no** **AI**; **`LogView`** / **`TurnLabel`** refresh on **accept**; **no** definition cycling.
- **3.4g** — **`ProgressDetector`**: **`suggested_complete_progress_actions`** proposes **`complete_progress`** (**`controlled_fire`**) after an **accepted `move_unit`** **observation** of the optional **prototype** **`lightning_tree_hex`** (destination **on** the tree hex **or** **hex-adjacent** to it) when not already completed; **read-only**, **not** **`GameState`**-wired; **no** **`LegalActions`** / **AI**.
- **3.4h** — **`ProgressCandidateFilter.for_current_player`** + **`KEY_H`**: manual **first** **current-player** detector candidate via **`try_apply`**; **no** validate in filter; **no** auto-apply; **no** **`LegalActions`** / **AI**.
- **3.5a** — **[FACTION_IDENTITY.md](FACTION_IDENTITY.md)** docs-only checkpoint: predefined + custom civ identity model and balanced trait vocabulary; **bias layer** that **does not** alter **`ProgressDefinitions`**, **`ProgressState`**, **`ProgressUnlockResolver`**, **`ProgressDetector`**, **`LegalActions`**, **AI**, or **`GameState`** in **3.5a**.
- **3.5b** — **`FactionDefinitions`** debug seed: **three** non-canonical debug faction rows exist as **metadata only**; they do **not** alter **`ProgressDefinitions`**, **`ProgressState`**, **`ProgressUnlockResolver`**, **`ProgressDetector`**, **`LegalActions`**, **AI**, or **`GameState`**.
- **Later** — additional **detectors** and optional **auto-consumption** policy (deterministic first; LLM advisory at edges only).
- **Phase 5** — strategic dynamics; many **modifiers** and **systems** become real.
- **Phase 6** — world identity, names, flavor; does not replace this model.
- **Phase 7** — balance and numeric tuning.
- **5.1.12a** — **Ancient science tree documentation checkpoint** — **docs only**; **19-science** tree + model contracts in this file and **[PHASE_PLAN.md](PHASE_PLAN.md)**.
- **5.1.12b** — **`ProgressDefinitions`** **`cost`** + **`prerequisites`** (19 sciences); **`ScienceAvailability`**; **`ScienceTick`** reads **`cost`** from definitions; **`CompleteProgress`** **`prerequisites_not_met`** — **shipped**.
- **5.1.12c** — **`current_research_id`**, **`SetCurrentResearch`**, **`ScienceTick`** target routing + **`science_no_target`** — **shipped**.
- **5.1.12d** — **Settler baseline** default unlock; **Controlled Fire** reward bundle correction — **shipped**.
- **5.1.13** — **`SciencePanel`** minimal HUD (**`SetCurrentResearch`** + derived availability display) — **shipped**.
- **5.1.14** — **`SciencePanel`** adds a compact **locked-science** hint list (missing prerequisites only); still **not** a full tech-tree UI — **shipped**.

## Explicit non-goals

- No full tech tree implementation in code.
- No **120+** science registry drop-in.
- No **200+** breakthrough registry drop-in.
- No **LLM** as authoritative rule engine.
- No unlock **gating** in **3.4a**.
- No **save/load** or replay **migration** design lock-in here.
- No **balance** numbers as normative.
- No **Civ-derived** tech tree copy as source of truth.

See also: **[PHASE_PLAN.md](PHASE_PLAN.md)** Phase **3.4a** block for milestone accounting.
