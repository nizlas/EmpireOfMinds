# Faction and custom-civilisation identity

## Status and purpose

- **Phase 3.5a** is **documentation-only**.
- It defines the **identity model** for **predefined civilisations** and **custom civilisations**.
- It does **not** implement registries, traits, gameplay, UI, assets, generated images, or balance math.
- It is a **structural identity checkpoint** before any faction or trait registry exists.
- **Lore**, **final copy**, **final naming**, **aesthetics**, and **IP review** are deferred to **Phase 6** (see [PHASE_PLAN.md](PHASE_PLAN.md)).

## Phase 3.5b status (implemented)

- **`game/domain/content/faction_definitions.gd`** now contains **three** non-canonical debug rows: **`debug_vasterviksjavlarna`**, **`debug_malmofubikkarna`**, **`debug_pajasarna_fran_paris`**.
- All three have **`profile_type: debug_example`** and **`canon_status: non_canonical`**.
- They are **not** assigned to players.
- They do **not** affect gameplay, AI, **`LegalActions`**, progression, or **`GameState`**.
- **`trait_ids`** are **forward references** only (no **`TraitDefinitions`** registry exists yet).
- **`visual_identity`** is **metadata only** and contains **no** asset paths.
- Serious prototype factions (**Hearthbound**, **Wayfinders**, **Forge Compact**) remain **prose examples only** in 3.5b (not shipped in the registry).

## World identity pillars

- **Civilisation as mentality**, not only territory — societies are defined by how they think, coordinate, and justify choices, not only by map borders.
- **Progression as civilisational learning**, not only technology — advances are framed as collective practice, institutions, and habits, not as a flat tech list.
- **The map as lived geography**, not only a board — terrain, routes, and settlements carry social meaning; identity informs how groups inhabit space.
- **Factions and custom civs express both strengths and weaknesses** — memorable profiles have tradeoffs; “all upside” presets are avoided in design intent.

Empire of Minds should read as societies developing **characteristic ways of thinking, organising, learning, expanding, and failing** — not as interchangeable paint on the same mechanical shell.

## Two supported identity paths

### 1. Predefined civilisations

- **Curated presets** built from the shared trait system.
- **Presentation-friendly** for demos, screenshots, and narrative read.
- Useful for **internal playtests**, **AI matchups**, **scenarios**, **demos**, and **screenshots**.
- **`profile_type: predefined`**.

### 2. Custom civilisations

- **Player-authored** profiles assembled from **balanced traits**.
- **High replay value** through different combinations of strengths and weaknesses.
- Supports **memorable** origins, values, governance style, and visual direction (described in prose only in 3.5a).
- **`profile_type: custom`**.

### Shared principle

**Predefined civilisations are curated presets over the same trait system that custom civilisations use.** There is one conceptual trait vocabulary; “official” civs are not a separate ruleset.

### Rules

- Predefined civs **must not** introduce **gameplay rules** that custom civs could **never** express via the same trait system.
- If a predefined civ needs something that feels **unique**, that uniqueness should become a **trait** (or trait bundle) first; the civ then **selects** that trait like any custom profile.
- Predefined civs **should normally** obey the **same trait budget** as custom civs.
- **Early curated prototypes** may **temporarily violate** the budget **only if** the deviation is **explicitly documented** in that profile’s **`notes`** field.
- Once a trait budget is **implemented** in a later subphase, any documented deviation becomes **technical debt** to reconcile (either adjust the civ or add missing traits).

## Civilisation profile model

This section is **conceptual only**. It is **not** an implemented schema.

- **`id`** — stable string id for documentation and future registry rows.
- **`display_name`** — human-readable label.
- **`profile_type`** — `predefined` | `custom` | `debug_example`
- **`origin_traits`** — geography / climate / founding-era seed (conceptual tags).
- **`society_traits`** — e.g. kinship, urban, nomadic, pluralistic.
- **`governance_traits`** — e.g. council, chieftain, pluralist structures.
- **`value_traits`** — e.g. prestige, stability, curiosity, piety.
- **`advantage_traits`** — positive systemic biases (prose in 3.5a).
- **`weakness_traits`** — explicit negative biases; in a future budget, weaknesses **refund** points.
- **`progression_biases`** — bias hints for sciences, breakthroughs, unlock **presentation** (not enforcement in 3.5a).
- **`visual_identity`** — palette, motifs, banner direction; **no asset paths** in 3.5a.
- **`city_naming_style`** — naming conventions / placeholder strategy (prose).
- **`notes`** — free prose, including **any documented budget deviation** for early prototypes.

**In 3.5a:** no `class_name`, no `.gd` file, no validators, no registry, no serialized JSON/tres format.

## Balanced trait model

This section is **conceptual only**. It is **not** implemented.

Each trait is described by:

