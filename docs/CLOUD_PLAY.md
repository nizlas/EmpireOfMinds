# Empire of Minds — Cloud Play Strategy

**Long-term direction (authority model, async/live-feel, action vocabulary, roadmap labels, AI parity):** [CLOUD_PLAY_DIRECTION.md](CLOUD_PLAY_DIRECTION.md). This page stays focused on **product/strategy** (modes, BYOS); the direction doc is the **canonical architecture checkpoint** for cloud/multiplayer/AI without implementation detail.

**Authority pivot:** The project is **migrating** canonical gameplay authority to **Python/FastAPI** under `server/` while preserving a **legacy** Godot-domain path until cutover is proven. **Slices, rollback, and “local = localhost authority”** are defined in [AUTHORITY_PIVOT.md](AUTHORITY_PIVOT.md). Local hotseat and future cloud play share the **same** server rules; they differ only by **base URL / transport**.

## Vision

Empire of Minds should support asynchronous play-by-cloud.

Players should be able to participate in a long-running turn-based game without being online at the same time.

## Initial Cloud Principle

Do not start by hosting all player games officially.

The project should support Bring Your Own Server / Private Cloud first.

## Supported Modes Over Time

### Local / Hotseat

Single machine. Useful for Phase 1 and early testing.

### Current state as of Phase 5.2.0

The **shipping playable embryo** today is a **local hotseat prototype**: **one** client process, **no** network multiplayer, **no** lobby, **no** accounts, and **no** **remote-seat** concept in code. **All** gameplay changes still go through **`GameState.try_apply`** with the usual **`actor_id == current_player_id()`** gate **until** the **Authority pivot** cutover ([AUTHORITY_PIVOT.md](AUTHORITY_PIVOT.md)); after cutover, the same actions go through **`POST /v1/matches/.../actions`** on the **localhost** or **remote** authority. **Slice C8 (opt-in)** adds a **Godot cloud-client prototype**: **`Main.use_cloud_server`** or **`EOM_CLOUD_CLIENT=1`** boots **`POST /v1/matches`**, **`GET .../legal-actions`**, and **`POST .../actions`** for **`end_turn` / `move_unit` / `found_city` / `set_city_production`**, then replaces presentation from the **response snapshot** — **no** auth, **no** websocket/SSE, **no** AI driving server turns. **Slice C9** adds **reconnect** via **`EOM_CLOUD_MATCH_ID`** / **`cloud_match_id`** and **`GET /v1/matches/{id}`**. **Slice C10** adds server-authoritative **`attack_unit`** (Local Combat 0.1 parity): cloud client posts **`attacker_id` / `defender_id`** only, highlights adjacent enemy warriors from **`GET .../legal-actions`**, and applies the returned snapshot — **no** clash animation (C11), **no** city/ranged combat, **no** event replay or polling. When create succeeds, the console logs the **`match_id`** with a reconnect hint. By default, **`Main.cloud_base_url`** is **`http://127.0.0.1:8000`** (not **`http://localhost:8000`**) so Windows Godot builds are less likely to stall on IPv6 **`::1`** before falling back to IPv4; **`EOM_CLOUD_BASE_URL`** and the inspector export still override. Until the first snapshot is applied, the client shows a **loading overlay** and **does not** treat local prototype state as playable; **`create-match`** or **reconnect GET** failure surfaces an **error** instead of silently reverting to hotseat. Default editor play remains **local try_apply**. A **FastAPI** authority prototype (`server/`, [CLOUD_API_V0.md](CLOUD_API_V0.md)) exists today with a **minimal** snapshot (`end_turn` only in the shipped v0 wire); it will grow to hold the full loop. UI copy such as **“Waiting for remote Player N”** belongs to a **future** slice, **not** to the current **local hotseat prototype** (the HUD uses **`Player N's turn`** instead).

### Reconnect to an existing match (Slice C9)

