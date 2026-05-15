# Empire of Minds — City interaction UX direction

Concise orientation for **future small implementation slices**. Not a full design bible; **[CITIES.md](CITIES.md)** / **[RENDERING.md](RENDERING.md)** stay authoritative for **today’s shipped behavior**.

---

## Purpose

Align city interaction around:

1. A **lower-right hub** when a city is selected (production + navigation).
2. An **opt-in city planning mode** (“Manage Citizens”) entered **only from the hub**, not automatically on selection.
3. **Always-visible empire borders** — **shipped** (**`EmpireBorderView`**) — owner **union** envelope (**selection-independent**); **no** second thick outline when a city is selected. **`CityTerritoryView`** does **not** draw a rim; **Manage Citizens / PLANNING** shows **citizen/head** markers on owned tiles (**`CityWorkedTilesView`**, **not** a border stroke).

---

## Core distinction: empire territory vs city tile ownership vs worked tiles

| Concept | Meaning | Visibility intent |
|---------|---------|-------------------|
| **Empire territory** | Union of **all** hexes owned by **any** city **share**ing the same **`owner_id`** (faction). Perimeter is **empire-level**. | **Shipped** — **`EmpireBorderView`** always-on **strong** rim (**dual** **`Line2D`**); **same** visual whether or not a city is selected (**selection-independent**). |
| **City tile ownership** | **`City.owned_tiles`** — tiles **that city** controls for founding / yields scope / future swaps. City-specific; **`Scenario`** tracks **`tile_owner_city_id`**. | **Manage Citizens / PLANNING:** **`CityWorkedTilesView`** **citizen/head** markers (**dim** = owned, **not** worked; **worked** = in **`yield_breakdown`..`worked_tiles`**). **Not** a second **`Line2D`** rim (**`CityTerritoryView`** **`_draw`** dormant). |
| **Worked tiles** | Subset of **`owned_tiles`** contributing yields via **`CityYields`** (**deterministic auto-work** today). **Not** empire geometry. | **Selected-city / planning** information only — never confused with empire border. |
| **Future swap candidates** | Tiles owned by **another friendly nearby city** that could **eventually** exchange ownership (**Civ-like** swap). **Not implemented.** | Preview overlays **later**, read-only until actions exist. |

**Worked tiles are selected-city / planning information, not empire border information.**

---

## End-state interaction flow

1. **Map play** — **`EmpireBorderView`** always-on (**union** perimeter per **`owner_id`**); map overlays otherwise match **[RENDERING.md](RENDERING.md)**. No **City Hub** until a city is selected.
2. **Select city** — **City Hub** only (**`city_production_panel.gd`** / **`CityProductionPanel`**, lower-right **`HudCanvas`**) — yields + production + **Manage Citizens** + **Done** (when planning) + **Close**; **no** citizen markers on the map until **Manage Citizens**.
3. **Hub actions** — production unchanged in intent; **Manage Citizens** enters **CityPlanningMode** (**presentation** state + **`set_city_worked_tiles`**; **5.1.19e** **`worked_tiles_mode`**).
4. **CityPlanningMode** — **`CityWorkedTilesView`** draws **citizen** **`dim` / `worked`** markers (**read-only** display); **5.1.18a / 5.1.19d / 5.1.19e:** map clicks on owned ring tiles (non-center; **assigning** a new tile requires nonzero raw yield) submit **`set_city_worked_tiles`** — **dim** ring = place/append/replace-last up to **`City.population`**; **worked** ring = **remove** that assignment (**idle** citizen — **no** hidden auto-replacement; **`tiles: []`** leaves all citizens idle in **manual** mode). See **CITIES.md** / **PHASE_PLAN**. Tile **ownership** swap preview remains **future**; exit via **Done** / **Escape** / selection changes per **[RENDERING.md](RENDERING.md)**.
5. **No automatic jump** into planning on city click — hub remains the gate.

---

## Lower-right CityHubPanel concept

**Shipped (5.1.17g / 5.1.17i):** **`CityProductionPanel`** (**`city_production_panel.gd`**) — **City Hub** header, **Manage Citizens** (**enters presentation PLANNING** for **current-player** cities), **Done** (**exits PLANNING**, keeps city selected), **Close** (**`reset_to_normal`** + **`selection.clear_city()`**). Further hub polish / rename may follow.

Evolve toward full hub:

- Header (city id / owner).
- Read-only yields + breakdown (**existing domain reads**).
- Production actions (**still from `LegalActions`** only).
- **Manage Citizens** → enters planning presentation mode (**no rules yet**).
- **Close** → clear city selection (or hide hub — slice decides).

Hub is **HUD** (`HudCanvas`), not a separate scene tree root.

---

## CityPlanningMode concept

- **Presentation state** gates marker draw and input routing; **Manage Citizens** tile clicks build **`set_city_worked_tiles`** payloads (**domain** validates). **`[]`** payload = all citizens **idle** on worked yields (**manual** mode; **no** “restore auto” button in this slice).
- Focused overlays: emphasize **`owned_tiles`**, highlight **worked** subset, reserve styling for **swap candidates** (read-only enumeration later).
- Does **not** replace map camera or spawn a full city screen scene in early slices.

---

## Visual layer model