- **`id`** — stable string id.
- **`category`** — one of the categories listed below.
- **`display_name`** — human label.
- **`cost`** — **conceptual** sign/magnitude only (**no numeric values** in 3.5a).
- **`effects`** — prose: intended bias on play feel / future systems.
- **`drawbacks`** — prose: explicit downside where applicable.
- **`tags`** — free vocabulary (e.g. `coastal`, `urban`).
- **`mutually_exclusive_tags`** — tags that **cannot** coexist within one profile.
- **`recommended_pairings`** — traits that combine well **thematically**.
- **`prototype_notes`** — mark prototype-only or experimental design intent.

### Trait categories

- `origin`
- `society`
- `governance`
- `value`
- `economy`
- `military`
- `science`
- `culture`
- `logistics`
- `weakness`
- `visual_theme`

### Balance principle (shape only)

- **Positive** traits **cost** points (in a future budget).
- **Weakness** traits **refund** points.
- Some traits are **mutually exclusive** (by tags or explicit rules, TBD in implementation).
- **Predefined civs** should obey the **same** budget as custom civs; **documented exceptions** allowed only during early prototyping.
- **3.5a** documents the **shape** of the budget, **not** the numbers.

## Relationship to progression

- **3.5a is a bias layer**, not a rewrite of the progression model.
- The **shared progression chain** remains:

  **`ProgressDefinitions`** → **`ProgressUnlockResolver`** → **`ProgressState`** → **`CompleteProgress`** → **`ProgressDetector`** → **`ProgressCandidateFilter`**.

- The **same `progress_id`** (e.g. `controlled_fire`) may be **culturally framed** differently per civ profile in **future** presentation or flavour text; **no** such wiring exists in 3.5a.
- **No** presentation layer, **no** registry changes, **no** detector changes, **no** `LegalActions`, **no** AI, **no** `GameState` changes in 3.5a.

### Controlled Fire — framing examples (non-binding flavour)

- **Hearthbound-style profile:** hearth, settlement comfort, survival around the fire.
- **Wayfinder-style profile:** camp discipline, mobility, frontier survival.
- **Forge-style profile:** heat control, material handling, workshop foundation.

### Future (not 3.5a)

Traits **may later** affect, among other things:

- detector weights
- unlock presentation
- costs
- starting unlocks
- progression speed
- specialist / building / unit preferences

**None of this is implemented in 3.5a.**

## Prototype predefined factions

The three profiles below are **prototype candidates** — **not final canon**, **not** the final roster — intended to **test** whether the identity model can express coherent strengths, weaknesses, and progression hints.

Each uses **`profile_type: predefined`**.

### A. The Hearthbound

| Field | Content |
|--------|---------|
| **One-line fantasy** | Early settled communities built around hearth, food security, kinship, and stable growth. |
| **Likely strengths** | Growth, health, settlement comfort, defensive stability. |
| **Likely weaknesses** | Slower exploration or weaker early mobility. |
| **Likely trait direction** | Settlement, stability, kinship, food security, survival. |
| **Visual direction** | Ochre, clay, warm red, smoke, hearth, circle, shelter motifs. |
| **Progression connection** | *Controlled Fire*, *Foraging Systems*, storage, settlement comfort, defensive stability — framed as hearth and household. |

### B. The Wayfinders

| Field | Content |
|--------|---------|
| **One-line fantasy** | Route-makers, scouts, trackers, and frontier-adapted societies. |
| **Likely strengths** | Scouting, terrain memory, exploration, adaptation. |
| **Likely weaknesses** | Weaker dense urban production or lower stability in large cities. |
| **Likely trait direction** | Exploration, mapping, terrain familiarity, hunting, frontier adaptation. |
| **Visual direction** | Green-blue-gray, trail marks, stars, bones, leather, landmarks. |
| **Progression connection** | *Oral Surveying*, *Animal Tracking*, map notes, landmarks, tracking — framed as routes and memory. |

### C. The Forge Compact

| Field | Content |
|--------|---------|
| **One-line fantasy** | Organised practical builders focused on tools, workshops, material control, and infrastructure. |
| **Likely strengths** | Production, workers, quarry/mining, military equipment. |
| **Likely weaknesses** | Culture/influence or flexibility (relative to other prototypes). |
| **Likely trait direction** | Production, tools, labour organisation, material discipline, infrastructure. |
| **Visual direction** | Bronze, soot, stone, hammer, wedge, structured geometry. |
| **Progression connection** | *Stone Tools*, quarry, worker, workshop and armory flavour — tools, metallurgy, material pipeline. |

## Non-canonical toy custom-civ examples

The three profiles below are **`profile_type: debug_example`**. They are **non-canonical**, **playful**, **playtest-oriented** **test vectors** for trait composition. They are **not final lore** and **not** a statement that the game world is built around these joke factions.

**Tone guard:** playful, respectful, clearly non-final; stress-test the model without overfitting global design to any one joke.

### A. Västerviksjävlarna

- **One-line fantasy:** Coastal, stubborn, overambitious, theory-heavy proto-civilisation with poor practical logistics.
- **Likely traits:** `origin: coastal_people`; `science: theoretical_research_culture`; `value: stubborn_independence`; `weakness: poor_logistics`; `weakness: impractical_implementation`.
- **Strength bias:** Science / progress insight.
- **Weakness bias:** Logistics, practical conversion, production inefficiency.
- **Visual joke:** Defiant fishing-village banner, sea-storm palette.
- **Useful as test vector:** Extreme **science vs. logistics** asymmetry.

