# Empire of Minds — Actions and local session (Phase 1.6+)

## Overview

Gameplay changes are expressed as **explicit actions** (see [ARCHITECTURE_PRINCIPLES.md](ARCHITECTURE_PRINCIPLES.md)), not as ad-hoc mutation from UI or AI:

```text
intent
  -> validation
  -> application (domain)
  -> structured log append (accepted only)
  -> presentation reflects new Scenario
```

**Phase 1.6** introduces **`move_unit`**, **`GameState`**, and **`ActionLog`**. **Phase 1.7** adds **`TurnState`**, **`end_turn`**, and a **common current-player gate** in **`GameState.try_apply`** (see [TURNS.md](TURNS.md)). **Phase 1.8** adds **legal-action enumeration** for the current player (see below, [AI_LAYER.md](AI_LAYER.md)). **Phase 2.2b** adds **`found_city`** (`FoundCity`): structural validation and **`Scenario`** rebuild that consumes the founding unit and appends a **`City`** with **`city_id = peek_next_city_id()`** before apply (see [CITIES.md](CITIES.md)). **Phase 2.3** adds **`set_city_production`** (`SetCityProduction`): sets a city’s **`current_project`** primitive **`Dictionary`** (or **`null`** to clear); **no** production progress or unit creation in that phase (see [CITIES.md](CITIES.md)). **Phase 2.4a** adds an **engine** **`production_progress`** log step on **accepted** **`end_turn`**. **Phase 2.4b** introduced **`produce_unit`** **completion** (threshold) on tick. **Phase 2.4c** **defers** **`unit_produced`** / unit spawn until the **owner** becomes **`current_player_id`** again (**`ProductionDelivery`** after **`end_turn`**); see **Production on EndTurn (Phase 2.4a–c, engine)** below.

## Legal action enumeration (Phase 1.8, extended Phase 2.5)

**`LegalActions.for_current_player(game_state) -> Array`** in [legal_actions.gd](../game/domain/legal_actions.gd) returns a **deterministically ordered** list of player-action **`Dictionary`** values:

1. All legal **`MoveUnit.make(...)`** for **`game_state.scenario`** under **`MovementRules.legal_destinations`** for each **current-player** unit (deterministic unit and destination order; see [AI_LAYER.md](AI_LAYER.md)).
2. **Phase 2.5:** each **current-player** unit’s **`FoundCity.make`** at its current tile, **only** if **`FoundCity.validate`** passes (policy-agnostic; multiple cities per player are still enumerated if legal).
3. **Phase 2.5:** for each **current-player** city with **`current_project == null`**, **`SetCityProduction.make(..., "produce_unit")`** **only** if **`SetCityProduction.validate`** passes. Cities with any non-**`null`** project (including **`ready: true`**) emit **no** **`set_city_production`** here; **`"none"`** clear actions are **not** enumerated in this phase.
4. Exactly one **`EndTurn.make(current_player_id)`**, **last**.

**`production_progress`** and **`unit_produced`** remain **engine-only** log types and are **never** included in this list. Returns **`[]`** if **`game_state`** is **`null`**.

Enumeration is a **read-only query**: it does not mutate **`GameState`**, call **`try_apply`**, or filter by AI taste. **AI and debug UI** pick one entry from this list (or pass it to **`RuleBasedAIPlayer.decide`**) and still submit only through **`GameState.try_apply`**.

**Phase 1.8b:** AI turn length for **movement** is still gated by **`RuleBasedAIPolicy.has_actor_moved_this_turn`** ([rule_based_ai_policy.gd](../game/ai/rule_based_ai_policy.gd)). **Phase 2.5:** **`found_city`** and **`set_city_production`** do **not** count as **`move_unit`** for that policy (see [AI_LAYER.md](AI_LAYER.md)).

**Phase 3.0 / 3.1+:** Player-action **`Dictionary`** schemas may later carry content **IDs** (e.g. **`unit_type_id`**, **`project_id`**) per [CONTENT_MODEL.md](CONTENT_MODEL.md). Any required-field change **must** bump **`schema_version`** on that action. **Phase 3.0** introduces **no** schema changes.

## MoveUnit schema (Dictionary)

Actions are plain **`Dictionary`** values with **primitive** fields so they stay **easy to serialize** later for save/load and cloud.

