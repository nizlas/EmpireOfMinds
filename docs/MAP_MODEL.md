# Empire of Minds — Domain map model (Phase 1.2)

Hex cell addressing uses axial coordinates; see [HEX_COORDINATES.md](HEX_COORDINATES.md) for `(q, r)` and neighbor directions. This document only describes the **map container** in Phase 1.2.

## Representation

- **`HexMap`** (domain, `class_name` in [game/domain/hex_map.gd](../game/domain/hex_map.gd)) holds a **finite** set of hexes that exist in play.
- **API boundary:** queries use [HexCoord](HEX_COORDINATES.md) (`q`, `r`).
- **Storage:** internal dictionary keys are `Vector2i(q, r)` (value-typed) → terrain enum value. This avoids identity-based lookup bugs with `RefCounted` keys.
- **Landforms:** a parallel optional dictionary `_landforms` maps the same keys to `HexMap.Landform`. Omitted keys default to **`FLAT`**.
- **Woods overlay (Phase 5.1.16c):** optional parallel dictionary **`_woods`** (same **`Vector2i`** keys → **`true`**). **`HexMap.has_woods(HexCoord)`** is **only** valid when **`has`** is true. The **prototype play map** copies keys from **`PrototypeTerrainFeatures.prototype_woods_set()`** — the same list **`plains_forest_decoration.gd`** re-exports for the forest **decoration** pass; **woods** affects **`CityYields`** (v0) but is **not** a **`Terrain`** enum variant.

## Terrain (tag-only in Phase 1.2)

`HexMap.Terrain` is a minimal inline enum: `PLAINS`, `WATER`, **`GRASSLAND` (2)** — append-only so existing numeric values stay stable. Values are **tags** only in **`HexMap`** (no per-cell gameplay fields here). **Phase 3.2:** **[TerrainRuleDefinitions](../game/domain/content/terrain_rule_definitions.gd)** holds **passability** and **`movement_cost`** metadata keyed by stable ids **`plains`** / **`water`** / **`grassland`** mapped from this enum. **`movement_cost`** does **not** expand move range yet—still one step per [MOVEMENT_RULES.md](MOVEMENT_RULES.md).

## Landform (visual / data-only)

`HexMap.Landform`: **`FLAT`**, **`HILLS`**. **Passability, movement cost, combat, vision, and yields** do **not** depend on landform in the current slice. **`HILLS`** is stored for presentation only: **[MapView](../game/presentation/map_view.gd)** draws a **local alpha overlay decal** per **PLAINS** / **GRASSLAND** hill hex on top of the normal base terrain texture. **`Landform`** is available for future rules.

## Presentation note (MapView base terrain, repo)

**Base** textured land is chosen by **`HexMap.Terrain`** only: **`plains_painterly`**, **`grassland_painterly`**, **`water_painterly`**. **`Landform.HILLS`** does **not** swap the base texture. Instead, **[MapView](../game/presentation/map_view.gd)** draws a second **`draw_colored_polygon`** pass with **hills overlay decals** — hex-centered, **scaled inside** the hex (**`hills_overlay_scale`**, default **1.0**, changes **on-screen polygon size**), **hex-local UVs** from the same center (**UV zoom does not cancel polygon scale**; a larger scale still draws a larger shape). Optional **`hills_overlay_uv_zoom`** (default **1.24**) recenters UVs toward **(0.5, 0.5)** in texture space — **> 1** zooms **into** the PNG (helps if the art has wide transparent margins). Tinting uses **`plains_hills_terrain_modulate`** / **`grassland_hills_terrain_modulate`** (RGB clamp ~0.75–1.25); alpha uses per-terrain **`plains_hills_overlay_opacity`** (default **0.45**) and **`grassland_hills_overlay_opacity`** (default **0.40**).

