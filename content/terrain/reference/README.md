# TS-08 Stage-2 reference terrain dataset (N2)

Engine-neutral, deterministic reference output for the accepted TS-08 Stage-2 cut-domain thin-plate CG chain on `handdrawn_test_map_full_01`.

**Authority:** this exported JSON — not the `.blend` mesh. Blender remains development/reference tooling only. Godot parity (N3+) compares against this dataset within documented tolerances.

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
- **`source_map_identity`** — canonical `MapIdentity`: `map_id`, `schema_version`, `content_hash`, `source_path`.
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

1. Stored `content_hash` matches canonical body bytes.
2. Source map identity matches the committed reference map hash.
3. TS-08 golden counts: 168 hexes, 74129 nodes, 145152 triangles, 168 center pins, 78 cliff edges.
4. Stage-0 topology: 861 duplicated cliff-line nodes, `adjacency_cross_cliff_violations == 0`.
5. Stage-2 solver converged; center pins match solved Godot Y within `1e-6`.
6. Smooth-edge midpoints are not split across topology (seam separation preserved on cliffs only).
7. No smooth-edge height mismatch across duplicated mid-edge samples.

## Current committed hash

`4420fe98088ffb8e538b87f5debb8408dc7a16b279da85dcd335a01f166467ce`

See also: [docs/TERRAIN_SURFACE_TARGET.md](../../docs/TERRAIN_SURFACE_TARGET.md), [tools/blender/terrain/TERRAIN_PROTOTYPE_MANIFEST.md](../../tools/blender/terrain/TERRAIN_PROTOTYPE_MANIFEST.md), [docs/PHASE_PLAN.md](../../docs/PHASE_PLAN.md) (slice N2).
