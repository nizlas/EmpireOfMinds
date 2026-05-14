# Empire of Minds — Cities (domain, Phase 2.1+)

## Representation

**`City`** ([city.gd](../game/domain/city.gd)) is a `RefCounted` value object with:

- **`id`**: `int` — unique among cities **within** a **`Scenario`** (enforced at construction).
- **`owner_id`**: `int` — same convention as **`Unit.owner_id`** (see [UNITS.md](UNITS.md)).
- **`city_name`**: **`String`** — **Phase 5.1.15:** display name for the city. **`FoundCity`** assigns the first founded city per owner **`Capital`**, then **`Settlement 2`**, **`Settlement 3`**, … (counting existing cities **of that owner** before append). Tests and tooling may construct **`City`** with an explicit fifth argument; **`""`** means “unnamed” until set. **`SetCityProduction`**, **`ProductionTick`**, and **`ProductionDelivery`** preserve **`city_name`** when rebuilding **`City`** rows.
- **`is_capital`**: **`bool`** — **Phase 5.1.16c:** **`true`** only for a player’s **first** city created by **`FoundCity`** in a save run (tests may set explicitly). **`ProductionTick`**, **`ProductionDelivery`**, and **`SetCityProduction`** preserve it on rebuilds.
- **`building_ids`**: **`Array[String]`** — **Phase 5.1.16c:** v0 **`FoundCity`** appends **`palace`** to the **capital** only; other cities default **empty**. Same rebuild preservation as **`city_name`**.
- **`owned_tiles`**: **`Array[HexCoord]`** — **Phase 5.1.16g:** territory footprint; **center hex first**, then other owned cells. Default construction is **`[position]`** only. **`FoundCity`** assigns **center +** valid **radius-1** map hexes (including **WATER**); no overlap between cities; ring tiles already owned are skipped. **Not** culture/border growth — minimal ownership for later **worked tiles** (**5.1.16h**). **`Scenario`** construction asserts every city owns its center, owned tiles lie on the map, and no tile is owned twice. **Prototype note (5.1.16g.2):** the **expanded** **g.1-lineage** **`make_prototype_play_map()`** (**island** with **full** outer **water**, **NE tongue**, **variegated** terrain, **smaller** **woods** patches) keeps **spatially separated** land anchors (see **`test_prototype_play_map_distribution.gd`**) so **`tile_already_owned`** / **coastal WATER** claims stay easy to exercise in headless tests.
- **`position`**: **`HexCoord`** — city tile; must be on the map and **not** **`HexMap.Terrain.WATER`**.
- **`current_project`**: **`null`** **or** a **primitive** **`Dictionary`** — **Phase 2.3+** current build / production state. **`null`** means **no** project. For **`produce_unit`**, the shape includes **`progress`**, **`cost`**, and **`ready`** (**`bool`**, **`false`** until **`progress` >= `cost`** on an **accepted** **`end_turn`** tick, **Phase 2.4c**). When a **`Dictionary`** is passed to **`City._init`**, the constructor stores **`duplicate(true)`** so later mutation of the caller’s **`Dictionary`** does **not** affect the **`City`**.

**Phase 3.3:** **`current_project`** may include **`project_id`** (e.g. **`"produce_unit:warrior"`**, **`"produce_unit:settler"`**), copied from **`SetCityProduction.apply`** into **`City`**. **`cost`** for that project comes from **`CityProjectDefinitions`**. Completed units’ **`Unit.type_id`** comes from **`CityProjectDefinitions.produces_unit_type(project_id)`** in **`ProductionDelivery`**, with a transitional **`"warrior"`** fallback when **`project_id`** is missing or unknown (legacy **`current_project`** rows).

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

**Phase 2.2b:** **`FoundCity`** ([found_city.gd](../game/domain/actions/found_city.gd)) creates a **`City`** at the founder **unit’s hex**, assigns **`city_id = peek_next_city_id()`**, sets **`city_name`** via **`FoundCity.default_city_name_for_owner`** (**`Capital`** / **`Settlement <n>`**), increments **`peek_next_city_id()` by 1** in the returned **`Scenario`**, and **removes** that **unit** from the unit list. **`GameState.try_apply`** dispatches **`FoundCity`** like other versioned actions; **`FoundCity.validate`** does **not** check **`current_player_id`** (**`not_current_player`** is only the common **`try_apply`** gate).

