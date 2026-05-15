# Empire of Minds — Current architecture (orientation)

Concise map of **what exists in code today**. For phased history and decisions use [PHASE_PLAN.md](PHASE_PLAN.md) and [DECISION_LOG.md](DECISION_LOG.md). For norms and boundaries use [ARCHITECTURE_PRINCIPLES.md](ARCHITECTURE_PRINCIPLES.md), [CONTENT_MODEL.md](CONTENT_MODEL.md), [CORE_LOOP.md](CORE_LOOP.md), [MAP_MODEL.md](MAP_MODEL.md), and [PROGRESSION_MODEL.md](PROGRESSION_MODEL.md).

---

## Purpose

- Give agents and contributors a **fast mental model**: where state lives, how actions apply, where UI wires in, and high-risk hotspots.
- **Not** source-of-truth for every rule—for schemas and semantics always follow [ACTIONS.md](ACTIONS.md), [TURNS.md](TURNS.md), [CITIES.md](CITIES.md), [AI_LAYER.md](AI_LAYER.md), [RENDERING.md](RENDERING.md).
- **Forward-looking city interaction UX** (hub + opt-in planning mode + empire-border layering intent): **[CITY_UX.md](CITY_UX.md)** — orientation only until matching slices ship.

---

## Runtime flow

1. **Local run:** [main.gd](../game/main.gd) constructs **Scenario**, **HexLayout**, **SelectionState**, **GameState**, wires map layers, HUD panels, [SelectionController](../game/presentation/selection_controller.gd), [EndTurnController](../game/presentation/end_turn_controller.gd), [AITurnController](../game/presentation/ai_turn_controller.gd). It is **wiring-only** — not authoritative gameplay logic.
2. **Every gameplay change:** an action **dictionary** enters **[`GameState.try_apply`](../game/domain/game_state.gd)** (`RefCounted`).
3. **Validation + apply:** `try_apply` dispatches by `action_type` to modules under **`game/domain/actions/`** ([MoveUnit](../game/domain/actions/move_unit.gd), [FoundCity](../game/domain/actions/found_city.gd), [SetCityProduction](../game/domain/actions/set_city_production.gd), [EndTurn](../game/domain/actions/end_turn.gd), [CompleteProgress](../game/domain/actions/complete_progress.gd), [SetCurrentResearch](../game/domain/actions/set_current_research.gd), …).
4. **Domain transition pattern:** validated actions rebuild an immutable **[Scenario](../game/domain/scenario.gd)** snapshot (units, cities, **`HexMap`, id counters**, **`lightning_tree_hex`**). **[ActionLog](../game/domain/action_log.gd)** gains an accepted entry where applicable.
5. **Ticks on [`EndTurn`](../game/domain/actions/end_turn.gd)** (inside **`GameState.try_apply`**): [ProductionTick](../game/domain/production_tick.gd) appends **`production_progress`** entries; [ScienceTick](../game/domain/science_tick.gd) may append Ancient-era accumulation lines **before** the **`end_turn`** record advances **`TurnState`**; **`end_turn`** is logged (the returned **`try_apply`** index targets this row); then [ProductionDelivery](../game/domain/production_delivery.gd) runs for the **new** actor (**`unit_produced`**). Canonical ordering: **[TURNS.md](TURNS.md)**, **[ACTIONS.md](ACTIONS.md)**.
6. **Presentation refresh:** controllers assign **`scenario` / `game_state`** handles into **`Node2D`** views (`queue_redraw`, HUD `refresh`). **[TurnViewSync](../game/presentation/turn_view_sync.gd)** is a small **`RefCounted`** helper (**not** a bus, registry, or pub/sub): **`refresh_map_views_and_hud_after_try_apply_turn_controllers`** centralizes terrain/map-layer redraws (`selection_view`, **`units_view`**, **`TerrainForegroundView`**, nameplates, yield overlay, territory) plus turn label **`refresh`** and the HUD **`refresh`** calls invoked from **EndTurn** / **AI** paths after an accepted **`try_apply`**; **`sync_terrain_related_views`** handles the terrain-related map-layer/sync path delegated from **[SelectionController](../game/presentation/selection_controller.gd)**. Controllers still own accepted-action handling, **`DiscoveryPopup`** sequencing, **`selection.clear_unit()`**, and any view/HUD updates not covered by those helpers.

---

## Domain layer (`game/domain/`)

