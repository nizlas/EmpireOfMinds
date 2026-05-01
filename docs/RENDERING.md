# Empire of Minds — Rendering (Phase 1.3+)

## Presentation boundary

- **`game/presentation/`** may use Godot `Node2D` / `CanvasItem` and drawing APIs. It must **not** own authoritative game rules or mutable domain objects as the long-term source of truth.
- **`game/domain/`** remains the home of `HexMap`, `HexCoord`, and other rule-state types. The presentation layer **reads the domain** (e.g. `coords()`, `terrain_at()`) to decide what to draw. **Rendered** geometry is a **derived view**; `HexMap` is still the source of which cells exist and what terrain they have.

## Phase 1.3 approach

- A single **[MapView](../game/presentation/map_view.gd)** `Node2D` overrides **`_draw()`** to fill the screen with the map.
- **`MapView.compute_draw_items(map, layout)`** is a **pure** static helper: it takes a `HexMap` and a [HexLayout](../game/presentation/hex_layout.gd), iterates **`map.coords()`** (the domain list of `HexCoord`), and returns draw lists with world position, hex corners, **domain terrain id**, and **flat fallback colors**. It does **not** use a hand-authored coordinate list and does not read `HexMap` internal storage.
- **HexLayout** implements **pointy-top** axial \((q, r) \to\) `Vector2` and six vertex positions for a hex of circumradius **`HexLayout.SIZE`** world units (**Phase 4.3c** current value **128.0** — **4×** the original **32.0** prototype; **Phase 4.2a** raised **32 → 64**, **4.3c** raised **64 → 128** for live readability). See [HEX_COORDINATES.md](HEX_COORDINATES.md) for domain axial meaning; layout orientation is a presentation choice. **Domain** `HexCoord` / `HexMap` **cell identities** are unchanged — only **presentation** scale.

## Map-driven coordinates

- Rendered cell positions and counts **derive from** `map.coords()`. The tiny test map from `HexMap.make_tiny_test_map()` is the same domain object used in tests; **no** duplicate fixture list in the view.

## Terrain rendering (flat fallback + prototype textures)

- **Terrain type** still comes only from **`HexMap.terrain_at(coord)`** — **no** gameplay dependence on pixels.
- **`MapView._terrain_to_color`** ([map_view.gd](../game/presentation/map_view.gd)) supplies **fallback** flat fills (also used for unknown terrain and when textures fail to load):
  - **`HexMap.Terrain.PLAINS`** — `Color(0.74, 0.67, 0.52)` (parchment-style land).
  - **`HexMap.Terrain.WATER`** — `Color(0.28, 0.46, 0.62)` (slate-teal water).
  - Unknown — `Color(1, 0, 1)` (should not occur for current enums).
- **Phase 4.1c / 4.1d / 4.1e (current draw path):** When **`plains_painterly.png`** / **`water_painterly.png`** load successfully, **`MapView._draw()`** fills each hex with **`draw_colored_polygon(corners, Color.WHITE, uvs, texture)`**. **Phase 4.1d:** **UVs** are **world-anchored**: each corner uses **`layout`**-space **`(x, y) / terrain_texture_world_scale`** so the same world point maps to the same UV on every hex — textures read as a **continuous layer**, not a per-hex **0–1 AABB** stamp. **`MapView.texture_repeat`** is **`TEXTURE_REPEAT_ENABLED`** so UVs outside **0–1** tile the image. Default **`terrain_texture_world_scale`** **512** (~**2.3** hex widths per repeat at **`SIZE` 128**). **PLAINS** and **WATER** each use their own cached **`Texture2D`**, loaded in **`_ready()`** via **`ResourceLoader.load`** ([assets](../game/assets/prototype/terrain/) — see **`PROVENANCE.md`**). **Phase 4.1e:** after the base fill, **`MapView`** draws a **subtle procedural overlay** per hex — low-alpha **specks** and short **strokes** on **PLAINS**, light **ripple lines** on **WATER** — **deterministic** from **`(q, r)`** via **`_terrain_detail_hash`** (**no** runtime RNG); same overlay runs for **textured** and **flat** fallback paths so **readability** stays consistent.
- **Fallback:** If either **`ResourceLoader.load`** fails or the resource is not a **`Texture2D`**, **`MapView`** logs a warning and uses **`draw_colored_polygon(corners, color)`** for the **base** fill (Phase **4.1** colors); **4.1e** **procedural** overlay still draws on top for **PLAINS** / **WATER**.
- **Historical:** Pre-4.1 PLAINS `Color(0.50, 0.78, 0.47)`, WATER `Color(0.20, 0.45, 0.80)`. **Not** final art.

