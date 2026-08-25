# A2.6 Nail-Surface Ground-Truth Forensic Audit

Date: 2026-08-23. Status: **historical forensic evidence (visual FAIL
confirmed — root cause identified)**. Canonical hand-surface rules:
`docs/EQUIPMENT_INTERACTION.md`. This warrior’s compiled patches:
`uthana_warrior_hand_fixture.gd`. Do not rewrite the measurements below.
Follow-up implementation: A2.7 (see dated note at the end). A2.8b
preserved the causal contract; it did not recalibrate the grip.

Contradiction under audit: the A2.6 grip reports `nail_out ≈ +0.98`,
`pad_in ≈ +0.63`, `nail_axis ≈ 0.06`, yet in F6 the textured thumb nail is
not visible from the radially-outer camera; it appears turned roughly a
quarter turn, pointing along/backwards relative to the shaft.

## 0. Baseline

- `slice a1`: 71 checks OK. `slice a2`: 198 + 61 = 259 checks OK.
- `a1_native_walking.res` SHA256 `5876B1C5E8A51598…` (unchanged).
- Uthana GLB SHA256 `ADFE53DB59FE21D9…` (unchanged).
- The green baseline contains the visually incorrect A2.6 pose; every
  numeric claim below was measured against that exact baseline.

## 1. Measurement-chain trace (old path)

The old `nail_out` value flows through:

1. `uthana_a2_power_grip.gd` constants `T3_NAIL_NORMAL_LOCAL`,
   `T3_PAD_NORMAL_LOCAL`, `T3_PAD_MARKER_LOCAL` — compiled in A2.5 from a
   temporary probe (since deleted).
2. `_derive_thumb_anatomy()` — rebuilds the thumb anatomical frames from
   those constants (the pad marker also rebinds `_pad_locals["thumb"]`).
3. `measure_thumb_now()` — transforms the compiled bone-local normals by
   the CURRENT Thumb3 pose basis and dots them against a SINGLE radial
   direction taken at the pad marker: `nail_out_dot = nail_w · r_hat`.
4. `evaluate_thumb_wrap()` R10 gates → tests/HUD display the same numbers.

No skinned triangle is ever consulted at any point. The entire chain is
exactly as trustworthy as the compiled constants — and those are wrong
(§3). The transformation math itself (steps 3–4) is correct; this audit
found **no pose-phase or cache divergence** (§6).

## 2. Nail-patch identity without brightness heuristics

Method: UV/albedo census of every Thumb3-dominated triangle (≥2 of 3
vertices dominant on Thumb3, remainder Thumb2) on BOTH thumbs; labeled UV
atlas crops rendered and inspected; rest-pose 3D orbit renders of both
thumbs captured and inspected.

Findings (albedo 2048×2048, one skinned surface, `si=0`):

- **Left thumb** (24 tris, islands at UV ≈ (0.145, 0.66) and (0.94, 0.86)):
  the dorsal island contains an **unmistakable textured nail plate**
  (bright oval, defined bed, lunula) — triangles census-ids {2, 3, 5, 7,
  13}, luminance ≥ 0.52. Confirmed visually in 3D orbit render
  (`left_orbit7`): plate clearly visible on the dorsal face.
- **Right thumb** (30 tris, islands at UV ≈ (0.17, 0.30), (0.93, 0.02),
  (0.77, 0.01)): the nail texture is **much fainter and smaller** — a
  small bright low-saturation plate in the tip island at
  UV ≈ (0.924–0.936, 0.030–0.033), census-ids {14, 18, 22, 23}
  (luminance 0.60–0.69, saturation 0.38–0.45). The (0.77, 0.01) island the
  old constant tracked (§3) is plain dorsal knuckle skin with **no nail
  content**. In 3D orbit renders the right nail reads as a faint light
  streak only — an asset asymmetry vs the left thumb (documented
  limitation; the plate exists but is visually subtle).

Verified right nail patch (compiled into A2.7 profile metadata):

| si | vertex indices | UV centroid |
|----|----------------|-------------|
| 0 | 5486, 3302, 3301 | (0.9236, 0.0306) |
| 0 | 5486, 5488, 3302 | (0.9310, 0.0321) |
| 0 | 3302, 5488, 5489 | (0.9338, 0.0332) |
| 0 | 3302, 5489, 5484 | (0.9361, 0.0334) |

Verified right distal pad patch (10 triangles, volar tip island, vertex
indices 5480–5489/3300/3301, UV ≈ (0.921–0.935, 0.011–0.027)); identified
by topological mirroring of the left pad island plus rest-normal
coherence, no brightness heuristic.

## 3. What the old compiled constants actually tracked

