# Empire of Minds — Blender terrain prototype (7 hex)

Visual proof-of-concept for a future real 3D terrain model. **Not** runtime terrain, **not** canonical gameplay, and **not** connected to Godot or tile-improvement rules.

Handdrawn full-map terrain prototypes (`generate_terrain_terrainmap_handdrawn_full_01.py` and `run_*_blend_regen.py` runners) are indexed in **[TERRAIN_PROTOTYPE_MANIFEST.md](TERRAIN_PROTOTYPE_MANIFEST.md)**. The approved smooth TS-03 baseline is regenerated via **`generate_ts03_global_continuous_baseline.py`** (not the legacy cliff-cut `run_ts_variational_spline_blend_regen.py` path). Frozen baseline blends are audited read-only via `audit_ts03_baseline_blend.py`.

Seven Blender scripts exist:

| Script | Model | Default output |
|--------|-------|----------------|
| `generate_terrain_prototype.py` | Per-hex analytic top surface (milestone / reference) | `terrain_prototype_7_hex.blend` |
| `generate_terrain_heightfield_prototype.py` | Multi-mesh global IDW heightfield | `terrain_prototype_7_hex_heightfield.blend` |
| `generate_terrain_single_patch_prototype.py` | Single mesh, radial hill, separate hex overlay (approved geometry milestone) | `terrain_prototype_7_hex_single_patch.blend` |
| `generate_terrain_single_patch_material_prototype.py` | Same geometry as single-patch; procedural material proof of concept | `terrain_prototype_7_hex_single_patch_material.blend` |
| `generate_terrain_single_patch_pbr_ground_prototype.py` | Same geometry + procedural ash/stone; tileable PBR ground layer (Object coords) | `terrain_prototype_7_hex_single_patch_pbr_ground.blend` |
| `generate_terrain_single_patch_pbr_ground_uv_prototype.py` | **Approved** ground-PBR baseline via world-anchored planar UV | `terrain_prototype_7_hex_single_patch_pbr_ground_uv.blend` |
| `generate_terrain_single_patch_pbr_ground_stone_prototype.py` | Approved ground-PBR UV + full stone PBR via existing stone splat weight | `terrain_prototype_7_hex_single_patch_pbr_ground_stone.blend` |
| `generate_terrain_single_patch_pbr_ground_stone_ash_prototype.py` | Approved ground + stone PBR UV + full ash PBR via existing ash splat weight | `terrain_prototype_7_hex_single_patch_pbr_ground_stone_ash.blend` |
| `generate_terrain_single_patch_pbr_ground_stone_ash_niclas_demo.py` | Niclas idle/kick visual demo on locked porting baseline (no terrain retune) | `terrain_prototype_7_hex_single_patch_pbr_ground_stone_ash_niclas_demo.blend` |

The third prototype generates one continuous terrain mesh (no per-hex terrain geometry), plus a toggleable `EOM_Hex_Overlay` object in Blender for logical hex edges. It is **not** runtime terrain or canonical gameplay implementation.

The fourth script copies that approved geometry unchanged and prototypes procedural terrain material blending (ground / ash / stone layers, slope masks, noise variation). Tileable PBR textures are expected to replace the simple procedural colors later while keeping the same blend logic.

The fifth script adds the first tileable PBR ground texture set while ash and stone remain procedural colors with the existing mask/splatting logic. Ground normal and roughness maps currently provide shared surface microdetail across the whole top surface until ash/stone receive their own PBR sets. Object-space texture coordinates can show tangent-space normal triangulation artifacts on curved top surfaces.

