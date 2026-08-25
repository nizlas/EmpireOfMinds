# Equipment interaction pipeline (weapon grips)

**Status: CANONICAL. The generic core is the actual engine owner and the
accepted right-hand runtime path (A2.9 ownership inversion).**

Distinguished results:

| Claim | Status |
|-------|--------|
| Bilateral profile / API architecture | Established |
| Generic core owns the power-grip engine (no A2 preloads) | **Done (A2.9)** — `power_grip_1h_engine.gd`; A2 files are compatibility/reference shells |
| True dependency injection (family / fixture / skinning / weapon / engine) | **Done (A2.9)** — fail-closed named errors; composition root selects concretes |
| Right-hand A2.7 parity through the generic path | **Proven (A2.9)** — legacy-vs-generic matrix: 4 Walking times × 3 grip radii, surface ground-truth gate at all 12 points, ±137° yaw invariance, determinism, reversibility |
| Accepted walking preview runs the generic assembler | **Done (A2.9)** — F6 runtime owner is `EquipmentAssembler`; the legacy attachment is a parity/diagnostic fixture only |
| Left anatomical derivation and failure classification | Demonstrated |
| Left full wrap + contour + surface acceptance | **DERIVED BUT FULL ASSEMBLE NOT ACCEPTED** — fail-closes `THUMB_CONTOUR_GATE_FAILED` / `thumb_middle_penetration_excess` |
| Per-unit fixture compilation pipeline | **Not started** — only the hand-authored Uthana fixture exists; absence fails closed |

Production Meshy-club migration remains a separate slice.

Promoted from the A2 theoretical audit
(`game/assets/prototype/3d/units/generated_warrior/uthana_a2/A2_GRIP_THEORETICAL_AUDIT.md`)
and the A2.8 / A2.8b / A2.9 slices.

## Scope

How procedurally generated weapons are attached to and gripped by generated
humanoids on the WorldMap path. Presentation-side only: grips never become
gameplay state, and gameplay never reads weapon transforms.

Generated humanoids and equipment may vary visually. Hand anatomy, interaction
semantics, assembly order and validation are reusable infrastructure. Weapons
remain separate rigid assets.

## Owners

| Owner | Role |
|-------|------|
| **`HumanoidHandProfile`** (`game/presentation/equipment/humanoid_hand_profile.gd`) | Compiled per-side hand: semantic bone map, chirality, palm L/radial/volar/dorsal, joint frames, skinned contact samples, confidence. Family, fixture AND skinning implementation are injected; each missing dependency fails closed by name. |
| **`PowerGrip1hEngine`** (`power_grip_1h_engine.gd`) | The actual grip engine (A2.9): anatomical pose compilation, bounded refinement, finger contact, signed winding, thumb direction, contour, surface ground truth, pose freshness, fail-closed gates. Consumes the injected profile only; contains no bone name, triangle ID or asset path. `uthana_a2_power_grip.gd` is a thin compatibility shell serving the legacy right fixture through overridable seams. |
| **`SkinnedMeshGeometry`** (`skinned_mesh_geometry.gd`) | Generic CPU skinning: renderer-compatible bind-matrix vertex skinning, pad sampling, humanoid height (bone candidates injected from the family), skeleton/mesh lookup. No A1 preloads in generic code. |
| **`Melee1hNormalize` / `MeleeGripShape`** (`melee_1h_normalize.gd`, `melee_grip_shape.gd`) | Generic melee_1h weapon compiler + elliptical grip shape. Weapon SELECTION never happens here. |
| **`EquipmentGripGeometry`** | Hand-independent grip: `primary_grip` frame, optional `secondary_grip`, shaft axis, elliptical/circular cylinder radii, contact extent, head side, owner-hand, interaction-profile id. |
| **`GripInteractionProfile`** | Policy boundary. Implemented: `power_grip_1h_v1`. Reserved (not implemented): secondary/support power grip, shield, bow hold/draw, sling, firearm trigger/support. |
| **`HandGripSolver`** | Attach step: instantiates the INJECTED engine, injects the profile, applies the pose, runs wrap/contour/surface gates fail-closed. Never preloads an engine or asset. |
| **`EquipmentAssembler`** | One application order (below); one transform owner. All family/fixture/weapon/engine choices arrive via `configure_dependencies()` — no silent defaults; classified errors (`FAMILY_REQUIRED`, `FIXTURE_REQUIRED`, `ENGINE_REQUIRED`, `WEAPON_SOURCE_REQUIRED`). |
| **Composition root** (`uthana_a2/uthana_a2_equipment_composition.gd`) | The ONLY place selecting the concrete Mixamo-52 family, Uthana fixture, wooden club and 1h engine for the Uthana previews/tests. |

