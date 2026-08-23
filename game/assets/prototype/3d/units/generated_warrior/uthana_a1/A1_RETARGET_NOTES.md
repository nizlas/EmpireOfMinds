# A1 Uthana retarget notes

## Method (acceptance)
- `godot_import_humanoid_retarget` -- Godot 4.6.2 import-time SkeletonProfileHumanoid + BoneMap + Rest Fixer
- Docs: https://docs.godotengine.org/en/latest/tutorials/assets_pipeline/retargeting_3d_skeletons.html
- Custom baked `global_hierarchical_rest_delta` is FAILED and is not used by acceptance preview/tests.

## Isolation
- Godot cannot attach a second import config to the production GLB paths.
- A1 uses byte-identical copies under `import_sources/` with separate `.import` files.
- Original Meshy/Uthana GLBs remain unchanged.

## Paths
- Meshy original (immutable): `res://assets/prototype/3d/units/generated_warrior/generated_warrior_3d.glb`
- Uthana original (immutable): `res://assets/prototype/3d/units/generated_warrior/uthana_a0/generated_warrior_3d_uthana_rigged.glb`
- A1 Meshy source copy: `res://assets/prototype/3d/units/generated_warrior/uthana_a1/import_sources/a1_meshy_walking_source.glb`
- A1 Uthana target copy: `res://assets/prototype/3d/units/generated_warrior/uthana_a1/import_sources/a1_uthana_target.glb`
- Canonical Walking library: `res://assets/prototype/3d/units/generated_warrior/uthana_a1/a1_native_walking.res`
- Preview: `res://assets/prototype/3d/units/generated_warrior/uthana_a1/uthana_a1_walking_preview.tscn`

## Importer settings (source PackedScene -> extract Walking library)
- Godot rewrites type=AnimationLibrary back to PackedScene on headless import; Walking is extracted to `a1_native_walking.res`.
- Remove Tracks / Except Bone Transform = false (4.6.2 bug: collapses multi-key rotations)
- Remove Tracks / Unimportant Positions = true
- Remove Tracks / Unmapped Bones = Remove
- animation/remove_immutable_tracks = false
- Bone Renamer + unique `GeneralSkeleton`
- Rest Fixer: Apply Node Transform, Normalize Position Tracks, Overwrite Axis
- Rest Fixer / Fix Silhouette = true (Meshy A-pose); filter/base_height unused (no measured need)

## Importer settings (target PackedScene)
- Bone Renamer + unique `GeneralSkeleton`
- Rest Fixer: Apply Node Transform, Normalize Position Tracks, Overwrite Axis
- Fix Silhouette = false (Uthana already T-pose)

## Scale / orientation
- Preview ModelRoot scale `0.30`, yaw `0.0`
- Ground offset recalculated from natively imported target feet.

## Last extract
- ok: `true`
- path: `res://assets/prototype/3d/units/generated_warrior/uthana_a1/a1_native_walking.res`
- tracks: `45`
- length: `1.03333330154419`

## Launch
Open `res://assets/prototype/3d/units/generated_warrior/uthana_a1/uthana_a1_walking_preview.tscn` (F6).
Automated gate does **not** claim visual PASS -- F6 required.
Optional diagnostic: `uthana_a1_side_by_side_diagnostic.tscn`.