| Field | Type | Meaning |
|--------|------|--------|
| `schema_version` | `int` | Currently `1` (`MoveUnit.SCHEMA_VERSION`). |
| `action_type` | `String` | Must be `"move_unit"` (`MoveUnit.ACTION_TYPE`). |
| `actor_id` | `int` | **Owner** of the unit (`unit.owner_id`); must match **`GameState.turn_state.current_player_id()`** when **`try_apply`** runs (common gate). |
| `unit_id` | `int` | Unit to move. |
| `from` | `Array` of two `int` | `[q, r]` must match the unit’s current `position`. |
| `to` | `Array` of two `int` | `[q, r]` destination; must be in **`MovementRules.legal_destinations`** for that unit. |

Built with **`MoveUnit.make(actor_id, unit_id, from_q, from_r, to_q, to_r)`** in [game/domain/actions/move_unit.gd](../game/domain/actions/move_unit.gd).

## Validation

**`MoveUnit.validate(scenario, action) -> { "ok": bool, "reason": String }`** runs checks in a **fixed order** (stable, testable reasons):

1. `scenario_null`
2. `wrong_action_type`
3. `unsupported_schema_version`
4. `malformed_action`
5. `unknown_unit`
6. `actor_not_owner`
7. `from_does_not_match_unit_position`
8. `destination_not_legal` — uses **`MovementRules.legal_destinations`** and **`HexCoord.equals`**.

## Application

**`MoveUnit.apply(scenario, action)`** may run only when **`validate`** returned **`ok`**.

- **Does not** mutate the input **`Unit`** or **`Scenario`**.
- Builds a **new** **`Unit`** for the moved id with the new **`HexCoord`**, copies other unit references from **`scenario.units()`**, and returns **`Scenario.new(...)`** passing forward **`scenario.map`**, **`new_units`**, **`scenario.cities()`**, **`scenario.peek_next_unit_id()`**, and **`scenario.peek_next_city_id()`** (see [CITIES.md](CITIES.md)) — **no** city or counter recomputation from remaining entities in **`apply`**.

## EndTurn schema (Phase 1.7)

| Field | Type | Meaning |
|--------|------|--------|
| `schema_version` | `int` | `1` (`EndTurn.SCHEMA_VERSION`). |
| `action_type` | `String` | `"end_turn"`. |
| `actor_id` | `int` | Must equal **`turn_state.current_player_id()`** at **`try_apply`** (enforced in **`GameState`**, not in **`EndTurn.validate`**). |

Built with **`EndTurn.make(actor_id)`** in [end_turn.gd](../game/domain/actions/end_turn.gd). **`EndTurn.validate`** is structural only; **`not_current_player`** is returned only from **`GameState.try_apply`**.

**`EndTurn.apply(turn_state, action)`** returns **`turn_state.advance()`** (new **`TurnState`**).

### Production on EndTurn (Phase 2.4a–c, engine)

**`production_progress`** and **`unit_produced`** are **not** player **`action_type`** values and **may not** be submitted through **`try_apply`**.

**On accepted `end_turn`, in order:**

1. **`ProductionTick.apply_for_player(scenario, ending_player_id)`** ([production_tick.gd](../game/domain/production_tick.gd)) runs **after** **`EndTurn.validate` succeeds** and **before** **`TurnState.advance`**. It emits only **`production_progress`** events. It **does not** spawn units or emit **`unit_produced`**.

2. **`TurnState`** is updated with **`EndTurn.apply`**.

3. The **`end_turn`** log entry is appended. **`try_apply(end_turn)`** returns this entry’s **`index`** (not any following **`unit_produced`** indices).

4. **`ProductionDelivery.deliver_pending_for_player(scenario, turn_state.current_player_id())`** ([production_delivery.gd](../game/domain/production_delivery.gd)) runs with the **new** current player. **`unit_produced`** events are appended **after** the **`end_turn`** entry.

**`GameState._init`** may run **`ProductionDelivery`** for the **opening** **`current_player_id`** when the initial **`Scenario`** already has **`ready`** **`produce_unit`** projects, appending **`unit_produced`** to a fresh **`ActionLog`** (**no** **`ProductionTick`** in **`_init`**).

**Who ticks (`ProductionTick`):** cities owned by the **ending** player with **`current_project != null`**, **`ready != true`** (missing **`ready`** treated as false), in **ascending `city.id`**.

