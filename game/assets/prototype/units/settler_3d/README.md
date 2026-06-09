# Settler 3D map experiment (prototype)

- **Model:** `settler_animations.glb` — map clip is the **exact name** on `AnimationPlayer` (e.g. `Dead`, `Idle_3`, `Left_Slash`), **not** a list index. Default visual: **`Idle_3`** (with remap on). Optional launch override: `EOM_WARRIOR_3D_ANIM=Idle_3` (shared with warrior for now).
- **Enable on map:** `EMPIRE_USE_3D_MODELS=1` (settler is **not** enabled by legacy `EMPIRE_USE_3D_WARRIOR=1`).
- **Animations:** `settler_animations.glb` exposes **`Idle_3`** and **`Walking`** directly — no warrior swap remap.
- **Root motion:** `Walking` animates **Hips** translation (~160 units forward in GLB space). Map hex lerp is separate; `Warrior3DUnitMarkersView.settler_neutralize_root_motion` (default on) counter-offsets via **`RootMotionAnchor`** so the settler stays framed in the SubViewport.
- **Remap:** inspector **Use Glb Animation Name Remap** on `Warrior3DUnitMarkersView` (default on).
- **Implementation:** `game/presentation/warrior_3d_unit_markers_view.gd` (shared SubViewport markers); see `docs/RENDERING.md`.
- **Orientation defaults:** model yaw **+48°** (three-quarter toward screen-right; GLB faces **-Z** at yaw 0). Same SubViewport camera as warrior.