**Phase 3.1:** **founding** is gated by **`UnitDefinitions.can_found_city(unit.type_id)`** (see [UNITS.md](UNITS.md), [ACTIONS.md](ACTIONS.md)). The **F-key** path in **`SelectionController`** remains a manual presentation entry. **Phase 2.5:** **`LegalActions`** and **`RuleBasedAIPlayer`** may choose **`FoundCity`** and **`SetCityProduction`** from the legal list (see [AI_LAYER.md](AI_LAYER.md)); **no** new action schemas.

**Domain validation (structural only):** founder must **own** the **`actor_id`**, have a **`type_id`** that **can found** (**`UnitDefinitions.can_found_city`**), sit at **`position`**, on **land** (**not** **WATER**), on the **map**, on a hex **without** an existing **city**, and on a hex **not** already in another city’s **`owned_tiles`** (**`tile_already_owned`**, **Phase 5.1.16g**).

## Phase 5.1.16g — City territory foundation (domain)

**Phase 5.1.16g (shipped):** **`City.owned_tiles`** lists **`HexCoord`** cells the city controls (**center first**). **`FoundCity`** claims the **center** plus every **on-map** neighbor at hex distance **1** (including **WATER**); tiles already owned by another city are **skipped** on the ring, and founding on **any** owned tile is **`tile_already_owned`**. **`Scenario`** asserts **no** duplicate ownership, **all** owned tiles exist on the map, and each city **owns its center**. Read-only queries: **`tile_owner_city_id`**, **`city_owning_tile`**, **`tile_is_owned`**, **`tiles_owned_by_city`**. **`ProductionTick`**, **`ProductionDelivery`**, and **`SetCityProduction`** preserve **`owned_tiles`**. **`CityYields.city_total_yield`** still uses **only** center + buildings — **not** **`owned_tiles`** (**5.1.16h** adds worked-tile yield).

## Phase 2.3 — `current_project` and SetCityProduction (Phase 3.3 registry)

**`SetCityProduction`** ([set_city_production.gd](../game/domain/actions/set_city_production.gd)) updates **one** city’s **`current_project`** via **`GameState.try_apply`**. **Phase 3.3:** the player action carries **`project_id`** (**`schema_version` `2`**); **`PROJECT_ID_PRODUCE_UNIT_WARRIOR`** installs the **`produce_unit`** project shape (**`progress`**, **`cost`** from **`CityProjectDefinitions`**, **`project_id`**, **`ready: false`**); **`PROJECT_ID_NONE`** clears (**`current_project`** becomes **`null`**). **No** **unit** creation when setting production; **`progress`** increments on **accepted** **`end_turn`** (**`ProductionTick`**).

**`SetCityProduction.validate`** does **not** check **`current_player_id`** (**`not_current_player`** is only **`GameState.try_apply`**). Idempotent requests (**`project_already_set`**) are **rejected** (no log).

**Phase 2.5 (AI / legal list):** **`LegalActions`** may emit **`set_city_production`** for cities with **`current_project == null`** when **`SetCityProduction.validate`** passes, in deterministic order (**`produce_unit:warrior`** then **`produce_unit:settler`** when the latter is supported and unlocked). **`RuleBasedAIPlayer`** prefers filling an empty project before movement. **`PROJECT_ID_NONE`** clears are **not** enumerated in **2.5**.

## Phase 2.4a–c — Production on EndTurn (engine)

On **accepted** **`end_turn`**, **`ProductionTick`** ([production_tick.gd](../game/domain/production_tick.gd)) increments **`progress`** by **`CityYields.city_total_yield(scenario, city)["production"]`** (**Phase 5.1.16d**; replaces a fixed **+1**). It may set **`ready: true`** for **`produce_unit`** when **`progress` >= `cost`**; cities with **zero** **production** produce **no** **`production_progress`** event for that turn. **`production_progress`** log lines are appended **before** **`turn_state`** advances and **before** the **`end_turn`** entry. **`ProductionDelivery`** ([production_delivery.gd](../game/domain/production_delivery.gd)) runs **after** **`end_turn`** for the **new** **`current_player_id`**, appending **`unit_produced`** and spawning **Units** (see [ACTIONS.md](ACTIONS.md), [TURNS.md](TURNS.md), [UNITS.md](UNITS.md)). Initial **`GameState`** construction may deliver **`ready`** projects for the opening current player.

**Phase 3.3:** **`ProductionDelivery`** sets **`Unit.type_id`** via **`CityProjectDefinitions.produces_unit_type`** when **`current_project`** has a known **`project_id`**; legacy rows and unknown ids fall back to **`"warrior"`**. **`produce_unit:settler`** uses this same path — headless **`test_settler_production_flow.gd`** (Phase **5.1.3**) proves end-to-end delivery without engine code changes. **`unit_produced`** log rows stay **unchanged** (**no** **`type_id`** / **`unit_type_id`** on the event yet).

