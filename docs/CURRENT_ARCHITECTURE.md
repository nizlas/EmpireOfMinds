# Empire of Minds — Current architecture (orientation)

Concise map of **what exists in code today**. For phased history and decisions use [PHASE_PLAN.md](PHASE_PLAN.md) and [DECISION_LOG.md](DECISION_LOG.md). For norms and boundaries use [ARCHITECTURE_PRINCIPLES.md](ARCHITECTURE_PRINCIPLES.md), [CONTENT_MODEL.md](CONTENT_MODEL.md), [CORE_LOOP.md](CORE_LOOP.md), [MAP_MODEL.md](MAP_MODEL.md), and [PROGRESSION_MODEL.md](PROGRESSION_MODEL.md).

## Authority pivot (in progress)

**Charter:** [AUTHORITY_PIVOT.md](AUTHORITY_PIVOT.md). **Target:** Python/FastAPI under `server/` owns canonical gameplay; Godot becomes client/presentation for **localhost** (hotseat) and **remote** (cloud) by address only. **Today (pre–Slice F):** the runnable game still uses **`GameState.try_apply`** + `game/domain/` as described below; the Python server is **Cloud 0.1**-shaped and will grow per the pivot slices. **Slice C8 (opt-in):** [`main.gd`](../game/main.gd) can run a **prototype cloud client** (`use_cloud_server` or `EOM_CLOUD_CLIENT=1`) that creates a match, reads **`GET .../legal-actions`**, and posts **`end_turn` / `move_unit` / `found_city` / `set_city_production`**, then rebuilds presentation from the **server snapshot** via [`server_snapshot_adapter.gd`](../game/cloud/server_snapshot_adapter.gd) (see [CLOUD_PLAY.md](CLOUD_PLAY.md)). **Slice C9:** when **`cloud_match_id`** or **`EOM_CLOUD_MATCH_ID`** is set, bootstrap uses **`GET /v1/matches/{id}`** instead of **`POST /v1/matches`**; failure strands with overlay (no hotseat fallback). **Slice C10:** cloud client also posts **`attack_unit`** (`attacker_id`, `defender_id` only); server **`combat_rules.py`** + **`attack_unit.py`** resolve Local Combat 0.1; legal-actions selection mode lists adjacent enemy **Warrior** attacks; Godot shows attack-target highlights and clears selection after accept. **Slice C11:** accepted **`attack_unit`** responses carry additive **`event`**; Godot plays **`CombatClashBurstView`** from server **`attacker_position`** / **`defender_position`** before applying snapshot (presentation-only; no client damage math). **Legacy Godot domain is kept** until cutover survives playtesting.

---

## Purpose

- Give agents and contributors a **fast mental model**: where state lives, how actions apply, where UI wires in, and high-risk hotspots.
- **Not** source-of-truth for every rule—for schemas and semantics always follow [ACTIONS.md](ACTIONS.md), [TURNS.md](TURNS.md), [CITIES.md](CITIES.md), [AI_LAYER.md](AI_LAYER.md), [RENDERING.md](RENDERING.md).
- **Forward-looking city interaction UX** (hub + opt-in planning mode + empire-border layering intent): **[CITY_UX.md](CITY_UX.md)** — orientation only until matching slices ship.

---

## Runtime flow

