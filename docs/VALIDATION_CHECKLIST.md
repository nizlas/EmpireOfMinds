# Empire of Minds — Validation Checklist

This checklist is used after each implementation step.

**Test profiles (T1) and validation policy (T2):** See **`docs/TESTING.md`**. Use **`slice <id>`** for focused work; use **`smoke`** when shared boot/helpers change; use **`cloud`**, **`presentation`**, and **`full`** only when the policy table says so or the user explicitly requests them.

### Validation policy (T2) — quick reference

| Situation | Run | Usually skip |
|-----------|-----|----------------|
| Implementing a focused slice | `slice <id>` on the side you changed | `full`, `cloud`, `presentation` |
| Final report, small/local slice | Same `slice`; optional `smoke` if shared boot/session/helpers touched | `full`, `cloud`, `presentation` |
| Godot front door / labels / credential UX | `run-godot-tests.ps1 slice c14c` (+ `smoke` if BootIntent / main boot changed) | `full`, `cloud`, `presentation` |
| Small server API slice | `run-server-tests.ps1 slice <id>` (+ `smoke` if shared match/action plumbing changed) | `full`, Godot `cloud` unless deploy prep |
| Large refactor, deploy checkpoint, user asked for full regression | `full` (and `cloud` / `presentation` if relevant) | — |

Agents: in the final report, list focused tests run, broader tests skipped, why, and whether **full** is recommended before commit/deploy.

## Architecture Boundary Validation

- [ ] Game rules are not owned by Godot rendering nodes.
- [ ] Unit positions are stored in domain/game state, not only in sprites.
- [ ] Map/hex data is represented as domain data, not only as drawn tiles.
- [ ] UI requests actions rather than directly mutating gameplay state.
- [ ] AI chooses from legal actions and does not mutate state directly.
- [ ] Actions are validated before application.
- [ ] Action application updates authoritative state.
- [ ] Rendering reflects state rather than owning state.
- [ ] The implementation does not assume future cloud games are client-authoritative.

## Phase 1 Functional Validation

- [ ] A local map can be displayed.
- [ ] At least one unit exists in domain state.
- [ ] Unit selection works.
- [ ] Legal destination hexes can be determined.
- [ ] A legal move action succeeds.
- [ ] An illegal move action is rejected.
- [ ] End turn advances the turn state.
- [ ] A simple AI turn can choose at least one legal action.
- [ ] AI actions go through the same validation path as player actions.
- [ ] Action log records structured actions.

## Determinism / Replay Readiness

- [ ] Actions have structured data, not only human-readable text.
- [ ] Game state changes happen through actions.
- [ ] Randomness is absent, seeded, or explicitly recorded.
- [ ] The same initial state plus the same action sequence should produce the same result, within current phase limits.

## Cloud Readiness

- [ ] Actions are serializable or designed to become serializable.
- [ ] Game state is serializable or designed to become serializable.
- [ ] Player identity is explicit enough to support future cloud turns.
- [ ] Turn ownership is explicit enough to support future server validation.
- [ ] No Phase 1 shortcut makes server-authoritative validation impossible later.

## AI Readiness

- [ ] AI has a narrow interface.
- [ ] Rule-based AI works without network access.
- [ ] No OpenAI/Ollama dependency is required for gameplay.
- [ ] LLM integration, if discussed, remains behind future adapter boundaries.
- [ ] AI rejected actions are logged or diagnosable.

## IP / Licensing

- [ ] No Civilization names, icons, text, leaders, or exact UI/system copying.
- [ ] Any added dependency has an acceptable license.
- [ ] Any added asset has a known source and license.
- [ ] No AGPL/GPL dependency is added without explicit approval.
- [ ] No “free for personal use” asset is included in distributable content.

## Agent Behavior

- [ ] Agent stated the phase scope before implementation.
- [ ] Agent stated explicit out-of-scope items.
- [ ] Agent listed plausible wrong implementations.
- [ ] Agent listed hidden assumptions.
- [ ] Agent listed deferred decisions and why deferral is safe.
- [ ] Agent listed files changed.
- [ ] Agent explained responsibility split.
- [ ] Agent explained validation performed.
- [ ] Agent did not silently change steering documents.
- [ ] Agent proposed steering document updates when needed.

