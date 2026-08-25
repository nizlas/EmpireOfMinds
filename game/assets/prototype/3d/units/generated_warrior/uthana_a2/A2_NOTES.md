# A2 — automated club attachment + procedural one-hand power grip

## Status
**Ongoing — hybrid correction implemented (audit-approved); automated
invariant+contact gate PASS. User F6 grip inspection still required.**
Two earlier grip generations (generic curl `cylindrical_grip_v1`, free-CCD
`contact_grip_v1`) were visually FAILED and are deleted; the full failure
analysis lives in `A2_GRIP_THEORETICAL_AUDIT.md`.

## Root causes (measured, from the theoretical audit)
1. Socket identity-mapped the club shaft onto the palm **longitudinal** axis
   (`dot(D,L) = 1.0`) instead of the transverse axis — the club lay along the
   fingers, so encirclement was geometrically unreachable.
2. Palm basis was left-handed (`det = -1`) — mirrored composed transforms.
3. Volar (flesh) side was mis-identified by an invalid probe — the shaft was
   offset onto the **back of the hand** and finger flexion was reversed.
4. Both automated gates measured orientation-blind scalar distances.

## Hybrid solution (implemented)
- `uthana_a2_hand_grip_frame.gd` — anatomical **right-hand** walking-preview
  frame `Basis(A, L, V)`, `V = A x L`, det +1 by construction; volar sign verified
  by two independent checks (thumb-side + pose-consistent skinned flesh
  extent asymmetry) that must agree, else classified STOP. The flesh check
  uses quantile extent difference along V (metacarpals lie dorsally, so skin
  reaches farther volar of the bone plane) — a plain centroid sign was
  knife-edge (~1e-5) and flipped with the animation pose, which fail-closed
  the real preview scene into a clubless warrior.
- `uthana_a2_club_attachment.gd` — canonical power-grip socket mapping:
  shaft `D = normalize(A + tan(12°)·L)` (head toward the radial side, explicit
  `head_side = radial` profile convention), centre = palm centre + `1.2r`
  volar + `0.15·hand_length` distal (oblique palmar crease). Hard audit
  Section 7 invariants gate the ACHIEVED socket fail-closed BEFORE any finger
  solving (`evaluate_grip_invariants`).
- `uthana_a2_power_grip.gd` (`power_grip_v1`) — canonical authored joint
  angles per finger chain + thumb opposition pose, numerically calibrated for
  the 52-bone profile; measured per-rig flexion sign; bounded per-digit radius
  refinement (±15°, capped iterations, best-so-far with backtracking, degrades
  to the canonical pose); post-animation, deterministic, reversible; wrist /
  forearm / left hand untouched.
- Test gates (`test_uthana_a2_club_attachment_grip.gd`): frame invariants
  before fingers, negative regressions (mirrored socket, shaft-along-L,
  dorsal offset must be REJECTED), achieved-contact gaps/penetration in grip
  radii, encirclement coverage >= 180°, thumb opposition dot <= -0.3,
  monotonic contact ordering, stability over Walking, determinism, OFF
  restore, A1 regression.
- Runtime scene gate (`test_uthana_a2_preview_runtime.gd`): loads the exact
  F6 `.tscn` in a live SceneTree, waits for init, then verifies the club node
  exists under `UthanaA2ClubAttachment/WeaponSocket_R/SocketOffset/WoodenClub`,
  is renderable/visible, has sane scale/AABB/transform, sits within one hand
  length of the palm, survives `G`/`H`, and that a broken club resource
  produces an explicit HUD init error instead of a silent weaponless preview.
  Grip math alone is NOT sufficient to pass A2.

## Measured result (headless, Walking t = 0.35)
`dot(D,A) = 0.978`, `dot(D,L) = 0.208`, `dot(D,V) = 0.000`, volar offset
`1.2r`, digit gaps 0.01–0.16r (all `refined`), coverage `222°` (v2 metric),
wrist/forearm/left deltas exactly 0.

