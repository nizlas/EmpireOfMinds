# Map content (`content/maps/`)

Repo-root logical map source files for Empire of Minds. Full architecture, JSON envelope schema, and category definitions: [docs/MAP_CONTENT.md](../docs/MAP_CONTENT.md).

| Subdirectory | Purpose |
|--------------|---------|
| `reference/` | Locked or versioned maps for parity, regression, audits, and reproducible visual comparisons |
| `authored/` | Intentionally designed playable maps (future) |
| `generated/` | Curated generator results deliberately promoted into version control (future) |

Ordinary runtime-generated maps belong in future user save/cache data, not here.

Current reference map: `reference/handdrawn_test_map_full_01.json` (TS-08 parity/regression grid).