**Overlay PNG variants (presentation):** **`MapView`** loads optional numbered files **`plains_hills_overlay_1.png`** through **`plains_hills_overlay_4.png`** and **`grassland_hills_overlay_1.png`** … **`_4.png`** from **`game/assets/prototype/terrain/`** when present. If **no** numbered file loads for a family, it falls back to the legacy single files **`plains_hills_overlay.png`** / **`grassland_hills_overlay.png`**. Each **HILLS** hex picks one loaded variant **deterministically** from **(q, r)** and **`HexMap.Terrain`** via a **fixed integer hash** (no RNG): the same cell always gets the **same** variant across redraws, pan/zoom, and restarts; neighbors usually differ. If **no** texture loads for that family, the overlay is skipped (**one-time editor warning**).

Overlays should be **alpha relief** art (highlights/shadows); repo copies may be flattened placeholders until final art lands. **FLAT** land uses **world-anchored UVs** on the base quad (continuous ground). **No** shader, **no** subdivision, **no** seam-fix layer. Full **`plains_hills_painterly`** / **`grassland_hills_painterly`** files may remain in **`game/assets/prototype/terrain/`** as **deprecated / unused** prototype art.

Presentation-only: modulation and overlay draws are **not** stored in **`HexMap`** or **`TerrainRuleDefinitions`**. **`debug_hills_overlay_draws`** counts overlay draws per **`MapView._draw`** (prototype / headless diagnostics). **`debug_draw_hills_overlay_bounds`** (default off) outlines the **scaled overlay** vs **full hex** after each overlay draw for art/layout review.

When **`debug_map_presentation_audit`** is on, **`MapView`** prints a single **`[EOM_MAP_PRESENTATION_AUDIT]`** line per frame (prototype instrumentation; default off) including **`hills_overlay_scale`**, **`plains_hills_overlay_opacity`**, **`grassland_hills_overlay_opacity`**, **`hills_overlay_uv_zoom`**, shared **`effective_scale`** / **`effective_uv_zoom`**, per-terrain **`effective_opacity_plains`** / **`effective_opacity_grassland`**, **`debug_force_hills_overlay_extreme`**, **`plains_hills_overlay_variants_loaded`**, **`grassland_hills_overlay_variants_loaded`**, **`hills_overlay_draws`**, and forest/back-layer counters. **`debug_mapview_forest_pipeline_log`** gates MapView **`[EOM_DEBUG_FOREST_PIPELINE]`** / **`[EOM_DEBUG_FOREST_GRID]`** console lines (default off) so the editor is not slowed by per-frame logging.

**Prototype play map only:** **[main.gd](../game/main.gd)** may pass a **`forest_decoration_override`** hex set into **[MapView](../game/presentation/map_view.gd)** and **[TerrainForegroundView](../game/presentation/terrain_foreground_view.gd)** so forest decoration appears in hand-placed clusters for visual review; keys match **domain** **`HexMap.has_woods`** on **`make_prototype_play_map()`** (see [**`prototype_terrain_features.gd`**](../game/domain/prototype_terrain_features.gd), [**`plains_forest_decoration.gd`**](../game/presentation/plains_forest_decoration.gd)). This overlay is **not** a production biome rule and does not change the forest symbol grid or lattice.

## Fixed tiny test map

`HexMap.make_tiny_test_map()` is the **canonical 7-hex** fixture: center cell `(0,0)` plus all six neighbors, as below.

| (q, r) | Terrain |
|--------|---------|
| (0, 0) | PLAINS |
| (1, 0) | PLAINS (E) |
| (1, -1) | PLAINS (NE) |
| (0, -1) | PLAINS (NW) |
| (-1, 0) | WATER (W) |
| (-1, 1) | PLAINS (SW) |
| (0, 1) | PLAINS (SE) |

Direction names in the table are **labels** for axial neighbors; see [HEX_COORDINATES.md](HEX_COORDINATES.md) for orientation neutrality.

## Query API (Phase 1.2)

