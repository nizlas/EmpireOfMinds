## 2026-06-03 — Slice **C14d-4f** — Cloud TurnStatusPanel suppression

- **Decision:** In cloud ongoing play, hide **`HudCanvas/TurnStatusPanel`** (lower-right “{Civ}'s turn” / “Turn N”). Keep **`PlayerContactStrip`** chips (current-player highlight) and C14d-4b small **“Other player’s turn”** waiting line. **`TurnStartBanner`** (C14d-4d local-seat gating) unchanged. Local hotseat still shows **TurnStatusPanel**.
- **Tests:** **`test_cloud_turn_panel_c14d4f.gd`** in Godot slice **`c14d`**.

## 2026-06-03 — Slice **C14d-4e** — Staging civilization terminology & display names

- **Decision:** Player-facing staging term is **civilization/civ** (Godot labels/messages). Internal API/schema unchanged: **`faction_id`**, **`available_factions`**, **`faction_taken`**, etc. Server staging registry **`display_name`** values align with **`docs/FACTION_IDENTITY.md`** debug profiles: **`malmo`** → **Malmöfubikkarna**, **`vastervik`** → **Västerviksjävlarna**, **`paris`** → **Pajasarna från Paris** (not the short city names). Godot uses server **`display_name`** in dropdown/read-only slots (no local fallback drift).
- **Tests:** server **`test_faction_display_names_c14d4e.py`**; Godot **`test_cloud_staging_civ_terminology_c14d4e.gd`** in slice **`c14d`**.
- **Not in C14d-4e:** gameplay rules, Docker/Caddy, lifecycle, broad **`faction_*` field renames**.

## 2026-06-03 — Slice **C14d-3** — Godot staging UI + dual-token credential store

- **Decision:** **Create Cloud Match** and **Join/Continue setup** route to **`cloud_staging.tscn`** (not **`main.tscn`**) until server **`status=ongoing`**. One credential store entry per **`(server_url, match_id)`** holds **`host_token`** (admin: rename) and **`seat_token`** (claim, faction, ready, gameplay) via **`merge_entry`** — claim must not overwrite host. Legacy rows with only **`seat_token`** field migrate **`ht_…` → host_token**, **`st_…` → seat_token**.
- **BootIntent:** **`MODE_CLOUD_STAGING`** with **`host_token`**, **`seat_token`**, **`actor_id`**, **`display_name`**; staging status text **"Entering staging…"** (not gameplay reconnect wording). **`set_cloud_reconnect`** unchanged for ongoing resume with **seat token only**.
- **Staging UI:** two seats, manual **Refresh**, claim / faction / ready via server C14d-1 endpoints; auto-transition to gameplay when summary **`status=ongoing`** and local **seat_token** exists; host-only ongoing shows **"Choose a player slot…"** (no host-as-all-players).
- **Front door:** saved button **Resume match** vs **Continue setup**; open list **Join {display_name}** (no match_id/tokens in UI).
- **Not in C14d-3:** waiting/read-only turn UX (C14d-4), polling, server/deploy changes.
- **Tests:** Godot slice **`c14d`** — **`test_cloud_staging_c14d.gd`** + credential/boot/lobby tests.

## 2026-06-03 — Slice **C14d-2** — Server lifecycle: auto-start, first player, action gate

- **Decision:** When all seats are claimed, have a valid faction, and **`ready=true`**, the final **`POST …/ready`** auto-starts the match: **`status=ongoing`**, **`started_at`**, **`first_player_id`**, snapshot **`turn_state.current_index`** updated (revision unchanged). First player: **`sha256((match_seed or match_id) + ":first_player")`** → index mod **`len(players)`**; not host/client-chosen. Append optional **`match_started`** event to **`events.jsonl`**.
- **Action gate:** **`POST /actions`** on meta v2 **`staging`** returns **`accepted=false`**, **`reason=match_not_ongoing`** (after credential gate). No meta / v1 meta → permissive (ongoing) as before.
- **Lobby summary:** ongoing rows may include **`first_player_id`**; **`ready_to_start`** is false when not staging.
- **Not in C14d-2:** manual **`/start`**, Godot UI, gameplay/faction effects, Docker/Caddy, accounts/realtime.
- **Tests:** **`test_auto_start.py`**, **`test_action_status_gate.py`**; **`create_staging_match`** vs **`create_seated_match(start_ongoing=True)`** in **`match_helpers`**.

## 2026-06-03 — Slice **C14d-1** — Server staging seat config (faction + ready)

- **Decision:** Extend **`meta.json` v2** (additive, not v3) with per-seat **`faction_id`** (default **`null`**), **`ready`** (default **`false`**), optional **`claimed_at`** / **`ready_at`** ISO timestamps, and match-level **`match_seed`** set at create. Staging faction registry (metadata only, no gameplay): **`malmo`** → Malmö, **`vastervik`** → Västervik, **`paris`** → Paris.
- **API:** **`POST /v1/matches/{id}/seats/{actor_id}/faction`** body **`{"faction_id":"…"}`** and **`POST …/ready`** body **`{"ready":true|false}`** — require **`X-Empire-Seat-Token`** for that seat only (**`seat_token_actor_id`**; host token **`invalid_seat_token`**). Both return token-free **`lobby_summary`** (same fields as **`GET /v1/matches`** row, including **`available_factions`**, per-seat **`faction_id`** / **`ready`**, derived **`ready_to_start`**). Rejects: **`faction_unknown`**, **`faction_taken`**, **`seat_not_claimed`**, **`faction_required`** (ready without faction), **`match_not_in_staging`**, **`missing_seat_token`** / **`invalid_seat_token`** / **`seat_not_allowed`**.
- **Explicitly not in C14d-1:** auto-start (**staging → ongoing**), first-player selection, action gating while staging, Godot/UI, gameplay/faction effects, Docker/Caddy/deploy.
- **Tests:** server slice **`c14d`** — **`test_faction_select.py`**, **`test_seat_ready.py`**, extended **`test_seats.py`** / **`test_lobby_list.py`**.

## 2026-06-03 — Slice **C14d-0** — Cloud staging authority decision checkpoint (docs-only)

- **Decision (no runtime code):** Lock the cloud-staging model before implementing C14d. Cloud alpha is **async-first / loosely coupled** — players need **not** be co-present; staging lives on the **server**; clients hold **credentials only**.
  - **Host-token (`ht_…`) = match owner/admin** (rename / manage staging+settings / delete-abandon / future admin-debug), **not** normal gameplay identity. Host-as-all-players is **dev/debug only**.
  - **Seat-token (`st_…`) = gameplay identity** for exactly one `actor_id` (claim slot, choose faction/civ, ready/unready, play that actor once ongoing).
  - **Async staging:** create → `status=staging` (server-persistent) → host lands in **staging area** (not gameplay) → host/other players claim a seat, choose faction/civ, ready up across separate sessions.
  - **Auto-start, no manual host-start:** when all required seats are **claimed + faction-selected + ready**, the **server** transitions **staging → ongoing** and picks the first player. **Alpha:** exactly **2 seats**; factions **Malmö** + **Västervik** (Paris if easy, else near-future).
  - **Status model:** prefer **`status=staging`** with a **derived `ready_to_start`** (all seats claimed + faction + ready) → auto-start sets **`status=ongoing`** (seats/settings locked). **No** separate `status=ready` unless a strong reason emerges.
  - **First player chosen by server**, deterministically (e.g. `deterministic_hash(match_seed_or_match_id + "first_player") % player_count`), **not** implicitly host, **never** client-chosen.
  - **Ongoing async UX:** read-only/waiting view on others’ turns (“Malmö’s turn” / “You are playing as Västervik” / “Waiting for Malmö”) with **manual Refresh** / **Back**; **no** realtime/polling required in v1.
  - **Delete/abandon** is a future **host-token** action; **early finish/concede** is a separate future lifecycle feature, not part of initial staging.
- **Out of scope:** server endpoints/schema, Godot UI, faction-selection details, accounts/private/invite, polling/realtime, AI, and the actual auto-start/lock enforcement (later C14d slices).
- **Docs:** [CLOUD_PLAY.md](CLOUD_PLAY.md), [CLOUD_PLAY_DIRECTION.md](CLOUD_PLAY_DIRECTION.md), [VALIDATION_CHECKLIST.md](VALIDATION_CHECKLIST.md), [TESTING.md](TESTING.md). **Docs-only:** no Godot/server/test/deploy/gameplay change.

## 2026-06-02 — Slice **C13a** — Player seats / invite tokens (cloud-alpha access)

- **Decision:** New matches write **`meta.json`** (beside **`snapshot.json`**) with per-seat tokens (**`st_`**) and optional **host token** (**`ht_`**, acts for all seats in that match — alpha/dev convenience, not accounts). **`POST /v1/matches/{id}/actions`** on seated matches requires header **`X-Empire-Seat-Token`**; server verifies **`action.actor_id`** is allowed by the token, then runs existing gameplay gates unchanged. **`GET /v1/matches/{id}`** and **`GET .../legal-actions`** stay ungated in C13a. Tokens are **not** in snapshot/events/**GET** response. Legacy matches without **`meta.json`** remain permissive. Godot: **`EOM_CLOUD_SEAT_TOKEN`** / **`Main.cloud_seat_token`**; create auto-uses **`host_token`** when unset; full tokens logged only when **`EOM_CLOUD_DEBUG=1`**.

## 2026-06-02 — Slice **C12b** — Cloud explored-map memory in snapshot v2

- **Decision:** Persist per-player **explored** tiles in authoritative snapshot **`visibility_state`** (`by_owner` + `explored` coord pairs). Server updates visibility on **`move_unit`**, **`found_city`**, and **`attack_unit`** (same radii/rules as Godot **`PlayerVisibilityState`**). Godot cloud adapter restores **`visibility_state`** from snapshot instead of re-seeding from current unit/city sight only. Legacy snapshots without the field seed on read (same as pre-fix reconnect). **Out of scope:** fog privacy, cross-player reveal, presentation-only caches, hotseat path changes.
- **Local hotseat:** unchanged — still client **`GameState.visibility_state`** via **`try_apply`**.

## 2026-06-02 — Slice **C12a** — Cloud Alpha deploy foundation (Hetzner + Docker + Caddy)

- **Decision:** Add repo-tracked **`server/Dockerfile`**, **`deploy/hetzner/docker-compose.yml`**, and **`deploy/hetzner/Caddyfile`** for **empire-cloud-01** (`62.238.44.6`). **Caddy** serves **only** **`cloud.thewizardsapprentice.org`** with automatic HTTPS; **FastAPI** stays on the internal Docker network (**`expose: 8000`**, no host **`ports`** for the API). Match persistence reuses existing **`EMPIRE_SERVER_DATA_DIR=/app/data`** (writes under **`/app/data/matches/`**) on named volume **`empire_match_store`** — **no** new env var and **no** server code change. **Out of scope:** Postgres, auth/seats/accounts, polling/realtime, AI/LLM, new endpoints, gameplay/schema changes, SiteGround SSL for the subdomain, CI/CD automation.
- **Local dev:** unchanged — **`uvicorn`** from **`server/`**; Godot default **`http://127.0.0.1:8000`** when cloud is off or unset.
- **Docs:** [DEPLOY_HETZNER.md](DEPLOY_HETZNER.md); updates to [CLOUD_PLAY.md](CLOUD_PLAY.md), [VALIDATION_CHECKLIST.md](VALIDATION_CHECKLIST.md).

## 2026-06-02 — Slice **C11** — cloud combat presentation v0 (additive **`event`** in action response)

- **Decision:** Accepted **`POST /v1/matches/{id}/actions`** responses include additive **`event`** (same object appended to **`events.jsonl`**). Godot cloud client uses **`event.attacker_position`** / **`defender_position`** to fire **`CombatClashBurstView`** before applying the authoritative snapshot; **`combat_animation_request_from_response`** never infers damage/outcome. Missing/invalid **`event`** → immediate snapshot apply. Only cloud **`attack_unit`** uses the animation path; other actions unchanged. **Out of scope:** damage popups, death fade, sound, polling, replay-on-reconnect, local hotseat changes.
- **Local hotseat:** unchanged — still **`GameState.try_apply`** + existing **`CombatClashBurstView`** in **`SelectionController`**.

## 2026-06-01 — Slice **C10** — server-authoritative **`attack_unit`** (Local Combat 0.1 cloud parity)

- **Decision:** **`POST /v1/matches/{id}/actions`** accepts **`attack_unit`** with **`attacker_id`** + **`defender_id`** only (no client-supplied **`from`**/**`to`**). Server **`combat_rules.py`** resolves damage/retaliation/death deterministically (Godot **`CombatRules`** parity); **`attack_unit.apply_with_result`** sets attacker **`remaining_movement = 0`**. **`GET .../legal-actions`** selection mode enumerates adjacent enemy **Warrior** attacks; Godot cloud client highlights defender hexes and posts normalized payloads. **Out of scope:** clash animation (C11), city/ranged combat, AI combat, event replay, polling, schema v3, new endpoints.
- **Local hotseat:** unchanged — still **`GameState.try_apply`** + existing combat presentation.

## 2026-05-17 — Authority Pivot — Python/FastAPI canonical gameplay authority

- **Decision:** Commit to **`server/`** (Python/FastAPI) as the **canonical** target for **rules, validation, state mutation, action log, snapshots, and `state_hash`**. Godot’s **`game/domain/`** + **`GameState.try_apply`** remain **legacy** until **cutover is proven**; **do not delete** legacy domain until post–playtest cleanup. **Local hotseat** will run against **localhost authority**; **cloud** uses the **same** authority codepaths with **different base URL/transport**. Unrelated feature work **pauses** until the **current playable loop** runs through the server path (see [AUTHORITY_PIVOT.md](AUTHORITY_PIVOT.md) slices **B–F**).
- **Constraints during pivot:** No new gameplay, no AI/LLM/realtime/auth/lobby/deployment in pivot slices; **no semantic change** when porting—[ACTIONS.md](ACTIONS.md) + existing tests are the contract; redesign only after parity.
- **Docs:** [AUTHORITY_PIVOT.md](AUTHORITY_PIVOT.md); updates to [ARCHITECTURE_PRINCIPLES.md](ARCHITECTURE_PRINCIPLES.md), [CURRENT_ARCHITECTURE.md](CURRENT_ARCHITECTURE.md), [CLOUD_PLAY.md](CLOUD_PLAY.md), [CLOUD_API_V0.md](CLOUD_API_V0.md). **Slice A:** documentation only—**no** Godot or server code behavior change.

## 2026-05-14 — Phase **5.1.16i** — **hex-traced** **Line2D** **loops** (**continuous** border)

- **Decision:** Replace **per-segment** **`draw_line`** + **vertex** **`draw_circle`** **join** **dots** with **one** **closed** **`Line2D`** per **perimeter** **component** (**outer** owner stroke + **inner** indigo stroke). **Half-edges** are listed from **axial** **topology**; **loops** are **walked** by **graph** **adjacency** on **`world_corner_key`** (**layout**-fixed keys — **not** **MapCamera**). **Projection** and **stroke** **width** use **`MapCamera`** only **after** **loop** **order** is known. **Inner** corners use **averaged** **edge** **inward** directions in **presentation** space (same **intent** as prior **inset**).
- **Rationale:** **Tangent** **extend** + **small** **disks** still **read** as **rivets**; **true** **stroke** **joints** need a **continuous** path. This **loop** **trace** is **not** **screen-space** **sorting** — it is **deterministic** **half-edge** **chaining** in **hex** **space**, then **project**.

## 2026-05-14 — Phase **5.1.16i** — **local** **vertex** **join** disks (**round** **patches**)

- **Status:** **Superseded** by **hex-traced** **`Line2D`** **loops** entry above — historical note only.

## 2026-05-14 — Phase **5.1.16i** — **corner** **closure** (**tangent** **overdraw** tune)

- **Decision:** Increase **deterministic** **segment** **extension** (separate **outer** / **inner** **fractions**, **inner** **floor** vs **`outer_w`**) so **flat** **`draw_line`** **caps** meet at **~120°** hex **joints** without **dots** or **loop** **assembly**. **Axial** **perimeter** **identity** unchanged.
- **Rationale:** Prior **0.20×** **stroke** **extend** left **visible** **wedges**; **fix** is **local** **draw** **overdraw** only.

## 2026-05-14 — Phase **5.1.16i** visual polish — **inward** indigo + **no** round joints (**stable** segments unchanged)

