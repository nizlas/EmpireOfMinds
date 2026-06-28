# Empire of Minds — Canonical terrain model (planning)

Status: **planning / design-of-record**. This document defines the canonical mathematical model for Empire of Minds 3D terrain generation. It is the source of truth for future implementation; **no implementation is described here as done** unless a section explicitly states otherwise (e.g. §10 current boundary snap). The **Mid-Edge Invariant** (§11) defines canonical center→edge-midpoint heights; the **Smooth Ribbon G1 gate** (§12) resolves cross-edge tangents; the **HexPatch center bubble anchor** (§13) fixes tile center height; **§14 falsifies** the first-slice IDW operator; **§15–§16 freeze HexPatch Mathematics v1.0** (smooth core) as a **reference backend specification** under the **`TerrainSolver`** framework (see [DECISION_LOG.md](DECISION_LOG.md) entry "pivot to Global Terrain Optimization") — not the assumed final terrain model. It does not change gameplay, the domain `HexMap` (tag-only; see [MAP_MODEL.md](MAP_MODEL.md)), or any Godot code.

This model was selected in the Terrain Mathematics Design Review. See the decision-log entry "Adopt heightfield + edge constraints as canonical terrain model" in [DECISION_LOG.md](DECISION_LOG.md).

## Scope and intent

- Define a deterministic terrain model that supports rolling hills, plateaus, cliffs, ravines, and escarpments from **hand-authored** maps (PowerPoint-derived, JSON) and **future procedural** maps.
- Preserve the approved Blender prototype appearance for smooth regions. Do **not** introduce a new smoothing model.
- Add exactly one new capability over the approved prototype: certain neighbor relationships can be marked **cliff** and excluded from smoothing.

Axial coordinates `(q, r)` and neighbor directions follow [HEX_COORDINATES.md](HEX_COORDINATES.md) (E, NE, NW, W, SW, SE). The terrain tooling's `NEIGHBOR_DIRS` already matches this table.

## Background: two curvature kernels exist today

The repository contains two different curvature implementations, and conflating them is the root cause of recent crumpled / faceted output.

- **Radial single-hill kernel** — `sample_radial_height()` in `tools/blender/terrain/generate_terrain_single_patch_pbr_ground_stone_ash_prototype.py`. Height is measured as a smootherstep falloff from **one** hill center over `HILL_RADIUS = 2.2 * HEX_RADIUS`. This produced the approved visual but is mathematically a **special case for a single hill**; it cannot represent a general elevation map.
- **Analytic per-hex kernel** — `tools/blender/terrain/generate_terrain_prototype.py`: `build_corner_height_map`, `sector_barycentric_xy`, `sector_edge_height`, `analytic_surface_height`. This **generalizes to any elevation map** and is the true canonical curvature.

The two kernels share identical mesh topology (the same per-sector barycentric grid and the same `pos_key` world-XY vertex sharing used in `build_single_patch_mesh`). The single-patch baseline simply swapped the height **source** from analytic center→edge blending to radial sampling. The canonical model is therefore a localized swap at the height-sampling seam, not a rewrite.

The crumpling seen in `tools/blender/terrain/generate_terrain_single_patch_pbr_ground_stone_ash_handdrawn_map_test.py` came from a third, ad-hoc hybrid: a **global** corner-height map (`_build_corner_heights`) plus a `max(zs)` override at any corner touching a cliff (`_corner_height_from_tiles`). That global+max approach blends and ramps across cliff lines and is **not** part of the canonical model.

## 1. Data model — TerrainMap IR (heightfield + edge constraints)

The canonical representation is a **heightfield plus sparse edge constraints** (not a heightfield alone, and not a fully hand-authored edge graph).

- **Primary source of truth: an integer heightfield.** Each tile is `{ q, r, elevation }`. World height is `(elevation - base) * elevation_step` (the prototype uses `ELEVATION_STEP = 0.4`).
- **Edge transitions are derived, with sparse explicit overrides.**
  - Default rule classifies each shared neighbor edge: `abs(delta elevation) > threshold` ⇒ **cliff**, otherwise **smooth** (`threshold = 1` in current maps).
  - An optional override list `{ edge: [tileA, tileB], transition: "cliff" | "smooth" }` can force a transition — most importantly a **cliff at delta = 1** (an escarpment between equal-or-near-equal elevations). Overrides may also force a smooth edge across a large delta if ever needed.
  - The full transition graph is **computed**, not authored edge-by-edge.

Source-agnostic intermediate representation:

```
TerrainMap = {
  tiles:           { (q, r) -> elevation:int },
  edge_overrides:  { sorted_edge_key((qA,rA),(qB,rB)) -> "cliff" | "smooth" },
  params:          { elevation_step, default_cliff_threshold, ... }
}
```

Why this model (option C) rather than alternatives:

- **Heightfield only** cannot represent equal-elevation escarpments or author-forced cliffs.
- **Heightfield + fully authored edge graph** forces authoring every edge; poor fit for hand-drawn and procedural input.
- **Heightfield + edge constraints** keeps authoring light, stays deterministic, and supports both hand-authored and procedural sources.

## 2. Smoothing domains and cliff semantics

Define a **smoothing graph**: nodes are tiles; an edge exists between two neighboring tiles only when their resolved transition is **smooth**. Cliff edges are simply absent.

- **A smoothing domain is a connected component of the smoothing graph.**
- **Corner heights are computed per smoothing domain.** A lattice corner's height is the mean elevation of only the tiles **in that domain** that touch the corner — a function of `(corner world-XY, domain)`, not of corner world-XY alone.
- **Cliffs do not participate in smoothing.** Because the far side of a cliff is in a different connected component, it cannot contribute to a domain's corner heights or surface interpolation. This is exactly the intended intuition: for smoothing purposes, the other side of a cliff does not exist.
- This removes any need for the `max()` corner override: heights never blend across a cliff because the contributing tile set is partitioned by construction.

This is mathematically clean: smoothing is defined independently within each domain, and the model is deterministic given the heightfield and resolved transitions.

## 3. Top-surface generation

- **Smooth-connected tiles form one continuous surface.** Within a domain, shared `pos_key` world-XY vertices merge, exactly as the approved baseline already merges them in `build_single_patch_mesh`.
- **Cliff-separated regions are independent local smoothing domains.** At a cliff boundary a shared lattice corner becomes **two coincident-XY vertices with different Z** (one per adjacent domain); these are deliberately **not** merged. That intentional gap is the cliff.
- **Within each domain, use the analytic per-hex kernel unchanged.** Height is `center + (edge - center) * profile(radial)`, with edge heights derived from per-domain shared-corner means (`analytic_surface_height` / `sector_edge_height` semantics). Use the same profile that reproduces the approved appearance (`smootherstep`); tuning the profile to match the approved look is allowed, inventing a new smoother is not.

## 4. Cliff edges and cliff walls

Cliff and ravine edges are treated as **internal hard borders between two elevation regions**, not as ordinary textured terrain slopes.

- **Top-surface separation and deterministic edge semantics are the priority deliverable**, not cliff-wall fidelity. The two sides' top surfaces are generated independently and must never interpolate across the edge (sections 2–3).
- **Cliff walls are placeholder presentation in the first model.** The vertical/abrupt gap may be simple, hidden, dark, or minimally capped (for example a flat dark skirt, or no fill at all). Do **not** invest in cliff-wall UV/texture mapping in the first model.
- **Walls are a downstream phase** that consumes resolved top surfaces and never feeds back into corner-height averaging or surface interpolation.
- **The cliff-edge graph is an authoritative output.** The list of cliff/ravine edges (with their two tiles and elevations) is a first-class, persisted result of the math core, deterministic and order-independent across runs and sources.
- **Intended final visual: external rock/cliff props.** Later, deterministic 3D rock/cliff formation props (for example Meshy-generated) are placed **along the authoritative cliff-edge graph**. Cliff walls in the generated mesh remain placeholders until props cover them.

## 5. Mesh-generation phases

