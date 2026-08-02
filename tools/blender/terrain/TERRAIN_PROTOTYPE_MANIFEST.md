# Empire of Minds — Handdrawn full-map terrain prototype manifest

Traceability index for `generate_terrain_terrainmap_handdrawn_full_01.py` and its
`run_*_blend_regen.py` runners, plus the later standalone TS-07c/TS-07d/TS-08 generators.
Each entry is one selectable prototype path.

> **Current accepted reference: TS-08** (see the TS-08 section below and
> [docs/TERRAIN_SURFACE_TARGET.md](../../../docs/TERRAIN_SURFACE_TARGET.md)). All TS-01…TS-07
> entries are earlier history; the TS-03 baseline remains a frozen historical visual
> baseline but is superseded as the terrain model.

**Frozen TS-03 baseline artifact (never overwritten by runners; historical):**

| Item | Value |
|------|-------|
| File | `game/assets/prototype/3d/terrain/prototype_3d_terrain/generated/terrain_handdrawn_test_map_full_01_variational_spline_BASELINE_2026-06-27.blend` |
| Origin | Copy of `..._variational_spline.blend1` (mtime 2026-06-27 14:37) |
| Status | **HISTORICAL BASELINE (frozen)** — superseded as terrain model by TS-08 |
| Audit | `blender --background --python tools/blender/terrain/audit_ts03_baseline_blend.py` (read-only) |

---

## TS-03 — Variational spline (legacy cliff-cut runner)

| Field | Value |
|-------|-------|
| Prototype ID | `TS-03` |
| Runner | `tools/blender/terrain/run_ts_variational_spline_blend_regen.py` |
| Output | `terrain_handdrawn_test_map_full_01_variational_spline.blend` |
| Solver | `VariationalSplineTerrainSolver` (per-cliff-side cluster / TS-03d cliff-cut) |
| Flags | `USE_VARIATIONAL_SPLINE_SURFACE=True`; all other TS flags `False` |
| Cliff behavior | Per-cliff-side TPS + top vertex split at cliff edges |
| Material behavior | Full PBR ground/stone/ash splatting via locked 7-hex baseline |
| Status | **DEPRECATED** — produces cut top surface (77 islands); use dedicated baseline script below |

---

## TS-03-GLOBAL-CONTINUOUS-BASELINE — Approved smooth baseline regeneration

| Field | Value |
|-------|-------|
| Prototype ID | `TS-03-GLOBAL-CONTINUOUS-BASELINE` |
| Generator | `tools/blender/terrain/generate_ts03_global_continuous_baseline.py` |
| Runner | `tools/blender/terrain/run_ts03_global_continuous_baseline_regen.py` |
| Output | `terrain_handdrawn_test_map_full_01_ts03_global_continuous_baseline.blend` |
| Solver | `GlobalContinuousVariationalSplineTerrainSolver` (single global TPS, all tile centers) |
| Mesh mode | `split_top_at_cliff_edges=False`; position-key top merge (continuous top island) |
| Cliff behavior | Presentation walls only; no per-cliff-side clustering; no rim/release constraints |
| Material behavior | Full PBR ground/stone/ash splatting (unchanged) |
| Status | **HISTORICAL** — regen path for the frozen smooth TS-03 baseline; superseded as terrain model by TS-08 |
| Audit | `blender --background --python tools/blender/terrain/audit_ts03_global_continuous_baseline_blend.py` |

Does **not** read or set shared experiment `USE_*` flags. Never writes to `*_BASELINE_*` files.

Visual target: one broad continuous smooth TPS-like surface matching
`terrain_handdrawn_test_map_full_01_variational_spline_BASELINE_2026-06-27.blend`.

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
| Status | **OBSOLETE — never implement.** The TS-03 + cliff-rim direction was superseded by the TS-08 cut-domain thin-plate chain. |

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

## TS-07c — Global TPS + virtual cliff rails (SUPERSEDED)

| Field | Value |
|-------|-------|
| Prototype ID | `TS-07c` |
| Generator / runner | `generate_ts07c_global_tps_virtual_cliff_rails.py` / `run_ts07c_global_tps_virtual_cliff_rails_regen.py` |
| Output | `terrain_handdrawn_test_map_full_01_ts07c_global_tps_virtual_cliff_rails.blend` |
| Status | **SUPERSEDED — do not build on.** Virtual-rail constraint experiment; replaced by the TS-08 cut-domain topology. Cautionary reference only. |

---