## A2.7 ground-truth nail orientation + final thumb wrap (supersedes A2.5/A2.6 distal references)
> Implements the corrections of `A2_6_NAIL_SURFACE_GROUND_TRUTH_AUDIT.md`
> (2026-08-23). All A2.5/A2.6 nail/pad numbers below this section were
> measured against MISLABELED surfaces and are preserved as historical,
> explicitly superseded values.

User-visible defect in the accepted A2.6 grip: the true textured thumbnail
was not visible from the radial outside; the thumb read as twisted about a
quarter turn too far, while the automated gates reported `nail_out ≈ +0.98`.

**Root cause (audit):** the A2.5 patch identity was compiled from
brightness/low-saturation heuristics on a CW-authored mesh (authored cross
products point OPPOSITE the imported shading normals) with the a-priori
assumption that the nail faces exactly anti-volar. The compiled
`T3_NAIL_NORMAL_LOCAL` actually tracked dorsal knuckle skin ~67 deg away
from the true nail plate; the pad marker sat ~7 mm off on side skin. Every
"nail_out" ever reported by A2.5/A2.6 was a rigid projection of that wrong
constant — a false positive by construction. At the A2.6 pose the DEFORMED
skinned true nail plate measured `out +0.61 / axial 0.66` (axial-dominant:
the nail faced along the shaft) and the true pad plate penetrated to
−0.46r, while the old path claimed +0.98/+0.99.

**Fix (causal order):**
1. **Patch identity as profile metadata:** the texture-verified nail
   (4 tris) and pad (10 tris) patches — identified on the LEFT thumb where
   the nail texture is unambiguous, mirrored topologically onto the right
   — are compiled into `T3_NAIL_TRIS` / `T3_PAD_TRIS` (surface index,
   vertex ids, UV centroid, rest winding flip). Runtime never reads the
   albedo texture. `_bind_patches` fail-closes on bone-weight, UV and
   rest-normal mismatches. Old constants remain as `SUPERSEDED_A25_*`
   (diagnostics + false-positive regression only).
2. **Deformed geometry as ground truth:** `measure_thumb_surface_truth`
   CPU-skins the verified triangles at the ACHIEVED final pose (same bind
   matrices/bone poses as rendering), takes rest-anchored winding (no
   auto-flip), per-triangle local radials to the final shaft axis and
   area-weighted statistics; a pose stamp rejects stale measurements.
3. **Recalibrated canonical pose** (production path, visually confirmed
   via orbit renders BEFORE adoption): `CANON_THUMB_ANAT`
   `sigma 25 -> 20, tau -90 -> -60, MCP 0 -> 10, IP 90 -> 80` (phi 0
   unchanged). The audit's tau sweep showed A2.6's `tau -90` was 30-45 deg
   over-pronated for the true plate; MCP/IP stay pure flexion.

**Before/after (deformed skinned ground truth, Walking t=0.35, 1.0x):**
`nail_out_geom +0.61 -> +0.93`, `nail_axis_geom 0.66 -> 0.24`,
`pad_in_geom -> +0.30`, pad plate min gap `-0.46r -> -0.17r` (contact,
within skin tolerance), nail plate gap `+0.03r -> +0.39r` (clear of the
surface), physical distal roll `+1 deg`, closest patch = PAD. Wrap:
winding `Wt +86 vs Wf -73` (opposite), `TOWARD_INDEX`, CMC twist −59,
MCP +8.5 / IP +79 (pure flexion), no thumb-index contact required. Stable
at t = 0/0.35/0.52/1.01 and radii 0.9x/1.0x/1.1x (12/12 configs green).

**New fail-closed ground-truth gate** (`run_surface_truth_gate`, enforced
at equip after wrap + contour): `thumb_true_nail_patch_missing`,
`thumb_true_pad_patch_missing`, `thumb_nail_geom_faces_inward` (< 0.72),
`thumb_nail_geom_axial_to_shaft` (> 0.45), `thumb_pad_geom_faces_outward`
(< 0.25), `thumb_nail_is_contact_surface`, `thumb_pad_not_contact_surface`,
`thumb_distal_physical_roll_excess` (> 65 deg),
`thumb_measurement_pose_stale`, `thumb_patch_frame_mismatch`. Separators
sit between the measured A2.6 defect (+0.61/0.66) and the calibrated pose
(+0.93/0.24). The compiled-normal projections in the wrap gate remain as
cheap diagnostics only.