### B. Malmöfubikkarna

- **One-line fantasy:** Blunt, practical, urban fighters with lower science but higher combat value.
- **Likely traits:** `origin: urban_coastal_people` or `dense_city_clans`; `military: strong_militia_tradition`; `society: pragmatic_mobilization`; `weakness: lower_theoretical_science`; `weakness: diplomatic_rough_edges`.
- **Strength bias:** Combat, local defence, mobilization.
- **Weakness bias:** Science, diplomacy.
- **Visual joke:** Gritty industrial-port banner.
- **Useful as test vector:** Militia / urban-resilience identity **without** science focus.

### C. Pajasarna från Paris

- **One-line fantasy:** Culture-heavy performance society with strong influence and questionable discipline.
- **Likely traits:** `culture: theatrical_public_life`; `value: prestige_and_style`; `diplomacy: soft_power_networks`; `weakness: military_discipline_gap`; `weakness: practical_overhead`.
- **Strength bias:** Culture, influence, diplomacy, morale.
- **Weakness bias:** Military discipline, production practicality.
- **Visual joke:** Theatrical-mask banner.
- **Useful as test vector:** Pure **soft-power** profile vs. stability, production, and combat-heavy prototypes.

## Prototype art policy

- **Generated images** are **allowed** for **internal prototype acceleration**.
- **Placeholder** and **generated** art must be **easily replaceable**.
- Prototype assets should be **stored or labelled** as **non-final**.
- **Prompts and provenance** should be kept **when practical**.
- Optimise for **readability and atmosphere**, not commercial certainty.
- **Gameplay must not depend** on a **specific** generated image (identity should survive asset swap).
- **Generated images must not lock final canon prematurely.**
- Prototype art decisions here are **internal-test guidance**, **not** Steam/release or final commercial policy.

### Preferred prototype visual direction

- Stylised painterly strategy art
- Readable silhouettes
- Faction palette accents
- Strong emblems, banners, and icons
- Atmospheric but not over-detailed
- Easy to replace later

## Generated asset safety

- Generated and prototype assets are **fine for internal testing**.
- They are **not** final commercial-release assets **by default**.
- A later wider release may require **replacement**, **licensing review**, **commissioned art**, or **internally produced final art**.
- Prototype assets should stay **isolated** from final-asset assumptions — no workflow should treat a prototype PNG as canonical lore.
- **No system** should depend on **exact** prototype image pixel content.
- **Final lore, aesthetics, naming, and IP review** stay in **Phase 6**.

**Do not create `ART_DIRECTION.md` in 3.5a.** If real asset work begins, consider splitting a dedicated art-direction doc (e.g. **`ART_DIRECTION.md`**) around **Phase 3.5d** or **Phase 4** — not before assets exist.

## Phase mapping

- **3.5a** — Docs-only faction / custom-civ identity model (**this file**).
- **3.5b** — Possible tiny **`FactionDefinitions`** registry seed (future; not 3.5a).
- **3.5c** — Possible trait registry or concrete profile examples (future).
- **3.5d** — Possible prototype presentation / visual identity pass (future).
- **Later** — Custom civ builder UI, balance system, art pipeline, **final** lore and IP review (**Phase 6**).

## Explicit non-goals

- No full lore bible
- No final faction roster
- No final trait costs
- No trait math implementation
- No point-budget implementation
- No UI
- No assets
- No generated image **creation** in this phase
- No gameplay effects
- No AI changes
- No `LegalActions` changes
- No `GameState` changes
- No Steam / release policy
- No final art pipeline commitment

## Relationship to existing docs

- **[PHASE_PLAN.md](PHASE_PLAN.md)** — Phase roadmap; **Phase 3.5** mechanical identity vs **Phase 6** lore, copy, naming, aesthetics, and IP review.
- **[PROGRESSION_MODEL.md](PROGRESSION_MODEL.md)** — Shared progression vocabulary; faction identity **may later bias interpretation** of progress but **does not** modify that model in 3.5a.
- **[CONTENT_MODEL.md](CONTENT_MODEL.md)** — ID, definition, and state vocabulary for future registries (referenced conceptually; **not edited** in 3.5a).
- **[DECISION_LOG.md](DECISION_LOG.md)** — Decision trace for phase checkpoints.
- **[PROJECT_BRIEF.md](PROJECT_BRIEF.md)** — High-level project intent and **IP boundary**.

**Ownership split:**

- **Phase 6** owns **lore**, **final copy**, **final naming**, **deep aesthetics**, **worldbuilding**, and **IP review**.
- **Phase 3.5a–d** own the **mechanical / structural identity layer** — preset + custom civ **shape**, trait vocabulary **at the concept level**, and internal prototype-art **rules** — **before** full worldbuilding.
