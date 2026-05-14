# Empire of Minds — Content model

## Status

- **Phase 3.0** established this **engineering envelope** (IDs, boundaries, registry shape). Later phase-labeled slices **implemented** GDScript registries and wiring rather than superseding those rules.
- **Today**, `game/domain/content/` holds authoritative definition modules (**e.g.** **`UnitDefinitions`**, **`CityProjectDefinitions`**, **`ProgressDefinitions`**, **`TerrainRuleDefinitions`**, **`FactionDefinitions`**) with **`class_name`** + **static** read-only lookup, per the pillars below.
- **`EffectiveRules`** exists in code (`game/domain/effective_rules.gd`) as a **thin façade** over baseline registries; gameplay reads **toward** that boundary per [ARCHITECTURE_PRINCIPLES.md](ARCHITECTURE_PRINCIPLES.md). Further call sites migrate in small slices.
- **`RuleSet`** (validated match snapshot compiling to effective rules for play) remains **architecture direction** in § RuleSet / EffectiveRules below, [CLOUD_PLAY.md](CLOUD_PLAY.md), and [DECISION_LOG.md](DECISION_LOG.md). There is **no `RuleSet` GDScript type** yet—only registries plus **`EffectiveRules`**.
- The **Phase 2.x** loop shape (**`try_apply`**, turn order, core actions) persists; richer **content rows and gating** landed under later phases. Behavior and tests stay aligned with [CORE_LOOP.md](CORE_LOOP.md).
- Exploratory workbook-style ideas remain in [CONTENT_BACKLOG.md](CONTENT_BACKLOG.md); that file is **non-canonical** and must not override this contract.

Authoritative genre/IP boundaries for public-facing identity remain in [PROJECT_BRIEF.md](PROJECT_BRIEF.md). This doc is an **engineering envelope** for IDs and registries, not final lore or balance.

## Pillars