**Contour recalibration (honest classification):** the volar-flesh
classifier now uses the VERIFIED pad normal (~56 deg from the mislabeled
A2.5 reference), so the contour patches select different (honest) skin and
the old absolute bands are not comparable. Re-anchored on the visually
approved pose with 0.9x-radius margin: mid excess <= 1.25r, T2 median <=
1.55r, bulge <= 0.90r, kink <= 0.90r; T2 flesh may cross tangentially
(face dot > −0.85; only a flipped middle fails). Structural protections
(patch presence, distributed contact <= 0.30r, penetration >= −0.30r,
monotone winding, jump <= 100 deg) unchanged.

**Negative regressions:** the EXACT A2.6 pose (reconstructed via the
superseded frames) is rejected by the ground-truth gate by name while its
old compiled path still claims `nail_out >= 0.90` at the same pose —
proven false positive; plus analytic negatives for every new failure code
(nail inward/axial, pad outward, nail-as-contact, no pad contact, stale
pose, missing patches, frame mismatch) and a posed 150-deg distal twist
rejected by the GEOMETRIC gate. Why the old 259 checks false-PASSed: they
gated rigid projections of compiled constants, never the skinned surface.

**Preview:** `THUMB_DORSAL` now aims from the verified radial outside at
the TRUE nail patch station; `D` additionally draws the skinned nail
(magenta) / pad (cyan) triangles with their deformed aggregate normals,
the local radial (green) and shaft axis (yellow); the HUD adds a
`GeomTruth` line (NAIL_GEOM out/axis, PAD_GEOM in, gaps, physical roll,
closest patch, pose freshness, failure codes) re-measured every frame,
with the legacy compiled value shown as superseded diagnostic. Socket,
`DISTAL_SHIFT_HAND`, `KAPPA_DEG`, club normalization/radius/scale, hand
frame and the four fingers are untouched (pinned checks green).

## A2.6 distributed thumb contour contact (superseded by A2.7 — its nail/pad references were mislabeled)
User-visible defect in the accepted A2.5 grip: the distal pad reached the
shaft but the Thumb2/middle knuckle stood radially off it — a crooked /
polygonal silhouette instead of a continuous arc around the cylinder.

Measured A2.5 skinned volar gap profile (calibration probe, Walking
t = 0.35, gaps in grip radii, patch = dominant-weight volar-side vertices
per phalanx): `CMC 0.12r -> Thumb2 min 0.19r / MEDIAN 0.49r -> Thumb3
median 0.25r -> pad 0.18r`, isolated middle excess over the CMC-to-pad
contact corridor **0.34r** — the visible gap is the Thumb2/middle volar
surface. Root cause: the CMC swing sat 10 deg off the pure-flexion plane
(`phi 10`, `tau -95`), lifting the middle knuckle; the hypothesised
MCP-flexion redistribution is BLOCKED by the kept R4 approach gates beyond
~5 deg (measured: `thumb_approach_axial` from MCP >= 10 deg), so the
calibrated fix moves the CMC swing back into the flexion plane instead.

Pose change (everything else identical): `phi 10 -> 0`, `tau -95 -> -90`;
sigma 25, MCP 0, IP 90 unchanged. Result: T2 median **0.49r -> 0.33r**,
middle excess **0.34r -> 0.21r**, CMC contact 0.12r -> 0.11r, pad 0.14r,
raw pad gap inside the refinement comfort band (no CMC refinement delta at
nominal radius). A natural joint crease remains by design — the contract
never demands zero gap along the whole thumb.