The sixth script is the **visually approved Blender 5.1.2 ground-PBR baseline**. Top faces use an explicit world-anchored planar UV layer (`EOM_WorldUV`) derived from stable object/world XY positions (`U = X * WORLD_UV_SCALE`, `V = Y * WORLD_UV_SCALE`). Albedo, roughness, and tangent-space normal maps sample through one shared `ShaderNodeUVMap` → `ShaderNodeMapping` chain, giving a stable tangent basis without the triangle-shaped shading artifacts seen with object-space projection. UV is **not** normalized per patch or per hex; values may lie outside 0–1 and repeat via texture `REPEAT`. Future terrain chunks must share the same texture origin, axis directions, and `WORLD_UV_SCALE`. Side/chamfer/skirt/bottom faces still use the separate side material (cliff UV is future work). Stone and ash remain procedural colors with the existing splat weights; their PBR texture sets are the next separate prototype passes. See `Empire_of_Minds_World_Anchored_UV_and_Chunk_Continuity.docx` (design reference; not modified by these scripts).

### Approved ground-PBR UV baseline (`generate_terrain_single_patch_pbr_ground_uv_prototype.py`)

| Item | Value |
|------|-------|
| Script | `tools/blender/terrain/generate_terrain_single_patch_pbr_ground_uv_prototype.py` |
| Blend output | `game/assets/prototype/3d/terrain/prototype_3d_terrain/generated/terrain_prototype_7_hex_single_patch_pbr_ground_uv.blend` |
| GLB output | `game/assets/prototype/3d/terrain/prototype_3d_terrain/generated/terrain_prototype_7_hex_single_patch_pbr_ground_uv.glb` |
| UV layer | `EOM_WorldUV` on top faces only |
| UV formula | `U = object_x * WORLD_UV_SCALE`, `V = object_y * WORLD_UV_SCALE` (default scale `0.35`) |
| Ground PBR coord chain | `ShaderNodeUVMap` → `Ground UV Mapping` → `ground_albedo` / `ground_normal` / `ground_roughness` |
| Textures | `source/materials/ground/ground_albedo.png`, `ground_normal.png`, `ground_roughness.png` |

**Verified in Blender 5.1.2:** script completes; world-anchored UV is continuous across hex boundaries; tangent-space normal is active without hill-edge triangulation artifacts; normal response is smooth under rotating Material Preview light; subtle surface pits read naturally; prior normal/roughness mask worm artifacts are gone; side/skirt/chamfer/bottom unchanged.

**Not in this milestone:** stone PBR, ash PBR, chunk tiling, cliff UV, Godot import.

**Next separate step:** add stone and ash PBR material packs and wire them through the existing stone mask and ground/ash splat weights.

The seventh script adds a full stone PBR layer (`stone_albedo.png`, `stone_normal.png`, `stone_roughness.png`) on top of the approved ground-PBR UV baseline. Stone textures use the same `EOM_WorldUV` layer and `ShaderNodeUVMap` → `Ground UV Mapping` chain as ground. The **existing final stone weight** (slope mask + stone breakup, unchanged) drives albedo, tangent-space normal, and roughness together. Ground baseline values and graph are preserved; ash remains procedural color and still shares ground PBR normal/roughness under ash until a separate ash-PBR pass.

### Stone PBR prototype (`generate_terrain_single_patch_pbr_ground_stone_prototype.py`)

| Item | Value |
|------|-------|
| Script | `tools/blender/terrain/generate_terrain_single_patch_pbr_ground_stone_prototype.py` |
| Blend output | `game/assets/prototype/3d/terrain/prototype_3d_terrain/generated/terrain_prototype_7_hex_single_patch_pbr_ground_stone.blend` |
| GLB output | `game/assets/prototype/3d/terrain/prototype_3d_terrain/generated/terrain_prototype_7_hex_single_patch_pbr_ground_stone.glb` |
| Stone textures | `source/materials/stone/stone_albedo.png`, `stone_normal.png`, `stone_roughness.png` |
| Stone splat | Existing `mix_stone` factor (slope + breakup) — no new mask |
| Stone albedo darken | `STONE_ALBEDO_MULTIPLIER` (default `0.55`; `1.0` = unchanged source albedo) |
| Debug stages (new) | `stone_albedo`, `stone_normal`, `stone_roughness`, `ground_stone_pbr` |