1. **Local run (default):** [main.gd](../game/main.gd) constructs **Scenario**, **HexLayout**, **SelectionState**, **GameState**, wires map layers, HUD panels, [SelectionController](../game/presentation/selection_controller.gd), [EndTurnController](../game/presentation/end_turn_controller.gd), [AITurnController](../game/presentation/ai_turn_controller.gd). It is **wiring-only** — not authoritative gameplay logic. **Cloud prototype (Slice C8, opt-in):** the same wiring is fed a **GameState** built from the server **snapshot v2** (skip local **ProductionDelivery** / movement refresh at init); input branches **`POST .../actions`** and **`GET .../legal-actions`** instead of **`try_apply`** for supported actions.
2. **Every gameplay change:** an action **dictionary** enters **[`GameState.try_apply`](../game/domain/game_state.gd)** (`RefCounted`).
3. **Validation + apply:** `try_apply` dispatches by `action_type` to modules under **`game/domain/actions/`** ([MoveUnit](../game/domain/actions/move_unit.gd), [AttackUnit](../game/domain/actions/attack_unit.gd), [FoundCity](../game/domain/actions/found_city.gd), [SetCityProduction](../game/domain/actions/set_city_production.gd), [EndTurn](../game/domain/actions/end_turn.gd), [CompleteProgress](../game/domain/actions/complete_progress.gd), [SetCurrentResearch](../game/domain/actions/set_current_research.gd), …). **`CombatRules`** ([combat_rules.gd](../game/domain/combat_rules.gd)) resolves **`attack_unit`** once; **`AttackUnit.apply_with_result`** applies that snapshot only.
4. **Domain transition pattern:** validated actions rebuild an immutable **[Scenario](../game/domain/scenario.gd)** snapshot (units, cities, **`HexMap`, id counters**, **`lightning_tree_hex`**). **[ActionLog](../game/domain/action_log.gd)** gains an accepted entry where applicable.
5. **Ticks on [`EndTurn`](../game/domain/actions/end_turn.gd)** (inside **`GameState.try_apply`**): [ProductionTick](../game/domain/production_tick.gd) appends **`production_progress`** entries; [FoodGrowthTick](../game/domain/food_growth_tick.gd) may append **`food_growth_progress`** / **`city_grew`**; [ScienceTick](../game/domain/science_tick.gd) may append Ancient-era accumulation lines **before** the **`end_turn`** record advances **`TurnState`**; **`end_turn`** is logged (the returned **`try_apply`** index targets this row); then [ProductionDelivery](../game/domain/production_delivery.gd) runs for the **new** actor (**`unit_produced`**). Canonical ordering: **[TURNS.md](TURNS.md)**, **[ACTIONS.md](ACTIONS.md)**.
6. **Presentation refresh:** controllers assign **`scenario` / `game_state`** handles into **`Node2D`** views (`queue_redraw`, HUD `refresh`). **[TurnViewSync](../game/presentation/turn_view_sync.gd)** is a small **`RefCounted`** helper (**not** a bus, registry, or pub/sub): **`refresh_map_views_and_hud_after_try_apply_turn_controllers`** centralizes terrain/map-layer redraws (`selection_view`, **`units_view`**, **`TerrainForegroundView`**, **`MapVisibilityView`** (**5.2.3** — parchment fog for **`current_player_id`** explored complement), nameplates, yield overlay, territory) plus turn label **`refresh`** and the HUD **`refresh`** calls invoked from **EndTurn** / **AI** paths after an accepted **`try_apply`**; **`sync_terrain_related_views`** handles the terrain-related map-layer/sync path delegated from **[SelectionController](../game/presentation/selection_controller.gd)** (including **`MapVisibilityView.game_state`** + **`queue_redraw`** when **`game_state`** is passed). Controllers still own accepted-action handling, **`DiscoveryPopup`** sequencing, and any view/HUD updates not covered by those helpers. **5.2.1:** **EndTurn** (and AI-accepted **`end_turn`**) clear **unit** + **city** + **planning** via **`EndTurnController.apply_hotseat_clear_after_accepted_end_turn`** before **`TurnViewSync`** (see **Turn control** below).

### Turn control / local hotseat prototype

**Phase 5.2.0** names the shipped local mode **local hotseat prototype** (single instance; human can play every seat in turn).