## Phase 5.1.19c — Growth / play loop smoke (prototype map)

Manual validation in the Godot editor (`main.tscn`); **no** new visuals required. Confirms **5.1.19b** growth + **Manage Citizens** + production/delivery loop on the curated island.

- [ ] Launch **Play** / open **`main.tscn`** with the prototype scenario path used by local play.
- [ ] Found capital (**F** or equivalent) at the opening settler position.
- [ ] Open **City Hub**; confirm **Growth:** line shows `stored / threshold (+N/turn)`.
- [ ] **End Turn** repeatedly as P0; confirm **`food_stored`** / growth line climbs when surplus is positive (watch hub or **Action Log** `food_growth_progress`).
- [ ] **Manage Citizens**, click another **owned** non-center tile (planning); return to hub and confirm **`(+N/turn)`** changes **if** the tile differs from AUTO worked choice (if map gives no differing eligible tile, note equality).
- [ ] Continue until **population reaches 2** on the capital (hub **Pop** + optional `city_grew` in log).
- [ ] Queue **settler** production; **End Turn** until settler **delivers**; move settler to a distant legal land hex; found **second city** (**F**).
- [ ] Select second city; confirm **Growth** line appears and **food / stored** begin moving when surplus is positive.

For scripted coverage, run **`scripts/run-godot-tests.ps1`** — includes **`test_growth_play_loop_smoke.gd`** (headless, **Deterministic-first**).

## Phase 5.1.19f — Turn status HUD (hotseat wording + player accent)

Manual check in **`main.tscn`** / local play (**no** domain changes).

- [ ] **Lower-right** **Turn** strip shows **`Player 0's turn`** at start (or equivalent **“now playing”** copy — **no** **“Waiting for Player …”** in local hotseat).
- [ ] **End Turn** → strip shows **`Player 1's turn`**; P1 can act immediately in the **same** run.
- [ ] Panel **orb / border / tint** matches the **same** owner accent family as **empire border** and **unit/city nameplate** strips (teal/cyan vs rose for P0/P1 in the prototype palette).
- [ ] Turn strip stays **visible** and updates **without** opening **City Hub** / city selection.

## Phase 5.2.0 — Local hotseat readiness

Manual validation for **local hotseat prototype** builds (external playtest / “Niklas minigame” style). **No** server, lobby, or remote opponent — one human controls **whichever `TurnState` seat is current**.

- [ ] App starts and **`TurnStatusPanel`** shows **`Player 0's turn`** with the **P0** nameplate/empire accent family.
- [ ] **Capital** can be **founded**, **grown**, and queue **warrior** + **settler** (per current rules).
- [ ] **Space** ends turn; the HUD flips to **`Player 1's turn`** with the **P1** accent.
- [ ] **P1** can act on **P1** units in the **same** app instance without restart.
- [ ] Trying to act on the **wrong** player's unit/city is either **disabled** in UI or fails readably (e.g. **`not_current_player`** in reject paths / log).
- [ ] Selecting an **opponent** city does **not** allow **production** / **Manage Citizens** (hub explains **not your city** or equivalent).
- [ ] **`KEY_A`** is understood as **“AI plays one action for whoever is current”** — **not** autopilot; document for testers ([PLAYTEST_GUIDE.md](player/PLAYTEST_GUIDE.md)).
- [ ] **20–50** **`EndTurn`** cycles can run without **null** dereference or stack trace.
- [ ] **City Hub** **Close** clears city selection (expected today).
- [ ] **`scripts/run-godot-tests.ps1`** is green before handing off a build.

## Phase 5.2.1 — Hotseat: **`EndTurn`** clears **City Hub** selection

Manual check in **`main.tscn`** (**local hotseat prototype**).

- [ ] Select **P0** capital; open **Manage Citizens** (**PLANNING**); press **Space** (**End Turn**).
- [ ] **City Hub** closes (or is hidden); **citizen** markers leave the map (**PLANNING** off).
- [ ] **`TurnStatusPanel`** shows **`Player 1's turn`** (accent matches **P1**).
- [ ] **P1** can select and act immediately without seeing **P0**’s hub from the prior turn.

