# A2.2 Thumb Biomechanics & Index Opposition — Theoretical Audit

Status: **historical forensic evidence (A2.2 visual FAIL confirmed).**
Canonical rules: `docs/EQUIPMENT_INTERACTION.md`. Do not rewrite the
measurements below. The counter-winding contract R1-R4 is necessary but
not sufficient: the achieved pose buys the correct winding with a
biologically impossible joint combination and aims the distal thumb at
the pinky side. Audit only — no implementation was changed.

All numbers measured live on the shipped A2.2 stack (Walking t = 0.35,
socket/fingers untouched) with a temporary probe (deleted after the audit).
Angles are in the shaft section plane (`e1`,`e2` ⊥ axis `D`, CCW positive);
`along` is the signed coordinate on the shaft axis (+D = head side);
`r` = grip radius 0.00388. Hand frame: `+across` verified to point toward
INDEX (dot(mcp_index − mcp_pinky, across) > 0), `longitudinal` toward the
fingertips, `volar` out of the palm.

---

## 1. First anatomically incorrect joint and premise

**First incorrect premise:** *"positive rotation about each thumb bone's
imported local X axis = anatomical flexion, with one shared sign `s` for
the whole chain."* Measured at the rest pose (section 5 below), the rig's
thumb has **mixed conventions**: MCP anatomical flexion is **−X** while IP
anatomical flexion is **+X**. A single scalar flexion sign can therefore
never pose this thumb anatomically: the canonical `(50)/(70)` under
`s = +1` flexes the IP correctly but bends the **MCP 50° dorsally** — the
visible backward knee.

**First anatomically broken joint (visible):** Thumb2/MCP — segment bend
**−45°** toward the nail side (hyperextension). **Deepest violation:**
Thumb1/CMC axial twist **+87°** — far beyond any human CMC (~20–40°
coupled pronation). The counter-winding of A2.2 was *purchased* with this
twist: the calibration optimized winding, meeting angle and gap, and the
euler sweep found the cheapest geometric solution, not an anatomical one.

## 2. Why R1-R4 produced a false PASS

R1 (winding sign), R2 (meeting angle), R3 (contact/clearance), R4
(approach) are all **chain-versus-axis** measures. None of them inspects
per-joint anatomy (flexion sign, twist, hyperextension) and none is aware
of the **along-axis** coordinate that identifies WHICH finger a station
belongs to. A chain that is twisted 87° at the CMC and hyperextended at
the MCP satisfies every one of them (measured: W +96, meeting 54°, gap
0.17r, approach radial −0.34r/axial 0.01 — all PASS).

## 3. Why the aggregate finger sector pulled the thumb the wrong way

- The R2 target was the mean radial direction of all four finger pads:
  **139.9°**, which is **20.2° ulnar of the index pad** (119.6°).
- Worse, R2 is a pure section-plane ANGLE: the fingers are separated along
  the axis (index pad along **+1.89r**, middle **+0.98r**, ring
  **+0.08r**, pinky **−1.28r**), and R2 never looks at `along`.
  A pose whose pad sits at the pinky's angle measures a meeting angle of
  **13.1° — deep PASS** under the old ≤ 70° gate.
- The achieved A2.2 pad sits at ang 85.8°, **along −0.70r — at the
  ring/pinky station**, and every thumb segment points ulnar
  (dot(across→index) = −0.77 / −0.42 / −0.20). Skinned distances (below)
  classify it TOWARD_PINKY. The angular meeting measure was satisfied
  while the thumb ran down-shaft toward the little finger.

## 4. Anatomical joint frames (derived, not imported)

Per joint: twist axis `t̂` = live segment direction; flesh direction from
the skinned cluster/pad ⊥ offset; flexion axis `f̂ = t̂ × flesh` (positive
rotation bends toward the flesh side); abduction `â = t̂ × f̂`. Ordered
(t̂, f̂, â) the frames are right-handed (det +1; the probe printed det −1
only because it evaluated the determinant in (f, t, a) column order).
Achieved-pose alignment (dot with D / across / volar):

| Joint | twist axis | flexion axis | flesh dir |
|---|---|---|---|
| Thumb1 (CMC) | (−0.65, −0.77, +0.37) | dot(D) −0.01 | volar +0.30, across +0.62 |
| Thumb2 (MCP) | (−0.41, −0.42, +0.91) | dot(D) −0.91 | volar −0.16, across −0.31 |
| Thumb3 (IP) | (−0.01, −0.20, −0.40) | dot(D) +1.00 | volar +1.00, across 0.00 |