- **[`GameState.try_apply`](../game/domain/game_state.gd)** rejects actions when **`action["actor_id"] != turn_state.current_player_id()`** (**`not_current_player`**), before type-specific validation — same gate for humans and AI-chosen actions.
- **[`TurnState`](../game/domain/turn_state.gd)** holds **`players`**, **`current_index`**, **`turn_number`** only. There is **no** domain **`seat_kind`**, **human-player assignment**, or **remote/local** split.
- **Presentation** drives input for **whoever is current**; **[`TurnStatusPanel`](../game/presentation/turn_status_panel.gd)** shows hotseat copy **`Player N's turn`** (not “waiting for …”) and tints from **`UnitNameplateView.owner_nameplate_accent_color`**. **`local_player_id`** on that panel is **presentation-only**, reserved for **future remote-seat** UX; it does **not** gate **`try_apply`** today.
- **[`AITurnController`](../game/presentation/ai_turn_controller.gd)** is **manual** (**`KEY_A`**): one **`RuleBasedAIPlayer.decide`** per press for **`LegalActions.for_current_player`**, i.e. **whoever is current** — not an autopilot loop and **not** a per-seat “AI owns player 1” assignment.
- **Phase 5.2.1:** on **accepted** **`EndTurn`** (**`Space`** or AI-chosen **`end_turn`**), **[`EndTurnController.apply_hotseat_clear_after_accepted_end_turn`](../game/presentation/end_turn_controller.gd)** clears **unit** + **city** selection and **`CityViewState.reset_to_normal()`** (via **`city_production_panel.city_view_state`**) before the usual **HUD** refresh — so the next **current** player does not inherit the prior **City Hub** / **PLANNING** focus.
- **Phase 5.2.2:** **`PlayerContactStrip`** (**upper-right** **`HudCanvas`**) lists **`TurnState.players`** with **current-seat** highlight; **`TurnLabel.after_refresh`** (**`main.gd`**, **`_refresh_turn_hud_after_turn_label`**) refreshes **`TurnStatusPanel`** and **`PlayerContactStrip`** when the turn advances — **presentation-only**, no contact/diplomacy/fog.
- **Phase 5.2.5:** **`Unit`** MP — **`max_movement`** / **`remaining_movement`**; each accepted **`move_unit`** spends **1**; full refresh for a player’s units when that player **becomes** current (after **`end_turn`** + **`ProductionDelivery`** for the new actor, and once at session start for the opening current player). **`LegalActions`** / **`MovementRules`** respect exhausted MP.

---

## Domain layer (`game/domain/`)

| Area | Responsibility (today) |
|------|-------------------------|
| **[GameState](../game/domain/game_state.gd)** | Session facade **`try_apply`**; authoritative **`scenario`**, **`turn_state`**, **`progress_state`**, **`visibility_state`** (**[`PlayerVisibilityState`](../game/domain/player_visibility_state.gd)**, **5.2.3**), **`ActionLog`** for local play |
| **[HexCoord](../game/domain/hex_coord.gd)** | Axial cell identity / neighbors; **`axial_distance`** (**5.2.3** cube metric for sight radii) |
| **[HexMap](../game/domain/hex_map.gd)** | Finite cell set; terrain tags; **`Landform`**; **`_woods` overlay**; prototype factories (**`make_tiny_test_map`**, **`make_prototype_play_map`**) |
| **[Scenario](../game/domain/scenario.gd)** | Map + units + cities + id bookkeeping + **`tile_owner_city_id`**; **`City.owned_tiles`**, capital / **`building_ids`**, **`lightning_tree_hex`** |
| **[City](../game/domain/city.gd)** | City row including **`population`** (**default founding `1`**), **`food_stored`** (**5.1.19b**), **`owned_tiles`**, **`is_capital`**, **`building_ids`**, **`current_project`**, **`manual_worked_tiles`** |
| **[CityYields](../game/domain/city_yields.gd)** | Read-only yields from terrain, woods, **city-center rule**, buildings, and **worked** non-center **`owned_tiles`** (**manual-first** then deterministic auto-fill, bounded by **`population`**); **`yield_breakdown_for_city`** decomposes **`city_total_yield`** — presentation-independent |
| **[Unit](../game/domain/unit.gd)** | **`type_id`**, position, **`max_movement`**, **`remaining_movement`** (**5.2.5**), **`current_hp`** / **`max_hp`** (definitions-backed max; see **`UnitDefinitions`**) |
| **[TurnState](../game/domain/turn_state.gd)** | Player order / current index / turn counter |
| **[ProgressState](../game/domain/progress_state.gd)** | Unlocks, completed progress, science accumulation, **`current_research_id`** |
| **[PlayerVisibilityState](../game/domain/player_visibility_state.gd)** | **5.2.3:** Immutable per-player explored-tile sets; deterministic **`recompute_for_actor`** from scenario (units + cities); presentation-independent |
| **[LegalActions](../game/domain/legal_actions.gd)** | Enumerates **`move_unit`**, **`found_city`**, **`set_city_production`**, **`end_turn`** (optional **`effective_rules`**); not all player actions (**e.g.** **`complete_progress`** / **`set_current_research`**) appear here |
| **[MovementRules](../game/domain/movement_rules.gd)** | One-step destinations from **`TerrainRuleDefinitions`**, gated when **`remaining_movement < 1`** (**5.2.5**) |
| **[EffectiveRules](../game/domain/effective_rules.gd)** | **Thin façade** today (e.g. supported city projects via **`CityProjectDefinitions`**) |
| **`RuleSet`** | **Architecture direction only** — **no** matching GDScript **`class_name`** yet; persistence / compilation story lives in **[CONTENT_MODEL.md](CONTENT_MODEL.md)**, **[CLOUD_PLAY.md](CLOUD_PLAY.md)** |
| **`game/domain/content/`** | **`UnitDefinitions`**, **`CityProjectDefinitions`**, **`ProgressDefinitions`**, **`TerrainRuleDefinitions`**, **`FactionDefinitions`**, … |
| Helpers | **`ProgressUnlockResolver`**, **`ProgressDetector`**, **`ScienceAvailability`**, **`FoodGrowthTick`** (**Phase 5.1.19b** — food surplus → **`food_stored`**, threshold growth per **`end_turn`**), **`PrototypePlainsClusters`** (**[prototype_plains_clusters.gd](../game/domain/prototype_plains_clusters.gd)** — prototype play-map curated forest-debug cluster axial coords), … |

