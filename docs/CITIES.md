# Empire of Minds — Cities (domain, Phase 2.1+)

## Representation

**`City`** ([city.gd](../game/domain/city.gd)) is a `RefCounted` value object with:

- **`id`**: `int` — unique among cities **within** a **`Scenario`** (enforced at construction).
- **`owner_id`**: `int` — same convention as **`Unit.owner_id`** (see [UNITS.md](UNITS.md)).
- **`position`**: **`HexCoord`** — city tile; must be on the map and **not** **`HexMap.Terrain.WATER`**.
- **`current_project`**: **`null`** **or** a **primitive** **`Dictionary`** — **Phase 2.3+** current build / production state. **`null`** means **no** project. For **`produce_unit`**, the shape includes **`progress`**, **`cost`**, and **`ready`** (**`bool`**, **`false`** until **`progress` >= `cost`** on an **accepted** **`end_turn`** tick, **Phase 2.4c**). When a **`Dictionary`** is passed to **`City._init`**, the constructor stores **`duplicate(true)`** so later mutation of the caller’s **`Dictionary`** does **not** affect the **`City`**.

**Phase 3.3 (planned):** **`current_project["project_id"]`** (per [CONTENT_MODEL.md](CONTENT_MODEL.md)) will reference the **city project definition** row; Phase **3.0** adds **no** key and current **`current_project`** behavior is unchanged.

Cities are **immutable** (no mutators): changes happen only via **`GameState.try_apply`** **player** actions (e.g. **`FoundCity`**, **`SetCityProduction`**) **or** via **engine** steps tied to an accepted **`end_turn`** (Phase **2.4a** **`production_progress`**, see [ACTIONS.md](ACTIONS.md)) that return a **new** **`Scenario`**.

## Scenario bundle

**`Scenario`** holds **`HexMap`**, **`units`**, **`cities`**, and two **replay-safe** counters:

- **`peek_next_unit_id()`** — next **`Unit.id`** to allocate when creating units (defaults to **`max(unit.id) + 1`** when omitted at construction, or **`1`** if there are no units).
- **`peek_next_city_id()`** — next **`City.id`** to allocate (defaults to **`max(city.id) + 1`**, or **`1`** if there are no cities).

**Backward compatibility:** **`Scenario.new(map, units)`** remains valid; **`cities`** defaults to **`[]`**, counters default to **auto** (internal sentinel **-1** triggers max-id computation).

When the **_explicit_** counter arguments are used, they **must** be **strictly greater** than every existing id in the corresponding list. That way, **consumed or removed** ids are never reused after a future action passes the prior counters forward. **Auto** mode is only for fresh bundles where no ids were ever issued beyond the listed objects.

**At most one city per hex** is enforced at **`Scenario`** construction.

The canonical **`make_tiny_test_scenario()`** fixture has **no cities** in Phase 2.1; tests that need cities build a **`Scenario`** with explicit **`City`** instances and valid positions on **`HexMap.make_tiny_test_map()`**.

## Presentation (Phase 2.1)

**[CitiesView](../game/presentation/cities_view.gd)** draws **placeholder diamond** markers from **`Scenario.cities()`** via **`compute_marker_items`**. **[main.tscn](../game/main.tscn)** orders **MapView → CitiesView → SelectionView → UnitsView** so terrain sits under cities, selection under units. **`main.gd`** wires **`cities_view.scenario`** at startup; **`SelectionController`** re-points **`cities_view`** after **accepted** **`FoundCity`** (Phase 2.2b). **`MoveUnit`** alone does not require **`cities_view`** updates unless cities already exist on the map.

**Phase 2.2a:** **`MoveUnit.apply`** ([move_unit.gd](../game/domain/actions/move_unit.gd)) passes **`cities()`** and **`peek_next_unit_id()` / `peek_next_city_id()`** forward into the returned **`Scenario`** so moves do not drop cities or replay counters (see [test_move_unit_preserves_scenario_state.gd](../game/domain/tests/test_move_unit_preserves_scenario_state.gd)). **Future** actions that rebuild **`Scenario`** must use the same explicit pass-forward pattern.

