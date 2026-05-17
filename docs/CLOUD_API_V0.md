# Empire of Minds — Cloud API v0 (Cloud 0.1)

HTTP contract for the **local authority** prototype under `server/`. This is a **wire + persistence** slice, not a steering or gameplay-spec document.

**Authority pivot:** Python/FastAPI under `server/` is the **canonical gameplay authority target**; this document’s **`/v1`** match + snapshot + revision + `state_hash` + events shape is the **spine** that will gain **additional `action_type` values** and **richer snapshots** as slices **B–D** land—without changing rejection/HTTP semantics. **Full charter:** [AUTHORITY_PIVOT.md](AUTHORITY_PIVOT.md).

**Direction:** [CLOUD_PLAY_DIRECTION.md](CLOUD_PLAY_DIRECTION.md). **Strategy / BYOS:** [CLOUD_PLAY.md](CLOUD_PLAY.md).

## Principles

- Clients submit **actions** mirroring [ACTIONS.md](ACTIONS.md) / `GameState.try_apply` shape. **Cloud 0.1+ (Authority pivot)** accepts **`end_turn`**, **`move_unit`**, **`found_city`**, and **`set_city_production`** on **`POST /v1/matches/{id}/actions`**; other `action_type` values return **`unknown_action_type`** until their slices land.
- **Rejected** actions are **not** logged; responses use **HTTP 200** with `accepted: false` to mirror GDScript `try_apply` (not REST error semantics).
- **`state_hash`** is **never** stored inside `snapshot`; it is derived with `sha256(canonical_json(snapshot))` and returned by the API.

## `canonical_json`

- UTF-8 bytes of `json.dumps(snapshot, sort_keys=True, separators=(",", ":"), ensure_ascii=False)`.
- **`state_hash`**: lowercase hex SHA-256 digest of those bytes.

## Endpoints

| Method | Path | Notes |
|--------|------|--------|
| `GET` | `/v1/healthz` | `{ "ok": true }` |
| `POST` | `/v1/matches` | Optional body: `{ "player_ids": [0, 1], "scenario_id": "prototype_play" }`. Default players `[0, 1]`; default **`scenario_id`** **`"prototype_play"`**. Allowed: **`"prototype_play"`**, **`"tiny_test"`** (smaller map for tests). Unknown `scenario_id` → **HTTP 400**. |
| `GET` | `/v1/matches/{match_id}` | Latest snapshot; **404** if missing. |
| `POST` | `/v1/matches/{match_id}/actions` | Action body below; **404** if match missing. |
| `GET` | `/v1/matches/{match_id}/events` | All events. |
| `GET` | `/v1/matches/{match_id}/events?since=<index>` | Events with **`index > since`**. |

## Create match

**Response** includes `match_id`, `snapshot`, `revision`, `state_hash`.

### Snapshot schema v2 (Authority pivot Slice B — current)

Initial snapshots use **`schema_version`: `2`**. Top-level fields include the Cloud 0.1 envelope plus world model data for the **current playable loop** (map, starting units, default progress unlocks). **`action_log` is not embedded**; use **`GET /v1/matches/{id}/events`** for the append-only accepted-action log.

**Hex / coordinates in JSON**

- Unit/city **positions** and similar fields use **`[q, r]`** integer arrays (axial), not objects with string keys.
- Map **`cells`** are a sorted array of objects: `{ "q", "r", "terrain", "landform", "woods" }` with **`terrain`** ∈ `plains` | `water` | `grassland`, **`landform`** ∈ `flat` | `hills`, **`woods`** boolean.
- **`cells`** are sorted by **`(q, r)`**; **`units`** and **`cities`** by **`id`**; **`progress_state.by_owner`** by **`owner_id`**.

**Illustrative `snapshot` (trimmed; full map elided):**

```json
{
  "match_id": "...",
  "schema_version": 2,
  "revision": 0,
  "ruleset": { "id": "stub_v0", "content_hash": "stub", "schema_version": 0 },
  "scenario_id": "prototype_play",
  "scenario": {
    "next_unit_id": 4,
    "next_city_id": 1,
    "lightning_tree_hex": [3, 0],
    "map": { "cells": [{ "q": -6, "r": 0, "terrain": "plains", "landform": "flat", "woods": false }] },
    "units": [
      { "id": 1, "owner_id": 0, "position": [0, 0], "type_id": "settler", "remaining_movement": 2, "current_hp": 100 }
    ],
    "cities": []
  },
  "turn_state": { "players": [0, 1], "current_index": 0, "turn_number": 1 },
  "progress_state": {
    "by_owner": [
      {
        "owner_id": 0,
        "unlocked_targets": [
          { "target_type": "city_project", "target_id": "produce_unit:settler" },
          { "target_type": "city_project", "target_id": "produce_unit:warrior" }
        ],
        "completed_progress_ids": [],
        "science_progress": {},
        "science_observation_flags": {},
        "current_research_id": ""
      }
    ]
  }
}
```

