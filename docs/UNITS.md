# Units and scenarios (domain)

## World units (N7a — server-authoritative, `world_map` matches)

On the opt-in **`world_map`** match path, units are **server-owned minimal state** in snapshot v3 (`server/app/domain/world_match.py`), separate from the legacy Godot `Unit`/`Scenario` types below: each unit is exactly `{"id": int, "owner_id": int, "position": [q, r], "type_id": "settler" | "warrior"}`, deterministically sorted ascending by `id`. World units carry **no** movement points or moved flag — world movement v1 has no movement budget ([MOVEMENT_RULES.md](MOVEMENT_RULES.md)) — and **no HP yet**: world Combat 0.1 is the planned **N7g** slice, which adds additive `current_hp` plus a per-turn `has_attacked` flag — contracts locked 2026-08-06: warrior-vs-warrior only, melee over smooth edges, attack ends the unit's turn actions ([PHASE_PLAN.md](PHASE_PLAN.md) “Planned N7d–N8d”).

**Starting units** come from the map-keyed spawn table in `server/app/domain/world_scenario.py` (validated against the canonical `WorldMap` at creation; divergence fails creation with no partial match). World creation requires exactly two **distinct** `player_ids` (exact non-boolean integers, arbitrary values, request order preserved); the first entry owns units 1–2 (settler, warrior), the second owns units 3–4. For `handdrawn_test_map_full_01`: unit 1 settler `[1,1]`, unit 2 warrior `[2,1]` (first player); unit 3 settler `[2,14]`, unit 4 warrior `[2,13]` (second player). Wire contract: [CLOUD_API_V0.md](CLOUD_API_V0.md).

**Presentation (N7c):** the world-play scene renders every snapshot unit as the existing 3D settler/warrior character via `game/presentation/world/world_units_view.gd` — one stable `Node3D` root per unit id, placed exactly at the N4 `TerrainWorld.tile_anchors[Vector2i(q, r)]` (derived presentation data, never gameplay authority; nothing renders until both snapshot and anchors exist — no origin fallback, no recomputed anchors, no raycast placement). The GLB character sits below a `ModelRoot` child (scale 0.5 at terrain scale S=1) and plays the audited idle clip. The locked **effective** forward is local −Z: both shipped rigs are authored facing +Z (the glTF convention; audited via the toe-vs-ankle rest direction), so every character instance is mounted with one shared convention-level 180° yaw (`MODEL_FORWARD_CORRECTION_YAW`) — never per-unit facing hacks. Selection and action submission are the **N7d** client world interaction loop (implemented 2026-08; manual/visual gate passed 2026-08-06 — served-legality-only markers and exact-served-row submission; [CLOUD_PLAY.md](CLOUD_PLAY.md)); the legacy `unit_3d_world_view` path below is **not** reused.

