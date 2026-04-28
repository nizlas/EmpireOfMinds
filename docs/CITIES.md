# Empire of Minds — Cities (domain, Phase 2.1+)

## Representation

**`City`** ([city.gd](../game/domain/city.gd)) is a `RefCounted` value object with:

- **`id`**: `int` — unique among cities **within** a **`Scenario`** (enforced at construction).
- **`owner_id`**: `int` — same convention as **`Unit.owner_id`** (see [UNITS.md](UNITS.md)).
- **`position`**: **`HexCoord`** — city tile; must be on the map and **not** **`HexMap.Terrain.WATER`**.

Cities are **immutable** (no mutators): changes happen only via future **`GameState.try_apply`** actions that return a **new** **`Scenario`**.

## Scenario bundle

**`Scenario`** holds **`HexMap`**, **`units`**, **`cities`**, and two **replay-safe** counters:

- **`peek_next_unit_id()`** — next **`Unit.id`** to allocate when creating units (defaults to **`max(unit.id) + 1`** when omitted at construction, or **`1`** if there are no units).
- **`peek_next_city_id()`** — next **`City.id`** to allocate (defaults to **`max(city.id) + 1`**, or **`1`** if there are no cities).

**Backward compatibility:** **`Scenario.new(map, units)`** remains valid; **`cities`** defaults to **`[]`**, counters default to **auto** (internal sentinel **-1** triggers max-id computation).

When the **_explicit_** counter arguments are used, they **must** be **strictly greater** than every existing id in the corresponding list. That way, **consumed or removed** ids are never reused after a future action passes the prior counters forward. **Auto** mode is only for fresh bundles where no ids were ever issued beyond the listed objects.

**At most one city per hex** is enforced at **`Scenario`** construction.

The canonical **`make_tiny_test_scenario()`** fixture has **no cities** in Phase 2.1; tests that need cities build a **`Scenario`** with explicit **`City`** instances and valid positions on **`HexMap.make_tiny_test_map()`**.

## Presentation (Phase 2.1)

**[CitiesView](../game/presentation/cities_view.gd)** draws **placeholder diamond** markers from **`Scenario.cities()`** via **`compute_marker_items`**. **[main.tscn](../game/main.tscn)** orders **MapView → CitiesView → SelectionView → UnitsView** so terrain sits under cities, selection under units. **`main.gd`** wires the initial **`scenario`** only; **controllers do not re-point **`CitiesView`** yet** (no cities in the canonical game loop this phase).

**Phase 2.2a:** **`MoveUnit.apply`** ([move_unit.gd](../game/domain/actions/move_unit.gd)) passes **`cities()`** and **`peek_next_unit_id()` / `peek_next_city_id()`** forward into the returned **`Scenario`** so moves do not drop cities or replay counters (see [test_move_unit_preserves_scenario_state.gd](../game/domain/tests/test_move_unit_preserves_scenario_state.gd)). **Future** actions that rebuild **`Scenario`** must use the same explicit pass-forward pattern.

## Explicitly deferred

- **`FoundCity`**, **`SetCityProduction`**, production tick, **`GameState.try_apply`** extensions.
- City **names**, **population**, **tiles worked**, **garrison**, **zone of control**.
- **Combat**, **conquest**, **fog**, **save/load**.
- **Final** economy numbers and **Phase 4** visual identity.
