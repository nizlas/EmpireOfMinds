# TS-08 Stage-2 reference terrain dataset (N2)

Engine-neutral, deterministic reference output for the accepted TS-08 Stage-2 cut-domain thin-plate CG chain on `handdrawn_test_map_full_01`.

**Authority (locked):**

- **Authoritative terrain input:** the canonical 2D logical map in `content/maps/` — axial hex grid, integer elevation levels. Loaded into **`WorldMap`** (N1). This is the sole source input for terrain construction. Edge classifications (smooth/cliff) are **derived** from the height grid and the locked threshold rule, not independently authored; `edge_overrides` is reserved and must be an empty array (or absent) in schema v1.
- **This JSON file:** a **derived reference golden** — pre-solved TS-08 Stage-2 output exported for parity testing and auditing the accepted Blender/Godot solver result. It is **not** the final production terrain source and **does not replace** running a TS-08-equivalent solver.
- **Target production pipeline:** generate continuous terrain from the canonical 2D grid by running a TS-08-equivalent solver (see [PHASE_PLAN.md](../../../docs/PHASE_PLAN.md), [TERRAIN_SURFACE_TARGET.md](../../../docs/TERRAIN_SURFACE_TARGET.md)).
- **N3 checkpoint (if used):** loading this pre-solved dataset for an early visible 3D world is permitted as a **temporary visual-parity checkpoint only** — not the target architecture.

Blender remains development/reference tooling only. The `.blend` mesh is also not a runtime or production terrain source.

## Permanent path

| Item | Value |
|------|-------|
| Dataset | `content/terrain/reference/handdrawn_test_map_full_01_ts08_stage2_reference_v1.json` |
| Schema | `schema_version: 1` (see below) |
| Source map | `content/maps/reference/handdrawn_test_map_full_01.json` |
| Exporter | `tools/blender/terrain/export_ts08_reference_dataset.py` (bpy-free) |

## Commands

From repository root (requires `numpy`):

```bash
python tools/blender/terrain/export_ts08_reference_dataset.py export
python tools/blender/terrain/export_ts08_reference_dataset.py check
```

Focused tests:

```bash
python -m pytest tools/blender/terrain/tests/test_export_ts08_reference_dataset.py -q
```

Regeneration must be byte-identical when the source map hash, TS-08 solver chain, and exporter version are unchanged.

## Schema v1 (summary)

Top-level envelope fields:

- **`schema_version`**, **`dataset_id`**, **`origin`**, **`content_hash`** — dataset identity and integrity (hash covers all fields except `content_hash`, canonical JSON).
- **`source_map_identity`** — embeds the canonical three-field **`MapIdentity`** (`map_id`, `schema_version`, `content_hash`) plus optional provenance:
  - **`source_path`** — repo-relative path to the canonical map file **at export time** (human/diagnostic traceability only). It is **not** part of `MapIdentity` verification; clients and audits must match on the three identity fields and raw-byte hash, not on path strings.
- **`ts08`** — prototype metadata, Godot Y-up frame, axis conversion `(x_g, y_g, z_g) = (x_b, z_b, -y_b)`.
- **`topology_summary`** — accepted Stage-0 cut-lattice audit snapshot (counts, seam duplication, cross-cliff adjacency gate).
- **`solver_summary`** — Stage-2 CG solve metrics (convergence, energy, z-range in Blender Z).
- **`seam_duplication`** — duplicated cliff-line node count and pos-key duplication instances.
- **`node_count`**, **`triangle_count`** — golden topology sizes (74129 nodes, 145152 triangles).
- **`nodes`** — `positions_xyz` (Godot), `sheet_ids`, stable `node_keys`, `pos_keys`.
- **`center_pins`** — tile `(q,r)` → cut-lattice center node index and pinned Godot Y.
- **`triangles`** — top-surface triangle index triples with Y-up outward winding.
- **`cliff_edges`** — authoritative cliff tile pairs (`delta > cliff_threshold`).

## Audit contract (read-only `check`)

The checker validates:

1. **Byte-for-byte match** with deterministic regeneration (full file including `content_hash`). Tampering a vertex/topology value and recomputing `content_hash` still fails.
2. Stored `content_hash` matches canonical body bytes.
3. Source map identity matches the committed reference map hash.
4. TS-08 golden counts: 168 hexes, 74129 nodes, 145152 triangles, 168 center pins, 78 cliff edges.
5. Stage-0 topology: 861 duplicated cliff-line nodes, `adjacency_cross_cliff_violations == 0`.
6. Stage-2 solver converged; center pins match solved Godot Y within `1e-6`.
7. **Accepted Stage-2 height range** (Godot Y / Blender Z): min `-0.0953001335506`, max `2.09155970068` (tol `1e-12`).
8. Smooth-edge midpoints are not split across topology (seam separation preserved on cliffs only).
9. No smooth-edge height mismatch across duplicated mid-edge samples.

## Current committed hash

`4420fe98088ffb8e538b87f5debb8408dc7a16b279da85dcd335a01f166467ce`

See also: [docs/TERRAIN_SURFACE_TARGET.md](../../../docs/TERRAIN_SURFACE_TARGET.md), [tools/blender/terrain/TERRAIN_PROTOTYPE_MANIFEST.md](../../../tools/blender/terrain/TERRAIN_PROTOTYPE_MANIFEST.md), [docs/PHASE_PLAN.md](../../../docs/PHASE_PLAN.md) (slice N2).
