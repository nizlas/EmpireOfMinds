# A1 isolated import sources

Godot binds one `.import` configuration to each GLB path. Production Meshy/Uthana imports must stay untouched, so A1 uses **byte-identical copies** of the originals under this folder with their own retargeting import settings.

| File | Original (immutable) |
|------|----------------------|
| `a1_meshy_walking_source.glb` | `../generated_warrior_3d.glb` |
| `a1_uthana_target.glb` | `../uthana_a0/generated_warrior_3d_uthana_rigged.glb` |

Do not manually merge these GLBs. Re-copy from originals if regenerating isolation.

Original production paths and their `.import` files are never modified by A1.