**Tick increment:** **`progress` += 1** per eligible city; each tick emits **`production_progress`** with **`progress_after` = `progress_before` + 1**. When **`String(project_type) == "produce_unit"`** and **`progress_after` >= `cost`**, the project's **`ready`** is set **`true`**; **`current_project`** stays **non-null** until delivery. Other **`project_type`** values set **`ready`**: **`false`**. **No** **`peek_next_unit_id`** change in tick.

**Delivery (`ProductionDelivery`):** cities owned by the passed-in **`owner_id`** with **`produce_unit`**, **`ready == true`**, sorted by **`city.id`** ascending: allocate **`unit_id`**, append **`Unit`** at **`city.position`**, set **`current_project`** to **`null`**, advance **`peek_next_unit_id()`** by completion count; **`peek_next_city_id()`** unchanged. **Stacking** on the city hex **allowed**.

**`production_progress`** entry shape ( **`source`: `"engine"`** ):

| Field | Type | Meaning |
|--------|------|--------|
| `schema_version` | `int` | `1` (constant on **`ProductionTick`**, not an action schema). |
| `action_type` | `String` | `"production_progress"`. |
| `actor_id` | `int` | **Ending** player id. |
| `city_id` | `int` | City that gained **progress**. |
| `project_type` | `String` | From **`current_project`**. |
| `progress_before` | `int` | Old progress. |
| `progress_after` | `int` | **`progress_before + 1`**. |
| `cost` | `int` | From **`current_project`**. |
| `source` | `String` | `"engine"`. |
| `result` | `String` | `"accepted"`. |

**`unit_produced`** entry shape ( **not** registered in **`try_apply`** ):

| Field | Type | Meaning |
|--------|------|--------|
| `schema_version` | `int` | `1`. |
| `action_type` | `String` | `"unit_produced"`. |
| `actor_id` | `int` | **Recipient** / **city owner** (player whose pending production was delivered). |
| `city_id` | `int` | City that **completed**. |
| `unit_id` | `int` | Allocated from **`peek_next_unit_id()`** at delivery. |
| `position` | `Array` of two `int` | `[q, r]` = **`city.position`**. |
| `project_type` | `String` | `"produce_unit"`. |
| `source` | `String` | `"engine"`. |
| `result` | `String` | `"accepted"`. |

## FoundCity schema (Phase 2.2b)

| Field | Type | Meaning |
|--------|------|--------|
| `schema_version` | `int` | `1` (`FoundCity.SCHEMA_VERSION`). |
| `action_type` | `String` | `"found_city"`. |
| `actor_id` | `int` | Must match **`unit.owner_id`** in **`FoundCity.validate`**; must equal **`turn_state.current_player_id()`** at **`try_apply`** (common gate). |
| `unit_id` | `int` | Founder unit; **removed** from the returned **`Scenario`**. |
| `position` | `Array` of two `int` | `[q, r]` must match the unit’s current **`HexCoord`**. |

Built with **`FoundCity.make(actor_id, unit_id, q, r)`** in [found_city.gd](../game/domain/actions/found_city.gd).

### FoundCity validation order

**`FoundCity.validate(scenario, action)`** runs in this **fixed order** (does **not** check **`current_player_id`** — that is only **`GameState.try_apply`**):

1. `scenario_null`
2. `wrong_action_type` — `action` null, not a **`Dictionary`**, missing **`action_type`**, or **`action_type` != **`"found_city"`**
3. `unsupported_schema_version`
4. `malformed_action` — **`actor_id`**, **`unit_id`**, **`position`** shape and integer **`q`/`r`**
5. `unknown_unit`
6. `actor_not_owner`
7. `unit_not_at_position`
8. `tile_not_on_map`
9. `tile_is_water`
10. `tile_already_has_city`

### FoundCity application

**`FoundCity.apply(scenario, action)`** runs only when **`validate`** returns **`ok`**.

- Does **not** mutate the input **`Scenario`**, **`Unit`**, or **`City`** instances.
- **`city_id`** for the new **`City`** is **`scenario.peek_next_city_id()`** at apply time.
- Returned **`Scenario`** passes forward **`map`**, **`peek_next_unit_id()`**, all **non-founder** units, **existing cities** plus the new **`City`**, and **`peek_next_city_id() + 1`** for the next-city counter (no recomputation from entity lists).

## SetCityProduction schema (Phase 2.3)