Validation: **`scripts/run-godot-tests.ps1`** — **`test_hotseat_endturn_selection_clear.gd`**.

## Phase 5.2.2 — Player / contact strip v0 (upper-right seats)

Manual check in **`main.tscn`** (**local hotseat prototype**).

- [ ] **Upper-right** strip shows **P0** and **P1** (one chip per **`TurnState`** seat).
- [ ] **Current** seat has a **stronger** border/fill than the inactive seat(s).
- [ ] Press **Space** (**End Turn**): highlight moves to the **next** player; **no** **“Waiting for Player …”** copy on the strip.
- [ ] Chip **accent** colors match the same **player** tint family as **`TurnStatusPanel`** / **empire** / **nameplates**.
- [ ] Strip stays **separate** from **lower-right** **`TurnStatusPanel`** and **City Hub** on the default viewport.

Validation: **`scripts/run-godot-tests.ps1`** — **`test_player_contact_strip.gd`**.

## Phase 5.2.3 — Map visibility / fog v0 (parchment unexplored overlay)

Manual check in **`main.tscn`** (**local hotseat prototype**).

- [ ] On start, only the area around **P0**’s starting units (radius **2**) is **clear**; the rest of the map shows **parchment** (or flat fallback if the texture is missing).
- [ ] Move **P0**’s warrior one hex: tiles within radius **2** of the new position are **clear** for **P0**; tiles explored earlier **stay** clear (**memory**).
- [ ] Press **Space** (**End Turn**): the overlay switches to **P1**’s explored set (**P1**’s starting areas clear, not **P0**’s full map unless overlapped).
- [ ] Found a city with **P0**’s settler: city center, **`owned_tiles`**, and radius-**2** ring become **clear** for **that** player.
- [ ] **P0** / **P1** discovery stays **separate** (no cross-player reveal).

Validation: **`scripts/run-godot-tests.ps1`** — **`test_player_visibility_state.gd`**, **`test_player_visibility_reveal.gd`**, **`test_map_visibility_view.gd`**, sibling-order and **`test_turn_view_sync.gd`** updates.

## Phase 5.2.4k — Unexplored map-detail source culling (yields, decorations, name banners)

Manual check in **`main.tscn`** with **Yields** toggled on where applicable.

- [ ] Over **unexplored** parchment: **no** yield icons or yield letter fallbacks, **no** lightning-tree stump, **no** forest **TerrainForegroundView** decorations on those hexes, **no** city **name** banners or unit **name** banners that would sit on unexplored cells.
- [ ] On **explored** hexes, those elements behave as **before** this slice.
- [ ] **Space** (hotseat): switching **current** player updates which cells are treated as explored for the above (**same** set as parchment).

Validation: **`scripts/run-godot-tests.ps1`** — **`test_presentation_visibility.gd`**, **`test_tile_yield_overlay_view_visibility.gd`**, **`test_lightning_tree_view_visibility.gd`**, **`test_terrain_foreground_view_visibility.gd`**, **`test_city_nameplate_view_visibility.gd`**, **`test_unit_nameplate_view_visibility.gd`**, plus **`test_turn_view_sync.gd`** ( **`game_state`** propagation).

## Phase 5.2.4l — Real WATER sea shell (prototype footprint)

Manual check in **`main.tscn`**.

- [ ] Map **footprint** reads as a **straight-edged rectangle** in world space (outer ring is **WATER** on **`HexMap`**, not a presentation plate).
- [ ] **Land / content** layout matches the pre-shell curated island: same **(q,r)** for terrain, cities, units, yields as before **5.2.4l** on those cells.
- [ ] Roughly **three** hex-steps of **WATER** padding between the old playable/content edge and the new outer boundary (world-axis shell).
- [ ] **Unexplored parchment** covers unexplored **outer** water (real map cells).
- [ ] Yields, decorations, and labels **do not** leak over parchment in unexplored areas (**5.2.4k** gating still holds).