`STONE_ALBEDO_MULTIPLIER` darkens stone albedo RGB before splat blending only. It does not affect stone mask coverage, normal, or roughness. Lower values darken stone; `1.0` preserves the source texture. Initial evaluation baseline: `0.55`.

**Known limits:** no ash PBR, no chunk tiling, no cliff UV, no Godot import. Side/skirt/chamfer/bottom use separate side material.

**Next step:** separate ash-PBR prototype wired through existing ground/ash splat weights.

The eighth script adds a full ash PBR layer (`ash_albedo.png`, `ash_normal.png`, `ash_roughness.png`) on top of the approved ground + stone PBR UV baseline. Ash textures use the same `EOM_WorldUV` layer and `ShaderNodeUVMap` → `Ground UV Mapping` chain as ground and stone. The **existing ash weight** (large-scale noise mask, unchanged) drives ash albedo, tangent-space normal, and roughness together. The **existing stone weight** still applies after ground/ash blending. Ground and stone baseline values and masks are preserved; this is the first full three-layer PBR splatting prototype.

### Ash PBR prototype (`generate_terrain_single_patch_pbr_ground_stone_ash_prototype.py`)

| Item | Value |
|------|-------|
| Script | `tools/blender/terrain/generate_terrain_single_patch_pbr_ground_stone_ash_prototype.py` |
| Blend output | `game/assets/prototype/3d/terrain/prototype_3d_terrain/generated/terrain_prototype_7_hex_single_patch_pbr_ground_stone_ash.blend` |
| GLB output | `game/assets/prototype/3d/terrain/prototype_3d_terrain/generated/terrain_prototype_7_hex_single_patch_pbr_ground_stone_ash.glb` |
| Ash textures | `source/materials/ash/ash_albedo.png`, `ash_normal.png`, `ash_roughness.png` |
| Ash splat | Regional `large_factor_map.Result` × medium-frequency breakup → ash-weight remap → `mix_ground_ash` factor |
| Ash weight remap | `ASH_WEIGHT_INPUT_MIN`/`ASH_WEIGHT_INPUT_MAX` = `0.30`/`0.95` (approved baseline) |
| Stone splat | Slope mask + stone breakup; applied after ground/ash blend |
| Ash PBR params | `ASH_ALBEDO_TINT_STRENGTH=0.0`, `ASH_NORMAL_STRENGTH=0.55`, `ASH_ROUGHNESS_MULTIPLIER=1.0`, `ASH_ROUGHNESS_VARIATION_STRENGTH=0.0` |
| Debug stages (new) | `ash_albedo`, `ash_normal`, `ash_roughness`, `ash_mask`, `ground_ash_pbr`, `ground_stone_ash_pbr` |
| Brightness diagnostics | `ash_albedo_raw` (Emission bypass, raw PNG color) and `ash_albedo_diffuse` (neutral matte Principled, Specular IOR Level 0) — for isolating Material Preview lighting vs texture data |
| Mask diagnostics | `ash_mask_raw` shows regional ash source (`large_factor_map.Result`) through Emission; `ash_breakup_raw` shows breakup factor only; `ash_mask_combined_raw` shows regional source after breakup multiply (before ash-weight remap); `ash_mask_remapped_raw` shows the final remapped PBR splat weight through Emission — all unaffected by lighting |

#### Approved Blender porting baseline — 2026-06-15

**Verified in Blender 5.1.2.** Scene World + Scene Lights were used as the reference for material assessment. Standard screenshots (not mobile photos) were used for color evaluation.

This baseline is the **reproducible Blender source for the upcoming Godot port**. It is not a claim about final in-game luminance — overall luminance and lighting must still be validated in the Godot runtime environment.

**What works in this baseline:**

