# A2.1 Thumb Opposition — Theoretical Audit

Status: **historical forensic evidence (A2.1 visual FAIL confirmed).**
Canonical rules: `docs/EQUIPMENT_INTERACTION.md`. Do not rewrite the
measurements below. The 185 green checks measured a wrong contract.
This document is audit-only; no implementation was changed.

All numbers below are measured on the live A2 stack (Walking t = 0.35,
socket/fingers exactly as shipped) with a temporary probe that was deleted
after the audit. Angles are in the shaft section plane (right-handed frame
`e1, e2` perpendicular to the shaft axis `D`; positive = counter-clockwise).
`r` = normalized grip radius (0.00388 in preview units).

---

## 1. First incorrect premise

> "Thumb opposition = the thumb pad lands in the radial sector
> diametrically opposite the four finger pads."

This is a **precision-pinch** model, not a power-grip model. Everything else
followed from it:

- The canonical thumb pose was calibrated to *reach the opposite sector*,
  which on this rig is only reachable by sweeping **the same angular
  direction as the fingers** (clockwise) across the palm.
- The thumb flexion sign was borrowed from the index
  (`_flex_sign["thumb"] = _flex_sign["index"]` in `uthana_a2_power_grip.gd`),
  hard-coding finger-like closing.
- The A2.1 gates encoded |wrap| (unsigned) and `radial_dot <= -0.25`
  (the diametric sector), so a same-winding thumb passes and — worse — a
  correctly opposing thumb **fails** them (Section 6, case 5).

In a real right-hand power grip around a cylinder the thumb winds in the
**opposite angular direction** to the fingers and its pad meets the finger
pads / index middle phalanx region from the other side (the "motlås" of a
fist). The pad does *not* land diametrically opposite the fingertips.

## 2. Why 185 checks produced a false PASS

| Gate (current) | Value for shipped thumb | Why it cannot catch the defect |
|---|---|---|
| `axial_dot_abs <= 0.60` | 0.50 | Direction-of-travel blind; only rejects axial lying |
| `transverse_over_axial >= 1.2` | 1.72 | Same |
| `abs(wrap_deg) >= 45` | \|−99.6\| | **Unsigned** — cannot distinguish winding direction |
| `radial_dot_vs_fingers <= -0.25` | −0.34 | Targets the diametric sector, i.e. the wrong destination; a same-winding thumb reaches it |
| pad gap / penetration | 0.16r / 0 | Contact says nothing about winding |
| chain min gap, volar clearance, IP >= 0 | pass | Orthogonal concerns |
| `opposition_dot <= -0.3` (A2 test) | −0.34 | Point-contact normal model; winding-blind (Section 5) |
| encirclement v2 >= 180° | 222.5° | **Thumb-independent** — the palm patch supplies the entire volar arc (Section 5) |
| negative regression | rejects old axial pose | Only encoded the *previous* defect |

No gate anywhere compares the **signed** thumb winding with the **signed**
finger winding. That is the missing invariant.

## 3. Measured signed windings (the core evidence)

Continuous signed angular sweep of each chain polyline (base → j2 → j3 →
pad) around the shaft axis:

| Chain | Sweep | Station angles (deg) |
|---|---|---|
| index | **−102.2°** | −138.2 → +173.4 → +130.1 → +119.6 |
| middle | −82.5° | −141.8 → +174.3 → +135.1 → +135.7 |
| ring | −62.6° | −146.3 → +176.5 → +149.3 → +151.0 |
| pinky | −60.0° | −147.0 → −179.4 → +162.7 → +152.9 |
| median (fingers) | **−72.6°** | |
| **thumb** | **−99.6°** | −10.6 → −53.4 → −127.2 → −110.2 |

**All five digits wind the same direction (negative/clockwise).** The thumb
is a fifth same-direction curl entering from the radial side — exactly what
the user sees. Opposition requires `sign(W_thumb) = −sign(median W_fingers)`.

Invariance (measured): identical after a 137° global yaw; identical at
t = 0.00 / 0.35 / 0.52 / 1.01; under an analytic frame mirror both sweeps
flip together (thumb +99.6, index +102.2), so the **relative** sign relation
is chirality-safe and coordinate-invariant. All quantities are expressed in
radii/hand units, hence scale-invariant.

## 4. Actually rendered/skinned geometry

Thumb chain in the section plane (angle, radius, along-axis, signed gap,
hand-volar side):

| Station | ang | radius | along | gap | volar side |
|---|---|---|---|---|---|
| Thumb1 (CMC) | −10.6° | 1.91r | +0.85r | +0.93r | +0.178 hand |
| Thumb2 (MCP) | −53.4° | 1.39r | +1.52r | +0.38r | +0.018 hand |
| Thumb3 (IP) | −127.2° | 0.93r | +1.63r | −0.08r | +0.096 hand |
| pad | −110.2° | 1.18r | +2.25r | +0.16r | +0.020 hand |

- The chain slides across the volar face (volar side ≈ 0 at the MCP —
  effectively **between shaft and palm**) and hugs the shaft along the same
  angular direction as the fingers.