The Thumb3 skinned cluster is entirely pad-side relative to the pad
direction (26/0 verts), so the pad marker remains a valid flesh reference.
Imported local Euler axes were characterized functionally by finite
differences (section 5) instead of being trusted as anatomy.

## 5. Finite-difference audit

**Rest-pose flexion-sign test (the decisive measurement).** Baseline
rest bends: MCP ≈ +49°, IP ≈ +91° toward flesh. Applying ±20° about each
joint's local X:

| Joint | X+ bend | X− bend | Anatomical flexion is |
|---|---|---|---|
| MCP (Thumb2) | +41.3° (less flesh-ward = extension) | +56.9° | **−X** |
| IP (Thumb3) | +97.7° (more flesh-ward = flexion) | +85.6° | **+X** |

**Per-axis response at the A2.2 pose** (15° steps; columns: Δvolar,
Δtoward-index, Δtoward-tips, Δradial-to-shaft in r; ΔW in deg):

```text
T1 X+: +0.45 +0.58 +0.09 +0.45  +0.1      T1 X-: -0.56 -0.45 -0.18 -0.54 -10.8
T1 Y+: -0.11 -0.00 +0.11 -0.11  +5.1      T1 Y-: +0.08 -0.02 -0.13 +0.09  -5.0
T1 Z+: +0.30 -0.10 -0.65 +0.45 -20.8      T1 Z-: -0.38 +0.25 +0.56 -0.28 +30.7
T2 X+: +0.08 +0.28 +0.13 +0.07  +3.1      T2 X-: -0.15 -0.25 -0.12 -0.14  -4.4
T2 Y+: -0.07 -0.16 -0.09 -0.07  -3.3      T2 Y-: +0.08 +0.17 +0.05 +0.08  +0.7
T2 Z+: +0.19 +0.06 -0.32 +0.24 -12.3      T2 Z-: -0.26 -0.01 +0.27 -0.24 +15.0
T3 X+: -0.02 -0.05 -0.02 -0.02  -0.7      T3 X-: +0.03 +0.04 +0.02 +0.03  +0.7
T3 Y+: +0.13 -0.14 +0.00 +0.13  +1.7      T3 Y-: -0.11 +0.14 -0.05 -0.10  -4.4
T3 Z+: +0.12 +0.12 +0.06 +0.12  +1.8      T3 Z-: -0.11 -0.10 -0.10 -0.10  -4.5
```

Readings: T1 Z is the dominant winding lever (∓21/+31° per 15°) but drags
the pad **away from the fingertips** (−0.65r per +15°) — the calibrated
Z = +80 is what pushed the chain down-shaft toward the pinky station.
T1 X+ is the "toward index" lever (+0.58r) — the canonical X = −60 pushed
**away** from index. IP X barely moves anything at this pose (pad orbiting
tangentially). The winding was created by CMC twist/aim, not by anatomical
flexion — "correct winding through the wrong joint combination".

## 6. A2.2 pose expressed anatomically

Swing–twist against the derived frames, and signed segment curvature
(positive = toward flesh):

| Joint | flexion | abduction | twist |
|---|---|---|---|
| Thumb1 (CMC) | +56.0° | −34.5° | **+86.8°** |
| Thumb2 (MCP) | **−37.4°** | +1.4° | −32.1° |
| Thumb3 (IP) | +57.2° | +30.2° | +24.1° |

Curvature: at MCP **−45.1°**, at IP **−107.0°** — both segments bend
**dorsally** (the backward knee; the IP figure sits in the strongly-curled
regime where the flesh-frame sign becomes less precise, but the MCP value
is robust). Every segment heads ulnar (dot across −0.77/−0.42/−0.20) and
the distal segment runs along the fingertip direction (+0.89) with the pad
at the ring/pinky along-station. Bone polyline (ang, along):
(−11°, +0.8r) → (11°, −0.1r) → (63°, −0.7r) → (86°, −0.7r); skinned
centroids agree ((−10, +0.8), (18, −0.2), (84, −0.7)) — bone and rendered
mesh give the SAME classification, so the bone-level verdict stands.

## 7. Thumb→finger distances and the direction classification

Skinned minimum distances from the thumb pad to each finger's phalanx
clusters (with section-angle and along-axis separations):

| Target | skinned min | Δang | Δalong |
|---|---|---|---|
| index | 2.36r | 34° | +2.59r |
| middle | 1.51r | 50° | +1.68r |
| ring | 1.02r | 65° | +0.78r |
| **pinky** | **0.95r** | 67° | −0.59r |
| index patch (near-shaft) | 2.80r | 72° | +2.51r |

