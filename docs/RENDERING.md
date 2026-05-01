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

- **[main.gd](../game/main.gd)** **`MAP_LAYER_ORIGIN`** (`Vector2(400, 428)`) — **`+128`** screen **Y** vs prior **`(400, 300)`** so the top hex row clears the viewport top; **4.5m:** this **constant** is applied **once** in **`_ready`** to **`MapView`**, **`CitiesView`**, **`SelectionView`**, **`UnitsView`**, **`TerrainForegroundView`**, **`SelectionController`** (**node** **`.position`** **not** mutated after **startup**). **Right-drag** pan updates **`MapCamera.camera_world_offset`** only. **Not** `Camera2D` / zoom; **`HexLayout.SIZE`**, **viewport** **2400×1500**, marker ratios unchanged.

## Phase 4.5a — Shared map-layer tilt scale + unit foot anchoring (historical; superseded by 4.5c)

- **Historical:** **`MAP_LAYER_TILT_Y`** + **`Node2D`** **`scale`** on map siblings (**removed** in **4.5c** in favor of **`MapPlaneProjection`**).
- **Retained (exports):** **`unit_icon_foot_offset_ratio`** (legacy, textured **unused**) / **`city_marker_center_y_offset_ratio`** — **4.5h** **`to_presentation(hex_to_world)`** + **`perspective_scale_at`**; **4.5i** **`unit_marker_pivot_*`** **for** **textured** **unit** **foot** **in** **sprite** **space**; **4.5j** **`_UNIT_MARKER_PIVOT_BY_TYPE`** **only** for **type_id**s **needing** **asset-specific** **pivot** (**e.g.** **`settler`**).

## Phase 4.5b — Map-plane projection (design checkpoint; superseded by 4.5c implementation)

**Status:** **Design checkpoint** documented **`4.5b`**; **implementation** is **Phase 4.5c** below.

**Live review:** **`4.5a`** **unit foot anchoring** is **approved** and **must be preserved** in future work. The shared **`Node2D`** **`MAP_LAYER_TILT_Y`** scale is **accepted only** as **temporary** vertical compression / **flattening** of the whole map subtree — **not** a convincing **receding plane** or true faux perspective.

**Original intended direction:** Replace reliance on **uniform Y squash** (alone) with a **single canonical** **presentation-space** **map-plane projection** shared by:

- **Forward** mapping: **`HexLayout`** **layout / world** coordinates (from **`hex_to_world`** and derived geometry) → **layer-local** presentation positions used for **draw** (offset from **`MAP_LAYER_ORIGIN`**).
- **Inverse** mapping: **same** math inverted for **`SelectionController`** / **hit-testing** so pointer checks stay aligned with drawn **hex** geometry (**one math path** — no per-layer ad hoc offsets).

**Consumers:** **`MapView`** **terrain** (hex corners, fills, procedural overlay), **`SelectionView`** **rings and destination fills**, **`UnitsView`** **anchors**, **`CitiesView`** **centers**, and **picking**. **Gameplay**, **`HexLayout.SIZE`**, **`hex_to_world`** formulas, and **domain content** stay **unchanged**; projection is **presentation-only**.

**Units:** Keep **foot / base** definition in **layout / world** space (**`4.5a`** **`unit_icon_foot_offset_ratio`** semantics), then apply the **forward** map projection to the **foot anchor** (and any billboard placement derived from it). **Prefer** drawing **unit** marker textures as **upright** **billboards** **without** inheriting map-plane **vertical squash**, so icons stay **readable** while the **terrain plane** reads **tilted** / **receding** (exact node/layout approach **TBD** at implementation).

**Cities:** **May** stay **center**-anchored markers as today, or gain a **dedicated** placement rule **later** — **no** mandate in this checkpoint.

**Layering (future):** **Terrain** **base / back** → **unit** **billboard** → **optional** **foreground** terrain **occluder**. **No** **forest / cover / occlusion** in **4.5c**.