**Prototype clusters (boundary):** Curated axial cluster coords for **`HexMap.make_prototype_play_map()`** plains/forest-debug alignment live in **`PrototypePlainsClusters`** (**[prototype_plains_clusters.gd](../game/domain/prototype_plains_clusters.gd)**). **[HexMap](../game/domain/hex_map.gd)** reads that domain source only—not presentation **[forest_debug_clusters.gd](../game/presentation/forest_debug_clusters.gd)** (**`preload`**/`import` stays **out** of production domain code for this data). **`ForestDebugClusters`** remains the presentation façade and diagnostic helper over the **same** domain-authored lists (**`TerrainForegroundView`**, headless cluster geometry tests). *Caveat:* some **`game/domain/tests/`** harness scripts **may still** **`preload`** presentation modules for layered smoke wiring; **`HexMap`** and other core **`game/domain/`** production scripts (**excluding** **`tests/`**) **do not** depend on **`res://presentation/`** for prototype cluster coordinates.

---

## AI layer (`game/ai/`)

- **[RuleBasedAIPlayer](../game/ai/rule_based_ai_player.gd):** **`decide(game_state, legal_actions)`** returns one action **`Dictionary`** chosen from **`LegalActions`** output (**no direct state mutation**).
- **[RuleBasedAIPolicy](../game/ai/rule_based_ai_policy.gd):** log-based “moved since last **`end_turn`**” helper.

---

## Presentation layer (`game/presentation/` + [main.gd](../game/main.gd) / [main.tscn](../game/main.tscn))

