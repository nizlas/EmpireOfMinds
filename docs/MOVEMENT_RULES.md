# Empire of Minds — Movement rules (Phase 1.5)

## Where rules live

- **`MovementRules`** ([game/domain/movement_rules.gd](../game/domain/movement_rules.gd)) is **`RefCounted`** domain code with **static** query methods only — **no** instance state, **no** `Node`, **no** rendering, **no** input.
- Legality is **not** implemented on **`Scenario`** (data bundle) or **`Unit`** (value object) so rule logic does not accumulate on immutable aggregates.
- **`HexMap`** and **`Terrain`** remain **tags only** in the map model; interpreting terrain for movement happens **here**, not inside `HexMap`.

## Phase 1.5 rule: one-step legal destinations

**`MovementRules.legal_destinations(scenario, unit_id) -> Array`** returns a list of **`HexCoord`** cells the unit could move into in **one** step, given:

1. The cell is a **neighbor** of the unit’s current `position` (`HexCoord.neighbors()` order is irrelevant; the result is a set of coords).
2. **`scenario.map.has(coord)`** — destination exists on the map.
3. **`TerrainRuleDefinitions.is_passable_hex_map_value(scenario.map.terrain_at(coord))`** — destination terrain must be **passable** per [terrain_rule_definitions.gd](../game/domain/content/terrain_rule_definitions.gd) (today **`plains`** passable, **`water`** not). Definitions include **`movement_cost`**, which is **metadata only** in **3.2** and does **not** change one-step range.
4. **`scenario.units_at(coord).size() == 0`** — destination is **not occupied** by any unit.

**`FoundCity.validate`** still uses **`tile_is_water`** against **`HexMap.Terrain.WATER`** directly; routing founding through **`TerrainRuleDefinitions`** is **deferred** so city and movement rule modules stay independently testable for now.

**Phase 3.2 (implemented):** passability is **global** (not unit-type-specific); unknown enum values fail **closed** as impassable.

Returns **`[]`** if `scenario` is **`null`**, **`unit_id`** is unknown, or the unit is missing from the scenario.

**No** pathfinding, **no** range beyond one hex, **no** movement points. **`MoveUnit`** validation **reuses** this list for legality; **state change** is **`MoveUnit.apply`** + **`GameState`** (see [ACTIONS.md](ACTIONS.md)).

## Layer boundary

`game/domain/movement_rules.gd` must not reference Godot scenes, `_draw`, input, or assets. See [game/domain/README.md](../game/domain/README.md).

## Explicitly deferred

- Range > 1, **consuming** **`movement_cost`** for legality or path budget, roads, railways.
- Stacking, zone of control, friendly/enemy blocking beyond “occupied”.
- Pathfinding (A*, etc.).
- Turn ownership (“only current player may query”) — Phase 1.7+.
