# Empire of Minds — Canonical terrain model (planning)

Status: **planning / design-of-record**. This document defines the canonical mathematical model for Empire of Minds 3D terrain generation. It is the source of truth for future implementation; **no implementation is described here as done**. It does not change gameplay, the domain `HexMap` (tag-only; see [MAP_MODEL.md](MAP_MODEL.md)), or any Godot code.

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
- **C0, not C1 continuity.** The analytic model matches heights at shared corners/edges but not slopes; slope kinks at hex/sector boundaries can read as facets on busy maps. This is inherent to the canonical model; any future global smoothing is a separate, explicit baseline-revision decision under the baseline guardrail.
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