**Phase 2.2b:** **`FoundCity`** ([found_city.gd](../game/domain/actions/found_city.gd)) creates a **`City`** at the founder **unit’s hex**, assigns **`city_id = peek_next_city_id()`**, increments **`peek_next_city_id()` by 1** in the returned **`Scenario`**, and **removes** that **unit** from the unit list. **`GameState.try_apply`** dispatches **`FoundCity`** like other versioned actions; **`FoundCity.validate`** does **not** check **`current_player_id`** (**`not_current_player`** is only the common **`try_apply`** gate).

**Phase 3.1:** **founding** is gated by **`UnitDefinitions.can_found_city(unit.type_id)`** (see [UNITS.md](UNITS.md), [ACTIONS.md](ACTIONS.md)). The **F-key** path in **`SelectionController`** remains a manual presentation entry. **Phase 2.5:** **`LegalActions`** and **`RuleBasedAIPlayer`** may choose **`FoundCity`** and **`SetCityProduction`** from the legal list (see [AI_LAYER.md](AI_LAYER.md)); **no** new action schemas.

**Domain validation (structural only):** founder must **own** the **`actor_id`**, have a **`type_id`** that **can found** (**`UnitDefinitions.can_found_city`**), sit at **`position`**, on **land** (**not** **WATER**), on the **map**, on a hex **without** an existing **city**.

## Phase 2.3 — `current_project` and SetCityProduction

**`SetCityProduction`** ([set_city_production.gd](../game/domain/actions/set_city_production.gd)) updates **one** city’s **`current_project`** via **`GameState.try_apply`**. Supported **`project_type`** values: **`"produce_unit"`** (canonical shape includes **`"ready": false`**, **`progress`**, **`cost`**) and **`"none"`** (**`current_project`** becomes **`null`**). **No** **unit** creation when setting production; **`progress`** increments on **accepted** **`end_turn`** (**`ProductionTick`**).

**`SetCityProduction.validate`** does **not** check **`current_player_id`** (**`not_current_player`** is only **`GameState.try_apply`**). Idempotent requests (**`project_already_set`**) are **rejected** (no log).

**Phase 2.5 (AI / legal list):** **`LegalActions`** may emit **`set_city_production`** for cities with **`current_project == null`** ( **`produce_unit`** only when valid). **`RuleBasedAIPlayer`** prefers filling an empty project before movement. **`"none"`** clears are **not** enumerated in **2.5**.

## Phase 2.4a–c — Production on EndTurn (engine)

On **accepted** **`end_turn`**, **`ProductionTick`** ([production_tick.gd](../game/domain/production_tick.gd)) increments **`progress`** and may set **`ready: true`** for **`produce_unit`** when **`progress` >= `cost`**; **`production_progress`** log lines are appended **before** **`turn_state`** advances and **before** the **`end_turn`** entry. **`ProductionDelivery`** ([production_delivery.gd](../game/domain/production_delivery.gd)) runs **after** **`end_turn`** for the **new** **`current_player_id`**, appending **`unit_produced`** and spawning **Units** (see [ACTIONS.md](ACTIONS.md), [TURNS.md](TURNS.md), [UNITS.md](UNITS.md)). Initial **`GameState`** construction may deliver **`ready`** projects for the opening current player.

**Phase 3.1 (transitional):** delivered units are created with **`Unit.type_id == "warrior"`**. **Phase 3.3** will tie **`produce_unit`** (via **`project_id`** / city project definitions) to specific unit types; until then, **`unit_produced`** log rows stay **unchanged** (**no** **`type_id`** on the event).

**[CitiesView](../game/presentation/cities_view.gd)** continues to draw cities from **`Scenario.cities()`**. **`SelectionController`** re-points **`cities_view.scenario`** after an **accepted** **`FoundCity`** (see [RENDERING.md](RENDERING.md)).

## Explicitly deferred

- **`ProduceUnit`** **player** action, economy/yields beyond this minimal completion rule.
- City **names**, **population**, **tiles worked**, **garrison**, **zone of control**.
- **Combat**, **conquest**, **fog**, **save/load**.
- **Final** economy numbers and **Phase 4** visual identity.