- Skinned vertex clusters (dominant weight > 0.4): Thumb1 7 verts centroid
  −24.3°; Thumb2 16 verts −61.1° (min gap −0.15r @ −46°); Thumb3 26 verts
  −107.5° (min gap **−0.37r @ −111°**). The nearest actual thumb flesh is
  pressed slightly *into* the shaft on the same-winding path — matching the
  rendered image of a thumb lying along/around the shaft with the fingers.
- Pad marker verification: marker at −110.2° sits 0.0016 (0.42r) from the
  nearest Thumb3-dominated vertex — it does track the distal thumb flesh —
  but its offset from the IP joint along the *hand* volar axis is −0.076
  hand (marginally dorsal). The hand-volar axis is a weak proxy once the
  thumb rotates; a thumb-own-frame pulp check is recommended (minor
  C-contribution, not the root cause).
- Final approach j3 → pad decomposed at the pad: radial **+0.29r (moving
  away from the surface)**, tangential −0.27r, axial **+0.61r (dominant)**.
  The thumb tip is not closing onto its contact; it is drifting axially.
- Thumb pad to index pad distance 2.11r (130° around the circumference);
  to middle pad 2.23r (114°). In a real power grip the thumb tip presses
  into/near the index–middle pad sector (case 5 below reaches 18°).

## 5. Contact normals, force closure, and encirclement v2

Point-contact normals (inward radial at each pad):

- Finger resultant normal points toward −40.1°; thumb normal toward +69.8°;
  `dot = −0.341`. This is the current `opposition_dot`/`radial_dot` measure.
- For the **correct** opposed-winding pose (case 5) the thumb pad lands at
  ≈ +158°, its normal nearly parallels the finger resultant (`dot ≈ +0.95`).
  **In a power grip the opposition lives in the winding (tangential
  closure), not in anti-parallel point normals.** The normal-dot measure
  describes a precision pinch; as a power-grip gate it is not merely
  insufficient — it enforces the wrong pose and rejects the right one.

Encirclement v2 decomposition (threshold 180° unchanged):

| Sample set | Coverage |
|---|---|
| fingers only | 43.0° |
| fingers + palm patch (NO thumb) | **222.5°** |
| fingers + palm + thumb (shipped value) | 222.5° |
| fingers + thumb (no palm patch) | 211.9° |
| fingers + palm + analytically mirrored (opposite-winding) thumb | 264.4° |

The shipped 222.5° is **identical with the thumb deleted**: the inferred
palm patch (centre −60°, half-width 42°) fills precisely the volar sector
the thumb was supposed to secure, and the same-winding thumb contributes
zero marginal coverage. Geometric angular coverage — especially with an
inferred (not measured) palm patch — is not force closure and **must never
substitute for a thumb-opposition gate**. It stays useful as a diagnostic
of overall wrap only. (Note: even measured-contacts-only force closure is a
necessary, not sufficient, condition — the same-winding thumb still passes
it at 211.9° — so the winding relation R1/R2 below is the discriminator.)

## 6. Negative analytic cases vs the CURRENT gates

| Case | Sweep (fingers −102.2) | Opposed? | Current gate verdict | Correct verdict |
|---|---|---|---|---|
| 1. Old axial thumb | −30.6 | no | FAIL (parallel/axial/wrap/through-shaft) | FAIL ✔ |
| 2. Shipped A2.1 pose (transverse, same winding) | −99.6 | no | **PASS — false positive** | FAIL |
| 3. Opposite radial pad, same winding | = case 2 (rd −0.34) | no | **PASS — false positive** | FAIL |
| 4. Large \|wrap\| without opposed closure | = case 2 (\|−99.6°\|) | no | **PASS — false positive** | FAIL |
| 5. Correct opposite winding (eulers (−30,0,60)/(45)/(54), found by probe) | **+168.4**, dot 0.19, gap −0.08r, pad ≈ 18° from finger pads | **yes** | **FAIL** (`thumb_pad_not_on_opposed_side`, `thumb_chain_through_shaft`) | PASS (after calibration) |

*(Correction, A2.2: the raw seed's chain min gap measured −0.96r, not −0.31r
as first tabulated — the −0.31r belonged to a neighbouring sweep candidate.
The seed genuinely cuts through the shaft; the pad cannot reach the +140°
finger-pad median around the OUTSIDE with the available chain length, so the
calibrated A2.2 pose stops the pad at ≈ +86° (meeting ≈ 54°) instead.)*
| 6. Mirrored chirality (analytic) | thumb +99.6 / index +102.2 | relation unchanged | gates indifferent (all unsigned) | relation-based contract invariant ✔ |
| 7. Low pad gap, wrong contact normal (synthetic metrics) | — | no | FAIL (`thumb_pad_not_on_opposed_side`) | FAIL ✔ (but note rd conflates this case with case 5) |

Case 2/3/4 are one and the same shipped pose seen through three gate
lenses — all pass falsely. Case 5 proves an opposed-winding contact pose
**exists in the rig's pose space** and that the current `radial_dot` gate
actively forbids it.

## 7. Root-cause classification

**F — combination, in causal order:**