Validation: **`scripts/run-godot-tests.ps1`** — **`test_prototype_rectangular_water_shell.gd`**, **`test_prototype_play_map_distribution.gd`**, **`test_map_visibility_view.gd`**, **`test_map_visibility_boundary_feather.gd`**, **`test_main_tscn_map_layer_sibling_order.gd`**, **`test_turn_view_sync.gd`**, **`test_presentation_visibility.gd`**.

## Phase 5.2.4m — Soft unexplored boundary feather (presentation)

Manual check in **`main.tscn`** (local hotseat; same **`MapVisibilityView`** in cloud once **`game_state`** is wired).

- [ ] Find a **forest clump** or other **tall decoration** near the **explored/unexplored** line: explored-side art **fades** under parchment at the boundary — **no separate line, rim, or detached strip**; feather **attaches** to the unexplored parchment.
- [ ] **Unexplored** tiles remain fully covered; **no** yields, labels, or hidden terrain leak through parchment.
- [ ] **Space** (hotseat): feather boundary **updates** with the **current player’s** explored set (same as parchment holes).
- [ ] **Cloud mode:** map visibility + feather draw normally after server snapshot (no server changes).

Validation: **`scripts/run-godot-tests.ps1`** — **`test_map_visibility_boundary_feather.gd`**, plus **`test_map_visibility_view.gd`** / **`test_presentation_visibility.gd`** regression.

## Phase 5.2.5 — Per-turn movement points v0 (warrior / settler)

Manual check in **`main.tscn`** (**local hotseat**).

- [ ] Select **P0** warrior: move **two** adjacent legal steps; a **third** move in the same turn is **not** applied (no position change / no illegal log spam).
- [ ] Select **P0** settler: same **two**-then-blocked behavior.
- [ ] **Space** (**End Turn**): **P1**’s units have **full** MP again; move them twice each; third blocked.
- [ ] **Space** until **P0** is current again: **P0**’s units have **full** MP again (**2** steps each).
- [ ] After a valid move, **fog / exploration** for the **current** player still updates as before (**5.2.3**).

Validation: **`scripts/run-godot-tests.ps1`** — **`test_unit_movement_points_v0.gd`**, **`test_move_unit.gd`**, **`test_movement_rules.gd`**, **`test_unit.gd`**, **`test_move_unit_preserves_scenario_state.gd`**, **`test_player_visibility_reveal.gd`** (or existing visibility suite as regression).

Validation: **`scripts/run-godot-tests.ps1`** — **`test_combat_rules.gd`**, **`test_attack_unit.gd`**, **`test_attack_unit_flow.gd`**, **`test_unit.gd`**, **`test_unit_definitions.gd`**.

## Local Combat 0.1 — Warrior vs adjacent Warrior (manual)

Manual check in **`main.tscn`** (**deterministic melee**; no combat UI polish).

- [ ] **Player 0** turn: select a **Warrior**, click an **adjacent** enemy **Warrior** — attack applies (**30** damage each when both full and equal strength), attacker **cannot move** again same turn.
- [ ] Click same attacker again at another adjacent enemy (or same after refresh): rejected (**movement_exhausted** / no effect) or no illegal submit.
- [ ] **Own** adjacent Warrior: click does **not** attack ally (**warning** / no HP change).
- [ ] Non-adjacent enemy Warrior: normal **move** / selection behavior, **not** an attack.
- [ ] **End Turn** / movement refresh: **wounded** unit keeps **HP** after turn rollover (see domain tests).

## Phase 5.2.5a — Keep unit selected while movement remains (presentation)

Manual check in **`main.tscn`** (**local hotseat**).

- [ ] Select **P0** warrior: move **one** hex — warrior **stays** selected and legal move highlights show any remaining **one**-step destinations; move a **second** hex without re-clicking the unit.
- [ ] After the **second** step, a **third** move is **not** available (no destination overlay / click does nothing).
- [ ] Repeat with **P0** settler: one step → still selected; second step → exhausted.
- [ ] **Space** (**End Turn**): **5.2.1** selection clear for the next player still behaves as before.

Validation: **`scripts/run-godot-tests.ps1`** — **`test_selection_post_move_unit.gd`**, **`test_hotseat_endturn_selection_clear.gd`** (unchanged **EndTurn** clear contract).