## Phase 4.1c — Prototype painterly terrain textures (implemented)

- **Scope:** **Presentation-only** PNGs for **PLAINS** and **WATER** only — **no** new **`HexMap.Terrain`** values, **no** domain or movement changes.
- **Provenance:** **`game/assets/prototype/terrain/PROVENANCE.md`** — externally generated (**ChatGPT** / image generation); **prototype / replaceable**.

## Phase 4.1d — Terrain texture UV polish (implemented)

- **UV mapping:** **World-anchored** (**corner / `terrain_texture_world_scale`**) replaces per-hex **AABB 0–1** mapping to reduce **per-hex stamp** repetition. **`texture_repeat`** on **`MapView`** for seamless tiling in UV space; hex clip shape unchanged.

## Phase 4.1e — Terrain detail overlay prototype (implemented)

- **Subtle procedural marks** on top of **base** painterly **PLAINS** / **WATER** (**`draw_circle`** + **`draw_line`**, low alpha), **clamped** inside ~**82–85%** of **`HexLayout.SIZE`** from hex center.
- **Determinism:** **`_terrain_detail_hash(q, r, salt)`** only — **no** **`randomize()`** / **`rand_*`**.
- **No** new terrain types, **no** domain changes, **no** unit **occlusion** / **cover** layers (**future** intent in **[VISUAL_DIRECTION.md](VISUAL_DIRECTION.md)** only).

## Optional labels (Phase 1.3)

- Coordinate text on tiles is **optional**; the first implementation may draw **polygons only** to stay robust across Godot versions. If labels are added later, they remain presentation-only and must not become gameplay state.

## Explicitly deferred

- `Camera2D` (pan / zoom), parallax, fit-to-screen.
- **Input** beyond Phase 1.5 unit pick / clear (menus, camera drag, global shortcuts), **hover**, tooltips.
- **TileMap** / `TileSet`, atlases, custom meshes, particles.
- **Animation** (`Tween` / `AnimationPlayer`) for map cells.
- **Theme**, custom **fonts** (other than default).
- Shipped **art** and a **final** terrain palette and accessibility contrast review.

## Phase 1.4b — Unit markers

