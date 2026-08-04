# Empire of Minds — Map content architecture

This document is the **canonical detailed source** for how logical map data is owned, categorized, serialized, and consumed. Other steering documents link here rather than duplicating the full architecture.

**Status:** envelope schema v1, TS-08 reference file, Godot **`WorldMap`** foundation loader, and packaging sync are **implemented** (slices B+C and **N1**, 2026-08). Server loading and server content packaging are **planned N5**; snapshot v3 and server match-identity usage are **planned N6**.

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
- `edge_rule` / cliff threshold — the locked derivation rule for edge classification.
- `edge_overrides` — **reserved for possible future use; must be an empty array (or absent) in schema v1.** Override behavior is not implemented; loaders reject a non-empty list as unsupported.
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

## MapIdentity (approved — implemented N1; server loading planned N5, server match usage planned N6)

A **`map_id` alone is insufficient.** Canonical immutable map content is identified by:

| Field | Source |
|-------|--------|
| `map_id` | `logical_map.id` |
| `schema_version` | envelope `schema_version` |
| `content_hash` | deterministic hash of the canonical file’s **raw bytes** (SHA-256) |

**Usage:**

- **Godot loader (N1):** computes and exposes `MapIdentity` when loading packaged content — **implemented**.
- **Server content loading (N5):** the server-owned loader computes and exposes `MapIdentity` from the packaged canonical content — **planned**.
- **Server match init (N6):** stores identity in match metadata and snapshot v3 — **planned**. Match state is server-owned under the locked dual-entry direction; the future one-PC debug mode gets its identity from a locally running authoritative server through the same path (no client-side match-state stamping).
- **Client bootstrap verification (N6):** the client loads local canonical content by `map_id` and verifies `content_hash` against the server identity; mismatch fails explicitly — **planned** (verified primarily in the Godot bootstrap tests).
- **Packaging freshness (N1):** compares source hash vs derived copy vs manifest — **implemented**.
- **Automated tests:** pin current hash as a golden; update deliberately when the map legitimately changes — **implemented**.

Clients and server **independently load** the canonical content matching the identity and **verify the hash**. A mismatch must **fail explicitly** — never silently continue with stale or wrong content.

---

## Authoritative logical map vs derived outputs

```text
logical_map (authoritative source input — 2D grid + elevation levels)
    → WorldMap (canonical in-memory authority — implemented N1 foundation)
        → terrain construction (TS-08-equivalent solver — target production path)
            → presentation (mesh, material, collision, overlays, UI)
        → reference dataset (N2 — derived golden for parity/audit only; not production source)
```

- The **logical map** in `content/maps/` is authoritative **source** data: the canonical 2D hex grid and its height-level field (edge classifications are derived from it by the locked rule).
- **`WorldMap`** is the authoritative **in-memory** representation for gameplay — **implemented** as non-rendered foundation code (N1); not yet wired to gameplay, server, or 3D presentation.
- **Production terrain** must be **generated** from the logical map by running a **TS-08-equivalent solver**. The solver is part of the construction pipeline, not replaced by a pre-solved export.
- The **N2 Stage-2 reference dataset** (`content/terrain/reference/`) is a **derived reference golden** for parity testing and auditing the accepted TS-08 result. It is **not** the final production terrain source.
- **Blender TS-08** tooling outputs and **Godot** terrain meshes are **deterministic derivatives** — never gameplay authority.
- **Parity validation** compares solver output against the N2 golden, the TS-08 algorithm/parameters in [TERRAIN_SURFACE_TARGET.md](TERRAIN_SURFACE_TARGET.md), and the audit chain. Godot headless tests use a **compact digest manifest** (`game/domain/tests/fixtures/world/handdrawn_test_map_full_01_ts08_n3a_topology_parity_v1.json`, ~2 KB): counts plus **SHA-256 digests over complete canonical streams** (ordered node identities, pos keys, sheet IDs, Godot X/Z positions, canonical triangle set, center-pin mapping) with integer-quantized coordinates — no raw topology arrays, no solved non-center Y values, no sampling. N2 stays the sole comparison golden: `python tools/blender/terrain/generate_ts08_n3a_parity_manifest.py write|check` regenerates/verifies the manifest from N2. **N3b height parity** uses a **test-only binary height golden** (`game/domain/tests/fixtures/world/handdrawn_test_map_full_01_ts08_n3b_heights_v1.bin` + JSON sidecar, ~580 KB): little-endian float64 solved heights in N3a node-index order derived from N2 (`python tools/blender/terrain/generate_ts08_n3b_height_golden.py write|check`) — a **test golden**, not a persisted lattice cache and not a runtime terrain source. An optional N3 checkpoint that loads the pre-solved N2 dataset for early visual parity is **temporary only** — not target architecture.

### Edge classification vs terrain authority (locked)