New fail-closed contour gate (`measure_thumb_contour` +
`evaluate_thumb_contour`, skinned patches, shaft-frame quantities only):
distributed volar contact beyond the distal pad (min patch gap <= 0.30r),
no isolated middle gap above the interpolated contact corridor (excess <=
0.25r), no middle radial bulge (T2 median <= 0.42r, bulge over neighbour
medians <= 0.24r), no mid-chain penetration (>= -0.30r), monotone
correctly-signed angular progression CMC->T2->T3->pad (jump <= 100 deg),
no outward curvature kink (centroid chord offset <= 0.30r), middle volar
flesh facing the shaft. Failure codes:
`thumb_contact_only_at_distal_pad`, `thumb_middle_surface_gap_excess`,
`thumb_middle_radial_bulge`, `thumb_middle_penetration_excess`,
`thumb_contact_contour_discontinuous`, `thumb_surface_winding_nonmonotonic`,
`thumb_curvature_kink_outward`, `thumb_middle_pad_faces_outward`,
`thumb_contour_patch_missing`. Enforced at equip (rejected pose stays
visible for debugging, classified loudly as FAIL). The exact A2.5 pose
passes every pre-A2.6 gate and is rejected by the contour gate by name
(mid 0.34r, T2 median 0.49r). Stable across Walking times (mid 0.21r at
t = 0/0.35/0.52/1.01) and solver radii (0.23r/0.21r/0.19r at
0.9x/1.0x/1.1x). Socket, club normalization, hand frame and the four
fingers are untouched; R1-R10 all stay green.

Preview: new `THUMB_CONTACT` H-view (side-on, perpendicular to the shaft
axis and the Thumb2 radial direction — where the middle gap is most
visible); `D` draws the volar patches, colour-coded gap lines to the
nearest shaft-surface points, the CMC->pad corridor and the centroid
curvature polyline; HUD adds per-patch min/median gaps, middle excess,
bulge, kink, progression continuity and contour failure codes.

## A2.5 nail-referenced distal thumb orientation (supersedes A2.4's thumb)
> **Correction note (2026-08-23) to the A2.4 conclusion:** the low-poly tip
> lobe was real, but classifying the residual as an asset limitation was
> INCOMPLETE — the textured nail surface orientation was never measured.
> The user's visual comparison against the free hand's visible nail
> reopened the root cause. Historical A2.4 measurements stand unmodified.

Nail identification (calibration probe, one-off): the Thumb3-dominated
triangles were sampled against the albedo texture (dense barycentric
rasterization); the two bright/low-saturation distal plates were separated
by anatomy at the open rest hand — the plate facing exactly away from the
palm side (dot(volar) = **-1.00**) is the NAIL, the plate facing
volar-ulnar (+0.71 / -0.55) is the PAD pulp. Left/right thumbs have
separate UV islands (no shared topology), reported and handled per side.

Measured A2.4 defect (posed, verified normals): **nail_out -0.71** (nail
facing the SHAFT), **pad_in -0.60** (pulp facing outward), distal roll
-126 deg — the distal surface orientation was inverted even though winding
/gap/direction were green and the internally-defined IP twist read 0.

Root cause chain (first wrong frame): the generic thumb pad MARKER was
biased by the HAND volar normal, which is nearly orthogonal to the thumb's
own pad/nail axis — the marker sat on the SIDE of the phalanx. The
anatomical frames derived their flesh axis from that marker, rolling the
flexion axes ~95 deg (measured: our f-axis dot nail = +0.89, true-axis
angle error 95 deg); and the CMC twist budget (+/-25..45 deg) FORBADE the
~90 deg coupled opposition pronation a real thumb uses, so calibration
kept converging to rolled poses whose "contact" was measured at the side
marker.

A2.5 fix:
- Compiled, texture-verified distal surface frame:
  `T3_NAIL_NORMAL_LOCAL`, `T3_PAD_NORMAL_LOCAL`, and the pad marker
  re-bound onto the verified pad-plate centroid (`T3_PAD_MARKER_LOCAL`).
  Runtime never reads the texture; bind-time sanity fails closed
  (`thumb_distal_frame_invalid`) if the compiled plates are not opposed
  and transverse to the phalanx.