- **[UnitsView](../game/presentation/units_view.gd)** is a **`Node2D`** **sibling** of **MapView** under **`Main`** in [main.tscn](../game/main.tscn). **Draw order:** **MapView** → **SelectionView** (Phase 1.5) → **UnitsView**, so terrain is bottom, selection overlays mid, markers top. **[main.gd](../game/main.gd)** creates **`GameState`** over the initial **`Scenario`**, **`HexLayout`**, and **`SelectionState`**, assigns **`scenario.map`** and **`layout`** to **MapView**, `scenario` / `layout` / `selection` to **SelectionView** and **UnitsView**, and wires **SelectionController** with **`game_state`**, **`units_view`**, **`selection_view`**, **`layout`**, **`selection`** — so views can follow **`game_state.scenario`** after Phase 1.6 moves (see [ACTIONS.md](ACTIONS.md)).
- **MapView** still derives which hexes to draw and terrain colors from **`HexMap`** (via `coords()` / `terrain_at()`). **UnitsView** derives marker positions, colors, and count **only** from **`Scenario.units()`** through the static **`UnitsView.compute_marker_items(scenario, layout)`** — not from a hand-authored coordinate list. **`compute_marker_items`** includes **`type_id`** (read from domain **`Unit`**, presentation-only). **Phase 4.3f / 4.3i** (current): for **`settler`** / **`warrior`**, **`ResourceLoader.load`** **`Texture2D`** (**true** **RGBA** PNGs) renders as **`draw_texture_rect`** only — **no** runtime **background-keying** for these icons; **no** unit **selection halo**, **no** owner under-circle, **no** rim **rings**. **Selected unit** reads from **`SelectionView`** hex highlight / legal-destination tint (**Phase 1.5**). **Fallback** (unknown **`type_id`**, missing file, failed load): **owner-coloured** filled disk + optional **`type_id`** first-letter **glyph** — **no** rim arc. **`type_id`** remains authoritative. **`main.gd`** still assigns **`units_view.selection`** for API compat; **`SelectionController`** may **`queue_redraw()`** **`UnitsView`** on pick/clear. See **[PHASE_4_3A_MARKER_SET.md](ASSET_REQUEST_PACKS/PHASE_4_3A_MARKER_SET.md)** and **`game/assets/prototype/map_markers/PROVENANCE.md`**.
- **Not in Phase 1.4b (historical note):** movement, **animation**, shipped **sprite** sheets, **labels**, health bars — **gameplay rules** are [SELECTION.md](SELECTION.md) / **Phase 1.5**; **map marker icons** are **static** presentation only (**Phase 4.3b**).

## Phase 4.2 — Unit marker readability (prototype; superseded in part by 4.3f)