1. Parse source (PowerPoint-derived / JSON / future procedural) into the **TerrainMap IR**.
2. Resolve edge transitions (default rule + sparse overrides).
3. Partition tiles into **smoothing domains** (connected components over smooth edges).
4. Compute **per-domain corner heights** (mean of in-domain tiles touching each corner).
5. Generate the **per-domain analytic top surface** (shared vertices within a domain; boundary corners split across domains).
6. Emit the **authoritative cliff-edge graph**.
7. Build **placeholder cliff-wall / gap fill** (separate phase; never influences smoothing).
8. Build skirt / base / rim, assign materials, and the hex overlay using the existing approved baseline assembly.

A later, separate phase places rock/cliff props along the cliff-edge graph.

## 6. Long-term architecture

```
PowerPoint export ┐
JSON maps         ├─> TerrainMap IR ─> pure deterministic math core ─┬─> Blender mesh backend
future procedural ┘    (heightfield +     (domains, per-domain        ├─> future Godot runtime backend
                        edge constraints)   corner heights, analytic   └─> later prop-placement pass
                                            sampler, cliff-edge graph)      (along cliff-edge graph)
```

- **Pure deterministic math core** (no `bpy`, no Godot): domain partitioning, per-domain corner heights, the analytic height sampler, and cliff-edge resolution. Identical results across Blender prototyping and a future Godot runtime, and testable outside Blender.
- **Thin backends.** The Blender backend keeps the approved baseline's mesh assembly and material graph and consumes the math core. The current handdrawn test's approach — monkeypatching the imported baseline module via `importlib` plus `inspect.getsource` string replacement — is fragile and should be retired in favor of the math core.
- **Separation of concerns.** This terrain mesh model is presentation/tooling. The gameplay domain `HexMap` stays tag-only (see [MAP_MODEL.md](MAP_MODEL.md)); axial conventions stay aligned with [HEX_COORDINATES.md](HEX_COORDINATES.md).

## 7. Risks and tradeoffs

- **Appearance parity is not automatic.** The radial and analytic kernels are different functions; the analytic kernel must be visually validated against the approved 7-hex baseline, with profile tuning if needed (appearance-preserving, not a new model). This gates adoption.
- **Slope continuity at smooth edges.** The legacy per-tile analytic / radial models match heights at shared edges but not necessarily cross-edge tangents (§7 historical note). The **Smooth Ribbon G1 gate** (§12) targets **G1 across smooth edges** by sharing a cross-edge tangent while preserving the canonical midpoint height; cliff edges remain intentionally discontinuous.
- **Vertex duplication at cliffs** increases counts and requires careful `(pos_key, domain)` keying to avoid accidental merges or T-junctions along boundaries.
- **Subdivision cost.** `SURFACE_SUBDIVISIONS` (currently 12) trades faceting against mesh size; keep it a single knob.
- **Cliff-edge graph is a contract.** Because rock/cliff props will be placed along it, the edge graph must be stable, deterministic, and order-independent across runs and sources — treat it as a versioned output, not a debug log.
- **Godot parity.** The math core must avoid Blender-only assumptions so the runtime backend reproduces identical heights.

## 8. Constraints carried from the review

- Deterministic-first.
- Preserve the approved prototype curvature behavior for smooth regions.
- Do not redesign terrain appearance.
- Do not optimize prematurely.
- This document is model/architecture only; implementation is a later, separate task and must not modify the approved prototype scripts.

## 9. Mixed corners (SSC) and local corner deformation

This section is the **design of record** for how the canonical model treats mixed smooth/cliff corners. It was selected after an adversarial review of the alternatives. See the decision-log entry "Adopt local mixed-corner deformation while preserving authoritative edge semantics" in [DECISION_LOG.md](DECISION_LOG.md). **No implementation is described here as done.**

### 9.1 Mixed-corner topology

Every **interior** lattice corner is shared by exactly **three** tiles (A, B, C) with three incident edges `AB`, `BC`, `CA`. Boundary corners have one or two tiles and are always consistent. Classifying each incident edge as smooth (S) or cliff (C) gives four classes by cliff count:

- **SSS** (0 cliffs): one smooth component `{A,B,C}`. Consistent.
- **SSC** (1 cliff): the single cliff edge's two endpoints are **bridged** by the other two smooth edges, so `{A,B,C}` is one smooth-connected component **that contains a cliff pair**. This is the only inconsistent interior class.
- **SCC** (2 cliffs): the two cliff edges always share a tile, giving components `{A,B}`, `{C}`. Consistent.
- **CCC** (3 cliffs): components `{A}`, `{B}`, `{C}`. Consistent.

Consistency rule: an interior corner is geometrically consistent under edge-local smoothing iff **no cliff edge has both endpoints in the same smooth-connected component at that corner**. The only violating class is **SSC**.

### 9.2 The SSC problem

Example: A = 1, B = 2, C = 4, with `A↔B` smooth, `B↔C` smooth, `A↔C` cliff.

Edge-local / per-tile corner heights make the shared corner **multivalued**: the value derived from A excludes A's cliff neighbour C, the value from C excludes A, and the value from B includes all three. The smooth edges `AB` and `BC` then disagree at the shared corner, producing a seam that is currently hidden by vertex splitting and the placeholder cliff wall. This is the "tension at the corner."

Note (default rule): a **bridged** SSC corner can only occur when the cliff edge's elevation delta is exactly **2** (the bridge tile B must be within one step of both A and C, forcing `|zA − zC| ≤ 2`, while a cliff needs `> 1`). In that benign default case the natural shared value equals B's own elevation. Larger or asymmetric SSC corners can only be produced through `edge_overrides`.

### 9.3 Rejected: full shared-corner ownership (full-edge taper)

One candidate fix is to give the whole corner-incident smooth component a single shared corner height (e.g. the component mean) and let the cliff gap follow from those smoothed corners. **This is rejected.**

- A cliff edge has **two** corners. Pinning both via shared smoothed corners can **taper the gap to zero at both ends**, and when **both endpoints are bridged** the cliff collapses to zero gap **along its entire length** — a classified cliff with no geometry.
- This is reachable under the **default rule** (e.g. A = 1, C = 3 with elevation-2 tiles on both flanks) and trivially under `edge_overrides` (e.g. a forced equal-elevation escarpment between three equal tiles).
- Letting the smoothed corner define the cliff gap makes geometry contradict the resolved transition, breaking the **"edge is authoritative"** contract and confusing the cliff-edge graph and prop placement.

### 9.4 Accepted: authoritative edge + bounded local corner deformation

**Edge owns the edge; the corner may locally deform nearby surface samples.**

- **Edge classification stays authoritative.** A smooth edge is a smooth transition; a cliff edge is a hard, movement-relevant discontinuity for its **full** gameplay edge.
- **Cliff height/gap is defined from the resolved edge transition and the integer elevation delta** (`|Δelevation| · elevation_step`), **never** from smoothed corner heights. The gap is constant along the edge as far as the model is concerned; it does not taper to zero from corner smoothing.
- **At SSC corners only, a small local top-surface deformation may be applied near the shared corner** so adjacent **smooth** surfaces meet cleanly there. The deformation:
  - acts on **top-surface sample heights only**, within a **bounded local radius / falloff** near the shared corner — guideline **last 10–30%** of the relevant edge/sector span, with the influence decaying to zero before mid-edge;
  - **does not** redefine the cliff edge, move its endpoints, or reduce its gap along the rest of the edge;
  - leaves **most of the cliff edge** visually and geometrically a cliff.
- **This is a visual/top-surface resolution rule, not a gameplay rule.** Gameplay continues to read tags/elevation and the resolved transition graph (see [MAP_MODEL.md](MAP_MODEL.md)); the deformation never changes which edges are cliffs, movement blocking, or the cliff-edge graph.

Distinction in one line: **rejected** = "corner owns the whole edge"; **accepted** = "edge owns the edge; corner may locally deform nearby surface samples."

### 9.5 Cliff gap remains elevation/edge-defined

- The **cliff-edge graph** (tiles, elevations, delta, domains) is derived from the integer heightfield and resolved transitions, so it stays well-defined, deterministic, and order-independent **regardless of any corner deformation** and even if two smooth surfaces happen to approach each other near a bridged corner.
- Cliff-wall sizing and future rock/cliff prop placement read the **elevation-defined** gap, not the deformed corner geometry, so they always have a non-degenerate edge to work with.