**Direction** (incremental layers; **`z_index`** / sibling order follow **[RENDERING.md](RENDERING.md)** conventions):

| Layer | Normal map | City selected | City planning |
|-------|------------|---------------|----------------|
| Terrain / forest / markers | yes | yes | yes |
| **Empire border** (always-on `EmpireBorderView`) | yes | yes | yes |
| **Citizen/head markers** on city-owned hexes (**not** a border stroke) | no | no | yes (**`CityWorkedTilesView`**, **PLANNING** only: **`dim` / `worked`** prototype PNGs; **non-center** tiles) |
| Owned-but-not-worked tint (optional alternative to dim heads) | no | no | optional later |
| Swap-candidate outline | no | no | preview only (later) |
| Yield overlay (`TileYieldOverlay`) | toggle | toggle | toggle |
| Nameplates | yes | yes | yes |

**Always-on empire border** = union perimeter per **`owner_id`** (**unchanged** when selecting a city). **City-selected NORMAL** = **hub only** — **no** citizen markers. **PLANNING** = hub + **`CityWorkedTilesView`** markers (**dim** vs **`worked`**, **`planning_marker_draw_style()`** sizing). **`CityTerritoryView`** does **not** draw a rim. **Manual** list is capped by **`population`** (**PHASE_PLAN** **5.1.19d**); **swap** / extra marker states remain **future**.

---

## Component responsibilities

| Piece | Responsibility |
|-------|------------------|
| **`CityHubPanel`** | Lower-right hub; gates entry to planning mode; stays **`LegalActions`**-clean for production buttons. |
| **`EmpireBorderView`** | Always-on faction **realm** envelope (**union** **`owned_tiles`**); **dual** **`Line2D`** rim (**5.1.17h** / **5.1.17h.1**). |
| **`CityTerritoryView`** | **Dormant** **`_draw`** (**no** selected-city border rim). Static perimeter helpers + **`Line2D`** pool for **`EmpireBorderView`** / tests. |
| **`CityWorkedTilesView`** | **5.1.17j / 5.1.17j.1:** **PLANNING** (**Manage Citizens**) **citizen** markers — **`dim`** on **non-center** **`owned_tiles`**, **`worked`** where coord ∈ **`yield_breakdown_for_city`(..).`worked_tiles`** (multiple **`worked`** markers when **`population`** and manual/auto fill use more than one tile); **`_draw`** empty in **NORMAL** (city-selected hub only). **v0:** no marker on city **center**. |
| **Planning-only views** (future slices) | **Swap** accent / previews — **read-only** until phased; **no** new citizen texture states in **5.1.17j**. |

---

## Mode/state model

- **`SelectionState`** — unchanged contract (**unit** vs **city** id).
- **`CityViewState`** (**`city_view_state.gd`**, presentation **`RefCounted`**) — **`NORMAL`** vs **`PLANNING`**; toggled from hub (**Manage Citizens** / **Done**) or **ESC** (exit planning); **`SelectionController`** resets planning when selection changes (**no** domain / **`try_apply`**).
- **No** `try_apply`, **no** log rows for mode toggles until product asks.

---

## Roadmap slices

Planning-only doc (**this file**) ships under **5.1.17f**. Recommended **implementation** order (IDs illustrative — adjust in **[PHASE_PLAN.md](PHASE_PLAN.md)**):

1. ~~Hub reposition/rename + **Manage Citizens** / **Close** buttons (presentation).~~ **Shipped:** **5.1.17g** hub skeleton + **5.1.17i** **Manage Citizens** / **Done** / **`CityViewState`** toggle (**presentation-only**).
2. ~~**`EmpireBorderView`** always-on union borders.~~ **Shipped:** **5.1.17h** + **5.1.17h.1** correction — **strong** dual rim (**parity** with legacy territory stroke); **`CityTerritoryView`** **dormant** until planning overlay slice.
3. ~~**`CityViewState`** + planning toggle~~ **Shipped:** **5.1.17i**. ~~Citizen markers~~ **Shipped:** **5.1.17j** assets + **5.1.17j.1** **PLANNING-only** draw. **Next:** swap-preview overlays (read-only), optional tint, rename **`CityCitizenMarkersView`** if desired.
4. ~~Planning-specific citizen markers~~ **Shipped:** **5.1.17j** + **5.1.17j.1** (**PLANNING-only**). **Next:** swap-preview overlays (read-only), optional tint, dedicated rename **`CityCitizenMarkersView`** if desired.

Polish/asset packs follow once interaction skeleton is stable.

---

## Explicit out of scope

Until explicitly phased:

- Happiness, housing, amenities, starvation, **settler** population cost (beyond **5.1.19b** growth).
- **Inter-city** tile **swap** actions / ownership transfer, **new** **`ACTIONS`** schemas beyond shipped **`set_city_worked_tiles`**, **`schema_version`** bumps driven by this UX slice, **new log events** for mode-only toggles.
- Dedicated **city screen** scene, camera modes, specialists.
- AI consumption of planning modes.
- **`TerrainForegroundView`** splits or large presentation rewrites.

**Future Civ-like tile swapping** may transfer **`tile_owner_city_id`** between **friendly nearby cities** — **design allowance only**; **not implemented**.