**Out of scope:** **`Camera2D`**, **zoom**, **pan**, **real 3D**, **new** terrain types, **domain** or **content** changes.

## Phase 4.5c — Shared map-plane projection (implemented; math superseded by 4.5e)

- **Architecture:** **`[main.gd](../game/main.gd)`** owns one **`MapPlaneProjection`** (**`_map_projection`**) and one **`MapCamera`** (**`_map_camera`**) with **`camera.projection = _map_projection`** (**Phase 4.5m**). **`MapView`**, **`CitiesView`**, **`SelectionView`**, **`UnitsView`**, **`TerrainForegroundView`**, **`SelectionController`** use **`.camera`** (**`MapCamera`**). **`MAP_LAYER_ORIGIN`** + **`scale`** **`Vector2.ONE`**; **`[main.tscn](../game/main.tscn)`** node order unchanged.
- **Historical math:** **4.5c–4.5d** used **affine** **`shear_x_per_world_y`** + **`plane_y_scale`** (**4.5e** replaces with **projective** divide — see **4.5e**).
- **`MapView`**: projects hex **corners** for **`draw_colored_polygon`**; **UVs** from **unprojected** layout corners (**4.1d** **`_world_anchored_corner_uvs`**). **4.5e:** vertices are **projectively** warped while **UVs** stay **layout/world**-anchored — small **non-perspective-correct** interpolation inside each hex is an accepted **prototype** tradeoff (painterly terrain hides most drift).
- **`SelectionView`**: projects overlay **corners** like terrain.
- **`UnitsView` / `CitiesView`**: project anchors; icons **axis-aligned** billboards.
- **`SelectionController`**: **Phase 4.5f:** **`projected_hex_contains`** — **`Geometry2D.is_point_in_polygon`** on **`camera.to_presentation`** **hex** corners in **layer-local** space vs **`to_local(mouse)`** — matches **drawn** cells (**legal** **destinations** and **unit** **hex**). **4.5m:** **`MapCamera.to_layout`** / **`MapPlaneProjection.to_layout`** for pan math in **`main.gd`**.
- **Tests:** **`test_map_plane_projection.gd`**, **`test_map_camera.gd`**; runner **50** scripts.

## Phase 4.5d — Map-plane away-direction tuning (historical; affine shear)

- **4.5d** tuned **`shear_x_per_world_y`** **`0.12` → `-0.10`** for better horizontal drift. **Superseded** by **4.5e** **projective** math (**shear** removed).

## Phase 4.5e — Projective map-plane perspective (implemented)

- **`[map_plane_projection.gd](../game/presentation/map_plane_projection.gd)`** — **presentation-only** **`w = 1 + depth_strength * (near_world_y - world.y)`**, **`scale = 1/w`**, convergence toward **`vanishing_pres`** in **layer-local** space: **`pres = vanishing + (world_scaled - vanishing) * scale`** with **`world.y`** scaled by **`plane_y_scale`** in the **Y** term. **Closed-form** **`to_layout`**. **`shear_x_per_world_y`** **removed**.
- **Exports (defaults):** **`plane_y_scale`** **`0.90`**, **`depth_strength`** **`0.0004`** (**4.5g** mild **Civ6**-like band **`0.0003`–`0.0005`**; **4.5f** was **`0.0010`**, **4.5e** shipped **`0.0015`**), **`near_world_y`** **`192.0`**, **`vanishing_pres`** **`(800, 322)`** — **`[main.gd](../game/main.gd)`** sets **`vanishing_pres = (get_viewport_rect().size * 0.5) - MAP_LAYER_ORIGIN`** so convergence tracks the **visible viewport center**.
- **Singularity:** denominator **`plane_y_scale + dy * depth_strength`** in **`to_layout`** is **outside** normal map coordinates at current **game** constants.

