# Prototype visual direction (Empire of Minds)

## Status and purpose

- **Phase 4.0** is **documentation-only**. It ships **this file** and steering updates only — **no** code, **no** assets, **no** UI, **no** tests, **no** scene changes.
- **Phase 4.0a** is **documentation-only**: it adds the **Asset request workflow** (see below) — **no** new art, **no** code.
- **This document** is the **direction source of truth** for upcoming **Phase 4** visual work (**4.1–4.5**): what the prototype should *aim for* before concrete pixels land.
- **[RENDERING.md](RENDERING.md)** remains the **current implementation-state** document (how `MapView`, `UnitsView`, `SelectionView`, `CitiesView`, labels, and draw order work today). When **4.1+** change rendering, **RENDERING.md** should be updated to match; **this file** should change only when the *intended* direction changes.

## Visual goals

- Make the prototype **read as a small strategy game** at a glance — not only a debug hex board.
- Improve **terrain, unit, city, and overlay readability** without adding new rules or domain types.
- **Support faction / world identity** through palette accents and iconography consistent with **[FACTION_IDENTITY.md](FACTION_IDENTITY.md)** and existing prototype banners — not through clutter or full-screen colour domination.
- Keep all prototype visuals **replaceable**; swapping art must not break mechanics.
- **Avoid final-art lock-in**: prefer a coherent **prototype** feel over production polish in Phase 4.

## Core visual principles

1. **Readability before beauty.**
2. **Coherence before detail.**
3. **Prototype assets are replaceable scaffolding**, not canon.
4. **Gameplay must not depend on pixel content** — identity survives asset swaps.
5. **Strong silhouettes and icons** over high-detail realism for units, cities, and markers.
6. **Generated images are allowed** for internal testing when **provenance is real** and status is **non-final**; do **not** fabricate provenance.
7. **Phase 4 improves presentation without changing rules** — no `HexMap`, **`MovementRules`**, **`Scenario` / `GameState`**, or **new actions** for visual reasons.

## Style direction

**Hybrid** target:

- **Stylised painterly / parchment-map** language for **terrain** — a map you might unfold, not a satellite photo.
- **Readable 2D / light 2.5D** map presentation within **Godot `CanvasItem` / `_draw`**-style constraints (see **[RENDERING.md](RENDERING.md)**).
- **Strong, clean icon overlays** for **units**, **cities**, **selection**, and **HUD-adjacent** feedback — high contrast, simple shapes.
- **Faction flavour** from **banners and accents** (e.g. owner rings, small emblem chips), **not** by tinting the whole map in faction colours.

**Avoid** for the prototype phase: photorealism, heavy pixel-art commitment, glossy mobile “card” UI, and **over-detailed** tiles or units that **compete with** legal-move and selection overlays.

## Palette and contrast

*Intent only — no concrete RGB values in 4.0; those land in **4.1** implementation.*

- **Terrain base** — **muted**, earthy **land** and **calmer water** so **water/land** reads **immediately** at default zoom.
- **Units and cities** — should **pop** against terrain using **owner accents** and shape read, not neon noise.
- **Selection / legal-destination / current-player** overlays — must stay **unambiguous**; contrast with terrain is the priority.
- **Faction colours** — **accents** (markers, rings, small HUD chips), **not** map-wide fills that fight terrain readability.

## Terrain direction for 4.1

- **Aim:** Tiles feel more **game-like** and **readable** while staying **simple hexes** — same domain terrain types, **no** new `HexMap.Terrain` values, **no** changes to **`MovementRules`** or **`HexMap`** structure.
- **First step:** **Palette refinement** (land/water relationship, muted bases) aligned with **parchment-map** intent.
- **Optional, deferred within 4.1:** very **subtle** per-hex texture, edge tint, or noise — only if it **helps readability** and stays cheap to replace; **no** TileMap/TileSet **pipeline** commitment in 4.0.
- **Terrain art is visual-only**; drawing remains derived from **`map.coords()`** / **`terrain_at()`** per **RENDERING.md**.

## Unit direction for 4.2

- **Aim:** Clear **type** and **ownership** at a glance (and at modest zoom).
- Prefer **markers, icons, badges, or small emblem cards** — **not** full character **sprites** or a locked roster of bespoke units.
- **Owner** should read via **accent ring, outline, or chip**, not by drowning the marker in one flat fill.
- **Generated icons** may be used if **replaceable** and **documented**; they must **not** fix lore or unit identity prematurely.

## City direction for 4.3

- **Aim:** Founded cities feel **more substantial** than a bare geometric marker.
- Prefer **settlement badges, banner pins, or simple city icons** — still **derived from** domain **`City`** data; **no** changes to the **City** domain model for art.
- **No** city-management **UI** or production panels in **4.3** as a goal — presentation of *where* the city is and *who* owns it comes first.