- `has(HexCoord)` — whether the coordinate is on the map.
- `terrain_at(HexCoord)` — terrain tag; **only valid** when `has` is true (asserts otherwise).
- `landform_at(HexCoord)` — landform tag; **only valid** when `has` is true (asserts otherwise). Missing storage entry ⇒ **`FLAT`**.
- `has_woods(HexCoord)` — **Phase 5.1.16c**; **only valid** when `has` is true. **Tiny test map:** always **false**.
- `size()` — number of cells.
- `coords()` — read-only list of all cells as `HexCoord` instances. Does not expose `Vector2i` keys. **Order is unspecified** in Phase 1.2; a future phase may document deterministic ordering if required (e.g. for replay or UI).
- `make_tiny_test_map()` — static factory for the table above.
- `make_prototype_play_map()` — **Phase 5.1.16g.2 (corrected + polish):** extends the **5.1.16g.1** **hand-authored island** lineage (**not** procedural **worldgen**). **Land** = **g.1** axial-disk shell (**distance from `(0,0)` ≤ `6`**, with **light** corner thinning) **minus** **west strait / NW bay** keys **plus** a large **curated `Vector2i` extension list** (NE / E **ridge** & **tongue**, SE **shelf**, explicit coastal **bridges** so woods/cities never sit on accidental **WATER**); **BFS from `(0,0)`** on the **union** yields **one** **connected** **land** component. **Terrain** defaults **grass-forward**; **PLAINS** / **plains·hills** and **grassland·hills** are **spot-painted** in **small curated groups** (no sector-wide `q ≥ …` carpets), with **extra** one-off **plains / grassland·hills** dots to **break up** large **grass** fields, including **light** **W / NW** **woods** **groves** (still **multi-component**, **no** strait-water mistakes). **`(-1,0)`** stays canonical **WATER**; **every** **land** hex has only **LAND** or **WATER** neighbors on the **finite** map (**full** **perimeter** **sea** shell — `_proto_add_full_water_ring`). **`PrototypeTerrainFeatures`** **woods** are **PLAINS**-terrain cells only (**flat** or **hills**), authored as **multiple small components** (isolates, pairs, short ribbons, **no** single giant forest carpet). Typical **`HexMap.size()`** is **~220–330** (**land + halo**); **`make_tiny_test_map()`** unchanged (**7** hexes).

## Phase 1.5 note (terrain vs movement rules)

**`HexMap`** holds **terrain** tags plus an optional parallel **landform**; **movement** still interprets **terrain** only, via **`TerrainRuleDefinitions`** (**`grassland`** is passable with the same cost as **`plains`** in the current slice). **`Landform`** does not affect **`MovementRules.legal_destinations`** yet. The first interpretation that **WATER is impassable** for unit movement lives in **[MOVEMENT_RULES.md](MOVEMENT_RULES.md)** (`MovementRules.legal_destinations`), not in ad hoc `HexMap` logic.

**`HexMap`** storage stays **enum-backed**: no string **`terrain_id`** in **`_cells`** and **no** save/load migration in **3.2**. **`TerrainRuleDefinitions.terrain_id_for_hex_map_value`** projects **`HexMap.Terrain`** values onto content ids. Unknown enum values map to an **empty** id and are treated as **impassable** in movement rules.

**Phase 3.2 (implemented):** Terrain **semantics** for **movement** are read through **`TerrainRuleDefinitions`** per [CONTENT_MODEL.md](CONTENT_MODEL.md); **`HexMap`** API and storage are **unchanged**.

## Layer boundary

Code under `game/domain/` must not depend on Godot scene nodes, rendering, UI, input, networking, or LLMs; see [game/domain/README.md](../game/domain/README.md).

## Explicitly deferred

- A dedicated **cell** or **terrain** type with gameplay fields (owner, resources, move cost, etc.)
- **Fog of war** and **visibility**
- **Distance / range / line / path** queries on the map
- **Pixel coordinates, viewport placement, projection, pan/zoom, and draw layering** belong to **presentation** (**`HexLayout`**, **`MapCamera`**, views under **`game/presentation/`**; see **[RENDERING.md](RENDERING.md)**). **`HexMap`** stays **presentation-free** hex addressing + terrain/landform/woods **tags**. It intentionally does **not** store screen offsets, texture UV policy, or `z_index`.
- **Serialization** of maps and terrain for save / replay (with schema versioning, per architecture)