## TS-07d — Weighted-curvature cliff band (SUPERSEDED)

| Field | Value |
|-------|-------|
| Prototype ID | `TS-07d` |
| Generator / runner | `generate_ts07d_weighted_curvature_cliff_band.py` / `run_ts07d_weighted_curvature_cliff_band_regen.py` |
| Output | `terrain_handdrawn_test_map_full_01_ts07d_weighted_curvature_cliff_band.blend` |
| Status | **SUPERSEDED — do not build on.** Curvature-weighting experiment; replaced by the TS-08 cut-domain topology. Cautionary reference only. |

---

## TS-08 — Cut-domain thin-plate chain (CURRENT ACCEPTED REFERENCE)

Canonical model: [docs/TERRAIN_SURFACE_TARGET.md](../../../docs/TERRAIN_SURFACE_TARGET.md).
Reference logical map: `content/maps/reference/handdrawn_test_map_full_01.json` (JSON envelope v1; see [docs/MAP_CONTENT.md](../../../docs/MAP_CONTENT.md)). Loaded by Blender tooling via `eom_map_content.py`.

| Stage | Meaning | Generator | Output |
|-------|---------|-----------|--------|
| Stage 0 | Cut-lattice topology audit (no height solve) | `audit_ts08_cut_lattice_topology.py` (module `eom_terrain_ts08_cut_lattice.py`) | `reports/ts08_cut_lattice_topology_audit.json` |
| Stage 1 | No-cut thin-plate CG solve (Γ = ∅ gate) | `generate_ts08_stage1_no_cut_thin_plate_cg.py` | `terrain_handdrawn_test_map_full_01_ts08_stage1_no_cut_thin_plate_cg.blend` |
| Stage 2 | Cut-domain thin-plate CG solve | `generate_ts08_stage2_cut_domain_thin_plate_cg.py` | `terrain_handdrawn_test_map_full_01_ts08_stage2_cut_domain_thin_plate_cg.blend` |
| Stage 3a | Basic cliff walls + stone wall material | `generate_ts08_stage3a_basic_cliff_walls.py` | `terrain_handdrawn_test_map_full_01_ts08_stage3a_basic_cliff_walls.blend` |
| Stage 3b | Fitted cliff-panel / Meshy asset fit test | `generate_ts08_stage3b_cliff_asset_fit_test.py` | `terrain_handdrawn_test_map_full_01_ts08_stage3b_cliff_asset_fit_test.blend` |

Status: **Stages 0–3a are the current accepted reference chain** (each with matching `run_*`/`audit_*` scripts and JSON reports under `reports/`). **Stage 3b is a superseded experiment — do not revive**; external cliff props remain deferred future work.

### N2 reference dataset (derived golden — not production source)

| Field | Value |
|-------|-------|
| Slice | **N2 (done, 2026-08)** |
| Role | **Derived reference golden** for parity testing/audit of accepted TS-08 Stage-2; **not** the production terrain source; **does not replace** the solver |
| Dataset | `content/terrain/reference/handdrawn_test_map_full_01_ts08_stage2_reference_v1.json` |
| Authoritative input | `content/maps/reference/handdrawn_test_map_full_01.json` → **`WorldMap`** |
| Exporter / audit | `tools/blender/terrain/export_ts08_reference_dataset.py` (`export` \| `check`, bpy-free) |
| Tests | `tools/blender/terrain/tests/test_export_ts08_reference_dataset.py` |
| Schema / contract | `content/terrain/reference/README.md` |
| Chain reused | Stage 0 topology audit + Stage 2 cut-domain thin-plate CG (solver/parameters unchanged) |
| Coordinate frame | Godot Y-up: `(x_g, y_g, z_g) = (x_b, z_b, -y_b)` |
| Golden counts | 74129 nodes, 145152 triangles, 168 center pins, 78 cliff edges, 861 duplicated cliff-line nodes |

The committed `.blend` Stage-2/3a artifacts remain development/visual references. **Target production path:** Godot generates terrain from the canonical 2D grid via a TS-08-equivalent solver and compares against this JSON golden. Optional N3 checkpoint loading of the pre-solved dataset is temporary visual parity only.

---

## Recovery branches

| Branch | Purpose |
|--------|---------|
| `terrain-ts03-recovery-checkpoint` | Immutable forensic snapshot (commit `248dc8b`) |
| `terrain-ts03-baseline` | Working branch for manifest, logging, and baseline lock |

Do not assume `main` alone contains the terrain recovery state.
