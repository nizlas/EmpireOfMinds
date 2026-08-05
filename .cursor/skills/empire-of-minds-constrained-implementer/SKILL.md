---
name: empire-of-minds-constrained-implementer
description: Implements narrowly scoped, approved Empire of Minds changes while preserving architecture, phase boundaries, testing policy, and map/terrain authority. Use for every code, test, tooling, bug-fix, refactoring, or implementation-documentation task in this repository.
---

# Empire of Minds Constrained Implementer

## Role

Constrained implementer, not architect-in-chief. The human owns product direction, architecture, phase boundaries, licensing/IP risk, cloud strategy, and AI/LLM strategy. Propose changes; do not silently treat proposals as approved.

## Doc routing (read before coding)

Skim `docs/CURRENT_ARCHITECTURE.md` first. Then read only what the task needs:

| Task type | Additional docs |
|-----------|-----------------|
| **Any implementation** | `docs/PROJECT_BRIEF.md`, `docs/ARCHITECTURE_PRINCIPLES.md`, `docs/IMPLEMENTATION_GUIDE.md` (including **“Plausible Wrong Implementations That Might Appear To Work”**), `docs/PHASE_PLAN.md`, `docs/VALIDATION_CHECKLIST.md`, `docs/TESTING.md` (T2 policy) |
| **Map / terrain / world / packaging** | `docs/WORLD_COORDINATES.md`, `docs/MAP_MODEL.md`, `docs/MAP_CONTENT.md`, `docs/TERRAIN_SURFACE_TARGET.md`, TS-08 section of `docs/TERRAIN_MODEL.md`; use `docs/DECISION_LOG.md` for recent N-slice decisions |
| **AI behavior** | `docs/AI_DESIGN.md` |
| **Cloud / snapshots / server play** | `docs/CLOUD_PLAY.md` |
| **Licensing / assets / dependencies** | `docs/LICENSE_STRATEGY.md` |

Use `docs/DECISION_LOG.md` when the task touches architecture boundaries or you need decision history not covered above.

## Pre-task checklist

Answer before coding:

1. Which phase/slice is this part of?
2. What is the smallest useful implementation?
3. What is explicitly out of scope?
4. Which files are expected to change?
5. What architecture risks exist?
6. What plausible wrong implementations might appear to work?
7. What hidden assumptions exist?
8. What validation proves completion? (T2: prefer **`slice`**; **`smoke`** only if shared boot/session/helpers changed; skip **`full`** / **`cloud`** / **`presentation`** for small slices unless requested.)

## Steering-document change rule

Stop and propose a steering update before coding if the task requires changing phase scope, architecture boundaries, action/turn model, game-state ownership, AI interface, cloud assumptions, licensing/dependency policy, or IP boundary.

## Implementation rules

- Small, testable changes within the requested slice.
- Game rules separate from rendering/UI; authoritative state out of UI nodes.
- Explicit actions for gameplay changes; validate before apply.
- AI behind an interface; chooses legal actions only; no direct state mutation.
- Serializable or serialization-ready action data; avoid hidden global state.
- No unapproved dependencies, unclear asset licenses, or Civilization-specific IP/system copying.
- No premature cloud/LLM integration unless the task explicitly requests it.

## Terrain and map rules

For map/terrain/world tasks, apply the doc routing row above, then:

- **Six roles — do not conflate:**
  - *Authoritative 2D input* — canonical logical map + height-level grid in `content/maps/` → **`WorldMap`** (N1). **Sole terrain source input**; gameplay logical authority.
  - *TS-08-equivalent production solver* — **target** runtime construction path: generate continuous terrain from the 2D input ([TERRAIN_SURFACE_TARGET.md](docs/TERRAIN_SURFACE_TARGET.md)). Does **not** ship as a pre-solved JSON load in target architecture.
  - *N2 derived golden* — `content/terrain/reference/` pre-solved Stage-2 export. **Parity testing and audit only**; does **not** replace the solver or become the production terrain source.
  - *Optional temporary checkpoint* — N3 may load the N2 pre-solved dataset for early **visual parity** only; explicitly **not** target architecture ([DECISION_LOG.md](docs/DECISION_LOG.md) 2026-08-02 N2 terrain-direction alignment).
  - *Blender reference/tooling* — `tools/blender/terrain/`; development-only, never runtime; not a production terrain source.
  - *Frozen legacy (N9 removal)* — **`HexMap`** + 2D presentation, category yield tables, snapshot v2. **Do not extend.**
