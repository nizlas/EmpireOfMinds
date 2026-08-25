# A2 Grip — Theoretical Audit (anatomical power grip for procedurally generated weapons)

Status: **historical forensic evidence (read-only planning/architecture audit
at the time of writing).** Canonical contract: `docs/EQUIPMENT_INTERACTION.md`.
Do not rewrite the measurements below. A2.7 later implemented the hybrid;
A2.8b preserved the causal rules. Green automated tests must NOT be read
as visual success.

Baseline cited from this session's runs (2026-08-22): `slice a1` 71 checks OK,
`slice a2` 67 checks OK. Fresh baseline re-runs are step 0 of the next
implementation slice (the a1 test rewrites `A1_RETARGET_NOTES.md` and re-extracts
the Walking library as side effects, so it was not re-run inside this audit).

---

## 1. Executive verdict

The failure is **not** a finger-solver problem. The weapon is attached in an
anatomically impossible orientation, and both grip generations then tried to
solve fingers inside that impossible premise:

1. **Primary defect — weapon/socket orientation convention.**
   `WeaponSocket_R` identity-maps the club's canonical shaft (+Y after
   normalize) onto the palm frame's **longitudinal** axis (+Y = wrist→knuckles).
   Measured: `dot(weapon_axis, palm_longitudinal) = 0.99999988`. A cylindrical
   power grip requires the shaft ≈ parallel to the palm **transverse** axis
   (index↔pinky). Measured: `dot(weapon_axis, palm_transverse) = −0.0000002` —
   maximally wrong (90° off). The club lies along the fingers, like a splint,
   which is why fingers "wrap" along the shaft instead of around its
   cross-section. This convention was inherited from the production Meshy club
   path and is codified in a green production test
   (`test_generated_warrior_equipment.gd`: *"club points grip→head along palm +Y"*).

2. **Secondary defect A — the palm basis is left-handed (det = −1).**
   `one_handed_palm_frame.gd` builds `palm_basis = Basis(across, longitudinal,
   normal)` with `normal = longitudinal × across`. For any orthonormal pair this
   yields `det = across · (longitudinal × (longitudinal × across)) =
   across · (−across) = −1`. Numerically confirmed with the measured Uthana
   axes. Every composed socket transform therefore mirrors the club and flips
   all chirality-dependent reasoning (wrap angles, thumb side).

3. **Secondary defect B — the volar (flesh) side was mis-identified.**
   The flesh-side probe was invalid twice over: its 0.08 sampling radius is
   ≈ 4× the hand size at preview scale (it averaged forearm mass), and it mixed
   bind-pose vertex positions with a posed palm centre. First-principles
   anatomy (`volar = across × longitudinal` for a right hand) and the measured
   thumb-pad position (on the **−code-normal** side of the palm plane) both show
   the code's `+normal` is **dorsal**. The contact-grip correction therefore
   offset the shaft onto the **back of the hand** and reversed finger flexion to
   −X (**hyperextension**) so pads could "reach" it — the visually absurd
   backwards thumb and the false contact PASS.

4. **Gate defect — both automated gates were orientation- and chirality-blind.**
   They measured scalar distances (tip→point, pad→surface) that are satisfiable
   in any weapon orientation, validated solver-generated *targets* instead of
   achieved contacts, and never required encirclement of the cross-section.

**Verdict: PROCEED WITH HYBRID** (canonical authored power-grip pose + small
constrained contact refinement), after the weapon→hand frame mapping and the
two palm-frame defects are fixed and hard anatomical invariants are gated
*before* any finger solving. The rig contract is sufficient (52-bone profile,
complete right-hand finger chains with verified names; flexion sign measured).

---

## 2. Anatomical right-hand frame from first principles

All quantities from Uthana global rest/pose bone positions (preview scale 0.30,
Walking t = 0.35 for live values). Notation: unit vectors with hats.

### Definitions (right hand)

| Axis | Formula | Meaning |
|---|---|---|
| Longitudinal `L̂` | `normalize(mean(MCP_index..pinky) − wrist)` | wrist → knuckles, along the extended fingers |
| Transverse `Â` | `normalize(MCP_index − MCP_pinky)`, then Gram-Schmidt vs `L̂` | across the palm, radial (index) side positive |
| Volar normal `V̂` | `Â × L̂` | out of the palm flesh (grip side) |
| Dorsal normal | `−V̂` | back of the hand |
| Forearm axis `F̂` | `normalize(wrist − elbow)` | distinct from `L̂` (wrist flexion separates them) |

