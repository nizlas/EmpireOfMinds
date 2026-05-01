# Prototype map marker icons — provenance

**Folder:** `game/assets/prototype/map_markers/`  
**Specification:** [docs/ASSET_REQUEST_PACKS/PHASE_4_3A_MARKER_SET.md](../../../../docs/ASSET_REQUEST_PACKS/PHASE_4_3A_MARKER_SET.md)

All assets below are **prototype-only**, **non-final**, and **replaceable**. **Gameplay must not depend** on exact pixel contents.

| Filename | Purpose | Creation method | Date |
|----------|---------|-----------------|------|
| `city_marker.png` | City **map marker icon** on the strategy map | Generated externally (ChatGPT / image generation), per project workflow | 2026-05-02 |
| `unit_settler_marker.png` | **Settler** unit marker icon (`type_id` `settler`) | Generated externally (ChatGPT / image generation), per project workflow | 2026-05-02 |
| `unit_warrior_marker.png` | **Warrior** unit marker icon (`type_id` `warrior`) | Generated externally (ChatGPT / image generation), per project workflow | 2026-05-02 |

**Phase 4.3c note:** Current files are **PNG RGB** (no **alpha** channel). **`MarkerTextureUtil.load_marker_icon`** derives transparency by keying pixels near the **top-left** background colour. Re-exporting these as **RGBA** with real **alpha** is **preferred** when refreshing art.

Do **not** treat these files as shipping art, canon, or authoritative for rules. Owner colour and unit type remain **programmatic** / **domain**-driven at runtime.