**Locomotion (N7f, implemented 2026-08-06; manual/visual gate PENDING):** accepted movement applies the authoritative snapshot and the new anchor to the unit root **immediately** — only the visual `ModelRoot` catches up, gliding one straight segment between the previous and new N4 anchors at `LOCOMOTION_SPEED_UNITS_PER_SEC = 1.6` world units/s (≈1.1 s per tile at S=1; the single tuning constant in `world_units_view.gd`). The semantic **`Walking`** clip plays while moving and **`Idle_3`** resumes on arrival, both through the audited per-type remap (`warrior_3d_animation_remap.gd`: settler `Running`/`Hit_Reaction_1`, warrior `Idle_02`/`Combat_Stance`); the audited clips carry no root-motion position tracks, so world displacement comes only from the locomotion layer. Facing is deterministic and **upright-humanoid**: the `ModelRoot` stays upright in world +Y and rotates with YAW ONLY so the locked effective −Z forward points along the horizontal movement direction, retained after arrival — terrain normals never pitch or roll the whole character. Terrain contact is **skeletal grounding** instead (`game/presentation/world/world_unit_leg_grounder.gd`, a `SkeletonModifier3D` under each character's skeleton — the supported post-animation pose override; bone map cached once: `Hips` / `Left|RightUpLeg` / `Left|RightLeg` / `Left|RightFoot`, identical on both shipped rigs): every frame, while walking and while idling, it samples the rendered top surface under BOTH feet independently, shifts the pelvis vertically by the lower foot target, and bends each knee with an analytic two-bone adjustment until the foot reaches its own terrain target — all within safe IK bounds (pelvis ≤ 0.35 and foot raise ≤ 0.6 of the leg length, targets clamped inside leg reach) and preserving bone lengths and the animated foot orientation. **Deliberately deferred fine-tune:** rotating the sole to match the local terrain normal (foot/ankle angle) — this pass eliminates floating/sinking, not sole-angle mismatch. Glide height and foot targets sample **only the rendered top surface** through `game/presentation/world/world_surface_sampler.gd` (short raycasts against the N3c.4 `TerrainCollision` top shape — never cliff walls, never gameplay legality; without a sampler the glide interpolates the two anchor heights and the skeleton keeps the animated pose). Initial spawn/reconnect snaps; identical snapshot reapplication never restarts a glide or clip; a newer accepted move mid-glide retargets from the in-flight visual position; removal cancels cleanly; the final pose is exactly the anchor pose. No path smoothing across moves, no client-side gameplay state from the interpolated pose ([PHASE_PLAN.md](PHASE_PLAN.md) N7f).

**Permanent WorldMap unit-render profile (N7c, locked):** the GLBs import fully metallic (`metallic 1.0`, `roughness 0.41`, `metallic_specular 0.5`), which renders yellow/golden under the warm N3c.7 key sun. Every rendered settler/warrior `StandardMaterial3D` surface therefore receives a **per-instance duplicated** material with `metallic 0.0`, `roughness 0.85`, `metallic_specular 0.3` — the same matte values the previously approved real-3D path used. The real albedo texture, albedo color, transparency/culling, and all other imported properties are preserved; imported GLB resources are never mutated. Filtering stays `TEXTURE_FILTER_LINEAR_WITH_MIPMAPS` with `mipmaps/generate=true` on the settler/warrior albedo imports (anisotropic filtering was tested on the prior path and rejected — no gain). The WorldMap 3D viewport renders with `Viewport.MSAA_2X` + `Viewport.SCREEN_SPACE_AA_FXAA`, configured once by `cloud_world_play.gd` on the existing viewport — no SubViewport/blit indirection.

Everything below is the **legacy (Godot local + Cloud v2) unit model**, frozen until its retirement in N9.

## Representation

**`Unit`** (see `res://game/domain/unit.gd`) is a `RefCounted` value object with:

- **`id`**: int — unique within a `Scenario` (enforced at construction).
- **`owner_id`**: int — which player or faction “owns” the unit. `Player` as a class is deferred; only integers are used in Phase 1.4.
- **`position`**: a `HexCoord` — where the unit sits. Must refer to a cell that exists on the map when placed inside a `Scenario`.
- **`type_id`**: **`String`** — stable id of the unit’s **content row** (see [CONTENT_MODEL.md](CONTENT_MODEL.md)). **`Unit._init`** defaults **`type_id`** to **`"warrior"`** so older **three-argument** call sites stay valid.
- **`max_movement`**: **`int`** — per-turn cap from **`UnitDefinitions`** (**5.2.5**).
- **`remaining_movement`**: **`int`** — how many **`MoveUnit`** steps (**cost 1** each in **5.2.5**) the unit may still take this turn; refilled when its owner **becomes** **`current_player_id`** (see **`Scenario.with_refreshed_movement_for_owner`**, **`GameState.try_apply`**).
- **`current_hp`** / **`max_hp`**: **`int`** — hit points; **`max_hp`** is **`UnitDefinitions.max_hp_for_type(type_id)`** at construction. **`Unit.new(..., p_current_hp := -1)`**: **`-1`** means full HP from definitions; explicit HP is carried through **`MoveUnit`**, movement refresh, and **`AttackUnit.apply_with_result`**.

## Unit definitions (Phase 3.1)

**`UnitDefinitions`** ([unit_definitions.gd](../game/domain/content/unit_definitions.gd)) is a **static registry** ( **`class_name`**, **`RefCounted`**, **no** autoload): **`has`**, **`get_definition`** (deep **`Dictionary`** copy of one row — named this way because **`RefCounted`** cannot define **`get`** without clashing with **`Object.get`**), **`ids`** (fixed order **`["settler", "warrior"]`**), **`can_found_city(type_id)`**, **`max_movement_for_type(type_id)`** (**5.2.5**), **`max_hp_for_type(type_id)`**, **`combat_strength_for_type(type_id)`** (melee strength for **`CombatRules`**; **`0`** means non-combatant for future expansion). **Combat strength** and **max HP** are registry fields; **current HP** is **`Unit`** instance state. Real rows today:

- **`settler`** — **`can_found_city: true`**, **`max_movement: 2`**, **`combat_strength: 0`**, **`max_hp: 100`**
- **`warrior`** — **`can_found_city: false`**, **`max_movement: 2`**, **`combat_strength: 20`**, **`max_hp: 100`**

Only types with **`can_found_city`** may **`FoundCity`** ([ACTIONS.md](ACTIONS.md)). Longer unit lists and flavor belong in [CONTENT_BACKLOG.md](CONTENT_BACKLOG.md); this file stays limited to **shipped** domain behavior.

Units are **immutable**: there are no setters, no `move()`, and no mutators on the type. **Phase 1.6** applies moves by **replacing** a unit with a new **`Unit`** at a new **`HexCoord`** inside a **new `Scenario`** (see [ACTIONS.md](ACTIONS.md), **`MoveUnit.apply`**).

## Owner ids

Owner identifiers are plain **integers**. A dedicated `Player` type, naming, and UI palette for owners are all **explicitly deferred**.

## Scenario

**`Scenario`** bundles a **`HexMap`** and a read-only list of **units**. It is:

- **Immutable** after construction: no `add_unit`, `remove_unit`, `move_unit`, or ownership changes.
- **Not** an autoload or singleton.
- **Not** a `Node` — it is pure domain data.

Queries such as `units()`, `unit_by_id`, `units_at`, and `units_owned_by` return information derived from the fixed unit list. `units()` returns a **duplicate** of the list so callers cannot mutate the scenario’s internal array.

**Layer boundary:** what belongs in the domain layer vs. presentation is summarized in [game/domain/README.md](../game/domain/README.md).

## Canonical fixture: `make_tiny_test_scenario()`

The static factory **`Scenario.make_tiny_test_scenario()`** builds a scenario on top of **`HexMap.make_tiny_test_map()`** with **three** units and **two** owner ids **0** and **1**:

- All unit positions are on **PLAINS** hexes: `(0,0)`, `(1,0)`, and `(0,-1)`.
- **Phase 3.1:** unit **`1`** (**P0**, **`(0,0)`**) and unit **`3`** (**P1**, **`(0,-1)`**) use **`type_id`** **`"settler"`**; unit **`2`** (**P0**, **`(1,0)`**) uses **`"warrior"`**, so each player keeps **one** **founding-capable** unit in the canonical fixture.
- The **WATER** hex at **`(-1,0)`** is **intentionally empty** (no unit there) so water vs land placement stays obvious in tests and docs.

## Presentation note (Phase 1.4b)

Simple **unit markers** (drawn circles, placeholder owner colors) are implemented in [game/presentation/units_view.gd](../game/presentation/units_view.gd) as a **read-only, derived** view of `Scenario.units()`. This is not gameplay state and does not add rules.

## Selection (Phase 1.5)

**Presentation-only** unit focus and **legal-movement overlays** (ring + destination tints) live in [selection_state.gd](../game/presentation/selection_state.gd), [selection_controller.gd](../game/presentation/selection_controller.gd), and [selection_view.gd](../game/presentation/selection_view.gd). **`SelectionState` holds a `unit_id` only**; it does **not** mutate **`Unit`** or **`Scenario`**. Legal destinations come from [movement_rules.gd](../game/domain/movement_rules.gd).

**Phase 1.6:** when a unit is selected, clicking a **legal destination** submits a **`MoveUnit`** Dictionary through **`GameState.try_apply`** (see [ACTIONS.md](ACTIONS.md)). **Local Combat 0.1:** with a **Warrior** selected, clicking an **adjacent** enemy **Warrior** submits **`AttackUnit`** first (before move / reselect handling). On accept, **`UnitsView`** and **`SelectionView`** are re-pointed to **`game_state.scenario`**; selection is **cleared**. The controller does **not** move units or resolve combat directly.

See [SELECTION.md](SELECTION.md) and [MOVEMENT_RULES.md](MOVEMENT_RULES.md).

## Production spawn (Phase 2.4b–c, engine)

When a **`produce_unit`** project is **`ready`** (**`progress` >= `cost`** after a tick), **`ProductionDelivery`** (on **`GameState`** **`end_turn`** after **`TurnState.advance`**, or during **`GameState._init`** if the opening scenario already has **`ready`** work) appends a **`Unit`** with **`unit_id`** from **`peek_next_unit_id()`** at **`city.position`**. **Phase 3.3:** the spawned unit’s **`type_id`** is **`CityProjectDefinitions.produces_unit_type(project_id)`** for known **`current_project.project_id`** (today **`"warrior"`** for **`produce_unit:warrior`**); missing or unknown **`project_id`** still yields **`"warrior"`**. The new unit is owned by the **city owner** and appears when **that player** becomes **`current_player_id`**, not during the opponent’s turn. **Phase 5.2.5:** delivered units initialize **`remaining_movement`** to full when the receiving **`GameState`** / refresh path applies (same timing as other units for that owner’s active turn). **Multiple** units per hex remain **allowed**. Not a **`ProduceUnit`** player action ([ACTIONS.md](ACTIONS.md)).

## FoundCity (Phase 2.2b, Phase 3.1)

**`FoundCity`** **consumes** the founding **unit**: after an **accepted** apply, that **`unit_id`** is **not** in **`Scenario.units()`**. **Phase 3.1:** only unit types with **`UnitDefinitions.can_found_city(type_id)`** (currently **`settler`**) may found; **`warrior`** and unknown **`type_id`** are rejected in **`FoundCity.validate`**.

## Explicitly deferred

The following are **out of scope** for Phase 1.4 and must not be assumed from the current types:

- Sprite, label, and health-bar **rendering** of units
- **Action-driven** selection or highlighting (e.g. only after a server-validated action); local **`MoveUnit`** does not replace cloud validation
- Pathfinding beyond one hex per accepted **`MoveUnit`**, **non-flat** movement costs from terrain, roads, rivers, embarkation
- Turn state machine subtleties **beyond** shipped **`TurnState`** + **5.2.5** MP refresh
- **Non-move** player actions not yet modeled as first-class **`LegalActions`** rows
- AI and automation
- **Combat** beyond **Local Combat 0.1** (adjacent Warrior vs Warrior, deterministic melee — see [ACTIONS.md](ACTIONS.md))
- Save/load
- Ownership transfer, renaming, and rich `Player` modeling
- A final **owner color palette** (placeholders in presentation only for 1.4b)
- Stacking **limits**, zone of control, and similar tactical rules (**multiple** units per hex are **allowed** after engine delivery at cities)