- Winding ground truth: for **every** thumb triangle on both thumbs, the
  authored cross-product normal `(v1−v0)×(v2−v0)` is **opposite** the
  imported (rendered) vertex normals (`dot ≈ −0.87…−1.00`, flip = −1).
  The mesh is CW-authored. Any probe using raw cross products without a
  rest-anchored flip factor selects/points surfaces inside-out.
- The A2.5 selection rule was "the bright plate facing exactly away from
  the palm (`dot(volar) = −1.00`) is the nail". Ground truth from the
  left thumb: the real nail's area-weighted rest normal has
  `dot(volar) = −0.68` (tilted ~47°, with a large distal/axial
  component). A plate at exactly −1.00 is *not* the nail.
- The compiled `T3_NAIL_NORMAL_LOCAL` points anti-volar (−1.00) and
  best-matches dorsal knuckle-skin triangle census-id 26 (UV (0.762,
  0.019), no nail texture), **67° away** from the true nail plate normal.
  T3-local truth: nail ≈ (0.845, −0.028, −0.535) vs compiled
  (−0.159, −0.049, −0.986).
- The compiled pad normal is **56°** off the true pad plate normal
  (T3-local truth (0.506, −0.186, 0.842) vs compiled (−0.417, −0.333,
  0.846)), and the pad marker sits ≈7 mm (model space) from the true pad
  centroid — on the wrong side of the distal phalanx.

## 4. Deformed-geometry ground truth at the A2.6 pose

CPU-skinned verified patches at the achieved final pose (Walking t=0.35 +
canonical + refinement), geometric normals with rest-anchored winding (no
auto-flip), **per-triangle** radial directions, area-weighted:

| Measure | OLD gate claims | TRUE deformed geometry |
|---|---|---|
| nail_out | **+0.99** | aggregate **+0.61**, per-tri mean +0.54 (min +0.37, med +0.92, max +0.93) |
| nail_axis | **0.11** | aggregate **0.66**, per-tri mean 0.67 |
| pad_in | **+0.75** | +0.47 (area-weighted) |
| pad min gap | (marker) +0.14r | **−0.46r (penetrates shaft)** |
| nail min gap | n/a | **+0.03r (nail nearly the contact surface)** |

The `nail_out=+0.99` is a **false positive**: it describes the compiled
(mislabeled) normal, not the nail. The true plate faces the shaft axis
almost as much as it faces out (0.66 axial vs 0.61 out) — exactly the
user's observation "riktad bakåt/längs skaftet" — while the pad plate is
buried 0.46r inside the club and the nail plate skims the surface.

## 5. Radial direction and statistics

Per-triangle radials (centroid → closest point on final shaft axis) were
used throughout; the old single-radial-at-marker shortcut is one more way
the old numbers detached from the plate (the marker is 7 mm off). Area
weighting per triangle; no normalization step hides sign.

## 6. Pose-phase verification

| Phase | TRUE nail agg out/ax | OLD nail_out |
|---|---|---|
| Thumb at rest (grip fingers on) | −0.37 / 0.92 | −0.90 |
| Canonical (no refinement) | +0.61 / 0.66 | +0.99 |
| Refined achieved A2.6 | **+0.61 / 0.66** | **+0.99** |

Canonical and refined-achieved are identical (refinement delta ≈ 0 at
nominal radius); HUD, tests and runtime gate all measured the same final
pose. **No stale-pose/cache error exists.** The F6 preview scene renders
this same pose (its runtime smoketest asserts the same diagnostics).

## 7. Visual patch ground truth

Rest-pose orbit renders of both thumbs (18 screenshots) plus labeled UV
atlas crops were captured and inspected during this audit (temporary
artifacts, removed after use). Left nail plate clearly visible dorsally;
right plate faint; no nail texture in the island the old constant
matched. This inspection fixed the patch identity in §2.

## 8. Tau (quarter-turn) sweep, TRUE plate geometry

At (σ=25, φ=0, MCP=0, IP=90), varying CMC pronation τ:

| τ | TRUE nail agg out | agg ax | pad in_w | marker gap | old gates |
|---|---|---|---|---|---|
| −135 | −0.25 | 0.38 | +0.56 | +0.31r | FAIL (zone/twist/parallel) |
| −105 | +0.38 | 0.62 | +0.56 | +0.11r | FAIL (twist) |
| **−90 (A2.6)** | **+0.61** | **0.66** | +0.47 | +0.14r | PASS |
| −75 | +0.75 | 0.64 | +0.38 | +0.22r | FAIL (approach) |
| −60 | +0.82 | 0.57 | +0.30 | +0.34r | FAIL (approach) |
| −45 | +0.87 | 0.45 | +0.24 | +0.49r | FAIL (contact+approach) |

