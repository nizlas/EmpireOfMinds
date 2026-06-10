# Settler 3D map experiment (prototype)

- **Model:** `settler_animations.glb` — map clip is the **exact name** on `AnimationPlayer` (e.g. `Dead`, `Idle_3`, `Left_Slash`), **not** a list index. Default visual: **`Idle_3`** (with remap on). Optional launch override: `EOM_WARRIOR_3D_ANIM=Idle_3` (shared with warrior for now).
- **Enable on map:** `EMPIRE_USE_3D_MODELS=1` (settler is **not** enabled by legacy `EMPIRE_USE_3D_WARRIOR=1`).
- **Animations:** GLB clip names are **not trustworthy** (F9 visual audit, 2026-06). With remap on: semantic **`Idle_3`** → GLB **`Hit_Reaction_1`** (idle); semantic **`Walking`** → GLB **`Running`** (short-term walk; less foot slide than raw **`Walking`**); semantic **`Dead`** → GLB **`walking_2`**. Warrior swap table does not apply to settler.
- **Root motion:** Runtime hex walk uses GLB **`Running`** (near in-place). Map hex lerp is separate. Manual **`RootMotionAnchor`** X/Z cancel is **off** by default (`settler_neutralize_root_motion=false`); anchor stays at zero. Raw **`Walking`** remains for F9 / opt-in `EOM_SETTLER_BUILTIN_RM` probe only.
- **TEMP debug:** with `EMPIRE_USE_3D_MODELS=1`, press **F9** to cycle raw settler clips (anchor zeroed, cancel off). Console: `[Settler3D state]` heartbeat 1 Hz, `[Settler3D anim]` transitions.
- **TEMP probe:** `EOM_SETTLER_BUILTIN_RM=1` (with `EMPIRE_USE_3D_MODELS=1`) sets `AnimationPlayer.root_motion_track='Armature/Skeleton3D:Hips'` and skips manual anchor cancel. Headless probe: `test_settler_root_motion_track_probe.gd`.
- **Remap:** inspector **Use Glb Animation Name Remap** on `Warrior3DUnitMarkersView` (default on).
- **Asset folder:** `game/assets/prototype/3d/units/settler/`
- **Implementation:** `game/presentation/warrior_3d_unit_markers_view.gd` (shared SubViewport markers); see `docs/RENDERING.md`.
- **Orientation defaults:** model yaw **+48°** (three-quarter toward screen-right; GLB faces **-Z** at yaw 0). Same SubViewport camera as warrior.
