# Empire of Minds — City interaction UX direction

Concise orientation for **future small implementation slices**. Not a full design bible; **[CITIES.md](CITIES.md)** / **[RENDERING.md](RENDERING.md)** stay authoritative for **today’s shipped behavior**.

---

## Purpose

Align city interaction around:

1. A **lower-right hub** when a city is selected (production + navigation).
2. An **opt-in city planning mode** (“Manage Citizens”) entered **only from the hub**, not automatically on selection.
3. **Always-visible empire borders** (**planned** visualization — faction territory envelope) distinct from **city-owned** and **worked-tile** overlays.

---

## Core distinction: empire territory vs city tile ownership vs worked tiles

| Concept | Meaning | Visibility intent |
|---------|---------|-------------------|
| **Empire territory** | Union of **all** hexes owned by **any** city **share**ing the same **`owner_id`** (faction). Perimeter is **empire-level**. | **Always on** once implemented — thin owner-colored outline; **not** selection-driven. |
| **City tile ownership** | **`City.owned_tiles`** — tiles **that city** controls for founding / yields scope / future swaps. City-specific; **`Scenario`** tracks **`tile_owner_city_id`**. | Selected-city emphasis ring / planning fills — **selection or planning mode**. |
| **Worked tiles** | Subset of **`owned_tiles`** contributing yields via **`CityYields`** (**deterministic auto-work** today). **Not** empire geometry. | **Selected-city / planning** information only — never confused with empire border. |
| **Future swap candidates** | Tiles owned by **another friendly nearby city** that could **eventually** exchange ownership (**Civ-like** swap). **Not implemented.** | Preview overlays **later**, read-only until actions exist. |

**Worked tiles are selected-city / planning information, not empire border information.**

---

## End-state interaction flow

1. **Map play** — **Empire border always-on** (**planned** — union perimeter view); until that ships, map overlays match **[RENDERING.md](RENDERING.md)** **today**. No **`CityHubPanel`** until a city is selected.
2. **Select city** — **City Hub** (**shipped** skeleton in **`city_production_panel.gd`** / **`CityProductionPanel`**, lower-right **`HudCanvas`**) shows yields + production + **Manage Citizens (planned)** + **Close**; **`CityWorkedTilesView`** shows worked tiles (**shipped**, selection-driven).
3. **Hub actions** — production unchanged in intent; **Manage Citizens** enters **CityPlanningMode** (**presentation-only** until mechanics ship).
4. **CityPlanningMode** — stronger city-centric tile reads (owned vs worked vs future swap preview); exit via **Done** / **Escape** / selecting another entity clears planning sub-state as specified in implementation slices.
5. **No automatic jump** into planning on city click — hub remains the gate.

---

## Lower-right CityHubPanel concept

**Shipped (5.1.17g):** skeleton as **`CityProductionPanel`** (**`city_production_panel.gd`**) — **City Hub** header, **Manage Citizens (planned)** (**disabled**), **Close** (**clears city selection**). Further hub polish / rename may follow.

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
| **Empire border** (always-on) | yes | yes | yes |
| Selected-city territory ring | no | yes | yes |
| Owned-but-not-worked tint | no | optional later | yes (slice) |
| Worked-tile markers | no | yes | stronger |
| Swap-candidate outline | no | no | preview only (later) |
| Yield overlay (`TileYieldOverlay`) | toggle | toggle | toggle |
| Nameplates | yes | yes | yes |

**Always-on empire border** = union perimeter per **`owner_id`** over **all** that owner’s **`City.owned_tiles`**. **Selection-driven overlays** = territory ring, worked markers, planning accents — **not** the empire envelope.

---

## Component responsibilities

| Piece | Responsibility |
|-------|------------------|
| **`CityHubPanel`** | Lower-right hub; gates entry to planning mode; stays **`LegalActions`**-clean for production buttons. |
| **Empire border view** (future node) | Draw faction envelope; always visible; reuse perimeter math patterns from **`CityTerritoryView`** without rewriting **`TerrainForegroundView`**. |
| **`CityTerritoryView`** (today) | Selected-city perimeter — migrate mentally to “emphasis ring over empire” when empire layer ships. |
| **`CityWorkedTilesView`** | Worked tiles from **`yield_breakdown_for_city`** **`.worked_tiles`** only. |
| **Planning-only views** (future slices) | Owned ring tint, swap preview outlines — pure reads + presentation flags. |

---

## Mode/state model

- **`SelectionState`** — unchanged contract (**unit** vs **city** id).
- **`CityViewState`** (presentation **`RefCounted`**, future slice) — e.g. **`NORMAL`** vs **`PLANNING`**; toggled by hub button / ESC / selection changes.
- **No** `try_apply`, **no** log rows for mode toggles until product asks.

---

## Roadmap slices

Planning-only doc (**this file**) ships under **5.1.17f**. Recommended **implementation** order (IDs illustrative — adjust in **[PHASE_PLAN.md](PHASE_PLAN.md)**):

1. ~~Hub reposition/rename + **Manage Citizens** / **Close** buttons (presentation).~~ **Shipped:** **5.1.17g** skeleton (**Close** + disabled **Manage Citizens (planned)**); **CityViewState** / real planning mode **not** in this slice.
2. **`EmpireBorderView`** always-on union borders.
3. **`CityViewState`** + planning toggle wiring.
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