### 9.6 Future implementation notes (not implemented)

- The deformation belongs in the **top-surface height sampler** of the math core (the smooth-domain / analytic kernel), as a bounded corner-proximity term added only at SSC corners; it must remain a pure, deterministic function of `(corner, resolved smooth edges, elevations)`.
- Corner detection should reuse the existing corner-incidence smooth-component primitive (`_smooth_component_at_corner`) to identify SSC corners; SSS/SCC/CCC require no special handling.
- The deformation radius/falloff should be a **single bounded knob** (target last 10–30% of edge/sector), defaulting to off-by-distance so most of each edge is untouched.
- Keep the **smooth-continuity target** and the **cliff-gap definition** as **separate concerns**: continuity may share a corner value among smooth-connected sectors; the cliff gap is always elevation-defined.
- A non-blocking classify-time **lint** may report bridged SSC corners (and both-endpoints-bridged cliff edges) as authoring-ambiguous inputs.

### 9.7 Validation requirements (gating)

- **Approved 7-hex baseline preserved.** The 7-hex prototype is all-smooth with no cliffs and therefore no SSC corners; the deformation must be **inert** there. Any change to the smooth-region corner value must be visually validated against the approved baseline under the existing baseline guardrail before adoption.
- **SSC fixture.** A synthetic SSC map (A = 1, B = 2, C = 4 and the default-rule A = 1, B = 2, C = 3 case) must show: clean smooth meeting near the shared corner, **no** seam, and a cliff that retains its full elevation-defined gap away from the corner.
- **Both-endpoints-bridged fixture.** A map where a cliff edge is bridged at both corners must **retain a non-zero cliff gap** along the edge (no full-edge erasure) and a stable cliff-edge graph entry.
- **Determinism.** Corner deformation must be order-independent and reproducible across runs and across the Blender and future Godot backends.
- **Gameplay neutrality.** Resolved transitions, cliff-edge graph, and movement-blocking semantics must be identical with and without the deformation.

## 10. Shared smooth edge curve

This section is the **design of record** for how resolved **smooth** edges obtain a single canonical boundary curve. See the decision-log entry "Adopt SharedEdgeCurve with symmetric-average boundary snap" in [DECISION_LOG.md](DECISION_LOG.md).

### 10.1 Problem

The current top-surface sampler (`sample_smooth_domain_surface_world`) evaluates height **per tile** using a radial influence kernel that **excludes cliff-neighbors of the sampling tile**. That exclusion set differs between the two tiles sharing a smooth edge, so the surface is not a pure function of world-XY along the shared boundary. Audits show widespread along-edge Z mismatch even after SSC corner fixes.

A **smooth edge** must not be two independently sampled surfaces that happen to match; it must have **one shared edge curve** used by both adjacent tiles.

### 10.2 SharedEdgeCurve (math core)

For every resolved **smooth** edge `(tile_a, tile_b)` the math core builds a `SharedEdgeCurve`:

- **Geometry:** `subdiv + 1` world-XY samples along the shared physical edge (corner `S` → corner `S+1`), keyed by `pos_key`.
- **Interior Z:** symmetric average of both tiles' post-SSC radial samples at each point: `(z_a + z_b) / 2`.
- **Endpoint Z:** pinned to the shared corner value — `ssc.target_z` at SSC corners, otherwise symmetric average of both tile samples at the corner with `at_sector_corner=True`.
- **Cliff edges:** no curve (hard discontinuity unchanged).

Stored on `TerrainModel.shared_edge_curves` and indexed by `shared_edge_z_lookup` for O(1) `shared_edge_z_at(model, pos_key_xy)`.

### 10.3 Consumption (first slice: boundary-row snap)

Backends snap **boundary-row** top-surface vertices (`si + sj == subdiv` on the sector facing the neighbor) to `shared_edge_z_at` when a curve exists. Both tiles write identical Z at shared XY; existing `(pos_key, domain_id)` merge collapses them to one vertex. Cliff-edge boundary rows are **not** snapped (remain split). **No near-edge interior blend band** in this slice.

### 10.4 Invariants

- Smooth-edge boundary samples are **single-valued** by construction.
- Cliff classification, cliff-edge graph, smoothing domains, and SSC deformation are **unchanged**.
- Deterministic, order-independent, consumable by Blender and future Godot backends.
- Approved 7-hex all-smooth baseline: curves equal per-tile radial values (inert/near-inert).

### 10.5 Limitations (continuity vs slope shape)

SharedEdgeCurve and boundary-row snap **solved boundary continuity** (zero smooth-edge mismatch, merged boundary vertices) but **did not reproduce the intended slope shape**. The mesh interior still comes from the per-tile weighted-mean radial kernel (`sample_smooth_domain_surface_world` / `sample_base_radial_height`); only the outermost boundary row is replaced by `shared_edge_z_at()`. Perceived delta-1 slopes therefore remain largely unchanged.

Quantitative gap at a delta-1 edge midpoint (apothem `≈ 0.866 · HEX_RADIUS`, hill radius `2.2 · HEX_RADIUS`):

- **Approved 7-hex single-hill prototype** (`sample_radial_height`, smootherstep): mid-edge height ≈ **69%** of one elevation step above the lower tile base.
- **Current weighted-mean radial kernel** (symmetric two-tile average, no cliff leakage): mid-edge height ≈ **50%** of one step; lower still when additional low neighbors fall inside the `2.2 · HEX_RADIUS` influence window.

The next canonical evolution is the **Mid-Edge Invariant** (§11). It supersedes the earlier design-review recommendation of a **global single-valued radial field** as the **primary visual fix**: a globally unified field removes seams but retains the weighted-mean sag at the midpoint; the mid-edge invariant targets the sag directly.

### 10.6 Deferred

- Near-edge interior blend band (remove one-row slope change near snapped boundaries).
- Optional full interior sampler edge-symmetry migration (superseded as primary visual strategy by §11; may remain useful for continuity-only paths).

## 11. Mid-Edge Invariant (next canonical evolution)

This section is the **design of record** for the next evolution of the canonical terrain surface model. It follows adversarial design reviews (boundary snap vs boundary-conditioned surface; mid-edge invariant falsification). See the decision-log entry "Adopt Mid-Edge Invariant as next canonical terrain evolution" in [DECISION_LOG.md](DECISION_LOG.md). HexPatch realization is specified in **§15–§16**.

### 11.1 Problem statement

Audits after SharedEdgeCurve (§10) confirm:

- deterministic terrain;
- smooth-edge mismatch **zero**;
- SSC continuity passing;
- authoritative cliff graph unchanged.

Visually, many delta-1 smooth slopes still read as **"held back"**: the middle of the slope does not rise naturally toward the higher hex. Continuity was solved; **terrain shape was not**.

The root cause is not primarily corner topology. The **edge midpoint** is the one location on every smooth edge that is free of corner, SSC, and cliff ambiguity. The current model does not treat that cross-section as canonical; instead, mid-edge height **emerges** from a global weighted-mean radial kernel and optional boundary snap (§10), which cannot change interior slope shape.

### 11.2 Mid-Edge Invariant

For every resolved **smooth** edge, the cross-section from

**hex center → edge midpoint**

must follow **exactly** the approved **7-hex single-hill curve** for the corresponding elevation delta (`|Δelevation| · elevation_step`), using the same smootherstep falloff semantics as `sample_radial_height()` in `tools/blender/terrain/generate_terrain_single_patch_pbr_ground_stone_ash_prototype.py` (`HILL_RADIUS = 2.2 · HEX_RADIUS`).

This is a **canonical invariant**, not an approximate target.

**Edge midpoint is unambiguous:** exactly two tiles share the midpoint; no competing corner constraints, no SSC ambiguity, no cliff ambiguity at that point, and no multi-component ambiguity along the median from center to midpoint (for the local two-hex profile).

**Corners are reconciliation zones:** the span from **edge midpoint → corner** may **locally deviate** to satisfy mixed-corner constraints (SSC, per-domain corner semantics, cliff-adjacent topology). Deformation must remain **bounded and local** (consistent with §9 guidelines: influence decaying before mid-edge).