- All three thumb frames now take their flesh axis from the verified pad
  normal (projected per joint), removing the hidden ~95 deg roll.
- Canonical pose includes the opposition pronation: sigma 25, phi 10,
  **tau -95 deg** (CMC pronation; budget raised to 100 deg for the CMC
  ONLY — a real opposition measures ~90 — while MCP/IP twist stays <= 25),
  MCP 0, IP 90.
- Achieved: **nail_out +0.98, pad_in +0.63..0.81, nail_axis <= 0.21,
  distal roll ~ +29 deg**, gap 0.15-0.18r, W +86..+94, TOWARD_INDEX,
  robust over Walking times and radii 0.9/1.0/1.1.
- New fail-closed R10 gates: `thumb_nail_faces_inward`,
  `thumb_nail_axial_to_shaft`, `thumb_pad_faces_outward`,
  `thumb_surface_orientation_inconsistent`, `thumb_distal_roll_excess`
  (thresholds midway between the measured A2.4 defect and the corrected
  pose). Negative regressions: the measured A2.4 orientation (all old
  metrics green -> nail gate rejects by name), nail along +/-D, correct
  nail without shaft contact, distal twist hiding the nail, extreme CMC
  twist beyond the pronation budget (tau -130).
- Preview: new `THUMB_DORSAL` H-view (from the radially-outer side where
  the nail must be visible); HUD shows nail-out/axis/pad-in/roll and a
  NAIL classification line.

## A2.4 residual thumb-tip silhouette correction (superseded by A2.5)
Viewed along the shaft axis, A2.3 exposed a small isolated flesh lobe at
the thumb tip. Root cause: **combination (E)** — a pose component (all
distal bend concentrated in the IP at 80 deg with MCP 0; class A) on top
of a skinning/topology component (class C): the distal Thumb3 cluster is
~26 low-poly verts whose tip flesh has no covering neighbour flesh in its
angular window, and the tip knuckle hovers ~0.5-0.65r off the shaft across
the ENTIRE anatomical range (MCP 0-25, IP 45-80, CMC +/-5) — it cannot be
posed away without opening the grip (lower IP fails the pad-gap and
radially-outward approach gates; measured, not assumed).
- A2.4 canonical (minimal local change, socket/fingers untouched):
  sigma 20 -> 17.5, phi 90 -> 94, tau 20 -> 23, MCP 0 -> 5, IP 80 kept.
  Skinned tip isolation 0.206r -> 0.166r, distal max radial 1.70r ->
  ~1.6r, achieved W +73.5, TOWARD_INDEX (along_n 0.80), CMC twist 22.7,
  gap 0.11r, pen 0; robust over Walking times and radii 0.9/1.0/1.1
  (gap 0.17/0.11/0.01r).
- The tip-isolation metric (max excess of high-weight Thumb3 tip verts
  over the outer envelope of other thumb flesh within +/-20 deg, shaft-
  axis projection) is a shared DIAGNOSTIC (`measure_tip_isolation`), NOT a
  hard scalar gate: the pose/skinning components have no sharp separation,
  so the test asserts the RELATIVE regression (A2.4 pose measures lower
  than the A2.3 pose in the same run) and the preview HUD classifies the
  residual as SMOOTH / MILD (low-poly asset limit) / ISOLATED.
- New negative regressions: IP 45 opens the grip (pad-gap/approach FAIL);
  distal +40 deg axial twist (nail toward shaft) fails R9 ip-twist.
- New H-view THUMB_AXIS: camera along the shaft toward the hand — the
  silhouette view that exposed the defect. HUD adds IP twist and the tip
  lobe classification.
- Remaining hover is documented as a known asset limitation of the
  generated warrior mesh (not fixable in pose space; GLB unchanged).

