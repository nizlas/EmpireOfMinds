# Empire of Minds — Handdrawn full-map terrain prototype manifest

Traceability index for `generate_terrain_terrainmap_handdrawn_full_01.py` and its
`run_*_blend_regen.py` runners. Each row is one selectable prototype path.

**Frozen baseline artifact (never overwritten by runners):**

| Item | Value |
|------|-------|
| File | `game/assets/prototype/3d/terrain/prototype_3d_terrain/generated/terrain_handdrawn_test_map_full_01_variational_spline_BASELINE_2026-06-27.blend` |
| Origin | Copy of `..._variational_spline.blend1` (mtime 2026-06-27 14:37) |
| Status | **APPROVED BASELINE (frozen)** |
| Audit | `blender --background --python tools/blender/terrain/audit_ts03_baseline_blend.py` (read-only) |

---

## TS-03 — Variational spline (approved baseline)

| Field | Value |
|-------|-------|
| Prototype ID | `TS-03` |
| Runner | `tools/blender/terrain/run_ts_variational_spline_blend_regen.py` |
| Output | `terrain_handdrawn_test_map_full_01_variational_spline.blend` |
| Solver | `VariationalSplineTerrainSolver` (`TerrainBackend.variational_spline`) |
| Flags | `USE_VARIATIONAL_SPLINE_SURFACE=True`; all other TS flags `False` |
| Cliff behavior | Standard cliff-wall placeholder geometry (not debug-isolated) |
| Material behavior | Full PBR ground/stone/ash splatting via locked 7-hex baseline |
| Status | **APPROVED BASELINE** |

Visual target: one broad continuous smooth TPS-like surface; material/splatting works;
no holes; no disconnected surfaces; cliff walls exist but must not dominate as blocky
plateaus. Matches 2026-06-27 screenshots.

Math reference: `Empire_of_Minds_TS03_Surface_Math_Spec_EXTENDED.docx`.

---

## TS-03e — Cliff wall visibility debug

| Field | Value |
|-------|-------|
| Prototype ID | `TS-03e` |
| Runner | `tools/blender/terrain/run_ts_cliff_wall_debug_blend_regen.py` |
| Output | `terrain_handdrawn_test_map_full_01_variational_spline_cliff_debug.blend` |
| Solver | `VariationalSplineTerrainSolver` |
| Flags | `USE_VARIATIONAL_SPLINE_SURFACE=True`, `DEBUG_SHOW_CLIFF_WALLS=True`, `DEBUG_HIDE_TOP_SURFACE=True` |
| Cliff behavior | Mid-grey cliff debug material; top surface hidden; isolated cliff object |
| Material behavior | Cliff debug material only (rendering verification) |
| Status | **EXPERIMENTAL** (debug overlay) |

---

## TS-07a — Control clone of TS-03

| Field | Value |
|-------|-------|
| Prototype ID | `TS-07a` |
| Runner | `tools/blender/terrain/run_ts07a_ts03_clone_blend_regen.py` |
| Output | `terrain_handdrawn_test_map_full_01_ts07a_ts03_clone.blend` |
| Solver | `VariationalSplineTerrainSolver` |
| Flags | `USE_VARIATIONAL_SPLINE_SURFACE=True`, `USE_TS07A_TS03_CLONE=True`; TS-05/06 off |
| Cliff behavior | Same as TS-03 |
| Material behavior | Same as TS-03 |
| Status | **EXPERIMENTAL** (control clone; alternate output filename only) |

---

## TS-02 — Global biharmonic (diagnostic)

| Field | Value |
|-------|-------|
| Prototype ID | `TS-02` |
| Runner | `tools/blender/terrain/run_tsglobal_biharmonic_blend_regen.py` |
| Output | `terrain_handdrawn_test_map_full_01_global_biharmonic.blend` |
| Solver | `GlobalBiharmonicTerrainSolver` |
| Flags | `USE_GLOBAL_BIHARMONIC_SURFACE=True` |
| Cliff behavior | Standard cliff walls |
| Material behavior | Full PBR splatting |
| Status | **EXPERIMENTAL / DIAGNOSTIC** (falsified discrete formulation) |

---

## TS-04 — FEM thin plate (diagnostic)

| Field | Value |
|-------|-------|
| Prototype ID | `TS-04` |
| Runner | `tools/blender/terrain/run_ts_fem_thin_plate_blend_regen.py` |
| Output | `terrain_handdrawn_test_map_full_01_fem_thin_plate.blend` |
| Solver | `FemThinPlateTerrainSolver` |
| Flags | `USE_FEM_THIN_PLATE_SURFACE=True` |
| Cliff behavior | Cliff-cut mesh |
| Material behavior | Full PBR splatting |
| Status | **EXPERIMENTAL / DIAGNOSTIC** |

