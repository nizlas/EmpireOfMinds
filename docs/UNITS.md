# Units and scenarios (domain)

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