### 11.3 Canonical center heights

Tile **center** heights used for the invariant profile must be **canonical**:

`z_center = elevation · elevation_step`

(not a neighborhood weighted mean). Corner heights for the HexPatch path are pinned in **§15.5** (SSC `target_z`; otherwise the arithmetic mean of incident smooth-component canonical center heights). They are not globally averaged across cliff-separated components for the purpose of the mid-edge profile.

Under the **HexPatch** architecture (§13), this same canonical value is enforced **exactly at the tile center point** via a symmetric interior bubble anchor. That is a **point height constraint only** — it does not imply a flat terrace, zero slope, zero curvature, or a planar tile interior.

### 11.4 Two-problem decomposition

The terrain surface model decomposes into two largely independent problems:

| Part | Span | Role |
|------|------|------|
| **A. Canonical edge profile** | center → edge midpoint | Closed-form 7-hex single-hill curve parameterized by elevation delta; topology-free; identical from both adjacent tiles |
| **B. Corner reconciliation** | edge midpoint → corner | Local patches where SSC, cliff-adjacent, and multi-edge corner constraints are satisfied; free corner scalars |

**Philosophy shift:**

- **Previous model (§3, §9, §10):** corner / domain constraints → edge behaviour emerges from global or per-tile radial sampling (+ boundary snap).
- **Proposed model:** canonical edge-midpoint profile by construction → corner reconciliation only where necessary.

This **reduces SSC special-casing**: SSC and mixed-corner logic belong entirely in **B**; the mid-edge in **A** is structurally independent of SSC and cannot be pulled down by corner deformation on short smooth edges.

### 11.5 Relationship to §9 (SSC) and §10 (SharedEdgeCurve)

- **§9 SSC deformation** remains valid for **corner reconciliation (B)** only. It must not redefine mid-edge heights in **A**.
- **§10 SharedEdgeCurve** remains the continuity mechanism for the **current implementation slice**. Under the mid-edge invariant, both tiles evaluate identical heights along center → midpoint by construction; SharedEdgeCurve becomes a **verification artifact** (or redundant) on pure smooth edges rather than the primary surface generator. Boundary-row snap alone is insufficient for shape (§10.5).
- **§12 Smooth Ribbon G1 gate** completes the smooth-edge interface: **`h_mid` from §11 is preserved**; **cross-edge G1** is achieved by a **shared tangent `m = S_low`**, not by moving the midpoint to 0.5. See §12 for the theorem, gate decision, and first-slice validation.

### 11.6 Superseded design direction

The **Mid-Edge Invariant supersedes** the earlier design-review recommendation of a **global single-valued radial field** as the **primary visual fix**:

- Global single-valued field: removes per-tile seam disagreement; **does not** fix midpoint sag if the field remains a multi-tile weighted mean.
- Mid-Edge Invariant: fixes midpoint sag **by construction** (local two-hex canonical profile) and inherits seam-free mid-edge behaviour because both tiles share the same profile on the shared median.

### 11.7 Falsification summary (design review)

Adversarial review attempted to disprove the invariant:

- **Well-foundedness** requires local two-hex profile definition and canonical centers (§11.3); the current global `2.2 · HEX_RADIUS` weighted mean violates the literal invariant via neighborhood leakage.
- **Corner reconciliation (B)** is always solvable in **C0** for scalar height fields when corner vertices are free scalars and midpoints are fixed; no valid counterexample was found that prevents smooth reconciliation while preserving **A**.
- Residual **quality** risks (not blockers): full 2-D field may not be globally **C1**; sharp delta contrasts at corners produce high-curvature patches — both confined to reconciliation zones **B**.

### 11.8 Validation requirements (gating — not yet implemented)

Any future implementation of §11 must satisfy:

1. **Midpoint profile parity.** On every smooth edge, center → edge-midpoint cross-section matches the approved 7-hex single-hill curve for that edge's elevation delta (within numerical epsilon), including delta-1 cases that currently sag.
2. **Smooth-edge continuity.** Smooth-edge mismatch audit remains **zero** (no regression from §10).
3. **SSC continuity.** SSC corner continuity audit remains **passing** (20/20 on full-map fixture).
4. **Corner reconciliation locality.** SSC / mixed-corner deformation affects only reconciliation zones **B** (midpoint → corner); mid-edge samples in **A** are invariant under SSC.
5. **7-hex baseline preserved.** The approved 7-hex all-smooth prototype remains visually preserved (no cliffs, no SSC; canonical profile **A** is inert and matches the existing gold standard).
6. **Smooth-edge G1 (§12).** When ribbons are implemented, cross-edge tangents at smooth interfaces match between adjacent tiles; midpoint height remains at `ρ ≈ 0.69357 · Δ`, not 0.5.

Determinism, cliff-edge graph authority, edge classification, and gameplay neutrality constraints from §8–§9 remain unchanged.

### 11.9 Future implementation notes (not implemented)

- Replace or augment the interior height sampler so sector medians from center to edge midpoint use the canonical profile **A**; fill corner wedges with reconciliation **B** (Coons/transfinite or equivalent piecewise construction).
- Retire dependence on boundary-row snap for shape on smooth edges once **A** is enforced in the interior sampler; keep audits from §10 as regression checks until redundant.
- Do **not** implement §11 in the same slice as unrelated material, JSON, cliff-graph, or edge-classification changes.

## 12. Smooth ribbon edge invariant (G1 gate)

This section is the **design of record** for the smooth-edge **interface** under the shared Hermite ribbon + HexPatch side-blend transfinite operator (§15). It resolves the **G1 vs 0.69357 midpoint gate** identified after adversarial review of cross-edge slope continuity. See the decision-log entry "Adopt Smooth Ribbon G1 gate (preserve 0.69357 midpoint, share tangent)" in [DECISION_LOG.md](DECISION_LOG.md).

### 12.1 Smooth-edge ribbon invariant

Every resolved **smooth** edge owns one **shared Hermite ribbon** used identically by both adjacent tiles:

| Datum | Definition |
|-------|------------|
| **Interface height** `h_mid` | `h_mid = z_low + ρ · Δ`, where `ρ ≈ 0.69357` (`canonical_rise_at_edge_midpoint` / approved 7-hex single-hill midpoint fraction), `Δ = \|z_high − z_low\|` in world height, and centers are **canonical** (`elevation · elevation_step`, §11.3). |
| **Cross-edge tangent** `m` | Shared scalar magnitude `S_low` at the edge midpoint, normal to the edge in the cross-section plane (see §12.4). |
| **Usage** | Both adjacent tiles must evaluate the **same** `h_mid` and the **same magnitude** `|m| = S_low`. Each tile applies **opposite-signed** cross-edge derivative at the midpoint: `d_m = ε_T · S_low` where `ε_T = +1` on the higher tile, `−1` on the lower, `0` when `Δ = 0` (§15.8). This yields continuous cross-edge slope (G1). |

This is the new smooth-edge **interface invariant**: one height + one tangent per smooth edge, not two independent half-profiles.

Cliff edges do **not** share a ribbon; each tile owns a private lip curve and inward roll-off tangent (cliff discontinuity unchanged).

### 12.2 Theorem — height continuity alone is insufficient for G1

Consider the one-dimensional two-tile cross-section along the center-to-center line. Let tile centers sit at elevations `z_0` and `z_1 = z_0 + Δ`, with **zero slope at both centers** (canonical flat dome tops). The shared edge midpoint is at arc length `a` (hex apothem) from each center.

If each tile uses the **same canonical half-profile** `P(u)` (approved smootherstep 7-hex rise) to reach interface height `h_mid = z_0 + ρ · Δ`:

- **Low side** slope at midpoint: `S_low = (ρ · Δ / a) · P'(1)`.
- **High side** slope at midpoint: `S_high = ((1 − ρ) · Δ / a) · P'(1)`.

Both sides agree on height at the midpoint (**C0**) but their tangents differ by the ratio:

`S_low / S_high = ρ / (1 − ρ)`.

At `ρ ≈ 0.69357` this ratio is **≈ 2.26**. Therefore, with fixed zero-slope centers and identical canonical half-profiles on both sides, **G1 across the shared midpoint requires `ρ = 0.5`**. The canonical 7-hex midpoint fraction **0.69357 is incompatible with G1** under those assumptions alone.