## Phase 5.2.6 — Turn-start scroll banner (first interaction dismisses)

Manual check in **`main.tscn`** (**assets** **`game/assets/prototype/ui/turn_scroll_banner.png`**).

- [ ] On **Play**, a centered **scroll** banner appears with **`Your turn, Västerviksjävlarna`** (opening **Player 0** seat; **5.2.6a** display names).
- [ ] Any **click**, **key**, **wheel**, or **right-drag** motion dismisses the banner; gameplay (**Space** end turn, map pick, etc.) can still run on that same input when **`Main._input`** runs first (**5.2.6** hook).
- [ ] After **End Turn** (**Space**), the **next** player’s banner appears (**`Your turn, Malmöfubikkarna`** for **Player 1**).
- [ ] If you **do nothing**, the banner may stay visible (no close button).

Validation: **`scripts/run-godot-tests.ps1`** — **`test_turn_start_banner_view.gd`**, **`test_playtest_player_display.gd`**.

## Phase 5.2.6a — Playtest player display names (hotseat HUD)

Manual check in **`main.tscn`** (names from **`FactionDefinitions`** debug rows via **`PlaytestPlayerDisplay`**).

- [ ] **Turn** label (**upper-left**) and **lower-right** turn strip use **Västerviksjävlarna** / **Malmöfubikkarna** (not **Player 0 / Player 1**); **numeric ids** in domain / log lines are unchanged.
- [ ] **Player contact** chips (**upper-right**) show the same faction names (may truncate at max chip width); tooltips match.
- [ ] Turn-advance order is unchanged (**Player 0** → **Player 1** → …).

Validation: **`scripts/run-godot-tests.ps1`** — **`test_playtest_player_display.gd`**, **`test_turn_label.gd`**, **`test_turn_status_panel.gd`**, **`test_player_contact_strip.gd`**.

## Slice C8 — Godot cloud-client prototype (local FastAPI, opt-in)

Manual validation (**no** auth, **no** websocket, **no** combat parity; server remains authoritative). **Local hotseat** is unchanged when cloud is **off** (default).

1. Start server: `cd server` then `python -m uvicorn app.main:app --reload --port 8000` (or your venv Python).
2. Enable cloud in Godot: set **`Main.use_cloud_server`** in the inspector **or** set env **`EOM_CLOUD_CLIENT=1`**; optional **`EOM_CLOUD_BASE_URL`** overrides **`cloud_base_url`** (default `http://localhost:8000`).
3. Before the first server-backed frame is ready, a **full-screen dimmed overlay** shows **Connecting to cloud match…** then **Loading cloud match…**; map zoom/pan, selection, **Y**, and other gameplay shortcuts are blocked (**Esc** / **F1** still work). If **create-match** or snapshot wiring fails, the overlay stays up with an **error** message and the client does **not** fall back to local hotseat.
4. **Play:** **`POST /v1/matches`** runs once; note **`match_id`** in the console.
5. Select a **unit** belonging to the current player: move highlights follow **`GET .../legal-actions`** **`move_unit`** list; **found city** via **F** uses the server-listed action.
6. Select a **city**: **City Hub** production buttons use **`set_city_production`** entries from legal-actions where applicable.
7. **Space**: **`end_turn`** posts to the server; HUD / turn banner refresh from the response snapshot.
8. Confirm **production / growth / science / movement** advance after end turn when exercising the server loop.
9. Disable cloud and confirm **local hotseat** still uses **`try_apply`** only (AI **A**, combat, **P**/**G**/**H**, **Manage Citizens** planning, etc.).

**Diagnostics:** set **`EOM_CLOUD_DEBUG=1`** for compact **`SliceC8DBG`** lines (**`cloud_bootstrap`** logs **`effective_url`**, **`url_source`** (`EOM_CLOUD_BASE_URL` vs **`Main.cloud_base_url`**), **`cloud_scenario_id`**) and other cloud routing lines, plus **`SliceC8TIME`** milestones (**`cloud_init_start`** … **`first_cloud_snapshot_ready`**). Create-match lines include **`base_url`**, **`path`**, **`full_url`**, **`scenario_id`**, and response **`elapsed_ms`** / snapshot **`scenario_id`** / **`map_cells`**. On boot failure, **`cloud_boot_failed`** includes URL metadata. No full snapshots in logs by default.