- Three-layer ground / ash / stone PBR
- Continuous world-anchored UV (`EOM_WorldUV`, `WORLD_UV_SCALE=0.35`)
- Tangent-space normal maps without triangle-shaped artifacts
- Ground, ash, and stone share the same UV source
- Same splat weight per layer drives albedo, normal, and roughness
- Blend order: ground ↔ ash, then result ↔ stone

**Ash mask chain:** regional `large_factor_map.Result` source → medium-frequency breakup → final weight remap (`ASH_WEIGHT_INPUT_MIN/MAX` = `0.30`/`0.95`).

**Stone mask chain:** slope mask + breakup (`STONE_BREAKUP_STRENGTH=0.080`).

**`USE_FINE_DETAIL = False` is intentionally locked.** Fine-detail albedo modulation produced a global gray patchy haze; `FINE_NOISE_*` parameters remain for future dedicated experiments only.

**Guardrail:** `APPROVED_BLENDER_PORTING_BASELINE` is checked at startup via `_validate_blender_porting_baseline()`. Changes to locked parameters raise `RuntimeError` unless `ALLOW_BLENDER_PORTING_BASELINE_RETUNE = True`.

**Do not retune this Blender source during the Godot port** unless a dedicated baseline revision is explicitly requested.

**Baseline revision procedure:**

1. Create a separate baseline-revision task.
2. Set `ALLOW_BLENDER_PORTING_BASELINE_RETUNE = True`.
3. Change one parameter family at a time.
4. Verify in Blender (Scene World + Scene Lights).
5. Update `APPROVED_BLENDER_PORTING_BASELINE` and this README.
6. Reset `ALLOW_BLENDER_PORTING_BASELINE_RETUNE = False` before completing the pass.

**Ash breakup:** regional ash source subdivided multiplicatively by calm medium-frequency breakup before ash-weight remap. Stone weight still applies after ground/ash blending.

All nine PBR textures (ground, ash, stone albedo/normal/roughness) share one world-anchored UV source: `ShaderNodeUVMap` (`EOM_WorldUV`) → `Ground UV Mapping` → image textures. No separate ash UV layer or mapping scale.

Blend order: ground ↔ ash (existing ash weight) → result ↔ stone (existing stone weight). Side/chamfer/skirt/bottom still use the separate side material.

**Known limits:** no chunk tiling, no cliff UV, no Godot import, no height-based blending. Height-based layer blending remains future work.

**Next step:** Godot port of material and lighting logic from this Blender baseline.

## Purpose

Explore flat-top hex meshes where:

- each hex has a central elevation level;
- each outer edge height is the average of the two adjacent hex levels;
- low hex rises toward a shared edge, high hex falls toward the same edge;
- the east neighbor of the center hex is a hill so the shared edge sits halfway between plain and hill.

The first prototype is a fixed **7-hex cluster** (center + six neighbors) generated by script, not hand-placed variants.

## How to run

**Per-hex analytic milestone:**

1. Open **Blender** (3.x or 4.x with Python API).
2. **Scripting** workspace → **Open** → `tools/blender/terrain/generate_terrain_prototype.py`
3. Click **Run Script**.

**Global heightfield prototype:**

1. **Scripting** workspace → **Open** → `tools/blender/terrain/generate_terrain_heightfield_prototype.py`
2. **Text → Reload** (after edits) → **Run Script**.

**Single-patch radial hill prototype (geometry milestone):**

1. **Scripting** workspace → **Open** → `tools/blender/terrain/generate_terrain_single_patch_prototype.py`
2. **Text → Reload** → **Run Script**.
3. In the outliner, toggle visibility of `EOM_Hex_Overlay` to show/hide the logical hex grid.

**Single-patch procedural material prototype:**

1. **Scripting** workspace → **Open** → `tools/blender/terrain/generate_terrain_single_patch_material_prototype.py`
2. **Text → Reload** → **Run Script**.
3. Switch to **Layout** and **Material Preview** to inspect the procedural terrain material.