## A2.3 anatomical thumb-to-shaft power grip (supersedes the A2.2 thumb)
A2.2's counter-winding thumb was bought with a +86.8 deg CMC twist and a
backward-bent MCP (audit `A2_2_THUMB_BIOMECHANICS_THEORETICAL_AUDIT.md`).
A2.3 implements the anatomical contract with the corrected premise that
the thumb holds the SHAFT (the index patch is a direction reference, not a
collision target):
- **Socket UNCHANGED** (step-A search at the exact current socket found 58
  anatomically valid counter-winding poses once thumb-to-index contact was
  dropped and the axis space fixed; distal shift +0.15h, kappa 12 deg,
  dot(D,A) 0.9781, volar offset 1.20r and ALL four-finger pins are
  bit-identical to A2.1/A2.2).
- Thumb pose is authored ANATOMICALLY and compiled at bind: CMC swing
  sigma=20 deg about phi=90 deg in the measured (flexion, abduction) plane
  + tau=20 deg bounded twist; MCP 0 deg, IP 80 deg flexion about per-joint
  EMPIRICALLY VALIDATED axes (this rig: MCP anatomical flexion = -X,
  IP = +X — the single shared flexion sign was the A2.2 root cause). Axes
  are derived at the rest pose from segment directions + skinned flesh
  side, converted through the bone's current global POSE basis, and
  flip-corrected by a finite-difference bend test; ambiguity fails closed
  (`thumb_flexion_axis_underivable`, `finger_winding_ambiguous`,
  `thumb_canonical_not_counter_winding`).
- Achieved (t=0.35): W_thumb +75.2 vs finger median -72.6 (R1), direction
  TOWARD_INDEX at along-station +1.50r (index 1.89, middle 0.98; along_n
  0.79), shaft gap 0.15r / pen 0, chain min +0.09r, CMC twist 19.7 deg,
  MCP flex 0 / IP flex 80 (no hyperextension, no S), approach axial 0.29 /
  radial +0.07r. Thumb-to-index pad distance 1.12r — a PASS with NO finger
  contact, proving separate thumb-to-shaft + finger counter-hold contacts.
- Gates: R1 winding, R3 contact (axial-lying discriminator moved 0.60 ->
  0.70: it rejects the A2.1 lying thumb at 0.93 while correct anatomical
  chains measure 0.32-0.63; anatomy is now owned by R5-R9), R4 approach,
  R5 per-joint anatomical flexion (hyperextension <= -10 deg fails),
  R6 no S-chain (opposite MCP/IP anatomical flexion signs), R7 direction
  classification (TOWARD_INDEX / INDEX_MIDDLE allowed; RING/PINKY/WRIST/
  AMBIGUOUS fail; wrist test on the WHOLE chain base->pad, since a fully
  flexed distal phalanx naturally points proximally), R8 no MCP/IP lateral
  compensation, R9 joint limits (CMC twist <= 45, MCP/IP twist <= 25).
  Old R2 meeting-angle, radial/opposition dots and unsigned wrap remain
  DIAGNOSTICS only.
- Robust across Walking t=0.00/0.35/0.52/1.01 and solver radii 0.9/1.0/1.1
  (gap 0.20/0.15/0.04r, pen 0). Runtime fail-closed: a failing profile
  keeps the pose visible but equips REJECTED with explicit failures and a
  red "GRIP REJECTED — debug view only" HUD banner.

## A2.2 counter-winding thumb (superseded by A2.3)
A2.1's thumb passed 185 checks but wound the SAME angular direction as the
fingers (audit: `A2_1_THUMB_OPPOSITION_THEORETICAL_AUDIT.md`). A2.2
implements the audited opposition contract:
- Canonical pose `(-60,30,80)/(50)/(70)`: signed winding **+96.4 deg**
  against the finger median **-72.6 deg** (index -102.2, middle -82.5,
  ring -62.6, pinky -60.0); pad at +86 deg meets the finger-pad sector
  (139.9 deg) at 54 deg; approach radial -0.34r (closing), tangential
  +0.64r along the winding, axial fraction 0.01; gap 0.17r, pen 0,
  chain min -0.05r, `refined`.