## HUD / feedback direction for 4.4

- **Aim:** The player can infer **controls**, **what is selected**, **whose turn it is**, and **recent meaningful events** without reading code.
- **Candidate elements** (none mandated in 4.0; pick incrementally in 4.4):
  - **Controls / help** overlay (toggleable).
  - **Selected unit / city** summary strip or card.
  - **Progress / unlock** feedback — toast, flash, or **`LogView`** emphasis when appropriate.
  - **Turn / current player** clarity building on existing **`TurnLabel`** patterns.
- **Debug vs HUD:** Treat **F1 `FactionBannerGallery`**, **KEY_*** debug actions, and similar surfaces as **internal / debug** unless explicitly promoted in a later phase. **Player-facing HUD** should be labelled and separated conceptually even if it shares Godot nodes.

## Camera / presentation direction for 4.5

- **Aim:** Better **feel** — pan, zoom, framing — **without** changing gameplay truth.
- **Candidates:** smoother **Camera2D** behaviour, **zoom limits** that preserve readability, **selected-hex** highlight polish, **light** motion on **accepted** actions (non-authoritative).
- **Must not:** hide rules state in **tween-only** client assumptions; **RENDERING.md**’s domain-vs-presentation boundary applies.

## Prototype asset folder policy

- **`game/assets/prototype/`** remains the home for **non-final** prototype art (consistent with **[FACTION_IDENTITY.md](FACTION_IDENTITY.md)** and Phase **3.5d** banners).
- **Per-category `PROVENANCE.md`** (or equivalent) when adding files: filename, purpose, creation method, date, **non-final** status.
- Assets are **replaceable**; **no** workflow should treat a prototype file as **release** or **canonical** lore.

## Generated asset policy

- **Allowed** for **internal testing** acceleration.
- Record **prompt / tool / source / date** when practical; **do not invent** AI provenance.
- If generation is unavailable, use **clearly labelled programmatic placeholders** (as with Phase **3.5d** banner placeholders).
- **Do not** use generated images to **lock** lore, names, or faction canon — **Phase 6** owns final identity and IP review.
- **No** Steam, storefront, or commercial-release asset policy is defined here.

## Asset request workflow

For **non-trivial** prototype visual assets, the **implementation agent** should **not** generate or add assets **ad hoc**.

The preferred workflow is:

1. The implementation agent produces an **Asset Request Pack**.
2. The **Asset Request Pack** is **reviewed** by the user.
3. Assets may then be **generated externally** or **created manually** (outside the constrained implementation pass, or by explicit user action).
4. A **later implementation phase** may **import and wire** those approved assets.
5. The **Mandatory Implementation Report** (or phase report) must list **all** imported or generated assets and **provenance** notes.

This keeps the implementation agent in the role of **constrained implementer**, not art director or autonomous asset generator.

### Asset Request Pack

An **Asset Request Pack** must list **every** proposed asset:

- **Target filename and path** (e.g. under `game/assets/prototype/…`).
- **Asset category:** terrain, unit marker, city marker, HUD, overlay, faction banner, mockup, other.
- **Purpose in-game** (what readability or identity problem it solves).
- **Required dimensions** (max size, aspect if relevant).
- **Transparent background:** yes / no.
- **Visual description** (enough for an external artist or tool to execute).
- **Preferred generation method:** external generation, manual, programmatic placeholder, or implementation-agent placeholder (justify if the latter).
- **Why this asset is needed** for the **current** phase.
- **Required for implementation** vs **visual exploration only**.
- **Provenance / documentation requirements** (what must be recorded in `PROVENANCE.md` or equivalent).
- **Confirmation** that the asset is **prototype-only**, **non-final**, **replaceable**.
- **Confirmation** that **gameplay must not depend** on exact **pixel contents**.

### Prototype raster import quality standard (Phase 4.3j — default)

**Unless an Asset Request Pack explicitly justifies a different approach**, future **raster** assets that are **expected to be scaled in-game** should default to:

- **Dimensions** stated in the **Asset Request Pack** (repo-ready; no ad hoc rescale as a substitute for spec).
- **True PNG RGBA** (**color type 6**) when **transparency** is required — **real** transparent background, **not** checkerboard baked in, **not** a flat white/paper fill pretending to be transparency.
- **Alpha 0** in **empty** corners / **empty** background regions where applicable.
- **Antialiased semi-transparent** edge pixels where **silhouettes** meet transparency (alpha quality is part of the asset contract when the visual needs transparency).
- **Direct loading** as **`Texture2D`** for **approved RGBA** deliveries — **no** runtime **background-keying** / **chroma-key** removal on the happy path.
- **`MarkerTextureUtil`**-style runtime keying is **only** acceptable as a **temporary repair** or **fallback** for **bad RGB** prototype inputs — **not** the preferred pipeline.
- **Scoped** Godot **import** settings and **`CanvasItem.texture_filter`** choices appropriate to the **asset category** (e.g. marker-like icons may use **scoped mipmaps** + **`LINEAR_WITH_MIPMAPS`** as implemented for map markers — **document** any category-specific import assumptions in **`PROVENANCE.md`** or the phase report).
- **Gameplay must not depend** on image pixels; **provenance** must record **generation/source**, **date**, **prototype-only** / **replaceable** status, and **relevant import** assumptions.