Nearest-finger order: pinky, ring, middle, index →
**CLASSIFICATION: TOWARD_PINKY.** The angular numbers alone (34° to index)
would have looked fine — the along-axis and true 3D distances expose the
defect, matching the rendered image exactly.

## 8. Skinned index opposition target (replaces the aggregate sector)

Per-phalanx shaft stations (skinned, dominant-weight clusters; near-shaft
= verts with gap ≤ 0.6r):

| Phalanx | station (ang, along) | note |
|---|---|---|
| Index1 (proximal) | −143°, +1.63r (9 near-shaft verts) | far/dorsal side |
| Index2 (middle) | +157°, +1.89r | |
| Index3 (distal/pad) | +119°, +1.89r | pad contact |
| Middle1 (proximal) | −141°, +0.70r | |
| Middle3 (distal) | +137°, +0.96r | **at the thumb's own along-station** |

The index opposition target patch must be built from these index
(+ optionally index-side middle) surfaces — ring/pinky may not contribute.
Note the axial geometry: ALL index stations sit at along +1.6..+1.9r,
while the thumb's anatomical crossing region measured ±0.8r (section 10).

## 9. R2 audit verdict

- Sector composition: mean of four pad radials = 139.9°, 20.2° ulnar of
  index — the target itself leans toward ring/pinky.
- R2 is angle-only: a pinky-pointing pose measures 13.1° and PASSES ≤ 70.
- The achieved pad is 2.36r from index but 0.95r from pinky — closer to
  pinky, still PASS.
- **R2 must be replaced**, not tuned: new index-specific R2 = (a) target
  is the skinned index patch (+ index-side middle boundary at most),
  (b) signed direction toward index along `+across`, (c)
  dist(thumb→index) < dist(thumb→ring/pinky) in 3D skinned distance,
  (d) along-axis separation to the index patch bounded, (e) winding still
  opposite (R1 unchanged).

## 10. Proposed biomechanical contract R5–R9 (not implemented)

- **R5 anatomical flexion sign:** per-joint measured flexion direction
  (MCP = −X, IP = +X on this rig, from the rest-pose finite difference);
  achieved segment bends must be ≥ −10° (no hyperextension beyond a small
  tolerance). A2.2 measures −45/−107 → FAIL.
- **R6 consistent chain curvature:** both bends forward (no dorsal bend,
  no S: one bend strongly positive while the other strongly negative).
  The probe's provisional S-test (opposite-sign bends) missed the
  constructed S-case because both its bends measured dorsal — the
  implementation must evaluate curvature in one consistent bending plane
  rather than per-joint flesh frames.
- **R7 index-directed opposition:** the new R2 above (skinned index patch,
  across-sign, nearest-finger ordering, along-aware). TOWARD_RING /
  TOWARD_PINKY / TOWARD_WRIST always fail closed.
- **R8 joint roles:** CMC owns opposition/abduction (bounded twist);
  MCP/IP contribute flexion only — lateral swing and twist at MCP/IP
  bounded (measured A2.2: MCP twist −32°, IP abd +30° → FAIL).
- **R9 anatomical limits (rig-relative, in the derived frames):** CMC
  twist ≤ ~45°, MCP/IP twist ≤ ~25°, MCP flexion 0..~70° (anatomical
  sign), IP flexion 0..~90°, lateral deviation ≤ ~30°. A2.2 CMC twist
  +86.8° → FAIL.

Verdict per case (measured):

| Case | R1-R4 | R5-R9 |
|---|---|---|
| 1. A2.1 same-winding | FAIL (winding) | R5/R8/R9 FAIL |
| 2. A2.2 canonical (backward-knee, = cases 4/5/7/8: pinky-directed, twist-bought contact, passes old R2 at 54°, closer to pinky than index) | **PASS — false positive** | R5 FAIL (bends −45/−107), R7 FAIL (pinky nearest), R9 FAIL (twist 87°) |
| 3. Opposite winding, hyperextended IP | FAIL (gap only — fragile) | R5/R9 FAIL |
| 6. Anatomical flexion, no opposition | FAIL (meeting/parallel) | R5 FAIL |
| 9. Constructed S-chain | FAIL (gap only) | R5 FAIL (R6 as provisionally defined missed it — see R6 note) |
| 10. Anatomically correct index-directed candidate | — | **none exists at the current placement (below)** |