**Cross-product order and handedness.** `Basis(Â, L̂, V̂)` with `V̂ = Â × L̂`
has determinant `Â · (L̂ × V̂) = Â · (L̂ × (Â × L̂)) = Â · Â = +1` — right-handed.
For the **left** hand, use `Â_left = normalize(MCP_pinky − MCP_index)` so that
`V̂_left = Â_left × L̂_left` again points volar with det +1; hand-specific sign
lives in one place (the MCP ordering), not scattered through downstream code.

**Sign verification (must be gated, never assumed):**

1. *View-coordinate anatomy:* right palm toward viewer, fingers up: index is to
   the viewer's right of pinky, so `Â = +X_view`, `L̂ = +Y_view`, and
   `Â × L̂ = +Z_view` = toward the viewer = volar. Correct.
2. *Thumb-side check (measured):* the thumb column lies volar-radial. Measured
   thumb pad − palm centre = `(0.0097, −0.0058, 0.0088)`; dotted with the code
   normal `N_code = L̂ × Â` gives **−0.0080** → the thumb is on the −N_code
   side → `N_code` is dorsal, `V̂ = Â × L̂ = −N_code` is volar. Confirms (1).
3. *Skinned-mesh check (for the gate, not yet run correctly):* mean of skinned
   palm vertices within `0.5·hand_length` of the palm centre, computed with the
   same LBS transform as the pose being measured — the A1 sole-grounding helper
   (`uthana_a1_skinned_sole_ground.gd::skinned_vertex_world`) is the correct
   primitive. The previous probe did not use it; its result (+0.064 along
   N_code) is invalid (radius 4× hand size; bind-pose verts vs posed centre).

### Measured Uthana values (Walking t = 0.35, world/preview space)

```
wrist              W = (-0.069626,  0.009602, -0.006794)
knuckle centre     K = (-0.076725, -0.004442,  0.002875)      |K−W| ≈ 0.0185
L̂  (longitudinal)   = (-0.384408, -0.760384,  0.523494)
Â  (transverse)      = ( 0.541177,  0.273796,  0.795087)
N_code = L̂ × Â      = (-0.747902,  0.588941,  0.306253)   ← DORSAL (sign error)
V̂  (volar) = Â × L̂  = ( 0.747902, -0.588941, -0.306253)
dot(L̂, Â) ≈ 0.0000        (orthogonalized)
det Basis(Â, L̂, N_code) = −1   ← current code (left-handed, mirroring)
det Basis(Â, L̂, V̂)      = +1   ← required
```

**Forearm axis:** RightHand rest rotation relative to RightLowerArm is
(0°, −90°, 0°) — a pure Y rotation, so hand +Y coincides with forearm +Y in
rest: `F̂ ≈ L̂` in rest pose, hence `dot(weapon_axis, F̂) ≈ 0.99+` in the current
pose (rest-derived estimate; exact live capture is in the next-slice
diagnostic list). The club is approximately a **forearm extension** — a spear
through the fist, not a held club.

---

## 3. The correct cylindrical power-grip frame

In a hammer/power grip the shaft crosses the palm obliquely: distal at the
index MCP, proximal toward the ulnar/pinky side (the oblique palmar crease).

**Target weapon axis** (grip → active/head end):

```
D̂_target = normalize(Â + κ·L̂),   κ = tan(10°..15°) ≈ 0.18..0.27
```

with the **head/active end toward the radial (index/thumb) side** — an explicit
`melee_1h` profile convention (`head_side = radial`, like carrying a hammer),
never an incidental axis sign.

**Axis centre**: on the volar side of the bone palm plane,

```
C = P_palm + h·V̂,   h ≈ palm flesh offset + grip radius r  (gate band 0.4r..2.2r)
```

**Requirements, stated against the frame:**