**Conclusion:** height continuity at `h_mid` is necessary but **not sufficient**; cross-edge **G1** requires an explicit, **shared** tangent datum in addition to `h_mid`.

### 12.3 Gate decision

**Do not replace 0.69357 with 0.5.** Moving the midpoint to the symmetric average would restore G1 under left–right symmetry but would discard the approved 7-hex low-side rise and reintroduce the "held back" delta-1 slope complaint that motivated §11.

**Preserve the 7-hex low-side canonical profile.** The low tile's center→midpoint cross-section must remain the approved single-hill curve.

**Gain G1 by sharing the cross-edge tangent magnitude, not by moving the midpoint.** Keep `h_mid = z_low + 0.69357 · Δ` as a **hard invariant**; add and share `|m| = S_low`; each tile consumes `d_m = ε_T · S_low` with opposite sign (§15.8).

**Rejected alternatives (gate review):**

- **A. Hard 0.69357, no shared tangent:** preserves both half-profiles but leaves a guaranteed slope kink (≈2.26× mismatch); reproduces the observed cross-edge profile asymmetry.
- **B. G1-consistent ribbon with preserved midpoint (chosen):** see §12.1 and §12.4.
- **C. Hybrid (0.69357 only for isolated gold-standard tests):** unnecessary branching; option B already preserves the low-side canonical profile exactly on real multi-tile terrain.

### 12.4 Chosen shared tangent

`m = S_low = (ρ · Δ / a) · P'(1)`

where:

- `ρ ≈ 0.69357` is the canonical midpoint rise fraction;
- `a` is the hex apothem (`√3/2 · HEX_RADIUS`);
- `P` is the approved smootherstep profile used by the 7-hex single-hill prototype (`HILL_RADIUS = 2.2 · HEX_RADIUS` semantics).

**Effect:** the **low (rising) tile** reproduces its canonical center→midpoint profile **exactly** at the interface; the **high tile** rolls into the same shared slope magnitude via `d_m = +S_low` (low tile: `d_m = −S_low`).

**Per-tile sign:** shared ribbon stores the magnitude `m = S_low`; the quadratic `d(t)` is built with unsigned endpoint normals; at evaluation each tile applies `d_m = ε_T · S_low` (§15.6, §15.8).

**C2 is not enforced.** A high-side curvature adjustment near the edge is accepted; only **C0 + G1** at the smooth interface are required.

For `Δ = 0` (equal elevations), `h_mid` and `m` collapse to flat; the edge remains trivially G1.

### 12.5 Scope

This is a **terrain-surface mathematics decision only.**

**Unchanged:** gameplay, cliff-edge graph authority, edge classification, JSON/map IR, materials, and Godot/server behaviour.

**In scope for future implementation:** shared ribbon data on smooth edges, HexPatch side-blend transfinite interior (§15), and audits for G1 + §11 midpoint preservation. See **§16** for the construction pipeline.

**Out of scope for this gate:** replacing the six-sector fan with the hex patch (separate architecture slice), cliff lip/wall geometry details beyond "unshared ribbon," and any global field solve (harmonic / TPS / RBF).

### 12.6 Relationship to §11

§11 fixes **what height** the smooth edge midpoint must have (`h_mid` canonical). §12 fixes **what slope** both tiles must share at that point (`m = S_low`). §13 fixes **what height** the tile center must have (`z_center` canonical) on the HexPatch interior. Together, ribbons + corner jets + center bubble define the transfinite hex patch boundary/interior data. Corner reconciliation (§11 part B, §9 SSC) remains separate and local.

### 12.7 Future implementation gate (first slice)

The first implementation slice that adopts §12 must add:

1. **Shared ribbon tangent data** — store `m` alongside `h_mid` on every smooth edge; both tiles consume the same pair.
2. **G1 audit** — compare cross-edge slopes sampled from tile A and tile B at shared edge points; require agreement within numerical epsilon.
3. **Regression: smooth-edge mismatch remains 0** — C0 height continuity (§10 / §11) must not regress.
4. **Regression: low-side profile matches canonical 7-hex curve** — center→midpoint on the rising tile matches the approved prototype within epsilon.
5. **Monotonic / no-overshoot check on the high side** — high-tile half-profile stays within `[z_low, z_high]` without bumps.
6. **Flat delta-0 remains flat** — symmetric equal-elevation smooth edges stay flat and G1.
7. **SSC / cliff-adjacent falsification** — mixed-corner and cliff-next-to-smooth fixtures still pass **C0** and **G1** wherever the edge is smooth; cliff edges remain discontinuous.

Determinism, order-independence, and Godot-portable closed-form evaluation remain mandatory (§8).

Do **not** combine this slice with unrelated material, JSON, cliff-graph, or edge-classification changes.

## 13. HexPatch center bubble anchor

This section is the **design of record** for how the **sectorless HexPatch** (shared Hermite ribbons + side-blend transfinite interior, §15) honors the canonical tile center height from §11.3. It revises the interim HexPatch architecture decision that treated the center as fully emergent. See the decision-log entry "Adopt HexPatch center bubble anchor (fixed center height only)" in [DECISION_LOG.md](DECISION_LOG.md). The bubble basis `β(x)` is pinned in **§15.8**.

### 13.1 Revised center invariant

Every tile center is fixed to the **canonical elevation height**:

`z_center = elevation · elevation_step`

This is a **point constraint only**. It does **not** imply:

- a flat terrace across the tile;
- zero slope at the center;
- zero curvature at the center;
- a planar tile interior.

The surface may pass through the center with **any tangent and curvature** required by the surrounding boundary conditions (SharedCorner jets, SharedRibbon data). The center is the geometric manifestation of the authoritative gameplay elevation sample; the domain integer elevation remains authoritative for rules, and mesh Z is presentation.

### 13.2 Bubble anchor formulation

The clean boundary-driven HexPatch height field `S_patch(x)` is augmented by **one symmetric interior bubble basis**:

`S_final(x) = S_patch(x) + Δz · β(x)`

where:

| Condition | Meaning |
|-----------|---------|
| `Δz = z_center_canonical − S_patch(center)` | correction magnitude from audited drift |
| `β(center) = 1` | pins center height exactly |
| `β = 0` on the hex boundary | boundary height values unchanged |
| `∇β = 0` on the hex boundary | boundary cross-edge derivatives unchanged |
| `∇β(center) = 0` | center tangent inherited from `S_patch`, not zeroed |

**Consequences:**

- center height is **exact** at `z_center`;
- boundary ribbons are **untouched**;
- edge **G1** (§12) is **preserved**;
- SharedCorner jets are **preserved**;
- center **tangent** is inherited from the patch (not forced flat);
- no **sector/spoke** artifact is introduced (β is sectorless and symmetric).

This is a **rank-one augmentation**, not a consumed interior degree of freedom: the pure boundary transfinite patch has no free interior DOF; the bubble adds one interpolation condition without altering the boundary value problem.

### 13.3 Why this replaces the previous emergent-center lock

An earlier HexPatch architecture review recommended a **fully emergent** center (patch output only, with drift audit). The objection to **hard center pinning** in that review applied to the **old six-sector fan model**, where pinning the fan vertex and blending out per sector reintroduced visible spokes.

In the **new sectorless HexPatch**, a **symmetric bubble anchor** does not depend on sector numbering and cannot create spokes. Fixing **height only** (not slope or curvature) is therefore compatible with a fully smooth surface and with SharedRibbon / corner-jet boundary data.

### 13.4 Guardrails

The bubble must **not** become a rescue tool for bad boundary data.

- **Drift audit (before correction):** report max/mean `|S_patch(center) − z_center_canonical|` across the map.
- **Threshold / lint:** if drift exceeds a chosen threshold, **warn/lint** rather than silently allowing a huge correction; consider a bounded magnitude cap on `|Δz · β|`.
- **Future overrides:** features such as rivers may **deliberately override or modify** the center anchor when authored; the default anchor is not inviolable against future feature data.

Asset placement (foundations, skirts, local normals) must **not** drive this mathematical model; presentation adapts to the surface.