Validation: **`scripts/run-godot-tests.ps1`** includes **`cloud/tests/test_server_snapshot_adapter.gd`**, **`cloud/tests/test_cloud_client_payloads.gd`**, **`cloud/tests/test_cloud_routing_pick.gd`**, **`cloud/tests/test_main_default_cloud_base_url.gd`**, **`cloud/tests/test_main_cloud_boot_no_local_session_before_server.gd`**, **`cloud/tests/test_main_cloud_reconnect_get_match.gd`**, and **`domain/tests/test_dump_prototype_play_map_script_loads.gd`**. Server: **`pytest -q`** in **`server/`**.

## Slice C9 — Cloud reconnect via GET /v1/matches/{id}

Manual validation (**Godot client only**; reuses existing server GET — **no** new endpoint, **no** event replay, **no** polling).

1. Start server (same as Slice C8).
2. Enable cloud with **no** **`cloud_match_id`** / **`EOM_CLOUD_MATCH_ID`** → match is **created**; note **`match_id`** in console (`Slice C9 cloud: created match_id=… (set EOM_CLOUD_MATCH_ID=… to reconnect)`).
3. Make a server-visible change (e.g. **move_unit** or **end_turn**); note **revision** / **current player** / unit positions.
4. Quit Godot; relaunch with **`EOM_CLOUD_MATCH_ID=<that id>`** (or inspector **`cloud_match_id`**) → overlay shows **Reconnecting to cloud match…** then gameplay; **revision**, **current player**, and positions match the saved server state (**GET**, not **POST /v1/matches**).
5. After reconnect: **move_unit**, **end_turn**, and **legal-actions** refresh still work; turn banner shows on bootstrap/reconnect once and again only when **current player** changes.
6. Set **`EOM_CLOUD_MATCH_ID=m_bad_id`** with server running → **error overlay**, **no** local hotseat fallback, **`MapView.map`** stays unwired.
7. Unset match id env and disable cloud → **local hotseat** unchanged.

Validation: **`scripts/run-godot-tests.ps1`** — **`test_main_cloud_reconnect_get_match.gd`**, **`test_cloud_client_payloads.gd`** ( **`should_create_match`**, **`get_match_path`** ), plus C8 regression tests.

## Slice C10 — Server-authoritative `attack_unit` (Local Combat 0.1 cloud parity)

Manual validation (**no** clash animation, **no** city/ranged combat, **no** event replay/polling). **Local hotseat** unchanged when cloud is **off**.

1. Start server: `cd server && uvicorn app.main:app --reload` (or existing C8 command).
2. Enable cloud (`EOM_CLOUD_CLIENT=1` or **`Main.use_cloud_server`**). Use **`tiny_test`** or move adjacent enemy **Warriors** into range on **`prototype_play`** (server legal-actions only lists valid adjacent **Warrior** vs **Warrior** attacks).
3. Select your **Warrior** with movement remaining → adjacent enemy hex shows **attack-target** highlight (distinct from move destinations).
4. Click enemy hex → **`POST .../actions`** with **`attack_unit`** (`attacker_id`, `defender_id` only); HP updates from **response snapshot**; attacker **`remaining_movement`** becomes **0**; selection clears.
5. Equal-strength warriors: expect **30** damage each way if both survive; lethal strike skips retaliation.
6. **End turn** still works; combat state persists after **C9 reconnect** (`EOM_CLOUD_MATCH_ID`).
7. Disable cloud → local hotseat combat (**click enemy**, clash animation, **`try_apply`**) unchanged.

Validation: **`pytest -q`** in **`server/`** — **`test_combat_rules.py`**, **`test_attack_unit_flow.py`**. **`scripts/run-godot-tests.ps1`** — **`test_cloud_client_payloads.gd`** (attack float→int coercion, **`build_attack_maps_from_legal_actions`**), plus C8/C9 regression tests.