- **Historical:** strong **owner** fills, **rim**, **glyph**, **selection halo** — **4.3f** removes **halo / icon rims / under-circle** for textured **`settler`**/**`warrior`**; **selection** is **hex overlay** only. **Fallback** disk retains **owner** fill + **glyph** without rim.

## Phase 4.2a — Map display scale (prototype)

- **`HexLayout.SIZE`** was raised from **32.0** to **64.0** (**Phase 4.2a**), then to **128.0** (**Phase 4.3c** repair — see below). **No** `Camera2D` zoom, **no** pan, **no** domain coordinate changes.
- **Terrain** (`MapView`), **cities** (`CitiesView`), **selection overlay** (`SelectionView`), **unit markers** (`UnitsView`), and **mouse hit-testing** (`SelectionController` radii derived from `HexLayoutScript.SIZE`) all use the same **`HexLayout`** instance from **`main.gd`**, so **alignment is preserved**.

## Phase 4.3b — Prototype map marker icons (wired)

- **Presentation-only** textures under **`game/assets/prototype/map_markers/`** (see **[PHASE_4_3A_MARKER_SET.md](ASSET_REQUEST_PACKS/PHASE_4_3A_MARKER_SET.md)** and **`PROVENANCE.md`** in that folder). **Static map marker icons** only — **not** unit **sprite** sheets or animation.
- **Load path (Phase 4.3i):** **`CitiesView`** / **`UnitsView`** — **`ResourceLoader.load`** **`Texture2D`** for **`city_marker.png`**, **`unit_settler_marker.png`**, **`unit_warrior_marker.png`** (**true** **RGBA**, **no** **`MarkerTextureUtil`** keying for these). **[marker_texture_util.gd](../game/presentation/marker_texture_util.gd)** remains for **legacy** **RGB** sources if needed elsewhere; **not** used for the three approved marker paths.
- **Scale:** icon **height** is a **ratio** of pointy-top hex height (**`2 × HexLayout.SIZE`**): **city** default **`city_icon_height_ratio` ≈ 0.90**; **unit** default **`unit_icon_height_ratio` ≈ 0.70** (**Phase 4.3f**) — tune in editor or code; sources are **512×512**, drawn smaller in world space.
- **Filtering / minification (4.3h / 4.3i):** **`texture_filter`** **`TEXTURE_FILTER_LINEAR_WITH_MIPMAPS`** on **`UnitsView`** / **`CitiesView`**; **only** the three marker **`.import`** files set **`mipmaps/generate=true`** — **terrain** imports unchanged.
- **Hit-testing:** **`SelectionController`** still uses **`HexLayout`** and **`marker_hit_radius_ratio`**; scales with **`SIZE`**.

## Phase 4.3c — Map scale + marker alpha repair (implemented)

- **`HexLayout.SIZE`**: **64.0 → 128.0** — global hex/spacing/hit-test scale (**not** icon-ratio-only tuning).
- **`MapView.hex_tile_size`** export default **128.0** (editor hint; draw path uses **`layout`**).

## Phase 4.3d — Viewport fit + marker size polish (implemented)

- **`project.godot`** **`[display]`**: prior default **`1600×1000`** before **4.3f** (see below).
- **Marker ratios** (historical): **`city_icon_height_ratio`** **0.80**; **`unit_icon_height_ratio`** **0.60**.

## Phase 4.3f — Play-area size + marker detail polish (implemented)

- **`project.godot`**: **`viewport`** **2400×1500** (**1.5×** the **1600×1000** **4.3d** baseline) — more default **play area**, **not** `Camera2D` / zoom.
- **`unit_icon_height_ratio`** default **0.70**; **`city_icon_height_ratio`** default **0.90**.
- **Clean markers:** **UnitsView** / **CitiesView** textured paths = **`draw_texture_rect`** only (**no** circular **frames**, **no** unit **selection halo**); **SelectionView** hex highlight remains **selected-state** read.

## Phase 4.3g — Map layer origin / top padding (implemented)

- **[main.gd](../game/main.gd)** **`MAP_LAYER_ORIGIN`** (`Vector2(400, 428)`) — **`+128`** screen **Y** vs prior **`(400, 300)`** so the top hex row clears the viewport top; applied in **`_ready()`** to **`MapView`**, **`CitiesView`**, **`SelectionView`**, **`UnitsView`**, and **`SelectionController`** so **draw** and **`to_local(mouse)`** hit-tests share one **origin**. **Not** `Camera2D` / zoom / domain coords; **`HexLayout.SIZE`**, **viewport** **2400×1500**, and marker ratios unchanged.

## Phase 4.5a — Shared map-layer tilt scale + unit foot anchoring (implemented)

- **[main.gd](../game/main.gd)** **`MAP_LAYER_TILT_Y`** **`0.85`** — **`Vector2(1.0, MAP_LAYER_TILT_Y)`** applied in **`_ready()`** to the same five nodes as **`MAP_LAYER_ORIGIN`**. **`Main`** has **no** extra scale (no double transform). **[main.tscn](../game/main.tscn)** mirrors **`scale = Vector2(1, 0.85)`** on those nodes so the editor preview matches runtime.
- **`HexLayout`**, **domain**, **`hex_to_world`**, terrain, and **`MAP_LAYER_ORIGIN`** are unchanged; tilt is **presentation-only**.
- **[units_view.gd](../game/presentation/units_view.gd)** **`unit_icon_foot_offset_ratio`** default **`0.20`** — for **textured** unit icons only, the rect is **foot-anchored**: `foot_y = world.y + HexLayout.SIZE * ratio`, `Rect2(world.x - icon_side*0.5, foot_y - icon_side, icon_side, icon_side)`. **City** markers stay **centered**; **fallback** disk path and **marker sizes** unchanged.

## Phase 4.5b — Map-plane projection (design checkpoint; not implemented)

**Status:** **documentation-only** — **no** code, scenes, assets, imports, or domain changes in this checkpoint.

**Live review:** **`4.5a`** **unit foot anchoring** is **approved** and **must be preserved** in future work. The shared **`Node2D`** **`MAP_LAYER_TILT_Y`** scale is **accepted only** as **temporary** vertical compression / **flattening** of the whole map subtree — **not** a convincing **receding plane** or true faux perspective.

**Intended direction:** Replace reliance on **uniform Y squash** (alone) with a **single canonical** **presentation-space** **map-plane projection** shared by:

- **Forward** mapping: **`HexLayout`** **layout / world** coordinates (from **`hex_to_world`** and derived geometry) → **screen / presentation** positions used for **draw**.
- **Inverse** mapping: **same** math inverted for **`SelectionController`** / **hit-testing** so pointer checks stay aligned with drawn **hex** geometry (**one math path** — no per-layer ad hoc offsets).

**Consumers of that path (future implementation):** **`MapView`** **terrain** (hex corners, fills, procedural overlay), **`SelectionView`** **rings and destination fills**, **`UnitsView`** **anchors**, **`CitiesView`** **centers**, and **picking**. **Gameplay**, **`HexLayout.SIZE`**, **`hex_to_world`** formulas, and **domain content** stay **unchanged**; projection is **presentation-only**.

**Units:** Keep **foot / base** definition in **layout / world** space (**`4.5a`** **`unit_icon_foot_offset_ratio`** semantics), then apply the **forward** map projection to the **foot anchor** (and any billboard placement derived from it). **Prefer** drawing **unit** marker textures as **upright** **billboards** **without** inheriting map-plane **vertical squash**, so icons stay **readable** while the **terrain plane** reads **tilted** / **receding** (exact node/layout approach **TBD** at implementation).

**Cities:** **May** stay **center**-anchored markers as today, or gain a **dedicated** placement rule **later** — **no** mandate in this checkpoint.

**Layering (future, not this checkpoint):** **Terrain** **base / back** → **unit** **billboard** → **optional** **foreground** terrain **occluder** (e.g. cover / forest) for **readability-safe** overlap. **Do not** implement **forest / cover / occlusion** as part of **`4.5b`**.

**Out of scope for this design checkpoint:** **`Camera2D`**, **zoom**, **pan**, **real 3D**, **new** terrain types, **domain** or **content** changes.

## Phase 4.3h — Marker texture filtering polish (implemented)

- **Historical:** **`TEXTURE_FILTER_LINEAR`** first — superseded for markers by **4.3i** **`LINEAR_WITH_MIPMAPS`** + marker-only **mipmaps**.

## Phase 4.3i — True-alpha marker adoption + sharp downscale (implemented)

- **Assets:** **512×512** **PNG** **RGBA** (color type **6**), transparent background — verified before adoption (corners **a=0**, non-uniform alpha in image).
- **Loading:** Direct **`Texture2D`** via **`ResourceLoader.load`** in **`UnitsView`** / **`CitiesView`**; **no** **`MarkerTextureUtil`** for city/settler/warrior.
- **Import:** **`mipmaps/generate=true`** **only** on the three **`map_markers/*.png.import`** files; **`MapView`** / terrain **unchanged**.
- **Draw:** **`texture_filter = TEXTURE_FILTER_LINEAR_WITH_MIPMAPS`** on **`UnitsView`** / **`CitiesView`** for **`draw_texture_rect`** marker paths.

## Phase 4.3j — Prototype asset import quality standard (documentation)

- **Steering only** — codifies lessons from **4.3i** for **all** future **scaled** prototype rasters. Full policy: **[VISUAL_DIRECTION.md](VISUAL_DIRECTION.md)** — **Prototype raster import quality standard**.
- **Expectations in code paths:** **Approved** **RGBA** map markers → **`ResourceLoader.load`** **`Texture2D`**; **no** runtime keying **`MarkerTextureUtil`** for those paths; **`[marker_texture_util.gd](../game/presentation/marker_texture_util.gd)`** remains **legacy / RGB fallback** only.
- **Import / filter:** Category-specific — map markers use **per-asset** **`.import`** **mipmaps** + **`TEXTURE_FILTER_LINEAR_WITH_MIPMAPS`** on **`UnitsView`** / **`CitiesView`** only; **terrain** textures keep their **own** import and **`MapView`** defaults.
- **Verification** (when transparency is required): confirm **dimensions**, **PNG RGBA / color type 6**, **corner alpha** where applicable, **alpha** not **globally opaque**; reject **RGB** masquerading as transparent unless the **Asset Request Pack** documents an exception.
- **Gameplay** still **must not** depend on pixels; **`PROVENANCE.md`** continues to record source, date, prototype status, and import notes.

## Phase 1.5 — Selection overlay

- **[SelectionView](../game/presentation/selection_view.gd)** is a **`Node2D`** sibling **between** **MapView** and **UnitsView** (see [main.tscn](../game/main.tscn)): terrain → **destination tint fills + selected-hex ring** → unit markers. Overlays are computed by **`SelectionView.compute_overlay_items(scenario, layout, selection)`**, which uses **`MovementRules.legal_destinations`**; **no** parallel coordinate list.
- **[SelectionController](../game/presentation/selection_controller.gd)** handles **`_unhandled_input`**: when a unit is selected, **legal-destination** hit-test runs **before** unit-marker hit-test so overlapping markers do not block moves. Submits **`MoveUnit`** via **`GameState.try_apply`**; **`push_warning`** on reject. Re-points **`UnitsView`** / **`SelectionView`** after accept. See [SELECTION.md](SELECTION.md), [ACTIONS.md](ACTIONS.md).
- Destination hexes use a **translucent fill**; the **selected** cell uses a **closed polyline** ring (built from hex corners + closing vertex). **No** animation or shipped assets.

## Phase 1.6 — MoveUnit and refreshed views

- After an **accepted** **`MoveUnit`** via **`GameState.try_apply`**, **`SelectionController`** re-points **`UnitsView.scenario`** and **`SelectionView.scenario`** to **`game_state.scenario`** and **`queue_redraw()`**; markers jump to the new hex (no tween). See [ACTIONS.md](ACTIONS.md) and [SELECTION.md](SELECTION.md).

## Phase 1.7 — Turn label

- **`TurnLabel`** ([turn_label.gd](../game/presentation/turn_label.gd)) is a **`Label`** child of **`Main`** (renamed from the placeholder label in [main.tscn](../game/main.tscn)). Text is **`Turn N — Player P`** from **`compute_text(game_state)`**; **`main.gd`** assigns **`game_state`** and calls **`refresh()`** at startup. **`SelectionController`** and **`EndTurnController`** call **`refresh()`** after accepted actions so the HUD tracks **`TurnState`** (see [TURNS.md](TURNS.md)).

## Phase 1.8 — AI turn trigger

- **`AITurnController`** ([ai_turn_controller.gd](../game/presentation/ai_turn_controller.gd)) is a **`Node2D`** **last** child of **`Main`** (after **`EndTurnController`**) in [main.tscn](../game/main.tscn): **`KEY_A`** (no echo) calls **`LegalActions.for_current_player`**, **`RuleBasedAIPlayer.decide`**, then **`game_state.try_apply`** once. On accept it **clears selection**, re-points **`selection_view.scenario`** and **`units_view.scenario`**, **`queue_redraw()`**, **`turn_label.refresh()`**. See [AI_LAYER.md](AI_LAYER.md), [ACTIONS.md](ACTIONS.md).

## Phase 1.9 — Action log debug view

- **`LogView`** ([log_view.gd](../game/presentation/log_view.gd)) is a **`Label`** child of **`Main`**. **Phase 4.4a:** **[main.tscn](../game/main.tscn)** places it in the **lower HUD band** (approx. **y 1220–1475**, **w ~1160**, **left 20** on the default **2400×1500** viewport) so it **does not** overlap the **hex map** (which sits around **`MAP_LAYER_ORIGIN`** **y ~428** with **~±320** vertical span for the tiny test map) or **`TurnLabel`** (**~y 20–100**). It shows the **last `MAX_ENTRIES` (10)** accepted log lines via **`compute_text(game_state)`**, **oldest at top, newest at bottom**; it reads only **`game_state.log.size()`** and **`game_state.log.get_entry(i)`** and **never mutates** domain state. **`main.gd`** assigns **`game_state`** and calls **`refresh()`** once at startup. **`SelectionController`**, **`EndTurnController`**, and **`AITurnController`** call **`log_view.refresh()`** after each **accepted** action ( **`log_view`** is optional — **null-safe**). **`format_entry`** covers **`move_unit`**, **`end_turn`**, **`found_city`**, **`set_city_production`**, engine **`production_progress`**, and engine **`unit_produced`**. After **accepted** **`EndTurn`**, refreshed views reflect **delivered** units (**Phase 2.4c**). This is a **debug** surface only: **no** replay, **no** undo/redo, **no** polling or **`_process`** (see [ACTIONS.md](ACTIONS.md)).

## Phase 2.1 — City placeholder markers

- **`CitiesView`** ([cities_view.gd](../game/presentation/cities_view.gd)) is a **`Node2D`** sibling **after** **`MapView`** and **before** **`SelectionView`** in [main.tscn](../game/main.tscn). **Draw order:** **terrain → cities → selection overlay → unit markers** ( **`UnitsView`** remains topmost among map-layer siblings). Cities are derived from **`Scenario.cities()`** via **`compute_marker_items`**. **Phase 4.3f:** when **`city_marker.png`** loads, **centered `draw_texture_rect` only** (no owner/dark rings). **Fallback:** **filled diamond** + outline. **Not** final art; see **[PHASE_4_3A_MARKER_SET.md](ASSET_REQUEST_PACKS/PHASE_4_3A_MARKER_SET.md)**.
- The canonical **`make_tiny_test_scenario()`** has **zero** cities; **`CitiesView`** is wired so **Phase 2.2+** can show markers without scene churn. Domain and tests use explicit **`City`** lists where needed (see [CITIES.md](CITIES.md)).
- **No** **`FoundCity`**, **no** **`try_apply`** changes, **no** controller re-point of **`CitiesView`** in this subphase.

## Phase 2.2b — FoundCity input and CitiesView refresh

- **`SelectionController`** handles **`KEY_F`** (pressed, non-echo): if a **unit** is **selected**, builds **`FoundCity.make`** from **`game_state.scenario`** and submits via **`game_state.try_apply`**. On **accept**, **clears selection** and re-points **`units_view`**, **`selection_view`**, optional **`cities_view`**, **`queue_redraw()`**, **`turn_label.refresh()`**, **`log_view.refresh()`**; **`cities_view`** stays **null-safe** (optional / not required for headless tests or default startup wiring beyond [main.gd](../game/main.gd)).
- After **accepted** **`FoundCity`**, **`CitiesView`** must show the **new** city marker at the **founder’s former** hex.

## Phase 2.3 — KEY_P debug (SetCityProduction)

- **`SelectionController`** handles **`KEY_P`** (pressed, non-echo): picks the **lowest-id** **current-player** city with **`current_project == null`** and submits **`SetCityProduction.make(..., "produce_unit")`** via **`try_apply`**. **Does not** clear **selection**; **no** production UI. **`CitiesView`** is **refreshed** only so manual checks stay consistent when wired (markers unchanged — projects are **not** drawn in **CitiesView** this phase). After **Space** **`end_turn`**, **`LogView`** may show **`production_progress`** before **`end_turn`**, and **`unit_produced`** lines **after** **`end_turn`** when delivery runs for the new current player.

## Phase 3.4f — KEY_G debug (`CompleteProgress`)

- **`KEY_G`** (pressed, non-echo) submits **`CompleteProgress`** for the **current player** and hardcoded **`progress_id`** **`foraging_systems`** via **`try_apply`**. On **accept**, **`TurnLabel`** and **`LogView`** **`refresh()`** when wired; **no** **`scenario`** re-point, **no** map/city/unit/selection redraws, **no** **`scene`** changes.

## Phase 3.4h — KEY_H debug (detector candidate)

- **`KEY_H`** (pressed, non-echo): **`ProgressCandidateFilter.for_current_player(game_state)`**, then **`try_apply`** the **first** candidate (detector-driven **`controlled_fire`** when eligible). On **accept**, **`TurnLabel`** and **`LogView`** **`refresh()`** when wired; **no** **`scenario`** re-point, **no** map/city/unit/selection redraws, **no** **`scene`** changes. **`push_warning`** when **no** filtered candidate or **`try_apply`** rejects.