1. **E (primary):** the acceptance gates measure the wrong concept
   (diametric pad sector + unsigned wrap + point-normal opposition). This
   is the first incorrect premise (Section 1); it also steered calibration.
2. **A:** the canonical thumb angles author a same-winding sweep (a direct
   consequence of calibrating against E's target).
3. **B (contributing):** `_flex_sign["thumb"] = _flex_sign["index"]` and the
   gap-only CMC probe assume finger-like closing; with all thumb hinge axes
   measured near-parallel to the shaft (`dot(local X, D)` = 0.88–0.89) the
   flexion sign fully determines winding direction, so borrowing the finger
   sign locks the thumb into finger-direction winding.
4. **Not C:** the pad marker tracks the distal thumb flesh (0.42r to the
   nearest Thumb3-dominated vertex); a thumb-own-frame pulp check is a
   recommended hardening, not the cause.
5. **Not D:** frames are det = +1 and the winding measurement is
   rotation/time/scale-invariant and chirality-consistent (Section 3).

## 8. Correct coordinate-invariant opposition contract

Let `W(chain)` be the continuous signed angular sweep of a chain polyline
(base → j2 → j3 → pad) around the shaft axis in any right-handed section
frame (det = +1). All requirements are sign *relations* and radius/hand
ratios — invariant under global rotation, scale, Walking pose, world club
direction, and consistent under mirroring.

- **R1 Winding opposition (new, hard):**
  `sign(W_thumb) == −sign(median W_fingers)`, with `|W_thumb| >= ~60°`
  and each `|W_finger| >= ~45°` (fingers measured 60–102°; thresholds to be
  calibrated between the failing pose (−99.6) and the passing pose (+168.4)).
- **R2 Meeting closure / motlås (new, hard):** the angular distance from
  the thumb pad to the median finger-pad direction, measured **along the
  thumb's winding direction**, must be small (≤ ~70°; case 5 measures 18°).
  A same-winding thumb measures ~330° along its own winding and fails.
- **R3 Contact (kept):** pad gap ≤ 0.35r, penetration ≤ 0.20r, chain min
  gap ≥ −0.25r, IP flexion ≥ 0, volar clearance, axial-lying rejections
  (`axial_dot_abs`, transverse ratio) — all keep their current thresholds.
- **R4 Approach (new, soft→hard after calibration):** the final-segment
  approach at the pad must not be radially outward / axially dominant
  (shipped pose: radial +0.29r, axial +0.61r — fails).
- **R5 Force-closure safety net (new, diagnostic):** measured contacts only
  (pads + in-contact phalanges, **no inferred palm patch**): max angular
  gap of inward normals < 180°. Necessary, not sufficient (case 2 passes
  it); never a substitute for R1/R2.
- **Degraded to diagnostics:** `radial_dot_vs_fingers` and
  `opposition_dot` (both winding-blind and, worse, reject the correct
  pose), unsigned `|wrap|` (superseded by signed R1), encirclement v2
  (reported, with an additional "coverage without palm patch" variant).

## 9. Recommended next slice (NOT implemented here)

1. **Thumb winding sign from first principles:** replace
   `_flex_sign["thumb"] = _flex_sign["index"]` with the sign that makes
   `W_thumb` oppose the measured median finger winding (finite-difference
   probe on W, not on gap). The CMC refinement probe likewise scores
   (gap, winding-preservation), still bounded and deterministic.
2. **Recalibrate the canonical thumb pose** from the case-5 seed
   ((−30, 0, 60) / (45) / (54)) with a sweep that optimizes: R1 sign,
   pad in the finger-pad meeting sector (R2), gap band, chain min gap
   ≥ −0.25r (the raw seed sits at −0.31r), volar clearance. CMC creates
   the opposition/aim; IP hinges create flexion onto the surface.
3. **Gates:** implement R1–R4 as hard fail-closed gates in
   `evaluate_thumb_wrap`; R5 + degraded metrics as diagnostics. Redefine
   the A2 test's `opposition_dot <= −0.3` line to the R1/R2 contract (it
   currently enforces the disproven diametric model; keeping it would
   reject the correct thumb).
4. **Negative regressions:** old axial pose, the exact shipped A2.1 pose
   (case 2 eulers (−65,−16,30)/(60)/(72) — must FAIL R1), mirrored-frame
   consistency, and a positive case-5-style fixture.
5. **Unchanged, verified:** four-finger canonical pose/refinement, all
   finger contact gates, socket mapping and invariants, encirclement
   threshold, A1, preview flow. Existing finger contact-angle checks
   already pin these; the slice must keep them bit-identical.
6. **Preview HUD:** show `W_thumb`, median `W_fingers`, opposed flag,
   meeting angle, and fail-closed reason.

## 10. Changed files

- Created: `A2_1_THUMB_OPPOSITION_THEORETICAL_AUDIT.md` (this document).
- Temporary probe `game/_tmp_a21_audit_probe.gd` created and deleted.
- Nothing else: `power_grip_v1`, club attachment, preview, tests, A1,
  production path, steering docs and decision log untouched. No commit.

---

`A2.1 visual FAIL confirmed; thumb-opposition contract audited; implementation not started.`