| Area | Responsibility (today) |
|------|-------------------------|
| **[GameState](../game/domain/game_state.gd)** | Session facade **`try_apply`**; authoritative **`scenario`**, **`turn_state`**, **`progress_state`**, **`ActionLog`** for local play |
| **[HexCoord](../game/domain/hex_coord.gd)** | Axial cell identity / neighbors |
| **[HexMap](../game/domain/hex_map.gd)** | Finite cell set; terrain tags; **`Landform`**; **`_woods` overlay**; prototype factories (**`make_tiny_test_map`**, **`make_prototype_play_map`**) |
| **[Scenario](../game/domain/scenario.gd)** | Map + units + cities + id bookkeeping + **`tile_owner_city_id`**; **`City.owned_tiles`**, capital / **`building_ids`**, **`lightning_tree_hex`** |
| **[City](../game/domain/city.gd)** | City row including **`population`** (**default founding `1`**; **no** growth rules yet), **`owned_tiles`**, **`is_capital`**, **`building_ids`**, **`current_project`** |
| **[CityYields](../game/domain/city_yields.gd)** | Read-only yields from terrain, woods, **city-center rule**, buildings, and **deterministic auto-worked** non-center **`owned_tiles`** (bounded by **`population`**); **`yield_breakdown_for_city`** decomposes **`city_total_yield`** — presentation-independent |
| **[Unit](../game/domain/unit.gd)** | **`type_id`** + position (see **`UnitDefinitions`**) |
| **[TurnState](../game/domain/turn_state.gd)** | Player order / current index / turn counter |
| **[ProgressState](../game/domain/progress_state.gd)** | Unlocks, completed progress, science accumulation, **`current_research_id`** |
| **[LegalActions](../game/domain/legal_actions.gd)** | Enumerates **`move_unit`**, **`found_city`**, **`set_city_production`**, **`end_turn`** (optional **`effective_rules`**); not all player actions (**e.g.** **`complete_progress`** / **`set_current_research`**) appear here |
| **[MovementRules](../game/domain/movement_rules.gd)** | One-step destinations from **`TerrainRuleDefinitions`** |
| **[EffectiveRules](../game/domain/effective_rules.gd)** | **Thin façade** today (e.g. supported city projects via **`CityProjectDefinitions`**) |
| **`RuleSet`** | **Architecture direction only** — **no** matching GDScript **`class_name`** yet; persistence / compilation story lives in **[CONTENT_MODEL.md](CONTENT_MODEL.md)**, **[CLOUD_PLAY.md](CLOUD_PLAY.md)** |
| **`game/domain/content/`** | **`UnitDefinitions`**, **`CityProjectDefinitions`**, **`ProgressDefinitions`**, **`TerrainRuleDefinitions`**, **`FactionDefinitions`**, … |
| Helpers | **`ProgressUnlockResolver`**, **`ProgressDetector`**, **`ScienceAvailability`**, **`PrototypePlainsClusters`** (**[prototype_plains_clusters.gd](../game/domain/prototype_plains_clusters.gd)** — prototype play-map curated forest-debug cluster axial coords), … |

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
| **Foreground hub** | [TerrainForegroundView](../game/presentation/terrain_foreground_view.gd) — **large (~2k+ lines), multi-pass forest + delegated unit/city markers, depth-merge, many debug knobs** → **fragile hotspot**; **do not split blindly** pending a deliberate slice |
| **Overlays / landmark** | [TileYieldOverlayView](../game/presentation/tile_yield_overlay_view.gd), [CityWorkedTilesView](../game/presentation/city_worked_tiles_view.gd) (**PLANNING / Manage Citizens** citizen **`dim` / `worked`** markers **above** yield icons; **non-center** **`owned_tiles`**; **5.1.17j** + **5.1.17j.1**), [LightningTreeView](../game/presentation/lightning_tree_view.gd), nameplate views |
| **Camera / space** | [MapCamera](../game/presentation/map_camera.gd), [MapPlaneProjection](../game/presentation/map_plane_projection.gd), [HexLayout](../game/presentation/hex_layout.gd) |
| **Input / actions submission** | [SelectionController](../game/presentation/selection_controller.gd) (mouse + **`F`/`P`/`G`/`H`**, shared-hex semantics), **`EndTurn`/`AITurn`** controllers (**`SPACE`/`A`**) |
| **HUD** | **`HudCanvas`** in **`main.tscn`** — **selected-city hub** (**`city_production_panel.gd`**, **`CityProductionPanel`**) + **`CityViewState`** (**`city_view_state.gd`**, **NORMAL**/**PLANNING** presentation submode); discovery/science panels, popups, yields toggle; **`main.gd`** wires hub **`Close`** redraw refs (**`selection_view`**, **`city_territory_view`**, **`city_worked_tiles_view`**). Map stack includes **always-on** **`EmpireBorderView`**. |

Presentation **reads domain** (**`scenario`**, **`game_state`**); authoritative rules stay **`try_apply`**.

---

## Test architecture

- **Runner:** from repo root, [scripts/run-godot-tests.ps1](../scripts/run-godot-tests.ps1) runs a **fixed list (~104)** of Godot headless scripts (**`-s res://…`**).
- **Layout:** **`game/domain/tests/`**, **`game/presentation/tests/`**, **`game/ai/tests/`** — mix of invariant tests and tighter draw/UI harnesses.

---

## Known fragile areas

- **[TerrainForegroundView](../game/presentation/terrain_foreground_view.gd)** — central visual hub; regressions ripple through layering, merges, diagnostics.
- **Layer sibling order / `z_index`** in **`main.tscn` / **`main.gd`** — must stay consistent with **`EmpireBorderView`** vs dormant **`CityTerritoryView`** slot, overlays, HUD (see also [RENDERING.md](RENDERING.md)).
- **Post-`try_apply` refresh** — shared terrain/map-layer/HUD redraw and **`refresh`** calls for **EndTurn** / **AI** live in **`TurnViewSync.refresh_map_views_and_hud_after_try_apply_turn_controllers`**; **`SelectionController`** uses **`TurnViewSync.sync_terrain_related_views`** for terrain-related sync. Accepted-action wiring, **`DiscoveryPopup`** timing, **`selection.clear_unit()`**, and other controller-owned view/HUD updates remain explicit where they sit outside those helpers.

---

## What not to infer

- **`PHASE_PLAN.md` / `DECISION_LOG.md` are append-heavy** — this file does **not** replace drilling into them for slice intent.
- **`LegalActions`** is **not** the full universe of playable actions (science / **`CompleteProgress`** paths exist outside it).
- **`EffectiveRules`** is **not yet** the sole read boundary for every rule (**registry reads remain** elsewhere).
- **Population growth / manual worked-tile UI / food stockpiling are not implemented** (**5.1.17a** ships **`population`** **`1`** + deterministic **`city_total_yield`** worked tiles **without** those systems).

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
