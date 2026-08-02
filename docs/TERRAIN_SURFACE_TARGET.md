# Terrain Surface Target — Cut-Domain Thin-Plate Model

## Status

This document defines the **canonical mathematical target** for Empire of Minds terrain surface generation.

It is a **design target**, not an implementation report. Nothing in this document is implemented by the document itself.

**Implementation status (2026-08):** the validation stages below are implemented in Blender as the accepted **TS-08 reference chain** (`tools/blender/terrain/`, Stage 0 cut-lattice audit, Stage 1 no-cut CG, Stage 2 cut-domain CG, Stage 3a walls + stone material; see [TERRAIN_MODEL.md](TERRAIN_MODEL.md) "Current canonical model"). **Slice N2** exports a deterministic Stage-2 **derived reference golden** to `content/terrain/reference/handdrawn_test_map_full_01_ts08_stage2_reference_v1.json` for parity testing and audit (not the production terrain source; does not replace the solver). The authoritative terrain input remains the canonical 2D logical map + height-level grid. The approved production path is Godot-native terrain **generated** from that grid by a TS-08-equivalent solver (N3+); see the "Fixed-grid Godot 3D terrain parity" milestone in [PHASE_PLAN.md](PHASE_PLAN.md). This document remains the mathematical target both solver implementations are judged against.

Where this formulation conflicts with any ad-hoc terrain solver experiment (past or future), **this document supersedes the experiment**. Experiments are judged against this target; the target is only revised by editing this document deliberately and reviewably.

Source: two read-only planning/audit passes performed in-session:

1. *Mathematical Audit — Terrain Surface with Internal Cliff Cuts*
2. *Audit — Minimum-Gradient Gauge Convention for Deficient Cut Components*

## Purpose

Terrain solver work in this repo previously iterated blindly: each failed prototype was patched with new constraints, bands, or clustering, without an explicit mathematical goal to check against. This document exists so future solver work can be judged against a stable target. When an experiment fails, the question becomes decidable:

1. Is the implementation wrong (deviates from this target)?
2. Or is the mathematical target itself wrong (in which case this document is revised first, explicitly)?

## Core target

> Find the minimum-bending-energy surface over the map domain cut along all authoritative cliff edges, interpolating the exact hex-center elevations, with free natural boundary conditions on both the outer map boundary and all internal cut boundaries.

The goal is **not** a continuous ramp across cliffs. The goal is a smooth terrain surface that is topologically cut along authoritative cliff edges: the upper and lower terrain sheets are separate at cliffs, and the gap is later filled by presentation-only cliff assets or wall geometry.

## Mathematical formulation

```
Data:    Ω ⊂ R² (union of hex footprints), hexes H with centers c_h and integer levels e_h,
         elevation scale s = elevation_step, base b = elevation_base,
         Γ = { shared hex edges with |e_i − e_j| > 1 }   (cliff_threshold = 1).

Domain:  Ω_cut := completion of (Ω \ Γ) under the intrinsic path metric.

Find:    z ∈ H²(Ω_cut) minimizing

             E[z] = ∫_{Ω_cut} ( z_xx² + 2 z_xy² + z_yy² ) dA

Subject: z(c_h) = (e_h − b) · s   for every h ∈ H   (hard interpolation).

BCs:     none imposed — free (natural) conditions arise variationally on the outer
         boundary and on every cut face (vanishing bending moment and Kirchhoff shear).

Unique:  provided every connected component of Ω_cut contains ≥ 3 non-collinear centers;
         deficient components are handled by the gauge convention below.
```

Definitions:

- **Ω** — the 2D map domain in the XY plane: the union of all terrain hex footprints in the current patch/map.
- **H** — the set of hexes. Each hex h has a center point c_h ∈ Ω and an authoritative discrete integer elevation level e_h.
- **Γ** — the set of internal cliff edges: shared edges between neighboring hexes with |e_i − e_j| > 1.
- **Ω_cut** — the completion of Ω \ Γ under the intrinsic path metric (distance = shortest path length staying inside Ω \ Γ). This single definition produces two boundary copies along each cliff edge automatically: points on opposite sides of a cut are far apart in the path metric even at identical world XY. The copies may occupy the same world-space XY line, but they are not the same mathematical points.
- **z : Ω_cut → R** — the unknown height function, single-valued on Ω_cut. The same world XY on a cliff edge may correspond to two topological points and therefore two height values.