### 13.5 Scope

Terrain-surface mathematics only.

**Unchanged:** JSON/map IR, cliff-edge graph, edge classification, gameplay rules, materials, Godot/server behaviour.

**Pinned (§15.8):** bubble basis `β(x) = ∏_i S(h_i/a)` with `S(u)=6u⁵−15u⁴+10u³`; drift audit, threshold lint, and verification that boundary reproduction is unchanged remain mandatory at implementation.

### 13.6 Future implementation gate

Any implementation slice adopting §13 must verify:

1. **Center exact after bubble** — `S_final(center) = z_center` within numerical epsilon.
2. **Boundary unchanged** — boundary height values and normal (cross-edge) derivatives match pre-bubble `S_patch` on all six edges.
3. **Smooth-edge mismatch remains 0** — C0 regression (§10 / §11).
4. **G1 ribbon audit passing** — cross-edge tangent agreement (§12).
5. **No-spoke probe clean** — radial / barycentric probes through the center show no derivative discontinuity aligned with former sector boundaries.
6. **Drift audit reported before correction** — max/mean center drift logged; threshold violations surfaced.

Determinism, order-independence, and Godot-portable closed-form evaluation remain mandatory (§8).

Do **not** combine this slice with unrelated material, JSON, cliff-graph, or edge-classification changes.

## 14. HexPatch interior operator — IDW Hermite patch falsification

This section records the **falsification / supersession** of the first HexPatch prototype's **inverse-distance Hermite transfinite blend** as the canonical patch operator. See the decision-log entry "Reject IDW Hermite HexPatch operator (falsification)" in [DECISION_LOG.md](DECISION_LOG.md). **No further tuning or extension of the IDW operator is authorized.**

### 14.1 Context

The first HexPatch implementation slice (SharedCorner + SharedRibbon + center bubble, legacy sector path retained) used an **inverse-distance Hermite transfinite blend** (Shepard-style weights `w_e = 1 / d_e²` over the six edges, with boundary values `b_e(t)` and cross-edge derivatives `d_e(t)` bolted together) as a **temporary slice-1 substitute** for the locked **HexPatch side-blend transfinite operator** (§15).

That operator is now **rejected** as the canonical patch interior. SharedCorner, SharedRibbon, and the §13 center bubble anchor remain valid; only the **interior blend operator** is superseded.

### 14.2 Objective evidence (168-tile handdrawn map)

On `handdrawn_test_map_full_01` (168 tiles, 374 smooth / 78 cliff edges), mathematical audits reported:

| Audit | Result | Interpretation |
|-------|--------|----------------|
| Smooth-edge height mismatch | ≈ 0 (machine epsilon) | C0 seam values correct |
| G1 ribbon (cross-edge slope) | Passed within tolerance (ε = 2×10⁻³; max ≈ 1.93×10⁻³) | First normal derivative at seams acceptable |
| Boundary reproduction | Passed (≈ 0) | Patch equals SharedRibbon `b(t)` on edges |
| Cross-derivative reproduction | Passed within tolerance (max ≈ 1.79×10⁻³) | Normal derivative matches `d(t)` at seams |
| **Center drift before bubble** | **max ≈ 0.74, mean ≈ 0.19; 118 / 168 tiles warned** | Patch interior structurally undershoots canonical center |
| **No-spoke probe** | **Failed: max derivative discontinuity ≈ 0.47** | Interior gradient field still spoke/lobe structured |

Visual regeneration of `terrain_handdrawn_test_map_full_01.blend` (HexPatch path) showed **map-wide, repeating** artifacts despite passing seam audits:

- rounded **"bubble" hills** in tile interiors;
- **edge collars** — narrow depressions / volume loss just before hex borders;
- **"butt-shaped"** edge transitions (rise → bend down → rise) along some shared edges;
- **persistent perceived interior discontinuities** along former sector directions.

These are not isolated fixture failures; they repeat across the map.

### 14.3 Mathematical reason (inherent operator limitation)

Assuming correct SharedCorner / SharedRibbon boundary data, the IDW Hermite blend is **unsuitable** as a terrain patch operator because:

1. **Normalized boundary average.** The value term is a convex combination of edge boundary heights. It cannot reach interior targets above or below the boundary envelope without an external correction.
2. **Dominant bubble required.** The §13 center bubble became the **primary terrain shaper** (drift up to ≈ 0.74 on a map with `elevation_step = 0.4`), violating the §13.4 guardrail that the bubble must not rescue bad boundary-driven patches.
3. **Not linearly / affinely precise.** Shepard interpolation cannot reproduce a tilted plane when boundary data lie on a plane. Local ramps and plateaus warp into rounded bulges between edges.
4. **Singular `1/d²` weights.** Edge influence is sharply localized, producing **edge lobes** and **spoke-like interior influence** (confirmed by the failing no-spoke probe). This is structurally independent of sector numbering but visually similar to the old fan spokes.
5. **Bolted value + derivative terms.** Boundary value and normal derivative are not members of a single Hermite transfinite basis; they are superposed with incompatible turn-on distances near the boundary, producing the observed collar and butt-shaped transitions.

**Conclusion:** Seam-level audits (C0, G1 at the edge line) can pass while the interior shape is wrong. The failing center-drift and no-spoke metrics are the objective signatures of operator unsuitability, not implementation bugs.

### 14.4 Decision

- **Do not tune or extend** the inverse-distance Hermite patch further (no weight-power tweaks, no additional correction layers, no bubble rescaling as a workaround).
- The **canonical interior replacement** is the **HexPatch side-blend transfinite operator** (§15), which satisfies the properties listed above. SharedCorner, SharedRibbon (§12), and the center bubble formulation (§13) are **not** superseded by this falsification.

### 14.5 Separate deferred issues (do not conflate with IDW failure)

The following are **not** explained by IDW rejection and remain tracked separately:

- **Cliff lip placeholder behaviour** — private linear lips with zero cross-derivative; near-vertical lips until corners. Known first-slice deferral, not an IDW artifact.
- **Future refinement of ribbon / corner data** — ribbon profile shape (`h_mid`, smootherstep half-blends), corner gradient least-squares. A correct transfinite patch will expose these cleanly instead of masking them with operator noise.
- **Possible G2 / shading continuity** — even a correct G1 transfinite patch may leave subtle normal-map shading seams until second-derivative matching is addressed.

### 14.6 Future implementation gate (next interior-operator slice)

Any next HexPatch implementation slice must **replace** the IDW patch operator, not tune it. The **authoritative gate** for the side-blend operator is **§15.10** (supersedes this list for v1.0). Historical first-slice requirements included:

1. **Affine / plane reproduction audit** — patch equals a tilted plane when all six edges lie on that plane.
2. **No-spoke audit** — interior derivative probes show no discontinuity along former sector directions (must pass, not merely report).
3. **Center drift audit before bubble** — max/mean `|S_patch(center) − z_center|`; drift must be small enough that the bubble is an anchor, not the primary shaper (§13.4).
4. **Boundary value reproduction** — patch on each smooth edge equals SharedRibbon `b(t)`.
5. **Cross-derivative reproduction** — finite-difference normal derivative equals `d(t)`.
6. **G1 ribbon audit** — cross-edge slope from both tiles agrees within epsilon.
7. **Visual regeneration** — `terrain_handdrawn_test_map_full_01.blend` via the HexPatch path; visual-risk notes reported.

Regression: smooth-edge height mismatch **0**; smooth/cliff counts unchanged; SSC continuity passing; cliff edges remain discontinuous.

Determinism, order-independence, and Godot-portable closed-form evaluation remain mandatory (§8).

Do **not** combine this slice with unrelated material, JSON, cliff-graph, or edge-classification changes.

## 15. Canonical HexPatch Mathematics v1.0

This section is the **frozen mathematical and implementation specification** for the HexPatch smooth surface core. It supersedes any earlier "free" or deferred wording for `g_V`, non-SSC `c_V`, `d(t)`, and `β`. See the decision-log entry "Freeze HexPatch Mathematics v1.0" in [DECISION_LOG.md](DECISION_LOG.md).

### 15.1 Scope — HexPatch Mathematics v1.0

