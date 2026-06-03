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

### Cloud front door / lobby UI (Slice C14c)

- **Launch:** `run/main_scene` is **`res://cloud/cloud_front_door.tscn`** — choose **Local Hotseat**, **Create Cloud Match**, refresh **Cloud Matches** (staging list), or **Resume** a saved entry for the current server URL.
- **Join:** select **Join {match_id} as Player N** to **`POST .../claim`**; credential saved; gameplay loads **`main.tscn`** with that seat token.
- **Create:** host token saved to **`user://cloud_matches.json`**; same create-then-play flow as before (no **`/start`** until C14d).
- **Resume:** uses C14a store; reconnect via **`GET /v1/matches/{id}`**.
- **Dev skip:** **`EOM_CLOUD_CLIENT=1`** still jumps straight to **`main.tscn`** with env-based cloud boot (headless tests unchanged).
- **Lobby list** never displays tokens; only claim/create responses store tokens locally.

### Cloud staging authority & async lifecycle (Slice C14d-0 — decision checkpoint, docs-only)

**Status:** decision-only. **No** runtime code, schema, or endpoint exists for this yet; it locks the intended model **before** the C14d staging/ready/auto-start implementation slices. Cloud alpha is **async-first and loosely coupled**: players do **not** need to be online at the same time, staging state lives on the **server**, and local clients hold **credentials only**.

**1. Host-token vs seat-token (two distinct credentials).**
- **Host-token (`ht_…`)** = match **owner/admin** credential, **not** the normal gameplay identity. It may authorize: rename match, manage staging/settings, delete/abandon match, and future admin/debug actions. **Host-as-all-players** stays **only** as an explicit **dev/debug** convenience (where documented), never as normal player UX.
- **Seat-token (`st_…`)** = **gameplay identity** for **exactly one** seat / `actor_id`. It authorizes: claiming/owning that slot, choosing faction/civ for that slot, setting ready/unready for that slot, and gameplay actions for that `actor_id` once the match is **ongoing**.
- Normal UI must **not** treat the host-token as “play all players.”

**2. Async staging flow (server-persistent).**
1. Host creates a match → stored server-side with **`status=staging`**.
2. Host lands in a **staging area**, **not** directly in gameplay.
3. Host may claim **one** seat and choose faction/civ.
4. Host may close the client; the match **remains in staging** on the server.
5. Another player later opens the cloud lobby, sees the staging match, claims an **open** seat, chooses faction/civ, and readies up.
6. Players are **never required to be co-present**.

**3. Readiness & auto-start (no manual host-start in normal UX).**
- There is **no** “host starts match” button in normal UX.
- Each player: **claims a seat → chooses an available faction/civ → presses Ready**.
- When **all required seats** are **claimed + faction-selected + ready**, the **server** automatically transitions the match to **`ongoing`** and selects the first player. The host does **not** auto-start first.
- **Alpha shape:** exactly **2 seats**; initial factions/civs **Malmö** and **Västervik** (add **Paris** if easy, otherwise treat as near-future).

**4. Status model (prefer derived `ready_to_start`, not a separate `ready` status).**
- **`status=staging`** — players can claim slots, choose faction/civ, ready/unready; in the **final** lifecycle, gameplay actions are **not** accepted while staging.
- **`ready_to_start` (derived, while staging)** — true when all required seats are claimed, factions selected, and `ready=true`. This is a **computed condition**, not a stored status.
- **`status=ongoing`** — match started; seats/settings **locked**; gameplay actions enabled per turn/seat authorization.
- A separate **`status=ready`** is **not** introduced unless a strong repo reason emerges; auto-start moves **staging → ongoing** directly.

**5. First-player selection (server-chosen, deterministic).**
- The **server** chooses the first player at **staging → ongoing**.
- First player is **not** implicitly the host.
- Use **deterministic pseudo-random** selection seeded by match identity so it is random-feeling but reproducible, e.g. principle:
  `first_player_index = deterministic_hash(match_seed_or_match_id + "first_player") % player_count`.
- The **client must not** choose the first player.

**6. Ongoing async UX (manual refresh, no realtime required).**
- Opening an **ongoing** match:
  - **Your turn** → gameplay with actions enabled.
  - **Another player’s turn** → read-only/waiting view of the map/state, e.g. “Malmö’s turn”, “You are playing as Västervik”, “Waiting for Malmö to play”, with **Refresh** / **Back** controls.
- **No** realtime/polling in the first version; **manual Refresh** is acceptable.

**7. Delete/abandon (host-token, future).**
- Host-token should later authorize **delete/abandon match** (remove or mark deleted/abandoned; clean up broken/unwanted matches).
- **Early finish/concede** is a **separate future** gameplay/lifecycle feature, **not** part of initial staging.

**Out of scope for C14d-0 (decision-only):** any server endpoint/schema, Godot UI, faction-selection model details, accounts/private matches/invite codes, polling/realtime, AI, and the actual auto-start/lock enforcement (those are later C14d implementation slices).

### Staging seat config — faction & ready (Slice C14d-1 — server-only)

