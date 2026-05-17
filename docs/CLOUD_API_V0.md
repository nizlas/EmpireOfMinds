# Empire of Minds — Cloud API v0 (Cloud 0.1)

HTTP contract for the **local authority** prototype under `server/`. This is a **wire + persistence** slice, not a steering or gameplay-spec document.

**Authority pivot:** Python/FastAPI under `server/` is the **canonical gameplay authority target**; this document’s **`/v1`** match + snapshot + revision + `state_hash` + events shape is the **spine** that will gain **additional `action_type` values** and **richer snapshots** as slices **B–D** land—without changing rejection/HTTP semantics. **Full charter:** [AUTHORITY_PIVOT.md](AUTHORITY_PIVOT.md).

**Direction:** [CLOUD_PLAY_DIRECTION.md](CLOUD_PLAY_DIRECTION.md). **Strategy / BYOS:** [CLOUD_PLAY.md](CLOUD_PLAY.md).

## Principles

- Clients submit **actions** mirroring [ACTIONS.md](ACTIONS.md) / `GameState.try_apply` shape. **Shipped Cloud 0.1** accepts **`end_turn` only**; additional player actions arrive with the pivot slices (see **Out of scope** / [AUTHORITY_PIVOT.md](AUTHORITY_PIVOT.md)).
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

**Slice B `end_turn` semantics (unchanged from Cloud 0.1):** an accepted **`end_turn`** only advances **`turn_state`** and **`revision`**. It does **not** refresh movement, run **`ProductionTick`**, **`FoodGrowthTick`**, **`ScienceTick`**, mutate **`progress_state`**, or change **`scenario`** — those come in later pivot slices.

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

## Submit action (v0: `end_turn` only)

**Body:**

```json
{
  "schema_version": 1,
  "action_type": "end_turn",
  "actor_id": 0
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

**Rejected** (HTTP **200**):

```json
{
  "accepted": false,
  "reason": "not_current_player | unknown_action_type | malformed_action | unsupported_schema_version",
  "index": -1
}
```

Validation order matches `GameState.try_apply`: `action_type` / `actor_id` gate, **then** `EndTurn`-style structural checks (see `server/app/domain/actions/end_turn.py`).

## Event log (JSONL line shape)

Append one JSON object per accepted action to `events.jsonl`:

```json
{
  "index": 0,
  "revision": 1,
  "schema_version": 1,
  "action_type": "end_turn",
  "actor_id": 0,
  "turn_number_before": 1,
  "next_player_id": 1,
  "result": "accepted",
  "accepted_at": "2026-05-16T19:00:00Z"
}
```

`accepted_at` is UTC ISO-8601 with `Z`.

## Persistence layout

Under `server/data/matches/<match_id>/` (or `EMPIRE_SERVER_DATA_DIR/matches/...`):

- `snapshot.json` — latest snapshot (overwritten each accept).
- `events.jsonl` — append-only accepted events.

## Out of scope (v0 wire as originally shipped)

Auth, lobby, WebSockets, Godot client harness, **`move_unit`**, combat, deployment, database.

**Note:** The **Authority pivot** explicitly adds these to **`server/`** in later slices; when a capability is implemented server-side, update this document’s examples and tables for that **schema version**—the **`/v1`** endpoint family and **`try_apply`-mirroring rejection behavior** stay stable.
