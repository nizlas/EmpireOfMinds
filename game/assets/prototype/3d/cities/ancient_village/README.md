# Ancient village 3D city marker (prototype)

- **Model:** `ancient_village.glb` — static map diorama (no animation).
- **Enable on map:** `EMPIRE_USE_3D_MODELS=1` replaces `city_marker.png` with this GLB.
- **Path:** `res://assets/prototype/3d/cities/ancient_village/ancient_village.glb`
- **Implementation:** `game/presentation/city_3d_markers_view.gd` (SubViewport markers); registered via `Warrior3DUnitExperiment.city_scene_path()`.
- **Material:** runtime matte override (`metallic=0`, `roughness≈0.85`) when Meshy-like porcelain import is detected.
- **Scale:** tune via `City3DMarkersView` exports on `main.tscn` (`model_scale`, `model_offset_y`, camera framing).
