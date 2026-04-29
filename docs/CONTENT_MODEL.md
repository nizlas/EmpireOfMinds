# Empire of Minds — Content model (Phase 3.0 envelope)

## Status

- **Phase 3.0 is docs-only.** No code, no registries, no new `game/domain/content/` tree yet.
- **Phase 3.1+** will implement **content definitions** and wire them into validation, `LegalActions`, and fixtures per this document.
- **Phase 2.x** core loop is **unchanged** until an explicit later subphase changes it; behavior and tests today match [CORE_LOOP.md](CORE_LOOP.md).
- Exploratory candidates (units, projects, sciences, unlock chains) are collected in [CONTENT_BACKLOG.md](CONTENT_BACKLOG.md); that file is **non-canonical** input for Phase **3.1–3.5** and does not override this contract.

Authoritative genre/IP boundaries for public-facing identity remain in [PROJECT_BRIEF.md](PROJECT_BRIEF.md). This doc is an **engineering envelope** for IDs and registries, not final lore or balance.

## Pillars

- **Definitions are static and immutable** at runtime. They are edited only by shipping new code (or later, versioned data files if a future phase explicitly allows them).
- **Definitions are primitive / JSON-equivalent shaped** (`bool`, `int`, `float`, `String`, arrays and nested dictionaries of those). No `Node`, no `RefCounted` gameplay objects inside definition blobs.
- **State stores stable string IDs only.** Full definition rows live in registries, not inside `Unit`, `City`, or `Scenario` aggregates.
- **Registries expose read-only static lookup** (`get`, `has`, `ids`). No mutation API on the registry.
- **No autoload / singleton `ContentDB`.** Definitions remain ordinary domain modules so headless tests and future server code never depend on Godot scene/autoload plumbing.
- **No external JSON / `.tres` / Resource files yet.** First implementation pass uses **GDScript** registry modules under `game/domain/content/` (future path, not created in 3.0).
- **Deterministic iteration** for any API whose order surfaces in `LegalActions`, logs, or rebuilds (`ids()` must be sorted or insertion-ordered and documented).
- **Definitions are not gameplay state.** Only `Scenario` + `TurnState` + `ActionLog` / session types carry evolving run data.
- **`Scenario` remains a state snapshot** and **does not hold registry references** or embed definition tables.

## Where definitions will live

- **Future path:** `game/domain/content/` (not added in Phase 3.0).
- **Form:** GDScript modules (likely `class_name` + **static** methods) built from `const` tables or small helpers.
- **Planned static API shape:**
  - `get(id: String) -> Dictionary` — returns a deep **read** view or `null` if unknown
  - `has(id: String) -> bool`
  - `ids() -> Array` — deterministic order
- **No mutation API**, no `Node`, no **signals**, no `_process`, no dependency on scenes or assets.
- Rule code and action validators **preload** the canonical registry script and call **static** helpers (same pattern as existing domain `RefCounted` helpers with static methods).

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

- **`Unit.type_id`** (String) — **planned for Phase 3.1.** Today `Unit` has no type field; Phase 2.x behavior is generic.
- **`City.current_project["project_id"]`** (String) — **planned for Phase 3.3**, alongside existing `project_type` / progress fields. Today projects use the Phase 2.3 shape only.
- **Terrain semantics** move toward **content-defined terrain rules** in **Phase 3.2**; **`HexMap`** stays **tag-like** today per [MAP_MODEL.md](MAP_MODEL.md).
- **`Scenario` does not embed definitions** or registries; it only holds map, units, cities, and id counters.
- **Actions** may later carry content IDs (`unit_type_id`, `project_id`, etc.). Any change to required fields **must bump `schema_version`** and follow the versioning discipline in [ACTIONS.md](ACTIONS.md). **Phase 3.0 changes no action schemas.**

## Registry access strategy