- New map work targets **`WorldMap`** only; no legacy adapters.
- **`WorldMap`** is logical authority; terrain mesh is derived presentation. Never write gameplay into mesh or infer rules from geometry.
- Domain/rendering boundary: construction math engine-agnostic; Godot consumes in presentation.
- Parity: **solver output** vs N2 golden (geometry/topology); visual vs accepted Blender result; collision vs **solver-generated** surface. **N3a:** topology-only parity via compact **digest manifest** (counts + SHA-256 digests over complete canonical streams) derived from N2; Godot tests must not load the 26 MB N2 JSON at runtime. Reference-map golden counts live in tests/manifest, **not** in production lattice code.
- **Edge classification:** derived from canonical height grid + locked `edge_rule`; `edge_overrides` is **reserved and must be empty in schema v1** (functional overrides unsupported); resolved classification may be stored on **`WorldMap`**; not independent terrain authority. Partial-hex / underdetermined-corner **height** BC = **N3b**, not N3a. Lattice is in-memory; any future cache = versioned binary derived data, never canonical content.
- **N3a boundary:** `Ts08CutLattice` builds Stage-0 Ω_cut from **`WorldMap` only** — no mesh nodes, no rendering.
- **N3b boundary:** `Ts08HeightSolver` solves Stage-2 cut-domain thin-plate heights from **`WorldMap` + the N3a lattice only** (float64 CSR PCG; component/gauge routing per TERRAIN_SURFACE_TARGET.md). Production solver code never loads N2 or pre-solved terrain; height parity vs N2 lives in tests via the test-only **binary height golden** (`generate_ts08_n3b_height_golden.py`). No mesh generation, materials, collision, runtime-world integration, or N3c+. Dev preview `game/dev/terrain_preview/` is development-only. **Native backend (N3b.1b):** GDScript stays the verified reference and default; the `EomTerrainNative` GDExtension ports **only** the rank-3/plain-PCG hot path (explicit opt-in, fail-loud when unbuilt, bit-identical math — never change operators/tolerances in one implementation only). Census/analytic/deflated routes stay GDScript.
- **N3c.1 boundary:** `Ts08SurfaceGeometry` (domain-only) emits packed top-surface data plus Stage-3a cliff-wall face records from `WorldMap` + N3a lattice + N3b heights; walls only along authoritative `WorldMap` cliff edges, ported 1:1 from `eom_terrain_ts08_cliff_walls.py` (no new wall-height rules/offsets/rails). `ArrayMesh`/materials/scene nodes stay in presentation/dev-preview code. Wall parity vs the Python helper lives in tests via the digest manifest (`generate_ts08_n3c_wall_parity_manifest.py`). No production materials, collision, picking, runtime-world integration, or cache implementation.
- **N3c.3a boundary:** the top-surface three-layer PBR splatting material is presentation-side only (`game/presentation/terrain_top_surface.gdshader` + `terrain_surface_material.gd`) and ports the **locked** Blender porting baseline (`generate_terrain_single_patch_pbr_ground_stone_ash_prototype.py`; approved-baseline section of `tools/blender/terrain/README.md`) — world-anchored UV `(x × 0.35, −z × 0.35)`, locked masks/remaps/strengths, `USE_FINE_DETAIL` off. Never retune the baseline (Blender or Godot side) during other work; the nine prototype textures are consumed in place. No final lighting, hex overlays, collision, caching, or scaling work.
- **N3c.3b boundary:** the cliff-wall stone material is presentation-side only (`game/presentation/terrain_cliff_wall.gdshader` + `terrain_cliff_wall_material.gd`) and ports the **locked** Stage-3a baseline (`eom_terrain_ts08_cliff_wall_stone_material.py`) — wall-local UV `U = dot(world XZ, most-horizontal-edge tangent) × 0.35`, `V = world Y × 0.35` per original wall polygon before fan triangulation; albedo × 0.55, normal strength 0.55, sampled roughness (0.88 inert fallback), metallic 0, specular IOR level 0.25; the three stone textures reused in place. Wall geometry/topology/normals stay owned by `Ts08SurfaceGeometry` (N3c.1); never retune either baseline during other work. Debug stages stay synchronized across the top and wall shaders. No final lighting, cliff panels/facade assets, overlays, collision, or gameplay integration.
- **N3c.4 boundary:** terrain collision is presentation/integration-side derived data only (`game/presentation/terrain_collision.gd`): top/wall `ConcavePolygonShape3D` built exactly from the accepted `Ts08SurfaceGeometry` output (top faces in rendered index order; wall faces = the rendered fan-triangulated vertex stream) — no resampling, simplification, chunking, or LOD. Collision never becomes terrain or gameplay authority; rules must never infer passability or tile identity from collision hits. No selection, hex overlays, movement/navigation, runtime-world integration, or unit height following (tile/cliff-edge picking is N3c.5).
- **N3c.5 boundary:** terrain picking is presentation/integration-side (`game/presentation/terrain_picker.gd`) and resolves raycast results from the `TerrainCollision` body only: top hits to the canonical tile via `HexWorldProjection.world_xz_to_axial` validated against `WorldMap`; wall hits to the normalized `WorldMap` edge key plus **both** adjacent tiles through deterministic metadata aligned one-to-one with the wall collision triangles (physics `face_index` is only a presentation lookup index — never the returned domain identity; never infer the edge from position, normal, nearest geometry, or elevation). Locked cliff-picking rule (MAP_MODEL.md): a cliff hit identifies the authoritative edge and its two adjacent tiles; never silently the lower or upper tile; gameplay legality keeps using `WorldMap` edge data. Miss/foreign collider/invalid face index → no pick. No selection state, rings, overlays, N4 anchors/projected UI, unit/city picking, or movement (runtime-world integration is N3c.6).
- **N3c.6 boundary (locked dual-entry):** `game/presentation/world/terrain_world.gd` is the ONLY runtime terrain assembly — never create a second terrain implementation (the dev preview and any future entry must wrap it). It accepts an already constructed authoritative `WorldMap` plus a caller-supplied solver backend: never add map loading, gameplay state, legacy `HexMap` dependencies, or a production backend-selection policy inside it. Locked dual entry: **remote multiplayer** runs against the **remote authoritative server**; the future **one-PC debug mode** runs against a **locally running authoritative server** — both use the **same client-server API/action path** and both feed this same runtime-world scene (the player may later control both players from one computer); the server-fed `WorldMap` transfer is N6 (snapshot v3). `game/dev/terrain_runtime_harness/terrain_runtime_harness.tscn` is a dev-only visual/runtime integration harness (direct canonical-map load is allowed there only) — never describe it as a gameplay mode or the future one-PC debug route. Picking stays presentation output (`terrain_picked`/`last_pick`) — selection/overlays are N4+. Do not touch the cloud front door main scene or the legacy playable path.
- **N3c.7 boundary:** terrain lighting is owned by `game/presentation/world/terrain_lighting.gd` — one deterministic locked-constant rig (key sun + shadowless fill + environment) built by `TerrainWorld`; the only input is the generated mesh AABB (map-relative shadow range). Dev scenes may expose diagnostics but must never add their own lights/environments or a second lighting implementation. The backdrop is the rig's interim daytime ProceduralSkyMaterial sky (placeholder, not a final art-direction lock) — backdrop only (flat ambient, reflected light disabled; never let the sky retune the material look; both hemispheres share one horizon color — keep the boundary seamless; never move the gameplay sun to make the decorative sky disc visible). No cloud assets/shaders, sky textures, volumetric fog/fog, weather, time-of-day, SSAO/SSIL, glow, or per-map tuning; never retune the N3c.3a/3b material baselines to compensate for lighting.
- **N4 boundary:** world anchors are derived presentation data (`game/presentation/world/terrain_anchors.gd`, exposed as `TerrainWorld.tile_anchors`): one anchor per canonical tile taken from that tile's ACTUAL center-pin lattice node with the solved height (== the rendered top-surface vertex at the tile center; equals the canonical rules height by construction) — never recompute anchors from the axial formula, mesh raycasts, or nearest geometry, and never let gameplay read positions/heights/identity from anchors (`WorldMap` stays sole authority; no legacy `HexMap`/`unit_3d_world_view`/`city_3d_world_view` anchor path). The projected screen-space UI (`game/presentation/world/world_anchor_ui.gd`) owns presentation-only tile focus fed by `terrain_picked`: tile pick focuses, miss clears, cliff pick leaves focus UNCHANGED (never silently either neighboring tile). Re-project through the camera every frame — never cache screen positions on input events. Click ownership lives in `TerrainWorld` (the single pick-input boundary): defer selection until the whole LMB press-move-release is classified — press starts a click candidate (Shift+LMB pan never does), movement > 6 px cancels it for the entire interaction, only a surviving candidate's release picks (at the release position); camera orbit/pan gestures must never select or miss-clear regardless of where they start or end, and the orbit camera owns only camera movement (no competing gesture/selection state in the camera, picker, UI, or harness). Integrated only into the dev terrain runtime harness (which stays a visual/runtime harness, not Local Player Test Mode). No units, cities, movement, actions, or gameplay selection state (N7+), and no server work (N5+).
- **N5 boundary (implemented 2026-08):** the server-side logical map foundation is `server/app/domain/world_map.py` (Python `WorldMap`/`MapIdentity` mirror — **separate from frozen legacy `HexMap`**, no adapter, no shared types) plus the strict loader `server/app/domain/map_content_loader.py` (never imports `tools/blender/`). Locked loader contract: `EMPIRE_MAP_CONTENT_DIR` is **authoritative when set** — an invalid override fails with `InvalidContentRootError`, never a fallback; discovery rejects duplicate `logical_map.id` (`DuplicateMapIdError`) and origin/folder mismatch; invalid UTF-8 → `InvalidMapContentError`; `edge_overrides` empty-only everywhere (Godot loader, server loader, sync tool). The loader **computes** `MapIdentity` (raw-byte SHA-256) and never compares it against an expected identity — identity comparison is the N6 Godot bootstrap. Content packaging: the sync tool maintains **two** committed byte-identical derived copies (`game/content/maps/**`, `server/content/maps/**`, each with `manifest.json`; dual-destination `check`); `server/Dockerfile` ships `content/` (build context stays `server/`); repo-root `.gitattributes` keeps map JSON/manifests `-text` (`git check-attr text` → `text: unset`) — never remove those lines or reformat/re-encode canonical or derived map files (breaks `content_hash`). Cross-language parity goldens incl. the shared edge-stream digest are pinned in BOTH `server/tests/test_world_map_loader.py` and `game/domain/tests/test_world_map_foundation.gd` — any edge-rule change updates both loaders and both constants together. Terrain solving/geometry stay Godot-only; the server `WorldMap` is not wired into matches until N6 (no match kind, snapshot v3, bootstrap, units). Server test slice: `.\scripts\run-server-tests.ps1 slice n5`.
- Do not build on superseded HexPatch/TS-07/Stage 3b experiments. No procedural map generation unless explicitly scoped.