- `|dot(D̂, Â)| ≥ 0.90` — shaft ≈ transverse (diagonal budget included)
- `|dot(D̂, L̂)| ≤ 0.35` — never along the fingers
- `|dot(D̂, V̂)| ≤ 0.25` — never stabbing through the palm
- per-finger stations along `D̂`, strictly monotonic index → pinky
- each finger flexes in a plane ⊥ its MCP hinge axis; MCP hinge axes are ≈ ∥ Â
  ≈ ∥ D̂_target, so the flexion planes **cut the shaft cross-section** — this is
  the geometric reason the shaft must be transverse: encirclement is only
  possible when the cylinder axis is ≈ perpendicular to the flexion planes
- thumb approaches from the opposite side of the cross-section and closes the
  loop (opposition), on the volar-radial side

**Axis vocabulary and what the implementation confused:**

| Concept | Correct meaning | What A2 did |
|---|---|---|
| Weapon long axis | shaft direction `D̂` | correct on the weapon side (+Y canonical) |
| Palm longitudinal | wrist→knuckles `L̂` | **used as the shaft direction** (socket +Y) |
| Palm transverse | index↔pinky `Â` | unused for orientation |
| Palm normal | volar `V̂ = Â × L̂` | built as `L̂ × Â` (dorsal) and later "verified" by an invalid probe |
| Finger flexion direction | −V̂ closing motion, +X local bone flexion (measured) | v2 reversed to −X (dorsal hyperextension) |
| Weapon radial/front (`up_axis`/`front_dir`) | should be the palm-facing contact direction | arbitrary `Vector3.BACK` hint, treated as meaningful |

---

## 4. Numeric measurement of the current failure

Session diagnostic (Walking t = 0.35, grip OFF, pre-"flesh-offset" geometry
unless noted):

| Quantity | Measured | Anatomical requirement |
|---|---|---|
| `dot(D̂, L̂)` | **0.99999988** | ≤ 0.35 |
| `dot(D̂, Â)` | **−0.0000002** | ≥ 0.90 in magnitude |
| `dot(D̂, N̂)` | 0.0000002 | ≤ 0.25 in magnitude |
| `dot(D̂, F̂)` | ≈ 0.99 (rest-derived) | small/moderate |
| axis↔palm lateral offset (v1) | 0.0000 (axis exactly through bone palm plane) | volar offset 0.4r..2.2r |
| axis volar offset (v2 "fix") | **−0.00388 along V̂** (dorsal: sign flipped by the invalid probe) | +0.4r..+2.2r along V̂ |
| `det(palm_basis)` | **−1** | +1 |
| `det(weapon normalize basis)` | +1 | +1 |
| composed socket/club world det | **−1** (mirrored render) | +1 |
| MCP projections onto D̂ | degenerate (D̂ ⊥ Â ⇒ spread ≪ knuckle breadth, non-monotonic) | strictly monotonic, spread ≥ 0.6·breadth |
| `FINGER_ALONG` stations (±0.016) | spread the four finger targets **along the finger direction** | along the transverse shaft |
| finger flexion sign (v2) | −X = dorsal hyperextension (measured +X is volar) | +X volar flexion |
| thumb opposition | targets-only check; achieved pose bent backwards | achieved contacts opposed ≥ 180° |

**Transform-chain first-failure trace:**

1. Club raw mesh axes — OK (Y long, det +1, verts 1434/tris 1080).
2. Normalizer (`uthana_a2_melee_1h_normalize.gd`) — OK as canonicalization
   (grip→origin, shaft→+Y, dual-hypothesis grip end, det +1) but **incomplete**:
   emits a point + shaft axis + placeholder front (`front_hint = Vector3.BACK`),
   not a fully oriented grip frame with an anatomically meaningful radial
   direction and a head-side convention.
3. `primary_grip` point — OK.
4. **Weapon/socket alignment — FIRST ANATOMICAL BREAK.** Socket = palm frame;
   `SocketOffset = identity`; canonical weapon +Y lands on palm +Y
   (longitudinal). Inherited from the production Meshy path.
5. Palm frame — axes correct as descriptors, but det −1 (defect A) and volar
   sign unverified/false (defect B) make it unsafe as an attachment frame.
6. Animation pose — not at fault.
7. Post-animation grip modifiers — attacked fingers inside an impossible
   premise. v1: correct volar flexion (+X) but open hook in the air (axis on
   the bone plane, shaft along fingers). v2: dorsal shaft offset + reversed
   flexion to "reach" it — contact numbers passed, anatomy destroyed.