| Field | Type | Meaning |
|--------|------|--------|
| `schema_version` | `int` | `1` (`SetCityProduction.SCHEMA_VERSION`). |
| `action_type` | `String` | `"set_city_production"`. |
| `actor_id` | `int` | Must match **`city.owner_id`** in **`SetCityProduction.validate`**; must equal **`turn_state.current_player_id()`** at **`try_apply`** (common gate). |
| `city_id` | `int` | Target **city** to update. |
| `project_type` | `String` | **`"produce_unit"`** or **`"none"`** (clear project). |

Built with **`SetCityProduction.make(actor_id, city_id, project_type)`** in [set_city_production.gd](../game/domain/actions/set_city_production.gd). **`cost`** is **not** part of the action payload: for **`produce_unit`**, **`apply`** assigns **`cost: 2`** and **`progress: 0`** inside a **fresh** project **`Dictionary`**.

### SetCityProduction validation order

**`SetCityProduction.validate(scenario, action)`** runs in this **fixed order** (does **not** check **`current_player_id`**):

1. `scenario_null`
2. `wrong_action_type`
3. `unsupported_schema_version`
4. `malformed_action` — **`actor_id`**, **`city_id`**, **`project_type`** (must be **`TYPE_STRING`**)
5. `unknown_city`
6. `actor_not_owner`
7. `unsupported_project_type` — string not **`"produce_unit"`** or **`"none"`**
8. `project_already_set` — **`produce_unit`** requested but city already has **`produce_unit`**, or **`none`** requested but **`current_project`** is already **`null`**

### SetCityProduction application

**`SetCityProduction.apply(scenario, action)`** runs only when **`validate`** returns **`ok`**.

- Does **not** mutate the input **`Scenario`** or **`City`** instances; replaces only the target **`City`** with **`City.new(id, owner, position, new_project)`** (see [CITIES.md](CITIES.md) for **`current_project`** deep-copy at construction).
- Returned **`Scenario`** passes forward **`map`**, **all** **`units()`**, all **non-target** **`City`** references as-is, **`peek_next_unit_id()`**, **`peek_next_city_id()`** unchanged.
- **Phase 2.4a–c** advance **`progress`**, mark **`produce_unit`** **`ready`**, and **deliver** units via **`ProductionDelivery`** (see **Production on EndTurn** above); there is **no** **`ProduceUnit`** player action.

## GameState

**[game_state.gd](../game/domain/game_state.gd)** (`class_name GameState`, `RefCounted`):

- **`var scenario`** — current authoritative **`Scenario`**.
- **`var turn_state`** — immutable **`TurnState`** snapshot; replaced when **`end_turn`** applies.
- **`var log`** — **`ActionLog`**.

**`try_apply(action) -> { "accepted": bool, "reason": String, "index": int }`**

- **`action`** must be a **`Dictionary`** with string **`action_type`** **`move_unit`**, **`end_turn`**, **`found_city`**, or **`set_city_production`**; otherwise **`unknown_action_type`** (also **`null`** / non-dict / missing **`action_type`** / non-string **`action_type`**).
- **Common gate** (these action types): **`actor_id`** must be present and **`TYPE_INT`**; **`actor_id == turn_state.current_player_id()`** or **`malformed_action`** / **`not_current_player`**.
- **`move_unit`**: **`MoveUnit.validate` → apply →** log entry as in Phase 1.6.
- **`found_city`**: **`FoundCity.validate` →** read **`created_city_id = scenario.peek_next_city_id()`** **before** **`apply`** (deterministic log) **`→ FoundCity.apply →`** log entry includes **`city_id`**, **`position`** (duplicate), **`unit_id`**, **`result: "accepted"`**.
- **`set_city_production`**: **`SetCityProduction.validate` → apply →** log entry includes **`city_id`**, **`project_type`**, **`result: "accepted"`**.
- **`end_turn`**: **`EndTurn.validate` →** **`ProductionTick.apply_for_player`** (optional **`production_progress`** **0..N**) **→** **`EndTurn.apply` (`turn_state`)** **→** append **`end_turn`** **→** **`ProductionDelivery.deliver_pending_for_player`** (optional **`unit_produced`** **0..M**) **after** **`end_turn`**. Returned **`index`** is the **`end_turn`** entry only.

On **reject**: **`accepted: false`**, **`index: -1`**, no log append, **`scenario` / `turn_state` / `log`** unchanged (except where only validation failed after gate — still no mutation).