| Concern | Main nodes / scripts |
|--------|-----------------------|
| **Map stack** | [MapView](../game/presentation/map_view.gd), [TerrainEdgeBlendView](../game/presentation/terrain_edge_blend_view.gd) (**5.1.17k** — **present**; **`draw_edge_blend`** default **off**, **no** edge ribbons until re-enabled), [EmpireBorderView](../game/presentation/empire_border_view.gd) (**selection-independent** realm border), [CityTerritoryView](../game/presentation/city_territory_view.gd) (**dormant** **`_draw`** — **no** selected-city rim; forward **citizen/head** markers for owned tiles), [CitiesView](../game/presentation/cities_view.gd), [SelectionView](../game/presentation/selection_view.gd), [UnitsView](../game/presentation/units_view.gd) |
| **Foreground + fog** | [TerrainForegroundView](../game/presentation/terrain_foreground_view.gd) — **large (~2k+ lines), multi-pass forest + delegated unit/city markers, depth-merge, many debug knobs** → **fragile hotspot**; **do not split blindly** pending a deliberate slice. **5.2.4k** — forest/decoration passes are **source-culled** per **`PresentationVisibility.should_draw_map_detail_for_current_player`** (same explored set as parchment). **[MapVisibilityView](../game/presentation/map_visibility_view.gd)** (**5.2.3**) — **`Node2D`** **after** **`TerrainForegroundView`**, **`z_index` 1**, parchment overlay on hexes **not** in **`visibility_state`** for **`current_player_id()`** on **all** **`scenario.map`** coords (including **5.2.4l** outer **WATER**); **5.2.4m** adds a **soft boundary feather** (strip quads spanning **[-inner_overlap, +width]** at unexplored/explored edges; feather draws **before** solid fill so overlap attaches to parchment — presentation-only, no placement changes). Refresh via **`TurnViewSync`** with **`game_state`**. |
| **Overlays / landmark** | [TileYieldOverlayView](../game/presentation/tile_yield_overlay_view.gd) (**5.2.4k** — yields culled when unexplored), [CityWorkedTilesView](../game/presentation/city_worked_tiles_view.gd) (**PLANNING / Manage Citizens** citizen **`dim` / `worked`** markers **above** yield icons; **non-center** **`owned_tiles`**; **5.1.17j** + **5.1.17j.1**), [LightningTreeView](../game/presentation/lightning_tree_view.gd) (**5.2.4k**), **[presentation_visibility.gd](../game/presentation/presentation_visibility.gd)** helper, nameplate views (**5.2.4k** — banners culled when unexplored) |
| **Camera / space** | [MapCamera](../game/presentation/map_camera.gd), [MapPlaneProjection](../game/presentation/map_plane_projection.gd), [HexLayout](../game/presentation/hex_layout.gd) |
| **Input / actions submission** | [SelectionController](../game/presentation/selection_controller.gd) (mouse + **`F`/`P`/`G`/`H`**, shared-hex semantics; **5.2.5a** — after accepted **`MoveUnit`**, same unit stays selected while it exists so multi-step MP use needs no re-select), **`EndTurn`/`AITurn`** controllers (**`SPACE`/`A`**) |
| **HUD** | **`HudCanvas`** (**layer** **16**) in **`main.tscn`** — **`PlayerContactStrip`** (**`player_contact_strip.gd`**, **5.2.2** — **upper-right** seat chips from **`TurnState.players`**, current-seat highlight, **`UnitNameplateView.owner_nameplate_accent_color`**; **`contact_state`** placeholder **known** — **not** diplomacy/contact/fog logic) + **`TurnStatusPanel`** (**`turn_status_panel.gd`**, lower-right **current-player** strip for **local hotseat**: **`Player N's turn`**, same accent source as **`EmpireBorderView`** / nameplates; **remote "waiting for …"** semantics **deferred**) + **selected-city hub** (**`city_production_panel.gd`**, **`CityProductionPanel`**) + **`CityViewState`** (**`city_view_state.gd`**, **NORMAL**/**PLANNING** presentation submode); discovery/science panels, popups, yields toggle; **`main.gd`** wires hub **`Close`** redraw refs (**`selection_view`**, **`city_territory_view`**, **`city_worked_tiles_view`**). **5.2.6 / 5.2.6a:** **`TurnStartBannerView`** ([turn_start_banner_view.gd](../game/presentation/turn_start_banner_view.gd), **`CanvasLayer`** **layer 15**) — centered scroll banner + **`Your turn, …`** (**`PlaytestPlayerDisplay`** → **`FactionDefinitions`** debug names for seats **0**/**1**) on session start and after accepted **`EndTurn`** (and AI **`end_turn`**); dismissed on first user input via **`main.gd`** **`_input`**. **`TurnLabel`**, **`TurnStatusPanel`**, **`PlayerContactStrip`** use the same display-name helper (**ids** stay **int**). Map stack includes **always-on** **`EmpireBorderView`**. |