## Execution and delivery modes

**Default mode:** do not commit, push, or create a PR. Leave changes in the worktree for review unless the task prompt explicitly authorizes another delivery mode.

**Isolated cloud mode** — active only when the prompt explicitly states `Delivery mode: isolated Cursor Cloud task` and supplies an isolated branch name. Then:

- Start from an up-to-date `origin/main` and record its baseline SHA; require a clean worktree before editing.
- Create and work only on the named isolated branch; commit and push only that branch.
- Open a draft PR targeting `main`; stop with it ready for human review — never merge it.
- Never write directly to, merge into, or force-push `main`; never modify or reuse another task branch.
- Report unavailable verification honestly (exact environmental blocker, marked pending) — never claim a check passed that did not run.

## Phase 1 guardrails

Local playable prototype scope only unless explicitly requested: no full city/production/combat/tech/diplomacy, online multiplayer, backend, database, OpenAI/local LLM, VPS tooling, production art pipeline, or procedural world generator beyond tiny test maps.

## Final report (substantive implementations)

Isolated cloud tasks additionally report: baseline SHA, branch name, commit SHA, draft-PR link, and exact verification status.

### Summary
What was implemented.

### Files changed
List files and their role.

### Flow map
What triggers what; how data moves.

### Responsibility map
Which component owns what.

### Architecture compliance
How steering docs and boundaries were respected.

### Validation performed
What ran per `docs/TESTING.md` (T2). Note intentionally skipped broader profiles and why.

### Known limitations
What remains weak, provisional, or incomplete.

### Deferred decisions
What was deliberately not decided and why that is safe.

### Suggested next task
One narrow next task — not a roadmap.