- Thumb flexion sign is DERIVED per rig (no index borrow): the sign whose
  canonical pose winds opposite the fingers AND whose flexion response
  drives the sweep further in that direction (measured dW at +40 deg IP
  probe: +7 for s=+1, -14 for s=-1). Fail-closed classes:
  `thumb_both_signs_same_winding_as_fingers`,
  `thumb_sign_perturbation_too_small`, `thumb_winding_sign_underivable`,
  `finger_winding_ambiguous`.
- Gates R1-R4 (fail-closed at equip, `THUMB_OPPOSITION_GATE_FAILED`; the
  failed pose stays visible in the preview but is loudly classified FAIL):
  R1 opposite winding (|Wt| >= 60, each |Wf| >= 45), R2 meeting <= 70 deg,
  R3 contact/through-shaft/through-palm/backward-bend/axial-lying
  (unchanged thresholds), R4 approach (axial fraction <= 0.60, radial
  <= +0.15r).
- DEGRADED TO DIAGNOSTICS (reported, never gated): `radial_dot_vs_fingers`
  and `opposition_dot` (the old gate would REJECT the correct pose: it
  measures +0.59 now), unsigned `|wrap|`, encirclement coverage
  (explicitly thumb-independent; 326 deg with the new thumb, and >= 180
  even with no thumb at all via the palm patch).
- Negative regressions: the exact shipped A2.1 pose must fail
  `same_winding_as_fingers` while ALL its old metrics are green; plus old
  axial, transverse same-winding, opposite-sector same-winding, large
  |wrap| wrong sign, opposite-but-far (exact R2), through-shaft seed,
  axial-approach, mirrored chirality (PASS invariance), zero-gap without
  counter-grip.
- Four fingers and socket pinned numerically (contact angles
  119.6/135.7/151.0/152.9 +/-2 deg, dot(D,A) 0.9781 +/-0.005, volar offset
  1.20r +/-0.02) — unchanged from A2.1.

## A2.1 thumb wrap correction (superseded by A2.2)
The first accepted A2 thumb scored opposition `-0.9998` yet lay ALONGSIDE
the shaft: the scalar opposition dot only measures the pad's radial side,
not the chain direction. Measured defect: `|dot(chain,D)| = 0.933`,
transverse/axial `0.38`, wrap `-31°`. Fix (sweep-calibrated canonical pose
`(-65,-16,30)/(60)/(72)` + CMC-dominant bounded refinement with measured
adduction sign): `|dot(chain,D)| = 0.50`, transverse/axial `1.72`, wrap
`-100°`, pad gap `0.16r`, pen `0`, `refined`. New fail-closed thumb-wrap
gate (axial dot <= 0.60, T/A >= 1.2, |wrap| >= 45°, pad on opposed side,
no through-shaft/through-palm, IP flexion >= 0) is enforced at equip — a
failing thumb removes the club and surfaces a HUD error. Negative
regression: the old axial pose (low gap + green opposition scalar) is now
rejected by name. Robust across the whole Walking loop (grip is
hand-relative, metrics time-invariant) and across solver radii 0.9–1.1x.
Encirclement metric corrected to v2: all contacting chain samples (with the
measured per-rig flesh offset, median distal-joint-minus-pad gap ~0.3r) plus
the palm patch derived from the achieved volar offset; the pads-only metric
under-reported true encirclement (129°) once the thumb correctly crossed to
`-110°`, while its old 194° depended on the DEFECTIVE thumb. Threshold
unchanged (>= 180°); v2 measures 222°.

## A2.8 — reusable bilateral pipeline (partial architecture promotion)

A2.8 established the bilateral profile/API and demonstrated right-hand
generic-path parity plus left anatomical derivation. It is **not** a
completed bilateral runtime proof.

- Intended owners: `game/presentation/equipment/` (`HumanoidHandProfile`,
  grip geometry, `power_grip_1h_v1`, solver façade, assembler).
- At A2.8 time the accepted F6 walking preview still used
  `uthana_a2_club_attachment.gd`; **superseded by A2.9** (see below), which
  proved assembler parity and migrated the preview.