**Agent / implementation rule:** If a delivery is **flattened RGB** (no alpha) but the **pack** or **direction** expects **transparency**, treat that as an **asset-format problem** — **report** it; **do not** silently pile on **rendering hacks** beyond an explicitly scoped **temporary** fallback.

**Exceptions:** Any departure from this standard must be **explicit** in the **Asset Request Pack** or the **Mandatory Implementation Report**.

**Wording to remember:** Approved **scalable marker / icon-style** raster assets should be **true-alpha RGBA** files and should **not** require **runtime background removal**. If the visual needs transparency, **alpha quality** is part of the **asset contract**.

### Who may create assets

- The **implementation agent** may create **trivial programmatic placeholders** when **explicitly useful** for the **current** phase and **in scope** — e.g. flat-colour debug tiles, simple rings, text labels, or stamped placeholder banners (as in Phase **3.5d**), with **honest** provenance.
- For **non-trivial** **painterly**, **illustrative**, **faction**, **terrain**, **unit**, **city**, **HUD**, or **mockup** assets, the **preferred path** is **request-first:** the agent describes the needed asset set (via an **Asset Request Pack**), then work proceeds only after **externally generated** or **user-approved** assets are available — unless a **phase prompt** **explicitly overrides** this and allows direct creation.
- When a phase prompt **explicitly allows** direct asset work, the **implementation report** must still **document all assets** (paths, purpose, provenance, non-final status).

This stays consistent with the rest of this document and **[FACTION_IDENTITY.md](FACTION_IDENTITY.md):** prototype assets are **non-final** and **replaceable**; **no fabricated provenance**; **no lore / canon lock** from pixels; **gameplay must not depend** on pixel contents.

## Phase 4 roadmap

| Subphase | Focus |
|----------|--------|
| **4.0** | **This document** — direction checkpoint (**docs-only**). |
| **4.0a** | **Asset request workflow** — **Asset Request Pack** process (**docs-only**). |
| **4.1** | Terrain readability — prototype palette in **`MapView`** (**implemented**); optional subtle texture still future. |
| **4.2** | Unit readability — owner rim, **type_id** glyph, selection halo (**implemented**); sprites still out of scope. |
| **4.2a** | Map **display scale** — **`HexLayout.SIZE`** **2×** for readability (**implemented**); **no** camera zoom. |
| **4.3** | City visual polish — badges / pins. |
| **4.4** | HUD / feedback / controls clarity. |
| **4.5** | Camera / presentation feel — light juice, no rule changes. |

## Explicit non-goals (Phase 4.0 and this direction doc)

- **No** final or release art commitment.
- **No** Steam / storefront / commercial asset policy.
- **No** gameplay rule changes, **no** domain model changes, **no** new terrain/unit/city **content** for mechanics.
- **No** full **UI redesign** or large menu systems in Phase 4 as a whole — incremental, readable slices only.
- **No** dedicated **asset pipeline** (atlases, DCC toolchain, CI for art) — folder + provenance discipline only.
- **No** **`ART_DIRECTION.md`** rename or merge required — **VISUAL_DIRECTION.md** is the Phase **4** prototype direction doc.

## Relationship to existing docs

- **[FACTION_IDENTITY.md](FACTION_IDENTITY.md)** — Faction / custom-civ identity and **prototype / generated-art policy**; **VISUAL_DIRECTION** applies that policy to **map and HUD presentation** in Phase **4**.
- **[RENDERING.md](RENDERING.md)** — **What exists in code today** (draw order, placeholder colours, deferred items); update when **4.1+** implementations change. **Phase 4.3j** bridges policy (**this file**, **Prototype raster import quality standard**) with marker/texture expectations documented there.
- **[PHASE_PLAN.md](PHASE_PLAN.md)** — Phase **4** roadmap and validation expectations.
- **[DECISION_LOG.md](DECISION_LOG.md)** — Decision trace for **4.0** and later visual milestones.
- **[PROJECT_BRIEF.md](PROJECT_BRIEF.md)** — Project intent and **IP boundary**; visual work must stay aligned and **non-infringing** as the project matures (**Phase 6** deep review).