Dependency direction (enforced by structural tests on script source):

```text
uthana_a2 compatibility/demo adapters
    → generic equipment core (engine, solver, assembler, profile, skinning)
        ← injected family        (mixamo_52_hand_family.gd)
        ← injected asset fixture (uthana_warrior_hand_fixture.gd)
        ← injected grip geometry / weapon source
        ← injected policy/engine registry
```

### What is generic vs specific

- **Generic:** profile/geometry/policy/solver/assembler/engine contracts; palm-frame construction; volar dual-check; socket mapping; contact/winding/contour/surface gates; CPU skinning; fail-closed classifications; the hand-surface ground-truth rules below.
- **Skeleton-family (Mixamo 52):** bone-name templates, MCP hinge `+X` **on this family only**, distal-tip fraction, humanoid-height bone candidates (`mixamo_52_hand_family.gd`). Positive local X is not a universal flexion axis.
- **Per-asset compiled data (this warrior):** triangle IDs, UV centroids, rest plate normals, pad marker, rest-winding flip, bind-weight/patch-sanity, canonical finger flexion, rejected A2.6 vs accepted A2.7 thumb anatomical numbers, superseded false-positive references, schema version and mesh hash (`uthana_warrior_hand_fixture.gd`). A future generated unit must compile or load its own fixture.

Do not put A2.7 triangle IDs, UV rectangles or calibrated angles in generic solver/policy code.

A future generated humanoid must never fall back to the superseded brightness
heuristic, this warrior’s triangle IDs, a hard-coded right-hand quaternion, an
assumed imported bone axis, or an unverified coordinate negation for the left
hand.

## Owner-hand vs secondary-hand

- One hand owns a rigid weapon through `primary_grip`.
- A second hand, when a later policy requires it, follows `secondary_grip` through IK and then uses the same hand-contact machinery.
- A rigid weapon is never parented to two hands.
- This slice establishes the `secondary_grip` interface only. Full two-handed arm IK is not implemented (`power_grip_2h_support_v1` fail-closes `SECONDARY_IK_NOT_IMPLEMENTED`).

## Bilateral semantics

Left is derived from that hand’s bones and skinned mesh, not by negating a coordinate, copying right-hand local quaternions, or assuming identical imported bone axes.

- Radial = this hand’s thumb/index side (`index − pinky`, Gram-Schmidt vs L).
- On a left hand, `radial × L` points **dorsal**. Volar is taken from the thumb column (and confirmed by the skinned-flesh probe), then the triad is completed as a right-handed `Basis(across, L, V)` with `across = L × V`. That frame has det +1; `Basis(radial, L, V)` on the left has det −1 and is rejected.
- A single palm normal does not identify every finger’s volar surface; each digit uses its own anatomical frames and achieved skin.
- Thumb opposition is toward the index side under that hand’s chirality.
- Nail/dorsal and pad/volar checks use that side’s achieved skinned geometry.
- Global yaw does not change the result (hand-relative socket + dimensionless gates).
- Mesh topology/UVs are compiled per side. A topological mirror is used only when correspondence is proven — it is not assumed here.

## Final-pose skinned-geometry truth

Validation measures the achieved final skinned geometry after the assembler pose, not only bones, authored constants or solver targets. Compiled plate normals are bind-time references and cheap diagnostics; acceptance for nail/pad orientation is the deformed skinned-triangle gate (A2.7).

## Hand-surface ground truth and lessons from the A2 power-grip proof

Detailed forensic measurements stay in the A2 audits (historical; do not
rewrite them). The reusable rules are:

- Bone-local constants, solver targets and marker directions are not
  rendered-surface ground truth. One rigid normal transformed by a bone pose
  does not prove final surface orientation.
- Nail/dorsal and pad/volar identity come from the compiled hand profile and
  must be validated against skinned geometry. Texture brightness or low
  saturation is not sufficient nail identification (A2.5 compiled dorsal
  knuckle skin ~67° from the true plate).