**Why a finger CCD/contact solver cannot rescue a mis-oriented weapon:** the
weapon's orientation is a global 2-DOF property of the socket frame; finger
joints cannot change it. Finger chains flex in near-parallel planes ⊥ Â. A
shaft ∥ L̂ lies *inside* those planes, so every reachable contact collapses
onto essentially one line on the cylinder (one generatrix) — the encirclement
condition (contacts distributed ≥ 180° around the cross-section with the thumb
opposed) is **geometrically unreachable** regardless of solver quality,
iterations, or tolerances. The solver can only fake scalar contact, which is
exactly what happened.

---

## 5. Why two automated gates produced false PASSes

**Gate v1 (`cylindrical_grip_v1`)** passed on: mean fingertip distance to the
`primary_grip` *point* decreasing, plus mean tip motion along −N_code. Curling
fingers toward the palm satisfies both **in any weapon orientation** — the
metric never referenced the weapon axis direction at all. The "thumb opposite"
check compared solver-*constructed targets* (opposite by construction), not
achieved poses — self-referential.

**Gate v2 (contact)** passed on: per-finger pad→surface distance to an
elliptical cylinder ≤ tolerance. With the shaft running parallel beneath the
finger chains, every pad starts ≈ one radius away and any flexion (even
backwards) touches the surface. Distance-to-surface is **orientation-blind**:
a cylinder along the fingers is exactly as "touchable" as one across the palm.
No gate measured `dot(D̂, Â)`, monotonic MCP ordering along D̂, angular coverage
around the cross-section, or the volar sign of the offset. The
`palm_offset_after ≈ radius` gate confirmed the offset *magnitude* while the
*sign* was wrong (dorsal), because the sign came from the invalid flesh probe.
Frame determinants were checked for the weapon triad only — never for the palm
basis or the composed socket (both −1).

**Meta-lesson:** every gate validated a *scalar consequence* of a grip instead
of the *frame preconditions* of a grip. Anatomical invariants must gate the
frame **before** any finger metric is allowed to count.

---

## 6. Strategy comparison

### Strategy A — canonical authored grip pose

An anatomically correct `power_grip_v1` (fixed joint angles per finger chain,
thumb opposition; authored once for the EoM/Uthana 52-bone skeleton profile).
Weapon snaps to the hand by a full grip-frame mapping; the pose is reused for
every compatible humanoid; small parametric adjustment for handle radius.

- Strengths: deterministic, batch-safe, trivially testable, zero per-unit
  authoring (the skeleton profile is shared — A1's retarget normalizes every
  generated humanoid onto the same canonical bones), matches the steering
  principle that fixed EoM grip poses are allowed and intended infrastructure.
- Weaknesses: does not adapt to unusual handle radii/shapes by itself; still
  requires the weapon grip frame to be correct (as does everything).

### Strategy B — full contact/IK solve