**Center constraints (world-z units).** The constraint is `z(c_h) = (e_h − elevation_base) · elevation_step`, i.e. the repo's authoritative world-z scale (`tile_world_z` / `canonical_center_world_z` in `tools/blender/terrain/eom_terrain_math_core.py`). Stating the constraint as `z(c_h) = e_h` in raw levels is a units error: every audited z-range comparison would be wrong by the step factor. No slope, gradient, or normal is prescribed at hex centers — the surface is free to choose the locally smoothest slope consistent with all center constraints and the cut topology.

**Smoothness/energy.** The primary model is thin-plate / bending energy — minimum squared curvature — not a membrane model minimizing ∫|∇z|². This is not merely aesthetic: in 2D, a membrane model with point constraints is **mathematically ill-posed** (H¹ does not embed into continuous functions; the Laplacian's Green function diverges like log r), and discretizations produce mesh-dependent spikes at pinned points — the tent-pole / "Spetsbergen" artifact family. Thin-plate (H², curvature-based) makes point pins well-posed and yields C¹ surfaces through them. In 2D, H² embeds into continuous functions, so the pointwise interpolation constraints are continuous functionals and the constrained minimization has a solution in H²(Ω_cut); standard crack-domain Sobolev theory covers the slit topology, including reduced regularity at crack tips, which is harmless here (z stays bounded and continuous).

On the **uncut** plane (Γ = ∅) this energy with exact interpolation is exactly the thin-plate spline — i.e., the visually approved TS-03 baseline is the special case Γ = ∅ of this formulation. The target is a strict generalization of the model that already looks right.

**Continuity requirements.** Within every connected smooth sheet of Ω_cut, z is continuous and ∇z is continuous — stated as a *property of the minimizer* (interior regularity of the biharmonic equation; C¹ even at the r²·log r behavior of interpolation points), not as an additional imposed constraint. Across ordinary edges (delta ≤ 1) the surface is not cut, so ordinary smooth continuity applies. Across cliff edges (delta > 1) there is **no** continuity condition: z need not be continuous, ∇z need not be continuous, and no Laplacian, curvature, interpolation, or mesh-connectivity stencil may couple the two sides across the cut. The upper and lower sides are solved as parts of the same global cut-domain problem, but they are topologically separated along the cliff boundary.

**Boundary conditions.** Free/natural everywhere: no fixed height or slope on the outer map boundary, no implicit pull toward z = 0, and each internal cut boundary copy behaves as an internal free boundary. The cliff boundary is not a row of forced interpolation points by default; it is primarily a topological cut. Natural boundary conditions arise variationally and need not (must not) be imposed as extra constraint rows.

**Overshoot expectation.** Thin-plate minimizers do not obey a maximum principle. Mild overshoot beyond the [min, max] center heights is *inherent and correct*: the accepted TS-03 baseline itself has z ∈ [−0.587, 2.304] against pins in [0, 2.0]. The acceptance criterion must be "TS-03-like mild overshoot", never "z within pin range" — or the model will be falsely failed.

**Deliberate consequence to accept.** With center-only data, the solver decides where within each hex the steepening happens near a cliff. The cut is exactly on the authoritative edge, but the upper sheet's height at its cut boundary will generally not equal the upper hex level exactly (it is free). If art direction later demands "the upper rim sits at exactly the hex elevation", that is a new, deliberate soft constraint to be added explicitly — not smuggled in.

**Technical note (energy variant).** ∫(z_xx² + 2z_xy² + z_yy²) and ∫(Δz)² differ by a null Lagrangian: identical interior Euler–Lagrange equation (Δ²z = 0 away from pins), *different natural boundary conditions*. Both are defensible "free plate" models; ∫(Δz)² is what the simple discrete operator below actually approximates. The ∫(Δz)²-type natural boundary conditions are accepted for v1, and the choice is documented here.

## Cliff-edge rule

For every shared edge between neighboring hexes h_i and h_j, with delta = |e_i − e_j| on integer levels:

- **delta ≤ 1** — ordinary smooth traversable transition. No cut, no seam, no cliff band. (delta 0: no elevation transition; delta 1: ordinary smooth transition.)
- **delta > 1** — internal cliff cut, member of Γ.

This rule is based **only** on authoritative discrete hex elevation data. Cliffs must not be inferred from:

- rendered mesh slope
- generated vertex heights / generated mesh
- material or splatting
- visual appearance
- later cliff assets

## Corner and termination rules

The **path-metric completion is the authoritative definition** of the cut topology. It resolves every corner case without ad hoc identification rules. For an interior corner v where exactly three hexes meet, classify the three incident hex-pair edges by delta (smooth iff delta ≤ 1, cliff iff delta > 1). With k incident cliff edges, the completion gives:

- **Case 0** (k = 0): all transitions smooth. v remains 1 point; the surface is fully smooth through the corner; no cut boundary starts or ends at v.
- **Case 1** (k = 1): the cliff boundary **terminates** at v. v remains 1 point (a crack tip); the sheets are connected around the tip; the two other incident edges are smooth and remain connected.
- **Case 2** (k = 2): the cut continues/turns through v. v becomes **2 points**: the hexes connected through the one smooth edge share a corner point; the hex isolated by the two cliffs gets its own. This is a cliff continuation/junction, not a termination.
- **Case 3** (k = 3): three-way cliff junction. v becomes **3 points** (one per hex wedge). The completion handles this cleanly — it does **not** need to be disallowed mathematically. Keeping it rare in map generation is a design choice, but the formulation must not claim it is undefined, because it is not. It must never be silently treated as an ordinary termination.

**Interior termination theorem (delta exactly 2).** For an interior corner where hexes a, b, c all exist with integer elevations, if edge_ab is the only cliff (delta_ab > 1, delta_bc ≤ 1, delta_ca ≤ 1), then by the triangle inequality for absolute differences:

```
delta_ab = |e_a − e_b| ≤ |e_a − e_c| + |e_c − e_b| ≤ 1 + 1 = 2
```

With delta_ab > 1 and integrality, **delta_ab = 2**. The claim is verified sound, with three scope caveats:

1. It requires **all three hexes to exist**. At map-boundary corners or footprint holes, a cliff of any delta > 1 may terminate with no such constraint — boundary-terminating cliffs are outside the three-hex theorem.
2. It requires **integer elevation levels** (the load-bearing assumption).
3. It is a **consequence, not a rule to enforce** — useful as a map-validation assert: every interior Case-1 corner must show delta = 2, otherwise the cliff classification or corner census is buggy.

**Natural crack-tip closure.** Because a Case-1 termination corner is a *single* point of Ω_cut, z is single-valued there, so the height gap across the cliff tapers continuously to zero at the termination corner — automatically. The exact model *derives* the "symmetric closure" behavior that earlier prototypes (TS-07c/TS-07d planning) imposed heuristically. **No explicit midpoint closure constraint is needed or wanted.**

## Uniqueness / gauge convention

The thin-plate bending energy has an affine nullspace:

```
z(x, y) = a + bx + cy
```

A connected component of Ω_cut therefore has a unique primary minimizer only if it contains at least three non-collinear pinned hex centers. **Deficient components are allowed** — e.g. a plateau component containing one hex, a narrow component of two hexes, or a component with collinear centers — and must not be rejected as invalid.

Structure: on a connected component C, the set M of primary minimizers is the affine family

```
M = z* + N_C,   N_C = { affine g : g(c_h) = 0 for every pinned center c_h in C }
```

Every component contains at least one whole hex and therefore at least one pin, so **constants are never in N_C** — the convention structurally cannot shift the height level or pull anything toward z = 0. dim N_C = 3 − rank of the pin set (rank 1: single center; rank 2: ≥ 2 collinear centers; rank 3: ≥ 3 non-collinear centers).

**Convention.** For deficient components, the terrain solution is defined as the unique primary minimizer whose *component-averaged gradient* ⟨∇z⟩_C has zero projection onto the gauge directions {∇g : g ∈ N_C} — equivalently, the primary minimizer of least secondary gradient energy ∫_C |∇z|² dA. Existence and uniqueness of this representative are guaranteed (strictly convex quadratic over the finite-dimensional gauge family).

Warnings that must be preserved by any implementation:

- This is a **gauge / uniqueness convention only**, acting within the primary minimizer set.
- It is **not** a global membrane regularizer. No ε·∫|∇z|² term may appear in any assembled energy.
- It is **not** a boundary slope condition, **not** a rim condition, and **not** a z = 0 anchor.
- It **must not affect well-determined rank-3 components**: there N_C = {0}, M is a single point, and the convention is vacuous *by definition, not by tolerance*.
- It changes the solution only by an affine function per deficient component, which carries zero curvature — it is mathematically incapable of creating tent poles, and it cannot change the bending energy.
- The preference for zero tilt is a deliberate world-horizontal (gravity-aligned) gauge — a purely coordinate-free rule could not distinguish tilts, and "isolated plateau should be flat" is the intended behavior.

Expected behavior:

- **One pinned center (rank 1):** constant horizontal surface, z ≡ z₁ (the pinned world height).
- **Two pinned centers (rank 2):** the plane through both pinned heights with zero perpendicular tilt. With u = normalize(c₂ − c₁):

```
z(x) = z₁ + ((z₂ − z₁) / |c₂ − c₁|) · dot(x − c₁, u)
```

- **Collinear pinned centers (rank 2, ≥ 3 pins):** if the pin heights are *not* affine along the line, the primary minimizer is a genuinely **curved** surface (bending energy > 0), unique up to the perpendicular tilt mode. The convention sets the component-mean perpendicular gradient to zero — it does not force the surface to be a plane and does not flatten the determined along-line profile. The perpendicular affine tilt is the only gauge freedom removed.

## Recommended discrete target

Implementation guidance for later solver slices — **not implemented by this document**. Environment constraint (verified): Blender's bundled Python has NumPy but **SciPy must not be assumed, added, or used**.

- **Unknowns:** z on the **cut top-surface lattice** — the same subdivided barycentric lattice as the analytic mesh, with vertices along Γ duplicated per side and **Case-1 termination corners kept single**. The mesh builder already builds exactly this topology when `split_top_at_cliff_edges=True`; the earlier TS-03d disaster was not this cut but the per-cliff-side *cluster solve* layered on top. The cut connectivity itself is the correct discrete Ω_cut.
- **Energy:** E(z) = Σ_i a_i · ((L z)_i)², with L the umbrella (uniform-weight) graph Laplacian on the cut lattice and a_i a vertex area weight (uniform acceptable on this near-equilateral lattice). This is the standard squared-graph-Laplacian / biharmonic-style discrete plate.
- **No stencil may cross Γ** — automatic when adjacency is built on the cut graph, and asserted structurally.
- **Constraints:** hard pins by elimination (hex centers are lattice nodes; substitute and solve for free nodes only).
- **Solver:** Conjugate Gradient in plain NumPy on the SPD system (Lᵀ A L restricted to free nodes). The matvec is two vectorized Laplacian applications over precomputed CSR-style neighbor arrays. Jacobi (diagonal) preconditioning; warm start from a per-sheet planar/TPS fit.
- **Jacobi/Gauss–Seidel relaxation is not the production solver.** The biharmonic condition number scales like h⁻⁴; relaxation demonstrably fails to converge in reasonable iteration counts even on easier operators.
- **Sampling into the mesh:** keyed by **(position, side)**, not position alone, so duplicated cliff vertices receive their own sheet's height. Mesh generation then uses the cut topology so the geometry realizes the two sheets.
- **Discrete pitfall that dictates component handling:** the discrete plate energy does *not* exactly vanish on tilted planes (boundary vertices have asymmetric one-rings), so on a deficient component the discrete system is **nearly singular, not singular** — tiny positive eigenvalues along near-affine modes. A naive solve would converge miserably and "select" a mesh-dependent artifact tilt. The gauge must be handled explicitly, never left to the solver.
- **Boundary caveat:** the squared-graph-Laplacian energy with reduced boundary stencils approximates "Δz = 0 at the free boundary" rather than exact moment-free plate conditions. Mild, known, acceptable v1 bias — documented here.

## Component handling

Run a component census on the cut lattice first; compute the pin-set rank per component with an **exact integer collinearity test** on hex axial coordinates (no floating-point epsilon — "deficient" is an authoritative-data property, never a numerical judgment call). Route each component:

- **rank 3** → plain CG. No gauge machinery instantiated at all (structural code-path guarantee).
- **rank 1** (single hex) → analytic constant horizontal surface z ≡ z₁. No solve.
- **rank 2, affine-consistent heights** (always true for 2 pins) → analytic plane via the two-pin formula. No solve.
- **rank 2, non-affine collinear heights** (≥ 3 collinear pins, curved primary solution) → CG with **rank-one deflation** of the perpendicular-tilt mode (B′ = B + σ·ĝĝᵀ, ĝ the tilt mode, which vanishes at every pin) plus **exact post-projection** to zero component-mean perpendicular gradient.

Per-component diagnostics to report:

- `component_id`
- `node_count`
- `hex_count` / `pinned_center_count`
- `pin_rank` (1 / 2 / 3, exact integer test)
- `fully_determined` (rank == 3)
- `gauge_convention_applied` and `method` (`analytic_constant` / `analytic_plane` / `cg_deflated` / `cg_plain`)
- `selected_affine_gradient`
- `mean_gradient_gauge_projection` (≈ 0 where the convention applied)
- `max_center_interpolation_error`
- `discrete_bending_energy` (pre/post gauge projection where applicable)
- `z_min` / `z_max`

Global asserts: `convention_applied_count == deficient_count`; convention never touched a rank-3 component; no global regularization active; bending energy identical before/after gauge projection (within the tiny boundary-row residue, itself reported). Banner flags: `GAUGE_CONVENTION_SCOPE=deficient_components_only`, `GLOBAL_MEMBRANE_REGULARIZER=OFF`.

## Validation stages

- **Stage 0 — cut-lattice audit only, no solve:** build the cut lattice; report node count, duplicated cliff-line nodes, component count, pins per component with rank check, corner census (Case 0/1/2/3 counts); assert every interior Case-1 corner has delta = 2.
- **Stage 1 — Γ = ∅ null solve:** discrete thin-plate CG on the *uncut* lattice. **Gate: Stage 1 must visually and numerically resemble the approved TS-03 smooth terrain baseline before any cliff behavior is judged.** This isolates the operator and solver from the topology.
- **Stage 2 — cut solve:** enable the cut; audit z-range (TS-03-like mild overshoot), gap profile along cliffs, crack-tip closure at terminations, convergence.
- **Stage 3 — presentation walls / cliff assets:** mesh realizes the two sheets; presentation-only geometry fills the gap; dedicated standalone generator/runner/audit files; never touch a `*BASELINE*` path.

## Failure modes to avoid

- **TS-07c hard-rail TPS ringing / overshoot:** hard near-discontinuous constraints forced into a globally-supported smooth basis answer with global ringing (audited z ∈ [−2.84, 4.85] vs expected ≈ [0, 2.4]). The fix is cut topology, not added constraints.
- **Membrane / relaxation tent-poles (TS-07d family):** point pins in a membrane-leaning model are ill-posed in 2D and produce mesh-dependent spikes at pinned centers. Any solver blend toward membrane behavior re-inherits this in proportion to the blend.
- **Old FEM / "Spetsbergen":** cautionary reference only; its mixed-FEM route with hard pins produced unstable, visually broken output. Do not reuse as a height solver.
- **TS-03d / 77-island patch fragmentation:** per-cliff-side cluster solving fragmented the terrain into dozens of islands. The true cut topology has a small component count (1 unless a region is fully ringed by cliffs); component counts anywhere near 77 indicate clustering has crept back in.
- **Zero-boundary pull:** any implicit anchor of the outer boundary (or any node) toward z = 0 violates the free-boundary model.
- **Global membrane regularizer creeping in:** an ε·∫|∇z|² term added "for stability" perturbs well-determined components, reintroduces tent-pole pathology in proportion to ε, and makes results mesh- and ε-dependent. The gauge convention exists precisely so this is never needed.

## Acceptance criteria

1. TS-03 baseline generator/runner/audit files and behavior unchanged; no `*BASELINE*` blend file overwritten.
2. Exact authoritative hex-center interpolation, in world-z units (max center error ≈ 0, reported).
3. Cliff edges detected only from authoritative discrete delta > 1.
4. Delta ≤ 1 edges remain smooth: no cut, no seam, single-valued z along them.
5. The Γ = ∅ null solve resembles the approved TS-03 baseline (visual and numeric gate) before cliff behavior is judged.
6. No operator stencil couples nodes across Γ (structural assert).
7. No z = 0 boundary pull anywhere.
8. No global membrane regularizer in any assembled energy.
9. Deficient components are handled only by the gauge convention (constant / plane / deflation + projection), and the convention never touches rank-3 components.
10. Ordinary terrain remains broad and rolling — no tent poles: max gradient in a one-ring around each pinned center stays bounded under lattice refinement.
11. Overshoot is mild and TS-03-like (≈ [−0.65, 2.35] band for the current map); anything approaching the TS-07c failure range ([−2.84, 4.85]) is a hard fail.
12. Case-1 terminations close naturally at the crack tip: the gap tapers continuously to zero, with no explicit closure constraint.
13. Cliff walls / assets are presentation-only; wall vertices never become solver constraints; wall construction never alters the solve.
14. All topology/component diagnostics are logged (corner census, component census, per-component report, gauge asserts).
15. Mesh top-island count equals the solver's cut-component count (expected small; never ~77).
16. Deterministic reruns produce identical output; solver convergence is reported (residual below tolerance, monotone energy).
17. No failed experimental solver becomes canonical without explicit visual approval.

## Reference dataset (N2 derived golden — not production source)

The N2 export is a **pre-solved reference golden** for parity testing and auditing the accepted TS-08 Stage-2 result. It is **not** the final production terrain source and **does not replace** running a TS-08-equivalent solver on the canonical 2D grid.

Parity checks compare **solver output** against this golden (and against the accepted visual Blender result where applicable), not against a `.blend` mesh:

| Item | Value |
|------|-------|
| Path | `content/terrain/reference/handdrawn_test_map_full_01_ts08_stage2_reference_v1.json` |
| Regenerate | `python tools/blender/terrain/export_ts08_reference_dataset.py export` |
| Audit | `python tools/blender/terrain/export_ts08_reference_dataset.py check` |
| Frame | Godot Y-up positions/heights; axis `(x_g, y_g, z_g) = (x_b, z_b, -y_b)` |
| Contents | `MapIdentity`, cut-lattice node keys/sheet ids, seam duplication summary, Y-up top triangles, center-pin `(q,r)` mapping, cliff tile pairs |
| Golden topology | 74129 nodes, 145152 triangles, 168 center pins, 78 cliff edges, 861 duplicated cliff-line nodes, 0 cross-cliff adjacency violations |
| Golden height range (Godot Y / Blender Z) | min `-0.0953001335506`, max `2.09155970068` (tol `1e-12`) |
| Audit gate | Full file byte-for-byte match with deterministic regeneration (tamper + recomputed `content_hash` still fails) |

Full schema v1 and audit contract: `content/terrain/reference/README.md`.

## Cautionary references

The following are cautionary references, **not** part of the target. Read for context; do not reuse as solver behavior:

- The old FEM thin-plate experiment (`eom_terrain_fem_thin_plate.py`, TS-04d) that produced "Spetsbergen" artifacts — mesh bookkeeping ideas may be read; the height solver must not be reused.
- TS-03d cliff-side clustering (`build_cliff_side_cluster_lookup`, `_side_cluster_for_tile`) — the 77-island failure; never call.
- TS-07c hard virtual rails (`eom_terrain_ts07c_virtual_rails.py`) — cautionary for constraints; its geometry helpers (cliff edge endpoints, upper/lower classification, presentation wall builder) remain reusable.
- TS-07d weighted Jacobi/Gauss–Seidel relaxation — lattice-construction and vectorization patterns are reusable; the membrane/plate blend and plain relaxation are not the target.
- Release bands.
- Rim constraints.
- Epsilon-offset rail tricks (e.g. 0.001 offsets).
- Per-region TPS patching.
- Local post-solve corrections masquerading as solver output.