- Imported triangle winding, authored cross products and shading normals may
  disagree. This warrior’s thumb mesh is CW-authored; rest-anchored `flip = −1`
  is required. Failing normals must never be silently auto-flipped to pass.
- Nail and pad normals are measured from CPU-skinned surface triangles in the
  achieved final pose, after body animation, attachment, IK where applicable,
  canonical hand pose, refinement and all modifiers.
- Each measured triangle uses its own centroid, closest shaft-axis point and
  radial at its own axial station. A radial copied from one pad marker is
  insufficient.
- Measurements carry a final-pose freshness stamp. Stale pre-animation
  measurements fail closed (`thumb_measurement_pose_stale`).
- For a cylindrical power grip: the true nail/dorsal surface faces radially
  outward and remains sufficiently non-axial; the true pad/volar surface faces
  inward and supplies the shaft contact. The nail must not be accepted as the
  contact surface.
- CMC opposition/pronation, MCP/IP flexion and distal axial twist are
  different anatomical roles. The solver must not manufacture opposition
  through excessive distal roll or a mislabeled local axis. On this warrior
  the rejected A2.6 pose is approximately `tau = -90°` (over-pronated
  compensation for mislabeled plates); the accepted A2.7 result is
  approximately `tau = -60°`. Those numbers are this asset’s evidence, not
  universal solver constants.
- Winding, pad gap, contour coverage, unsigned wrap, radial dot or target
  proximity do not independently prove correct nail/pad orientation. Absolute
  unsigned wrap alone cannot prove thumb opposition.
- Visual F6 acceptance remains a required final gate.

These principles apply to later shield, secondary-hand, bow, sling, crossbow
and firearm profiles even when their contact policies differ. Later profiles
reuse anatomy, surface sampling, transforms, contact measurement and failure
classification — they do not reuse the exact `power_grip_1h_v1` pose.

Why earlier scalar/orientation-blind gates false-passed: they projected
mislabeled compiled constants (A2.5/A2.6 `nail_out ≈ +0.98`) or measured
gap/winding without the true plates. The A2.6 visual-failure pose remains an
executable negative regression
(`test_uthana_a2_club_attachment_grip.gd` `neg-a26a`).

Evidence owners: historical audits under `uthana_a2/A2_*_AUDIT.md`; this
warrior’s versioned fixture `uthana_warrior_hand_fixture.gd`; executable
coverage in the A2 and generic pipeline tests.

## Application order

1. Sample/apply body animation.
2. Apply owner-hand carry/interaction overlay where relevant (interface only in this slice).
3. Attach the rigid equipment once through the owner hand and `primary_grip`.
4. Solve secondary-hand reach/IK when the profile requires it (not implemented).
5. Apply per-hand finger interaction after animation/IK.
6. Update skeleton transforms.
7. Measure achieved skinned geometry in that exact final pose.
8. Accept or reject fail-closed.
9. Expose classified diagnostics to preview, batch generation and retry logic.

Finger grip is applied after body animation. Fallback/retry is a caller boundary (batch generation) — the assembler does not invent a second pose.

## Failure classifications

Typical classes: `HAND_PROFILE_FAILED`, `HAND_PROFILE_FIXTURE_REQUIRED`, `HAND_PROFILE_FAMILY_REQUIRED`, `HAND_PROFILE_SKINNING_REQUIRED`, `FAMILY_REQUIRED`, `FIXTURE_REQUIRED`, `ENGINE_REQUIRED`, `WEAPON_SOURCE_REQUIRED`, `ENGINE_PROFILE_REQUIRED`, `VOLAR_VERIFICATION_FAILED`, `GRIP_FRAME_PRECONDITION_FAILED`, `THUMB_OPPOSITION_GATE_FAILED`, `THUMB_CONTOUR_GATE_FAILED`, `THUMB_SURFACE_TRUTH_GATE_FAILED`, `WEAPON_TWO_TRANSFORM_OWNERS`, `SECONDARY_IK_NOT_IMPLEMENTED`, `POLICY_NOT_IMPLEMENTED`. Scalar distance decrease alone is never a PASS.

