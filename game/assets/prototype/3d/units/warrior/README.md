# Warrior 3D prototype (presentation experiment)

- **Model:** `warrior_3d_animations.glb` — map clip is the **exact name** on `AnimationPlayer` (e.g. `Dead`, `Idle_3`, `Left_Slash`), **not** a list index. Default visual: **`Idle_3`** (with remap on). Optional launch override: `EOM_WARRIOR_3D_ANIM=Idle_3`.
- **Enable on map:** `EMPIRE_USE_3D_MODELS=1` enables warrior + settler. `EMPIRE_USE_3D_WARRIOR=1` enables **warrior only** (legacy).
- **GLB name mismatch (audit 2026-06):** clip **names** in the file do not match their **visual** motion. `Warrior3DAnimationRemap` maps semantic → GLB key until a corrected re-export:

| GLB key (Godot name) | User saw visual |
|----------------------|-----------------|
| Dead | Left_Slash |
| Left_Slash | Dead |
| Hit_Reaction_1 | Running |
| Running | Hit_Reaction_1 |
| Idle_02 | Walking |
| Walking | Idle_02 (uncertain) |
| Combat_Stance | Idle_3 |
| Idle_3 | Combat_Stance |

- **Remap:** inspector **Use Glb Animation Name Remap** on `Warrior3DUnitMarkersView` (default on). Log shows `visual='Idle_3' glb_clip='Combat_Stance'`.
- **Animation audit (temporary):** `EOM_WARRIOR_3D_ANIM_AUDIT=1` cycles raw `get_animation_list()` names (remap off) to re-verify GLB contents.
- **Default:** warrior units use the existing 2D `unit_warrior_marker.png` path.
- **Asset folder:** `game/assets/prototype/3d/units/warrior/`
- **Implementation:** `game/presentation/warrior_3d_unit_markers_view.gd` (SubViewport markers); see `docs/RENDERING.md`.
- **Orientation defaults:** model yaw **+48°** (settler-like three-quarter toward screen-right; GLB faces **-Z** at yaw 0). SubViewport camera is elevated/oblique (not a separate unit camera). Tune via inspector exports on `Warrior3DUnitMarkersView` in `main.tscn`.