**Single-patch PBR ground prototype:**

1. Place required textures under `game/assets/prototype/3d/terrain/prototype_3d_terrain/source/materials/ground/`:
   - `ground_albedo.png`
   - `ground_normal.png`
   - `ground_roughness.png`
2. **Scripting** workspace → **Open** → `tools/blender/terrain/generate_terrain_single_patch_pbr_ground_prototype.py`
3. **Text → Reload** → **Run Script**.
4. Switch to **Layout** and **Material Preview**.
5. Adjust `GROUND_TEXTURE_SCALE` at the top of the script if tiles feel too large or too small (higher = more repeats).

**Single-patch PBR ground world-UV prototype (approved baseline):**

1. Same ground textures as the PBR ground milestone (paths above).
2. **Scripting** workspace → **Open** → `tools/blender/terrain/generate_terrain_single_patch_pbr_ground_uv_prototype.py`
3. **Text → Reload** → **Run Script**.
4. Switch to **Layout** and **Material Preview**.
5. Smoke test: `DEBUG_MATERIAL_STAGE = "ground_pbr"` then `"final"`; confirm no triangle artifacts on hill edges, continuous texture across hex boundaries, smooth normal under rotating light.
6. Optional **UV Editor** check: continuous planar XY layout on `EOM_WorldUV` (not per-hex islands).
7. Do not change `WORLD_UV_SCALE` or material tuning unless starting a new deliberate baseline pass.

**Single-patch PBR ground + stone prototype:**

1. Place ground textures under `source/materials/ground/` and stone textures under `source/materials/stone/`:
   - `stone_albedo.png`, `stone_normal.png`, `stone_roughness.png`
2. **Scripting** workspace → **Open** → `tools/blender/terrain/generate_terrain_single_patch_pbr_ground_stone_prototype.py`
3. **Text → Reload** → **Run Script**.
4. **Material Preview** smoke test: `stone_albedo` → `stone_normal` → `stone_roughness` → `stone_mask` → `ground_stone_pbr` → `final`.
5. Confirm stone appears only where the existing stone weight activates; ground unchanged elsewhere; ash still procedural.

**Single-patch PBR ground + stone + ash prototype:**

1. Place ground textures under `source/materials/ground/`, stone under `source/materials/stone/`, and ash under `source/materials/ash/`:
   - `ash_albedo.png`, `ash_normal.png`, `ash_roughness.png`
2. **Scripting** workspace → **Open** → `tools/blender/terrain/generate_terrain_single_patch_pbr_ground_stone_ash_prototype.py`
3. **Text → Reload** → **Run Script**.
4. **Material Preview** smoke test: `ash_albedo` → `ash_normal` → `ash_roughness` → `ash_mask` → `ground_ash_pbr` → `ground_stone_ash_pbr` → `final`.
5. Confirm ash appears only where the existing ash weight activates; stone blend unchanged from stone milestone; ground unchanged where ash-weight = 0.

**Niclas idle/kick demo on approved porting baseline:**

1. Same ground/stone/ash textures as the ash PBR milestone.
2. Niclas asset at `game/assets/prototype/3d/units/niclas/niclas_3d.glb` (actions `Idle_3`, `Flying_Fist_Kick`).
3. **Scripting** workspace → **Open** → `tools/blender/terrain/generate_terrain_single_patch_pbr_ground_stone_ash_niclas_demo.py`
4. **Text → Reload** → **Run Script**.
5. Press timeline **Play** and verify at least three full cycles: trimmed idle → full kick → reset → repeat.
6. Niclas stands on west outer hex `(-1,0)` with center `(0,0)` between him and hill `(1,0)`; faces flat neighbor `(0,0)` so kick root motion moves along flat ground (not toward hill or patch edge).
7. Does **not** modify the locked terrain baseline script or its output files.

