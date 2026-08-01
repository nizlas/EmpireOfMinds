# Empire of Minds — Map content architecture

This document is the **canonical detailed source** for how logical map data is owned, categorized, serialized, and consumed. Other steering documents link here rather than duplicating the full architecture.

**Status:** the architecture and schema direction below are **approved but not yet implemented** in the repository. The current TS-08 reference grid is still embedded as `TERRAIN_MAP_JSON` inside [tools/blender/terrain/generate_terrain_terrainmap_handdrawn_full_01.py](../tools/blender/terrain/generate_terrain_terrainmap_handdrawn_full_01.py). Extraction into `content/maps/` is planned for Slice B+C of the Fixed-grid Godot 3D terrain parity milestone ([PHASE_PLAN.md](PHASE_PLAN.md)).

---

## Map categories

All maps must ultimately produce the **same authoritative logical map representation** regardless of origin. Folder placement indicates intent but is **not** the only semantic indicator — each map file carries sufficient metadata (see [JSON envelope schema v1](#json-envelope-schema-v1) below).

| Category | Location (planned) | Purpose |
|----------|-------------------|---------|
| **Reference** | `content/maps/reference/` | Locked or deliberately versioned maps used for parity, regression tests, audits, and reproducible visual comparisons. The current TS-08 hand-authored test map belongs here. |
| **Authored** | `content/maps/authored/` | Intentionally designed playable maps (e.g. a future Earth map). |
| **Curated / promoted generated** | `content/maps/generated/` | Generator results **deliberately promoted** into version-controlled game content. Does **not** contain every runtime-generated map. |
| **Ordinary runtime-generated** | *Future user save/cache data* | Maps produced during normal play from a generator + seed. **Not** stored under `content/maps/`. |

Additional placement rules:

- A generated map **locked specifically for parity/regression** belongs under **`reference/`**, not `generated/`.
- A generated map **substantially redesigned by hand** may become **authored** content instead.
- **Generator algorithms** belong in **code**, not in map-content directories.

---

## Planned directory structure

Repo-root `content/maps/` is the approved source-content root (engine-neutral: readable by Blender tooling, future Godot client, and future authoritative server).

```text
content/maps/
├── reference/     # parity / regression / audit maps
├── authored/      # intentionally designed playable maps
└── generated/     # curated generator results promoted into version control
```

The first planned reference file:

`content/maps/reference/handdrawn_test_map_full_01.json`

**Not created yet.** Slice B+C will add this file and migrate Blender consumers.

---

## JSON envelope schema v1

Initial serialization format: **JSON**. The problem being solved is **ownership and placement**, not the format.

### Envelope fields (required in v1)

| Field | Type | Purpose |
|-------|------|---------|
| `schema_version` | integer | Schema migration gate. **v1 = `1`**. Matches the repo convention used elsewhere (server snapshots, action envelopes). |
| `origin` | string | `"reference"` \| `"authored"` \| `"generated"`. Semantic category; must agree with folder placement but is authoritative in the file itself. |
| `provenance` | string | Free-text description of why this map exists and how it was produced (e.g. hand-authored date, promotion note, regression lock reason). |
| `logical_map` | object | The logical map payload — see below. **Unchanged** from the current TerrainMap IR. |

### `logical_map` payload (TerrainMap IR)

The existing TerrainMap intermediate representation, parsed today by `parse_terrain_map_ir` in [tools/blender/terrain/eom_terrain_math_core.py](../tools/blender/terrain/eom_terrain_math_core.py):

- `id` — **canonical map identity** (e.g. `"handdrawn_test_map_full_01"`). Audits and tooling already key off this value (`MAP_JSON_ID` in the TS-08 chain).
- `orientation` — axis convention for the stored `(q, r)` coordinates (the reference map uses `"pointy_top_custom_axes"`).
- `elevation_step`, optional `elevation_base`
- `edge_rule` / `cliff_threshold`, `edge_overrides`
- `tiles` — array of `{q, r, elevation}` entries

**No rendering, mesh, material, camera, collision, or Blender object state** belongs in `logical_map`.

### Deliberately absent from v1 (reserved)

Do not add these until a concrete consumer exists:

- Envelope-level **`map_id`** or **`display_name`** — would duplicate `logical_map.id`; the payload id remains canonical.
- **`generator_id`**, **`seed`**, promotion status fields — required only when generated maps are promoted; the promotion workflow itself is **not** being designed now.
- Save-game or replay serialization — separate future concern.

### Example shape (illustrative; file not yet committed)

```json
{
  "schema_version": 1,
  "origin": "reference",
  "provenance": "Hand-authored 2026-06 for the terrain-surface prototype chain; locked as the TS-08 parity/regression reference map.",
  "logical_map": {
    "id": "handdrawn_test_map_full_01",
    "orientation": "pointy_top_custom_axes",
    "elevation_step": 0.4,
    "edge_rule": { "default": "smooth", "cliff_if_abs_delta_greater_than": 1 },
    "edge_overrides": [],
    "tiles": [ "...168 entries..." ]
  }
}
```

---

## Authoritative logical map vs derived outputs

```text
logical_map (authoritative gameplay/domain input)
    → terrain construction (deterministic derived geometry — TS-08 algorithm)
        → presentation (Blender reference mesh / future Godot mesh, material, collision)
```

- The **logical map** is authoritative gameplay/domain state input.
- **Blender TS-08** outputs and **future Godot** terrain outputs are **deterministic derivatives** — never the source of truth for gameplay rules.
- Reference authority for terrain parity is the **contract as a whole**: canonical logical grid, TS-08 algorithm/parameters, deterministic reference dataset, audit chain, accepted visual result ([DECISION_LOG.md](DECISION_LOG.md) 2026-08-01 entry).

---

## Relationship to runtime `HexMap`

The domain **`HexMap`** ([game/domain/hex_map.gd](../game/domain/hex_map.gd), [MAP_MODEL.md](MAP_MODEL.md)) is the authoritative in-memory logical map for the running game today. It stores terrain/landform/woods tags and **does not** store elevation.

The TS-08 reference payload is **elevation-only** in **custom hand-drawn axes** (`handdrawn_to_baseline_axial(q,r) = (q+r, -r)` in the Blender math core), which differs from the domain axial convention in [HEX_COORDINATES.md](HEX_COORDINATES.md).

**An explicit loading/translation boundary is required** when Godot (or server) consumes reference/authored/generated map files. That boundary — coordinate translation, elevation integration, packaging — is **explicitly deferred to Slice D** and must not be attempted during map extraction (Slice B+C).

---

## Promotion boundary (recorded, not designed)

Promoting an ordinary runtime-generated map into `content/maps/generated/` is initially a **developer/admin workflow**. No end-user publishing, Workshop, or marketplace system is being designed now. A future commercial release may require a different mechanism.

---

## Loader ownership (planned)

- **Schema:** shared across Blender tooling and future runtime.
- **Loaders:** environment-specific (Python for Blender tooling now; GDScript for Godot later). No Python module under `tools/blender/` becomes the architectural owner merely because it currently contains the embedded map.
- **Godot packaging:** files under repo-root `content/` are **not** automatically on `res://`; how they reach the Godot export is a **Slice D** decision.

---

## Related documents

- [MAP_MODEL.md](MAP_MODEL.md) — runtime `HexMap` container and query API
- [TERRAIN_MODEL.md](TERRAIN_MODEL.md) — terrain construction model (TS-08)
- [TERRAIN_SURFACE_TARGET.md](TERRAIN_SURFACE_TARGET.md) — mathematical target for terrain surface generation
- [PHASE_PLAN.md](PHASE_PLAN.md) — Fixed-grid Godot 3D terrain parity milestone slices
- [ARCHITECTURE_PRINCIPLES.md](ARCHITECTURE_PRINCIPLES.md) — logical map → construction → presentation layering
- [CURRENT_ARCHITECTURE.md](CURRENT_ARCHITECTURE.md) — what is implemented vs approved target
