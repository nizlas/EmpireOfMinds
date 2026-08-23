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
- `uthana_a2_hand_grip_frame.gd` — anatomical right-hand frame
  `Basis(A, L, V)`, `V = A x L`, det +1 by construction; volar sign verified
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
`1.2r`, digit gaps 0.01–0.20r (all `refined`), coverage `194°`, opposition
`-0.9998`, wrist/forearm/left deltas exactly 0.

## Preview
`res://assets/prototype/3d/units/generated_warrior/uthana_a2/uthana_a2_walking_preview.tscn` (F6)

Keys: `1`/`2`/`3` speed, `Space` pause, `H` cycle body/palm/dorsal/thumb/tips
views, `G` grip on/off, `D` debug dots, `[`/`]` finger HUD. HUD shows frame
invariant status, encirclement coverage, thumb opposition, and per-finger
gap/penetration/refine-delta/classification.

## A1 baseline
`Visually accepted baseline; gait slightly strutting but acceptable for feasibility.`

## Known limitation
The production Meshy club path (`generated_warrior_equipment.gd` +
`one_handed_palm_frame.gd` with its det = -1 basis and the production test's
"club points grip->head along palm +Y" assertion) still carries the old
convention — fixing it is a separate proposed slice
(see `docs/EQUIPMENT_INTERACTION.md`).