This is a visual prototype only: idle is trimmed to `NICLAS_IDLE_DURATION_SECONDS` (default `2.5`); kick always plays its full imported frame range with root motion preserved; world transform resets at each cycle boundary to prevent drift. No Godot or gameplay changes.

Each script clears the current scene, builds the cluster, sets up camera/lights/material, and optionally saves output.

`bpy` exists only inside Blender. Syntax can be checked outside Blender with:

```powershell
python -c "import ast; ast.parse(open('tools/blender/terrain/generate_terrain_prototype.py', encoding='utf-8').read())"
python -c "import ast; ast.parse(open('tools/blender/terrain/generate_terrain_heightfield_prototype.py', encoding='utf-8').read())"
python -c "import ast; ast.parse(open('tools/blender/terrain/generate_terrain_single_patch_prototype.py', encoding='utf-8').read())"
python -c "import ast; ast.parse(open('tools/blender/terrain/generate_terrain_single_patch_material_prototype.py', encoding='utf-8').read())"
python -c "import ast; ast.parse(open('tools/blender/terrain/generate_terrain_single_patch_pbr_ground_prototype.py', encoding='utf-8').read())"
python -c "import ast; ast.parse(open('tools/blender/terrain/generate_terrain_single_patch_pbr_ground_uv_prototype.py', encoding='utf-8').read())"
python -c "import ast; ast.parse(open('tools/blender/terrain/generate_terrain_single_patch_pbr_ground_stone_prototype.py', encoding='utf-8').read())"
python -c "import ast; ast.parse(open('tools/blender/terrain/generate_terrain_single_patch_pbr_ground_stone_ash_prototype.py', encoding='utf-8').read())"
python -c "import ast; ast.parse(open('tools/blender/terrain/generate_terrain_single_patch_pbr_ground_stone_ash_niclas_demo.py', encoding='utf-8').read())"
```

## Output

Default paths (repo-relative, resolved from script location):

| File | Path |
|------|------|
| Analytic blend | `game/assets/prototype/3d/terrain/prototype_3d_terrain/generated/terrain_prototype_7_hex.blend` |
| Analytic GLB | `game/assets/prototype/3d/terrain/prototype_3d_terrain/generated/terrain_prototype_7_hex.glb` |
| Heightfield blend | `game/assets/prototype/3d/terrain/prototype_3d_terrain/generated/terrain_prototype_7_hex_heightfield.blend` |
| Heightfield GLB | `game/assets/prototype/3d/terrain/prototype_3d_terrain/generated/terrain_prototype_7_hex_heightfield.glb` |
| Single-patch blend | `game/assets/prototype/3d/terrain/prototype_3d_terrain/generated/terrain_prototype_7_hex_single_patch.blend` |
| Single-patch GLB | `game/assets/prototype/3d/terrain/prototype_3d_terrain/generated/terrain_prototype_7_hex_single_patch.glb` |
| Single-patch material blend | `game/assets/prototype/3d/terrain/prototype_3d_terrain/generated/terrain_prototype_7_hex_single_patch_material.blend` |
| Single-patch material GLB | `game/assets/prototype/3d/terrain/prototype_3d_terrain/generated/terrain_prototype_7_hex_single_patch_material.glb` |
| Single-patch PBR ground blend | `game/assets/prototype/3d/terrain/prototype_3d_terrain/generated/terrain_prototype_7_hex_single_patch_pbr_ground.blend` |
| Single-patch PBR ground GLB | `game/assets/prototype/3d/terrain/prototype_3d_terrain/generated/terrain_prototype_7_hex_single_patch_pbr_ground.glb` |
| Single-patch PBR ground UV blend | `game/assets/prototype/3d/terrain/prototype_3d_terrain/generated/terrain_prototype_7_hex_single_patch_pbr_ground_uv.blend` |
| Single-patch PBR ground UV GLB | `game/assets/prototype/3d/terrain/prototype_3d_terrain/generated/terrain_prototype_7_hex_single_patch_pbr_ground_uv.glb` |
| Single-patch PBR ground + stone blend | `game/assets/prototype/3d/terrain/prototype_3d_terrain/generated/terrain_prototype_7_hex_single_patch_pbr_ground_stone.blend` |
| Single-patch PBR ground + stone GLB | `game/assets/prototype/3d/terrain/prototype_3d_terrain/generated/terrain_prototype_7_hex_single_patch_pbr_ground_stone.glb` |
| Single-patch PBR ground + stone + ash blend | `game/assets/prototype/3d/terrain/prototype_3d_terrain/generated/terrain_prototype_7_hex_single_patch_pbr_ground_stone_ash.blend` |
| Single-patch PBR ground + stone + ash GLB | `game/assets/prototype/3d/terrain/prototype_3d_terrain/generated/terrain_prototype_7_hex_single_patch_pbr_ground_stone_ash.glb` |