1. Start the server (see [VALIDATION_CHECKLIST.md](VALIDATION_CHECKLIST.md) Slice C8).
2. Enable cloud (**`EOM_CLOUD_CLIENT=1`** or **`Main.use_cloud_server`**).
3. **Create path (default):** leave **`cloud_match_id`** empty and **`EOM_CLOUD_MATCH_ID`** unset → **`POST /v1/matches`** runs once. Copy the logged **`match_id`** from the Godot console (`Slice C9 cloud: created match_id=…`).
4. **Reconnect path:** set **`EOM_CLOUD_MATCH_ID=<match_id>`** (or **`Main.cloud_match_id`** in the inspector) and relaunch → **`GET /v1/matches/{id}`** loads the saved snapshot; **no** new match is created.
5. **Failure:** bad or missing match id → full-screen **error overlay**; client does **not** fall back to local hotseat.
6. After reconnect, **`GET .../legal-actions`**, **`POST .../actions`**, and turn-banner gating behave the same as after create.

**Out of scope for C9:** event replay, polling, websocket/SSE, state-hash/desync recovery beyond the GET snapshot, new server endpoints.

### Server-authoritative combat (Slice C10)

1. Same cloud bootstrap as C8/C9.
2. Select a **Warrior** with movement → **`GET .../legal-actions?selected_unit_id=...`** includes **`attack_unit`** rows for adjacent enemy **Warriors**.
3. Click highlighted enemy hex → client posts **`attack_unit`**; server resolves combat; snapshot shows updated HP / removed units.
4. Reconnect preserves post-combat state (C9 + C10).
5. Local hotseat (cloud off) still uses **`GameState.try_apply`** and existing combat UX.

**Out of scope for C10:** clash animation (landed in **C11**), AI combat, city/ranged combat, event replay, polling, schema v3, endpoints beyond **`/actions`** and **`/legal-actions`**.

### Cloud combat presentation (Slice C11)

1. Same cloud bootstrap as C8/C9/C10.
2. Accepted **`attack_unit`** POST response includes additive **`event`** (same row as **`GET .../events`**).
3. Godot fires **`CombatClashBurstView`** at **`event.attacker_position`** / **`defender_position`** **before** applying the authoritative snapshot (~0.6s); map input blocked via **`cloud_session_blocks_map_input()`** during the burst.
4. If **`event`** is missing or invalid, snapshot applies immediately (no animation).
5. Other accepted actions (**`move_unit`**, etc.) still apply snapshot immediately; only cloud **`attack_unit`** uses the animation path.
6. **No** client-side damage math, death fade, sound, or replay-after-reconnect. Local hotseat unchanged.

**Out of scope for C11:** damage popups, sprite hit flash, death fade, sound, event polling, combat replay on reconnect.

### Local cloud credentials (Slice C14a)

- **Client-only:** match credentials are persisted in **`user://cloud_matches.json`** (plaintext JSON for alpha; not encrypted).
- **Fields:** `server_url`, `match_id`, `actor_id`, `seat_token`, `is_host`, `last_seen_revision`, `last_seen_status` ( **`unknown`** until server exposes staging/ongoing in C14b), optional `label`, `updated_at`.
- **After create:** host token and `match_id` are saved automatically; reconnect no longer requires **`EOM_CLOUD_SEAT_TOKEN`** when **`EOM_CLOUD_MATCH_ID`** is set.
- **Resolution (conservative):** env/inspector **`EOM_CLOUD_SEAT_TOKEN`** wins; else if **`EOM_CLOUD_MATCH_ID`** / **`cloud_match_id`** is set but token is empty, load token from the store for that **`server_url` + `match_id`**; else create-new-match when match id is empty. **No** auto-resume of “latest” saved match without an explicit match id (lobby UI in C14c).
- **Dev overrides unchanged:** **`EOM_CLOUD_CLIENT`**, **`EOM_CLOUD_BASE_URL`**, **`EOM_CLOUD_MATCH_ID`**, **`EOM_CLOUD_SEAT_TOKEN`**, **`EOM_CLOUD_DEBUG`**.
- **Out of scope:** lobby/front-door UI, server list/claim/start, encryption/keychain.