- Left-hand support uses the same API: radial = that hand’s index side,
  volar from thumb + skinned flesh, det +1 triad, independently compiled
  left nail/pad patches. Bilateral diagnostic:
  `uthana_a2_bilateral_preview.tscn` (RIGHT vs LEFT side-by-side).
- Left full assemble on this asset fail-closes A2.6 T2 contour
  (`thumb_middle_penetration_excess`). That is the next-slice **blocker**,
  not a copied right-hand quaternion and not a reason to weaken gates.
  See `docs/EQUIPMENT_INTERACTION.md`.

## A2.8b — knowledge preservation

Canonical hand-surface rules live in `docs/EQUIPMENT_INTERACTION.md`
(“Hand-surface ground truth and lessons from the A2 power-grip proof”).
This warrior’s versioned patches, rejected A2.6 `tau = -90°` vs accepted
A2.7 `tau = -60°`, rest-winding and bind-sanity live in
`uthana_warrior_hand_fixture.gd`. The A2.1–A2.7 audits below remain
historical evidence; their measured failures are not rewritten. Generic
`HumanoidHandProfile` requires an injected fixture and does not silently
reuse this warrior’s triangle IDs.

## A2.9 — generic ownership inversion + accepted-preview migration

The power-grip engine now lives in
`res://presentation/equipment/power_grip_1h_engine.gd` (mechanical move —
no math, pose, socket or threshold changes); CPU skinning in
`skinned_mesh_geometry.gd`; melee normalize/shape in `melee_1h_normalize.gd`
/ `melee_grip_shape.gd`. The `uthana_a2_*` scripts are compatibility shells:
`uthana_a2_power_grip.gd` only carries the A2.7 right fixture constants and
legacy fallback seams; `uthana_a2_melee_1h_normalize.gd` only owns the demo
club SELECTION. `uthana_a2_equipment_composition.gd` is the composition
root injecting Mixamo-52 family + Uthana fixture + wooden club + engine
into the generic `EquipmentAssembler`.

The F6 walking preview (`uthana_a2_walking_preview.tscn`) runs the GENERIC
assembler as its runtime equipment owner (HUD shows
`owner: EquipmentAssembler (generic)`; H/G/D/Space/1-2-3/[ ] preserved; the
debug layer moved into the preview). The legacy
`uthana_a2_club_attachment.gd` path is kept ONLY as the live parity /
diagnostic reference: `test_uthana_a2_power_grip_parity.gd` (773 checks)
proves legacy-vs-generic parity over 4 Walking times × 3 grip radii with
the deformed surface-ground-truth gate at all 12 points, ±137° yaw
invariance, determinism and reversibility — tight float tolerances, not
the acceptance bands.

Left is unchanged: DERIVED BUT FULL ASSEMBLE NOT ACCEPTED (classified
T2 contour fail-closed). No per-unit fixture compiler exists yet.

## Preview
`res://assets/prototype/3d/units/generated_warrior/uthana_a2/uthana_a2_walking_preview.tscn` (F6)

Runtime equipment owner since A2.9: the generic `EquipmentAssembler`
(Uthana composition root); the HUD title line shows
`owner: EquipmentAssembler (generic)`.

Keys: `1`/`2`/`3` speed, `Space` pause, `H` cycle
BODY/PALM/DORSAL/THUMB/TIPS/THUMB_AXIS/THUMB_DORSAL/THUMB_CONTACT views,
`G` grip on/off, `D` debug dots + contour gap lines, `[`/`]` finger HUD.
HUD shows frame invariant status, encirclement coverage, thumb opposition,
the A2.6 contour block, and per-finger
gap/penetration/refine-delta/classification.

## A1 baseline
`Visually accepted baseline; gait slightly strutting but acceptable for feasibility.`

## Known limitation
The production Meshy club path (`generated_warrior_equipment.gd` +
`one_handed_palm_frame.gd` with its det = -1 basis and the production test's
"club points grip->head along palm +Y" assertion) still carries the old
convention — fixing it is a separate proposed slice
(see `docs/EQUIPMENT_INTERACTION.md`).