---

## TS-05 — TPS cliff-band release (deprecated path)

| Field | Value |
|-------|-------|
| Prototype ID | `TS-05` |
| Runner | `tools/blender/terrain/run_ts05_tps_cliff_release_blend_regen.py` |
| Output | `terrain_handdrawn_test_map_full_01_tps_cliff_release.blend` |
| Solver | `TpsCliffReleaseTerrainSolver` (wraps variational spline) |
| Flags | `USE_VARIATIONAL_SPLINE_SURFACE=True`, `USE_TPS_CLIFF_RELEASE=True`, `USE_TS05_DEBUG_OVERLAY=True` |
| Cliff behavior | Release bands at cliff fronts (not baseline) |
| Material behavior | Full PBR splatting + TS-05 debug overlay collection |
| Status | **DEPRECATED** (release bands; not the approved baseline) |

---

## TS-06 — TPS rim constraints (deprecated path)

| Field | Value |
|-------|-------|
| Prototype ID | `TS-06` |
| Runner | `tools/blender/terrain/run_ts06_tps_rim_constraints_blend_regen.py` |
| Output | `terrain_handdrawn_test_map_full_01_tps_rim_constraints.blend` |
| Solver | `TpsRimConstraintsTerrainSolver` |
| Flags | `USE_VARIATIONAL_SPLINE_SURFACE=True`, `USE_TPS_RIM_CONSTRAINTS=True` |
| Cliff behavior | Explicit rim constraints (PDE-style; not baseline) |
| Material behavior | Full PBR splatting |
| Status | **DEPRECATED** (rim constraints; not the approved baseline) |

---

## HXP-03 — HexPatch v1 diagnostic

| Field | Value |
|-------|-------|
| Prototype ID | `HXP-03` |
| Runner | `tools/blender/terrain/run_hxp03_v1_blend_regen.py` |
| Output | `terrain_handdrawn_test_map_full_01_hexpatch_v1.blend` |
| Solver | `HexPatchV1TerrainSolver` |
| Flags | `USE_HEXPATCH_V1_SURFACE=True` |
| Cliff behavior | IDW fallback on cliff-adjacent tiles |
| Material behavior | Full PBR splatting |
| Status | **EXPERIMENTAL / DIAGNOSTIC** |

---

## FULL01-DEFAULT — IDW / legacy default generator path

| Field | Value |
|-------|-------|
| Prototype ID | `FULL01-DEFAULT` |
| Runner | *(none — run generator directly with default flags)* |
| Output | `terrain_handdrawn_test_map_full_01.blend` |
| Solver | `IdwTerrainSolver` (default when all TS flags off) |
| Flags | All `USE_*` TS flags `False`; `USE_HEXPATCH_SURFACE=True` |
| Cliff behavior | Standard cliff walls |
| Material behavior | Full PBR splatting |
| Status | **REFERENCE** (pre-TS-03 IDW path) |

---

## TS-07b — Cliff-rim TPS interpolation points (PLANNED, NOT STARTED)

| Field | Value |
|-------|-------|
| Prototype ID | `TS-07b` |
| Runner | *(not implemented)* |
| Output | *(TBD)* |
| Solver | `VariationalSplineTerrainSolver` (same as TS-03) |
| Flags | Exact recovered TS-03 path + extra cliff-rim interpolation points only |
| Status | **PLANNED — DO NOT IMPLEMENT until TS-03 baseline is locked** |

### Non-negotiable invariant for TS-07b

TS-07b may **ONLY** add extra interpolation points before `solve_component_field`.
It must **not**:

- create a new independent solver
- override `sample_world`
- alter mesh generation
- alter wall generation
- alter material assignment
- alter overlay behavior
- reuse TS-05 release code
- reuse TS-06 divergent solver logic
- modify FEM / Stein / global biharmonic code

Future cliff-rim formulation: `Empire_of_Minds_Explicit_Cliff_Rim_Formulation_Long_Spec_v2.docx`.
Cliff-rim samples are ordinary TPS interpolation constraints (not PDE boundary conditions).
XY follows exact hex edges; only Z along the edge is interpolated; no rim slope condition;
corner/termination elevation = halfway between adjacent upper and lower cliff-side elevations.

---

## Recovery branches

| Branch | Purpose |
|--------|---------|
| `terrain-ts03-recovery-checkpoint` | Immutable forensic snapshot (commit `248dc8b`) |
| `terrain-ts03-baseline` | Working branch for manifest, logging, and baseline lock |

Do not assume `main` alone contains the terrain recovery state.