- **Definitions are static and immutable** at runtime. They are edited only by shipping new code (or later, versioned data files if a future phase explicitly allows them).
- **Definitions are primitive / JSON-equivalent shaped** (`bool`, `int`, `float`, `String`, arrays and nested dictionaries of those). No `Node`, no `RefCounted` gameplay objects inside definition blobs.
- **State stores stable string IDs only.** Full definition rows live in registries, not inside `Unit`, `City`, or `Scenario` aggregates.
- **Registries expose read-only static lookup** (`get`, `has`, `ids`). No mutation API on the registry.
- **No autoload / singleton `ContentDB`.** Definitions remain ordinary domain modules so headless tests and future server code never depend on Godot scene/autoload plumbing.
- **No external JSON / `.tres` / Resource files yet.** Definitions live in **`GDScript`** modules under **`game/domain/content/`** as shipped today (see § [Where definitions live](#where-definitions-live)).
- **Deterministic iteration** for any API whose order surfaces in `LegalActions`, logs, or rebuilds (`ids()` must be sorted or insertion-ordered and documented).
- **Definitions are not gameplay state.** Only `Scenario` + `TurnState` + `ActionLog` / session types carry evolving run data.
- **`Scenario` remains a state snapshot** and **does not hold registry references** or embed definition tables.

## Where definitions live

- **Path:** **`game/domain/content/`** (implemented).
- **Form:** **`class_name`** + **static** methods on **RefCounted**-extending scripts, built from **`const`** tables or small helpers (**e.g.** **`progress_definitions.gd`**).
- **Typical API shape** (exact names vary per registry):
  - `get(id: String) -> Dictionary` — deep **read** view or **`null`** if unknown
  - `has(id: String) -> bool`
  - `ids() -> Array` — deterministic order
- **No mutation API**, no `Node`, no **signals**, no `_process`, no dependency on scenes or assets.
- Rule modules and validators **`preload`** the canonical registry scripts and call **static** helpers.

Cross-links: [UNITS.md](UNITS.md), [CITIES.md](CITIES.md), [MAP_MODEL.md](MAP_MODEL.md), [MOVEMENT_RULES.md](MOVEMENT_RULES.md), [ACTIONS.md](ACTIONS.md).

## ID conventions

- **Lowercase `snake_case`**, **ASCII only**, pattern **`[a-z][a-z0-9_]*`**. (Optional single-level namespace below.)
- **Optional one-level namespace** with **`:`** only when it disambiguates families, e.g. **`produce_unit:settler`** vs plain **`produce_unit`** (transitional).
- **Examples (non-exhaustive placeholders, not final balance):**
  - **Unit type:** `settler`, `warrior`
  - **Terrain:** `plains`, `water` (align with content rules in Phase 3.2; map today still uses `HexMap.Terrain` tags)
  - **City project:** `produce_unit:settler`, `produce_unit:warrior`
  - **Transitional alias:** `produce_unit` (today’s broad token—may map to a default project definition during migration)
  - **Future tech placeholder:** `tech:foundation`
  - **Future faction placeholder:** `faction:em_first`
- **IDs are stable once shipped.** Renaming meaning requires a **new ID** plus a documented migration note (typically [DECISION_LOG.md](DECISION_LOG.md) + test updates).
- **Display names live inside definition rows**, not in IDs.
- **IDs must not collide with engine log `action_type` values:** `production_progress`, `unit_produced`, or any future engine-only types documented in [ACTIONS.md](ACTIONS.md).

## State-vs-definition boundary

- **`Unit.type_id`** (String) — **implemented**; references **`UnitDefinitions`** rows ([UNITS.md](UNITS.md)).
- **`City.current_project`** carries **`project_id`** and progress fields wired to **`SetCityProduction`** / **`ProductionDelivery`** ([CITIES.md](CITIES.md)).
- **Terrain semantics** for **movement** are read through **`TerrainRuleDefinitions`** (**Phase 3.2 implemented**); **`HexMap`** storage stays **enum tag-like** per [MAP_MODEL.md](MAP_MODEL.md).
- **`Scenario` does not embed definitions** or registries; it only holds map, units, cities, and id counters.
- **`City.owned_tiles`** (**`Array[HexCoord]`**, **Phase 5.1.16g**) — **state** on each **`City`** row (territory footprint), not a content definition or resource registry.
- **Actions** carry content IDs (**`project_id`**, **`type_id`** where applicable); any change to required fields **must bump `schema_version`** per [ACTIONS.md](ACTIONS.md).

## Registry access strategy

- **Rule modules** may `const Registry = preload("res://domain/content/....gd")` and call static helpers.
- **`LegalActions`** consults registries (**e.g.** founding gated by **`UnitDefinitions.can_found_city`**) and may take an optional **`EffectiveRules`** façade for supported-project checks.
- **AI** consumes **`LegalActions` output** via **`RuleBasedAIPlayer.decide`**; it **does not** own or mutate content tables.
- **Registries must remain headless-testable** without instantiating scenes or autoloads.

See [AI_LAYER.md](AI_LAYER.md) for how AI stays on the legal-action path.

## Phase 3 subphase implications

Each subphase **must reference this document** when implementing code. Illustrative intent only—exact fields are fixed per subphase, not all in 3.0.

- **3.1 — Unit definitions:** registry of unit types; `Unit.type_id`; `FoundCity` / fixtures / `LegalActions` updated so founding and tests use explicit types where needed.
- **3.2 — Terrain rules and movement costs:** terrain rule registry; **`MovementRules`** consults definitions for passability/cost while keeping **`MovementRules`** as the legality oracle ([MOVEMENT_RULES.md](MOVEMENT_RULES.md)).
- **3.3 — City project definitions:** project registry; `current_project` gains `project_id`; **`SetCityProduction`** / **`ProductionDelivery`** tie **produce** completion to a definition (e.g. which `type_id` to spawn).
- **3.4 — First tech / progress definitions:** minimal tech/civic registry and shape; **scoped** slice, flavor deferred to Phase 6. **Phase 5.1.12b (planned):** **`ProgressDefinitions`** science rows may also declare **`cost`** (**int**) and **`prerequisites`** (**`Array[String]`** of prerequisite science ids); see [PROGRESSION_MODEL.md](PROGRESSION_MODEL.md) Phase **5.1.12**.
- **3.5 — First faction / world identity pass:** early mechanical knobs (e.g. faction id on players); **no** leader names or branded copy—that is Phase 6 ([PROJECT_BRIEF.md](PROJECT_BRIEF.md)).

## IP / non-Civ identity guardrails

Per [PROJECT_BRIEF.md](PROJECT_BRIEF.md) **IP Boundary**:

- **No** Civilization (or other commercial game) **names**, **leaders**, **exact tech tree**, **unique units**, **icons**, **UI layout copying**, or **exact systems**.
- **Generic role words** (`settler`, `warrior`, `plains`, `water`) are acceptable **scaffolding IDs**, not branded content.
- **Branded Empire of Minds** names for factions, units, and tech belong primarily in **Phase 6**; Phase 3 uses **placeholder** IDs such as `faction:em_first` or `tech:foundation` until steering updates add real copy.
- **Display strings** in future definition rows are **editable copy** and are **not** rule-bearing; rules key off **IDs** only.

## FAQ

**Why not an autoload?** Autoloads hide dependencies, complicate headless tests and future non-Godot validation, and encourage mutable service objects. Explicit `preload` + static registries keep the graph obvious.

**Why not JSON (or `.tres`) yet?** The project has no save/load pipeline that requires hot-reload data files. In-code **`GDScript`** registries stayed small, deterministic, and reviewable for early phases. External data belongs in a phase that also defines load errors, versioning, and modding policy.

**How does save/load see content?** Snapshots and logs should store **state** (`type_id`, `project_id`, terrain id if any) that **references** definitions by ID. Definitions ship with the build; they are **not** duplicated in every save. When save/load lands, schema migration maps old IDs to new ones.

**Why not put definitions in `Scenario`?** Mixing static tables with per-turn state makes snapshots heavier, blurs authority (which client owns definitions in cloud play?), and encourages accidental mutation. **State** stays in `Scenario`; **definitions** stay in versioned code modules until a deliberate data phase says otherwise.

## RuleSet / EffectiveRules layer (Phase 5.0a)

**Architecture checkpoint** — full **RuleSet** packaging, deterministic validation/compilers, snapshot identity in saves, and cloud flows are **not** finished here. **Code today:** registries (**definitions**) plus a thin **`EffectiveRules`** façade; **no standalone `RuleSet` type** exists yet—see § [Status](#status).

Three conceptual layers:

1. **Definitions** — GDScript registries under **`game/domain/content/`** and other **baseline content providers**. How rows are authored follows the pillars above.
2. **RuleSet** — intended **canonical content snapshot** for a match (**curated** preset or **generated** world package); baseline registries remain **providers**, not bypass paths once compilation is fully wired.
3. **EffectiveRules** — **validated** / normalized **compiled** view that **gameplay** queries. Partially realized in **`effective_rules.gd`**; expansion continues in small slices.

**Snapshot metadata concepts** (exact field shapes deferred): **`ruleset_id`**, **`schema_version`**, **`source_kind`** (e.g. curated vs generated), **content hash**, **timestamp**.

- **Validation / repair / compilation** must be **deterministic** and able to run **without human review**.
- **Invalid** RuleSets are **rejected** or **repaired/recompiled** along deterministic rules; they are **not** silently played.
- **Human curation** is optional later: interesting **generated** RuleSets may be **promoted** to **curated** presets.

See [PROGRESSION_MODEL.md](PROGRESSION_MODEL.md) for **capability / material roles** and alternate world binding. See [CLOUD_PLAY.md](CLOUD_PLAY.md) for **RuleSet snapshot stability** and replay.

## EffectiveRules migration (Phase 5.1 onward)

**Current code:** **`EffectiveRules`** (**`domain/effective_rules.gd`**, **`RefCounted`**, **no** autoload) exposes reads such as **`is_city_project_supported`** over baseline **`CityProjectDefinitions`**. **`LegalActions.for_current_player`** accepts an optional **`effective_rules`** argument; callers may pass **`EffectiveRules.with_baseline_registries()`** or **`null`** (tests / legacy callers).

- Gameplay reads that still hit registries **directly** elsewhere should migrate toward the façade **in small slices**; registries remain **definition providers**, not alternate runtime oracles once a read is routed.
- **Phase 5.1.2 (implemented):** **`produce_unit:settler`** is a curated **`CityProjectDefinitions`** row. **Phase 5.1.12d:** **`controlled_fire`** no longer unlocks **Settler**; **`produce_unit:settler`** is **default-unlocked** from turn **1** in **`ProgressState.with_default_unlocks_for_players`** alongside **`produce_unit:warrior`**. **`LegalActions`** enumerates warrior then settler per empty city when each passes support and unlock checks. **`GameState.try_apply`** gates **`SetCityProduction`** via **`project_not_unlocked`** for locked projects.

See [PHASE_PLAN.md](PHASE_PLAN.md) **Phase 5.1** (slice detail), [CORE_LOOP.md](CORE_LOOP.md) **Phase 5.1 Ancient embryo**.

## Related docs

- [ACTIONS.md](ACTIONS.md) — player vs engine actions, schema versioning.
- [CITIES.md](CITIES.md) — city and production state; **5.1.16c** **`CityYields`** + capital **`Palace`** (see [MAP_MODEL.md](MAP_MODEL.md) woods overlay).
- [UNITS.md](UNITS.md) — unit state (today).
- [AI_LAYER.md](AI_LAYER.md) — `LegalActions` and AI contract.
- [CORE_LOOP.md](CORE_LOOP.md) — **Phase 2.x** baseline loop; **Phase 3+** expands **content** without changing **`try_apply` / turn** plumbing; Phase **5.1** overlays Ancient **science / settler embryo**.