Presentation **reads domain** (**`scenario`**, **`game_state`**); authoritative rules stay **`try_apply`**.

---

## Test architecture

- **Runner:** from repo root, [scripts/run-godot-tests.ps1](../scripts/run-godot-tests.ps1) runs a **fixed ordered list** of Godot headless scripts (**`-s res://…`**); count grows with new phases (see script array — includes **5.2.3** visibility tests, **5.2.4k** presentation gating tests, **5.2.4l** prototype sea-shell tests, **5.2.5** movement-points tests, **5.2.6** turn-start banner test, **5.2.6a** playtest display-name test).
- **Layout:** **`game/domain/tests/`**, **`game/presentation/tests/`**, **`game/ai/tests/`** — mix of invariant tests and tighter draw/UI harnesses; **`game/cloud/tests/`** (Slice C8) — snapshot adapter + HTTP URL/payload helpers (**no** live server in CI).

---

## Known fragile areas

- **[TerrainForegroundView](../game/presentation/terrain_foreground_view.gd)** — central visual hub; regressions ripple through layering, merges, diagnostics.
- **Layer sibling order / `z_index`** in **`main.tscn` / **`main.gd`** — must stay consistent with **`EmpireBorderView`** vs dormant **`CityTerritoryView`** slot, overlays, HUD (see also [RENDERING.md](RENDERING.md)).
- **Post-`try_apply` refresh** — shared terrain/map-layer/HUD redraw and **`refresh`** calls for **EndTurn** / **AI** live in **`TurnViewSync.refresh_map_views_and_hud_after_try_apply_turn_controllers`** (including **`MapVisibilityView`** when wired); **`SelectionController`** uses **`TurnViewSync.sync_terrain_related_views`** for terrain-related sync and **5.2.3** visibility **`game_state`** assignment. Accepted-action wiring, **`DiscoveryPopup`** timing, **`EndTurnController.apply_hotseat_clear_after_accepted_end_turn`** (**5.2.1**), and other controller-owned view/HUD updates remain explicit where they sit outside those helpers.

---

## What not to infer

- **`PHASE_PLAN.md` / `DECISION_LOG.md` are append-heavy** — this file does **not** replace drilling into them for slice intent.
- **`LegalActions`** is **not** the full universe of playable actions (science / **`CompleteProgress`** paths exist outside it).
- **`EffectiveRules`** is **not yet** the sole read boundary for every rule (**registry reads remain** elsewhere).
- **Starvation / settler population cost / housing / amenities / happiness / disease / specialists are not implemented** (**5.1.19b** ships **`food_stored`**, **`FoodGrowthTick`**, and **`CityProductionPanel`** **`growth_line`** only; **no** food drain when surplus **≤ 0**).

---

## Quick links

| Topic | Doc / code entry |
|--------|-------------------|
| Action schemas | [ACTIONS.md](ACTIONS.md) |
| Turn + engine ordering | [TURNS.md](TURNS.md) |
| Cities & production | [CITIES.md](CITIES.md) |
| Movement | [MOVEMENT_RULES.md](MOVEMENT_RULES.md) |
| AI contract | [AI_LAYER.md](AI_LAYER.md), [AI_DESIGN.md](AI_DESIGN.md) |
| Rendering detail | [RENDERING.md](RENDERING.md), [SELECTION.md](SELECTION.md) |
| Map data model | [MAP_MODEL.md](MAP_MODEL.md) |
| Content envelope | [CONTENT_MODEL.md](CONTENT_MODEL.md) |
| Progression / science shape | [PROGRESSION_MODEL.md](PROGRESSION_MODEL.md) |
| Playable loop narration | [CORE_LOOP.md](CORE_LOOP.md) |
