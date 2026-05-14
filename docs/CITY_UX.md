# Empire of Minds — City interaction UX direction

Concise orientation for **future small implementation slices**. Not a full design bible; **[CITIES.md](CITIES.md)** / **[RENDERING.md](RENDERING.md)** stay authoritative for **today’s shipped behavior**.

---

## Purpose

Align city interaction around:

1. A **lower-right hub** when a city is selected (production + navigation).
2. An **opt-in city planning mode** (“Manage Citizens”) entered **only from the hub**, not automatically on selection.
3. **Always-visible empire borders** — **shipped** (**`EmpireBorderView`**, **`main.tscn`**) — owner **union** envelope at **full rim strength** (dual stroke); **`CityTerritoryView`** reserved for future **CityPlanningMode**, **not** normal selected-city territory emphasis.

---

## Core distinction: empire territory vs city tile ownership vs worked tiles

| Concept | Meaning | Visibility intent |
|---------|---------|-------------------|
| **Empire territory** | Union of **all** hexes owned by **any** city **share**ing the same **`owner_id`** (faction). Perimeter is **empire-level**. | **Shipped** — **`EmpireBorderView`** always-on **strong** **owner-colored** outer + **indigo** inner rim (**same recipe** as legacy territory emphasis); **not** selection-driven. |
| **City tile ownership** | **`City.owned_tiles`** — tiles **that city** controls for founding / yields scope / future swaps. City-specific; **`Scenario`** tracks **`tile_owner_city_id`**. | Future **CityPlanningMode** emphasis (**owned** tint / rim) — **not** normal selection-only territory overlay (**5.1.17h** correction). |
| **Worked tiles** | Subset of **`owned_tiles`** contributing yields via **`CityYields`** (**deterministic auto-work** today). **Not** empire geometry. | **Selected-city / planning** information only — never confused with empire border. |
| **Future swap candidates** | Tiles owned by **another friendly nearby city** that could **eventually** exchange ownership (**Civ-like** swap). **Not implemented.** | Preview overlays **later**, read-only until actions exist. |

**Worked tiles are selected-city / planning information, not empire border information.**

---

## End-state interaction flow

1. **Map play** — **`EmpireBorderView`** always-on (**union** perimeter per **`owner_id`**); map overlays otherwise match **[RENDERING.md](RENDERING.md)**. No **City Hub** until a city is selected.
2. **Select city** — **City Hub** (**`city_production_panel.gd`** / **`CityProductionPanel`**, lower-right **`HudCanvas`**) shows yields + production + **Manage Citizens** + **Done** (when planning) + **Close**; **no** worked-tile map overlay until **Manage Citizens**.
3. **Hub actions** — production unchanged in intent; **Manage Citizens** enters **CityPlanningMode** (**presentation-only** until mechanics ship).
4. **CityPlanningMode** — **`CityWorkedTilesView`** highlights **worked** tiles (**read-only**); stronger city-centric reads (owned tint / swap preview) remain **future**; exit via **Done** / **Escape** / selection changes per **[RENDERING.md](RENDERING.md)**.
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

- **Presentation state only** until explicit phases add actions/schemas.
- Focused overlays: emphasize **`owned_tiles`**, highlight **worked** subset, reserve styling for **swap candidates** (read-only enumeration later).
- Does **not** replace map camera or spawn a full city screen scene in early slices.

---

## Visual layer model

**Direction** (incremental layers; **`z_index`** / sibling order follow **[RENDERING.md](RENDERING.md)** conventions):

| Layer | Normal map | City selected | City planning |
|-------|------------|---------------|----------------|
| Terrain / forest / markers | yes | yes | yes |
| **Empire border** (always-on `EmpireBorderView`) | yes | yes | yes |
| Selected-city territory ring (`CityTerritoryView`) | no | no | yes (planned) |
| Owned-but-not-worked tint | no | optional later | yes (slice) |
| Worked-tile markers (`CityWorkedTilesView`) | no | no | yes |
| Swap-candidate outline | no | no | preview only (later) |
| Yield overlay (`TileYieldOverlay`) | toggle | toggle | toggle |
| Nameplates | yes | yes | yes |

**Always-on empire border** = union perimeter per **`owner_id`** over **all** that owner’s **`City.owned_tiles`** at **full** rim strength. **City-selected NORMAL** = hub + map reads **without** worked markers; **PLANNING** = hub + worked-tile overlay (**Manage Citizens**). **City-owned territory rim** remains **future**.

---

## Component responsibilities

| Piece | Responsibility |
|-------|------------------|
| **`CityHubPanel`** | Lower-right hub; gates entry to planning mode; stays **`LegalActions`**-clean for production buttons. |
| **`EmpireBorderView`** | Always-on faction **realm** envelope (**union** **`owned_tiles`**); **dual** **`Line2D`** rim (**5.1.17h** / **5.1.17h.1**). |
| **`CityTerritoryView`** | **Dormant** draw in normal play; **static** perimeter helpers + **`Line2D`** pool for **`EmpireBorderView`** / future planning emphasis. |
| **`CityWorkedTilesView`** | **`yield_breakdown_for_city`** **`.worked_tiles`** markers **only** when **`CityViewState`** is **PLANNING**. |
| **Planning-only views** (future slices) | Owned ring tint, swap preview outlines — pure reads + presentation flags. |

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
3. ~~**`CityViewState`** + planning toggle wiring.~~ **Shipped:** **5.1.17i** shell (**NORMAL** / **PLANNING**); owned-tile overlays / swap preview still **future**.
4. Planning-specific owned / swap-preview overlays (read-only helpers).

Polish/asset packs follow once interaction skeleton is stable.

---

## Explicit out of scope

Until explicitly phased:

- Food storage, population **growth**, happiness, housing, amenities.
- **Manual** worked-tile assignment, **swap actions**, new **`ACTIONS`** schemas, **`schema_version`** bumps, **new log events**.
- Dedicated **city screen** scene, camera modes, specialists.
- AI consumption of planning modes.
- **`TerrainForegroundView`** splits or large presentation rewrites.

**Future Civ-like tile swapping** may transfer **`tile_owner_city_id`** between **friendly nearby cities** — **design allowance only**; **not implemented**.
