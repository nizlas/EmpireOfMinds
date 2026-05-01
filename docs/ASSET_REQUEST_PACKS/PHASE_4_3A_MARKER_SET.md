# Phase 4.3a — Prototype map marker icons (approved request pack)

## Status and purpose

- **Status:** **Approved specification** (repository source of truth). **No assets are included in this document** — generation/import happens separately; wiring is **Phase 4.3b**.
- **Purpose:** Define the **minimal** set of **static map marker icons** (strategy-map **badges** / **icons**) for **city**, **settler**, and **warrior**. These are **not** animated **sprites**, **not** character-art production sheets, and **not** VFX.

Related steering:

- **[VISUAL_DIRECTION.md](../VISUAL_DIRECTION.md)** — Phase 4 visual direction and asset workflow.
- **[RENDERING.md](../RENDERING.md)** — Current presentation implementation (updated when assets are wired).
- **[FACTION_IDENTITY.md](../FACTION_IDENTITY.md)** — Prototype art policy; **no faction-specific** marker variants in this pack.

## Approved asset list

| Asset | Target path |
|--------|--------------|
| City marker icon | `game/assets/prototype/map_markers/city_marker.png` |
| Settler unit marker icon | `game/assets/prototype/map_markers/unit_settler_marker.png` |
| Warrior unit marker icon | `game/assets/prototype/map_markers/unit_warrior_marker.png` |

## Terminology

Use **map marker icons** or **marker icons** only. Do **not** describe these as **sprites** (avoids implying animation, full unit sprites, or sprite sheets).

## Source specification

- **Format:** **512×512 px** PNG (high-res source for 4K and future zoom); implementation draws **smaller** in world/view space.
- **Background:** **Transparent** (alpha).
- **Silhouette occupancy (meaningful motif on canvas):**
  - **Unit** icons: roughly **60–75%** of the canvas (leave margin for scaling/clipping).
  - **City** icon: roughly **70–85%** of the canvas.
- **Overall readability:** Markers should be **lighter and more readable** than a **dark sepia** wash. The first draft had a good parchment mood but read **too dark** overall — aim **clearer value range** while keeping the painterly map-table feel.

## Intended in-game display (layout reference)

With **`HexLayout.SIZE` = 64** (circumradius), a **pointy-top** hex has **vertex-to-vertex height ≈ 128** world units.

- **Unit** marker icons: target roughly **45–65%** of hex height → about **58–83** world units (tune at wire time).
- **City** marker icon: target roughly **55–75%** of hex height → about **70–96** world units (tune at wire time).

## Style direction

- **Family:** **Stylised painterly parchment-map** — readable **silhouettes**, **non-photorealistic**, **non-pixel-art**, **non-glossy**, **non–mobile-shiny**.
- **Colour:** **Not** monochrome brown only. **Muted natural accents** are encouraged while keeping a **coherent map icon** set—e.g.:
  - warm stone  
  - ochre  
  - muted clay red  
  - olive  
  - desaturated blue-grey  
  - leather brown  
- **Mood:** Softer, **lighter** base values than heavy dark sepia; accents stay **muted** so **owner colour** (programmatic) and **terrain** remain legible underneath.

### City marker icon

- **Neutral** settlement read: walls / civic mass / map-pin badge — **no** culture-specific landmark, **no** player colour baked into the PNG.

### Settler marker icon

- **Civil / travel** cue: pack, staff, wagon motif, small banner — **non-violent**, chunky silhouette; **simpler** than city so hierarchy stays **city ≥ unit**.

### Warrior marker icon — **first / basic melee** (critical)

The game’s **`warrior`** is the **first/basic troop** type, **not** organized line infantry or a bronze-era specialist. The icon must **not** read as **spearman**, **hoplite**, **bronze warrior**, or **armored soldier**.

**Do:**

- **Primitive** early melee: **club** / **wooden cudgel**, **simple wooden shield**, **leather or fur** hints.

**Do not:**

- **Metal armour**, **helmet crest**, **spear-dominant** pose, or “later tech” soldier silhouettes.

This keeps the marker **distinct** from plausible future **Bronze-Armed Warrior**-style content and matches **primitive early melee** identification.

## Rules and constraints

- **Owner / player colour:** **Programmatic** at render time — **not** baked into marker PNGs.
- **`type_id` / domain:** **Authoritative** for unit type; **pixels are presentation-only**.
- **Gameplay** must **not** depend on exact pixel contents.
- **No faction-specific** variants in this pack.
- **No terrain** textures in this pack.
- **No animation**, **no VFX**, **no sprite sheets**.

## Provenance (on import)

When files are added to the repo, create or extend:

- `game/assets/prototype/map_markers/PROVENANCE.md`

…with **filename**, **purpose**, **creation method** (tool / artist), **date**, and **non-final / replaceable** status — per **[VISUAL_DIRECTION.md](../VISUAL_DIRECTION.md)**. **Do not fabricate** provenance.

## Next phases (narrow)

1. **Phase 4.3b — Import and wire prototype marker icons** (code/presentation + `RENDERING.md`; **no** domain/content change for this asset set alone).
2. **Phase 4.1b — Painterly terrain asset request pack** (docs): minimal **plains** / **water** sources only.
3. **Phase 4.1c — Import and wire minimal painterly terrain prototype** (presentation-only; **no** new `HexMap.Terrain` values in first pass).
