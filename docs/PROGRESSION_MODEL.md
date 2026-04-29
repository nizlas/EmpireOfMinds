# Progression Model

## Status and purpose

- **Phase 3.4a** is **documentation-only** — no code, registries, or gameplay changes in this checkpoint.
- This document defines the **systematic model** for future **progression** and **unlock** work (sciences, breakthroughs, targets, modifiers, detection).
- It is **not** a registry and **not** a balance pass.
- It does **not** canonicalize the full workbook lists (~200 breakthroughs, ~140 sciences).
- **Empire_of_Minds_Content_Workbook** and **[CONTENT_BACKLOG.md](CONTENT_BACKLOG.md)** are **non-canonical design raw material**, not implementation truth.
- **[CONTENT_MODEL.md](CONTENT_MODEL.md)** remains the **general content contract** (IDs, registries, state vs definitions).

### Phase 3.4b status (implemented)

- **[ProgressDefinitions](../game/domain/content/progress_definitions.gd)** (`class_name` **`ProgressDefinitions`**) — tiny **metadata-only** registry with **five** seed **sciences** (`category` **`science`**, `era_bucket` **`ancient_foundations`**).
- **No** unlock gating, **no** breakthrough detection, **no** player progress state; `target_type` / `target_id` rows may reference **future** systems not yet implemented.

### Phase 3.4c status (implemented)

- **[ProgressState](../game/domain/progress_state.gd)** (`class_name` **`ProgressState`**) — **immutable** snapshot of **player-specific** **unlocked targets** (`target_type` + **`target_id`** rows; literal gate type **`"city_project"`** for **`SetCityProduction`** in this slice).
- **`GameState`** owns **`progress_state`** (**not** **`Scenario`**). **Default seed:** every **initial** **`turn_state.players`** id gets **`city_project` / `produce_unit:warrior`** unlocked; **`GameState.new(scenario)`** (omitted second arg) keeps that default.
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

## Seed Science examples — Ancient / Foundations

**Explicitly non-final, non-canonical** — brainstorming anchors, not shipped content.

### 1. `foraging_systems`

- **Display name:** Foraging Systems
- **Era bucket:** Ancient / Foundations
- **Description:** early food gathering, camps, simple survival practices.
- **Concrete unlocks**
  - `building` or `tile_improvement`: `scout_camp`
  - `specialist`: `forager`
- **Systemic effects**
  - `modifier`: `forest_food_bonus`
  - `modifier`: `outside_borders_healing`
- **Future dependency hooks**
  - `science`: `survival_knowledge`
  - `science`: `woodland_logistics`

### 2. `stone_tools`

- **Concrete unlocks**
  - `unit`: `worker`
  - `tile_improvement`: `quarry`
  - `unit_upgrade`: `basic_melee_equipment`
- **Systemic effects**
  - `modifier`: `stone_production_bonus`
- **Future dependency hooks**
  - `science`: `masonry`
  - `science`: `mining`
  - `science`: `toolmaking`

### 3. `controlled_fire`

- **Concrete unlocks**
  - `building`: `hearth`
  - `action`: `camp_clearing`
- **Systemic effects**
  - `modifier`: `cold_terrain_growth_bonus`
  - `modifier`: `small_health_bonus`
- **Future dependency hooks**
  - `science`: `pottery`
  - `science`: `metallurgy`
  - `science`: `settlement_comfort`

### 4. `oral_surveying`

- **Concrete unlocks**
  - `map_feature`: `landmark_markers`
  - `action`: `map_notes`
- **Systemic effects**
  - `modifier`: `improved_scout_sight_memory`
  - `modifier`: `revisit_terrain_movement_bonus`
- **Future dependency hooks**
  - `science`: `cartography`
  - `science`: `administration`
  - `science`: `writing`

### 5. `animal_tracking`

- **Concrete unlocks**
  - `unit`: `tracker`
  - `tile_improvement`: `hunting_camp`
- **Systemic effects**
  - `resource_visibility`: `reveal_animal_resources`
  - `modifier`: `ambush_detection_bonus`
- **Future dependency hooks**
  - `science`: `animal_domestication`
  - `science`: `riding`
  - `science`: `hunting_traditions`