## Slice C11 — Cloud combat presentation v0

Manual validation (**presentation-only**; server remains authoritative). **Local hotseat** unchanged when cloud is **off**.

1. Start server; enable cloud (C8/C10 setup).
2. Get adjacent **Warriors**; select attacker; click highlighted enemy.
3. Confirm **`POST .../actions`** returns **`accepted=true`** with **`event.action_type == attack_unit`**.
4. Confirm short **`CombatClashBurstView`** plays **before** HP/state updates on screen.
5. Confirm post-animation HP/death matches **`response.snapshot`** (and **`GET .../events`** row).
6. Confirm map input works again after ~0.6s (no permanent block).
7. **Reconnect** shows final combat state only (no animation replay).
8. Disable cloud → local hotseat combat unchanged (clash burst via **`try_apply`** path).

Validation: **`pytest -q`** — **`test_attack_unit_flow.py`** (`event` in response matches log). **`scripts/run-godot-tests.ps1`** — **`test_cloud_combat_animation.gd`**, plus C8/C9/C10 regression tests.

## Slice C12a — Hetzner deploy foundation (Docker + Caddy)

Deploy-only validation; **no** gameplay, schema, auth, Postgres, polling, or AI changes. See [DEPLOY_HETZNER.md](DEPLOY_HETZNER.md).

- [ ] DNS: `cloud.thewizardsapprentice.org` resolves to **62.238.44.6** (`dig +short` or equivalent).
- [ ] On Hetzner: `cd deploy/hetzner` then `docker compose up --build -d` starts **caddy** + **empire-server**.
- [ ] `curl -fsS https://cloud.thewizardsapprentice.org/v1/healthz` returns **`{"ok":true}`**.
- [ ] From outside: `curl http://62.238.44.6:8000/v1/healthz` **fails** (no public FastAPI port).
- [ ] Match data survives **`docker compose restart empire-server`** (GET same `match_id` after restart).
- [ ] Godot with **`EOM_CLOUD_CLIENT=1`** and **`EOM_CLOUD_BASE_URL=https://cloud.thewizardsapprentice.org`**: create match, move, attack, end turn, reconnect via **`EOM_CLOUD_MATCH_ID`**.
- [ ] **`thewizardsapprentice.org`** / **`www`** WordPress site unchanged (DNS not pointed at Hetzner for root/www).
- [ ] Local dev unchanged: `cd server` + `uvicorn app.main:app --reload --port 8000`; cloud off → hotseat only.

**Local pre-deploy checks:** `docker build -t empire-server ./server`; `docker compose -f deploy/hetzner/docker-compose.yml config`; **`pytest -q`** in **`server/`**; **`scripts/run-godot-tests.ps1`** (no Godot code changes in C12a).

## Slice C12b — Cloud explored-map memory (reconnect / server restart)

- [ ] Cloud: move unit to reveal new tiles; **GET** same match (or reconnect Godot with **`EOM_CLOUD_MATCH_ID`**) — previously visited tiles outside current sight stay clear (parchment does not return over them).
- [ ] Remote or local FastAPI: **`docker compose restart empire-server`** (or restart uvicorn) — explored memory still restored from snapshot file.
- [ ] Local hotseat (cloud off): fog memory unchanged after **End Turn** / long play.

Validation: **`pytest -q`** — **`test_player_visibility_flow.py`**. **`scripts/run-godot-tests.ps1`** — **`test_server_snapshot_adapter_visibility.gd`**.

## Slice C13a — Player seats / invite tokens

- [ ] **`POST /v1/matches`** returns additive **`seats`** + **`host_token`**; **`GET /v1/matches/{id}`** has neither in body or snapshot.
- [ ] Seated match: **`POST .../actions`** without **`X-Empire-Seat-Token`** → **`missing_seat_token`**.
- [ ] Invalid token → **`invalid_seat_token`**; seat0 acting as actor 1 → **`seat_not_allowed`**; host token + valid **`actor_id`** → accepted when gameplay allows.
- [ ] Legacy match (no **`meta.json`**) still accepts actions without header.
- [ ] Godot create + reconnect with **`EOM_CLOUD_SEAT_TOKEN=<host_token>`**; move/attack/end-turn work locally and on **`https://cloud.thewizardsapprentice.org`**.
- [ ] Garbled/missing token on seated match → actions rejected; cloud off → hotseat unchanged.