- **Decision:** Keep **axial-only** perimeter **segment** topology and **two** **`draw_line`** passes per edge. **Remove** default **`draw_circle`** **joint** dots. **Inner** **indigo** line is **offset inward** in **presentation** space: **`normalize(to_presentation(hex_center) − midpoint(outer_segment))`**, clamp-scaled from **`outer_w`**. **Slightly** **extend** both strokes along edge tangent to hide **micro-gaps** (acceptable **overlap**). **Round** **debug** caps remain **opt-in** (`debug_draw_territory_endpoint_caps` / **`EOM_DEBUG_CITY_TERRITORY_CAPS`**).
- **Rationale:** Caps read as **rivets**; centered inner stroke read as **double-track**. **Per-edge** inward from the **local** **owner** hex center stays **deterministic** and does not rebuild **presentation-space** **loops** (no **pan**/**zoom** **topology** **risk**).

## 2026-05-14 — Phase **5.1.16i** bugfix — **stable segment** territory border (**no** presentation-space loops)

- **Correction:** Removed **fragile** **loop** / **polyline** / **presentation-snap** assembly that caused **zoom**- and **pan**-dependent **diagonal spokes** and **triangulation-like** artifacts. **Topology** is derived **only** in **axial** space from **`tiles_owned_by_city`**; **`MapCamera`** affects **projected** endpoints and **thickness** only.
- **Replacement:** Perimeter = **only** **per-hex-edge** **`draw_line`** segments (**later:** **inward-offset** inner stroke + **tangent** **extend**; **no** default round caps — see **5.1.16i visual polish** entry). **No** interior fill; **no** cached segment arrays across draws.
- **Layering unchanged:** **`CityTerritoryView`** remains **`z_index` 0** immediately **after** **`MapView`**, **below** cities / units / **TerrainForegroundView** / yields / nameplates.

## 2026-05-14 — Phase **5.1.16i** follow-up — **continuous** territory border (**loop assembly** + **2×** stroke)

- **Status:** **Superseded** by the **2026-05-14 5.1.16i bugfix** entry above — loop assembly caused **map-camera**-dependent artifacts and was **removed**.

## 2026-05-14 — Phase **5.1.16i** polish — **CityTerritoryView** layering + **Civ**-style border (**no fill**)

- **Decision:** **`CityTerritoryView`** (**`z_index` 0**, sibling **after** **`MapView`**) draws **only** a **union** **perimeter** — **no** translucent **tile** **fill**. **Two** **strokes**: **thick** **outer** **owner** **accent** + **thinner** **inner** **indigo** line **inset** toward the **owned** **hex** **center**. **`TileYieldOverlayView`**, **`TerrainForegroundView`**, **markers**, **nameplates** stay **above** the border so territory does not **occlude** **trees** / **units** / **yields**.
- **Rationale:** Fill **dims** large **empires**; prior **`z_index` 1** placement **read** **floating** **over** **sprites**. **Map-surface** ordering matches **Civ**-style **read**.

## 2026-05-14 — Phase 5.1.16i follow-up — **CityTerritoryView** visible in editor play

- **Decision:** Treat **`tiles_owned_by_city`** rows with **duck-typed** **`q` / `r`** only — remove **`is HexCoord`** guards that skipped **all** tiles in some **editor** runs (nothing drawn). Slightly **stronger** default **outline** / **fill**; optional **`@export`** + **`EOM_DEBUG_*`** env **log** / **high-contrast** **smoke**; **`SelectionController._refresh_city_territory_view()`**; **`TileYieldOverlayView`** included in **`MAP_LAYER_ORIGIN`** loop.
- **Rationale:** Headless tests constructed **`HexCoord`** literals; **runtime** **`Scenario`** copies still expose **`q` / `r`** but failed **global class** **`is`** checks, producing an **empty** overlay.

## 2026-05-14 — Phase 5.1.16i — **Selected** city territory visualization (presentation)

- **Decision:** Add **`CityTerritoryView`** (**`Node2D`**, **`MapCamera`**-anchored) that draws **only** when **`SelectionState`** has a **city**: **outer perimeter** of **`Scenario.tiles_owned_by_city`**, **owner** accent from **`UnitNameplateView.owner_nameplate_accent_color`**, **faint** **fill** + **slightly stronger** **center** treatment; **sibling order** **above** **`LightningTreeView`**, **below** **`TileYieldOverlayView`** so **yield** icons stay readable; **nameplates** unchanged above. **No** all-cities mode, **no** domain / **`FoundCity`** / yield / production / science changes.
- **Update (2026-05-14 polish):** **No** **fill**; **`z_index` 0** **after** **`MapView`** (under cities / units / **TerrainForegroundView** / **LightningTreeView** / yields); **two-stroke** **Civ**-style **border** — see **DECISION_LOG** entry **“5.1.16i polish”**.
- **Rationale:** **5.1.16g** territory is otherwise invisible; **Civ VI**-style **inspiration** — **readable** border, **not** a **HUD**-fixed overlay.
- **Follow-up:** Optional debug **all** **cities**; **population** / **worked** tiles (**5.1.16h**) remain **separate**.

## 2026-05-13 — Phase 5.1.16g.2 — **Fixture polish** (forest fragmentation + grass speckle; same island silhouette)

- **Decision:** **`PROTOTYPE_WOODS_HEXES`** / **`HexMap._proto_paint_land_terrain()`** **only**: **re-list** prototype **woods** so **no** decoration component **exceeds ~9** connected **PLAINS** hexes, with **more** isolates / thin patches; add **small** extra **plains** and **grassland·hills** accents on former **flat-grass** stretches. **Landmass** keys (**g.1** + extension list + **full** water ring), **scenario** starts, **CityYields** / **production** / **science** / **territory** rules **unchanged**.
- **Rationale:** Visually the prior corrected map still read as **compact forest blobs** and **over-smooth** grass; this pass keeps structural tests but pushes **hand-authored** **variegation** without a **layout** **rebuild**.
- **Follow-up:** Unchanged — **5.1.16h** population / **procedural** maps **un-steered**.

## 2026-05-13 — Phase 5.1.16g.2 — **Corrected** curated island expansion (g.1+extensions; grass-forward; full sea ring)

- **Decision:** **`HexMap.make_prototype_play_map()`** was **re-implemented** after review: keep **5.1.16g.1** **disk + strait + NW bay** **lineage**, expand with an **explicit axial extension list** (NE **tongue** / E **ridge** / SE **shelf**), **soft** R=**6** core **with corner thinning** (avoid a bland **bigger disk**), **grass-default** terrain with **hand-placed** plains / hill **fragments** only (no half-map **plains·hills** sweep), **`_proto_add_full_water_ring`** so **all** **land** periphery touches **WATER** on the **finite** map (true **island** read), and **`PROTOTYPE_WOODS_HEXES`** re-tuned for **multi-cluster** **PLAINS** **woods** on **dry** land (including fixed **E/NE** **bridge** hexes so list coords are never halo-**WATER**). **`make_prototype_play_scenario()`** unchanged from prior **5.1.16g.2** attempt: **P0** **`(0,0)`** / **`(1,0)`**, **P1** **`(9,5)`**, **`lightning_tree_hex`** **`(3,0)`**; **`make_tiny_test_map()`** unchanged.
- **Rationale:** The first **5.1.16g.2** pass read as a **formula banana** with **plains·hills** **monotony** and **incomplete** **water** enclosure; this slice **restores** **curated** **subregions**, **mixed** **grassland**, and a **full** **coastal** shell while staying **deterministic** and **fixture-only**.
- **Follow-up:** **Fog-of-war**, **workers**, **procedural** maps — **unchanged** / **un-steered**.

## 2026-05-13 — Phase 5.1.16g.1 — Curated Ancient prototype map replaces formula play disk

- **Decision:** **`HexMap.make_prototype_play_map()`** is now a **fixed hand-authored** **island / micro-continent** (west **lake strait** keeping **`(-1,0)`** **WATER**, **NW bay** bite, **east peninsula**, **PLAINS/GRASSLAND** paints, **HILLS** bands, **water halo** to **axial distance 8**, **`PrototypeTerrainFeatures`** **woods** on **PLAINS** only). It **replaces** the prior **R=7** **169-cell** **sector disk** as the **playtest** fixture — **not** a general map generator; **`make_tiny_test_map()`** is **unchanged**. **`make_prototype_play_scenario()`** moves the **P1** **settler** to **`(-3,4)`** so **radius-1** **territory** does not start **blocking** sensible expansion from **`(0,0)`**.
- **Rationale:** Support a **small Ancient-era mini-game** layout (capital candidate, food / hill / coastal / frontier pockets, meaningful **yield overlay**) without touching **economy** rules or **terrain** scope.
- **Follow-up:** **Population / worked tiles** remain **5.1.16h**; optional future **map authoring** tools stay **out of scope** until steered.

## 2026-05-13 — Phase 5.1.16g — City territory foundation (`owned_tiles`)

- **Decision:** **`City.owned_tiles`** (**`Array[HexCoord]`**, **center first**) persists city territory. **`FoundCity`** claims **center** plus all **on-map** hexes at hex distance **1** (including **WATER**); ring tiles already owned by another city are **skipped**; founding on **any** tile in another city’s territory returns **`tile_already_owned`**. **`Scenario`** asserts each city **owns its center**, every owned tile **exists on the map**, and **no** tile is owned by two cities; adds **`tile_owner_city_id`**, **`city_owning_tile`**, **`tile_is_owned`**, **`tiles_owned_by_city`**. **`ProductionTick`**, **`ProductionDelivery`**, and **`SetCityProduction`** forward **`owned_tiles`** when rebuilding **`City`**. **`CityYields.city_total_yield`** is **unchanged** — it still sums **only** **city-center** + **buildings**; **`test_city_yields`** regression holds extra **owned** land tiles to prove ring yields are **not** included (**worked tiles** → **5.1.16h**).
- **Rationale:** Worked tiles must be chosen from **declared** city territory, not an implicit radius; coastal ownership can include water before fishing systems exist (**v0** water yields remain empty in **`CityYields.raw_terrain_yield`**).

## 2026-05-12 — Phase 5.1.16f — Map-anchored **TileYieldOverlayView** + **Yields** toggle

- **Decision:** **`TileYieldOverlayView`** (**`Node2D`**, **`z_index` 1**) draws prototype yield icons from **`CityYields`** only (**`city_total_yield`** on city hexes, **`raw_terrain_yield`** elsewhere); icon size scales with **`MapCamera.perspective_scale_at`**. **Default OFF**; **`HudCanvas`** **`Yields`** **`CheckButton`** and **`KEY_Y`** stay in sync via **`YieldOverlayToggle`** (keyboard updates **`CheckButton`** with **`set_pressed_no_signal`**). **No** HUD-fixed overlay; **no** domain / **ProductionTick** / **ScienceTick** changes; letter fallback when icon PNGs are missing.
- **Rationale:** Visually inspect **v0** yields on the map before population / worked tiles; complements **5.1.16e** panel summary.
- **Follow-up (same phase, presentation polish):** Enlarged overlay icons (**~2×** prior nominal size, named **`YIELD_ICON_*`** constants in **`tile_yield_overlay_view.gd`**; **`compute_icon_metrics`** only) — still **map-anchored**, no rule changes.
- **Follow-up (filtering):** **`TileYieldOverlayView`** aligns with marker rendering: **`TEXTURE_FILTER_LINEAR_WITH_MIPMAPS`** plus **`yield_icons`** **`.import`** **`mipmaps/generate=true`** (same as **`map_markers/`**) — fixes pixelated minification without per-frame outlines or shaders.

## 2026-05-12 — Phase 5.1.16e — **CityProductionPanel** **CityYields** visibility

- **Decision:** **`CityProductionPanel.compute_view_model`** adds **`yields`** / **`yields_line`** from **`CityYields.city_total_yield(scenario, city)`** (read-only); **`refresh()`** shows a single **Yields:** summary line. **No** terrain logic in the panel; **no** **`ProductionTick`** / **`ScienceTick`** from UI. Opponent city selection still shows yields for transparency.
- **Rationale:** **5.1.16c–d** economy affects play; players need an in-game read of **Food** / **Production** / **Science** / **Coin** before population / worked tiles.

## 2026-05-12 — Phase 5.1.16d — **ProductionTick** uses **`CityYields`** **production**

- **Decision:** **`ProductionTick.apply_for_player`** advances **`produce_unit`** **`progress`** by **`CityYields.city_total_yield(scenario, city)["production"]`** each eligible **end_turn** (no duplicated terrain tables in **`production_tick.gd`**). **`Palace`** contributes **science**/**coin** only — **not** **production**. If **production** ≤ **0**, the city is **not** ticked that turn. **`ProductionDelivery`** unchanged aside from consuming the new **progress** curve.
- **Rationale:** **Founding** location and **v0** **city-center** / **woods** rules affect **unit** **production** pacing, aligned with **`CityYields`** as single source of truth.

## 2026-05-12 — Phase 5.1.16c — Domain city yields + prototype woods overlay

- **Decision:** **`HexMap`** carries a **shallow-copied** **`woods`** **`Dictionary`** (axial **`Vector2i` → true**) populated for **`make_prototype_play_map`** from **`PrototypeTerrainFeatures.prototype_woods_set()`** — the **same** coordinate list as the historical presentation-only forest decoration list. **`CityYields`** (domain-only, **no** presentation imports) defines **v0** **`food` / `production` / `science` / `coin`** vectors from **terrain**, **woods**, **city-center** minimums, and **`building_id` `palace`**; **`ScienceTick.apply_for_player`** uses **`CityYields.science_for_player`** instead of a flat **per-city constant**. **`City`** gains **`is_capital`** and **`building_ids`**; **`FoundCity`** marks a player’s **first** founded city as capital with **`["palace"]`**; **`ProductionTick`**, **`ProductionDelivery`**, and **`SetCityProduction`** copy these fields when rebuilding **`City`** rows. **`PlainsForestScript`** **aliases** **`PrototypeTerrainFeatures.PROTOTYPE_WOODS_HEXES`** for the prototype overlay.
- **Rationale:** Single source of truth for prototype **woods** in domain rules and yields; **Palace** science matches the player-guide intent; presentation stays a thin re-export.

## 2026-05-12 — Player guide: Early City Economy (intended model)

- **Decision:** Document the **intended** early city economy in **player-facing** HTML (**[player/city-economy.html](player/city-economy.html)**): **v0** worked-tile yields (**Food** / **Production** / **Coin**; no raw-terrain **Science** in that table), **city center** normalization (**Food** ≥ 2, **Production** ≥ 1, **Coin** 0, **Science** 0 from that rule), **capital** + **Palace** **+1 Science** and **+1 Coin** (no Palace **Production** in this tutorial), **Coin** as the early generic economic yield with era-flexible **flavor**, and the principle that **science** starts from institutions (**Palace**) rather than every new city automatically acting as a full second research source from turn one. **Future systems** section ties to workers, improvements, **Stone Tools**, etc.
- **Rationale:** Shared vocabulary for testers; **documentation-only** slice (no gameplay change in this task).

## 2026-05-12 — Phase 5.1.15e — Shared city/unit hex: banner placement vs layering correction

- **Decision:** Revert **5.1.15d**’s **below-marker** city banner offset; keep the banner in the **normal above-marker** band so it stays visually **attached** to the city. **Layering:** **`CityNameplateView`** (**`z_index` 2**) cannot sit **under** unit markers drawn inside **`TerrainForegroundView`** (**1**), so when a **unit** shares the city hex, **`TerrainForegroundView`** draws **`CityNameplateView.draw_city_banner_on_canvas_item`** **after** **`draw_city_marker_at`** and **before** **`draw_unit_marker_at`** (depth-merge + pass 2). **`CityNameplateView`** skips that city’s banner when **`terrain_foreground_view`** is wired (**[main.gd](../game/main.gd)**). **`UnitNameplateView`** remains topmost (**`main.tscn`** sibling order unchanged). Default-off: **`TerrainForegroundView.debug_log_shared_hex_layer_order`** / **`EOM_DEBUG_SHARED_HEX_LAYER_ORDER`**.
- **Rationale:** Matches Civ-like **unit-over-label** overlap on the same tile without a detached banner; presentation-only.

## 2026-05-12 — Phase 5.1.15d — Shared city/unit hex: city banner below marker (**superseded by 5.1.15e**)

- **Decision:** **Diagnose-first:** **city-before-unit** marker order in **`TerrainForegroundView`** was already sufficient for readable unit PNGs in play. The visible bug was **`CityNameplateView`** shared-hex banner geometry: a small **x/y** offset still overlapped the **warrior** raster. **5.1.15d** places the city **banner below** the **city marker quad** when **`units_at(city.position)`** is non-empty (**`marker_bottom` + `CITY_BANNER_SHARED_UNIT_BELOW_GAP_PX`**, centered on **anchor** **x**). Default-off diagnostics: **`CityNameplateView.debug_log_shared_hex_banner`**, **`TerrainForegroundView.debug_log_shared_hex_marker_order`** (plus env **`EOM_DEBUG_*`** aliases).
- **Rationale:** Deterministic, presentation-only readability without moving units, changing selection, or reordering **`main.tscn`**.

## 2026-05-10 — Phase 5.1.15c — Shared city/unit hex marker and banner readability

- **Decision:** In **`TerrainForegroundView`** depth-merge, **`_fg_depth_merge_item_lt`** treats **same-hex** **city+unit** marker pairs **before** **sy/sx** comparisons so **microfloat** **`to_layout`** noise cannot paint **units** **behind** **city** art (defensive). Shared-hex **banner** readability is handled by **5.1.15e** (**TFV**-hosted banner under **unit** marker, normal above-marker geometry).

## 2026-05-10 — Phase 5.1.15b — City banner placement + unit-over-city nameplate layering

- **Decision:** Tighten city-banner **vertical gap** and raise **`CITY_BANNER_FONT_SIZE`** (presentation only). Reorder [main.tscn](../game/main.tscn) so **`CityNameplateView`** is **before** **`UnitNameplateView`** at the same **`z_index`**, so **unit** nameplates draw **on top** on **shared** city/unit hexes—**no** domain or selection changes.
- **Rationale:** Matches Civ-like expectation that the **active unit** remains readable; avoids per-hex special cases.

## 2026-05-10 — Phase 5.1.15 — City names (domain) + map banners (presentation)

- **Decision:** **`City.city_name`** is **domain state**, set deterministically by **`FoundCity`** (**`Capital`** for a player’s first city, then **`Settlement 2`**, **`Settlement 3`**, …); engine/production paths that rebuild **`City`** copy **`city_name`** forward. **Map banners** are **presentation-only** (**`CityNameplateView`**), reuse **`UnitNameplateView`** owner-accent logic, and fall back to **`City <id>`** only when **`city_name`** is empty (tests / legacy fixtures).
- **Rationale:** Readable capitals on the prototype map without economy/save work; names are available for future **HUD**, **save**, and **capital** features.

## 2026-05-10 — Phase 5.1.14 — SciencePanel locked-science prerequisite hints

- **Decision:** Surface **locked** sciences in the **same** **`SciencePanel`** as a **compact** prerequisite hint list (**`Requires:`** with **missing** prereqs only), using **`ScienceAvailability.locked_for`** order and **`ProgressDefinitions.prerequisites`** — **not** a tech-tree canvas, dependency arrows, research queue, or tooltip system.
- **Rationale:** Players can see **what exists next** and **why** it is blocked without **`LegalActions`** / **AI** changes or a full tree UI.

## 2026-05-10 — Phase 5.1.13 — Minimal science selection HUD (`SciencePanel`)

- **Decision:** The **first** in-run **science UI** is a **compact** **`HudCanvas`** **`SciencePanel`** — **not** a tech-tree canvas. It shows **effective** research (same rules as **`ScienceTick`** for display), **per-science** progress from **`ProgressState`**, and **available** rows from **`ScienceAvailability.available_for`**; buttons call **`SetCurrentResearch`** through **`GameState.try_apply`** only.
- **Decision:** **`SciencePanel`** may **`preload`** **`ProgressDefinitions`** for **`display_name`** / **`cost`** on this panel only; **Discovery** / **Science completed** popups stay **log-driven** without **`ProgressDefinitions`** imports.
- **Rationale:** Makes **5.1.12c** research pinning **discoverable** without **`LegalActions`**, **AI**, or **save/load** work.

## 2026-05-10 — Phase 5.1.12d — Settler baseline + Controlled Fire reward bundle

- **Decision:** **`ProgressState.with_default_unlocks_for_players`** unlocks **`city_project` / `produce_unit:warrior`** and **`produce_unit:settler`** for every initial player — **Train Settler** is **not** a **Controlled Fire** reward.
- **Decision:** **`controlled_fire`** **`concrete_unlocks`** / **`systemic_effects`** are the **hearth / camp / survival** metadata **bundle** only (**no** **`produce_unit:settler`** row); mechanics for **`hearth`**, **`camp_clearing`**, and modifiers stay **deferred**.
- **Decision:** **`ScienceCompletedPopup`** shows **Controlled Fire** curated copy when **`science_completed`** has **no** **`city_project`** **Train** lines (**Phase 5.1.12d**); **`DiscoveryPopup`** for **`complete_progress`** remains **train-line-gated** (real **Controlled Fire** **`complete_progress`** logs may **hide** it when the unlock delta is metadata-only).

## 2026-05-10 — Phase 5.1.12c — current_research_id + SetCurrentResearch + ScienceTick routing

- **Decision:** **Explicit** research target is stored as **`ProgressState.current_research_id`** per owner (**`""`** = **auto-target**); **`ScienceAvailability`** remains the **only** source of **which** sciences are available — **no** cached availability list on state.
- **Decision:** **`ScienceTick.apply_for_player`** uses **explicit** id when **set** **and** still **available**; otherwise **first** **`ScienceAvailability.available_for`** (alphabetical today); emits **`science_no_target`** when **no** research remains.
- **Decision:** **Lightning-tree** **`science_bonus`** and associated **`controlled_fire`** **`science_progress`** / completion stay **hard-wired** to **`controlled_fire`**, **independent** of **`current_research_id`** (discovery bonuses may “jump” a different lane than the city-yield target).
- **Rationale:** Players (or future UI) can **pin** a legal science while **map bonuses** keep **story-consistent** **controlled_fire** feedback.
- **Caveat:** **Auto-target** order is **not** Civ “left-to-right” tree order — it follows **`available_for`** sort (**alphabetical** in **5.1.12c**).

## 2026-05-10 — Phase 5.1.12b — ProgressDefinitions cost/prerequisites + ScienceAvailability

- **Decision:** **`cost`** and **`prerequisites`** are **canonical** on **`ProgressDefinitions`** science rows; **availability** (**what can be researched / completed next**) is **computed** from **`completed_progress_ids`** via **`ScienceAvailability`**, not duplicated on **`ProgressState`**.
- **Decision:** **`CompleteProgress`** (explicit player/debug completion) **validates prerequisites** for sciences and returns **`prerequisites_not_met`** when the DAG requires earlier sciences first.
- **Decision:** **`ScienceTick`** uses **`ProgressDefinitions.cost`** for log **`cost`** fields on **routed** targets (**5.1.12b**); **5.1.12c** replaces the **single hardcoded** tick target with **explicit** / **auto** routing (see **5.1.12c** decision block).
- **Rationale:** Unlocks the **19-science** Ancient slice in data while keeping the **playable** single-target loop stable through **5.1.12c** targeting work.
- **Caveat:** **`ProgressUnlockResolver`** does not re-check prerequisites (validation is **`CompleteProgress`** / future **`SetCurrentResearch`**); illegal completion paths must not bypass **`try_apply`**.

## 2026-05-10 — Phase 5.1.12a — Ancient science tree documentation checkpoint

- **Decision:** **Sciences** are **bundles** (`concrete_unlocks` / `systemic_effects`); **Controlled Fire** **stops being a Settler gate** ( **`produce_unit:settler`** drops from **`controlled_fire`** unlocks in **5.1.12d** ).
- **Decision:** **Settler** is **baseline from turn 1**, implemented in **5.1.12d** via **default `ProgressState` unlocks** (`city_project` / **`produce_unit:settler`**).
- **Decision:** **`cost`** + **`prerequisites`** extend **`ProgressDefinitions`**; **no** new **`ScienceDefinitions`** registry.
- **Decision:** **Textile Work** is unlocked by **Foraging Systems** to avoid a **Column 2** science with **no** inbound dependency in the Ancient tree.
- **Rationale:** Locks a **19-science** DAG, **costs**, targeting contracts, and **Settler** / **survival-tech** split before **5.1.12b–d** code.
- **Caveat:** **5.1.12a** is **docs-only**; behavior and tests change in **5.1.12b**–**d**.

## 2026-05-10 — Phase 5.1.11 — Code-drawn unit nameplates

- **Decision:** Add **`UnitNameplateView`** — **presentation-only** banners (unit label + muted owner accent) drawn **above** markers in **`_draw`**, **no** new PNGs, **no** **`Control`** / hit-test surface. Serves as **medium-term** unit-type clarity until unique marker art exists for every **`type_id`**.
- **Rationale:** Readable **Warrior** / **Settler** (and future types) labels reduce reliance on silhouette-only icons during the parchment prototype; **HudCanvas** remains the exclusive modal/panel layer (**`CanvasLayer` 16**).
- **Caveat:** Nameplate **`z_index` 2** must stay **below** **`HudCanvas`**; dense stacks of units can overlap labels visually.

## 2026-05-10 — Phase 5.1.10 — Discovery vs science-completed popups

- **Decision:** **`ScienceCompletedPopup`** remains the vocabulary for **`science_completed`** (automatic **`controlled_fire`** finish). **`DiscoveryPopup`** also handles **optional** **`science_bonus`** rows (**Phase 5.1.10:** **`bonus_id: lightning_scarred_tree`**) for one-time observation **feedback** — curated narrative + **`practical_line`** from log fields, **no** rule application in presentation. When **`science_bonus`** and **`science_completed`** appear in the **same** post-apply log slice, **show **`DiscoveryPopup`** first**, then **`ScienceCompletedPopup`** after **OK** (no simultaneous modals).
- **Rationale:** Players need to **see** that the landmark granted bonus progress; **`science_progress`** lines alone are easy to miss. Reusing **`DiscoveryPopup`** keeps “you noticed something” distinct from “science finished.”
- **Caveat:** Only **`lightning_scarred_tree`** is wired; other future bonuses would add **`compute_view_model`** cases or stay hidden.

## 2026-05-10 — Phase 5.1.8c — Lightning tree placement + stump scale

- **Decision:** **`make_prototype_play_scenario`** **`lightning_tree_hex`** moves from **`(3, -3)`** (**inside** the **prototype forest-cluster** decoration) to **`(3, 0)`** — **GRASSLAND** **FLAT**, **not** in **`PROTOTYPE_FOREST_DECORATION_HEXES`**, **hex distance ≥ 2** from all **starting unit** hexes so observation still requires a short move. **`LightningTreeView.STUMP_HEIGHT_HEX_FRAC`** reduced to **~0.50** (~half prior visual height). **`plains_forest_decoration.gd`** adds **`is_prototype_foreground_forest_hex(q,r)`** as the single predicate for “forest overlay cell” (wraps the existing prototype list — **not** a gameplay feature registry).
- **Rationale:** Manual play showed the stump **too large** and sitting under **foreground forest** art; design intent is an **open** landmark on **PLAINS/GRASSLAND** as **rendered**, not only by base **HexMap** tag under overlay.
- **Caveat:** **`is_prototype_foreground_forest_hex`** is **prototype-only** and tied to the hand-maintained cluster list.

## 2026-05-10 — Phase 5.1.8b follow-up — LightningTreeView visibility (layering)

- **Decision:** Move **`LightningTreeView`** **after** **`TerrainForegroundView`** in [main.tscn](../game/main.tscn) and set **`z_index = 1`** (with TFV) so it draws **on top of** the forest overlay. Earlier **`z_index = 0` placement** left the stump **fully covered** by **TFV** in play. **Chroma** narrowed to **bright magenta** only; removed **near-black** global key that could erase **bark/shadow**; optional **unkeyed** fallback when a bad key wipes the art.
- **Rationale:** Prototype landmark must be **seen** before the player visits the hex; **TFV** is intentionally above **`MapView`**/marker shells.
- **Caveat:** Stump may draw **above** **TFV-embedded** city/unit markers on that tile (acceptable trade until a single-pass interleave exists).

## 2026-05-09 — Phase 5.1.8b — Lightning tree HUD + `scarred_tree_stump.png` marker

- **Decision:** Add **`LightningTreeView`** (**`Node2D`**) and **`DiscoveryActionPanel`** (**`HudCanvas`**). The stump uses **`res://assets/prototype/terrain/scarred_tree_stump.png`** loaded via **`Image.load`** into an **`ImageTexture`**, with **magenta** and **near-black matte** pixels keyed transparent at runtime (**prototype landmark** only — **not** a resource catalogue, weather sim, or generalized art pipeline). **`DiscoveryActionPanel`** uses **`ProgressCandidateFilter`** and submits the same **`CompleteProgress`** **`try_apply`** as **`KEY_H`**; on accept it triggers **`DiscoveryPopup.maybe_show_for_log_index`** like **`KEY_G`/`KEY_H`**.
- **Rationale:** **5.1.8a** made **`controlled_fire`** depend on **observing** the optional map cell; players need a **visible landmark** on the prototype map and a **HUD** affordance besides the debug shortcut.
- **Caveat:** **Chroma** tolerances are tuned for this PNG; replacing the art may require retuning or switching to **true alpha**.

## 2026-05-09 — Phase 5.1.8a — Lightning-Scarred Tree observation (`controlled_fire` detector)

- **Decision:** Add optional **`Scenario.lightning_tree_hex`** (**nullable**, **untyped** ctor parameter) carried through **`MoveUnit`**, **`FoundCity`**, **`SetCityProduction`**, **`ProductionTick`**, and **`ProductionDelivery`** **`Scenario`** rebuilds. **`make_prototype_play_scenario`** sets a deterministic axial cell (**Phase 5.1.8c:** **`(3, 0)`** open **GRASSLAND**; earlier **`(3, -3)`** superseded); **`make_tiny_test_scenario`** keeps **`null`**. **`ProgressDetector`** no longer uses **found_city** for **`controlled_fire`**; it requires **`lightning_tree_hex != null`** and an **accepted `move_unit`** log entry for the player whose **`to`** is **on or adjacent** to the tree. **No** new actions, **no** log shape change, **no** **`try_apply`** contract change, **no** presentation.

- **Rationale:** **Prototype play** should gate **`controlled_fire`** on a **visible map interaction** (observation **via movement**), not on founding alone. This is a **single-cell landmark**, **not** a weather system, wildfire sim, resource catalogue, or random event layer.

- **Caveat:** **HEADLESS** / **tiny** tests keep **`lightning_tree_hex == null`** unless a test **opts in**; **`KEY_H`** only applies **`controlled_fire`** after the new observation rule is satisfied.

## 2026-05-09 — Phase 5.1.7 — Discovery unlock popup (HudCanvas)

- **Decision:** Add **[discovery_popup.gd](../game/presentation/discovery_popup.gd)** under **`HudCanvas`**: after **accepted** **`CompleteProgress`** from **`SelectionController`** (**`KEY_G`** / **`KEY_H`** only), **`maybe_show_for_log_index(int(try_apply["index"]))`** loads **`game_state.log.get_entry(index)`** and shows a **dismissible** panel when **`compute_view_model`** sees **`complete_progress`** with at least one **5.1.6-equivalent** **`city_project` / `produce_unit:*`** unlock; **`compute_view_model(log_entry)`** takes an **untyped** parameter so **`null`** and non-**`Dictionary`** inputs return **`visible: false`** without coercion errors, and **hidden** view models **do not** mutate existing popup visibility (**no** queue). **`controlled_fire`** uses fixed title (**`Discovery completed`**), heading, body, and **Unlocked:** bullets; other **`progress_id`** values with visible train unlocks use a **generic** body/heading. **No** domain / registry / **`LogView`** / production-panel / turn-controller edits.

- **Rationale:** **5.1.6** log lines are **debug-adjacent**; a short **HUD** acknowledgment makes **Train Settler**-class unlocks legible without reading the tail log.

- **Caveat:** Only **manual** **`KEY_G`** / **`KEY_H`** paths trigger the hook; other **`try_apply`** sites stay unchanged this phase.

## 2026-05-09 — Phase 5.1.6 — Unlock feedback cue (LogView)

- **Decision:** **[log_view.gd](../game/presentation/log_view.gd)** `format_entry` for **`complete_progress`** prints **`[<i>] P<p> <Humanized progress_id> completed`**, then one line per eligible unlock: **`       Unlocked: Train <Suffix>`** — **exactly seven ASCII spaces** before **`Unlocked`**. Only **`unlocked_targets`** rows with **`target_type` `city_project`** and **`target_id`** starting **`produce_unit:`** participate; **`buildings`**, **`modifiers`**, etc. stay hidden in this slice. String humanization only — **no** **`ProgressDefinitions`** / registry reads; **no** action log schema change.

- **Rationale:** **5.1.0–5.1.3** loop is playable; players need a **visible** cue when **Train Settler** becomes legal without popups or city-panel churn.

- **Caveat:** **`MAX_ENTRIES`** still counts **log entries**, not wrapped lines; **`complete_progress`** can add multiple visible lines per entry.

## 2026-05-09 — Phase 5.1.5 — City production panel polish

Decision:

- Present **`CityProductionPanel`** as a restrained **`PanelContainer`** with **StyleBoxFlat** (parchment tone, border, light corner radius, subtle shadow), **HSeparator** section breaks, **theme** font sizes/colors on **Labels** / **Buttons**, and clearer **view-model** strings (**City**, **#id · Owner**, **Producing:** / **Ready:** / **No active project**, **Available production**, empty **busy** vs **no projects** lines). **`compute_view_model`** still drives options from **`LegalActions`** only; **`call_deferred("refresh")`** after button **`try_apply`** unchanged.

Rationale:

- **5.1.4** functionally complete; **playtest** readability benefits from hierarchy and muted strategy-HUD feel **without** art imports or gameplay edits.

Caveat:

- **Multi-line** status may grow with future project types; panel width is **viewport-anchored** in **main.tscn**.

## 2026-05-09 — Phase 5.1.4b — Shared city / own-unit hex click cycling

Decision:

- When the hex under the cursor contains **both** the **selected** city (lowest **`city.id`** hit) **and** **at least one unit owned by** **`turn_state.current_player_id()`**, **`SelectionController`** alternates on **repeated left clicks** on **that** **(q,r)**: **city** → **unit** (**lowest unit id** on the tile) → **city** → …**. **Implementation:** pure helper **`plan_shared_hex_pick`** + **instance** **track** **`(q,r)`** + **`phase`**, reset when the player clicks another hex, clears selection, moves successfully, or picks a unit on a **non-city** tile.

Rationale:

- **Phase 5.1.4** routed **city** pick **before** **unit** pick so the **CityProductionPanel** was reachable; that made **own units** on the **city** hex **unselectable**. **Cycling** preserves **first** click = **city** / **panel**, **second** = **unit**, without new HUD or domain changes.

Caveat:

- Multiple **own** units on one city hex always use the **same** **lowest-id** target on the **unit** step (**no** per-hex **unit** round-robin yet).

## 2026-05-09 — TerrainForegroundView symbol-grid merge — city/unit sort keys

Decision:

- In **`_fg_draw_depth_merged_forest_symbol_grid_and_units`**, **merge list entries** for **cities** and **units** use **`cam.to_layout(cam.to_presentation(hex_center_world))`** as **`sy`/`sx`**, not **`city_effective_depth_presentation`** / **`unit_effective_depth_presentation`**. **`draw_city_marker_at`** / **`draw_unit_marker_at`** still receive **anchors** and **scale** as before; only **interleave order** vs **forest symbols** changes.

Rationale:

- **Effective-depth** presentation points differ on the **same hex**, so **`ty`** tie-break never ran and **cities** could **paint after** **units** in the merge pass, **hiding warriors** (including **starting** units on **city** tiles). **Hex-center** keys align **same-tile** **`sy`/`sx`** so **`ty` 1 < 2** draws **units on top**.

Caveat:

- **Forest** symbol **interleaving** vs **city/unit** on **adjacent** hexes now keys off **hex-center** depth in **merge mode** (not sprite foot/bottom); **TFV** remains **visual-only**.

## 2026-05-09 — Phase 5.1.4 bugfix — City panel input + pick order

Decision:

- Move **`CityProductionPanel`** under **`HudCanvas`** (**`CanvasLayer`**) with **top-right anchors**; **`refresh()`** sets **`mouse_filter`** to **`IGNORE`** when hidden and **`STOP`** when visible. Run **city** hex hit-test **before** **unit** hex hit-test so a **unit** on the **city tile** does not block **`select_city`**.

Rationale:

- **Manual smoke:** map clicks are **`_unhandled_input`** on **`SelectionController`**; a **`Control`** using **`MOUSE_FILTER_STOP`** must not sit in the **Node2D** root in a way that **starves** that path, and **hidden** panels must **not** steal input. **Pick order** matches **city management** expectations on **shared** tiles.

Caveat:

- **Clicking** a **hex** that has **both** a **city** and a **unit** now **prefers** the **city** (panel); select the **unit** via a **hex** that contains **only** that **unit** (or clear the **city** focus first).

## 2026-05-09 — Phase 5.1.4 — Minimal city production panel

Decision:

- Add **`CityProductionPanel`** (**`VBoxContainer`**, **`LegalActions`**-driven buttons only, **`try_apply`** on press) and **`SelectionState.city_id`** with **city** hex pick after **unit** pick; **`EndTurnController`** / **`AITurnController`** use **`selection.clear_unit()`** on accept so **city** focus survives **`EndTurn`**; panel hides when **`scenario.city_by_id`** is missing.

Rationale:

- Smallest **HUD** slice so players see **production** status and legal **SetCityProduction** targets without a second rules engine; **click-through** blocked via **`MOUSE_FILTER_STOP`**.

Caveat:

- **No** registry/EffectiveRules reads in the panel; **no** clear-production UI; labels are **substring** titles from **`project_id`**, not **`CityProjectDefinitions`** display names.

## 2026-05-09 — Phase 5.1.3 — Settler production and delivery proof

Decision:

- Ship **`game/domain/tests/test_settler_production_flow.gd`** only: **`GameState.try_apply`** path from **`FoundCity`**, **`CompleteProgress(controlled_fire)`**, **`SetCityProduction(produce_unit:settler)`**, **`EndTurn`** cadence for **`ProductionTick`** / **`ProductionDelivery`**, then **`MoveUnit`** and **`FoundCity`** with the delivered settler. **No** changes to **`production_tick.gd`**, **`production_delivery.gd`**, **`game_state.gd`**, content, or actions.

Rationale:

- Confirms **5.1.2** wiring against the **existing** generic **`produces_unit_type`** resolution; keeps the slice proof-only and regression-safe.

Caveat:

- Test-only slice; does not change AI, UI, or auto-apply.

## 2026-05-09 — Phase 5.1.2 — Settler city project + controlled_fire unlock

Decision:

- Mint **`produce_unit:settler`** in **`CityProjectDefinitions`**, add **`city_project` / produce_unit:settler** to **`controlled_fire`** **`concrete_unlocks`**, expose **`PROJECT_ID_PRODUCE_UNIT_SETTLER`**, and have **`LegalActions`** enumerate warrior then settler through existing **`EffectiveRules`** and **`ProgressState`** gates. **`GameState.try_apply`** already returns **`project_not_unlocked`** for locked **`SetCityProduction`**; **5.1.2** does not change that branch.

Rationale:

- Smallest slice that makes the planned v0 second project playable after **`controlled_fire`** without schema bumps, UI, AI policy changes, or **`ProgressUnlockResolver`** code changes (data-only unlock row).

Caveat:

- **`LegalActions`** uses an explicit **`[warrior, settler]`** candidate list keyed on **`SetCityProduction`** constants; broader registry-driven enumeration remains a future slice. No **`ProductionDelivery`** regression test for settler in **5.1.2**.

## 2026-05-09 — Phase 5.1.1 — EffectiveRules façade + LegalActions read path

Decision:

- Ship minimal **`EffectiveRules`** ([`effective_rules.gd`](../game/domain/effective_rules.gd)) and route **one** read through **`LegalActions.for_current_player`**: **`is_city_project_supported`** before warrior **`SetCityProduction`** enumeration; optional injectable façade for tests; baseline matches **`CityProjectDefinitions`**.

Rationale:

- Establishes the **read boundary** from **Phase 5.0a** in code without changing default behavior; keeps validation and progress gating order intact.

Caveat:

- **5.1.1** introduced the façade and warrior-first enumeration; **5.1.2** adds settler when supported and unlocked. **AllTrue**-style fakes still prove the support gate does not bypass **`validate`** for enumerated ids.

## 2026-05-09 — Phase 5.1 — Ancient mini-game embryo umbrella

Decision:

- **Phase 5.1** owns the **curated** Ancient mini-game embryo: **EffectiveRules** first-read wiring, **second city project** after knowledge unlock, **no** generated worlds in v0. See [PHASE_PLAN.md](PHASE_PLAN.md).

Rationale:

- Separates **strategic-dynamics** growth from **2.x** loop freeze documentation without restarting terrain or presentation architecture.

Caveat:

- Subphases **5.1.1+** implement incrementally; this entry is **steering** only.

## 2026-05-09 — Phase 5.1.0 — embryo intent + content shortlist (docs-only)

Decision:

- **5.1.0** ships **documentation only** in six owner files; **no** code, registry, action, or presentation changes.

Rationale:

- Locks **v0 loop intent** and **deferrals** before the first **EffectiveRules** code slice.

Caveat:

- Headless test count must stay unchanged (regression-only).

## 2026-05-09 — Phase 5.1.0 — planned v0 unlock `produce_unit:settler`; minting deferred

Decision:

- Steering may name **`produce_unit:settler`** as the **planned** future v0 **city project** unlock target (settler-class production). **5.1.0** **does not** implement, register, validate, or **mint** that id in **`CityProjectDefinitions`** or elsewhere — that happens in a **later** code slice. See [PROGRESSION_MODEL.md](PROGRESSION_MODEL.md), [CORE_LOOP.md](CORE_LOOP.md).

Rationale:

- Human-readable planning without premature registry churn or **`LegalActions`** surface expansion in a docs-only gate.

Caveat:

- Final id string remains subject to the same **[CONTENT_MODEL.md](CONTENT_MODEL.md)** id discipline when implemented.

## 2026-05-09 — Phase 5.1.0 — EffectiveRules first-read pattern documented

Decision:

- First **5.1.x** code slice introduces a thin **`EffectiveRules`** façade and migrates **one** existing registry read; further reads migrate in small follow-ons. See [CONTENT_MODEL.md](CONTENT_MODEL.md).

Rationale:

- Satisfies **Phase 5.0a** runtime boundary intent without a monolithic rewrite.

Caveat:

- **`EffectiveRules`** owns **no** authoring tables in v0; curated baseline registries remain providers.

## 2026-05-09 — Phase 5.1.0 — no expansion of 5.0a future systems; deferrals explicit

Decision:

- **5.1.0** does **not** expand LLM, generator, save/load, cloud, or networking design **beyond Phase 5.0a**; focus stays on the **curated** embryo. **Deferred:** dedicated per-city **science yield** stat, detector **auto-apply**, second science row, generated worlds. See [PHASE_PLAN.md](PHASE_PLAN.md), [CITIES.md](CITIES.md).

Rationale:

- Prevents scope bleed from embryo work into infrastructure not yet in implementation scope.

Caveat:

- Future slices add features only when explicitly steered.

## 2026-05-09 — Phase 5.0a — RuleSet / EffectiveRules as runtime content boundary

Decision:

- **RuleSet** (canonical match snapshot) + **EffectiveRules** (validated / compiled view) are adopted as the **runtime content boundary** once implemented; **definitions / registries** remain **inputs**, not direct gameplay oracles. See [CONTENT_MODEL.md](CONTENT_MODEL.md), [ARCHITECTURE_PRINCIPLES.md](ARCHITECTURE_PRINCIPLES.md).

Rationale:

- Supports **generated worlds**, **replay**, and **cloud-shaped** authority without baking one global static table into every rule path.

Caveat:

- **5.0a** is **docs-only**; no code, schema field tables, or balance numbers.

## 2026-05-09 — Phase 5.0a — capability / material roles; no fixed historical material chain

Decision:

- Model work may use **role abstractions** (e.g. edge material, armor material, smelting capability, metallurgy tier); the engine must **not** assume **iron / bronze / steel** always exist or always form one fixed dependency chain. See [PROGRESSION_MODEL.md](PROGRESSION_MODEL.md).

Rationale:

- Alternate worlds can make different materials **strategically central** or **absent**.

Caveat:

- **Roles** are conceptual in **5.0a**; binding and registry rows ship in later phases.

## 2026-05-09 — Phase 5.0a — generation is candidate-only; validation / compilation is authoritative

Decision:

- **LLM** or other **generators** produce **candidates** only; **deterministic** validation / compilation decides playable **RuleSets**. **AI players** still choose from **legal actions** over **EffectiveRules**. See [AI_DESIGN.md](AI_DESIGN.md), [CONTENT_MODEL.md](CONTENT_MODEL.md).

Rationale:

- Keeps **replay** and **server authority** compatible with generative content without bypassing the rules engine.

Caveat:

- **5.0a** does not add generator or validator implementations.

## 2026-05-09 — Phase 5.0a — RuleSet id + hash + schema_version for replay / cloud

Decision:

- Saved and **async / cloud** sessions must **reference** **RuleSet id**, **content hash**, and **`schema_version`** concepts so **`ActionLog`** replay uses the **same** **EffectiveRules**. See [CLOUD_PLAY.md](CLOUD_PLAY.md).

Rationale:

- Prevents silent mismatch between **log** and **content** across builds and generated worlds.

Caveat:

- **No** wire format or storage schema in **5.0a**.

## 2026-05-09 — Phase 5.0a — visual polish paused after Phase 4 checkpoint

Decision:

- **Visual polish** is **paused** from **5.0a** until the **playable embryo** direction is established; resumption requires **explicit** later phase scoping. See [VISUAL_DIRECTION.md](VISUAL_DIRECTION.md), [PHASE_PLAN.md](PHASE_PLAN.md).

Rationale:

- Avoids **scope bleed** between **terrain / presentation** iteration and **Phase 5** gameplay embryo work.

Caveat:

- **RENDERING.md** and implementation state are unchanged; only **direction / process** gate is updated.

## 2026-05-09 — Phase 5.0a — playtest guide skeleton; Cursor skill for player copy deferred

Decision:

- Add **`docs/player/PLAYTEST_GUIDE.md`** as a **skeleton** (headings + intent notes only). **Defer** a dedicated **Cursor skill** for player guide / civilopedia-style writing until player-facing copy is actually authored.

Rationale:

- Reserves a **player-facing** channel without duplicating steering text; skill is unnecessary until there is recurring author work.

Caveat:

- **PLAYTEST_GUIDE** must stay **player-facing**; implementation detail belongs in **`docs/PHASE_PLAN.md`** and model docs.

## 2026-05-01 — Phase 4.5n — center-anchored MapCamera zoom (wheel; not cursor-anchored)

Decision:

- **`MapCamera`:** **`zoom`**, **`min_zoom` / `max_zoom`**, **`set_zoom_clamped`**; **presentation** **scale** **around** **`vanishing_pres`**; **`perspective_scale_at` * `zoom`** for **billboard** **sizing**. **`to_layout`** **divides** by **`max(zoom, 0.0001)`** **only** **when** **needed** ( **`zoom≈1`** **fast** **paths** **avoid** **FP** **drift** ).
- **`main.gd`:** **wheel** **in** **`_input`**, **`ZOOM_STEP`**, **`center_local`** **correction** **`offset += world_before - world_after`**; **`old_zoom`** **guard** **when** **clamp** **blocks** **factor**; **no** **`Camera2D`**, **no** **mouse-anchored** **zoom** **this** **phase**.

Rationale:

- **Uniform** **zoom** **in** **map** **layer** **space** **keeps** **picking** / **markers** / **forest** **aligned** **through** **`MapCamera`** **only**.

Caveat:

- **`vanishing_pres`** **still** **set** **once** in **`_ready`**; **resize** **does** **not** **recalc**; **mouse**-**anchored** **zoom** **deferred**.

## 2026-05-01 — Phase 4.5m — **MapCamera** plane-space pan (replaces **4.5l** screen-layer pan)

Decision:

- **`MapCamera`** (**`map_camera.gd`**) wraps **`MapPlaneProjection`** + **`camera_world_offset`**; views / **`SelectionController`** use **`camera.to_presentation`** / **`to_layout`** / **`perspective_scale_at`**. **`main.gd`:** **`vanishing_pres`** set **once** in **`_ready`** to **`viewport * 0.5 - MAP_LAYER_ORIGIN`**; map nodes **`position = MAP_LAYER_ORIGIN`** once; right-drag updates **`camera_world_offset`** from **layer-local** **`MapView.to_local`** samples (**grab** invariant: **`offset += prev_world - cur_world`**).

Rationale:

- **4.5l** panned by **moving** **Node2D** **layers** — the **projected** image **slides** as a **flat** **composite**. **4.5m** pans in **layout** **space** **before** **projection** so **recession** / **scale** **update** during drag.

Caveat:

- **4.5n** adds **presentation** **zoom** (**wheel**); still **no** **`Camera2D`**, **bounds**, **inertia**; **window** **resize** does **not** **recompute** **`vanishing_pres`** after **`_ready`**.

## 2026-05-01 — Phase 4.6d — terrain foreground stable; unit occluder additive only

Decision:

- **`TerrainForegroundView`:** **always** **`_draw_plains_forest_front`** on **decorated** **PLAINS**; **`_draw_unit_forest_occluder`** **only** **after**, **if** **`enable_unit_occlusion_test`** **and** **units** **without** **city**.

Rationale:

- **Occupied** hex **replaced** **branch** **dropped** **terrain**-**owned** **clumps**; **layering** **test** must **not** **remove** **hex** **vegetation**.

Caveat:

- **`enable_unit_occlusion_test`** remains **prototype** **overlay**; **final** **read** is **hex**/ **terrain**-**owned** **foreground**.

## 2026-05-01 — Phase 4.6c — unit-aware forest foreground occluder (presentation test)

Decision:

- **`TerrainForegroundView`:** on **decorated** **PLAINS** with **units** and **no** **city**, draw **large** **occluder** from **`anchor_pres`** and **`side`** (**same** formula as **`UnitsView`** **`side`**); **`Scenario`** **read-only**; **controllers** **sync** **`scenario`**, **`map`**, **`queue_redraw`** on **accepted** actions.

Rationale:

- **Hex-only** foreground did **not** **overlap** **units** **meaningfully**; **unit-anchored** **mass** tests **layering** **without** **terrain** **rules**.

Caveat:

- **Prototype** **decoration** **only** — **not** **cover** / **combat** semantics.

## 2026-05-01 — Phase 4.6b-polish — larger woodland clumps, density 0.25

Decision:

- **MapView** **back** forest: **2–3** **clusters** / **decorated** hex, **large** **overlapping** circles + **occasional** **skewed** **quad**; **TerrainForegroundView**: **1–2** **front** **masses** (circles + **triangle**), **stronger** **olive** read, **`forest_front_opacity`** default **0.72**. **`forest_density_ratio`** default **0.25** (**MapView** + **synced** in **`main.gd`**).

Rationale:

- **Live** read was **plot**/ **speckle**; **goal** is **painterly** **woodland** **silhouettes** with **clear** **front**/**back** **layering**.

Caveat:

- Still **PLAINS** **decoration** **only** / **no** **`Terrain.FOREST`**.

## 2026-05-01 — Phase 4.6b-debug — forest visibility + shared projection (TerrainForegroundView)

Decision:

- **`Main`:** **`TerrainForegroundView.camera = _map_camera`** (**same** **`MapCamera`** / **`MapPlaneProjection`** as **`MapView`** / markers) — **not** a **fallback** **`MapPlaneProjection.new()`** in **`_draw()`**.
- **`MapView` / `TerrainForegroundView`:** **raise** procedural forest **alpha** and **stroke/circle** sizes for readability over **terrain** art; **`MapView.forest_back_opacity`** export for quick tuning; **`TerrainForegroundView.forest_debug_log_counts_once`** for **one** **PLAINS**/**decorated** stats line.

Rationale:

- **Live** review: marks were **near-invisible** (**~0.08** alpha, **~2px** dots); **foreground** projection **wiring** was **missing**, so **pan** could **misalign** **layers**.

Caveat:

- Still **decoration-only** / **PLAINS-only** / **no** **`Terrain.FOREST`**.

## 2026-05-01 — Visual-only PLAINS forest decoration prototype (Phase 4.6b; presentation only)

Decision:

- **`MapView`** draws **deterministic** **back** canopy/stroke clumps on a **density**-gated subset of **PLAINS** hexes (after **4.1e** detail); **`TerrainForegroundView`** draws **1–3** **foreground** bush clumps per the **same** hexes; sibling order **MapView** → **CitiesView** → **SelectionView** → **UnitsView** → **`TerrainForegroundView`** → **`SelectionController`**. **`plains_forest_decoration.gd`** holds the **shared** gate (**no** **`Terrain.FOREST`**).

Rationale:

- Exercises **4.6a** **layering** (back vs **foreground** occluder) **without** domain terrain types, **3D**, **shaders**, or **rule** changes.

Caveat:

- **Decoration** **only** — **no** combat/movement/vision semantics; **no** new **PNG**s; future **rasters** → **4.3j**.

## 2026-05-01 — Terrain layering + forest visual model checkpoint (Phase 4.6a; documentation only)

Decision:

- Adopt a **terrain layering** model for future **2.5D** “**forest** / **cover**” **feel**: **terrain** **base** / **back** detail → **cities** → **selection**-**ground** overlays → **units** → **planned** **`TerrainForegroundView`** (**small** foreground occluders) **between** **`UnitsView`** and **`SelectionController`** → **controller** / **HUD**. **4.6a** updates **docs** **only** — **no** **`TerrainForegroundView`** node yet.

Rationale:

- Delivers a **simple** **layered** read (**depth** **without** full **3D**, **custom** **shaders**, or a **gameplay** **terrain** system) while keeping **units**, **cities**, and **selection** **readable**.

Caveat:

- **First** forest-**styled** delivery (**4.6b**) is **visual**-**only** on **PLAINS** — **no** **`Terrain.FOREST`** **enum**, **no** **rules**, **no** **domain** semantics; **procedural** **first**; **rasters** **later** only under **4.3j**.

## 2026-05-01 — Larger prototype map + right-drag pan (Phase 4.5l)

Decision:

- **`HexMap.make_prototype_play_map()`** — **R**=**5**, **91** **cells**; **`make_tiny_test_map()`** **unchanged** **for** **headless** **fixtures**.
- **`Scenario.make_prototype_play_scenario()`** — **same** **three** **units** **as** **tiny**; **`main.gd`** **uses** **this** **for** **editor** **play**.
- **`Main`:** **`_map_layer_pos`** **starts** **at** **`MAP_LAYER_ORIGIN`**; **right-button** **mouse** **drag** **pans** **map** **layers** **`+=`** **`relative`**; **`vanishing_pres`** = **`viewport`** **half-size** **−** **`_map_layer_pos`** **on** **each** **move**; **no** **`Camera2D`**.

Caveat:

- **Rollback** = **single** **`make_tiny_test_scenario()`** **in** **`main`** **and** **remove** **pan** **state**.

## 2026-05-01 — Settler pivot override fine-tune (Phase 4.5k)

Decision:

- **`UnitsView._UNIT_MARKER_PIVOT_BY_TYPE["settler"]`**: **`y`** **`0.88` → `0.86`** (**presentation-only**).

Caveat:

- **Rollback** = restore **`0.88`**.

## 2026-05-01 — Per–**type_id** unit marker pivot overrides (Phase 4.5j)

Decision:

- **`UnitsView._UNIT_MARKER_PIVOT_BY_TYPE`** — **only** **type_id**s whose **marker** **art** **differs** from **`unit_marker_pivot_*`** defaults; **settler** **`Vector2(0.50, 0.86)`** (**4.5k**; **was** **`0.88`** **at** **4.5j** **ship**) (**warrior** unlisted → **default** **`0.90`** **Y**).

Rationale:

- **Settler** **asset** **foot** / **alpha** **margin** **differs** from **warrior**; **per-type** **table** **avoids** **global** **pivot** **drift**.

Caveat:

- **Rollback** = remove **table** / **settler** **entry** and **`_resolved_marker_pivot`**, use **export** **pivots** **only** (**4.5i**).

## 2026-05-01 — Unit marker foot-pivot in texture space (Phase 4.5i)

Decision:

- **`UnitsView`**: **`unit_marker_pivot_x_ratio`** (**default** **`0.50`**) and **`unit_marker_pivot_y_ratio`** (**default** **`0.90`**) — **`anchor_pres`** (**`projection.to_presentation(layout.hex_to_world)`**) aligns to that **fraction** inside the **square** **`draw_texture_rect`**, not the **image** **bottom** **edge** (**prior** behavior = **implicit** **`(0.5, 1.0)`**).
- **Textured** **`Rect2`**: **`anchor_pres - (side * pivot_x, side * pivot_y)`** origin; **`side`** = **`unit_icon_height_ratio`** span × **`perspective_scale_at(world_center)`** — **unchanged**.

Rationale:

- **Asset** **feet** sit **above** the **PNG** **bottom**; anchoring the **rect** **bottom** at the **hex** **center** drew units **too** **high**.

Caveat:

- **Rollback** = restore **`Rect2(..., anchor.y - side, ...)`** with **fixed** **½** / **full-height** **offset** only.

## 2026-05-01 — Projected top-view hex center marker anchoring (Phase 4.5h)

Decision:

- **Units** / **cities:** **anchor** = **`projection.to_presentation(layout.hex_to_world(q, r))`** — **logical** top-view **hex** **center** then **projected**, **not** **centroid(projection(hex corners))** (those differ under **non-affine** **projection**).
- **`MapPlaneProjection.projected_hex_centroid_pres`** **removed** (was **4.5g** only); **`perspective_scale_at(world_center)`**, **polygon** **picking**, **depth** / **`plane_y_scale`** **unchanged**.

Rationale:

- **Live review:** **4.5g** centroid **mis-placed** markers vs **intended** **gameplay** **cell** **center**.

Caveat:

- **Rollback** = restore **4.5g** **centroid** helper + **call** **sites**.

## 2026-05-01 — Civ6-like mild perspective + marker scale/centroid (Phase 4.5g)

Decision:

- **`depth_strength`** **`0.0010` → `0.0004`** — **intended tuning band** **`0.0003`–`0.0005`** for a **mild** strategic-map recession (**Civ6** ballpark), not a **steep** tabletop strip.
- **`plane_y_scale`** **`0.82` → `0.90`** — **less** vertical flattening; **broader** readable board.
- **`MapPlaneProjection.perspective_scale_at(world)`** — **`1.0 / (1.0 + depth_strength * (near_world_y - world.y))`**, same as **`to_presentation`** scale; **UnitsView** / **CitiesView** textured markers multiply **`icon_side`** by this **exactly** (no **lerp**).
- **`MapPlaneProjection.projected_hex_centroid_pres`** — **shoelace** centroid of **projected** hex corners; **units**: **bottom-center** of upright **`draw_texture_rect`** at centroid; **cities**: **centered** textured rect on centroid. **`vanishing_pres`** policy (**viewport center** − **`MAP_LAYER_ORIGIN`**) **unchanged**; **SelectionController** still **picks** on the **full projected hex polygon** (same corners as terrain).
- **`city_marker_center_y_offset_ratio`** default **`0.05` → `0.0`**; **draw** **ignores** pre-projection **Y** nudge (**4.5g** centroid path). **`unit_icon_foot_offset_ratio`** **unused** on textured path (**compat** export).

Rationale:

- **Live review:** **4.5f** still read as **strong** **shear** / **tabletop**; **weaker** **`depth_strength`** + **higher** **`plane_y_scale`** move toward **almost** top-down with **subtle** depth.

Caveat:

- **Rollback** = revert **4.5g** commit; reverts **marker** **scale** + **centroid** anchoring to **4.5f** behavior.

## 2026-05-01 — Perspective tuning + picks + anchors (Phase 4.5f)

Decision:

- **`depth_strength`** **`0.0015` → `0.0010`** — softer **projective** **recession**; **`vanishing_pres`** wiring unchanged.
- **`SelectionController`**: **legal** hexes + **unit** hexes — **`Geometry2D.is_point_in_polygon`** on **projected** corners vs **`to_local(mouse)`** (matches **drawn** **cells**).
- **`unit_icon_foot_offset_ratio`** **`0.20` → `0.24`**; **`city_marker_center_y_offset_ratio`** **`0.05`** (**+layout** **Y** before **project**).

Rationale:

- **4.5e** felt **strong**; **layout**-space **radius** **picks** mis-aligned with **skewed** **hex** **silhouettes**.

Caveat:

- **`marker_hit_radius_ratio`** **unused** for **mouse** **path**; **rollback** = revert **4.5f** **commit**.

## 2026-05-01 — Projective map-plane perspective (Phase 4.5e)

Decision:

- **`MapPlaneProjection`**: replace **affine** **`shear_x_per_world_y`** with **projective** **`w` / `scale`**, **`depth_strength`** **`0.0015`** at ship (**4.5f** softens to **`0.0010`**), **`near_world_y`** **`192.0`**, **`plane_y_scale`** **`0.82`**, **`vanishing_pres`** from **viewport center** − **`MAP_LAYER_ORIGIN`** in **`main.gd`**. **Closed-form** **`to_layout`**.

Rationale:

- **Affine** **4.5d** still read as **shear**; **perspective divide** gives **receding** convergence toward **visible** **center**.

Caveat:

- **Terrain** **UVs** stay **layout**-anchored; slight **non-perspective-correct** **per-hex** **warp** — **prototype** **acceptable**. **Rollback** = **git** revert to **4.5d** **affine**.

## 2026-05-01 — Map-plane shear sign tuning (Phase 4.5d)

Decision:

- **`shear_x_per_world_y`** **`0.12` → `-0.10`** — **`plane_y_scale`** **`0.82`** unchanged; **`MAP_LAYER_ORIGIN`** unchanged. **4.5c** **`MapPlaneProjection`** **API** and **inverse** unchanged.

Rationale:

- **Live:** positive shear read as **lateral** skew vs **receding** plane; **negative** shear reverses **X** drift vs layout **Y** for a better **away-from-viewer** read with the board on the **left**.

Caveat:

- If **`-0.10`** feels strong, try **`-0.08`**; **no** per-layer hacks.

## 2026-05-01 — Shared map-plane projection (Phase 4.5c)

Decision:

- **`MapPlaneProjection`** (**`to_presentation`** / **`to_layout`**) — affine **`shear_x_per_world_y`** **`0.12`**, **`plane_y_scale`** **`0.82`** at ship (**4.5d** adjusts default shear — see **4.5d** entry); **one** instance from **`main.gd`** shared by **`MapView`**, **`SelectionView`**, **`UnitsView`**, **`CitiesView`**, **`SelectionController`**. **`MAP_LAYER_TILT_Y`** / layer **`scale`** **removed**.
- **Terrain / selection:** project **polygon** corners; **UVs** remain **layout**-anchored (**4.1d**). **4.1e** details use **projected** positions.
- **Units / cities:** **layout** anchors + **upright** rects. **Picking:** **`to_layout(to_local(mouse))`** vs **`hex_to_world`**.

Rationale:

- **Receding-plane** read without **3D** / **`Camera2D`**; **foot** anchoring preserved; **icons** not **squashed** by **`Node2D`** scale.

Caveat:

- **Affine** only; **rollback** = restore **`4.5a`** **`Node2D`** **`scale`** + drop projection wiring.

## 2026-05-01 — Map-plane projection design checkpoint (Phase 4.5b; docs only)

Decision:

- **Documentation-only:** Future **faux perspective** should use a **shared** **presentation-space** **map-plane projection** — **forward** (**layout / world** → **draw**) and **inverse** (**picking** / **`SelectionController`**) — **one** canonical path for **terrain**, **selection** geometry, **units**, **cities**, and **hit-tests**.
- **`4.5a`** **unit** **`unit_icon_foot_offset_ratio`** / **foot** anchoring in **`hex_to_world`** space is **approved** and **preserved**; **`MAP_LAYER_TILT_Y`** is **explicitly** **temporary** **flattening**, **not** true **receding-plane** perspective.
- **Units:** **Foot** in **layout** space, then **project**; **prefer** **upright** **billboard** draws **without** inheriting map-plane **squash**. **Cities:** **center** markers **or** **later** placement rule — **no** change **required** now. **Layering:** **terrain back** → **unit** → **optional** foreground **occluder** remains **future**; **no** **forest/cover** in **4.5b**.
- **Checkpoint excludes:** **Camera2D** **zoom/pan**, **real 3D**, **gameplay/domain/content/** **`HexLayout`** changes.

Rationale:

- **Live review:** uniform **Y-scale** does **not** read as **perspective**; steering **now** avoids **divergent** per-view hacks and keeps **readability** / **click alignment** as the **priority**.

Caveat:

- **Implementation** phase must **reconcile** **billboard** icons with **`main.tscn`** **layer** structure and **tests** — **TBD**; **rollback** remains **revert** to **`4.5a`** **Node2D** scale.

## 2026-04-29 — Phase 3.0: Content model envelope decided

Decision:
Phase **3.0** locks a **docs-only** content model: **GDScript** registry modules (added starting **3.1**, under `game/domain/content/`), **stable string IDs** on domain state, **no autoload**, **no JSON / `.tres`** data files yet, **`Scenario`** remains definition-free, and **[CONTENT_MODEL.md](CONTENT_MODEL.md)** is the **authoritative** envelope for Phase **3.1–3.5** implementation.

Rationale:
Keeps Phase **3** content work **deterministic**, **serializable** (state stores IDs; definitions ship with code), and **headless-testable** without hidden globals—aligned with domain-first architecture and future cloud/save constraints.

Caveat:
**Exact definition field shapes** are finalized **per subphase** (3.1–3.5), not all in **3.0**; this checkpoint fixes conventions and boundaries, not every stat column.

## 2026-04-29 — Phase 2.6: core loop frozen; CORE_LOOP.md + smoke test

Decision:
Phase **2.x** core loop is **frozen** as the baseline immediately before Phase **3** content foundation. **[CORE_LOOP.md](CORE_LOOP.md)** is the human-readable summary of what the prototype does today (playable loop, log order, placeholders, F5 checklist, validation command). **`game/ai/tests/test_core_loop_ai_smoke.gd`** is the headless **end-to-end** guard: AI drives **`GameState.try_apply`** until **`unit_produced`** appears and turn number reaches **2+**, without choosing engine log types.

Rationale:
Entering Phase **3** with only scattered docs and partial tests risks drift between “what we think works” and the **actual** loop. One short checkpoint doc plus one smoke test keeps **documentation and behavior aligned** at low cost.

Caveat:
**2.6** is **not** UI/HUD polish, not final balance, and not a replacement for Phase **4** presentation quality.

## 2026-04-28 — Phase 2.5: city actions in LegalActions + rule-based AI

Decision:
**`FoundCity`** and **`SetCityProduction`** are enumerated in **`LegalActions.for_current_player`** (legality-only; deterministic order after **`MoveUnit`** entries), and **`RuleBasedAIPlayer.decide`** selects them before the existing one-**`move_unit`**-per-segment / **`end_turn`** policy when the scenario calls for it.

Rationale:
The rule-based AI can drive the core **found → set production → move → end** loop using existing action schemas and **`GameState.try_apply`** only, without new types or engine-event “actions.”

Caveat:
Policy stays deterministic and shallow (no scoring, planning, or LLM). **`LegalActions`** lists every validator-legal city action; it does not encode “only one city” or other strategic cuts.

## 2026-04-27 — Initial Engine Direction

Decision:
Use Godot as the initial prototyping engine.

Rationale:
- permissive MIT license
- good fit for 2D/strategy prototyping
- low licensing risk
- fast iteration
- no revenue share/runtime fee

Caveat:
The architecture must not make core rules inseparable from Godot scenes.

## 2026-04-27 — AI Direction

Decision:
Start with deterministic rule-based AI.

Rationale:
- debuggable
- testable
- works offline
- creates legal-action interface needed for future LLM AI

Caveat:
LLM adapters may be explored later, but must choose from generated legal actions.

## 2026-04-27 — Cloud Direction

Decision:
Design for asynchronous play-by-cloud, but do not build official hosting first.

Rationale:
- async turns fit 4X gameplay
- avoids early operational burden
- enables Bring Your Own Server / Private Cloud

Caveat:
Server-authoritative architecture must be preserved for future cloud mode.

## 2026-04-27 — Scripting language for Godot (Phase 1.x)

Decision:
Phase 1.x uses Godot 4.x with GDScript as the default scripting language; C# is deferred to avoid introducing a .NET dependency during early prototyping.

Rationale:
- GDScript ships with Godot; no separate .NET SDK or Mono build required on the machine or in the repo for contributors to open and run the project.

Caveat:
C# may be reconsidered later only with an explicit steering decision to accept the .NET dependency.

## 2026-04-27 — Axial hex coordinates (Phase 1.1)

Decision:
Phase 1.1 uses axial (q, r) hex coordinates in the domain layer; cube conversion is deferred; distance-style helpers are deferred until a later phase needs them.

Rationale:
- Minimal representation, simple neighbor lookup, orientation-neutral at the domain layer, and compatible with later cube math for distance, line, and range.

Caveat:
Later phases may add `to_cube()`, `distance()`, or range helpers when movement or other rules need them; the steering documents should be updated when that happens.

## 2026-04-27 — Domain map model (Phase 1.2)

Decision:
Phase 1.2 introduces **`HexMap`**: a finite set of cells stored as `Dictionary[Vector2i -> int]`, with **public queries taking `HexCoord`**. `Terrain` is a minimal inline enum (`PLAINS`, `WATER`) with no gameplay effects in 1.2. A single canonical 7-hex test map is provided by the static `HexMap.make_tiny_test_map()`.

Rationale:
- `Vector2i` keys are value-based and work correctly with `has()`; `HexCoord` remains the domain identity at the API.
- Two terrain values are enough to exercise `terrain_at` without pre-committing to a full 4X terrain taxonomy.
- One factory method keeps the fixture consistent for later rendering and rules phases.

Caveat:
Later phases will likely introduce a `Cell` or richer `Terrain` model (costs, ownership, etc.); that will require an explicit steering update before implementation.

## 2026-04-27 — HexMap.read_coords (Phase 1.2 follow-up for Phase 1.3)

Decision:
`HexMap` adds **`coords()`** — a read-only list of all occupied cells as `HexCoord` instances, without exposing the internal `Vector2i` dictionary keys. **Iteration order is unspecified** in Phase 1.2.

Rationale:
Presentation (e.g. rendering) must **derive** what to draw from domain state, not hand-duplicate a coordinate list. `coords()` gives a single source of truth for “which cells exist” without mutating the map or returning raw storage types.

Caveat:
If a future system needs a stable order (e.g. deterministic serialisation), the steering documents and API must be updated to specify it.

## 2026-04-27 — Map rendering (Phase 1.3)

Decision:
**Phase 1.3** draws the **tiny test** `HexMap` using a single **`MapView` (`Node2D`)** and **`_draw()`**. A pure static helper **`MapView.compute_draw_items(map, layout)`** turns domain state into polygon colors and corner lists. `compute_draw_items` iterates **`map.coords()`** and **`terrain_at(coord)`**; it does **not** use a hand-duplicated coordinate list. **[HexLayout](../game/presentation/hex_layout.gd)** encodes pointy-top axial-to-world layout with `SIZE` 32. Placeholder terrain colors and scope are documented in [RENDERING.md](RENDERING.md).

Rationale:
One `Node2D` plus `_draw()` is minimal; derived drawing from `coords()` matches the “rendering reflects domain” rule. Pointy-top layout is a common default; the domain remains orientation-neutral in [HEX_COORDINATES.md](docs/HEX_COORDINATES.md).

Caveat:
**Orientation, tile size, palette, camera, input, and TileMap** are **not** locked for production; a future phase or steering pass may revise them.

## 2026-04-27 — Unit domain and Scenario (Phase 1.4)

Decision:
**Phase 1.4** introduces an immutable **`Unit`** and **`Scenario`** in `game/domain/`: a `Unit` is `(id, owner_id, position)` as `RefCounted` data; a **`Scenario`** holds a `HexMap` and a fixed list of units, validated at construction (positions on the map, unique unit ids), with read-only query APIs and **`make_tiny_test_scenario()`** as the canonical three-unit, two-owner fixture on PLAINS only, with `(-1,0)` WATER unoccupied.

Rationale:
**Smallest viable** representation: integers for **unit and owner ids** without a `Player` class; a single **`Scenario`** bundle unblocks **Phase 1.5** and later rules without entangling `Node` or global state.

Caveat:
**Rendering, selection, movement, actions, a `Player` type, owner palette, and stacking / ZoC rules** remain **deferred**; this phase does not define gameplay loops or presentation.

## 2026-04-28 — Unit markers in presentation (Phase 1.4b)

Decision:
**Phase 1.4b** introduces **`UnitsView`**, a separate **`Node2D`** **sibling** of **`MapView`**, both parented by **`Main`** in [main.tscn](../game/main.tscn) with [main.gd](../game/main.gd) as the only wiring: **`Main` owns a single `Scenario` instance and a single `HexLayout`**, passing **`scenario.map`** and **`layout`** to **`MapView`**, and **`scenario`** and **`layout`** to **`UnitsView`**. **`UnitsView` derives** marker positions, count, and placeholder **owner** colors from **`Scenario.units()`** only (via static **`compute_marker_items`**); markers are **simple drawn circles** with a thin outline.

Rationale:
Keeps **terrain** and **units** as two presentation concerns; one **`Scenario` + one `HexLayout`** prevent map/units/geometry from drifting. Derived drawing matches the “rendering reflects state, not owns it” rule from [ARCHITECTURE_PRINCIPLES.md](ARCHITECTURE_PRINCIPLES.md).

Caveat:
**Selection, movement, input, animation, sprites, the warrior asset, text labels, health bars, a final owner palette, and gameplay rules** remain **deferred**; 1.4b is read-only display only.

## 2026-04-28 — Selection and legal destinations (Phase 1.5)

Decision:
**Phase 1.5** adds **`MovementRules.legal_destinations(scenario, unit_id)`** in [game/domain/movement_rules.gd](../game/domain/movement_rules.gd) (neighbor-only, on-map, **not WATER**, **not occupied**). Presentation adds **`SelectionState`** ( **`RefCounted`**, `unit_id` only), **`SelectionController`** (**`_unhandled_input`**, hit-test markers, **no `UnitsView` reference**), and **`SelectionView`** ( **`compute_overlay_items`** + **`_draw`** ring via **`PackedVector2Array`** closed polyline, destination fills). **`Main`** wires one **`Scenario`**, **`HexLayout`**, and **`SelectionState`** to views. **`HexMap` / `Terrain`** stay tag-only; WATER-as-impassable is documented in [MOVEMENT_RULES.md](MOVEMENT_RULES.md).

Rationale:
Keeps **rules** in a small static domain API; keeps **selection** as **non-authoritative** client state; overlays **derive** from domain + selection so highlights are never truth.

Caveat:
**Actual movement**, **`MoveUnit`**, **validators**, **action log**, **turn ownership**, **AI**, **save/load**, and **final UX** for selection remain **deferred**.

## 2026-04-28 — MoveUnit, GameState, ActionLog (Phase 1.6)

Decision:
**Phase 1.6** adds **`MoveUnit`** ([game/domain/actions/move_unit.gd](../game/domain/actions/move_unit.gd)) as a versioned **`Dictionary`** schema, **`GameState.try_apply`** ([game_state.gd](../game/domain/game_state.gd)) as the sole local mutation entry point, and **`ActionLog`** ([action_log.gd](../game/domain/action_log.gd)) with **deep-duplicated** stored and returned entries. **`MoveUnit.apply`** returns a **new `Scenario`** with a **replaced `Unit`**, preserving the **`HexMap`** reference. **`MovementRules.legal_destinations`** remains the legality oracle inside **`MoveUnit.validate`**. **[SelectionController](../game/presentation/selection_controller.gd)** submits moves only via **`try_apply`**; **destination** hit-test precedes **unit-marker** hit-test; on accept it re-points **`units_view`** / **`selection_view`** and **clears** selection.

Rationale:
Matches [ARCHITECTURE_PRINCIPLES.md](ARCHITECTURE_PRINCIPLES.md) action pipeline; keeps **`Unit`/`Scenario`** immutable per instance; **`try_apply`** is the future cloud-shaped boundary.

Caveat:
**Turn order**, **AI**, **persistence**, **structured rejection log**, **replay UI**, and **movement animation** remain **deferred**.

## 2026-04-28 — TurnState, EndTurn, current-player gate (Phase 1.7)

Decision:
**Phase 1.7** adds immutable **`TurnState`** ([turn_state.gd](../game/domain/turn_state.gd)) with **`advance()`**, **`EndTurn`** ([end_turn.gd](../game/domain/actions/end_turn.gd)) as a versioned **Dictionary**, and **`GameState.turn_state`** updated only through **`try_apply`**. A **common gate** in **`GameState.try_apply`** enforces **`actor_id`** presence/type and **`actor_id == current_player_id()`** for both **`move_unit`** and **`end_turn`**. **`EndTurn.validate`** is **structural only**; **`not_current_player`** is **not** a **`EndTurn.validate`** reason. Accepted **`end_turn`** log entries include **`turn_number_before`** and **`next_player_id`**. Presentation adds **`TurnLabel`** and **`EndTurnController`** ( **Space** ); **`SelectionController`** refreshes the label after accepted moves. Selection may still target any unit; illegal-owner moves are rejected at **`try_apply`**.

Rationale:
Keeps turn truth in the domain next to **`Scenario`**; one gate avoids duplicating “whose turn” checks in every action validator; **`EndTurn`** stays easy to serialize like **`MoveUnit`**.

Caveat:
**Phased turns** (movement vs production), **AI end-turn**, **restricting selection to current player**, and **online turn order** remain **deferred**.

## 2026-04-28 — Legal actions + rule-based AI (Phase 1.8)

Decision:
**Phase 1.8** adds **`LegalActions.for_current_player`** ([legal_actions.gd](../game/domain/legal_actions.gd)) — deterministic **`MoveUnit`** enumeration from **`MovementRules`** plus trailing **`EndTurn`** — **`RuleBasedAIPlayer.decide`** ([rule_based_ai_player.gd](../game/ai/rule_based_ai_player.gd)) under **`game/ai/`**, and **`AITurnController`** ([ai_turn_controller.gd](../game/presentation/ai_turn_controller.gd)) on **`KEY_A`**. AI submission is only via **`GameState.try_apply`**; **`decide`** returns **`{}`** defensively on empty or unrecognized **`legal_actions`**. One key press applies at most one action; no **`_process`** automation. Topic doc: [AI_LAYER.md](AI_LAYER.md).

Rationale:
Matches [ARCHITECTURE_PRINCIPLES.md](ARCHITECTURE_PRINCIPLES.md): legal generation stays domain-shaped; AI choice stays in an **`ai/`** module; Godot input stays in presentation. **`try_apply`** remains the single mutation gate for cloud-shaped futures.

Caveat:
**Multi-action plans**, **LLM adapters**, **planner AI**, **auto-run to end of turn**, and **AI identity per seat** remain **deferred**.

## 2026-04-28 — ActionLog-derived one-move-per-turn AI policy (Phase 1.8b)

Decision:
**Phase 1.8b** adds **`RuleBasedAIPolicy.has_actor_moved_this_turn(action_log, actor_id)`** ([rule_based_ai_policy.gd](../game/ai/rule_based_ai_policy.gd)): **newest-first** scan of **`ActionLog`**; first **`end_turn`** ⇒ “not moved this segment”; first matching **`move_unit`** ⇒ “moved”. **`RuleBasedAIPlayer.decide`** consults this helper and returns **`EndTurn`** when the current player already moved, else keeps the Phase 1.8 move preference. **`LegalActions`**, **`GameState`**, schemas, and **`AITurnController`** are unchanged.

Rationale:
Avoids infinite **`MoveUnit`** chains on the tiny map without movement points, without **`LegalActions` lying about legality**, without schema bumps, and without hidden mutable AI state — **pure derive-from-log** stays replay-shaped.

Caveat:
**Flexible budgets** (N moves per turn), **phase sub-steps**, and **AI that differs from human caps** remain **deferred** until explicitly steered.

## 2026-04-28 — ActionLog debug surfacing (Phase 1.9)

Decision:
**Phase 1.9** adds **`LogView`** ([log_view.gd](../game/presentation/log_view.gd)) — **`extends Label`**, **`MAX_ENTRIES` = 10**, **`compute_text`** / **`format_entry`** static helpers, **tail-only** display (**newest at bottom**). It reads **`game_state.log`** only via **`size()`** and **`get_entry(i)`**; **no** **`ActionLog`** API changes and **no** mutation of **`GameState`** or entries. **`main.gd`** wires **`LogView`** and passes it to **`SelectionController`**, **`EndTurnController`**, and **`AITurnController`**, each calling **`if log_view != null: log_view.refresh()`** after **accepted** **`MoveUnit`**, **`EndTurn`**, or AI steps — **explicit refresh**, **no** polling, **no** replay/undo.

Rationale:
Makes the **append-only** log visible in the prototype while keeping the action pipeline and log semantics identical; optional **`log_view`** on controllers avoids tight coupling for headless or alternate scenes.

Caveat:
**Structured export**, **filter/search**, **rich replay UI**, and **rejected-action logging** remain **deferred**.

## 2026-04-28 — Long-term phase roadmap clarified (Phases 1–7)

Decision:
The forward roadmap in [PHASE_PLAN.md](PHASE_PLAN.md) is restructured into **Phases 2–7** (**core 4X loop**, **game content foundation** with **3.0–3.5**, **visual identity / presentation** with **4.0–4.5**, **strategic dynamics**, **Empire of Minds worldbuilding and identity**, **balance / content iteration**). Prior **cloud** milestones (**Async Cloud**, **Private Cloud / Self-Host**, **Server Manager**) are preserved verbatim in a **Deferred — Cloud / Self-Host roadmap** appendix and **[CLOUD_PLAY.md](CLOUD_PLAY.md)** remains canonical cloud steering — decoupled from gameplay numbering so **Phases 2–7** can be refined without renumbering infrastructure.

Rationale:
Separates **core systems**, **content model**, **visual presentation**, **world identity**, and **balance iteration** to limit **scope bleed** and keep each phase narrow enough to validate per [IMPLEMENTATION_GUIDE.md](IMPLEMENTATION_GUIDE.md).

Caveat:
**Phases 2–7** are **roadmap-level**; **Must not** and **Validation** will be refined as **Phase 2** progresses. **Placeholder** rendering may continue in **Phase 2.x / 3.x**; **full visual identity** belongs to **Phase 4**.

## 2026-04-28 — City domain + CitiesView (Phase 2.1)

Decision:
**Phase 2.1** adds **`City`** ([city.gd](../game/domain/city.gd)), extends **`Scenario`** ([scenario.gd](../game/domain/scenario.gd)) with **`cities()`**, **`city_by_id`**, **`cities_at`**, **`cities_owned_by`**, and **replay-safe** **`peek_next_unit_id()` / `peek_next_city_id()`** with **`Scenario.new(map, units)`** backward compatibility and **auto** counters from listed entities when not explicit. **`CitiesView`** ([cities_view.gd](../game/presentation/cities_view.gd)) provides **`compute_marker_items`** placeholder diamonds; [main.tscn](../game/main.tscn) draw order is **MapView → CitiesView → SelectionView → UnitsView**. **No** new actions, **no** **`GameState.try_apply`** changes; **`make_tiny_test_scenario()`** stays city-free.

Rationale:
Establishes cities in the **immutable domain bundle** before **FoundCity**; counters default safely for **two-arg** **`Scenario.new`** while allowing explicit pass-forward for future consumption/removal. Presentation stays **derived-only**.

Caveat:
**`main.gd`** does not re-point **`CitiesView`** after moves; acceptable while the canonical loop has **zero** cities.

## 2026-04-28 — Scenario pass-forward hardening (Phase 2.2a)

Decision:
**`MoveUnit.apply`** now returns **`Scenario.new(map, new_units, cities, peek_next_unit_id, peek_next_city_id)`** read from the input **`Scenario`**, so **cities** and **replay-safe counters** are not dropped on move.

Rationale:
Prevents silent loss of city state and **id** monotonicity before **`FoundCity`** and production; **`apply`** still replaces only the moved **`Unit`** and allocates **no** new ids inside **`apply`**.

Caveat:
Every **future** domain path that constructs a **`Scenario`** from a prior snapshot must **explicitly** pass **`cities`** and **`peek_*`** values (or deliberately document a reset); see [CITIES.md](CITIES.md).

## 2026-04-28 — FoundCity action (Phase 2.2b)

Decision:
**Phase 2.2b** introduces **`FoundCity`** ([found_city.gd](../game/domain/actions/found_city.gd)) as a **versioned** **`Dictionary`** action dispatched only through **`GameState.try_apply`**: structural **`validate`**, **`apply`** returns a **new** **`Scenario`** with the **founding unit removed**, a **new** **`City`** at that **hex** using **`city_id = peek_next_city_id()`**, **`peek_next_city_id()`** advanced by **1**, and **`map` / other units / existing cities / `peek_next_unit_id()`** preserved. **`created_city_id`** is read **before** **`apply`** for **deterministic** **`ActionLog`** entries. **`SelectionController`** uses **`KEY_F`** when a **unit** is **selected**; **`LogView`** formats **`found_city`** lines.

Rationale:
Establishes the **first city-creation** path through the same **validate → apply → log → refresh** pipeline as **`move_unit`** / **`end_turn`**, with **monotonic** **city ids** and **no** hidden **`Scenario`** mutation.

Caveat:
**Any-unit founding** is **temporary**; **`LegalActions`** and **AI** **do not** emit **`found_city`** yet (**Phase 2.6**). **Production**, **economy**, and **settler** eligibility belong in **later** phases (**Phase 3.1** unit definitions).

## 2026-04-28 — SetCityProduction + `City.current_project` (Phase 2.3)

Decision:
**Phase 2.3** adds **`current_project`** on **`City`** (**`null`** or **`Dictionary`**, stored via **`duplicate(true)`** in **`City._init`** when a **`Dictionary`** is supplied) and **`SetCityProduction`** ([set_city_production.gd](../game/domain/actions/set_city_production.gd)) routed through **`GameState.try_apply`**. **`apply`** replaces only the target **`City`** in a **new** **`Scenario`**; **`map`**, **units**, **non-target** cities, and **`peek_next_*`** are **preserved**. **`project_type`** **`"produce_unit"`** installs **`progress: 0`**, **`cost: 2`**; **`"none"`** clears. **`LogView`** formats **`set_city_production`**. **`SelectionController`** **`KEY_P`** submits **`produce_unit`** for the **lowest-id** eligible **current-player** **city** (debug only).

Rationale:
Establishes **city build state** in the **immutable** domain bundle with the same **validate → apply → log** pipeline; defers **tick** / **`ProduceUnit`** so Phase 2.3 remains **state-only**.

Caveat:
**`LegalActions` / AI** do **not** enumerate **`set_city_production`**. **Production progress on** **`end_turn`** is **Phase 2.4a**; **completion** / **`ProduceUnit`** is **Phase 2.4b**.

## 2026-04-28 — Production progress tick on EndTurn (Phase 2.4a)

Decision:
**Phase 2.4a** adds **`ProductionTick.apply_for_player`** ([production_tick.gd](../game/domain/production_tick.gd)), invoked **only** from **`GameState.try_apply`** on **accepted** **`end_turn`**, **after** **`EndTurn.validate`** and **before** **`TurnState.advance`**. **Ending-player** cities with **`current_project != null`** gain **`progress` += 1**; events logged as **`production_progress`** ( **`source`: `"engine"`** ) in **ascending `city.id` order**, **then** the **`end_turn`** entry. **`progress`** may **exceed** **`cost`**; **no** unit spawn, **no** project clear, **no** counter allocation. **`LogView`** formats **`production`** lines.

Rationale:
Keeps **player** **`action_type`** surface unchanged while making **production** **observable** and **replay-ordered**; defers **completion** / **`ProduceUnit`** to **2.4b**.

Caveat:
**`production_progress`** must **not** become a **`try_apply`** action or **`LegalActions`** entry.

## 2026-04-28 — Production completion on EndTurn (Phase 2.4b)

Decision:
**Phase 2.4b** extends **`ProductionTick.apply_for_player`** ([production_tick.gd](../game/domain/production_tick.gd)) so that when **`progress_after` >= `cost`** and **`project_type`** is **`produce_unit`**, the engine emits **`unit_produced`** immediately after that city’s **`production_progress`**, appends **one** **`Unit`** at **`city.position`**, sets **`current_project`** to **`null`**, increments **`peek_next_unit_id()`** by the number of completions, and leaves **`peek_next_city_id()`** unchanged. **No** overflow carry. **`unit_produced`** is **not** a player action; **`LogView`** formats **`unit_produced`** lines.

Rationale:
Completes the minimal **produce_unit** loop while keeping **`try_apply`** and **`LegalActions`** surfaces unchanged.

Caveat:
**No** production queues or **`ProduceUnit`** **player** action; stacking remains **unlimited** on a hex for this phase.

## 2026-04-28 — Pending production delivery (Phase 2.4c)

Decision:
**Phase 2.4c** splits **completion** from **delivery**: **`ProductionTick`** only increments **`progress`** and sets **`ready: true`** when **`produce_unit`** reaches **`cost`**; **`ProductionDelivery.deliver_pending_for_player`** ([production_delivery.gd](../game/domain/production_delivery.gd)) runs in **`GameState.try_apply`** **after** **`turn_state` advances** and **after** the **`end_turn`** log entry, spawning **Units** and appending **`unit_produced`** for the **incoming** **`current_player_id`**. **`GameState._init`** runs the same delivery for the **opening** current player when the **`Scenario`** already contains **`ready`** projects. There is **no** separate **StartTurn** action.

Rationale:
Prevents the **opponent** from interacting with **newly completed** production **before** the **owner**’s **next** turn.

Caveat:
**Replay** / tools that assumed **`unit_produced`** immediately after **`production_progress`** must update to **post-`end_turn`** ordering.

## 2026-04-29 — Unit definitions and founding gate (Phase 3.1)

Decision:

- **`UnitDefinitions`** registry **`settler`** / **`warrior`**; lookup via **`get_definition(id)`** (**`get`** is not a valid **GDScript** method name on **`RefCounted`** — see **`unit_definitions.gd`** comment and [DECISION_LOG.md](DECISION_LOG.md)).
- **`Unit.type_id`** added (**default** **`"warrior"`** for backward compatibility).
- **`FoundCity`** requires **`UnitDefinitions.can_found_city(type_id)`**; **`unit_type_cannot_found`** when the type cannot found (unknown **`type_id`** included).
- **`ProductionDelivery`** spawns produced units with **`type_id`** **`"warrior"`** until **Phase 3.3** city **project** definitions; **`unit_produced`** event shape unchanged.

Rationale:

- Smallest **useful** content step aligned with [CONTENT_MODEL.md](CONTENT_MODEL.md).
- **Canonical scenario** seeds **one settler per player** so the **Phase 2** loop shape and **`RuleBasedAIPlayer`** need **no** code change.
- **Project → unit type** mapping stays deferred to **3.3**.

Caveat:

- **No** combat stats, **no** movement rules by type, **no** visual differentiation by **`type_id`** yet.
- **GDScript / Godot 4:** registry **lookup** is **`UnitDefinitions.get_definition(id)`**, not **`get`**, because **`static func get`** on **`RefCounted`** is rejected (signature clash with **`Object.get`**).

## 2026-04-29 — Terrain rule definitions (Phase 3.2)

Decision:

- **`TerrainRuleDefinitions`** registry **[`plains` / `water`](../game/domain/content/terrain_rule_definitions.gd)** with **`passable`**, **`movement_cost`** ( **`999`** for **water** — data only; range still one hex), **`get_definition`**, **`terrain_id_for_hex_map_value`**, **`is_passable_hex_map_value`**.
- **`MovementRules.legal_destinations`** consults **`TerrainRuleDefinitions`** for passability; **`HexMap.Terrain`** enum remains map storage.
- Unknown **`HexMap.Terrain`** values map to **`TERRAIN_ID_UNKNOWN`** (empty string) and are **impassable**.
- **`FoundCity.validate`** still checks **`HexMap.Terrain.WATER`** for **`tile_is_water`**; consolidating with the registry is **deferred**.

Rationale:

- Adds the **[CONTENT_MODEL.md](CONTENT_MODEL.md)** terrain seam **without** storage migration, pathfinding, or loop-shape changes.

Caveat:

- **`movement_cost`** does not affect **`legal_destinations`** yet.
- **`get_definition`** naming follows the Phase **3.1** / **`Object.get`** caveat.
- Two terrain checks (**movement** vs **founding**) until a later consolidation phase.

## 2026-04-29 — City project definitions (Phase 3.3)

Decision:

- **`CityProjectDefinitions`** registry with first project **`produce_unit:warrior`** ( **`game/domain/content/city_project_definitions.gd`** ).
- **`SetCityProduction`** **`schema_version`** **`2`**: action carries **`project_id`** only (**no** **`project_type`** field, **no** **`schema_version` `1`** compatibility in validation).
- **`City.current_project`** carries **`project_id`** when set via **`apply`**; **`cost`** comes from the registry; **`project_type`** **`produce_unit`** remains on **`current_project`** for engine logic.
- **`ProductionTick`** may append optional **`project_id`** on **`production_progress`** when the source project had it; **`LogView`** may ignore it.
- **`ProductionDelivery`** uses **`CityProjectDefinitions.produces_unit_type(project_id)`** for spawned **`Unit.type_id`**, with **`"warrior"`** fallback for missing / unknown **`project_id`** (legacy fixtures only).

Rationale:

- Removes “hardcoded warrior production” as an action **shape** concern without opening **`produce_unit:settler`** or city-spam pressure in the same slice.

Caveat:

- **`produce_unit:settler`** and additional project rows are **deferred**.
- **`unit_produced`** still carries **no** **`unit_type_id`** / **`project_id`** (additive event churn deferred).
- Legacy **`current_project`** without **`project_id`** is supported only as transitional safety for in-flight **`Dictionary`** state in **tests and hand-built fixtures** (there is **no** save/load path yet).

## 2026-04-29 — Progression model checkpoint (Phase 3.4a)

Decision:

- Add **[PROGRESSION_MODEL.md](PROGRESSION_MODEL.md)** as the **systematic model** for future **sciences**, **breakthroughs**, **unlock targets**, **modifiers/effects/conditions**, and **detection** vocabulary — **documentation-only**.
- **Phase 3.4a** does **not** change **CONTENT_MODEL.md** (general contract) or canonicalize workbook / **CONTENT_BACKLOG** lists; those remain **design raw material**.
- **Deterministic-first** rule for any **replay-critical** progression; **LLM** roles limited to **non-authoritative** advisory / tooling unless explicitly steered otherwise later.

Rationale:

- Aligns constrained implementers and design notes **before** **3.4b+** code (registries, gating, detectors).

Caveat:

- **`ScienceDefinitions`**, breakthrough **registries**, and **LegalActions** / **`GameState`** unlock wiring remain **future** subphases; **no** gameplay or schema change in **3.4a**.

## 2026-04-29 — ProgressDefinitions seed (Phase 3.4b)

Decision:

- Add **`ProgressDefinitions`** in **[progress_definitions.gd](../game/domain/content/progress_definitions.gd)** — **five** ancient/foundations seed rows (**`foraging_systems`**, **`stone_tools`**, **`controlled_fire`**, **`oral_surveying`**, **`animal_tracking`**), all **`category`** **`science`**, **`era_bucket`** **`ancient_foundations`**.
- **Metadata-only**: **`concrete_unlocks`**, **`systemic_effects`**, **`future_dependencies`** as typed target rows; **no** enforcement, **no** preloads of other registries, **no** **`target_id`** validation against existing content.

Rationale:

- Validates **[PROGRESSION_MODEL.md](PROGRESSION_MODEL.md)** shape **before** unlock enforcement.
- One **forward-compatible** registry name (`ProgressDefinitions`) rather than several narrow registries too early.

Caveat:

- **`target_id`** values may reference **future** registries and systems — **not** enforced in **3.4b**.
- **No** gating, **no** breakthrough detectors, **no** **`LegalActions`** / **`GameState`** consumption yet.

## 2026-04-29 — Unlock state and deterministic gating (Phase 3.4c)

Decision:

- **`ProgressState`** lives on **`GameState`**, **not** **`Scenario`** — **player-specific** unlock targets (**`target_type`** + **`target_id`**) as immutable **`RefCounted`** snapshots.
- **Default seed:** every **initial** **`TurnState.players`** id gets **`city_project` / `produce_unit:warrior`** unlocked when **`GameState`** is constructed without an explicit **`ProgressState`**.
- **`SetCityProduction`**: **`GameState.try_apply`** enforces unlock **after** **`SetCityProduction.validate`** succeeds — rejection reason **`project_not_unlocked`** (**not** a **`validate`** reason). **`PROJECT_ID_NONE`** is **never** gated.
- **`LegalActions`** mirrors the gate for enumerated **`SetCityProduction`** (**`PROJECT_ID_PRODUCE_UNIT_WARRIOR`**); **`progress_state == null`** remains **ungated** for **synthetic** test shells.

Rationale:

- **Deterministic** core enforcement **without** changing action **schemas** or **`SetCityProduction`** **`validate`/`apply`** signatures.
- Keeps **`Scenario`** focused on **world / entity** state; unlock metadata stays **session-local**.

Caveat:

- **No** progress **accumulation** in **`GameState`**; **`LegalActions`** does **not** read **`ProgressDefinitions`**; **`SetCityProduction.validate`** does **not**; **`complete_progress`** (**Phase 3.4e**) is the **first** **`try_apply`** path that applies **`ProgressDefinitions`** via **`ProgressUnlockResolver`**; **no** breakthrough **detectors**; **no** **save/load** of **`ProgressState`** yet.

## 2026-04-29 — Apply progress-definition unlocks (Phase 3.4d)

Decision:

- Add **`ProgressUnlockResolver`** ([progress_unlock_resolver.gd](../game/domain/progress_unlock_resolver.gd)) — **`complete_progress`**, **`Dictionary`** result (**`ok`**, **`reason`**, **`progress_state`**, **`unlocked_targets`**); preloads **`ProgressDefinitions`** only here.
- Extend **`ProgressState`** with **`completed_progress_ids`** per owner (sorted, deduped); **no** content-registry preload on **`ProgressState`**.
- Resolver applies only **`concrete_unlocks`** and **`systemic_effects`**; **`future_dependencies`** stay **metadata-only** (not copied into **`unlocked_targets`**).
- **No** **`GameState`**, action, or **`LegalActions`** integration in this subphase.

Rationale:

- Keeps **`ProgressState`** generic; centralizes the **`ProgressDefinitions`** dependency in one helper.
- Deterministic, testable bridge with **no** gameplay loop change.

Caveat:

- **No** detectors; **no** progress **accumulation** tied to play; **no** **`future_dependencies`** semantics yet; **no** UI / save / replay wiring for **`completed_progress_ids`**.

## 2026-04-29 — Manual CompleteProgress action (Phase 3.4e)

Decision:

- Add player-submitted **`complete_progress`** ([complete_progress.gd](../game/domain/actions/complete_progress.gd)), **`schema_version: 1`**, wired in **`GameState.try_apply`** after the **common** current-player gate.
- **`CompleteProgress.validate`**: **`progress_state_null`** → **`wrong_action_type`** → **`unsupported_schema_version`** → **`malformed_action`** (**`actor_id`**, non-empty **`progress_id`**) → **`unknown_progress_id`** → **`progress_already_completed`** — **no** **`current_player`** check (owned by **`GameState`**).
- On accept: **`ProgressUnlockResolver.complete_progress`**, replace **`progress_state`**, append **`ActionLog`** entry with **`unlocked_targets`** delta; **`ActionLog`** deep-copies.
- **`complete_progress`** is **not** enumerated by **`LegalActions`** and **not** used by **AI**; **no** input-controller binding in this subphase.
- **`LogView`** formats **`complete_progress`** as **`[+N unlocks]`**.

Rationale:

- **Deterministic**, **replayable** bridge from “progress completed” to **`ProgressState`** unlocks.
- Supports future **debug/UI/detectors** without implementing detectors now.

Caveat:

- **No** detectors; **no** progress **accumulation**; **no** **UI** / **AI** use; the **five** seed **`ProgressDefinitions`** rows do **not** unlock **`city_project`** targets, so **`SetCityProduction`** legality is **unchanged** for normal play; **`future_dependencies`** remain **metadata-only**.

## 2026-04-30 — Manual progress debug input (Phase 3.4f)

Decision:

- **`KEY_G`** in **`SelectionController`** submits **`CompleteProgress`** with **hardcoded** **`progress_id`** **`foraging_systems`** for the **current player**; **`turn_label`** / **`log_view`** refresh on **accept**; **no** **`scenario`** re-point or view redraws.

Rationale:

- Simplest **F5 / manual** path to exercise the **progression** chain end-to-end without touching **`LegalActions`** or **AI**.

Caveat:

- **One-shot** per player for that **`progress_id`** (**`progress_already_completed`** on repeat) until cycling / UI / detectors exist.

## 2026-04-30 — First deterministic progress detector (Phase 3.4g)

Decision:

- Introduce **`ProgressDetector`** ([progress_detector.gd](../game/domain/progress_detector.gd)) — **candidate-only**: **`suggested_complete_progress_actions(game_state)`** returns **`CompleteProgress`** action **`Dictionary`** values; **first rule** is accepted **`found_city`** ⇒ **`controlled_fire`** when not already completed. **No** **`try_apply`**, **no** mutation of **`progress_state`** or **`log`**, **no** **`LegalActions`** / **AI** integration.

Rationale:

- Establishes a **deterministic**, **log-grounded** detector path with **no** hidden gameplay until a future subphase defines **apply** policy and ordering.

Caveat:

- **One** rule in **one** aggregator file; **not** consumed by runtime yet; future detectors may need split modules or richer event models.

## 2026-04-30 — Manual detector candidate consumption (Phase 3.4h)

Decision:

- **`ProgressCandidateFilter.for_current_player`** ([progress_candidate_filter.gd](../game/domain/progress_candidate_filter.gd)) keeps only detector candidates whose **`actor_id`** equals **`turn_state.current_player_id()`**; **does not** call **`CompleteProgress.validate`** — **`GameState.try_apply`** remains authoritative.
- **`SelectionController`**: **`KEY_H`** applies the **first** filtered candidate via **`try_apply`**; **no** **`scenario`** / view churn; **`turn_label`** / **`log_view`** refresh on **accept**; **no** **`LegalActions`** / **AI**; **no** auto-apply loop.

Rationale:

- Respects the **current-player** gate for **`complete_progress`** while still exercising **3.4g** detector output from the editor; smallest manual bridge before any start-of-turn / after-action policy.

Caveat:

- **First** candidate only; non-current players must take their turn (or use future policy) before their detector row applies via this path; **`ProgressDetector`** remains unchanged.

## 2026-05-01 — Faction / custom-civ identity model (Phase 3.5a)

Decision:

- Add **[FACTION_IDENTITY.md](FACTION_IDENTITY.md)** as the **docs-only** identity checkpoint for **predefined civilisations** and **custom civilisations**.
- **Predefined civilisations** are **curated presets** of the **same trait system** **custom civilisations** use.
- **Trait budget** is **normally shared**; **curated prototypes** may **temporarily violate** budget only with **explicit `notes`** in the profile.
- **Prototype / generated art** is **allowed for internal testing**; policy is documented in **`FACTION_IDENTITY.md`**.
- **`ART_DIRECTION.md`** is **deferred** until actual asset work begins.

Rationale:

- Locks **identity vocabulary** before faction registries, trait math, UI, or asset pipeline.
- Supports **fast curated playtesting** and long-term **custom-civ** replay value.
- Keeps **playful examples** useful as **test vectors** without making them canon.

Caveat:

- **No** trait costs, **no** gameplay wiring, **no** AI / `LegalActions` / `GameState` changes.
- **Prototype factions** and **toy examples** are **not final canon**.
- **Generated-art** language is **internal-prototype guidance**, not a final commercial-release policy.

## 2026-05-01 — Debug FactionDefinitions seed (Phase 3.5b)

Decision:

- Create **`faction_definitions.gd`** rather than **`civilization_definitions.gd`**.
- Include **exactly three** non-canonical debug rows.
- Use **ASCII** ids and **Swedish-character** display names.
- Keep **`profile_type`** and **`canon_status`** as **separate** fields.
- Store **`trait_ids`** as **forward references** only (**no** **`TraitDefinitions`** validation).
- **`visual_identity`** is **metadata only**; **no** asset paths.
- **No** gameplay wiring.

Rationale:

- Mirrors existing **content-registry** pattern (`RefCounted`, static accessors, deep copies).
- Provides **demo/playtest** profiles without making them canon.
- Tests whether the **trait-composition vocabulary** can express memorable identities.

Caveat:

- **No** **`TraitDefinitions`** registry exists.
- **No** player/faction assignment.
- **No** trait costs or balance math.
- **No** serious prototype factions are shipped in the registry yet.

## 2026-05-01 — Prototype faction-banner visual slice (Phase 3.5d)

Decision:

- Use **Phase 3.5d** rather than **Phase 4** for a **tiny banner-only** prototype slice.
- Add **exactly three** non-final prototype banners for the existing **debug** faction rows.
- Keep assets under **`game/assets/prototype/`**.
- Add **`FactionAssetPaths`** (**pure string** mapping) rather than an asset **registry** (no **JSON** / **`.tres`**).
- Add **F1** **`FactionBannerGallery`** debug overlay; **missing-image** fallback is **required**.
- **No** gameplay wiring or player assignment.

Rationale:

- Banners give **high identity value** for **low implementation cost**.
- They visualize **3.5b** data without locking **terrain** / **unit** / **HUD** style.
- Prototype assets can be **replaced** later.
- **F1** gallery is an **internal-testing** hook without a real HUD pass.

Caveat:

- **Not** final art.
- **Not** a Steam / release asset decision.
- **No** **`ART_DIRECTION.md`** yet.
- Generated / prototype images must remain **replaceable**.
- **Phase 4** and **Phase 6** still own broader visual direction and final identity.

## 2026-05-01 — Faction identity scope cleanup (Phase 3.5e)

Decision:

- **3.5a** **explicit non-goals** are **explicitly scoped** to **3.5a** (the original **docs-only** checkpoint) in **`FACTION_IDENTITY.md`**.
- **Later 3.5 subphases** may add **explicitly scoped** prototype assets, **debug** presentation, or registry slices without contradicting **3.5a**’s historical constraint.
- **3.5d** remains the intentional slice for **non-final** prototype **banners**, **F1** **`FactionBannerGallery`**, **replaceable** assets, and **no** gameplay dependence on pixels — **not** a **Phase 4** visual pass and **not** final art.

Rationale:

- Avoids a **documentation contradiction** after **3.5d** added prototype PNGs and **F1** overlay while an unscoped list still read like a global “no assets / no UI” rule.

Caveat:

- **No** new product feature: **documentation-only** change (**no** code, **no** tests, **no** assets in **3.5e**).
- **No** final art commitment; **no** **`ART_DIRECTION.md`**; **Phase 4** and **Phase 6** boundaries unchanged.

## 2026-05-01 — Visual direction checkpoint (Phase 4.0)

Decision:

- Add **`docs/VISUAL_DIRECTION.md`** as the **prototype visual direction** source of truth for **Phase 4.1–4.5**.
- **Phase 4.0** is **documentation-only**: **no** code, assets, tests, scenes, or UI implementation.
- **`RENDERING.md`** remains the **current implementation-state** doc; **`VISUAL_DIRECTION.md`** holds **intent** until subphases ship pixels.
- Adopt a **hybrid** direction: **stylised painterly / parchment-map** terrain language plus **strong icon overlays** for units, cities, and feedback — **not** photorealism or final-release polish.
- **F1 `FactionBannerGallery`** and similar surfaces stay **debug** unless a future phase explicitly promotes them.
- **Final** lore, aesthetics, naming, and **IP** review remain **Phase 6**; **no** Steam or commercial release asset policy in **4.0**.

Rationale:

- Enters **Phase 4** deliberately after **3.5** identity and prototype-banner work — coherent rules before terrain/unit/city/HUD/camera slices.
- Separates **direction doc** from **implementation doc** to reduce drift and scope creep.

Caveat:

- **Palette and contrast** in **`VISUAL_DIRECTION.md`** are **intent-only** until **4.1**; concrete RGB belongs in implementation + **`RENDERING.md` updates**, not premature locking in **4.0**.

## 2026-05-01 — Asset request workflow for prototype visuals

Decision:

- Future **Phase 4** visual work should **prefer** an **Asset Request Pack** workflow for **non-trivial** prototype art. The implementation agent may request a **minimal** asset set, but should **not** autonomously generate **painterly / illustrative** assets unless **explicitly allowed** by the phase prompt.

Rationale:

- Keeps visual production **reviewable**, **provenance-friendly**, and aligned with the **constrained-implementer** process. Reduces risk that prototype art **silently expands** phase scope or is **mistaken** for final / canonical art.

Consequences:

- **`VISUAL_DIRECTION.md`** owns the **asset request workflow** and **Asset Request Pack** checklist.
- **Trivial programmatic placeholders** remain allowed when **explicitly in scope**.
- **Non-trivial** terrain, unit, city, faction, HUD, or mockup assets should **normally** be **requested first**.
- **Implementation reports** must list **all** created / imported assets and provenance.

## 2026-05-01 — Terrain readability polish (Phase 4.1)

Decision:

- Refine **terrain** fills in **`MapView._terrain_to_color`** only: **PLAINS** `Color(0.74, 0.67, 0.52)`, **WATER** `Color(0.28, 0.46, 0.62)` for clearer **land vs water** and **parchment-map**-style land per **[VISUAL_DIRECTION.md](VISUAL_DIRECTION.md)**.
- **Programmatic** colours only — **no** textures, **no** Asset Request Pack, **no** **`HexMap`** or rules changes.

Rationale:

- **Phase 4.1** scope is **palette/readability** first; avoids asset pipeline while improving map coherence.

Caveat:

- Values are **prototype** documentation in **`RENDERING.md`**, not a final shipping palette; **Phase 6** and later art passes may replace them.

## 2026-05-01 — Unit marker readability (Phase 4.2)

Decision:

- **`UnitsView`** markers: stronger **owner** fills, **dark rim**, **`type_id`** first-letter **glyph** (`ThemeDB.fallback_font`), **white halo** when **`selection`** matches — **programmatic** only, **no** sprites or imports.
- **`main.gd`** wires **`units_view.selection`**; **`SelectionController`** calls **`units_view.queue_redraw()`** on selection change so the halo stays in sync (**presentation** only).

Rationale:

- Improves **owner / type / selected** read on **Phase 4.1** terrain without changing **Unit** or **`UnitDefinitions`**.

Caveat:

- Colours and **glyph** convention are **prototype**; multiple types may share a letter until **`type_id`** vocabulary grows.

## 2026-05-01 — Map display scale (Phase 4.2a)

Decision:

- Double **presentation** hex size by setting **`HexLayout.SIZE`** from **32.0** to **64.0** (circumradius). **`MapView.hex_tile_size`** default updated to **64.0** for consistency (**export** only; drawing uses **`layout`**).
- **No** `Camera2D` zoom, **no** input pan/scroll, **no** domain **`HexCoord`** / **`HexMap`** or movement rule changes — all views and **`SelectionController`** hit radii derive from the same **`HexLayout`**.

Rationale:

- In-app map read too small; a single shared layout constant scales **terrain**, **cities**, **selection**, **units**, and **click mapping** together.

Caveat:

- **Viewport fit** / cropping is unchanged; **Phase 4.5** or a narrow layout follow-up may address camera or fit without conflating with this **scale** tweak.

## 2026-05-02 — Phase 4.3a marker request pack committed to docs

Decision:

- Record the **approved Phase 4.3a** prototype **map marker icon** specification in **[ASSET_REQUEST_PACKS/PHASE_4_3A_MARKER_SET.md](ASSET_REQUEST_PACKS/PHASE_4_3A_MARKER_SET.md)** (three **512×512** transparent PNGs; paths under `game/assets/prototype/map_markers/`).
- Reflect **generation feedback:** overall markers **lighter** than dark sepia; **muted natural** accent palette (warm stone, ochre, muted clay red, olive, desaturated blue-grey, leather brown) — **not** monochrome brown only; **non-glossy**, painterly **parchment-map** family.
- **Warrior** icon = **first/basic melee**: **club / wooden cudgel / simple wooden shield / leather or fur** hints — **no** metal armour, **no** helmet crest, **no** spear-dominant pose; avoids reading as organized infantry or **Bronze-Armed Warrior**-style content.

Rationale:

- Centralises the request pack in-repo; aligns art brief with **primitive `warrior`** identity and readability learnings from the first draft.

Caveat:

- **Superseded by implementation:** icons are wired in **Phase 4.3b**; see follow-on **DECISION_LOG** entry and **`game/assets/prototype/map_markers/PROVENANCE.md`**.

## 2026-05-02 — Prototype map marker icons wired (Phase 4.3b)

Decision:

- **`CitiesView`** and **`UnitsView`** **`load()`** prototype **PNG map marker icons** from **`game/assets/prototype/map_markers/`** (**`city_marker.png`**, **`unit_settler_marker.png`**, **`unit_warrior_marker.png`**); **neutral texture** **`modulate`**, **programmatic** **owner** accents / **rim** / **selection halo**; **diamond** / **Phase 4.2** circle+glyph **fallback** when **`load()`** fails or **`type_id`** unknown.
- **`PROVENANCE.md`** in that folder documents external (**ChatGPT** / image generation) origin and **prototype-only** status.

Rationale:

- Implements **[PHASE_4_3A_MARKER_SET.md](ASSET_REQUEST_PACKS/PHASE_4_3A_MARKER_SET.md)** without changing **domain** or **hit-testing**.

Caveat:

- **512×512** sources scaled in-world via **`city_icon_height_ratio`** / **`unit_icon_height_ratio`**; tune per viewport — **not** final art.

## 2026-05-02 — Map scale + marker alpha repair (Phase 4.3c)

Decision:

- Raise **`HexLayout.SIZE`** **64.0 → 128.0** and **`MapView.hex_tile_size`** default **128.0** so terrain, cities, units, selection, and **hit radii** share one **global** presentation scale (icon **height ratios** unchanged vs hex).
- **Marker PNGs** inspected: **PNG** **color type 2** (**RGB**, no **alpha**) — **white** squares were **asset-format** (opaque background), not **`draw_texture_rect`**. **`MarkerTextureUtil.load_marker_icon`** converts to **RGBA** and keys pixels near **top-left** background to **transparent** (epsilon **~0.09**); **true RGBA** re-exports remain the **best** fix.

Rationale:

- Live map still read small at **SIZE 64** on test displays; **RGB** sources explained **alpha** failure.

Caveat:

- Background keying can punch holes if **icon** pixels match **corner** colour; prefer **RGBA** **PNG**s when refreshing art.

## 2026-05-02 — Viewport fit + marker ratios (Phase 4.3d)

Decision:

- **`project.godot`** default **`viewport` 1600×1000** so **`HexLayout.SIZE` 128** prototype scenarios show with less edge clipping — **window** sizing only, **not** zoom/pan/`Camera2D`.
- **`unit_icon_height_ratio`** default **0.60**, **`city_icon_height_ratio`** default **0.80** — marker detail/readability; **`SIZE`** stays **128.0**.

Rationale:

- Separates **viewport real estate** from hex world scale; icon ratios track **hex height** without changing layout math or hit-test **semantics**.

Caveat:

- **F11** fullscreen / multi-monitor still user-dependent; **Phase 4.5** may add camera/fit later.

## 2026-05-02 — Play-area 1.5× + clean markers (Phase 4.3f)

Decision:

- **`project.godot`** default viewport **2400×1500** (**1.5×** **1600×1000**).
- **`unit_icon_height_ratio`** **0.70**, **`city_icon_height_ratio`** **0.90**.
- **UnitsView** / **CitiesView:** remove **circular** icon **frames**, unit **selection halo**, owner **under-circle**; **SelectionView** hex overlay carries **selection** read for units.

Rationale:

- More **play area** without **zoom**; larger icons; avoids **redundant** rings now that **hex** highlight is sufficient.

Caveat:

- **Fallback** unit marker is a **filled disk** (not a “frame”); **true RGBA** PNGs still preferred per **PROVENANCE**.

## 2026-05-02 — Map layer origin / top padding (Phase 4.3g)

Decision:

- **`main.gd`** **`MAP_LAYER_ORIGIN`** = **`Vector2(400, 428)`** (**+128** **Y** vs **`(400, 300)`**); **`_ready()`** sets **`position`** on **MapView**, **CitiesView**, **SelectionView**, **UnitsView**, **SelectionController** — shared **Node2D** origin, **not** **`HexLayout`** math change.

Rationale:

- Top hex row clipped at viewport top; one **vertical** **screen** offset keeps layers and **`SelectionController.to_local`** aligned.

Caveat:

- Future **map-root** node could consolidate five assignments; **Phase 4.5** camera may revisit framing.

## 2026-05-01 — Painterly terrain textures for PLAINS + WATER (Phase 4.1c)

Decision:

- **`MapView`** loads **`game/assets/prototype/terrain/plains_painterly.png`** and **`water_painterly.png`** in **`_ready()`**; **`_draw()`** maps each hex with **`draw_colored_polygon(..., uvs, texture)`** when the **`Texture2D`** resolves; otherwise **`_terrain_to_color`** flat fill. **`compute_draw_items`** still derives rows from **`map.coords()`** / **`terrain_at`** and includes **`terrain`** on each item for draw dispatch.

Rationale:

- **Prototype** land/water read without changing **`HexMap.Terrain`** or rules; **UV** mapping from hex **AABB** keeps fills **cell-local**.

Caveat:

- **Not** shipping art; **`PROVENANCE.md`** documents external generation; per-cell **AABB** UVs were a **minimal** first fit — **Phase 4.1d** replaces them with **world-anchored** UVs for continuity.

## 2026-05-01 — World-anchored terrain UVs (Phase 4.1d)

Decision:

- **`MapView`**: **`uv = (corner.x, corner.y) / terrain_texture_world_scale`** (layout space, default scale **512**); **`texture_repeat = TEXTURE_REPEAT_ENABLED`** for **`draw_colored_polygon`** textured path. **Fallback** flat fill unchanged.

Rationale:

- Reduces **per-hex** texture **stamp** while keeping **hex clip** and **`terrain_at`** only.

Caveat:

- **Seamless** tiling still depends on **source PNG** edges; **coast blending** remains deferred.

## 2026-05-01 — Linear texture filter for map markers (Phase 4.3h)

Decision:

- **`UnitsView`** and **`CitiesView`**: **`texture_filter = TEXTURE_FILTER_LINEAR`** in **`_ready()`** for **`draw_texture_rect`** marker paths. **`MapView`** unchanged.

Rationale:

- **512×512** icons drawn **smaller** in world space minify **cleaner** than default **nearest** / inherited sampling; **scoped** to marker **CanvasItems**.

Caveat:

- **Heavy** minification can still **soften** edges; **mipmaps** not enabled (2D **`draw_texture_rect`** path; **linear** is the minimal fix).

## 2026-05-01 — True-alpha map markers + mipmapped downscale (Phase 4.3i)

Decision:

- **`city_marker.png`**, **`unit_settler_marker.png`**, **`unit_warrior_marker.png`**: verified **512×512** **PNG** **RGBA8** (corners **alpha 0**); **`UnitsView`** / **`CitiesView`** load via **`ResourceLoader.load`** — **no** **`MarkerTextureUtil`** keying. **`texture_filter`** **`LINEAR_WITH_MIPMAPS`**; **`mipmaps/generate=true`** on **those three** **`.import`** files only.

Rationale:

- **True** **RGBA** **alpha** removes keyed-edge artefacts; **mipmaps** + **linear** improve **minification** vs **base mip** alone.

Caveat:

- **`MarkerTextureUtil`** retained for **hypothetical** **RGB** sources; terrain **imports** untouched.

## 2026-05-01 — Prototype raster import quality standard (Phase 4.3j)

Decision:

- **Docs-only** steering: **[VISUAL_DIRECTION.md](VISUAL_DIRECTION.md)** adds a **default** **Prototype raster import quality standard** (true **RGBA** when transparency is required, **direct** **`Texture2D`** load, **scoped** mipmaps/filter where appropriate, **runtime keying** only as **temporary** **RGB** repair, verification checklist, **explicit** exceptions). **[RENDERING.md](RENDERING.md)**, **[PHASE_PLAN.md](PHASE_PLAN.md)**, marker **Asset Request Pack** updated for alignment.

Rationale:

- **Lock in** **4.3i** outcomes so future **Asset Request Packs** and implementers treat **alpha quality** as **contract**, not **rendering debt**.

Caveat:

- Category-specific **import** details still **evolve** per asset type; policy allows **ARP**-documented **exceptions**.

## 2026-05-01 — LogView lower band (Phase 4.4a)

Decision:

- **`main.tscn`** **`LogView`** **`Label`**: **y** **1220–1475** (default **2400×1500**) — clears **hex** **overlap** from prior **~480–720** band; **`MAP_LAYER_ORIGIN`**, **`log_view.gd`**, and **ActionLog** behaviour unchanged.

Rationale:

- **Debug** log remains **readable** in a **lower HUD** strip without **obscuring** **map** **content**.

Caveat:

- **Larger** maps / future **camera** may need another pass (**Phase 4.4+**).

## 2026-05-01 — Terrain procedural detail overlay (Phase 4.1e)

Decision:

- **`MapView`**: after **base** **textured** or **flat** hex fill, **deterministic** low-alpha **procedural** marks — **PLAINS:** **specks** + short **strokes**; **WATER:** light **ripple** **lines**; **`_terrain_detail_hash(q, r, salt)`** only. **No** new **terrain** types; **no** **2.5D** **occlusion** stack.

Rationale:

- **Visual** **life** without **domain** or **asset** churn; preserves **4.1d** **world** **UVs** and **existing** **PNGs**.

Caveat:

- Marks are **not** **clipped** to the **hex** **polygon** (kept **small** + **inward**); **future** **cover** **terrain** stays **documented** in **[VISUAL_DIRECTION.md](VISUAL_DIRECTION.md)** only.

## 2026-05-01 — Map layer tilt Y + unit icon foot offset (Phase 4.5a)

Decision:

- **`MAP_LAYER_TILT_Y`** **`0.85`** — shared **`Vector2(1.0, tilt_y)`** on **`MapView`**, **`CitiesView`**, **`SelectionView`**, **`UnitsView`**, **`SelectionController`** (**`main.gd`** + **`main.tscn`** mirror). **`Main`** has **no** layer scale.
- **`unit_icon_foot_offset_ratio`** **`0.20`** — **textured** unit icons only: **foot** **`world.y + HexLayout.SIZE * ratio`**, rect top at **`foot_y - icon_side`**; **cities** unchanged (**center**); **fallback** disk unchanged.

Rationale:

- Cheap **faux** **perspective** without **Camera2D** or **domain** changes; **`to_local`** stays consistent because **`SelectionController`** shares the **same** transform as drawn layers.

Caveat:

- **Hex** **center** vs **visual** **foot** for **icons** can diverge from **disk** **hit** **radius** (**unchanged**); future **Phase** **4.5+** may refine **picking** if needed.

## 2026-05-02 — Hex-owned foreground composition (Phase 4.6e)

Decision:

- **`TerrainForegroundView`** **foreground** is **hex-owned**: **deterministic** **main** + optional **secondary** from **`PlainsForestScript.cell_mix`** (**salts** **4000–4099**), **`anchor_pres`** = **`MapCamera.to_presentation(layout.hex_to_world(q,r))`**, **`base` = `HexLayout.SIZE × perspective_scale_at(world_center)`** for all **sizes**/ **offsets**. **Normal** path **does** **not** read **unit** occupancy. **City** hexes **omit** **main** **clump** only (**`scenario.cities_at(coord)`**). **`enable_unit_occlusion_test`** **default** **false**; **`_draw_unit_forest_occluder`** stays **debug**/ **test** **only**.

Rationale:

- **Stable** vegetation **independent** of **unit** **movement**; **overlap** **calibrated** to the **foot-contact** **region** (**`UnitsView`** **pivot** **convention** **unchanged**) so **mass** can **read** as **foreground** over **feet**/ **lower** **legs** without **tracking** **units**.

Caveat:

- **Still** **not** **`Terrain.FOREST`** / **not** **cover** **rules** — **procedural** **decoration** on **PLAINS** only.

## 2026-05-02 — Forest foreground visibility calibration (Phase 4.6f)

Decision:

- **`TerrainForegroundView.forest_front_opacity`** default **0.62** → **0.85**; **main**/**secondary** per-primitive **alpha** multipliers **slightly** **increased** (**circles** / **polygon**) with **same** **RGB** bands — **evaluative** pass so **clump** **geometry** and **overlap** **read** clearly. **`forest_back_opacity`** **unchanged** (**0.85**). **No** changes to **salts**, **placement** **formulas**, **`forest_density_ratio`**, **city**-**skip**, or **hex**-**ownership** **model**.

Rationale:

- **4.6e** **structure** was **plausible** but **too** **transparent** to **verify** **foot**-zone **calibration** and **readability** tradeoffs **in** **editor**.

Caveat:

- **Final** **shipping** **look** may **lower** **opacity** again or **move** to **raster** **forest** (**4.3j**); this phase is **not** a **commitment** to **permanent** **brightness**.

## 2026-05-02 — Forest raster overlays — PLAINS decoration (Phase 4.6g)

Decision:

- **`MapView`** / **`TerrainForegroundView`** draw **`res://assets/prototype/terrain/forest/forest_*_clump_0{1,2}.png`** (**preload** **`Texture2D`**) for **decorated** **PLAINS** when **`use_forest_asset_overlays`** (**default** **true**); **`PlainsForestScript.cell_mix`** salts **4100** / **4110–4112** for **variant** / **layout**; **`4.6e`** **4000–4099** **untouched**. **City** hexes: **skip** **front** **raster** only (**`scenario.cities_at`**) — **procedural** **secondary**-only; **back** **raster** still **draws**. **Procedural** **`_draw_plains_forest_*`** **preserved** for **`use_forest_asset_overlays = false`**. **Not** **`Terrain.FOREST`** / **not** **rules**.

Rationale:

- **Ship** **readable** **painterly** **masses** **aligned** to **pan**/ **zoom** while **keeping** a **deterministic** **debug**/**fallback** **path**.

Caveat:

- **Repo** paths are **`assets/prototype/terrain/forest/`** (not **`assets/terrain/forest/`**); **`main.gd`** **does** **not** **sync** **the** **two** **`use_forest_asset_overlays`** **flags** — **inspector** **must** **set** **both** **if** **toggling**.

## 2026-05-10 — Phase 5.1.9: automatic `controlled_fire` science + `ScienceCompletedPopup`

Decision:

- **`ProgressState`** adds **`science_progress`** and **`science_observation_flags`**. **`ScienceTick`** (**`controlled_fire`** only, **cost 6**) awards **+1** per owned city when the **owner ends their turn** (**after** **`ProductionTick`**, **before** **`TurnState` advance**), and a **one-time +4** when the **last log entry** is an **accepted `move_unit`** to a cell **on or adjacent** to **`scenario.lightning_tree_hex`**. At threshold, **`ProgressUnlockResolver.complete_progress`** runs and **`ActionLog`** records **`science_progress`** then **`science_completed`** (**`source: engine`**). **`ScienceCompletedPopup`** is **log-driven** and **presentation-only**; **`DiscoveryActionPanel`** **filters out** **`controlled_fire`**. **`KEY_H`** remains a **manual** **`CompleteProgress`** path when **`ProgressCandidateFilter`** still returns a candidate.

Rationale:

- **Science** completes **automatically** from play; the popup is **informational**, not a gate. **`DiscoveryActionPanel`** stays available for **future** non-science events.

Caveat:

- **Single-target** prototype — **no** **`SelectScience`**, **no** multi-science tree UI.

## 2026-05-17 — Slice C8 cloud boot: loading gate + no silent hotseat fallback

Decision:

- When cloud client mode is active, **`Main`** shows a **blocking overlay** from bootstrap until the **first** server snapshot is **adapted**, **`_wire_play_session`** completes, and **`_refresh_presentation_after_cloud_snap`** runs; gameplay input is suppressed (**Esc** / **F1** allowed). If **`POST /v1/matches`** or snapshot wiring fails, the overlay shows an **error** and the scene does **not** automatically re-run **local hotseat** wiring ( **`main.tscn`** defaults **`use_cloud_server`** to **off** so editor/tests complete **`_ready`** synchronously).

Rationale:

- Avoids presenting **local prototype** map as **interactable** while the server session is still starting, and avoids **misleading** recovery when the authority backend is down.

Caveat:

- **Retry / quit** from the stranded overlay is **not** implemented; player relaunches the scene or project.

## 2026-06-01 — Slice C9 cloud reconnect via GET /v1/matches/{id}

Decision:

- When **`Main.cloud_match_id`** or env **`EOM_CLOUD_MATCH_ID`** is non-empty, the Godot cloud client **skips** **`POST /v1/matches`**, binds **`CloudSession.match_id`**, and loads state via existing **`GET /v1/matches/{id}`** (same **`{match_id, snapshot, revision, state_hash}`** envelope as create). Empty match id preserves create-on-boot. Reconnect failure uses the same **stranded overlay** as create failure — **no** silent local hotseat fallback. Successful create logs **`match_id`** with a reconnect hint.

Rationale:

- Lets developers resume an in-progress authority match without new server endpoints, event replay, or polling.

Caveat:

- **No** desync recovery beyond the GET snapshot; **no** live presence or websocket refresh in this slice.

## 2026-06-02 — Slice C14a local cloud credential store (Godot client only)

Decision:

- Cloud match credentials are persisted in **`user://cloud_matches.json`** as plaintext JSON (**version 1**, array of `{server_url, match_id, actor_id, seat_token, is_host, last_seen_status, last_seen_revision, label, updated_at}`). Helper: **`game/cloud/cloud_credential_store.gd`**.
- **Conservative resolution:** **`EOM_CLOUD_SEAT_TOKEN`** / inspector token override saved store; saved token is used only when a **known `match_id`** is provided (env/inspector/export) and token is empty. **No** auto-resume of the latest saved match without explicit match id or future lobby selection.
- **`Main`** saves credentials after successful create/reconnect bootstrap and updates **`last_seen_revision`** after snapshot apply / accepted POST responses. **`last_seen_status`** remains **`unknown`** until C14b server staging metadata exists.

Rationale:

- Removes dev friction for reconnect while keeping C13a authority and hotseat paths unchanged; foundation for C14c lobby without server or API changes in this slice.

Caveat:

- **Alpha-grade local plaintext** — not suitable for production secrecy; no keychain/encryption in C14a.

## 2026-06-02 — Slice C14b server lobby list + open seat claim

Decision:

- New matches write **`meta.json` schema_version 2** with **`status: staging`**, **`created_at`**, **`scenario_id`**, and **`seats[].claimed`**. **`GET /v1/matches`** lists token-free summaries (directory scan); **`POST .../seats/{actor_id}/claim`** returns only the claimed seat token.
- **C14b does not** add **`POST /start`** or reject **`POST /actions`** while staging — preserves create-then-play and C13a token gate until **C14d**.
- **Legacy:** no-**`meta.json`** dirs omitted from list; permissive actions unchanged. **C13 meta v1** treated as **`ongoing`**; claim returns **`match_not_in_staging`**.

Rationale:

- Open alpha lobby discovery without accounts or invite codes; Godot lobby UI deferred to **C14c**.

Caveat:

- Public staging matches are joinable by any client with server access; no rate limiting or private matches.

## 2026-06-02 — Slice C14c Godot cloud front door / lobby UI

Decision:

- **`run/main_scene`** is **`cloud_front_door.tscn`**. **`BootIntent`** (static RefCounted, not autoload) passes mode/url/match/token into **`main.tscn`**. **`EOM_CLOUD_CLIENT=1`** skips the front door for dev/headless tests that load **`main.tscn`** directly.
- Front door uses C14b **`GET /v1/matches`** + **`POST .../claim`** and C14a credential store; lobby rows are token-free in the UI.

Rationale:

- Replaces env-var-only cloud entry for normal play while preserving test and dev override paths.

Caveat:

- No **`POST /start`**, no staging action gate, minimal layout only; lifecycle enforcement deferred to **C14d**.

## 2026-06-02 — Slice C14c.1 local saved-match labels

Decision:

- **Saved list** = **`entries_for_server`** (local credentials with **`seat_token`** only). **Open staging list** = server **`GET /v1/matches`** — kept as separate UI sections.
- **`label`** in **`user://cloud_matches.json`**; auto **Match N** defaults; naming **`Window`** after create/claim; **Rename** + **Resume** buttons on saved list (select row first).

Rationale:

- Usable resume UX without server match titles or shared names.

Caveat:

- Labels are per-computer only; other players do not see them until a future shared-title feature.

## 2026-06-02 — Slice C14b.1 / C14c.2 server display_name + host rename

Decision:

- **`display_name`** in **`meta.json` v2**; server default **`Match {short_match_id}`**; **`PATCH /v1/matches/{id}/display-name`** (host token only). Lobby list and create/claim responses expose **`display_name`** without tokens.
- Godot saved/open rows prefer server name; local **`label`** is cache; host **Rename** uses **PATCH** + lobby resync to fix revert.

Rationale:

- Shared lobby titles for alpha without accounts; local-only labels were invisible to other players and reverted on refresh.

Caveat:

- No private/invite titles; non-hosts cannot rename; GET single-match snapshot unchanged.

## 2026-06-02 — Slice T2 validation policy checkpoint

Decision:

- Document in **`docs/TESTING.md`** and **`docs/VALIDATION_CHECKLIST.md`** that agents and implementation prompts should default to **`slice`** profiles during work and in final reports; **`full`**, **`cloud`**, and **`presentation`** run only per explicit user request or release/deploy/large-refactor checkpoints.
- Cursor skill/rules reference the same policy in post-implementation validation reporting.

Rationale:

- T1 test profiles are underused when every slice report runs broad suites; focused iteration should match focused tests.

Caveat:

- **`full`** remains the runner default when no args are passed; humans and deploy scripts may still use it intentionally.

## 2026-06-03 — Slice C14d-dev local cloud credential profiles

Decision:

- Optional env **`EOM_CLOUD_PROFILE`** selects a separate Godot credential file: default **`user://cloud_matches.json`**; profile **`A`** → **`user://cloud_matches_A.json`**. Profile names are trimmed and sanitized (alnum, `_`, `-`; other chars → `_`). **`cloud_credential_store.gd`** resolves paths via **`resolved_store_path()`** / **`_effective_store_path()`** for all default-path I/O.
- Dev/test only: no product UI; **`EOM_CLOUD_DEBUG=1`** logs profile + store path once at front door/staging startup (no tokens).

Rationale:

- Two Godot instances on one machine need isolated saved credentials for async two-player staging validation without separate OS users.

Caveat:

- Plaintext JSON per profile on the same machine; not a security boundary—convenience for local multi-client testing only.