- **Rule modules** may `const Registry = preload("res://domain/content/....gd")` and call static helpers.
- **`LegalActions`** may consult registries from **Phase 3.1 onward** (e.g. filter `FoundCity` to units whose type allows founding).
- **AI** consumes **`LegalActions` output** via **`RuleBasedAIPlayer.decide`**; it **does not** own or mutate content tables.
- **Registries must remain headless-testable** without instantiating scenes or autoloads.

See [AI_LAYER.md](AI_LAYER.md) for how AI stays on the legal-action path.

## Phase 3 subphase implications

Each subphase **must reference this document** when implementing code. Illustrative intent only—exact fields are fixed per subphase, not all in 3.0.

- **3.1 — Unit definitions:** registry of unit types; `Unit.type_id`; `FoundCity` / fixtures / `LegalActions` updated so founding and tests use explicit types where needed.
- **3.2 — Terrain rules and movement costs:** terrain rule registry; **`MovementRules`** consults definitions for passability/cost while keeping **`MovementRules`** as the legality oracle ([MOVEMENT_RULES.md](MOVEMENT_RULES.md)).
- **3.3 — City project definitions:** project registry; `current_project` gains `project_id`; **`SetCityProduction`** / **`ProductionDelivery`** tie **produce** completion to a definition (e.g. which `type_id` to spawn).
- **3.4 — First tech / progress definitions:** minimal tech/civic registry and shape; **scoped** slice, flavor deferred to Phase 6.
- **3.5 — First faction / world identity pass:** early mechanical knobs (e.g. faction id on players); **no** leader names or branded copy—that is Phase 6 ([PROJECT_BRIEF.md](PROJECT_BRIEF.md)).

## IP / non-Civ identity guardrails

Per [PROJECT_BRIEF.md](PROJECT_BRIEF.md) **IP Boundary**:

- **No** Civilization (or other commercial game) **names**, **leaders**, **exact tech tree**, **unique units**, **icons**, **UI layout copying**, or **exact systems**.
- **Generic role words** (`settler`, `warrior`, `plains`, `water`) are acceptable **scaffolding IDs**, not branded content.
- **Branded Empire of Minds** names for factions, units, and tech belong primarily in **Phase 6**; Phase 3 uses **placeholder** IDs such as `faction:em_first` or `tech:foundation` until steering updates add real copy.
- **Display strings** in future definition rows are **editable copy** and are **not** rule-bearing; rules key off **IDs** only.

## FAQ

**Why not an autoload?** Autoloads hide dependencies, complicate headless tests and future non-Godot validation, and encourage mutable service objects. Explicit `preload` + static registries keep the graph obvious.

**Why not JSON (or `.tres`) yet?** The project has no save/load pipeline that requires hot-reload data files. GDScript registries keep Phase 3.1–3.3 small, deterministic, and reviewable. External data belongs in a phase that also defines load errors, versioning, and modding—explicitly **not** Phase 3.0.

**How does save/load see content?** Snapshots and logs should store **state** (`type_id`, `project_id`, terrain id if any) that **references** definitions by ID. Definitions ship with the build; they are **not** duplicated in every save. When save/load lands, schema migration maps old IDs to new ones.

**Why not put definitions in `Scenario`?** Mixing static tables with per-turn state makes snapshots heavier, blurs authority (which client owns definitions in cloud play?), and encourages accidental mutation. **State** stays in `Scenario`; **definitions** stay in versioned code modules until a deliberate data phase says otherwise.

## Related docs

- [ACTIONS.md](ACTIONS.md) — player vs engine actions, schema versioning.
- [CITIES.md](CITIES.md) — city and production state (today).
- [UNITS.md](UNITS.md) — unit state (today).
- [AI_LAYER.md](AI_LAYER.md) — `LegalActions` and AI contract.
- [CORE_LOOP.md](CORE_LOOP.md) — frozen Phase 2.x loop; Phase 3 refines **content**, not the action pipeline shape.
