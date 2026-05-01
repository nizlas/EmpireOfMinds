# Prototype map marker icons — provenance

**Folder:** `game/assets/prototype/map_markers/`  
**Specification:** [docs/ASSET_REQUEST_PACKS/PHASE_4_3A_MARKER_SET.md](../../../../docs/ASSET_REQUEST_PACKS/PHASE_4_3A_MARKER_SET.md)

All assets below are **prototype-only**, **non-final**, and **replaceable**. **Gameplay must not depend** on exact pixel contents.

| Filename | Purpose | Format | Creation method | Date |
|----------|---------|--------|-----------------|------|
| `city_marker.png` | City **map marker** on the strategy map | **512×512** **PNG** **RGBA** (color type **6**), transparent background | Replacements with true alpha (manual placement per project workflow) | 2026-05-01 |
| `unit_settler_marker.png` | **Settler** marker (`type_id` `settler`) | **512×512** **PNG** **RGBA**, transparent background | same | 2026-05-01 |
| `unit_warrior_marker.png` | **Warrior** marker (`type_id` `warrior`) | **512×512** **PNG** **RGBA**, transparent background | same | 2026-05-01 |

**Phase 4.3i (current):** **`CitiesView`** / **`UnitsView`** load these with **`ResourceLoader.load`** as **`Texture2D`** — **no** runtime background-keying. **`.import`**: **`mipmaps/generate=true`** for these three files only (terrain imports unchanged). **`texture_filter`** on those views is **`TEXTURE_FILTER_LINEAR_WITH_MIPMAPS`** for cleaner minification.

**Legacy:** earlier **RGB** (no alpha) prototypes used **`MarkerTextureUtil.load_marker_icon`** (top-left keyed transparency). That helper remains in the repo for **non-RGBA** sources only; **not** used for the three markers above.

Do **not** treat these files as shipping art, canon, or authoritative for rules. Owner colour and unit type remain **programmatic** / **domain**-driven at runtime.
