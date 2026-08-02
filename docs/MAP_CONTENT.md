# Empire of Minds — Map content architecture

This document is the **canonical detailed source** for how logical map data is owned, categorized, serialized, and consumed. Other steering documents link here rather than duplicating the full architecture.

**Status:** envelope schema v1 and the TS-08 reference file are **implemented** (Slice B+C, 2026-08). The approved **`WorldMap`** authority, **`MapIdentity`**, packaging sync, and Godot/server loading are **planned** (slices N1, N7) — **not yet implemented**. See [MAP_MODEL.md](MAP_MODEL.md) and [WORLD_COORDINATES.md](WORLD_COORDINATES.md).

---

## Map categories

All maps must ultimately produce the **same authoritative logical map representation** (`WorldMap`) regardless of origin. Folder placement indicates intent but is **not** the only semantic indicator — each map file carries sufficient metadata (see [JSON envelope schema v1](#json-envelope-schema-v1) below).

| Category | Location | Purpose |
|----------|----------|---------|
| **Reference** | `content/maps/reference/` | Locked or deliberately versioned maps used for parity, regression tests, audits, and reproducible visual comparisons. The current TS-08 hand-authored test map belongs here. |
| **Authored** | `content/maps/authored/` | Intentionally designed playable maps (e.g. a future Earth map). |
| **Curated / promoted generated** | `content/maps/generated/` | Generator results **deliberately promoted** into version-controlled game content. Does **not** contain every runtime-generated map. |
| **Ordinary runtime-generated** | *Future user save/cache data* | Maps produced during normal play from a generator + seed. **Not** stored under `content/maps/`. |

Additional placement rules:

- A generated map **locked specifically for parity/regression** belongs under **`reference/`**, not `generated/`.
- A generated map **substantially redesigned by hand** may become **authored** content instead.
- **Generator algorithms** belong in **code**, not in map-content directories.

---

## Directory structure

Repo-root `content/maps/` is the approved source-content root (engine-neutral: readable by Blender tooling, future Godot client, and future authoritative server).

```text
content/maps/
├── reference/     # parity / regression / audit maps
├── authored/      # intentionally designed playable maps
└── generated/     # curated generator results promoted into version control
```

The TS-08 reference file:

`content/maps/reference/handdrawn_test_map_full_01.json`

Blender tooling loads it via [tools/blender/terrain/eom_map_content.py](../tools/blender/terrain/eom_map_content.py).

---

## JSON envelope schema v1

Initial serialization format: **JSON**. The problem being solved is **ownership and placement**, not the format.

### Envelope fields (required in v1)

| Field | Type | Purpose |
|-------|------|---------|
| `schema_version` | integer | Schema migration gate. **v1 = `1`**. |
| `origin` | string | `"reference"` \| `"authored"` \| `"generated"`. Semantic category; must agree with folder placement but is authoritative in the file itself. |
| `provenance` | string | Free-text description of why this map exists and how it was produced. |
| `logical_map` | object | The logical map payload — see below. |

### `logical_map` payload (TerrainMap IR)

Parsed today by `parse_terrain_map_ir` in [tools/blender/terrain/eom_terrain_math_core.py](../tools/blender/terrain/eom_terrain_math_core.py):

- `id` — canonical **`map_id`** (e.g. `"handdrawn_test_map_full_01"`).
- `orientation` — **historical label** for the stored coordinate convention (`"pointy_top_custom_axes"` on the reference map). Orientation in the architectural sense is defined by embeddings ([WORLD_COORDINATES.md](WORLD_COORDINATES.md)), not by this string. Do **not** rename it to `axial_v1`; a future schema may add a properly named field such as `coordinate_convention`.
- `elevation_step` — float world-units per elevation integer step (**0.4** on the reference map).
- `elevation_base` — **optional**; **absent** on the current reference file. Effective base **1** comes from the parser default (`DEFAULT_ELEVATION_BASE = 1`). Adding explicit `"elevation_base": 1` is an approved **future hygiene change** (with TS-08 regression validation); not part of N0.
- `edge_rule` / cliff threshold, `edge_overrides`
- `tiles` — array of `{q, r, elevation}`

**No rendering, mesh, material, camera, collision, or Blender object state** belongs in `logical_map`.

### Elevation semantics

```
world_y = (elevation − elevation_base) · elevation_step
```

- **Source elevation:** integer per tile in the payload.
- **`elevation_step`:** authoritative in the map file.
- **`elevation_base`:** optional; defaults to **1** when omitted.
- **`world_y`:** rules-level height ([WORLD_COORDINATES.md](WORLD_COORDINATES.md)).
- **Sampled surface height:** continuous TS-08 terrain — presentation only.

### Deliberately absent from v1 (reserved)

- Envelope-level duplicate **`map_id`** or **`display_name`** — `logical_map.id` remains canonical.
- **`generator_id`**, **`seed`**, promotion status — when generated maps are promoted.
- Save-game or replay serialization — separate future concern.
- Secret geology, undiscovered deposits, unrevealed resources — **server-owned**; see [Public vs secret map information](#public-vs-secret-map-information).

---

## MapIdentity (approved — planned N1/N7)

A **`map_id` alone is insufficient.** Canonical immutable map content is identified by:

| Field | Source |
|-------|--------|
| `map_id` | `logical_map.id` |
| `schema_version` | envelope `schema_version` |
| `content_hash` | deterministic hash of the canonical file’s **raw bytes** (SHA-256) |

**Usage (planned):**

- **Godot loader (N1):** computes and exposes `MapIdentity` when loading packaged content.
- **Local debug init (N3+):** stamps identity into match state.
- **Server match init (N7):** stores identity in match metadata and snapshots.
- **Packaging freshness (N1):** compares source hash vs derived copy vs manifest.
- **Automated tests:** pin current hash as a golden; update deliberately when the map legitimately changes.

Clients and server **independently load** the canonical content matching the identity and **verify the hash**. A mismatch must **fail explicitly** — never silently continue with stale or wrong content.

---

## Authoritative logical map vs derived outputs

```text
logical_map (authoritative source input)
    → WorldMap (canonical in-memory authority — planned N1)
        → terrain construction (deterministic derived geometry — TS-08)
            → presentation (mesh, material, collision, overlays, UI)
```

- The **logical map** in `content/maps/` is authoritative **source** data.
- **`WorldMap`** is the authoritative **in-memory** representation for gameplay (planned).
- **Blender TS-08** outputs and **Godot** terrain are **deterministic derivatives** — never gameplay authority.
- Reference authority for terrain parity is the **contract as a whole**: canonical logical grid, TS-08 algorithm/parameters, deterministic reference dataset, audit chain, accepted visual result.

---

## Public vs secret map information

Distinguish four concepts:

| Concept | Authority | Client public package? |
|---------|-----------|------------------------|
| **Physical world truth** | Shared observable terrain (elevation, explicit cliffs, manifest geology visible on surface) | **Yes** — immutable public map content |
| **Secret server truth** | Hidden geology, undiscovered deposits, unrevealed resources | **No** — server-owned only |
| **Player-scoped knowledge** | What a civilization has discovered (prospecting, surveys) | **No** in the public map file — delivered per player via authoritative server state |
| **Presentation** | Icons, overlays, UI communicating knowledge | Derived from permitted inputs only |

**Rules:**

- The client’s canonical **public map package** contains shared observable physical terrain truth only.
- **Undiscovered** player knowledge must **not** be rendered as shared physical 3D resource objects.
- Prospecting clues that exist as **visible physical features** (e.g. exposed rock) may appear in shared world geometry; **knowledge markers** for hidden deposits appear only from that player’s `KnowledgeState`.

---

## Yield and capability direction (replacing category tables)

The new model **retires** fixed intrinsic yield tables keyed by categorical `terrain` / `landform` / `woods` ([MAP_MODEL.md](MAP_MODEL.md)).

| Mechanism | Role |
|-----------|------|
| **Base yields** | Deterministic function of physical tile properties; v1 may use simple flat constants |
| **Capabilities** (science/tech) | Unlock interpretation of features and exploitation actions |
| **Improvements** | Match-state modifiers on tile/edge ids |
| **Player knowledge** | Gates actions and presentation; does not alter shared physical truth |
| **Determinism** | Yields and legal actions are pure functions recomputed identically on server and clients |

Old content wording (“Hill Production Bonus”) is **design intent** for later translation — not a schema requirement. **`Hill`** is normally a **derived classification**, not primitive terrain truth.

**Implemented now:** nothing in the new yield model (legacy `CityYields.raw_terrain_yield` still runs on `HexMap`). **Planned:** N6 introduces yields v2 on `WorldMap`.

---

## Relationship to runtime map authorities

| Authority | Status |
|-----------|--------|
| **`WorldMap`** (approved) | **Not implemented** — sole target logical map (N1+) |
| **`HexMap`** (legacy) | **Still exists**, frozen, scheduled for removal N8 — categorical tags, no elevation |

There is **no adapter** between them. An explicit loading boundary converts envelope v1 → `WorldMap` at import ([WORLD_COORDINATES.md](WORLD_COORDINATES.md) import-boundary identity for the reference payload).

---

## Packaging and synchronization (planned N1)

**Canonical source:** `content/maps/**`

**Planned mechanism:** repository-owned Python script `tools/content/sync_map_content.py` (not yet implemented):

- Validates envelopes (reusing `eom_map_content.py` conventions).
- Copies to `game/content/maps/**` (committed derived artifact for Godot `res://`).
- Writes `game/content/maps/manifest.json` with per-file `{path, map_id, schema_version, content_hash, source_path}`.
- Freshness: tests compare source ↔ copy ↔ manifest hashes.

**Per environment (planned):**

- Local dev / Godot tests: `res://content/maps/**`
- Exports: include JSON + manifest
- Server (N7): canonical repo path in dev; ship `content/` in deployment
- Blender: continues reading canonical path via `eom_map_content.py`

Do not treat packaging as implemented until slice N1 lands.

---

## Promotion boundary (recorded, not designed)

Promoting an ordinary runtime-generated map into `content/maps/generated/` is initially a **developer/admin workflow**. No end-user publishing, Workshop, or marketplace system is being designed now.

---

## Loader ownership

| Layer | Owner |
|-------|-------|
| **Schema** | Shared conceptually across environments; envelope v1 rules documented here and in [WORLD_COORDINATES.md](WORLD_COORDINATES.md) |
| **Blender tooling loader** | `tools/blender/terrain/eom_map_content.py` — development/reference tooling only |
| **Repository sync tooling (N1)** | Planned `tools/content/sync_map_content.py` — may reuse validation semantics aligned with the canonical schema; **not** a runtime dependency |
| **Godot loader (N1)** | Planned `game/domain/world/map_content_loader.gd` |
| **Server loader (N7)** | Planned server-owned loader under `server/app/` — loads canonical content identified by `MapIdentity`, verifies raw-byte SHA-256 `content_hash`, rejects schema or identity mismatches explicitly; **must not import** from `tools/blender/` |
| **Architectural owner of map truth** | `WorldMap` — not any loader module |

The future authoritative **server runtime** must not depend on Blender tooling. N7 implements a server-owned map-content loader under `server/app/` following the same canonical schema and validation semantics as other loaders, without importing `eom_map_content.py` or any other module under `tools/blender/`.

---

## Related documents

- [MAP_MODEL.md](MAP_MODEL.md) — `WorldMap` layers and legacy `HexMap` status
- [WORLD_COORDINATES.md](WORLD_COORDINATES.md) — coordinate contract and elevation precision
- [TERRAIN_MODEL.md](TERRAIN_MODEL.md) — terrain construction model (TS-08)
- [TERRAIN_SURFACE_TARGET.md](TERRAIN_SURFACE_TARGET.md) — mathematical target
- [PHASE_PLAN.md](PHASE_PLAN.md) — N0–N8 implementation slices
- [CURRENT_ARCHITECTURE.md](CURRENT_ARCHITECTURE.md) — current vs target vs legacy
- [DECISION_LOG.md](DECISION_LOG.md) — approved architectural decisions