> **Correction note (2026-08-23, A2.3):** this audit's reachability search
> demanded thumb proximity to the index MESH (nearest-finger ordering with
> the pad close to index surfaces). That was too strong a requirement: a
> correct power grip may hold the shaft with the thumb while the fingers
> counter from the other side — the index patch defines the anatomical
> DIRECTION, not a mandatory collision target. It also converted world
> anatomical axes to bone-local space through the global REST basis; the
> correct space is the bone's current global POSE basis. With the corrected
> contract (thumb-to-SHAFT contact, direction classified by the pad's
> along-station, chain-based wrist test) and corrected axis space, the
> A2.3 step-A search found **58 anatomically valid counter-winding poses at
> the UNCHANGED socket** — the section-11 zero result and its socket-change
> recommendation are therefore superseded: no socket adjustment was needed.
> Historical measurements below are kept unmodified.

## 11. Is a correct pose reachable? — No, not at the current club placement

An anatomically-bounded search (T1 euler box ±80/±60/±60°, MCP/IP flexion
both signs up to 70°, requiring: counter-winding ≥ 45°, contact band,
chain-min ≥ −0.30r, volar clearance, bends ≥ −10°, CMC twist ≤ 45°,
MCP/IP twist ≤ 25°, index nearer than ring AND pinky) found
**0 feasible candidates** (5 488 poses). A relaxed reach-envelope pass
(winding ≥ 30°, no contact requirement) found **0 anatomical
counter-winding poses at all**: with anatomical joints, this rig cannot
wind the thumb opposite the fingers around the shaft *where the shaft
currently sits*. A2.1/A2.2 "achieved" it only via through-shaft paths or
the 87° CMC twist.

Geometric root: the socket's distal shift (+0.15 hand) and 12° obliquity
put the index-side contact stations at along **+1.6..+1.9r**, while the
thumb's anatomical crossing region is **−0.7..+0.8r** — an axial mismatch
of ~1–2.6r that no anatomical thumb pose can bridge (the outside path is
longer than the chain; the shortcut is through the shaft or via impossible
twist). Per the decision list: **the club placement must be adjusted for
the thumb** — shift the grip axis proximally along L (reduce/remove
`DISTAL_SHIFT_HAND`, possibly reduce `KAPPA_DEG`) so the index/middle
contact stations move ~1r toward the thumb's crossing region; the
Middle3/index-middle boundary station (+0.96r) already sits AT the thumb's
own along-station, so a modest proximal shift makes an INDEX_MIDDLE
meeting anatomically plausible, with TOWARD_INDEX as the calibration
target. The wrist and Walking do not need to change; the rig's thumb chain
is sufficient once the axial mismatch is removed. Caveat: the zero-result
is grid- and frame-definition-dependent (coarse 5 488-pose box,
flesh-frame anatomical classification); the next slice must re-run the
search after the placement change before locking conclusions.

## 12. Recommended next implementation (not started)

1. Adjust the socket axial placement for thumb reachability (drop or
   shrink `DISTAL_SHIFT_HAND`, re-validate finger gates — finger stations
   move with the socket, so the four-finger calibration must be re-pinned,
   which is a socket change and therefore a deliberate, separate slice).
2. Replace the single flexion sign with per-joint measured anatomical
   directions (MCP −X, IP +X) and re-derive the canonical pose inside
   R9 limits, with CMC doing opposition (twist-bounded) and MCP/IP doing
   forward flexion only.
3. Replace R2 with the index-patch contract (R7) and add R5/R6/R8/R9 as
   fail-closed gates; keep R1/R3/R4; degrade the old meeting-angle to a
   diagnostic.
4. Skinned mesh stays authoritative: classification from skinned
   distances and stations (bone polyline agreed with the mesh here, but
   the gate should read the mesh).
5. Negative regressions: the A2.2 canonical pose (must fail R5/R7/R9),
   plus the section-12 case table above.

## 13. Changed files

- Created: `A2_2_THUMB_BIOMECHANICS_THEORETICAL_AUDIT.md` (this document).
- Temporary probe `game/_tmp_a22_biomech_probe.gd` created and deleted.
- Nothing else: `power_grip_v1`, club attachment, preview, tests, A1,
  Walking, hand frame, socket, club normalization, production path,
  steering docs, decision log untouched. No commit.

## 14. Regression after cleanup

`slice a1`: 71 OK. `slice a2`: 149 + 57 OK (unchanged — the audit changed
no production code or tests).

---

`A2.2 visual FAIL confirmed; thumb-biomechanics and index-opposition contracts audited; implementation not started.`