**`next_city_id`:** matches Godot **`Scenario`** with no cities: **`peek_next_city_id()`** is **`_max_city_id([]) + 1` → `1`**.

**Slice C6 — `end_turn` production, food, **ScienceTick**, delivery, movement:** On an accepted **`end_turn`**, order matches Godot **`GameState.try_apply(end_turn)`** through **`ScienceTick`** ( **`ScienceTick.add_observation_bonus_if_eligible`** is **not** implemented on Cloud — lightning / move_unit log coupling only in Godot): (1) **`ProductionTick`**; (2) **`FoodGrowthTick`**; (3) **`ScienceTick`**: resolve target via **`current_research_id`** if set and **ScienceAvailability** says available, else first **`ScienceAvailability.available_for`** (lexicographic); if none, emit **`science_no_target`**; **`delta`** = sum of **`CityYields.city_total_yield` → `science`** over the ending player’s cities; if **`delta == 0`**, no science rows; else emit **`science_progress`** and maybe **`science_completed`** with **`unlocked_targets`** per **`ProgressUnlockResolver.complete_progress`** ( **`progress_definitions`** concrete_unlocks + systemic_effects only); (4) **`turn_state`** advance; (5) **`end_turn`** row (response **`index`**); (6) **`ProductionDelivery`**; (7) movement refresh. **`progress_state`** updates **only** in step (3). No combat, **`attack_unit`**, AI, roads, terrain move costs, or city automation.

**`found_city` (Slice C2):** matches Godot **`FoundCity`**: founding **`position`** must match the settler’s tile; **water** and **already-owned** tiles (any city’s **`owned_tiles`**) and tiles that **already have a city center** are rejected; the **founding unit is removed**; **`next_city_id`** increments; initial **`owned_tiles`** are **center-first** plus passable neighbors on the map not already owned (see `game/domain/actions/found_city.gd`). **`progress_state`** is unchanged; **no** production / food / science tick.

**`set_city_production` (Slice C3):** matches **[ACTIONS.md](ACTIONS.md)** — action **`schema_version` must be `2`**; **`project_id`** is **`"produce_unit:warrior"`**, **`"produce_unit:settler"`**, or **`"none"`** to clear. Non-**`none`** **`project_id`** values require **`progress_state`** unlock (**`city_project`** / **`project_id`**) like Godot **`GameState.try_apply`**. **`apply`** writes **`current_project`** with **`progress: 0`** and **`cost`** from **`CityProjectDefinitions`**; **no** production, food, science, or delivery **on that action** (**Slice C6** runs those ticks on **`end_turn`** only).

### Snapshot schema v1 (historical)

Early Cloud 0.1 prototypes used **`schema_version`: `1`** with only **`turn_state`** and a stub **`ruleset`**:

```json
{
  "match_id": "...",
  "schema_version": 1,
  "revision": 0,
  "ruleset": {
    "id": "stub_v0",
    "content_hash": "stub",
    "schema_version": 0
  },
  "turn_state": {
    "players": [0, 1],
    "current_index": 0,
    "turn_number": 1
  }
}
```

## Submit action (`end_turn`, `move_unit`, `found_city`, `set_city_production`)

Use the same **`actor_id`** field as Godot actions (not `actor_player_id`).

**`schema_version` per action:** **`1`** for **`end_turn`**, **`move_unit`**, and **`found_city`**; **`2`** for **`set_city_production`** (see [ACTIONS.md](ACTIONS.md)).

For **`found_city`**, the wire field is **`position`**: **`[q, r]`** (not `at`). Optional client-only names are **not** read by the server; **`city_name`** is **`Capital`** for a player’s first city, then **`Settlement 2`**, …, matching Godot **`FoundCity.default_city_name_for_owner`**.

### `end_turn`