- **In scope (implementation-complete):** SharedCorner, SharedRibbon, the **HexPatch side-blend transfinite operator**, center bubble, surface evaluation, and all smooth-edge / smooth-corner invariants **H1–H10** on tiles whose edges are smooth or consume cliff lips through the fixed interface below.
- **Deferred to Cliff Model v1:** cliff-lip interior `b_lip(t), d_lip(t)` on `(0,1)` and cliff-wall geometry. HexPatch **consumes** cliff edges only through the fixed `(b_e, d_e)` interface with **§15.7** endpoint rules; it does not define lip interiors.
- **Operator name:** the canonical operator is the **HexPatch side-blend transfinite operator** (Gregory / Kós–Várady squared-distance side blends). Do **not** call it "Wachspress-Hermite": Wachspress vertex coordinates `λ_i` (§15.3 note) are reference-only and do not appear in `S_patch`.

### 15.2 HexPatch side-blend transfinite operator

On the closed regular hexagon `H`, with affine signed edge distances `h_i(x) = a + x·n_i` and orthogonal-projection edge parameters `s_i(x)` (§15.3):

- Side weights: `D_i = ∏_{j≠i} h_j²`,  `Φ_i = D_i / Σ_k D_k`.
- Ribbon field per edge: `R_i(x) = b_i(s_i) + h_i(x) · d_i(s_i)` (per-tile signed `d_i`, §15.8).
- Pre-anchor patch: `S_patch(x) = Σ_{i=0}^{5} Φ_i(x) · R_i(x)` (canonical edge order `0..5`).
- Final surface (§13): `S_final(x) = S_patch(x) + Δz · β(x)`, `Δz = z_center − S_patch(center)`, `β` pinned in §15.8.

Properties: exact ribbon value and cross-derivative on open edges (H1, H2); operator-level affine precision (H6); gradient continuity on open hexagon (H7); bounded non-singular evaluation (H8); deterministic local closed form (H9).

### 15.3 Domain, notation, and parameter naming

- **Hexagon:** center `c`, circumradius `R`, apothem `a = (√3/2)·R`; corners `V_0…V_5` CCW (baseline `corner_xy_local` order); edge `e_i` joins `V_i → V_{i+1}`; unit inward normal `n_i`, tangent `t_i`, edge length `ℓ`.
- **Edge parameter (unified):** the along-edge parameter is **`t ∈ [0,1]`** from corner `V_i` to `V_{i+1}`. In the operator, **`s_i(x)`** is the orthogonal projection parameter (§15.2); on the boundary `s_i = t`. Ribbon functions `b(t)` and `d(t)` are evaluated at `t = s_i(x)` by **analytic extension** (no clamping). Older symbols `τ` and `P_i(τ)` mean the same boundary parameterization.
- **Wachspress reference (not used in operator):** `λ_i = ω_i / Σω_k`, `ω_i = ∏_{j∉{i−1,i}} h_j`; affine-precise on convex polygons; included for provenance only.

### 15.4 SharedCorner gradient `g_V` (O1)

For each physical corner `V` and smooth component `K` (tiles incident to `V` connected through smooth edges only):

Centered samples: `p̄, z̄` = mean of incident tile centers/heights; `q_i = p_i − p̄`, `ζ_i = z_i − z̄`; `M = Σ q_i q_iᵀ`, `b = Σ ζ_i q_i`.

**Definition:** `g_V = M⁺ b` (Moore–Penrose pseudoinverse; rank threshold §15.9).

**May read:** incident component tile center positions and canonical heights; component membership; SSC `target_z` for height only (§15.5).

**May not read:** any ribbon datum, any ribbon endpoint slope, any other corner gradient, any global field.

Affine consistency: if heights lie on an affine plane and `rank M = 2`, then `g_V = ∇A` exactly.

### 15.5 SharedCorner height `c_V` (F2)

For each `(V, K)`:

- **SSC corners:** `c_V = target_z` (§9).
- **All other (non-SSC) components:** `c_V = (1/|K|) Σ_{T∈K} z_T` (arithmetic mean of incident smooth-component canonical center heights).

Component-scoped; no averaging across cliff-separated components. Singleton component ⇒ `c_V = z_T`.

### 15.6 SharedRibbon `b(t)` and `d(t)`

**Value curve `b(t)` — unique minimal quartic** through:

- `b(0) = c_{V0}`, `b(1) = c_{V1}`
- `b'(0) = ℓ · (t_e · g_{V0})`, `b'(1) = ℓ · (t_e · g_{V1})` (**parameter-derivative** slopes; `σ = t·g` is world along-edge slope)
- `b(½) = h_mid = z_low + ρ · Δ` (§11, §12)

**Cross-edge derivative `d(t)` — unique quadratic** through:

- `d(0) = n_e · g_{V0}`, `d(1) = n_e · g_{V1}`
- `d(½) = d_m` with per-tile sign applied at consumption (§15.8)

Formula: `d(t) = 2(t−½)(t−1)·d₀ + 4t(1−t)·d_m + 2t(t−½)·d₁`.

Units: `d(t)` is world normal derivative `∂z/∂n` (height per world length); used directly in `R_i = b_i + h_i · d_i`.

**Authoritative formulas (not rounded literals):** `κ = a/HILL_RADIUS`, `ρ = 1 − S(κ)`, `S(u)=6u⁵−15u⁴+10u³`; `S_low = (ρ·Δ/a)·|P'(1)|`, `P'(1) = −κ·S'(κ)`, `S'(v)=30v²(v−1)²`; shared magnitude `m = S_low` (§12.4).

### 15.7 Cliff interface (O2 / deferred interior)

Private cliff lip per tile, same interface as a ribbon `(b_e, d_e)`.

**Endpoint rules** at corner `V` on a smooth component:

- `b_lip(V) = c_V`
- Tangential endpoint slope: `σ_lip = t_γ · g_V` (parameter derivative `b'(0)=ℓ·σ_lip`)
- Normal endpoint: `d_lip(V) = n_γ · g_V`

**Cliff-only (singleton) corners:** `g_V = 0` ⇒ endpoint slopes `0`; endpoint value = tile's own corner height.

**Deferred:** interior `b_lip, d_lip` on `(0,1)` → Cliff Model v1. Cross-cliff discontinuity preserved (H10): independent lips, no shared ribbon.

### 15.8 Center bubble `β` and implementation conventions

**Bubble (pinned):** `β(x) = ∏_{i=0}^{5} S(h_i(x)/a)` with `S(u)=6u⁵−15u⁴+10u³`. Satisfies §13.2 (`β(c)=1`, `β=∇β=0` on `∂H`, `∇β(c)=0`).

**Cross-edge sign (per tile `T` on edge `e`):** `ε_T = +1` if `z_T > z_neighbor`, `−1` if lower, `0` if equal; `d_m = ε_T · S_low`.

**Vertex evaluation:** if `|x − V| ≤ 10⁻⁶ · R`, return height `c_V` (corner limit); do not evaluate the rational operator form.

**Orientation / indexing:** corners CCW `V_0…V_5`; edges `e_i`; physical-edge↔neighbor-direction via baseline map; summation order `i = 0..5`.

**Numerical tolerances (default audit parameters):**

- Pseudoinverse: singular value zero if `≤ 10⁻⁹ · σ_max`
- Analytic derivative audits: residual `≤ 10⁻⁹` (relative to `elevation_step`)
- Finite-difference audits (step `δ = 10⁻⁴ · R`): residual `≤ 10⁻³`

**Affine precision scope:** operator-level — feed affine ribbon data ⇒ `S_patch` is that plane; canonical terrain with `ρ ≈ 0.69357` is intentionally non-affine by design (§11).

### 15.9 Hard invariants (HexPatch Contract)

Reference only; proofs in design reviews:

| ID | Invariant |
|----|-----------|
| H1 | Ribbon value reproduction on open edges |
| H2 | Cross-derivative reproduction on open edges |
| H3 | Corner 1-jet reproduction (value + gradient) |
| H4 | G1 across smooth edges |
| H5 | Center value exact after bubble |
| H6 | Operator-level affine precision |
| H7 | No-spoke / gradient continuity on open hexagon |
| H8 | Boundedness, no singular weights |
| H9 | Deterministic local evaluation |
| H10 | Cliff discontinuity preserved |

