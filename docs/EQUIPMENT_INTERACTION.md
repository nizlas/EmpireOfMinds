# Equipment interaction pipeline (weapon grips)

**Status: PROPOSAL — pending project-owner approval.** Promoted from the A2
theoretical audit
(`game/assets/prototype/3d/units/generated_warrior/uthana_a2/A2_GRIP_THEORETICAL_AUDIT.md`)
per the steering-document change rule: no steering doc covered the reusable
animation/weapon-interaction contract, which previously lived only in slice
prompts. The A2 slice implements this contract in isolated `uthana_a2/*`
modules; production adoption is a separate slice.

## Scope

How procedurally generated weapons are attached to and gripped by generated
humanoids on the WorldMap path. Presentation-side only: grips never become
gameplay state, and gameplay never reads weapon transforms.

## 1. Anatomical hand grip frame (per rig, measured, never assumed)

For the right hand, from wrist + finger-root (MCP) bone positions:

- `L` (longitudinal) = normalize(mean(MCP index..pinky) − wrist)
- `A` (transverse) = normalize(MCP_index − MCP_pinky), Gram-Schmidt vs `L`
  (radial/index side positive; the LEFT hand flips the MCP ordering so the
  hand-specific sign lives in exactly one place)
- `V` (volar, out of the palm flesh) = `A × L`
- `Basis(A, L, V)` must have det = +1 (right-handed) — gated, exact

The volar sign is verified by two independent checks that must agree, else a
classified STOP (never a silent sign flip):

1. thumb-side: the thumb column lies on the +V side of the palm plane
2. skinned-mesh: the LBS flesh centroid near the palm centre lies on +V,
   computed with the same skinning transform as the pose being measured

## 2. Weapon grip frame (`melee_1h` compiler convention)

The normalize compiler emits a fully oriented grip frame: origin =
`primary_grip` (parent origin after normalize), +Y = shaft grip→head,
+X/+Z = measured elliptical cross-section axes, det +1. The head/active end
points toward the **radial (index/thumb) side** of the gripping hand —
explicit profile constant `MELEE_1H_HEAD_SIDE = "radial"`, never an
incidental axis sign.

## 3. Canonical power-grip socket mapping

- Shaft direction `D = normalize(A + tan(κ)·L)`, κ ≈ 10–15° (oblique palmar
  crease); socket +Y → `D`, +Z → volar component ⊥ `D`, +X = `D × Z` (det +1)
- Axis centre = palm centre + (≈1.2·grip radius)·`V` + (≈0.15·hand length)·`L`
- The socket has full 6-DOF freedom relative to the hand bone: holding never
  requires wrist changes. Carry believability is a separate future
  `one_handed_carry` post-animation overlay — the grip contract must not
  silently acquire wrist authority.

## 4. Grip policy: canonical pose + bounded refinement (hybrid, locked by A2)

- One authored canonical `power_grip_v1` pose per skeleton profile (the
  52-bone EoM profile is shared by all A1-retargeted humanoids), applied with
  the measured per-rig flexion sign
- Bounded per-digit radius refinement from measured pad gaps: flex delta
  clamped (±15°), capped iterations, best-so-far with backtracking; a failed
  refinement degrades to the canonical pose (classified), never free CCD
- Post-animation `SkeletonModifier3D`, deterministic, reversible, no frame
  accumulation; wrist/forearm/left hand deltas exactly 0

## 5. Mandatory gates (fail-closed, dimensionless in grip radius r)

Frame preconditions BEFORE any finger solving: det(+1) for palm basis /
socket / grip frame; volar dual-check agreement; `|dot(D,A)| ≥ 0.90` with
radial sign; `|dot(D,L)| ≤ 0.35`; `|dot(D,V)| ≤ 0.25`; volar offset in
`[0.4r, 2.2r]`; axis-centre containment; MCP projections strictly monotonic
along `D` with spread ≥ 0.6·knuckle breadth; per-finger hinge `|dot(D,hinge)|
≥ 0.80`; station reach in `[0.35, 0.95]`·chain length.

Contact gates AFTER solving, on ACHIEVED contacts (never solver targets):
per-digit pad gap ≤ 0.35r and penetration ≤ 0.20r; encirclement (angular
coverage of contact directions) ≥ 180°; thumb-vs-fingers radial opposition
dot ≤ −0.3; contact ordering monotonic along `D`; stability across animation;
determinism; OFF restores rest.

Scalar distance decrease alone is never a PASS criterion. Visual acceptance
stays a user F6 gate and is never claimable by automated tests.

## 6. Known production gap (separate proposed slice)

The production Meshy club path still uses the old convention:
`one_handed_palm_frame.gd` builds a det = −1 basis with an unverified normal,
and `test_generated_warrior_equipment.gd` asserts "club points grip→head
along palm +Y" (the exact defect A2 corrected). Migrating production to this
contract is proposed as its own slice and must not be done as a side effect.