Snapshots remain **`schema_version`: `2`**; request shape unchanged. **`end_turn`** triggers **Slice C6** side effects (see snapshot section above).

```json
{
  "schema_version": 1,
  "action_type": "end_turn",
  "actor_id": 0
}
```

### `move_unit`

Matches [ACTIONS.md](ACTIONS.md) **MoveUnit** dictionary: **`from`** / **`to`** are **`[q, r]`** and must match the unit’s current tile and a legal adjacent destination.

```json
{
  "schema_version": 1,
  "action_type": "move_unit",
  "actor_id": 0,
  "unit_id": 1,
  "from": [0, 0],
  "to": [1, 0]
}
```

### `found_city`

Same shape as [ACTIONS.md](ACTIONS.md) / **`FoundCity.make`**: **`position`** only (no **`name`** / **`at`** in the authoritative schema).

```json
{
  "schema_version": 1,
  "action_type": "found_city",
  "actor_id": 0,
  "unit_id": 1,
  "position": [0, 0]
}
```

### `set_city_production`

**`schema_version` `2`** only.

```json
{
  "schema_version": 2,
  "action_type": "set_city_production",
  "actor_id": 0,
  "city_id": 1,
  "project_id": "produce_unit:warrior"
}
```

**Accepted:**

```json
{
  "accepted": true,
  "reason": "",
  "index": 0,
  "revision": 1,
  "snapshot": { "...": "..." },
  "state_hash": "..."
}
```

**Rejected** (HTTP **200**; **`index`** is **`-1`**; **no** snapshot or event updates):

- Common / routing: **`not_current_player`**, **`unknown_action_type`**, **`malformed_action`**, **`unsupported_schema_version`**.
- **`move_unit`**: **`unknown_unit`**, **`unit_not_owned_by_player`**, **`from_does_not_match_unit_position`**, **`movement_exhausted`**, **`destination_not_on_map`**, **`destination_not_adjacent`**, **`destination_not_passable`**, **`destination_occupied`**.
- **`found_city`**: **`unknown_unit`**, **`unit_not_owned_by_player`** (Godot: **`actor_not_owner`**), **`unit_cannot_found_city`** (Godot: **`unit_type_cannot_found`**), **`unit_not_at_position`**, **`tile_not_on_map`**, **`tile_is_water`**, **`tile_already_has_city`**, **`tile_already_owned`**.
- **`set_city_production`**: **`unknown_city`**, **`city_not_owned_by_player`** (Godot: **`actor_not_owner`**), **`unknown_city_project`** (Godot: **`unsupported_project_id`**), **`city_project_not_unlocked`** (Godot **`GameState`**: **`project_not_unlocked`**), **`project_already_set`**.

**`end_turn`** structural rejections remain **`malformed_action`** / **`unsupported_schema_version`** / **`unknown_action_type`** as implemented in `server/app/domain/actions/end_turn.py`.

## Event log (JSONL line shape)

Append one JSON object per **accepted player action** and per **engine-generated `end_turn` follow-up** (`production_progress`, `food_growth_progress`, `city_grew`, `science_no_target`, `science_progress`, `science_completed`, `unit_produced`) to `events.jsonl`.

Example — **`food_growth_progress`** (engine):

```json
{
  "index": 1,
  "revision": 2,
  "schema_version": 1,
  "action_type": "food_growth_progress",
  "actor_id": 0,
  "city_id": 1,
  "food_stored_before": 0,
  "food_stored_after": 1,
  "population_before": 1,
  "population_after": 1,
  "total_food": 3,
  "consumption": 2,
  "surplus": 1,
  "growth_threshold": 15,
  "source": "engine",
  "result": "accepted",
  "accepted_at": "2026-05-16T19:00:03Z"
}
```

Example — **`city_grew`** (engine):

```json
{
  "index": 2,
  "revision": 2,
  "schema_version": 1,
  "action_type": "city_grew",
  "actor_id": 0,
  "city_id": 1,
  "population_before": 1,
  "population_after": 2,
  "food_stored_after": 0,
  "source": "engine",
  "result": "accepted",
  "accepted_at": "2026-05-16T19:00:04Z"
}
```

Example — **`science_no_target`** (engine; no eligible science left for auto-routing):

```json
{
  "index": 1,
  "revision": 2,
  "schema_version": 1,
  "action_type": "science_no_target",
  "actor_id": 0,
  "source": "engine",
  "result": "accepted",
  "accepted_at": "2026-05-16T19:00:04Z"
}
```