The left T2 / distal-station conflict on this asset is an explicit classified
regression and the next-slice blocker. Do not weaken contour, penetration,
surface-orientation or anatomy gates merely to obtain a bilateral PASS.

## `power_grip_1h_v1`

- Four fingers close from the finger side (measured flexion sign).
- Thumb opposition is side-aware and anatomically valid (empirical joint frames, no trusted imported axis).
- Nail/dorsal surface remains outward; thumb pad/volar faces and contacts the handle.
- Winding, contact, penetration and contour are measured on achieved final geometry.
- The thumb is not required to touch the index finger.
- Grip acceptance is invariant under global rotation and hand side (same gates, per-side frames).
- Socket: `D = normalize(radial + tan(12°)·L)`, centre = palm + `1.2r` volar + `0.15·hand_length` along L; det +1.

## How later profiles extend this

`melee_2h`, shield, bow, sling, crossbow and firearm policies should reuse hand anatomy, surface sampling, transform handling, contact measurement and failure classification. They should differ mainly in contact roles, free fingers, targets, joint limits and state transitions — not by forking a second solver.

## Anatomical hand grip frame

- `L` = normalize(mean(MCP index..pinky) − wrist)
- `radial` = normalize(MCP_index − MCP_pinky), Gram-Schmidt vs `L`
- `V` is the volar direction verified by thumb-side + skinned-flesh extent; `across = L × V` so `Basis(across, L, V)` has det +1
- The two volar checks must agree, else a classified STOP (never a silent sign flip of a broken frame)
- Right-hand `across == radial`; left-hand `across` is ulnar. Do not write `V = radial × L` as a universal contract.

## Weapon grip frame (`melee_1h`)

Normalize compiler: origin = `primary_grip`, +Y = shaft grip→head, +X/+Z = measured elliptical cross-section, det +1. Head/active end toward the **radial** side of the gripping hand (`MELEE_1H_HEAD_SIDE = "radial"`).

## Grip policy (hybrid, locked by A2)

Canonical authored pose + bounded per-digit radius refinement (±15°, backtracking, classified fallback). Post-animation `SkeletonModifier3D`, deterministic, reversible. No free unconstrained CCD. Wrist/forearm/opposite-hand deltas exactly 0.

## Mandatory gates

Frame preconditions BEFORE finger solving; contact/winding/contour/surface AFTER, on achieved geometry. See A2 notes for the numeric bands. Visual acceptance stays a user F6 gate.

## Proof limitation and next implementation slice

Current executable proof covers the present Mixamo-52 / Uthana warrior family
and the current cylindrical one-handed weapon. Only this unit is visually
validated; batch multi-unit robustness is untested. The A2.9 injection-stub
test proves the ARCHITECTURE consumes injected family/fixture identities —
it is not visual multi-unit validation. No per-unit fixture COMPILATION
pipeline exists yet (the census tooling from A2.6 was a temporary probe);
a new unit today needs a hand-authored fixture, and absence fails closed.

Left hand: **DERIVED BUT FULL ASSEMBLE NOT ACCEPTED.** On this asset the
left thumb’s rest station sits distal of the finger slab: the pose that puts
the pad in-zone and on the handle fail-closes the A2.6 T2 contour
(`thumb_middle_penetration_excess`); the pose that keeps T2 legal leaves the
pad hovering/out-of-zone. That is a classified per-asset blocker, not a
reason to copy right-hand quaternions or weaken the accepted gates.

Done by A2.9 (2026-08-24): engine ownership inversion, true dependency
injection, full right-hand legacy-vs-generic parity matrix (12 points + yaw
invariance, surface ground truth at every point), and the accepted walking
preview migrated to the generic assembler — all without touching the
canonical pose, socket mapping, thresholds or calibration.

Remaining next slices (in no fixed order):

1. resolve the left T2/distal-station conflict without weakening the accepted gates, then pass the complete left wrap + contour + surface pipeline;
2. per-unit fixture compilation/verification pipeline (UV-island/census-based patch compiler with bind-sanity as the gate);
3. secondary-hand IK when a two-handed policy is actually needed.

## Known production gap (separate slice)

The production Meshy club path still uses `one_handed_palm_frame.gd` (det = −1, unverified normal) and `test_generated_warrior_equipment.gd` (“club points grip→head along palm +Y”). Migrating production to this contract must not be done as a side effect.