On **accept**: updates **`scenario`** and/or **`turn_state`**, appends **deep-copied** log entries; for **`end_turn`**, **`production_progress`** entries, then **`end_turn`**, then **`unit_produced`** entries; returns **`index`** for **`move_unit`**, **`found_city`**, **`set_city_production`** as that entry’s index; for **`end_turn`**, **`index`** is always the **`end_turn`** entry.

## ActionLog

**[action_log.gd](../game/domain/action_log.gd)** stores **accepted** player **actions** (**`move_unit`**, **`end_turn`**, **`found_city`**, **`set_city_production`**) **and** engine **`production_progress`** / **`unit_produced`** entries (Phase 2.4a+)).

- **`append(entry)`** stores **`entry.duplicate(true)`** and sets **`index`** on the stored copy.
- **`get_entry`** and **`entries()`** each return **duplicates** so callers cannot corrupt history.

**Rejected** moves are **not** logged (return reason only); rejection logging / replay of failures is deferred.

**Phase 1.9:** presentation **`LogView`** ([log_view.gd](../game/presentation/log_view.gd)) surfaces **`ActionLog`** **read-only** (tail of accepted entries, explicit **`refresh()`** from input controllers). **`ActionLog`** append semantics, schemas, and **`GameState.try_apply`** behavior are **unchanged**.

## Presentation boundary

- **[selection_controller.gd](../game/presentation/selection_controller.gd)** submits **`MoveUnit`** via **`try_apply`** on **left-click** and **`FoundCity`** on **`F`** when a unit is selected; **`KEY_P`** is a **debug** hook that submits **`SetCityProduction`** for the **lowest-id** **current-player** city with **`current_project == null`** (see [RENDERING.md](RENDERING.md)). **[end_turn_controller.gd](../game/presentation/end_turn_controller.gd)** submits **`EndTurn`** on **Space**. **[ai_turn_controller.gd](../game/presentation/ai_turn_controller.gd)** drives **one** **`try_apply`** per **`A`** key press using **`LegalActions`** + **`RuleBasedAIPlayer.decide`**. None assign **`unit.position`** or re-build **`Scenario`** outside **`try_apply`**.
- After an **accepted** **`MoveUnit`**, **`SelectionController`** re-points **`selection_view.scenario`**, **`units_view.scenario`**, and its optional **`scenario`** mirror to **`game_state.scenario`**, **clears selection**, **`queue_redraw()`**, **`turn_label.refresh()`** / **`log_view.refresh()`** when wired ( **`cities_view`** unchanged on move in this phase).
- After an **accepted** **`FoundCity`**, **`SelectionController`** also re-points **`cities_view.scenario`** when **`cities_view`** is wired, **`queue_redraw()`** on **`cities_view`**, **`log_view.refresh()`**, and **clears selection**.
- After an **accepted** **`SetCityProduction`** via **`KEY_P`**, **`SelectionController`** re-points **`cities_view`** and **`scenario`** mirror when wired, **`queue_redraw()`** **`cities_view`**, **`turn_label.refresh()`**, **`log_view.refresh()`**; **does not** change **selection**.
- After an **accepted** **`EndTurn`**, **`EndTurnController`** **clears selection**, re-points **`selection_view` / `units_view`**, **`queue_redraw()`**, **`turn_label.refresh()`**.

## Explicitly deferred

- Turn **phases** (movement vs production), **lobby / seating**, **async** turn submission.
- Broader **AI** (LLM, planners, multi-action plans per turn, auto-run) — later phases; every submitted action still uses **`try_apply`**.
- **Save/load**, JSON/binary serialization, network transport — later phases.
- **Animation** of movement; units **teleport** in Phase 1.6.
- **Combat**, **economy/yields**, multi-hex pathfinding, movement points, stacking **enforcement** beyond **`found_city`** placement rules (multiple units per hex are **allowed** after engine delivery at cities).
- **`SetCityProduction`** in **`LegalActions`** / **AI** — deferred with other non-enumerated actions.
- A **`ProduceUnit`** **player** action — **not** used; **`produce_unit`** uses **`ready`** + **`ProductionDelivery`** (**Phase 2.4c**).
- **`FoundCity`** in **`LegalActions`** / **AI** — deferred to Phase **2.6**; **settler-only** founding — **Phase 3.1** unit definitions.
- **Undo / redo**, replay UI, structured rejection log.
