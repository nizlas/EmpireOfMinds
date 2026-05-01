# Prototype terrain textures — provenance

**Folder:** `game/assets/prototype/terrain/`

All assets below are **prototype-only**, **non-final**, and **replaceable**. **Gameplay must not depend** on exact pixel contents or image boundaries.

| Filename | Purpose | Creation method | Date |
|----------|---------|-----------------|------|
| `plains_painterly.png` | **PLAINS** hex fill in **MapView** | Generated externally (ChatGPT / image generation), per project workflow | 2026-05-01 |
| `water_painterly.png` | **WATER** hex fill in **MapView** | Generated externally (ChatGPT / image generation), per project workflow | 2026-05-01 |

**Rendering:** Textures are mapped per-hex with **`draw_colored_polygon(..., uvs, texture)`** inside **`MapView._draw()`**. If load fails, **`MapView`** falls back to **Phase 4.1** flat colors (`_terrain_to_color`).

Do **not** treat these files as shipping art, canon, or authoritative for rules. Terrain type remains **`HexMap.Terrain`** at runtime.
