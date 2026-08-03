# Empire of Minds — Domain map model

**Status (2026-08):** **`WorldMap`** foundation is **implemented** (slice **N1**) under `game/domain/world/` — loads packaged canonical content, derives edges, exposes projection math. **Not yet connected** to gameplay, server, or 3D rendering. The current runnable game still uses the legacy **`HexMap`** categorical model documented in [Legacy HexMap (frozen)](#legacy-hexmap-frozen) below.

Coordinate contract: [WORLD_COORDINATES.md](WORLD_COORDINATES.md). Map content ownership: [MAP_CONTENT.md](MAP_CONTENT.md). Axial cell identity: [HEX_COORDINATES.md](HEX_COORDINATES.md).

---

## Approved target — `WorldMap` (one canonical authority)

**Decision:** `WorldMap` is the **sole** logical map authority for the 3D world integration phase. There is **no** parallel `HexMap` authority, **no** adapter to keep the deprecated 2D map alive, and **no** deferred unification. Legacy `HexMap` (GDScript and Python) is **frozen** and scheduled for removal in slice **N8**.

Everything that refers to “the map” in gameplay, server state, terrain construction, and presentation must use the same tile and edge identities from `WorldMap`:

- units, cities, improvements, ownership,
- movement and combat legality,
- yields and legal actions,
- scenario setup,
- terrain mesh/collision/overlays (as consumers, never as authority).

### Layered model

| Layer | Owner | Authority | v1 subset | Deferred |
|-------|-------|-----------|-----------|----------|
| 1. Tile identity & coordinates | `WorldMap.tiles` keyed by `(q,r)` | Immutable per map revision | All tiles from source JSON | — |
| 2. Physical tile properties | Tile records on `WorldMap` | Shared world truth | `elevation` (int) | soil, moisture, drainage, fertility, rock exposure, geology, vegetation, accessibility/buildability |
| 3. Edge relations | `WorldMap.edges` | Shared world truth | `smooth` / `cliff` from `\|Δe\| > threshold` + overrides | ravine, river, road/crossing, directional passability |
| 4. Derived terrain metrics | `TerrainMetrics` (planned module) | Deterministic derivation; rule-locked when consumed | — (extension point) | gradient, curvature, ruggedness, prominence |
| 5. Derived classifications | Classifier (planned) | Derived labels for UI/rules/AI | — (extension point) | hill, ridge, valley, plain, rocky slope, wet lowland, fertile plain |
| 6. Mutable match state | Match core (`Scenario` / `GameState` pattern, rewritten) | Authoritative per match | Units, cities, turn state, ownership, id counters, **`MapIdentity`** stamp | World-mutating terraforming rules |
| 7. Capabilities & player knowledge | Progress/science + `KnowledgeState` | Player-scoped where noted | Explored-set pattern reused from `PlayerVisibilityState` | Prospecting, discovered geology |
| 8. Improvements & exploitation | Match-state entities on tile/edge ids | Authoritative | — (extension point) | Full improvement catalog |
| 9. Yields & legal actions | Pure functions over layers 1–8 | Derived, authoritative outputs | Flat base yields (N6); movement over edges (N5) | Capability-driven yield content, full balance |
| 10. Presentation | 3D scene: mesh, materials, collision, overlays, UI | Derivative only | TS-08 solver-generated surface (N3); N2 golden for parity | Final materials, full UI catalog |

**Stable identities:**

- **Tile id:** canonical axial `(q, r)` (same as [HEX_COORDINATES.md](HEX_COORDINATES.md)).
- **Edge id (undirected):** a normalized pair of adjacent tile ids. Tile identities are ordered **lexicographically** by `q`, then by `r` when `q` is equal. An undirected edge identity is:

  ```text
  edge_id = (min_lex(tile_a, tile_b), max_lex(tile_a, tile_b))
  ```

  where each tile identity is its canonical axial `(q, r)` coordinate.

  This identity is independent of iteration order, which tile is upper or lower in elevation, smooth/cliff classification, mesh vertices or triangle indices, and presentation or collision geometry. When a rule needs a **directed** edge (e.g. movement from A to B), use the ordered pair `(from_tile, to_tile)` explicitly — do not substitute a sequential edge index.

**Scenario setup** belongs beside the match core: a `ScenarioFactory` takes a `MapIdentity`-resolved `WorldMap` plus a scenario spec (starting units, cities, players). Map factories on the map class itself are **not** carried forward.

### Rendered geometry is never gameplay authority

The continuous terrain mesh, cliff-wall collision triangles, shader output, and sampled surface heights are **presentation derivatives**. Rules must never infer passability, cliff blocking, or tile identity from mesh topology or triangle hits alone.

- **Top-surface hits** resolve to a tile via the coordinate inverse ([WORLD_COORDINATES.md](WORLD_COORDINATES.md)).
- **Cliff-face hits** resolve primarily to **`edge_id`** and both adjacent tile identities, with hit classification distinguishing cliff face from top surface.
- There is **no** universal rule that cliff hits always select the lower tile. Operations that require a tile must define their own deterministic policy, ask the player to target a top surface, or explicitly choose between adjacent tiles.
- Gameplay legality uses authoritative **edge data** on `WorldMap`, not visual geometry.

### Yield direction (replacing category tables)

The new model **retires** fixed intrinsic yield tables keyed by categorical `terrain` / `landform` / `woods`. Old descriptions such as “production from hills” remain **design intent** to translate into physical/capability terms — not schema requirements.

- **Base yields (v1):** simple, potentially flat physical base yields computed deterministically from physical properties.
- **Later divergence** through physical properties, adjacency/edges, civilization capabilities, player-scoped knowledge, discovered geology/resources, improvements, exploitation state, and other deterministic modifiers.
- **`Hill` and similar** are normally **derived classifications**, not primitive terrain truth.
- **Cliffs** are **edge relations**, not a boolean terrain type on one tile.

### Edge classification (locked — N3a)

Shared tile edges are classified **`smooth`** vs **`cliff`** deterministically from the canonical height-level grid:

1. Compute `|Δelevation|` for each undirected neighbor pair.
2. Apply the locked rule from envelope `edge_rule` (reference map: cliff when `|Δ| > cliff_threshold`, default threshold **1**).

**`edge_overrides`** in the envelope is **reserved for possible future use**: override behavior is **not implemented**, and the field must be an **empty array (or absent)** in schema v1 — loaders reject a non-empty list as unsupported. All current classifications come from the height grid plus the locked threshold rule.

**Authority boundaries:**

- Edge classification is **derived** from the logical map — not independently authored terrain geometry.
- The resolved classification may be **stored on `WorldMap`** (`WorldEdge.transition`) for consumers (construction, movement, UI).
- It is **not** a separate terrain authority layer; changing cliffs in presentation or mesh must not feed back into gameplay.
- **Underdetermined hex interior height** (partial-hex boundary condition at cliff corners) belongs to the **N3b height solver contract**, not N3a topology construction.

N3a (`Ts08CutLattice`) consumes **`WorldMap` edges** plus the TS-08 cut/merge rules to build Ω_cut topology only — no continuous height solve. The lattice is held **in memory**; any future persisted lattice cache must be a compact, versioned **binary** format (packed arrays, source `WorldMap` hash, format version, integrity checksum) treated as regenerable derived data — see [MAP_CONTENT.md](MAP_CONTENT.md).

N3b (`Ts08HeightSolver`) consumes the **`WorldMap`** plus the N3a lattice to solve the Stage-2 cut-domain thin-plate heights ([TERRAIN_SURFACE_TARGET.md](TERRAIN_SURFACE_TARGET.md)), including the partial-hex/underdetermined-component gauge convention (analytic constant/plane, deflated CG + exact post-projection). Solved heights are **derived data in memory** — never gameplay authority, never persisted map content. Production solver code never loads N2 or pre-solved terrain; N2 parity lives in tests via a test-only binary height golden. The GDScript solver is the verified reference and default; an **explicit opt-in** native `cg_plain` backend (`EomTerrainNative` GDExtension, N3b.1b) accelerates only the global plain-PCG path with bit-identical results, and fails loudly when the locally built extension is unavailable.

N3c.1 (`Ts08SurfaceGeometry`) consumes the `WorldMap`, the N3a lattice, and the N3b solved heights to emit **packed surface geometry**: the accepted top surface (Y-up triangles, smooth normals) plus Stage-3a cliff-wall polygons ported from the accepted Python helper. Walls exist **only along authoritative `WorldMap` cliff edges** and stay separately identifiable face records (cliff pair, segment, oriented node indices, height delta) so future wall materials and collision never infer cliffs from slope. All of it is **derived data in memory** — presentation derivatives, never gameplay authority.

**Derived terrain cache (approved contract — format not designed or implemented yet):**

- **Fixed (authored/reference) maps** may ship with prebuilt derived caches (lattice/heights) so players do not pay solve cost for content that never changes.
- **Future procedural maps** generate terrain at runtime on cache miss; an **exactly identical previously generated map** may reuse its cache.
- **Cache identity** includes the actual `WorldMap` content (content hash), plus generator version, generation parameters, and cache format version — never map name alone.
- **`WorldMap` remains authoritative**: a cache is regenerable derived data (compact, versioned binary with integrity checksum, per the lattice-cache direction above), never canonical content, and never a terrain authority. On identity mismatch the cache is discarded and terrain is re-solved.

See [MAP_CONTENT.md](MAP_CONTENT.md) for yield/knowledge boundaries and [DECISION_LOG.md](DECISION_LOG.md) for the approved direction.

### Snapshot v3 (planned N7 — not implemented)

Match snapshots will carry **`MapIdentity`** (`map_id`, `schema_version`, `content_hash`) plus **mutable match state**. Snapshots should **not** repeat every immutable tile and edge from the canonical map — clients and server load the canonical content matching the identity and verify the hash. Mismatch must **fail explicitly**. Details: [MAP_CONTENT.md](MAP_CONTENT.md).

### Planned module ownership (names provisional)

| Module | Responsibility |
|--------|----------------|
| `game/domain/world/world_map.gd` | Sole logical map authority |
| `game/domain/world/hex_world_projection.gd` | [WORLD_COORDINATES.md](WORLD_COORDINATES.md) math |
| `game/domain/world/map_content_loader.gd` | Envelope v1 → `WorldMap` + `MapIdentity` |
| `game/domain/world/ts08_terrain_math.gd` | TS-08 construction math (scalar float64; Python-compatible `pos_key`) |
| `game/domain/world/ts08_cut_lattice.gd` | TS-08 Stage-0 cut-lattice topology from `WorldMap` (N3a) |
| `game/domain/world/ts08_height_solver.gd` | TS-08 Stage-2 cut-domain thin-plate CG height solve (N3b) |
| `game/domain/world/ts08_surface_geometry.gd` | TS-08 surface geometry: top surface + Stage-3a cliff-wall faces as packed data (N3c.1) |
| `server/app/domain/world_map.py` | Python mirror (N7) |

Presentation modules under `game/presentation/world3d/` consume `WorldMap`; they do not own map truth.

### Terrain input vs generated surface (locked)

| Role | Authority | Notes |
|------|-----------|-------|
| Canonical 2D map + elevation levels | **Authoritative terrain input** | `content/maps/` → **`WorldMap`** |
| TS-08-equivalent solver | **Production construction path** | Generates continuous surface from input |
| N2 reference dataset | **Derived golden** | Parity testing/audit only; not production source |
| Mesh / collision / sampled Y | **Presentation derivative** | Never gameplay authority |

An optional N3 checkpoint that loads the N2 pre-solved dataset for early visual parity is **temporary only** — not target architecture. Details: [PHASE_PLAN.md](PHASE_PLAN.md), [MAP_CONTENT.md](MAP_CONTENT.md), `content/terrain/reference/README.md`.

---

## Legacy HexMap (frozen)

The following **still exists in the repository today** but is **deprecated, frozen, and scheduled for removal** (slice N8). New work must **not** extend it or build adapters for it.

### What is legacy

| Component | Location | Current behavior |
|-----------|----------|------------------|
| **`HexMap`** | [game/domain/hex_map.gd](../game/domain/hex_map.gd), [server/app/domain/hex_map.py](../server/app/domain/hex_map.py) | Categorical `Terrain` (PLAINS, WATER, GRASSLAND), `Landform` (FLAT, HILLS), optional `_woods`; **no elevation** |
| **Category yield tables** | [game/domain/city_yields.gd](../game/domain/city_yields.gd) | Fixed terrain × landform × woods production |
| **Snapshot v2 cells** | [server/app/domain/snapshot.py](../server/app/domain/snapshot.py) | `{q, r, terrain, landform, woods}` |
| **2D map renderer** | [game/presentation/map_view.gd](../game/presentation/map_view.gd), [HexLayout](../game/presentation/hex_layout.gd), overlays, fake-perspective camera | 2D projected map; polygon picking |
| **Rules coupled to categories** | [MovementRules](../game/domain/movement_rules.gd), [FoundCity](../game/domain/actions/found_city.gd), [TerrainRuleDefinitions](../game/domain/content/terrain_rule_definitions.gd) | WATER impassable; hills are presentation-only tags |

**Breakage during migration is acceptable.** The 2D map path may stop working as `WorldMap` lands; that is intentional.

### Legacy representation (reference only)

- Storage: `Vector2i(q, r)` → terrain enum; parallel `_landforms`, `_woods`.
- Factories: `make_tiny_test_map()` (7 hexes), `make_prototype_play_map()` (~220–750 cells with curated land/water/woods).
- Query API: `has`, `terrain_at`, `landform_at`, `has_woods`, `coords`, `size`.

Full Phase 1.2–5.x presentation notes for the 2D map remain in git history and phase docs ([PHASE_PLAN.md](PHASE_PLAN.md), [RENDERING.md](RENDERING.md)); they describe **historical implemented behavior**, not the target architecture.

### What may be reused from legacy code

Reuse is justified by **suitability**, not backward compatibility:

- **`HexCoord`** axial deltas and distance — orientation-neutral; gains geographic meaning under [WORLD_COORDINATES.md](WORLD_COORDINATES.md).
- **Action-in / state-out pattern** (`GameState.try_apply`, action dicts) — preserved; validators rewritten against `WorldMap`.
- **`PlayerVisibilityState`** explored-set pattern — extended toward player-scoped knowledge.
- **Server transport** (POST action, GET snapshot) — preserved; snapshot shape replaced in N7.

---

## Layer boundary

Code under `game/domain/` must not depend on Godot scene nodes, rendering, UI, input, networking, or LLMs; see [game/domain/README.md](../game/domain/README.md).

---

## Related documents

| Topic | Document |
|-------|----------|
| World embedding & elevation | [WORLD_COORDINATES.md](WORLD_COORDINATES.md) |
| Map content & `MapIdentity` | [MAP_CONTENT.md](MAP_CONTENT.md) |
| Terrain construction (TS-08) | [TERRAIN_SURFACE_TARGET.md](TERRAIN_SURFACE_TARGET.md), [TERRAIN_MODEL.md](TERRAIN_MODEL.md) |
| Legacy deprecation policy | [CURRENT_ARCHITECTURE.md](CURRENT_ARCHITECTURE.md) § Legacy map systems |
| Implementation slices | [PHASE_PLAN.md](PHASE_PLAN.md) — 3D Map and World Integration (N0–N8) |
