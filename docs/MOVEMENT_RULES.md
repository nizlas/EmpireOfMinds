# Empire of Minds — Movement rules (Phase 1.5 + **5.2.5** MP v0; **N7 world movement v1**)

## World movement v1 (N7a — `world_map` matches, server-authoritative)

World movement is implemented server-side in `server/app/domain/world_actions.py` and is **entirely separate** from the legacy `MovementRules` below (no `HexMap`, no `Scenario`, no adapter). Legality comes **exclusively** from the authoritative Python `WorldMap` loaded from canonical content ([MAP_MODEL.md](MAP_MODEL.md), [MAP_CONTENT.md](MAP_CONTENT.md)):

1. The destination tile must **exist** on the `WorldMap`.
2. The destination must be **adjacent** via the canonical axial neighbor deltas (`DIRECTIONS` in `server/app/domain/hex_coord.py`, parity with `hex_coord.gd`).
3. The derived edge between the tiles decides traversal: a **smooth** edge permits movement; a **cliff** edge blocks it (`destination_cliff_blocked`). A **missing edge record** between existing adjacent tiles rejects **fail-closed** (`destination_edge_missing`) — it is never treated as passable.
4. The destination must be **unoccupied** by any unit (`destination_occupied`).

There are **no movement points**, moved flags, water/terrain-category passability, pathfinding, or multi-step moves per action on the world path — a unit may take any number of single-step moves per turn. **No mesh, collision, sampled height, or presentation anchor ever decides legality.** The full first-failure rejection order and wire contract live in [CLOUD_API_V0.md](CLOUD_API_V0.md); the action inventory lives in [ACTIONS.md](ACTIONS.md). Clients never compute world legality (N7b, implemented, serves it via `legal-actions`). **Planned N7g (contract locked 2026-08-06):** a unit that has attacked this turn can neither move nor attack again until its owner's next turn (per-unit `has_attacked` flag — see [PHASE_PLAN.md](PHASE_PLAN.md) “Planned N7d–N8d”); movement itself stays budget-free, including moving before an attack.

Everything below this section is the **frozen legacy path** (retired in N9).

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
5. **Phase 5.2.5:** the unit’s **`remaining_movement >= 1`**. If exhausted, **`legal_destinations`** is **`[]`** (noMP-aware selection / **`LegalActions`**).

**`FoundCity.validate`** still uses **`tile_is_water`** against **`HexMap.Terrain.WATER`** directly; routing founding through **`TerrainRuleDefinitions`** is **deferred** so city and movement rule modules stay independently testable for now.

**Phase 3.2 (implemented):** passability is **global** (not unit-type-specific); unknown enum values fail **closed** as impassable.

Returns **`[]`** if `scenario` is **`null`**, **`unit_id`** is unknown, or the unit is missing from the scenario.

**Phase 5.2.5 (implemented):** each accepted **`MoveUnit`** deducts **1** from **`remaining_movement`** (flat step cost **regardless of terrain**). **`TerrainRuleDefinitions.movement_cost`** remains **metadata** for future slices — it does **not** affect **`MoveUnit`** spend or **`legal_destinations`** yet. **`max_movement`** comes from **`UnitDefinitions`**; MP is refilled when an owner **becomes** the current player (see **`Scenario.with_refreshed_movement_for_owner`**, **`GameState.try_apply`** after **`end_turn`**).

**No** pathfinding beyond one hex per action, **no** multi-hex paths in one **`MoveUnit`**. **`MoveUnit`** validation **reuses** this destination set for legality; **state change** is **`MoveUnit.apply`** + **`GameState`** (see [ACTIONS.md](ACTIONS.md)).

## Layer boundary

`game/domain/movement_rules.gd` must not reference Godot scenes, `_draw`, input, or assets. See [game/domain/README.md](../game/domain/README.md).

## Explicitly deferred

- Range > 1 **per accepted `MoveUnit`** (still one hex per action), **consuming** **`TerrainRuleDefinitions.movement_cost`** for legality or path budget (today flat **1** only), roads, railways.
- Stacking, zone of control, friendly/enemy blocking beyond “occupied”.
- Pathfinding (A*, etc.).
- Turn ownership (“only current player may query”) — Phase 1.7+.