## Phase 4.5f — Perspective tuning + hit-test + anchor polish (implemented)

- **`[map_plane_projection.gd](../game/presentation/map_plane_projection.gd)`** — **`depth_strength`** **`0.0015` → `0.0010`** (milder **recession**); **superseded** by **4.5g** defaults (**`0.0004`**, **`plane_y_scale`** **`0.90`**).
- **`[selection_controller.gd](../game/presentation/selection_controller.gd)`** — **`projected_hex_contains`**: **pick**/**move** targets by **projected** **hex** **polygon** vs pointer (**layer-local**), not layout **center** **radius**.
- **`[units_view.gd](../game/presentation/units_view.gd)`** — **`unit_icon_foot_offset_ratio`** **`0.20` → `0.24`**; **4.5h** / **4.5i:** **`anchor_pres`** + **`perspective_scale_at`**; **4.5i** / **4.5j** / **4.5k:** textured **pivot** from **`unit_marker_pivot_*`** with **`_UNIT_MARKER_PIVOT_BY_TYPE`** (**settler** **`y`** **`0.86`**).
- **`[cities_view.gd](../game/presentation/cities_view.gd)`** — **`city_marker_center_y_offset_ratio`** **`0.05`** in **4.5f** (**4.5g+**: default **`0.0`**, not used in **`_draw`** for textured path).

## Phase 4.5g — Civ6-like mild perspective + marker scale (implemented)

- **`[map_plane_projection.gd](../game/presentation/map_plane_projection.gd)`** — **`depth_strength`** **`0.0004`** (tuning band **`0.0003`–`0.0005`**); **`plane_y_scale`** **`0.90`**; **`perspective_scale_at`**. **4.5g** briefly shipped **`projected_hex_centroid_pres`** (**removed** in **4.5h**).
- **`[units_view.gd](../game/presentation/units_view.gd)`** / **`[cities_view.gd](../game/presentation/cities_view.gd)`** — upright **`draw_texture_rect`**: **`icon_side * perspective_scale_at(world_center)`**; **`anchor_pres = camera.to_presentation(layout.hex_to_world(q,r))`**. **Unit (textured):** **4.5i** **`unit_marker_pivot_*`** defaults; **4.5j** **per-** **`type_id`** **overrides** **only** **where** **art** **differs** — **hex** **center** = **foot/contact** **inside** **sprite** (**city** still **centered** on **`anchor_pres`**).
- **Picking:** unchanged **projected** hex **polygon** test (**[selection_controller.gd](../game/presentation/selection_controller.gd)**).

## Phase 4.5h — Projected top-view hex center marker anchoring (implemented)

- **`[units_view.gd](../game/presentation/units_view.gd)`** / **`[cities_view.gd](../game/presentation/cities_view.gd)`** — markers **anchored** at **`to_presentation(hex_to_world)`**, **not** **centroid** of **projected** corner polygon.
- **`[map_plane_projection.gd](../game/presentation/map_plane_projection.gd)`** — **`projected_hex_centroid_pres`** **removed** as **unused**.

## Phase 4.5i — Unit marker foot-pivot anchoring (implemented)

- **`[units_view.gd](../game/presentation/units_view.gd)`** — **`unit_marker_pivot_x_ratio`** / **`unit_marker_pivot_y_ratio`**: **layout** **hex** **center** (**`to_presentation(hex_to_world)`**) maps to **contact** point **inside** the **square** **marker** (defaults **`0.50`**, **`0.90`** — **center**-**X**, **near** **bottom** **but** **above** **frame**). **`draw_texture_rect`** origin **`anchor_pres - (side × pivot)`**.
- **Fallback** circle/glyph: still **centered** on **`anchor_pres`** (**legacy**).

## Phase 4.5j — Per–**type_id** pivot overrides (implemented)

- **`[units_view.gd](../game/presentation/units_view.gd)`** — **`_UNIT_MARKER_PIVOT_BY_TYPE`**: **sparse** **`Dictionary`** keyed by **`type_id`** (**same** **strings** **as** **texture** **lookup**); **settler** **`Vector2(0.50, 0.86)`**; **missing** **keys** **use** **`unit_marker_pivot_*`** **exports**.

## Phase 4.5k — Settler pivot fine-tune (implemented)

- **`[units_view.gd](../game/presentation/units_view.gd)`** — **settler** **`pivot_y`** **`0.88` → `0.86`** (**4.5k**).

## Phase 4.5l — Larger prototype map + right-drag pan (implemented; screen-space pan superseded by **4.5m**)

- **`[hex_map.gd](../game/domain/hex_map.gd)`** — **`make_prototype_play_map()`**: axial disk **R** = **5**, **91** cells, **(-1,0)** **WATER**; **`make_tiny_test_map()`** unchanged (**7** cells, tests).
- **`[scenario.gd](../game/domain/scenario.gd)`** — **`make_prototype_play_scenario()`** for **editor** play; headless tests keep **`make_tiny_test_scenario()`**.
- **Historical (pre-4.5m):** **`[main.gd](../game/main.gd)`** used **`_map_layer_pos`** and **`mm.relative`** so layers **slid** in **viewport** space; **`vanishing_pres`** tracked **`viewport_center - _map_layer_pos`**.

## Phase 4.5m — Plane-space pan (**MapCamera**; implemented)

- **[map_camera.gd](../game/presentation/map_camera.gd)** — **`MapCamera`** wraps **`MapPlaneProjection`**, **`camera_world_offset`**, and (**4.5n**) **`zoom`** / **`set_zoom_clamped`**. **Pan** ( **`4.5m`** ) and **zoom** ( **`4.5n`** ) both use **`vanishing_pres`** as the **layer-local** **scale** **anchor**. **`MapPlaneProjection`** **math** **unchanged**. Full **`to_presentation` / `to_layout` / `perspective_scale_at`** **semantics**: see **4.5n** below.
- **`[main.gd](../game/main.gd)`** — Builds **`_map_projection`**, sets **`vanishing_pres`** **once** in **`_ready`** to **`(get_viewport_rect().size * 0.5) - MAP_LAYER_ORIGIN`** (**independent** of pan **or** map zoom). Instantiates **`_map_camera`**, assigns **`_map_camera.projection`**, wires **`.camera = _map_camera`** on **`MapView`**, **`CitiesView`**, **`SelectionView`**, **`UnitsView`**, **`TerrainForegroundView`**, **`SelectionController`**. Map nodes **`position = MAP_LAYER_ORIGIN`** once; **`_redraw_map_layers()`** **`queue_redraw()`**s drawing views only.
- **Right-drag:** layer-local pointer samples via **`MapView.to_local(mm.global_position)`** and **`to_local(mm.global_position - mm.relative)`** (same space as **`SelectionController.to_local(get_global_mouse_position())`**). **`camera_world_offset += prev_world - cur_world`** where **`prev_world` / `cur_world`** = **`_map_camera.to_layout(prev_local / cur_local)`**, preserving the **world** point under the cursor (**not** **`cur_world - prev_world`** — that inverts the grab invariant for this projection).
- **Deferred (still):** **`Camera2D`**, **inertia**, **bounds**, **keyboard** pan — **not** covered here. **Map zoom** is **4.5n** (**mouse** **wheel** only).

## Phase 4.5n — Center-anchored **MapCamera** zoom (implemented)

- **Model:** **Uniform** **layer-local** **scale** **around** **`MapPlaneProjection.vanishing_pres`** (same point **`main.gd`** sets to **viewport** **center** **−** **`MAP_LAYER_ORIGIN`**). **Civ-like** **center-anchored** **zoom:** **mouse** **wheel** **does** **not** **use** **cursor** **position**; **`center_local = get_viewport_rect().size * 0.5 - MAP_LAYER_ORIGIN`**. After **`set_zoom_clamped`**, **`camera_world_offset += world_before - world_after`** with **`world_* = _map_camera.to_layout(center_local)`** so the **world** **under** **the** **visible** **center** **stays** **fixed** even **if** **`vanishing_pres`** **and** **`center_local`** ever **diverge**.
- **[map_camera.gd](../game/presentation/map_camera.gd):** **`zoom`** (default **1.0**), **`min_zoom` / `max_zoom`** (**0.5** … **2.5**), **`set_zoom_clamped`**. **`to_presentation`:** **`p = projection.to_presentation(world - offset)`** → **`vanishing + (p - vanishing) * zoom`**. **`to_layout`:** **`unzoomed = vanishing + (local - vanishing) / max(zoom, 0.0001)`** → **`projection.to_layout(unzoomed) + offset`**. **`perspective_scale_at`:** **`projection.perspective_scale_at(world - offset) * zoom`** so **markers** / **cities** / **forest** **occluder** **sizes** **track** **zoom** **without** **per-view** **code**.
- **[main.gd](../game/main.gd):** **`ZOOM_STEP`** (**1.10**); **`InputEventMouseButton`** **`WHEEL_UP` / `WHEEL_DOWN`** in **`_input`** (**pressed**); **`old_zoom`** **guard** **skips** **offset** **when** **clamp** **blocks** **change**; **`set_input_as_handled`** so **wheel** **does** **not** **reach** **gameplay** **or** **`_unhandled_input`**. **`vanishing_pres`** **not** **updated** **after** **`_ready`**.
- **Not** in **this** **phase:** **mouse-anchored** **zoom**, **`Camera2D`**, **zoom** **animation** / **inertia**, **map** **extent** **clamping**, **resize** **recalc** **of** **`vanishing_pres`**.

## Phase 4.6a — Terrain layering + forest visual model (design checkpoint; documentation only)

- **Scope:** **4.6a** **itself** was **documentation-only** — it recorded the **terrain layering** model and **4.6b** boundaries before implementation land. It did **not** add code or **`Terrain.FOREST`**.

## Phase 4.6b — Visual-only prototype forest overlays on PLAINS (implemented)

- **Scope:** **Presentation-only** — **decoration** on existing **`HexMap.Terrain.PLAINS`** cells only; **not** **`Terrain.FOREST`**, **not** movement / combat / vision rules, **no** domain / content / scenario semantics, **no** new assets or **PNG** imports. **MapPlaneProjection** constants and **formulas**, **right-drag** **panning** (**4.5m** **plane** **offset**), **mouse-wheel** **zoom** (**4.5n** **center**-**anchored**), **projected** **polygon** **picking**, and **marker** placement / pivots / scaling follow **4.5c** / **4.5m** / **4.5n** / **4.5x**.
- **Draw / input order** (**[main.tscn](../game/main.tscn)** under **`Main`**, map layers at **`MAP_LAYER_ORIGIN`**; pan = **`MapCamera.camera_world_offset`**; zoom = **`MapCamera.zoom`**):
  1. **[MapView](../game/presentation/map_view.gd)** — terrain hex polygons (unchanged **4.1d** UVs), **4.1e** procedural detail, then **4.6b** **back** canopy / clumps on **deterministically selected** PLAINS hexes (**after** detail, still under other map views).
  2. **[CitiesView](../game/presentation/cities_view.gd)**
  3. **[SelectionView](../game/presentation/selection_view.gd)**
  4. **[UnitsView](../game/presentation/units_view.gd)**
  5. **[TerrainForegroundView](../game/presentation/terrain_foreground_view.gd)** — on **decorated** **PLAINS**: **always** **terrain-owned** foreground clumps (**stable** per hex); **if** **`enable_unit_occlusion_test`**: **additional** unit-anchored occluder when **units** present and **no** **city** (**not** a replacement — **4.6d**); **no** **`_input`**.
  6. **[SelectionController](../game/presentation/selection_controller.gd)** — hit-test / input only; **no** draw.
  7. **HUD** — **`TurnLabel`**, **`LogView`**, etc.
- **Shared gate:** **[plains_forest_decoration.gd](../game/presentation/plains_forest_decoration.gd)** — **`is_plains_forest_decorated(q, r, density_ratio)`** and **`cell_mix(q, r, salt)`** (same polynomial family as **`MapView._terrain_detail_hash`**; **no** RNG). **`[main.gd](../game/main.gd)`** assigns **`TerrainForegroundView.forest_density_ratio` from** **`MapView.forest_density_ratio`**, **`scenario`**, and **`foreground_unit_reference_height_ratio`** from **`UnitsView`** at startup so **back** and **foreground** gates match (**density** default **0.25**). **4.6c:** **`terrain_foreground_view`** wired to **controllers** for **scenario**/**map** sync and **redraw** after accepted actions.
- **4.6b-debug (visibility + wiring):** **`[main.gd](../game/main.gd)`** assigns **`TerrainForegroundView.camera = _map_camera`** — **same** **`MapCamera`** (**shared** **`MapPlaneProjection`**) as **`MapView`** / markers — so **pan** stays **aligned** (**foreground** must **not** rely on a one-off default **`MapPlaneProjection`** in **`_draw()`**). **`MapView.forest_back_opacity`** (default **1.0**) scales **back** forest alpha only; **`TerrainForegroundView.forest_front_opacity`** scales **front** alpha. Optional **`TerrainForegroundView.forest_debug_log_counts_once`** prints **one** line (**PLAINS** count, **decorated** count, density, front opacity) for diagnosis — **off** by default.
- **4.6b-polish (silhouette read):** **`MapView`** draws **2–3** **canopy** **clusters** per decorated hex — **few** **overlapping** **large** circles plus an optional **skewed** **quad** in **presentation** space so mass reads as **woodland** **silhouette**, not **grass** **speckle**. **`TerrainForegroundView`** draws **1–2** **front** **bushes** from **layered** circles and a **triangular** **olive** mass, placed **lower-front** but **slightly** **inward** from the hex bottom so clumps stay **visible** vs **unit** **feet**. Default **`forest_front_opacity`** **0.72**. **No** thin **stroke** **noise** on these layers.
- **4.6c (unit-aware foreground occluder — layering test):** **`TerrainForegroundView`** holds **`Scenario`** (**read-only**) for **`units_at`** / **`cities_at`**. **4.6d:** **Terrain-owned** **`_draw_plains_forest_front`** runs **first** on **every** **decorated** **PLAINS** hex **independent** of **unit**/ **city** occupancy. **If** **`enable_unit_occlusion_test`** (**default** **true**) **and** **≥1** **unit** **and** **no** **city**, **`_draw_unit_forest_occluder`** draws **after** as an **extra** **test** overlay (does **not** replace hex bushes). **Long-term** model stays **terrain**/ **hex**-**owned** foreground. **Unit** mass: **`anchor_pres`**, **`side`** = **`2 × HexLayout.SIZE × foreground_unit_reference_height_ratio × perspective_scale_at`** (**`main.gd`** syncs ratio from **`UnitsView`**); **`unit_occluder_*`** exports. **Not** **`Terrain.FOREST`**, **not** **rules**. **`SelectionController`** / **`EndTurnController`** / **`AITurnController`**: **`terrain_foreground_view`** sync (**picking** unchanged).
- **Future:** **Raster** forest / terrain overlays remain **deferred**; if added, **Phase 4.3j** (**true RGBA PNG**, transparency, scoped **`.import`** / filtering, mipmaps where appropriate, **provenance**). **Further** split of **terrain** into separate base/back nodes is **steering** only until a later phase.

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