**Intentionally free (do not affect H1–H10):** G2 / cross-edge curvature; cliff-lip interior (Cliff Model v1); interior curvature shape beyond pinned blends.

### 15.10 Release gate (future implementation)

Any HexPatch v1.0 implementation must verify, in order:

1. SharedCorner construction (locality, affine fixture on 3-tile corners)
2. SharedRibbon node reproduction (`b`, `d` at `{0, ½, 1}`)
3. HexPatch: H1, H2, H6, H7, H8, H9
4. Bubble: H5; boundary unchanged vs `S_patch`; **pre-bubble center drift** reported (max/mean)
5. Sampling: H4 (G1 cross-edge); H3 at corners including SSC; H10 at cliffs; **smooth-edge height mismatch 0**; **deterministic rebuild** (identical output under fixed order); **visual regeneration** of `terrain_handdrawn_test_map_full_01.blend` with visual-risk notes

Cliff-adjacent interior validation awaits Cliff Model v1.

---

## 16. HexPatch Construction Algorithm

Implementation manual for §15. Assumes TerrainModel inputs exist. No proofs; reference §15 for formulas.

### Stage 0 — TerrainModel (prerequisite)

Read-only: canonical tile elevations `z_T`; cliff/smooth edge classification; lattice geometry (centers, corners, edges, `a`, `ℓ`, `n_e`, `t_e`); neighbor topology. No surface construction.

### Stage 1 — Smooth components

Partition tiles at each physical corner by connectivity through smooth edges only. Output: `(corner_world, component_tiles)` keys; deterministic order (corners by world key, components by sorted tile tuple).

### Stage 2 — SharedCorner

**Inputs:** Stage 1 components; tile centers/heights; SSC `target_z`. **No ribbon data.**

Build per `(V,K)`: `c_V` (§15.5), `g_V` (§15.4). Order: after Stage 1.

### Stage 3 — SharedRibbon

**Inputs:** endpoint SharedCorners; tile-center `Δ`; `S_low` (§15.6 formulas). **No HexPatch.**

Build per smooth edge: quartic `b(t)`, quadratic `d(t)` (§15.6). Ownership: the **edge** (shared). Order: after Stage 2.

### Stage 4 — Cliff interface

**Inputs:** endpoint SharedCorners for lip endpoints (§15.7). Interior from **Cliff Model v1** (deferred). HexPatch consumes `(b_e, d_e)` identically to smooth ribbons.

### Stage 5 — HexPatch assembly

Per tile: six edge interfaces (ribbon or lip + orientation flag + `ε_T`); six corner jets; `z_center`. Immutable object; no sampling; no neighbor HexPatch.

### Stage 6 — Surface evaluation

Input `(x,y)` + owning tile. Vertex rule → `c_V` if within tolerance (§15.8). Else: local coords → `s_i`, `h_i` → oriented `b_i`, `d_i` → `Φ_i`, `R_i` → `S_patch` → `β`, `Δz` → `S_final`.

### Stage 7 — Mesh sampling interface

Sample `S_final` at arbitrary locations; normals from analytic gradient or FD; shared corners return one value. Tessellation not specified.

### Stage 8 — Validation

Sequence per §15.10; reference H1–H10 at each stage.

### Dependency graph (acyclic)

`TerrainModel → SmoothComponents → SharedCorner → {SharedRibbon, CliffInterface} → HexPatchAssembly → SurfaceEvaluation → MeshSampling → Validation`. Cliff Model v1 feeds Stage 4 only. No cycles; SharedCorner never reads ribbons; HexPatch never reads neighbors.

**TerrainSolver framework (TS-01):** §15–§16 describe the **HexPatch v1 reference backend** — one implementation path behind the shared `TerrainSolver` interface (`tools/blender/terrain/eom_terrain_solver.py`). Global fair-surface optimization backends are the forward path for the canonical terrain model; HexPatch v1 remains available for diagnostic comparison against IDW and future global solvers on the established large map benchmark.

---

## 17. Global terrain surface — current research direction (active, not finalized)

Status: **active research direction**, not a finalized terrain algorithm. This section records the mathematical requirements that emerged from the HexPatch and GlobalBiharmonic investigations and the family currently preferred for the next prototype. It selects a **research family only** — not a specific formulation, discretization, or implementation. See the decision-log entry "select variational spline family as current research direction" in [DECISION_LOG.md](DECISION_LOG.md).

### 17.1 Required invariance properties

Any future global terrain solver must satisfy all of the following:

1. **Constant precision.** If every tile elevation increases by a constant `C`, the reconstructed terrain increases everywhere by `C` with identical shape.
2. **Linear precision.** If all tile elevations lie on a plane `z = ax + by + c`, the reconstructed terrain reproduces that plane exactly — no bowing toward a flat sheet.
3. **No implicit rest elevation.** The objective contains no hidden preference for a constant-height reference surface or mean elevation. The terrain is determined entirely by exact tile-center elevations, cliff topology, smooth connectivity, and a fairness objective.

Additional standing requirements: **exact interpolation** of tile-center elevations, a **global fairness objective**, and **natural handling of the disconnected smooth components** created by cliffs (no coupling across cliff edges).

### 17.2 Why affine precision matters

Terrain that reads as a global landscape must not invent features that the data does not imply. Constant precision guarantees the model has no absolute zero plane; linear precision guarantees a uniform regional slope is reproduced rather than flattened. A method without linear precision treats a tilted region as "non-fair," spends spurious energy resisting it, and relaxes toward a flat reference sheet — exactly the artifact observed. Affine precision is therefore a hard correctness gate, not a quality preference.

### 17.3 Why the graph-Laplacian formulation failed

The GlobalBiharmonic prototype (TS-02) minimized a tensioned-biharmonic energy discretized with a **random-walk / combinatorial graph Laplacian**. That operator's nullspace is `{constants}` only: it reproduces constants (constant precision holds) but **lacks linear precision** — planes are not in its nullspace at boundary and irregular vertices, so planar data carries spurious energy and the surface bows toward a flat sheet. The membrane (tension) component additionally behaves like a 2D point-load response with `log r` cusps at the pinned centers. The result — a flat reference sheet pulled into local spikes — is the **expected** output of that discrete operator. The failure is the **discrete operator (missing linear precision) plus the membrane term**, **not** evidence that point-center constraints are fundamentally insufficient.

### 17.4 Why the spline family is currently preferred

The **Thin-Plate / Polyharmonic Spline family with a polynomial tail** is **currently the strongest known candidate family satisfying the required invariance properties** (not the only correct solution). It provides exact interpolation, exact affine precision (the polynomial tail carries constants and planes), a pure bending-energy fairness objective with no implicit rest elevation, and clean per-component handling of cliffs (one spline per smooth-connected component; no cross-cliff coupling). Related and adjacent methods:

- **Universal kriging with a thin-plate (intrinsic) covariance** is mathematically very closely related and reduces to the same interpolant; not a separate destination.
- **FEM thin-plate with a cotangent/FEM Laplacian** is **not a competing idea** but a future discretization / evolution path within the same variational problem — advantageous once mesh-based solving or larger-scale **area/edge constraints** (e.g. flat plateaus, explicit smooth-edge ramps) become desirable.
- **Moving Least Squares** and **Natural Neighbour** interpolation remain valuable **secondary techniques** for editing, previews, or local reconstruction, but are not the current primary direction.

### 17.5 Why this remains an active research direction

This selects only the **research family** in the chain **research family → specific mathematical formulation → numerical discretization → implementation**. Current evidence is sufficient to prioritize this family for the next prototype, but not to finalize the terrain algorithm. Open questions deferred to future slices include: the specific spline formulation and kernel; a tension/regularization term to curb overshoot while preserving affine precision; whether crisp flat tile-tops are desired (which would add area/edge constraints, more naturally expressed in the FEM discretization); the treatment of small cliff-isolated components (a single-elevation component reduces to a flat top); and the numerical discretization and solver. The canonical 168-tile map remains the primary benchmark; no new evaluation maps.
