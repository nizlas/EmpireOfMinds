# Empire of Minds — Blender terrain prototype (7 hex)

Visual proof-of-concept for a future real 3D terrain model. **Not** runtime terrain, **not** canonical gameplay, and **not** connected to Godot or tile-improvement rules.

Six Blender scripts exist:

| Script | Model | Default output |
|--------|-------|----------------|
| `generate_terrain_prototype.py` | Per-hex analytic top surface (milestone / reference) | `terrain_prototype_7_hex.blend` |
| `generate_terrain_heightfield_prototype.py` | Multi-mesh global IDW heightfield | `terrain_prototype_7_hex_heightfield.blend` |
| `generate_terrain_single_patch_prototype.py` | Single mesh, radial hill, separate hex overlay (approved geometry milestone) | `terrain_prototype_7_hex_single_patch.blend` |
| `generate_terrain_single_patch_material_prototype.py` | Same geometry as single-patch; procedural material proof of concept | `terrain_prototype_7_hex_single_patch_material.blend` |
| `generate_terrain_single_patch_pbr_ground_prototype.py` | Same geometry + procedural ash/stone; tileable PBR ground layer (Object coords) | `terrain_prototype_7_hex_single_patch_pbr_ground.blend` |
| `generate_terrain_single_patch_pbr_ground_uv_prototype.py` | **Approved** ground-PBR baseline via world-anchored planar UV | `terrain_prototype_7_hex_single_patch_pbr_ground_uv.blend` |

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

Each script clears the current scene, builds the cluster, sets up camera/lights/material, and optionally saves output.

`bpy` exists only inside Blender. Syntax can be checked outside Blender with:

```powershell
python -c "import ast; ast.parse(open('tools/blender/terrain/generate_terrain_prototype.py', encoding='utf-8').read())"
python -c "import ast; ast.parse(open('tools/blender/terrain/generate_terrain_heightfield_prototype.py', encoding='utf-8').read())"
python -c "import ast; ast.parse(open('tools/blender/terrain/generate_terrain_single_patch_prototype.py', encoding='utf-8').read())"
python -c "import ast; ast.parse(open('tools/blender/terrain/generate_terrain_single_patch_material_prototype.py', encoding='utf-8').read())"
python -c "import ast; ast.parse(open('tools/blender/terrain/generate_terrain_single_patch_pbr_ground_prototype.py', encoding='utf-8').read())"
python -c "import ast; ast.parse(open('tools/blender/terrain/generate_terrain_single_patch_pbr_ground_uv_prototype.py', encoding='utf-8').read())"
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
