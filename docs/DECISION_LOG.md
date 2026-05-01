## 2026-05-01 — Phase 4.5m — **MapCamera** plane-space pan (replaces **4.5l** screen-layer pan)

Decision:

- **`MapCamera`** (**`map_camera.gd`**) wraps **`MapPlaneProjection`** + **`camera_world_offset`**; views / **`SelectionController`** use **`camera.to_presentation`** / **`to_layout`** / **`perspective_scale_at`**. **`main.gd`:** **`vanishing_pres`** set **once** in **`_ready`** to **`viewport * 0.5 - MAP_LAYER_ORIGIN`**; map nodes **`position = MAP_LAYER_ORIGIN`** once; right-drag updates **`camera_world_offset`** from **layer-local** **`MapView.to_local`** samples (**grab** invariant: **`offset += prev_world - cur_world`**).

Rationale:

- **4.5l** panned by **moving** **Node2D** **layers** — the **projected** image **slides** as a **flat** **composite**. **4.5m** pans in **layout** **space** **before** **projection** so **recession** / **scale** **update** during drag.

Caveat:

- **No** **`Camera2D`**, **zoom**, **bounds**, **inertia** in **4.5m**; **window** **resize** does **not** **recompute** **`vanishing_pres`** after **`_ready`** (**unchanged** from **4.5m** **scope**).

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
