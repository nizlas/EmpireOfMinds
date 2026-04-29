# Units and scenarios (domain)

## Representation

**`Unit`** (see `res://game/domain/unit.gd`) is a `RefCounted` value object with:

- **`id`**: int — unique within a `Scenario` (enforced at construction).
- **`owner_id`**: int — which player or faction “owns” the unit. `Player` as a class is deferred; only integers are used in Phase 1.4.
- **`position`**: a `HexCoord` — where the unit sits. Must refer to a cell that exists on the map when placed inside a `Scenario`.
- **`type_id`**: **`String`** — stable id of the unit’s **content row** (see [CONTENT_MODEL.md](CONTENT_MODEL.md)). **`Unit._init`** defaults **`type_id`** to **`"warrior"`** so older **three-argument** call sites stay valid.

## Unit definitions (Phase 3.1)

**`UnitDefinitions`** ([unit_definitions.gd](../game/domain/content/unit_definitions.gd)) is a **static registry** ( **`class_name`**, **`RefCounted`**, **no** autoload): **`has`**, **`get_definition`** (deep **`Dictionary`** copy of one row — named this way because **`RefCounted`** cannot define **`get`** without clashing with **`Object.get`**), **`ids`** (fixed order **`["settler", "warrior"]`**), and **`can_found_city(type_id)`**. Real rows today:

- **`settler`** — **`can_found_city: true`**
- **`warrior`** — **`can_found_city: false`**

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

**Phase 1.6:** when a unit is selected, clicking a **legal destination** submits a **`MoveUnit`** Dictionary through **`GameState.try_apply`** (see [ACTIONS.md](ACTIONS.md)). On accept, **`UnitsView`** and **`SelectionView`** are re-pointed to **`game_state.scenario`**; selection is **cleared**. The controller does **not** move units directly.

See [SELECTION.md](SELECTION.md) and [MOVEMENT_RULES.md](MOVEMENT_RULES.md).

## Production spawn (Phase 2.4b–c, engine)

When a **`produce_unit`** project is **`ready`** (**`progress` >= `cost`** after a tick), **`ProductionDelivery`** (on **`GameState`** **`end_turn`** after **`TurnState.advance`**, or during **`GameState._init`** if the opening scenario already has **`ready`** work) appends a **`Unit`** with **`unit_id`** from **`peek_next_unit_id()`** at **`city.position`**. **Phase 3.1:** the spawned unit’s **`type_id`** is **`"warrior"`** until **Phase 3.3** ties projects to **`project_id`** / definitions ([CITIES.md](CITIES.md)). The new unit is owned by the **city owner** and appears when **that player** becomes **`current_player_id`**, not during the opponent’s turn. **Multiple** units per hex remain **allowed**. Not a **`ProduceUnit`** player action ([ACTIONS.md](ACTIONS.md)).

## FoundCity (Phase 2.2b, Phase 3.1)

**`FoundCity`** **consumes** the founding **unit**: after an **accepted** apply, that **`unit_id`** is **not** in **`Scenario.units()`**. **Phase 3.1:** only unit types with **`UnitDefinitions.can_found_city(type_id)`** (currently **`settler`**) may found; **`warrior`** and unknown **`type_id`** are rejected in **`FoundCity.validate`**.

## Explicitly deferred

The following are **out of scope** for Phase 1.4 and must not be assumed from the current types:

- Sprite, label, and health-bar **rendering** of units
- **Action-driven** selection or highlighting (e.g. only after a server-validated action); local **`MoveUnit`** does not replace cloud validation
- Pathfinding beyond one hex, movement points, and **non-move** actions
- Turn state, phases, and action points
- AI and automation
- Combat resolution
- Save/load
- Ownership transfer, renaming, and rich `Player` modeling
- A final **owner color palette** (placeholders in presentation only for 1.4b)
- Stacking **limits**, zone of control, and similar tactical rules (**multiple** units per hex are **allowed** after engine delivery at cities)