Validation: **`pytest -q`** — **`test_seats.py`**, **`test_seat_token_flow.py`**. **`scripts/run-godot-tests.ps1`** — **`test_cloud_seat_token.gd`**. **`server/scripts/smoke_cloud_01.ps1`** (with server running).

## Slice C14b — Lobby list + seat claim (server)

- [ ] **`POST /v1/matches`** writes **`meta.json` v2** with **`status: staging`**, **`claimed: false`** on seats; create response still includes **`seats`** + **`host_token`**.
- [ ] **`GET /v1/matches`** returns summaries with **no** token fields; **`?status=staging`** filters v2 staging matches.
- [ ] **`POST /v1/matches/{id}/seats/{actor_id}/claim`** returns only that **`seat_token`**; **`meta.json`** shows **`claimed: true`**.
- [ ] Claim rejects: unknown match, non-staging (v1/ongoing), already claimed, missing seat.
- [ ] **`POST /actions`** with host token still accepted on staging match (no status gate until C14d).
- [ ] Legacy no-meta dirs do not appear in list; actions still permissive.

Validation: **`scripts/run-server-tests.ps1 slice c14b`** — **`test_lobby_list.py`**, **`test_seat_claim.py`**, **`test_seats.py`**. Full/cloud profiles include new tests.

## Slice C14c — Cloud front door / lobby UI (Godot)

- [ ] Normal launch shows front door (not immediate gameplay).
- [ ] **Local Hotseat** starts unchanged local session.
- [ ] **Create Cloud Match** stores host credential and starts cloud play.
- [ ] **Cloud Matches** lists staging rows without tokens; **Join … as Player N** claims and plays.
- [ ] **Resume** reconnects with saved token; missing match shows error on front door.
- [ ] **`EOM_CLOUD_CLIENT=1`** (+ optional env ids/tokens) still boots **`main.tscn`** cloud path without front door.
- [ ] Headless **`main.tscn`** cloud tests still pass.

Validation: **`scripts/run-godot-tests.ps1 slice c14c`** — lobby parsers, front-door boot intent, match labels, main boot-intent reconnect. **`scripts/run-godot-tests.ps1 cloud`** / **full**.

## Slice C14c.1 — Saved match labels (Godot)

- [ ] **Your matches on this server** lists **`GET /v1/matches`** rows filtered by local credentials for the active **`server_url`** (not credentials alone when the server is down).
- [ ] Credential for a match absent from the server list does not appear as playable resume.
- [ ] **Open staging matches** is separate from resume; staging rows show no tokens.
- [ ] **`EOM_CLOUD_BASE_URL`** to local debug server uses a separate credential/list scope from production cloud URL.
- [ ] **Create Cloud Match** → naming dialog prefilled **Match N**; OK saves label; cancel/empty uses default.
- [ ] Saved row shows human label + actor + short match id (not full token).
- [ ] **Rename** updates label; **Resume saved match** still reconnects.
- [ ] Claim open seat → naming dialog → saved with label; appears in saved list.

Validation: **`scripts/run-godot-tests.ps1 slice c14c`** — **`test_cloud_match_labels.gd`**.

## Slice C14b.1 / C14c.2 — Server display_name + host rename

- [ ] **POST /v1/matches** sets **`display_name`** (custom or **`Match {short_id}`** default).
- [ ] **GET /v1/matches** includes **`display_name`**; no tokens in list.
- [ ] **PATCH display-name** with host token succeeds; seat/invalid/missing token reject.
- [ ] Rename does not alter snapshot/events/state_hash.
- [ ] Front door saved rows show server name; host **Rename** persists after refresh; seat rename disabled/message.
- [ ] Open staging rows use server **`display_name`**.

Validation: **`scripts/run-server-tests.ps1 slice c14b`** (**`test_display_name.py`**), **`scripts/run-godot-tests.ps1 slice c14c`** (**`test_cloud_display_name.gd`**).