The true nail faces out **more** with **less** pronation; A2.6's τ=−90 is
30–45° over-pronated for the real plate. The user's quarter-turn
hypothesis is directionally confirmed (magnitude ≈ 30–45°, not exactly
90°). Better orientations are blocked only by contact/approach gates that
measure the **mislabeled pad marker** — which lifts off (+0.22…+0.49r)
while the TRUE pad still penetrates (−0.3…−0.46r). The marker sits on the
wrong side of the phalanx, so the whole calibration equilibrium rotated
the thumb to feed the wrong surfaces.

## 9. CMC τ ≈ −90° decomposition

Physical axial roll (rest → A2.6, twist-free transport reference):
Thumb1 −92°, Thumb2 −61°, Thumb3 −171° (swings 82/105/88°). τ=−90 is a
real physical quarter-turn pronation of the metacarpal; on top of the
mislabeled distal references it acted as **compensation for a mislabeled
distal frame**, not as anatomically motivated opposition. The distal
phalanx accumulates −171° of roll vs transport — anatomically impossible
as pure pronation and only "accepted" because no gate measured real skin.

## 10. Root-cause classification

1. **First wrong premise (A2.5):** "the nail is the bright plate facing
   exactly anti-volar at rest" + cross-product normals used without
   winding correction (mesh is CW-authored; all flips are −1). The real
   nail tilts 47° from anti-volar.
2. **First wrong implementation:** compiling `T3_NAIL_NORMAL_LOCAL` (67°
   off), `T3_PAD_NORMAL_LOCAL` (56° off) and `T3_PAD_MARKER_LOCAL` (7 mm
   off) from the mislabeled surfaces; every R10 gate, HUD value and
   calibration (τ=−95/−90) then optimized the wrong references.
3. Downstream effects (not independent causes): over-pronated CMC,
   true pad penetrating −0.46r, true nail near-axial (0.66) and skimming
   the shaft (+0.03r).
4. Explicitly ruled out: pose-phase/cache divergence (§6), radial-axis
   error at gate level (the math is right, the inputs are wrong),
   left/right confusion, debug-camera direction.

## 11. Why the 259 green checks false-passed

Every thumb-orientation gate (R10 family), the HUD lines and the runtime
smoketest read `measure_thumb_now()`, which projects the **compiled
constants** — never a skinned triangle. The gates faithfully verified
"the mislabeled A2.5 normal faces out" (+0.99, true) which is simply not
the proposition "the textured nail faces out" (+0.61 agg, axial 0.66,
false as a visual claim). Contour gates measure gap profiles, not
orientation, so they could not catch it either.

## 12. Recommended correction (binding for A2.7)

1. Replace patch identity with the §2 verified triangles, compiled as
   Uthana profile metadata (triangle/vertex/UV identity + rest-anchored
   winding flip); bind-sanity must fail on any mismatch. No runtime
   albedo analysis.
2. Rebind the pad marker/`_pad_locals["thumb"]` to the TRUE pad plate
   centroid and rebuild the thumb anatomical frames from the TRUE pad
   normal (bind/profile compilation stage) — the causal fix.
3. Make deformed skinned-triangle geometry (rest-anchored winding,
   per-triangle radials, area-weighted aggregate) the acceptance ground
   truth for nail-out/axis/pad-in at the final achieved pose; demote
   compiled-normal projections to diagnostics.
4. Recalibrate canonical CMC opposition/pronation after (2): expected
   valid region τ ≈ −60…−80 with true-pad contact restored; then a
   strictly local deterministic search over (σ, φ, τ, MCP, IP).
5. Add fail-closed ground-truth gates + negative regressions (A2.6 pose
   must be rejected; old `nail_out=+0.98` path shown as false positive).
6. Anatomical ceiling for this asset: the plate is curved with an
   inherent distal tilt — even the perfect grip cannot reach
   `agg out = 1.0`; thresholds must come from the reachable candidate
   set (τ sweep: agg out ≈ 0.75–0.87 reachable) and from the left-thumb
   rest reference (dot volar −0.68), not from wishful ±0.98.

---

**A2.6 visual FAIL confirmed; nail-surface ground-truth audited.**

## Implementation note (2026-08-23, A2.7)

A2.7 implemented recommendation §12 in `uthana_a2_power_grip.gd` (profile
patch metadata + ground-truth gates + recalibrated canonical pose),
`uthana_a2_walking_preview.gd` (ground-truth HUD/debug) and the A2 tests
(negative regressions incl. the A2.6 false-positive reproduction). The
historical values above are preserved as measured; superseded constants
are marked in code. See `A2_NOTES.md` §A2.7 for before/after numbers.