**[CitiesView](../game/presentation/cities_view.gd)** continues to draw cities from **`Scenario.cities()`**. **`SelectionController`** re-points **`cities_view.scenario`** after an **accepted** **`FoundCity`** (see [RENDERING.md](RENDERING.md)).

## Phase 5.1 city yields direction

**Phase 5.1.16c (shipped):** **`CityYields`** ([city_yields.gd](../game/domain/city_yields.gd)) computes **v0** **Food** / **Production** / **Science** / **Coin** from **`HexMap`** terrain, an optional **`HexMap.has_woods`** overlay (prototype disk only today), **city-center** minimums (**Food** ≥ 2, **Production** ≥ 1 from center rule), and buildings (**`palace`**: **+1 Science**, **+1 Coin**, **no** extra **Production**). **`ScienceTick`** consumes **`CityYields.science_for_player`** per **accepted** **end_turn** science step — not a flat **per-city** constant. **`produce_unit`** **production** remains the **`ProductionTick`** / **`ProductionDelivery`** path; **5.1.16d** **`ProductionTick`** advances **`progress`** by **`CityYields.city_total_yield`** **production** each tick (**founding location** / terrain / woods / center rule affect pacing).

**Earlier 5.1.0 docs** — **`produce_unit`** was the primary **visible** city **production** output; narrative “science” also pointed at **`CompleteProgress`** and project meters.

- The Ancient mini-game **embryo v0** reuses the **existing** **`produce_unit`** **`progress` / `cost` / `ready`** mechanic and **`ProductionTick`** / **`ProductionDelivery`** engine events for **unit production**; **5.1.16c** adds **institution**-style **science** from **`Palace`** (capital) toward **`ScienceTick`**.
- “Science progress” in player-facing descriptions still includes **completing** **`ProgressDefinitions`** sciences via **`CompleteProgress`**, **lightning** bonuses, and (**5.1.16c**) **Palace** baseline **science per turn** when tests/scenarios give the capital the **`palace`** building id.
- The **second** project **`produce_unit:settler`** is minted in **`CityProjectDefinitions`**; it is **default-unlocked** from turn **1** in **`ProgressState.with_default_unlocks_for_players`** alongside **`produce_unit:warrior`** (**Phase 5.1.12d**). Completing **`controlled_fire`** no longer adds that **`city_project`** row (see **[PROGRESSION_MODEL.md](PROGRESSION_MODEL.md)**).

See [PHASE_PLAN.md](PHASE_PLAN.md) **Phase 5.1**, [CORE_LOOP.md](CORE_LOOP.md) **Phase 5.1 embryo intent**.

**Player-facing tutorial:** The **intended** early city economy (worked-tile v0 yields, city-center normalization, capital **Palace** baseline **Science**/**Coin**, era-flexible **Coin** flavor, science-from-institutions principle) is summarized for testers in **[player/city-economy.html](player/city-economy.html)**. That page is **design intent**, not a guarantee of current build behavior.

**Phase 5.1.4:** **[CityProductionPanel](../game/presentation/city_production_panel.gd)** is **presentation-only**: it **never** reads **`CityProjectDefinitions`** or **`EffectiveRules`**; production buttons and gating come **only** from filtering **`LegalActions.for_current_player(game_state)`** for **`set_city_production`** rows matching the selected **`city_id`**. Labels derive from **`project_id`** substrings (no registry display names). **Phase 5.1.16e:** the same panel shows **total city yields** (**Food** / **Production** / **Science** / **Coin**) from **`CityYields.city_total_yield`** for the selected city (read-only; **no** worked-tile drill-down yet). **Phase 5.1.16f:** **`TileYieldOverlayView`** on the map shows per-hex **`CityYields`** (city totals vs **raw** terrain) when the **Yields** HUD toggle or **`KEY_Y`** is on (prototype inspection; not a new resource layer).

## Explicitly deferred

- **`ProduceUnit`** **player** action, economy/yields beyond this minimal completion rule.
- City **population**, **tiles worked** (beyond **`owned_tiles`** substrate; **5.1.16h**), **garrison**, **zone of control** (culture / dynamic borders).
- Procedural / culture-driven **renaming** and **nation name lists** (**5.1.15** ships deterministic placeholders only).
- **Combat**, **conquest**, **fog**, **save/load**.
- **Final** economy numbers and **Phase 4** visual identity.