### Seat tokens / host credential (Slice C13a)

- **Access model:** new matches get **`meta.json`** with per-seat **`st_…`** tokens and a **host **`ht_…`** token** (can act for any seat in that match; dev/single-client full-match flow).
- **`POST /v1/matches/{id}/actions`:** header **`X-Empire-Seat-Token`** required when **`meta.json`** exists; server checks token allows **`action.actor_id`**, then existing rules apply. Reject reasons: **`missing_seat_token`**, **`invalid_seat_token`**, **`seat_not_allowed`**.
- **`GET /v1/matches/{id}`** and **`GET .../legal-actions`:** unchanged in C13a (no token gate).
- **Create response** includes additive **`seats`** + **`host_token`** (not in GET snapshot).
- **Godot:** **`EOM_CLOUD_SEAT_TOKEN`** (or inspector **`cloud_seat_token`**); on create, client uses **`host_token`** if none set. Reconnect: set **`EOM_CLOUD_MATCH_ID`** + **`EOM_CLOUD_SEAT_TOKEN`**. Full tokens print only with **`EOM_CLOUD_DEBUG=1`**.
- **Legacy** matches without **`meta.json`:** permissive (no header required).
- **Out of scope:** accounts/login, Postgres, polling, legal-actions gating, invite UI/email.

### Remote alpha deploy foundation (Slice C12a)

- **Deploy-only:** repo-tracked Docker Compose + Caddy on Hetzner; **no** gameplay or authority semantics change.
- **Remote base URL:** `https://cloud.thewizardsapprentice.org` — set **`EOM_CLOUD_BASE_URL`** (or inspector **`Main.cloud_base_url`**) when testing against the alpha host.
- **Path:** Caddy terminates HTTPS on **80/443** and reverse-proxies to the FastAPI container on the internal Docker network (**port 8000 not published** on the host).
- **Persistence:** match snapshots/events use **`EMPIRE_SERVER_DATA_DIR`** on a named Docker volume (see [DEPLOY_HETZNER.md](DEPLOY_HETZNER.md)).
- **Local hotseat** and default **`http://127.0.0.1:8000`** cloud dev are unchanged when cloud mode is off or when pointing at localhost.

### Connect to Existing Server

Client connects to a backend URL.

### Private Cloud / Self-Hosted

User runs their own backend, likely via Docker Compose.

### Official Cloud

Optional future service if the project becomes commercial or widely used.

## Cloud Architecture Concept

```text
Godot Client
  -> HTTPS API
  -> Backend
  -> PostgreSQL
  -> Worker for AI turns / notifications
```

Alignment with [ARCHITECTURE_PRINCIPLES.md](ARCHITECTURE_PRINCIPLES.md): in cloud mode, the server owns canonical state; clients submit candidate actions; validation and application happen server-side. Phase 1 remains local-only; concrete backend work is deferred to the phase where it is in scope ([PHASE_PLAN.md](PHASE_PLAN.md)).

## RuleSet snapshot stability (Phase 5.0a)

**Concept-only** — no backend schema, protocol, storage format, or wire-format commitment in this subphase.

- **Saved games** and **async / cloud** sessions must **capture or reference** the **RuleSet** identity concepts **[CONTENT_MODEL.md](CONTENT_MODEL.md)**: **RuleSet id**, **content hash**, **`schema_version`**.
- Purpose: an **`ActionLog`** **replays** against the **same** **EffectiveRules**, not ad hoc definition code drift.
- **Server-authoritative** play replays the **validated RuleSet / EffectiveRules** for the session, not raw definition modules alone.
- **Seed** and **generator version** may help reproducibility for generative worlds, but **saved / replayed** games need a **stable content snapshot identity**.