## Candidate unlock catalog samples

**Small sample only** — not a full catalog, not registry truth.

**Buildings**

- `hearth`
- `scout_camp`
- `armory`
- `library`
- `freight_station`

**Districts**

- `harbor_district`
- `market_district`
- `workshop_quarter`
- `academy_quarter`

**Tile improvements**

- `farm`
- `quarry`
- `road`
- `railroad`

**Units**

- `basic_melee_warrior`
- `bronze_armed_warrior`
- `archer`
- `mounted_scout`
- `rifle_infantry`

**Modifiers**

- `forest_food_bonus`
- `outside_borders_healing`
- `troop_redeployment_bonus`
- `automated_route_optimization`

**Systems**

- `trade_routes`
- `supply_network`
- `shared_projects`
- `cyber_operations`

**Promotion rule**

- Samples become **shipped IDs** only via a **future subphase** plus **[DECISION_LOG.md](DECISION_LOG.md)** entry — never by silent doc edit alone.

## Relationship to existing docs

- **[CONTENT_MODEL.md](CONTENT_MODEL.md)** — general **content contract** (registries, IDs, duplication rules).
- **[CONTENT_BACKLOG.md](CONTENT_BACKLOG.md)** & workbook — **non-canonical** raw lists and brainstorms.
- **`PROGRESSION_MODEL.md`** (this file) — **systematic model** for progression / unlocks / detection vocabulary.
- **Implemented registries today:** `UnitDefinitions`, `TerrainRuleDefinitions`, `CityProjectDefinitions`, and **`ProgressDefinitions`** (**Phase 3.4b** — **metadata-only** progression seed; **no** gameplay enforcement).
- **Implemented session state:** **`GameState.progress_state`** (**Phase 3.4c**) — player-specific **`unlocked_targets`** and **`completed_progress_ids`** (**Phase 3.4d**); **deterministic** **`SetCityProduction`** gating (**`project_not_unlocked`** in **`try_apply`**); **`complete_progress`** (**Phase 3.4e**) applies definition unlocks via **`ProgressUnlockResolver`** without detectors or accumulation mechanics; **Phase 3.4f** adds **`KEY_G`** in **`SelectionController`** for a **manual** **`CompleteProgress`** debug slice (**still** **outside** **`LegalActions`** / **AI**).
- **Phase 3.4a** changes **no** gameplay behavior.

## Phase mapping

- **3.4a** — documentation-only progression model checkpoint (**this file**).
- **3.4b** — **`ProgressDefinitions`** registry seed ([progress_definitions.gd](../game/domain/content/progress_definitions.gd)): **five** ancient/foundations sciences, **metadata-only**, **no** gating.
- **3.4c** — **`ProgressState`** on **`GameState`**; **default** **`city_project` / `produce_unit:warrior`** for initial players; **`try_apply`** + **`LegalActions`** **`SetCityProduction`** gate (**`project_not_unlocked`**); **`ProgressDefinitions`** still **not** consumed in **`GameState`**.
- **3.4d** — **`ProgressUnlockResolver`** static helper applies a completed definition’s **`concrete_unlocks`** + **`systemic_effects`** into **`ProgressState`**; **`future_dependencies`** remain **metadata-only**; **no** detectors in **3.4d** alone.
- **3.4e** — **`CompleteProgress`** player action through **`GameState.try_apply`**; **not** **`LegalActions`** / **AI**; uses **`ProgressUnlockResolver`**; logs **`unlocked_targets`** delta.
- **3.4f** — **`KEY_G`** in **`SelectionController`**: manual **`CompleteProgress`** for **`foraging_systems`** only; **no** detectors, **no** **`LegalActions`**, **no** **AI**; **`LogView`** / **`TurnLabel`** refresh on **accept**; **no** definition cycling.
- **Later** — breakthrough **detectors** (deterministic first; LLM advisory at edges only).
- **Phase 5** — strategic dynamics; many **modifiers** and **systems** become real.
- **Phase 6** — world identity, names, flavor; does not replace this model.
- **Phase 7** — balance and numeric tuning.

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