Per-finger iterative solve against measured grip geometry (this slice's v2).

- Strengths: adapts to arbitrary radii and elliptical sections.
- Weaknesses: large failure surface, demonstrated twice in this slice — it
  needs correct joint axes (a sign error inverted flexion), correct volar
  identification (one invalid probe corrupted the whole chain), valid pads,
  penetration models, and per-rig behavior is harder to bound; hundreds of
  generated humanoids multiply every unverified assumption.

### Recommendation — HYBRID, canonical backbone

`canonical power_grip_v1 pose + small constrained contact refinement`:

1. hard-gated anatomical hand frame (Section 2, det +1, volar verified)
2. weapon grip frame from the normalize compiler + profile conventions
3. socket maps weapon frame → canonical hand power-grip frame (Section 3)
4. apply authored `power_grip_v1` joint angles (per-skeleton-profile constants)
5. bounded per-joint refinement from the measured radius: flex delta clamped to
   ±15° from canonical, driven by signed pad-gap, fixed iteration cap,
   classified failure — never free CCD
6. verification gates: contact + encirclement (Section 7)

The refinement is a *quality* layer; the *correctness* layer is the frame
mapping plus the canonical pose. A failed refinement degrades to the canonical
pose (still anatomically plausible) instead of inventing a new pose.

---

## 7. Mandatory invariants and tolerances

Dimensionless in grip radius `r`, `hand_length = |K−W|`, and
`knuckle_breadth = |MCP_index − MCP_pinky|`.

### Hard anatomical preconditions (fail-closed, BEFORE finger solving)

| Invariant | Tolerance |
|---|---|
| `det(palm_basis) = +1`, `det(socket) = +1`, `det(grip frame) = +1` | exact |
| volar sign: thumb-side check AND skinned-mesh check agree | both, else classified STOP |
| `abs(dot(D̂, Â))` | ≥ 0.90 |
| `abs(dot(D̂, L̂))` | ≤ 0.35 |
| `abs(dot(D̂, V̂))` | ≤ 0.25 |
| volar offset `dot(C − P_palm, V̂)` | in `[0.4r, 2.2r]` |
| axis centre containment | `abs(dot(C−P, L̂)) ≤ 0.5·hand_length`, `abs(dot(C−P, Â)) ≤ 0.6·knuckle_breadth` |
| MCP projections onto D̂ | strictly monotonic index→pinky, spread ≥ 0.6·knuckle_breadth |
| per-finger MCP hinge axis vs shaft | `abs(dot(D̂, hinge_i))` ≥ 0.80 |
| per-finger station reach | radial distance from MCP in `[0.35, 0.95]`·chain length |

Current pose fails immediately: `dot(D̂,Â) = 0.00` (needs ≥ 0.90) and
`dot(D̂,L̂) = 1.00` (needs ≤ 0.35).

### Hard contact gates (AFTER solving, on ACHIEVED contacts — never targets)

| Gate | Tolerance |
|---|---|
| per-finger pad gap | ≤ 0.35r |
| per-finger penetration | ≤ 0.20r |
| encirclement: angular span of achieved contact directions in the cross-section plane | ≥ 180° |
| thumb radial direction vs mean four-finger radial direction | dot ≤ −0.3 |
| contact ordering along D̂ | strictly monotonic index→pinky |
| wrist / forearm / left-hand pose deltas from the modifier | exactly 0 |
| determinism, no frame accumulation, OFF restores rest, finite transforms | exact |

### Soft quality measures (report, do not gate alone)

mean gap ≤ 0.2r; curl monotonicity (MCP ≥ PIP ≥ DIP within a margin); thumb
opposition angle 140°–220° from the finger mean; station spacing CV ≤ 0.5.

### Visual acceptance (user F6 only)

Palm view, dorsal view, thumb-side view, fingertip view; grip ON/OFF compare at
identical camera pose. Never claimable by automated tests.

---

## 8. May the Walking wrist stay untouched?

**Yes for A2 — with a sharpened justification.** The socket has full 6-DOF
freedom *relative to the hand bone*, so an anatomically correct hold is
achievable by orienting the **weapon** alone; nothing about holding requires
wrist changes. What raw Walking wrist motion affects is where the club *points*
during the arm swing — a believability concern that the A2 scope already
explicitly accepts as out of scope.

Separation of concerns:

| Concern | Owner | When |
|---|---|---|
| grip frame (hand can anatomically hold the weapon) | weapon socket mapping + hand frame | **A2 (now)** |
| finger articulation around the handle | canonical pose + bounded refinement | **A2 (now)** |
| wrist/arm carry overlay (weapon carried believably while walking) | future `one_handed_carry` overlay, post-animation, still additive | next slice |

If the carry slice later needs a small wrist bias, it must be its own bounded
post-animation overlay — the grip contract must not silently acquire wrist
authority.

---

## 9. Reuse / rewrite / discard

| Component | Verdict | Notes |
|---|---|---|
| `uthana_a2_melee_1h_normalize.gd` | **Reuse + extend** | dual-hypothesis axis/grip-end/radius compiler is sound; extend metadata to a full oriented grip frame + explicit `head_side = radial` convention; stop pretending `front_dir` means anything until then |
| `uthana_a2_grip_shape.gd` | **Reuse** | elliptical section in parent metric is the right contact model |
| `uthana_a2_skinned_pads.gd` | **Reuse + re-bind** | LBS pad binding is right; volar bias must be recomputed with corrected `V̂` |
| `uthana_a2_club_attachment.gd` | **Rewrite the mapping** | keep single-owner socket architecture + follow; replace palm placement with grip-frame mapping (Section 3); remove the dorsal "flesh offset" |
| `uthana_a2_contact_grip.gd` | **Demote** | strip free CCD + sign-flip fallbacks; keep pad/gap instrumentation as the verification layer; add canonical pose + ±15° bounded refinement |
| `uthana_a2_cylindrical_grip.gd` | **Delete** | superseded twice; header already marks it |
| `one_handed_palm_frame.gd` | **Fix carefully** | det −1 and volar sign are real defects; production Meshy path consumes this file — fix inside an A2-local hand-grip-frame module first, propose the production fix (and the production test's wrong "+Y along palm" assertion) as a separate slice |
| `test_uthana_a2_club_attachment_grip.gd` | **Rewrite gates** | keep asset/normalize/regression sections; replace grip gates with Section 7 invariants; delete "distance decreases"-class criteria |
| preview + HUD + A1 isolation | **Reuse** | add palm/dorsal/thumb-side camera presets if cheap |

**Steering gap found:** no `docs/` steering document exists for the reusable
animation/weapon-interaction pipeline (searched `one_hand_grip`, `grip`,
`weapon`, `carry`, `pipeline` — the contract lives only in slice prompts).
Proposal (per the steering-document change rule): promote the accepted contract
from this audit (hand frame, grip frame, profile conventions, invariant gates,
canonical-pose policy) into `docs/EQUIPMENT_INTERACTION.md` in the
implementation slice, as a proposal for owner approval.

---

## 10. Implementation plan for the next slice (summary)

0. Re-run `slice a1` + `slice a2` as fresh baseline.
1. `uthana_a2_hand_grip_frame.gd`: right-handed volar-verified hand frame
   (Section 2) + MCP stations + per-finger hinge axes + hard preconditions;
   classified errors on any sign/handedness ambiguity.
2. Extend the melee_1h compiler metadata: full oriented `primary_grip` frame +
   `head_side = radial` profile convention.
3. Attachment: socket = canonical power-grip mapping (Section 3), volar offset
   `≈ r` along verified `V̂`; keep one transform owner.
4. `power_grip_v1`: authored canonical joint angles (skeleton-profile
   constants, +X volar flexion as measured), bounded radius refinement (±15°,
   capped iterations, classified failure), post-animation, reversible, no
   accumulation.
5. Rewrite A2 test gates per Section 7 (invariants before fingers; achieved
   contacts + encirclement after); delete superseded cylindrical grip file.
6. Preview: keep controls (`1/2/3`, Space, `H`, `G`, `D`, `[`/`]`); HUD shows
   per-finger gap/penetration/iterations + frame invariant status.
7. Report + await user F6 from palm/dorsal/thumb/fingertip views.

Out of scope: production `generated_warrior_equipment.gd`/test fix (separate
proposed slice), carry overlay, shield, source assets, A1, commit.

---

## 11. Batch-generation risk assessment (5 → hundreds of humanoids)

| Risk | Mitigation |
|---|---|
| per-rig finger hinge-axis variance (sign surprises already observed) | hinge axes measured from rest pose per rig; gated (`dot(D̂, hinge) ≥ 0.80`); fail-closed |
| volar mis-identification on unusual meshes (gloves, mittens, asymmetric hands) | dual independent checks (thumb-side + skinned mesh) must agree or classified STOP |
| weapons whose grip segment is not straight/near-cylindrical | ellipse ratio + segment straightness gates in the compiler; classified `MARKER_*` errors |
| scale drift between generations | all tolerances dimensionless in `r`, `hand_length`, `knuckle_breadth` |
| left-handed / mirrored units | hand frame parameterizes MCP ordering per hand; det +1 enforced everywhere |
| tolerance mis-calibration at scale | canonical pose fallback keeps failures anatomically plausible; gates flag units for authoring review instead of shipping absurd grips |
| silent chirality flips (this audit's det −1) | determinant gates on every frame in the chain, in tests and at runtime bind |

The skeleton-profile amortization is the decisive argument for the hybrid: all
generated humanoids share the canonical 52-bone profile after A1-style
retargeting, so one authored pose scales to hundreds of units, while the
weapon-side variation is absorbed by the marker/normalize compiler — which is
already dual-hypothesis, confidence-gated, and fail-closed.

---

## 12. Decision

**PROCEED WITH HYBRID** — canonical `power_grip_v1` pose on a corrected,
invariant-gated weapon→hand frame mapping, plus small constrained contact
refinement and encirclement-based verification. Do not proceed with any finger
work until the Section 7 hard preconditions pass on the attached weapon.