Example — **`science_progress`** (engine):

```json
{
  "index": 2,
  "revision": 2,
  "schema_version": 1,
  "action_type": "science_progress",
  "actor_id": 0,
  "progress_id": "controlled_fire",
  "delta": 1,
  "total": 3,
  "cost": 6,
  "source": "engine",
  "result": "accepted",
  "accepted_at": "2026-05-16T19:00:04Z"
}
```

Example — **`science_completed`** (engine):

```json
{
  "index": 3,
  "revision": 2,
  "schema_version": 1,
  "action_type": "science_completed",
  "actor_id": 0,
  "progress_id": "controlled_fire",
  "unlocked_targets": [
    { "target_type": "building", "target_id": "hearth" }
  ],
  "total": 6,
  "cost": 6,
  "source": "engine",
  "result": "accepted",
  "accepted_at": "2026-05-16T19:00:04Z"
}
```

Example — **`production_progress`** (engine, **`schema_version` `1`**; optional **`project_id`** when present on the city project):

```json
{
  "index": 0,
  "revision": 2,
  "schema_version": 1,
  "action_type": "production_progress",
  "actor_id": 0,
  "city_id": 1,
  "project_type": "produce_unit",
  "project_id": "produce_unit:warrior",
  "progress_before": 0,
  "progress_after": 2,
  "cost": 2,
  "source": "engine",
  "result": "accepted",
  "accepted_at": "2026-05-16T19:00:05Z"
}
```

Example — **`unit_produced`** (engine; Cloud adds **`project_id`** and **`unit_type_id`** for wire clarity; **`position`** is the city center / spawn hex `[q, r]`):

```json
{
  "index": 2,
  "revision": 3,
  "schema_version": 1,
  "action_type": "unit_produced",
  "actor_id": 0,
  "city_id": 1,
  "unit_id": 4,
  "unit_type_id": "warrior",
  "position": [0, 0],
  "project_type": "produce_unit",
  "project_id": "produce_unit:warrior",
  "source": "engine",
  "result": "accepted",
  "accepted_at": "2026-05-16T19:00:10Z"
}
```

Example — **`end_turn`**:

```json
{
  "index": 1,
  "revision": 2,
  "schema_version": 1,
  "action_type": "end_turn",
  "actor_id": 0,
  "turn_number_before": 1,
  "next_player_id": 1,
  "result": "accepted",
  "accepted_at": "2026-05-16T19:00:00Z"
}
```

Example — **`move_unit`**:

```json
{
  "index": 1,
  "revision": 2,
  "schema_version": 1,
  "action_type": "move_unit",
  "actor_id": 0,
  "unit_id": 1,
  "from": [0, 0],
  "to": [1, 0],
  "remaining_movement": 1,
  "result": "accepted",
  "accepted_at": "2026-05-16T19:00:15Z"
}
```

Example — **`found_city`**:

```json
{
  "index": 2,
  "revision": 3,
  "schema_version": 1,
  "action_type": "found_city",
  "actor_id": 0,
  "unit_id": 1,
  "city_id": 1,
  "city_name": "Capital",
  "at": [0, 0],
  "settler_consumed": true,
  "result": "accepted",
  "accepted_at": "2026-05-16T19:00:30Z"
}
```

Example — **`set_city_production`**:

```json
{
  "index": 3,
  "revision": 4,
  "schema_version": 2,
  "action_type": "set_city_production",
  "actor_id": 0,
  "city_id": 1,
  "project_id": "produce_unit:warrior",
  "project_progress": 0,
  "result": "accepted",
  "accepted_at": "2026-05-16T19:00:45Z"
}
```

`accepted_at` is UTC ISO-8601 with `Z`.

## Persistence layout

Under `server/data/matches/<match_id>/` (or `EMPIRE_SERVER_DATA_DIR/matches/...`):

- `snapshot.json` — latest snapshot (overwritten each accept).
- `events.jsonl` — append-only accepted events.

## Out of scope (not yet on server)

Auth, lobby, WebSockets, Godot client harness, **`attack_unit`**, **`ScienceTick.add_observation_bonus_if_eligible`** (lightning tree / move_unit log coupling), combat, deployment, database.

**Note:** The **Authority pivot** adds capabilities to **`server/`** slice by slice; the **`/v1`** endpoint family and **`try_apply`-mirroring rejection behavior** stay stable as actions are added.