- **`meta.json` v2 (additive):** per-seat **`faction_id`** (default **`null`**), **`ready`** (default **`false`**), optional **`claimed_at`** / **`ready_at`**; match-level **`match_seed`** at create (for future deterministic first-player in C14d-2). Faction registry (lobby metadata only — **no** gameplay effects): **`malmo`** → Malmö, **`vastervik`** → Västervik, **`paris`** → Paris.
- **Lobby summaries** (`GET /v1/matches` and faction/ready POST responses): **`available_factions`**, per-seat **`faction_id`** / **`ready`**, derived **`ready_to_start`** (true while **`status=staging`** when every seat is claimed, has a faction, and **`ready=true`**). Still **no** tokens in summaries.
- **`POST /v1/matches/{id}/seats/{actor_id}/faction`** — body **`{"faction_id":"malmo"}`**; **`POST …/ready`** — body **`{"ready":true}`** or **`false`**. Both require **`X-Empire-Seat-Token`** for **that** seat (**seat token only** — host token → **`invalid_seat_token`**). Return updated token-free lobby summary for that match.
- **Rejects:** **`faction_unknown`**, **`faction_taken`**, **`seat_not_claimed`**, **`faction_required`** (ready without faction), **`match_not_in_staging`**, **`missing_seat_token`** / **`invalid_seat_token`** / **`seat_not_allowed`** (wrong seat token for path `actor_id`).
- **Not in C14d-1:** auto-start, **`status=ongoing`** transition, first-player selection, staging action lock, Godot UI, Docker/Caddy changes.

### Staging lifecycle — auto-start & action gate (Slice C14d-2 — server-only)

- **Auto-start:** When the last required seat sets **`ready=true`** and **`ready_to_start`** would be true, the server transitions **`staging` → `ongoing`** in the same **`POST …/ready`** (no manual host-start, no **`POST /start`**). Sets **`started_at`**, **`first_player_id`**, updates snapshot **`turn_state.current_index`** (revision unchanged). Idempotent if already ongoing.
- **First player:** Deterministic server choice: `first_index = int(sha256((match_seed or match_id) + ":first_player"), 16) % len(players)`; **`first_player_id = players[first_index]`**. Not implicitly the host.
- **`POST …/ready` response:** Token-free lobby summary; when started includes **`status: ongoing`**, **`first_player_id`**, **`ready_to_start: false`**.
- **Action gate:** **`POST /actions`** on v2 **staging** → **`accepted: false`**, **`reason: match_not_ongoing`** (after seat-token gate). **Legacy** (no **`meta.json`**) and **meta v1** remain permissive. Ongoing matches use existing turn/token validation.
- **Event log:** Optional **`match_started`** row in **`events.jsonl`** (`action_type`, **`first_player_id`**, **`started_at`**).
- **Not in C14d-2:** Godot staging UI (C14d-3), gameplay/faction effects, Docker/Caddy, accounts/realtime/delete-abandon.

### Server display names (Slice C14b.1 / C14c.2)

- **`meta.json` v2** includes **`display_name`** (public lobby title). **`POST /v1/matches`** accepts optional **`display_name`**; if missing/empty the server sets **`Match {short_match_id}`** (not client-local **Match N** numbering).
- **`GET /v1/matches`** summaries include **`display_name`**; still token-free.
- **`PATCH /v1/matches/{id}/display-name`** with body **`{"display_name": "…"}`** — requires **`X-Empire-Seat-Token`**; **host token only** in alpha (**`not_host`** / **`invalid_seat_token`** / **`missing_seat_token`** otherwise). Empty/whitespace name becomes the server default. Updates **`meta.json` only** (not snapshot/events/state_hash).
- **Godot front door (C14c server-scoped lobby):** active **`server_url`** (env **`EOM_CLOUD_BASE_URL`** or default) scopes the whole lobby. **`user://cloud_matches.json`** is a keyring only (**`server_url` + `match_id` → seat token**). **Your matches on this server** = **`GET /v1/matches`** filtered to rows whose **`match_id`** has a local credential for that same normalized **`server_url`**; match metadata (**`display_name`**, status, seats, revision) comes from the server; tokens stay local. **Open staging matches** = joinable staging seats from the same server response, excluding matches already in the resume list. If the server is unreachable, show a load error and no playable resume rows (credentials are kept). **Create** / **Rename** / **Claim** behavior unchanged; local **`label`** is cache only.
- **Out of scope:** private/invite-specific titles, accounts, **`display_name` on GET match snapshot** (unchanged).

### Saved match labels (Slice C14c.1, superseded for display by C14c.2)

- Local **`label`** in **`user://cloud_matches.json`** remains a cache; UI prefers server **`display_name`** when known.

### Lobby discovery and seat claim (Slice C14b)

- **Server-only:** new matches write **`meta.json` schema_version 2** with **`status: "staging"`**, **`created_at`**, **`scenario_id`**, and per-seat **`claimed: false`** (tokens remain in meta only).
- **`GET /v1/matches`:** token-free lobby summaries (`match_id`, `status`, `scenario_id`, `created_at`, `player_count`, `seats[{actor_id, claimed, faction_id, ready}]`, `open_seat_count`, `available_factions`, `ready_to_start`, `revision`, `turn_number`). Optional **`?status=staging`**. Matches without **`meta.json`** (C12 legacy) are omitted. C13 **`meta` v1** appears as **`ongoing`** with all seats **`claimed: true`** in summaries; excluded from staging filter.
- **`POST /v1/matches/{id}/seats/{actor_id}/claim`:** marks seat claimed, returns **`seat_token`** and **`display_name`**. Rejects: **`match_not_found`** (404), **`seat_not_found`** (404), **`match_not_in_staging`** (409), **`seat_already_claimed`** (409).
- **Alpha:** staging matches are public to anyone who can reach the server; no invite codes or accounts.
- **C14d-2+:** **`POST /actions`** rejects v2 **staging** matches (**`match_not_ongoing`**). **Not in C14b/C14d-1:** auto-start, first-player selection (C14d-2). No **`POST /start`** in normal UX.
- **Tokens never in:** list summaries, **`GET /v1/matches/{id}`** snapshot body, **`events.jsonl`**, or **`state_hash`**.

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