- **`edge_rule`** in the logical map envelope defines how shared edges become **`smooth`** or **`cliff`** from the height-level grid ([MAP_MODEL.md](MAP_MODEL.md)). **`edge_overrides` is reserved and must be empty in schema v1** — every current edge classification is derived from the canonical height grid and the locked threshold rule.
- **`WorldMap`** may cache the resolved classification for consumers; that cache is **derived**, not a second authored terrain source.
- Continuous height under partial-hex / cliff-corner boundary conditions is **N3b solver** scope — outside N3a topology parity.

### Lattice persistence (direction only — not implemented)

N3a constructs the cut lattice **in memory** from `WorldMap`; there is **no persisted lattice cache**. If persistence/caching is later justified, the lattice must use a **compact, versioned binary representation** (packed numeric/index arrays) carrying the source `WorldMap` content hash, a format version, and an integrity checksum — **regenerable derived data, never canonical map content**. JSON remains reserved for the small human-inspectable digest manifest, not for storing the lattice itself.

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

**Implemented now:** nothing in the new yield model (legacy `CityYields.raw_terrain_yield` still runs on `HexMap`). **Planned:** N8 introduces yields v2 on `WorldMap` using flat base yields on the existing canonical schema v1 — no content-schema expansion is pre-approved; water, terrain categories, and passability require a separately justified schema change in N8 or later.

---

## Relationship to runtime map authorities

| Authority | Status |
|-----------|--------|
| **`WorldMap`** (approved, N1 implemented) | **Implemented** as foundation code — not yet wired to gameplay or server |
| **`HexMap`** (legacy) | **Still exists**, frozen, scheduled for removal N9 — categorical tags, no elevation |

There is **no adapter** between them. An explicit loading boundary converts envelope v1 → `WorldMap` at import ([WORLD_COORDINATES.md](WORLD_COORDINATES.md) import-boundary identity for the reference payload).

---

## Packaging and synchronization (implemented N1)

**Canonical source:** `content/maps/**`

**Mechanism:** repository-owned Python script `tools/content/sync_map_content.py`:

- Validates envelopes via `eom_terrain_math_core.parse_terrain_map_ir`.
- Copies byte-identically to `game/content/maps/**` (committed derived artifact for Godot `res://`).
- Writes `game/content/maps/manifest.json` with per-file `{path, map_id, schema_version, content_hash, source_path}`.
- Freshness: `python tools/content/sync_map_content.py check` and pytest under `tools/content/tests/`.

**Commands:**

```text
python tools/content/sync_map_content.py sync
python tools/content/sync_map_content.py check
```

**Per environment:**

- Local dev / Godot tests: `res://content/maps/**` via **`MapContentLoader`**
- Exports: include JSON + manifest
- Server (N5): a **stable canonical content path** in both local and container execution; canonical content **included in the server image/distribution**, byte-identical and **LF-safe** so the raw-byte `content_hash` stays stable across checkout, sync, and deployment; verified from a server-like or built-container environment
- Blender: continues reading canonical path via `eom_map_content.py`

---

## Promotion boundary (recorded, not designed)

Promoting an ordinary runtime-generated map into `content/maps/generated/` is initially a **developer/admin workflow**. No end-user publishing, Workshop, or marketplace system is being designed now.

---

## Loader ownership

| Layer | Owner |
|-------|-------|
| **Schema** | Shared conceptually across environments; envelope v1 rules documented here and in [WORLD_COORDINATES.md](WORLD_COORDINATES.md) |
| **Blender tooling loader** | `tools/blender/terrain/eom_map_content.py` — development/reference tooling only |
| **Repository sync tooling (N1)** | `tools/content/sync_map_content.py` — validates and copies canonical maps; **implemented** |
| **Godot loader (N1)** | `game/domain/world/map_content_loader.gd` — **implemented** |
| **Server loader (N5)** | Planned server-owned loader under `server/app/` — loads canonical content by `map_id`, validates it (envelope schema v1, empty `edge_overrides`), and computes the raw-byte SHA-256 `content_hash` and `MapIdentity`; identity comparison against an expected identity and explicit mismatch failure belong to the **N6 Godot bootstrap**, not N5; **must not import** from `tools/blender/` |
| **Architectural owner of map truth** | `WorldMap` — not any loader module |

The future authoritative **server runtime** must not depend on Blender tooling. N5 implements a server-owned map-content loader under `server/app/` following the same canonical schema and validation semantics as other loaders, without importing `eom_map_content.py` or any other module under `tools/blender/`.

---

## Related documents

- [MAP_MODEL.md](MAP_MODEL.md) — `WorldMap` layers and legacy `HexMap` status
- [WORLD_COORDINATES.md](WORLD_COORDINATES.md) — coordinate contract and elevation precision
- [TERRAIN_MODEL.md](TERRAIN_MODEL.md) — terrain construction model (TS-08)
- [TERRAIN_SURFACE_TARGET.md](TERRAIN_SURFACE_TARGET.md) — mathematical target
- [PHASE_PLAN.md](PHASE_PLAN.md) — N0–N9 implementation slices
- [CURRENT_ARCHITECTURE.md](CURRENT_ARCHITECTURE.md) — current vs target vs legacy
- [DECISION_LOG.md](DECISION_LOG.md) — approved architectural decisions