The output folder is created if missing.

**Do not overwrite** the manual source asset:

`game/assets/prototype/3d/terrain/prototype_3d_terrain/source/empire_of_minds_terrain_prototype_01.blend`

## Main parameters (top of script)

| Parameter | Meaning |
|-----------|---------|
| `HEX_RADIUS` | Circumradius (center → corner); controls hex size and spacing |
| `BASE_THICKNESS` | Solid depth below top surface |
| `INNER_RADIUS_FACTOR` | Inner flat plateau size (fraction of `HEX_RADIUS`) |
| `ELEVATION_STEP` | World Z units per elevation level |
| `PLAIN_LEVEL` / `HILL_LEVEL` | Integer levels used in the prototype layout |
| `SAVE_BLEND` / `EXPORT_GLB` | Toggle file output (default: save blend, no GLB) |
| `OUTPUT_BLEND_PATH` / `OUTPUT_GLB_PATH` | Override output filenames |

## Layout (default)

| Hex | Axial (q, r) | Level | Label |
|-----|--------------|-------|-------|
| Center | (0, 0) | 0 | Plain |
| East | (1, 0) | 1 | Hill |
| Other five neighbors | ring around center | 0 | Plain |

## Hex coordinate model

- **Flat-top** axial coordinates `(q, r)`.
- Center world position: `x = R·√3·(q + r/2)`, `y = R·1.5·r` (circumradius `R`).
- Six neighbors: East, NE, NW, West, SW, SE (see `NEIGHBOR_DIRS` in script).
- Corners numbered CCW from 30°; edge `i` connects corner `i` → `(i+1) % 6`.
- Neighbor direction `d` maps to physical edge `(d - 1) % 6` (East → edge 5).

## Shared edge heights

Lattice corner world positions are keyed and each corner height is the **mean elevation** of every hex in the cluster that touches that corner.

- **Two hexes** at a corner → halfway blend.
- **Three hexes** at a corner (typical in this 7-hex cluster) → triple average.

Example: the east edge between center plain (0) and east hill (1) has a pure **two-hex edge blend** of `0.5` level units, but each endpoint corner also touches a third plain hex → corner Z = `(0+1+0)/3 × ELEVATION_STEP`. Both adjacent meshes use the same keyed corner, so the shared rim slopes without a vertical seam.

Adjacent hex center distance = `√3 × HEX_RADIUS` (verified).

## Scene objects

- Collection: `EOM_Terrain_Prototype`
- Meshes: `Hex_{q}_{r}_Plain` / `Hex_{q}_{r}_Hill`
- Material: `EOM_Terrain_Prototype` (single shared instance, object-space noise)
- Camera: `PrototypeCamera`
- Sun: `PrototypeSun`

## Out of scope (this version)

- Geometry Nodes
- External Python dependencies
- Vegetation, quarry, Worker, improvements, gameplay
- Godot import or runtime terrain
- Modifying `source/` manual blend or 2D terrain / projection code
