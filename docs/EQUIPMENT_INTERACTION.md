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
| Grip mechanism owned by the interaction policy, not the dispatch | **Done (A2.9b)** — `power_grip_1h_policy.gd` owns the socket mapping and hard preconditions; `grip_interaction_profile.gd` is a registry only |
| Unit fixture outside the generic core directory | **Done (A2.9b)** — the fixture lives with its asset and no longer selects a skeleton family |
| Left anatomical derivation and failure classification | Demonstrated |
| Left full wrap + contour + surface acceptance | **DERIVED BUT FULL ASSEMBLE NOT ACCEPTED** — fail-closes `THUMB_CONTOUR_GATE_FAILED` / `thumb_middle_penetration_excess` |
| Bilateral runtime | **NOT ESTABLISHED** — right only; left is classified fail-closed |
| Per-unit fixture compilation pipeline | **Not started** — only the hand-authored Uthana fixture exists; absence fails closed. Onboarding a new unit is NOT complete until this compiler exists. |

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
| **`GripInteractionProfile`** (`grip_interaction_profile.gd`) | Policy **registry** only: maps a policy id to the policy script that owns it, declares reserved ids and whether each would need a second transform owner. Owns no socket construction, no thresholds and no grip mechanism. Callers may inject a `policies` dictionary to resolve ids the registry has never heard of. Reserved (fail-closed): secondary/support power grip, shield, bow hold/draw, sling, firearm trigger/support. |
| **`PowerGrip1hPolicy`** (`power_grip_1h_policy.gd`) | The one implemented policy (`power_grip_1h_v1`): socket mapping (`KAPPA_DEG`, `VOLAR_OFFSET_RADII`, `DISTAL_SHIFT_HAND`), the hard anatomical preconditions and the semantic acceptance contract. A future policy is a sibling file exposing `POLICY_ID`, `REQUIRES_SECONDARY`, `build_grip_socket_world()` and `evaluate_grip_invariants()` — never an edit to the registry, the solver or the assembler. |
| **`HandGripSolver`** | Attach step: instantiates the INJECTED engine, injects the profile, applies the pose, runs wrap/contour/surface gates fail-closed. Never preloads an engine or asset. |
| **`EquipmentAssembler`** | One application order (below); one transform owner. All family/fixture/weapon/engine choices arrive via `configure_dependencies()` — no silent defaults; classified errors (`FAMILY_REQUIRED`, `FIXTURE_REQUIRED`, `ENGINE_REQUIRED`, `WEAPON_SOURCE_REQUIRED`). |
| **Composition root** (`uthana_a2/uthana_a2_equipment_composition.gd`) | The ONLY place selecting the concrete Mixamo-52 family, Uthana fixture, wooden club and 1h engine for the Uthana previews/tests. |

Dependency direction (enforced by structural tests on script source):

```text
uthana_a2 compatibility/demo adapters
    → generic equipment core (engine, solver, assembler, profile, skinning)
        ← injected interaction policy (power_grip_1h_policy.gd, resolved by
                                       the registry or injected directly)
        ← injected family             (mixamo_52_hand_family.gd)
        ← injected unit fixture       (uthana_a2/uthana_warrior_hand_fixture.gd)
        ← injected grip geometry / weapon source
        ← injected engine             (power_grip_1h_engine.gd)
```

`game/presentation/equipment/` holds generic core plus injectable
skeleton-family data. It holds no unit fixture and no asset path; a
structural test fails if a unit/asset-specific file appears there.

### What is generic vs specific

- **Generic executable mechanism:** profile/geometry/solver/assembler/engine; palm-frame construction; volar dual-check; anatomical hand frames; per-joint derived flexion axes and signs; chirality and the det +1 basis; CMC swing/twist/opposition; MCP/IP flexion; deterministic bounded refinement; winding and direction; finger contact and encirclement; CPU-skinned contour measurement; CPU-skinned nail/pad surface ground truth; rest-anchored triangle winding without auto-flip; per-triangle radial at each triangle's own station; pose freshness; fail-closed gates and classified error codes.
- **Interaction policy (`power_grip_1h_policy.gd`):** socket mapping, hard anatomical preconditions, semantic acceptance contract for `power_grip_1h_v1`. Policy, not generic mechanism — a different interaction supplies different numbers.
- **Skeleton-family (Mixamo 52):** bone-name templates and chains, MCP hinge `+X` **on this family only**, distal-tip fraction, imported axis conventions, humanoid-height bone candidates (`mixamo_52_hand_family.gd`). Positive local X is not a universal flexion axis. Injected data, not universal truth.
- **Per-unit fixture (this warrior, `uthana_a2/uthana_warrior_hand_fixture.gd`):** nail/pad triangle IDs per side, UV centroids, rest plate normals, pad marker, rest-winding flip, bind-weight/patch-sanity, canonical finger flexion, rejected A2.6 vs accepted A2.7 thumb anatomical numbers, superseded false-positive references, schema version and mesh hash. It records `EXPECTED_FAMILY_ID` as data but does not select a family. A future generated unit must compile or load its own fixture.

Still missing for automatic onboarding: a fixture **compiler** that derives
the per-unit patch data from a new asset. The data boundary is now shaped so
a compiler can emit it without editing core code, but until that compiler
exists, onboarding a new unit still requires hand-authored fixture data.

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

### Shield: asset prerequisite (C1, 2026-08)

The shield profile stays **reserved and unimplemented**, and it is blocked on the
asset rather than on the solver. A shield profile needs `shield_grip`,
`forearm_contact` and `shield_forward`, and a grip marker can only be placed on a
grip that exists as geometry. The current `wooden_shield.glb` has **no readable
handle**: structural analysis classifies it `NO_READABLE_HANDLE`
(`artifacts/assetgen/shield/wooden_shield_structural.json`).

A shield without a readable handle must never be classified as a full hand-held
shield, and inferred markers from automated analysis are **diagnostics only** —
they never become runtime markers. Generating a shield candidate with a real
handle is asset-pipeline work, not equipment-interaction work; see
[ASSET_PROVIDER_PIPELINE.md](ASSET_PROVIDER_PIPELINE.md).

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

## Automatic hand-fixture compilation (A2.10)

The per-unit surface evidence is no longer hand-authored. `hand_fixture_compiler.gd`
derives it from a rigged mesh plus an injected skeleton-family profile:

```
rigged humanoid + injected skeleton family
  → automatic fixture compilation (Godot headless)
  → versioned fixture artifact (.tres, self-hashed)
  → generic grip engine
  → achieved skinned-geometry measurement
  → automatic PASS or classified FAIL
```

No human selects triangles, a nail surface, a pad, a volar side or a bone.

### What the compiler decides, and on what evidence

Classification is carried by **skin-weight dominance**, **surface topology** and
the hand's **own anatomical directions**. Albedo, brightness and saturation are
not sampled at all: the reference asset's right nail texture is practically
absent, so a brightness heuristic would have to guess. UV data is recorded only
as a stable identity back-reference for bind sanity, never as a reason a patch is
a nail or a pad.

1. Complete finger and thumb chains resolve through `family.bone_map(side)`.
2. The mapped thumb must sit within a few of this rig's own hand spans of the
   wrist it is mapped to, so a bone map pointing at the other limb is refused
   rather than classified with this hand's directions.
3. A det +1 hand basis, then longitudinal / radial (index side) / volar, with
   volar cross-checked against the skinned palm flesh.
4. Candidate triangles are those whose three vertices are dominated by the
   distal or middle thumb segment, at least two on the distal.
5. Candidates are split into **connected components** by shared vertices. On the
   reference right hand this matters: 30 candidate triangles form three
   components, and only one is the thumb tip. The other two are auto-rig
   weight-bleed in unrelated UV regions, and averaging them in would corrupt
   both plate normals.
6. The thumb tip is the component carrying **both** an opposed dorsal-radial
   nail face and a volar pad face. Two components of near-equal area is an
   ambiguity, not a coin flip.
7. Within it: `pad = n·volar ≥ 0.45`, `nail = n·normalize(radial − volar) ≥ 0.35`
   — the nail faces off the back of the thumb and outward on that hand's index
   side. Each patch must clear the best rejected candidate by a real margin,
   otherwise the choice is a silent pick out of a continuum and is refused. That
   margin (0.08) is **CALIBRATING data**, not anatomy: it lives in
   `hand_fixture_compiler_calibration.gd` and is injected — see below.

On the accepted A2.7 right hand this reproduces the hand-authored oracle
exactly: the same 4 nail and 10 pad triangles, rest normals agreeing to 6
decimals, and a bit-identical pad marker.

### Fixture data contract, by ownership

| Field | Classification |
| --- | --- |
| `nail_tris` / `pad_tris` (surface, vertex triple) | automatically derivable |
| per-triangle UV centroid (`uvc`) | automatically derivable (identity only) |
| per-triangle winding flip (`flip`) | automatically derivable, rest-anchored |
| `nail_normal_local` / `pad_normal_local` | automatically derivable |
| `rest_nail_pad_dot` | automatically derivable |
| `pad_marker_local` / `nail_marker_local` | automatically derivable |
| bone-weight evidence, bind sanity | automatically derivable |
| per-structure confidence and diagnostics | automatically derivable |
| source mesh SHA-256, content hash | automatically derivable |
| bone names, MCP hinge, tip fractions, height candidates | **skeleton-family data** (injected) |
| `CANON_THUMB_ANAT`, `CANON_THUMB_ANAT_LEFT`, `CANON_FLEX_DEG` | **interaction-policy calibration** — pose, not surface; shared per grip profile, lives in `power_grip_1h_calibration.gd`, cannot be derived from geometry and must not be faked |
| the hand-authored Uthana fixture | **temporary reference oracle** (development + negative regression only) |
| `SUPERSEDED_A25_*` plate normals, `REJECTED_A26_THUMB_ANAT` | **historical regression** — previously rejected hypotheses about one asset; a compiler cannot derive a rejected hypothesis, so the compiled artifact deliberately carries none |

No Uthana-specific evidence became a general rule.

### Fail-closed classification

`HAND_SKELETON_INCOMPLETE`, `HAND_CHIRALITY_AMBIGUOUS`, `HAND_FRAME_UNDERIVABLE`,
`HAND_VOLAR_AMBIGUOUS`, `THUMB_SURFACE_CANDIDATES_MISSING`, `NAIL_PATCH_AMBIGUOUS`,
`PAD_PATCH_AMBIGUOUS`, `NAIL_PAD_NOT_OPPOSED`, `PATCH_BONE_WEIGHT_INSUFFICIENT`,
`PATCH_WINDING_UNDERIVABLE`, `FIXTURE_CONFIDENCE_TOO_LOW`,
`FIXTURE_MESH_HASH_MISMATCH`, `FIXTURE_FAMILY_MISMATCH`,
`FIXTURE_SCHEMA_UNSUPPORTED`, plus `FIXTURE_ARTIFACT_MISSING` /
`FIXTURE_ARTIFACT_HASH_MISMATCH` for artifact loading.

Confidence is reported **per structure** (component, nail, pad, opposition,
bone weight) and the overall value is the weakest of them. There is no fallback
to another unit's fixture and no silent selection of a best candidate below the
confidence floor.

### Left hand: classified, not compiled

The left hand compiles to `PAD_PATCH_AMBIGUOUS`. Its volar pad has no stable
geometric separation on this mesh — the best kept candidate clears the best
rejected one by 0.051 against a 0.08 requirement — so certifying it would mean
picking a "best" pad out of a continuum, which is exactly the manual judgement
this slice removes.

This is upstream of, and independent from, the known left T2/distal-station
conflict. The compiler does not mask, move or work around that conflict: the
left fail-close through the authored reference path is unchanged and still
verified.

The authored left reference also does **not** follow the right hand's anatomical
convention — its nail island faces ulnar (`n·radial = −0.86`) and its pad set
contains dorsal-facing triangles. That divergence is reported rather than
reproduced, and is independent evidence about the left-hand problem.

## Fixture identity, live-mesh binding and ingestion (A2.11)

A2.10 could accept an artifact because it was internally self-consistent. A2.11
closes that: an artifact's own payload can no longer vouch for which mesh it
belongs to, and a valid hash is not an acceptance.

### Three identity levels, kept separate on purpose

| Level | Question it answers | Owner | Failure |
| --- | --- | --- | --- |
| **1. Source mesh identity** | is this the mesh that was compiled, and the one being posed now? | `source_mesh_sha256` in the artifact vs `Compiler.mesh_identity_of_asset()` derived from the *asset*, checked by `CompiledHandFixture.verify_against_mesh()` | `FIXTURE_MESH_HASH_MISMATCH`, `FIXTURE_MESH_IDENTITY_REQUIRED` |
| **2. Fixture semantic/content identity** | is this payload exactly the one the compiler produced, unedited? | `content_hash` over the canonical payload | `FIXTURE_ARTIFACT_HASH_MISMATCH`, `FIXTURE_SCHEMA_UNSUPPORTED` |
| **3. Acceptance result** | does *this* mesh + *this* fixture + *this* policy actually grip? | bind sanity and the policy's ground-truth gate, through the real assembler | `GRIP_PATCH_BIND_FAILED`, `THUMB_SURFACE_TRUTH_GATE_FAILED` |

A valid level 2 says nothing about level 1 or 3. All three are checked, in that
order, and each has its own named failure.

### Canonical content identity

The A2.10 hash was context-dependent: the same GLB hashed differently in a test
context than in a separate headless run, because geometry was derived in **world
space from the achieved pose**, so ancestor scale and whatever pose the scene
happened to be in leaked into the hashed floats. Raising the quantum would only
have hidden it.

The fix is a canonical compile context, not a coarser hash:

- **Skeleton space.** `skinned_vertex_local()` stops at the skeleton and does not
  apply `skeleton.to_global()`, and `derive_frame(..., SPACE_SKELETON)` builds the
  hand basis from raw bone transforms. Ancestor scale and placement are therefore
  outside the compiled data by construction.
- **Rest pose.** The compiler pins every bone to its rest pose for the duration of
  the compile and restores the previous pose afterwards, so animation state cannot
  reach the artifact.
- **One declared precision.** Every float in the payload is snapped to
  `IDENTITY_QUANTUM = 1e-6` *as stored*, so the representation that is hashed is
  the representation the engine later runs on — no hashing a rounded view of
  unrounded data.
- **Whole-payload coverage.** The hash covers the entire canonicalised payload
  except `content_hash` itself and `source_asset` (provenance, declared
  non-behavioural). Patches, winding, rest normals, markers, confidence, family
  id/version, bone-map digest, schema, compiler version, calibration id/version
  and source-mesh identity are all inside it. Adding a behaviour-affecting field
  cannot silently fall outside the identity.

Result: one hash across the same process, a new Godot process, the test context,
headless ingestion, and the scaling/scene contexts that previously diverged —
while a geometric change larger than the quantum still changes the hash.

### Mandatory live-mesh binding

`CompiledHandFixture.from_artifact()` **requires** a non-empty expected mesh
identity and refuses `""` with `FIXTURE_MESH_IDENTITY_REQUIRED`; an empty string
can no longer disable the check. The expected identity is derived from the asset
(`Compiler.mesh_identity_of_asset(SOURCE_GLB_PATH)`), never read back out of the
artifact being verified, and no Uthana hash is duplicated into a composition or
preview.

`EquipmentAssembler.assemble()` calls `verify_against_mesh()` against the
`MeshInstance3D` it is about to pose, as its **first** action — before any pose,
socket or geometric bind sanity. A wrong-mesh artifact is therefore rejected as
`FIXTURE_MESH_HASH_MISMATCH` and never reaches `thumb_patch_frame_mismatch`. The
production callers are `uthana_a2_equipment_composition.gd` (F6 preview and
slice tests) and the ingestion step, not a test-only path.

Fail-closed, with no fallback to the authored oracle and no generic default
fixture: wrong mesh, wrong hand, foreign family/family-version, valid-but-rehashed
artifact bound to the wrong live mesh, missing expected identity, missing
artifact.

### Compiler PASS is not asset ACCEPTED

The canonical automatic chain is owned by `tools/assetgen/rig_ingest.py`
(CLI: `python -m tools.assetgen ingest-rig <res://…glb>`), which drives
`certify_hand_fixture_headless.gd` through `hand_fixture_ingest.py`:

```
import (godot --headless --import)
  → skeleton-family resolution
  → fixture compilation
  → artifact integrity (written, re-read, re-verified)
  → binding to the imported mesh
  → bind sanity            (real EquipmentAssembler)
  → grip ground truth      (selected policy's gate, closest_patch == "pad")
  → machine-readable result
  → ACCEPTED, or classified FAIL with a named domain error
```

Steps 2–7 run inside Godot. The artifact is written to a **staging** path and is
only published to the path a unit composition loads if the whole chain is
ACCEPTED, so a rejected artifact can be kept for diagnostics without ever
becoming a loadable accepted fixture.

**Exit protocol**, identical in the Godot step, the Python driver and the CLI:

| Exit | Meaning |
| --- | --- |
| `0` | the whole chain was accepted |
| `2` | expected, classified asset/fixture FAIL with a named domain error class |
| `1` | infrastructure / process / protocol / tooling error |

A fingerless or incomplete rig is exit `2` with `HAND_SKELETON_INCOMPLETE` — a
truthful statement about the asset, not `STEP_FAILED` and not exit `1`. Timeout,
missing/unparseable report, an unstartable Godot and a missing toolchain are
exit `1` with their own classes (`INGEST_TIMEOUT`,
`INGEST_REPORT_MISSING`, `INGEST_GODOT_START_FAILED`,
`INGEST_GODOT_NOT_AVAILABLE`) and still emit a machine-readable report.

Not claimed: no external provider callback invokes this automatically. The
provider round trip is `autorig` + `poll`/`download`; the ingestion step then
runs on the downloaded file from the CLI or the download path, and whether it
ran is visible in the emitted report rather than assumed.

### Import representation and family resolution

The pipeline establishes the import representation itself (`--headless --import`);
an editor visit is not part of the chain. Bone-name spelling is owned by the
**skeleton family**, not the compiler: `mixamo_52_hand_family.gd` declares its
alias prefixes (`mixamorig_`, `mixamorig:`) and resolves each canonical name
against the actual skeleton via `resolved_bone_map()`, reporting which
representation it found (`godot_humanoid_retarget` or `raw_mixamo`). No
`mixamorig_*` or Uthana name appears in the generic compiler.

Consequence: `generated_warrior_3d_uthana_rigged.glb` (a0), which uses
`mixamorig_RightHand`, is no longer misclassified as fingerless. It resolves the
family, compiles, and then receives a truthful later verdict from the grip gates
instead of a wrong statement about its skeleton. Genuinely missing finger bones
still fail closed.

### `MIN_CLASSIFICATION_MARGIN` is CALIBRATING data

The 0.08 margin was presented as a core compiler constant. It is not proven
anatomy: it was raised from 0.05 while implementing the reference, and the left
reference's outcome is decided by 0.0511 — it fails *because* the threshold sits
above that value. Two hands on one rig are not species-wide evidence.

The value therefore lives in `hand_fixture_compiler_calibration.gd` with an
explicit `CALIBRATION_ID`, `CALIBRATION_VERSION`, `CALIBRATION_STAGE` and the
list of rigs it was measured on, and is **injected** into the compiler. Its id
and version are part of the artifact's hashed identity, so changing the number
invalidates every existing artifact rather than quietly admitting more assets.
The value is unchanged in this slice; 0.35 and 0.45 are likewise unchanged.

## Certified fixture trust boundary (A2.12)

A2.11 made an artifact prove *which mesh* it belongs to. Three defects survived
that, all with the same shape — a check that could be satisfied without being
performed:

- a rig whose head bone was spelled `mixamorig_Head` measured height `0.0` and
  was rejected as `DEGENERATE_HEIGHT`, which is a false geometric claim about a
  perfectly good humanoid;
- `source_mesh_sha256` covered the vertex streams only, so moving a bone rest or
  a skin bind pose left the identity intact while every compiled bone-local
  marker moved;
- a classified-REJECTED asset's staged artifact loaded successfully, bound
  against its own mesh, and was kept out of the game only by its file location.

### Height landmarks are semantic roles owned by the family

`HEIGHT_HEAD_CANDIDATES = ["head_end", "Head"]` was a global string list in
generic code, so it could not see raw-Mixamo spelling however many prefix
variants were added elsewhere. Adding `mixamorig_Head` to the list would have
been the same defect one asset later.

Instead, height landmarks are now **semantic roles** resolved through the
injected skeleton family:

| Role | Meaning |
| --- | --- |
| `head_top` | the topmost cranial landmark |
| `foot_floor` | the ground-contact landmarks, both sides |

`mixamo_52_hand_family.gd` owns the alias table and `resolved_height_landmarks()`
maps each role to a bone that actually exists on *this* skeleton, using the same
alias prefixes the hand map already uses. `humanoid_hand_profile.gd` asks the
family; `skinned_mesh_geometry.gd` measures whatever it is handed. Neither
knows the string `mixamorig`, and the architecture test asserts that: the three
generic files are read as text and must not contain any rig prefix of their own.

The measurement declares its space (`HEIGHT_MEASURE_SPACE`, skeleton space — the
same canonical space the fixture is compiled in), so ancestor scale and
placement cannot change the number. Raw Mixamo and the Godot retarget of the
same humanoid measure `0.888740688562393` to within `1e-9`, and that value is
pinned in the test.

**Unresolved is not degenerate.** They are different facts and now have
different error classes:

| Situation | Error |
| --- | --- |
| a landmark role has no bone on this rig | `HUMANOID_HEIGHT_LANDMARKS_UNRESOLVED` |
| the family declares no landmarks at all | `HUMANOID_HEIGHT_LANDMARKS_UNRESOLVED` |
| an alias points at a missing or wrong-side bone | `HUMANOID_HEIGHT_LANDMARKS_UNRESOLVED` |
| landmarks resolved, and the geometry really is flat | `DEGENERATE_HEIGHT` |

`DEGENERATE_HEIGHT` is a claim about geometry and may only be made once the
landmarks are validly resolved.

### Four identity levels (A2.11's three, split where it mattered)

Level 1 of the A2.11 table conflated geometry with deformation. It is now two
levels, because a mesh can be bit-identical while the thing that deforms it has
moved:

| Level | Question | Function | Failure |
| --- | --- | --- | --- |
| **1a. Geometry identity** | are these the same surfaces, vertices, indices, normals and UVs? | `Compiler.geometry_identity()` → `source_geometry_sha256` | `FIXTURE_GEOMETRY_HASH_MISMATCH` |
| **1b. Rig / deformation identity** | will this rig deform that geometry identically? | `Compiler.rig_identity()` → `source_rig_sha256` | `FIXTURE_RIG_HASH_MISMATCH` |
| **2. Fixture content identity** | is this payload exactly what the compiler produced? | `Compiler.content_hash()` | `FIXTURE_ARTIFACT_HASH_MISMATCH` |
| **3. Certification identity** | did the whole acceptance chain pass, for these identities? | `Certification.certification_hash()` | `FIXTURE_CERTIFICATION_HASH_MISMATCH`, `FIXTURE_NOT_CERTIFIED` |

`source_mesh_sha256` is gone rather than reinterpreted: the two new names say
what they actually bind. Rig identity covers skin bone indices, skin weights,
skin bind matrices, the bone-name/semantic mapping, the parent hierarchy, every
bone rest transform, and the mesh→skeleton relation as imported.

It is deliberately invariant to things that do not change deformation:

| Change | Invalidates? |
| --- | --- |
| skin bind pose | yes |
| bone rest transform | yes |
| bone parent hierarchy | yes |
| skin weights or bone indices | yes |
| vertex positions or indices | yes (geometry) |
| current animation pose | no |
| ancestor transform, scale, placement | no |
| new process | no |

### Compiled evidence, rejected diagnostic, certified fixture

The compiler must not be able to mint a licence for its own output, so
acceptance is no longer a property of *where a file sits*. There are three
states and one direction:

| State | Schema | Runtime-valid? |
| --- | --- | --- |
| compiled evidence (staging) | `hand_fixture_evidence_v3` | never |
| rejected diagnostic | `hand_fixture_evidence_v3` | never — no envelope can exist for it |
| certified runtime fixture | `hand_fixture_certification_v1` | only this |

`hand_fixture_certification.gd` owns the boundary, because only the step that
observed the whole chain can attest to it. A staging artifact copied or renamed
onto the published path is refused **by type**: it carries no `certification`
property at all, so `load_certified()` reports `FIXTURE_NOT_CERTIFIED` without
having to inspect a flag that the file could simply have set.

A lone `certified = true` would be worthless, so the envelope names every
identity the acceptance was true *for*, and its own hash covers all of it:

- fixture content hash, with the evidence payload embedded verbatim;
- `source_geometry_sha256` and `source_rig_sha256`;
- family id + family version, and the family bone-map digest;
- compiler version, evidence schema, compiler-calibration id + version;
- policy id + version and policy-calibration id + version;
- acceptance schema + version, the completed chain, the certified sides;
- a digest of the canonical acceptance report — the gate results themselves.

Consequences, each with its own regression: editing the verdict without
re-hashing is caught by the certification hash; swapping the acceptance report
for another one that says `pass` is caught by the report digest; and an
*honestly* re-hashed certificate whose report is not a pass, or whose
`certified` is `false`, is still refused.

### Certification authority: who runs the chain (A2.13a)

**A2.12's own trust boundary was inverted, and the paragraph above overstated
what its envelope proved.** A2.12 moved certification out of the compiler but
left the *chain* in the headless CLI, and `Certification.certify()` took the
completed chain and the acceptance verdict **as parameters**. So this minted a
certificate:

```gdscript
Certification.certify(evidence, {
    "chain": Certification.REQUIRED_CHAIN,
    "acceptance_report": {"pass": true},
    ...
})
```

The result verified, loaded through the production loader, assembled as
`certified_bound`, reported `verified = true` and survived a save/load round
trip — with **zero gates run**. The envelope proved INTEGRITY (nothing drifted
after minting). It never proved EXECUTION. Anything above that reads as "the
certificate proves the chain passed" was, before A2.13a, "the certificate
records that its caller said the chain passed".

A2.13a removes the inversion by moving the chain to the certification side:

| Owner | Responsibility |
| --- | --- |
| `hand_fixture_certification_authority.gd` | runs the whole acceptance chain on real dependencies; the only public certification entry point |
| `hand_fixture_certification.gd` | builds the canonical report from the authority's observations, mints and verifies the envelope |
| `tools/certify_hand_fixture_headless.gd` | a CLI **adapter**: arguments, paths, transport, report, exit protocol |

The authority takes inputs only — an asset path, a staging path, the hands, a
policy id, a weapon — and resolves the family and the policy from its own
registries. There is **no parameter** through which a caller can assert a
completed chain, a gate result, an acceptance verdict or an identity that was
not derived from the asset. It then, itself: imports the asset, resolves the
family, measures the humanoid, compiles the evidence, writes and re-reads it,
derives both source identities from the asset on disk, drives the real
production assembler and reads the achieved contact out of the real grip
engine.

The acceptance report is an **output**. Each chain step contributes an entry
carrying its own observation, and `verify` re-derives the verdict from those
entries rather than reading a declared one:

| Step | Real operation | Observation bound to the run |
| --- | --- | --- |
| `import` | instantiate the asset the authority loaded itself | bone count, skeleton node |
| `family_resolution` | the family's own alias resolution | resolved family id + version, representation, hand bone |
| `humanoid_normalization` | measure semantic landmarks in the canonical space | height, space, landmark bones |
| `fixture_compilation` | `Compiler.compile` | evidence content hash, compiled sides |
| `artifact_integrity` | save then load from disk | reloaded content hash |
| `rig_binding` | `rig_identity_of_asset` on the file | geometry + rig identity |
| `assemble_and_measure` | the real assembler + grip engine | achieved `closest_patch`, invariant verdict, live binding |

`bind_sanity` and `grip_ground_truth` were merged. They were never two
independent gates: the surface-truth gate runs inside `assemble()`, and the
second step only re-read `closest_patch` out of the first step's result.
Claiming two gates for one measurement is the same species of defect as
claiming a chain that never ran, so the honest contract is one
`assemble_and_measure` step. `ACCEPTANCE_SCHEMA` is therefore
`hand_fixture_acceptance_v2`, and an A2.12 certificate is refused rather than
reinterpreted.

The chain needs a fixture before a certificate exists, because the assembler
accepts nothing else. A2.12 handled that by minting an ordinary certificate that
claimed the whole chain and set `provisional: true` — a field no consumer read.
That object now carries a different `acceptance_schema`
(`hand_fixture_acceptance_provisional_v2`), so `verify` refuses it unless the
caller explicitly opts in, and `Certification.save()` refuses to write it at
all.

### Certificate verification vs runtime verification — both are required

These prove different things and neither replaces the other.

| | Certificate verification (`Certification.verify`) | Runtime verification (`verify_against_rig` + assembler gates) |
| --- | --- | --- |
| Runs | when a certificate is read | every time a fixture is used |
| Proves | envelope and embedded evidence have not drifted; the certificate has the shape only the canonical path produces; it is bound to a specific evidence payload, geometry, rig, family + version and policy + calibration; the recorded verdict follows from the recorded step observations | the live mesh and rig still match the certified identities; the injected family and policy still match; bind sanity and the socket work *now*; the achieved geometry passes *now* |
| Does **not** prove | that the recorded measurements were really taken | anything about history |

The residual is stated deliberately: without a signing authority, no local check
can prove a measurement happened. A forger holding the real asset who
fabricates a fully self-consistent step set gets past `verify`. What closes the
hole is that (a) the public API has no parameter through which a verdict can
enter, so the canonical path is the only supported producer, and (b) the runtime
gates re-run on the actual rig and are the live safety property. A certificate
is prior acceptance evidence, never a permission to skip a gate.

What `verify` now refuses, each with a regression, and each **after** the
forgery has been honestly re-digested and re-hashed:

| Forgery | Error |
| --- | --- |
| a bare `{"pass": true}` report | `FIXTURE_NOT_CERTIFIED` |
| a report naming no authority | `FIXTURE_NOT_CERTIFIED` |
| a report for another asset's geometry / rig | `FIXTURE_GEOMETRY_HASH_MISMATCH` / `FIXTURE_RIG_HASH_MISMATCH` |
| a report naming a policy or calibration version that is not the envelope's | `FIXTURE_NOT_CERTIFIED` |
| a report naming another family or family version | `FIXTURE_FAMILY_MISMATCH` / `FIXTURE_FAMILY_VERSION_MISMATCH` |
| a chain that omits, duplicates or reorders a step | `FIXTURE_NOT_CERTIFIED` |
| a step with no observation, an invented extra step, or a `FAIL` step under a `PASS` conclusion | `FIXTURE_NOT_CERTIFIED` |
| a recorded achieved contact on the nail | `THUMB_SURFACE_TRUTH_GATE_FAILED` |
| recorded grip invariants that did not pass | `GRIP_GEOMETRY_FAILED` |

Every one of those is also offered to `save()` + `load_certified()` and to the
runtime loader, and refused identically: the file is not the boundary.

Finally, the pose calibration is bound. A certificate records the policy and the
calibration its achieved geometry was measured under, so injecting a different
calibration payload is `FIXTURE_CALIBRATION_MISMATCH` /
`FIXTURE_CALIBRATION_VERSION_MISMATCH`, and assembling under another policy or
policy version is `FIXTURE_POLICY_MISMATCH` /
`FIXTURE_POLICY_VERSION_MISMATCH`. A retuned pose cannot inherit an acceptance
that was never measured for it.

Publication is atomic: the certificate is written to staging, verified by
re-reading it from disk, and only then moved onto the published path. An
interrupted publish leaves the previous accepted artifact intact, and a
rejection never overwrites or deletes an accepted one — a rejected asset never
reaches the publish step at all.

### Family version is verified, not merely hashed

`family_version` was inside the payload hash but nothing ever compared it to the
family actually in use. Now the runtime caller supplies the expected family id
**and** version independently of the artifact, at both load and assembly:

| Situation | Error |
| --- | --- |
| certificate issued for another family | `FIXTURE_FAMILY_MISMATCH` |
| certificate issued for another family version | `FIXTURE_FAMILY_VERSION_MISMATCH` |
| caller states no expected version, or the injected family declares none | `FIXTURE_FAMILY_VERSION_MISMATCH` |

An empty expectation is a refusal, not a skipped check. Compiler and calibration
versions are checked separately and are not accepted as a substitute.

### Verification is a declared contract, not a method that happens to exist

`EquipmentAssembler` used to probe `fixture.has_method("verify_against_mesh")`
and treat absence as "unbound but fine", so any fixture could opt out of
identity verification by not implementing it — which is exactly how the
hand-authored A2.7 oracle assembled with `verified: false`.

Every fixture used in an assembly must now **declare** a contract, and the
assembler dispatches on the declaration:

| `fixture_verification_contract()` | Meaning |
| --- | --- |
| `certified_runtime_v1` | must verify against the live rig; an unverified or failed result is a refusal |
| `test_only_reference_v1` | the development oracle; two independent gates required |
| anything else, or nothing | `FIXTURE_BINDING_UNSUPPORTED` |

Named failures: `FIXTURE_VERIFICATION_REQUIRED` (claims the certified contract
but cannot honour it, or returned `ok` without `verified`),
`FIXTURE_NOT_CERTIFIED`, `FIXTURE_BINDING_UNSUPPORTED`,
`FIXTURE_REFERENCE_MODE_FORBIDDEN`. None of them can be reached after a pose or
socket has been touched: binding is still the assembler's first action.

The decisive regression is a fixture that implements `verify_against_rig`
*perfectly* — it would have sailed through the old duck-typed opt-in — and is
refused anyway, because it declares no contract.

### The authored oracle is test-only

`uthana_warrior_hand_fixture.gd` declares `test_only_reference_v1` and needs two
independent gates to be usable: the caller must inject
`reference_fixture_mode`, **and** the environment must set
`EOM_ALLOW_REFERENCE_FIXTURE=1`. A production composition never sets the first;
a shipped runtime never sets the second, so reference mode self-fail-closes
outside a test harness with `FIXTURE_REFERENCE_MODE_FORBIDDEN`. Through the
normal production assembler the oracle is `FIXTURE_NOT_CERTIFIED`. The F6
preview continues to use the certified compiled fixture.

### Raw a0 through the whole chain

`generated_warrior_3d_uthana_rigged.glb` (raw Mixamo naming) was run through the
real CLI ingestion. Up to A2.13a it passed import, family resolution, humanoid
normalization (the A2.11 blocker), compilation of the right hand — but with
**4 nail / 7 pad** triangles where the retargeted delivery resolved 4 / 10 — and
was then classified `THUMB_OPPOSITION_GATE_FAILED` at `assemble_and_measure` on
both `thumb_approach_axial` and `thumb_approach_radially_outward`.

**The rest-basis diagnosis is refuted (A2.13a).** This section previously said
a0's thumb-chain rest orientations differ from the Godot-retargeted
representation the A2.7 angles were authored against, so the authored angles aim
the approach wrong. Direct measurement disproves it: a0 and a1 reach the **same
anatomical joint pose to within ~1.5°**, despite a 90° difference in the hand's
rest basis and a 100× armature scale, because the pose is applied as
rest-relative deltas about axes derived from the rig — the representation
difference is already normalised by the pipeline. What actually differed was the
**compiled surface**, and the compiled pad normal is an input to the derived
anatomical axes, so the surface difference rotated the very frame the approach is
measured in.

**A2.13b found the operation, and both deliveries now certify.** See
[Representation-invariant thumb surface (A2.13b)](#representation-invariant-thumb-surface-a213b)
below: the divergence was the per-triangle winding decision, which compared a
skeleton-space face normal against a mesh-space shading normal. With the surface
derived in one canonical space both deliveries resolve 4 nail / 10 pad, agree on
every achieved gate metric to ~5·10⁻⁵, and exit `0` with a loadable certificate —
against the unchanged A2.2/A2.7 thresholds. The axial margin is `0.0063` on both,
which is ~1% and is thin; two assets clearing it is not batch evidence.

## Representation-invariant thumb surface (A2.13b)

Two deliveries of one humanoid must compile the same nail and pad. Until A2.13b
they did not, and the difference was not geometry.

### The first diverging operation

A development diagnostic,
`presentation/equipment/tools/thumb_surface_correspondence.gd`, maps every
candidate triangle of two deliveries into **one common space** — the distal thumb
bone's own rest frame, with every length divided by that digit's own length and
every direction taken as a dot product against that hand's own volar/radial/axis
directions — and reports the first operation at which a corresponding pair
diverges. It reads the compiler's own per-candidate table rather than
reimplementing classification, so it cannot drift from what the compiler did. It
is not a gate and is not in any acceptance chain.

The answer: not the candidate set (both find 30), not the tip component (both find
20 triangles), not the centroid, not the station, and not the geometry. The
divergence was the **per-triangle winding decision**. A2.13a resolved a triangle's
outward sense by comparing its skeleton-space face cross product against the
imported shading normal carried by `pose · rest⁻¹` — a carry that omits the bind
pose and uses the basis where the **inverse-transpose** is required. The two
vectors compared lived in different frames, and whether that flipped a given
triangle depended on the delivery's bind representation. On the raw delivery **7 of
30** candidates are flipped by the superseded rule and not by the current one,
which is precisely the 7-versus-10 pad result and the ~55° nail-plate difference.

### Canonical surface space and the winding contract

Classification happens in `thumb_distal_rest_local_v2`:

| | how |
| --- | --- |
| positions | CPU-skinned vertices in skeleton space, carried into the distal bone's frame |
| directions | carried by each vertex's own **inverse-transposed blended skin basis**, with the reflection sign applied (`skinned_mesh_geometry.gd::skinned_normal_basis` / `skinned_normal_local`) |
| geometric normal | from the transformed triangle vertices, with explicit winding |
| winding | resolved **once for the whole surface** by consensus between the geometric outward direction and the transformed imported normals |
| shading normal | a cross-check, never the sole authority |
| ancestor transform | excluded entirely; skeleton space |

Both winding authorities must agree by a margin. Disagreement is
`PATCH_WINDING_UNDERIVABLE`, not a silent geometry-only decision, and there is no
per-triangle auto-flip. A negative determinant is handled explicitly rather than
absorbed. The A2.6/A2.7 contract that achieved-pose ground truth uses real
CPU-skinned triangles with renderer-equivalent bind matrices is unchanged.

### Independent anatomical surface validation

Before A2.13b the only checks on "is this the right surface" compared the fixture
with **itself**: the bind-time `|nail·pad − rest_nail_pad_dot|` test and the
achieved-pose equivalent. Both are true statements about deformation drift and
neither is evidence that the compiler picked the nail and the pad — a surface
classified onto the wrong side of the digit satisfies both perfectly, because it
is consistent with itself.

Those two checks are kept and renamed for what they measure
(`thumb_surface_evidence_incoherent`, `thumb_surface_deformation_drift`,
`thumb_surface_geom_deformation_drift`), and the anatomical question is answered
by `thumb_surface_anatomy.gd` — **one** implementation, called by the compiler on
the patches it just selected and by the grip engine's patch bind on the patches a
certified fixture claims. Every verdict comes from information the chosen patch's
own normals do not produce:

| Class | What is refused |
| --- | --- |
| `NAIL_PATCH_NOT_DORSAL_RADIAL` | the nail centroid does not sit on the distal dorsal-radial flank |
| `PAD_PATCH_NOT_VOLAR` | the pad centroid does not sit on the volar side |
| `NAIL_PAD_SAME_SIDE` | the plates are not separated across the digit, or the pad is not volar of the nail |
| `NAIL_PAD_PATCH_OVERLAP` | a triangle is claimed by both plates |
| `PATCH_NOT_DISTAL_STATION` | a plate's area sits past the midpoint of the distal segment |
| `PATCH_WEIGHT_BLEED_COMPONENT` | too few of a plate's vertices are dominated by the distal segment |
| `PATCH_NORMAL_DISPERSED` | a plate is not a plate |
| `THUMB_ANATOMY_FRAME_UNDERIVABLE` | the resolved chain yields no usable digit frame |
| `THUMB_ANATOMY_PATCH_MISSING` / `_ON_AXIS` / `_DEGENERATE` | the context cannot be evaluated |
| `HAND_FRAME_RADIAL_INCONSISTENT` | the frame's declared radial axis contradicts the side its own thumb landmark sits on |

A refused bind surfaces as `GRIP_SURFACE_ANATOMY_REJECTED` /
`thumb_surface_anatomy_rejected`. The 0.35, 0.45 and 0.08 classification values are
untouched. Chirality is **cross-checked** rather than trusted: the shared
`hand_fixture_compiler.gd::frame_radial()` re-derives the radial sign from the
frame's own thumb landmark and compares it with any declared `radial`.

### The pad normal keeps its role in the pose axes

With the surface corrected the two deliveries agree on the pad normal to
`dot ≈ 1.0` (they were 6.7° apart), so the
`pad_rest_w → v_flesh → f_hat → MCP/IP flexion axis and CMC swing basis` coupling
in `_derive_thumb_anatomy()` is stable and produces equivalent axes from both.
The mesh-adaptive coupling therefore stays, and the independent anatomy module is
the input validation it was missing. No new joint basis, no copied quaternions, no
per-asset angle, no new calibration.

### Measured result, and its sensitivity

Both deliveries resolve **4 nail + 10 pad**, `rest_nail_pad_dot ≈ −0.0177`, and
both pass the whole chain to a loadable certificate with `closest patch = pad`.
Achieved gate metrics agree to ~5·10⁻⁵:

| metric | raw | retargeted | limit |
| --- | --- | --- | --- |
| `approach_axial_fraction` | 0.593724 | 0.593774 | ≤ 0.60 |
| `approach_radial_radii` | 0.055441 | 0.055421 | ≤ 0.15 |
| `winding_thumb_deg` | 85.461849 | 85.460202 | ≥ 60 |
| `nail_out_dot` | 0.749874 | 0.749885 | ≥ 0.30 |
| `pad_in_dot` | 0.629504 | 0.629488 | ≥ 0.30 |

**The R4 axial margin is `0.0063` (~1%) on both.** Nothing was tuned: τ, σ, the
authored angles, the R4 limit and the approach thresholds are the A2.2/A2.7
values. Two deliveries of one humanoid clearing a 1% margin is evidence about
representation invariance, not about an arbitrary rig.

### The two F6 paths, and the visual result

`uthana_a2_dual_certified_grip_preview.tscn` runs **both** deliveries through the
real certification authority and the generic assembler, with `A` switching
delivery and `C` switching between a **grip close-up** and a **body overview**.
Same club, same socket, same static certified grip pose, no authored oracle. The
HUD names the active delivery and view and reports `certified`, fixture owner,
gate verdict, nail/pad counts, approach axial/radial with their limits, the
achieved closest patch and the club's own attached/in-frame state.

Two rules the preview obeys, because both were violated and caught by the visual
check itself:

- `closest patch` is read from the authority's record of the achieved-geometry
  step — the value the grip engine measured and the gate compared — never
  re-derived for display. When that step was not reached the HUD names the
  absence instead of printing a patch name. It previously read a `surface` block
  off the assembler result, which does not carry one, and displayed `?`.
- **Neither view hides the weapon.** Both cameras are placed relative to the club
  the assembler built, so neither can put the torso between camera and grip. The
  overview camera previously stood on a fixed side of the scene with the club
  behind the body, and an occluded club is indistinguishable on screen from a
  failed attachment. There is deliberately no weapon-hiding view mode, so that
  ambiguity cannot return as a feature.

**Visual result: accepted by the user on both deliveries** — the grips look
practically identical, sit stably around the club and show no representation
effect, float or gross penetration. The two defects above were fixed after that
check and touched only the preview: no compiler, surface-derivation, grip-engine
or gate change, and the accepted close-up framing is unchanged.

### A finding on the left hand

The independent validator refuses the A2.8 hand-authored **left** reference
fixture, earlier than the T2 contour gate that used to classify it: its nail plate
sits at −0.917 along the dorsal-radial bisector this hand's own frame derives —
the dorsal-*ulnar* flank. That authored surface was self-consistent and
anatomically wrong, which is the exact class this validation exists to catch. The
left side remains unsolved by design and its compiler-side `PAD_PATCH_AMBIGUOUS`
fail-close is unchanged.

Compiler version: `hand_fixture_compiler_v4` / `hand_fixture_evidence_v4`. A2.13a
evidence is refused rather than reinterpreted.

### Proof limitation and next implementation slice

Current executable proof covers the present Mixamo-52 / Uthana warrior family
and the current cylindrical one-handed weapon. Only this unit is visually
validated; batch multi-unit robustness is untested. The A2.9 injection-stub
test proves the ARCHITECTURE consumes injected family/fixture identities —
it is not visual multi-unit validation.

Stage: **CALIBRATING.** The compiler is proven on one reference rig. That is not
BATCH_CERTIFICATION (the same profile compiling and passing across several
independent rigs) and not PRODUCTION_CERTIFIED (batch-green runs with no human
approval step). `certification_stage()` in `hand_fixture_ingest.py` refuses to
report a single certified unit as anything above CALIBRATING.

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

Done by A2.9b (2026-08-25): the grip mechanism moved out of the central
dispatch into the interaction policy that owns it, so a future profile is a
new file plus one registry row (or an injected `policies` entry) rather than
an edit to shared solver flow; the unit fixture moved out of the generic
core directory and stopped selecting its own skeleton family; and the
architecture tests were extended with a directory-level ban on unit/asset
files in the core plus a genuinely synthetic unit (own fixture data, own
identity, procedurally built weapon) proving the unmodified core consumes
injected data and rejects fabricated patch evidence with a classified
`GRIP_PATCH_BIND_FAILED` instead of a silent pass. Right-hand A2.7 metrics
were re-measured through the live generic path and are unchanged within the
pinned tolerances. This is development calibration of the generic production
code, not a manual production step: future runtime production is intended to
be automatic, without human approval per unit.

Done by A2.10 (2026-08-25): the last manual per-unit step is gone. The thumb
surface evidence is compiled automatically from the rigged mesh, written as a
versioned self-hashed artifact, and consumed by the Uthana production
composition instead of the hand-authored fixture — which is now reference and
negative regression only, and is no longer loaded on the production path. The
full 4×3 parity matrix, surface ground truth and yaw invariance run through the
compiled artifact with no gate or pose recalibrated. The remaining hardcoded
`mixamorig_LeftHandThumb*` names were removed from the reference fixture, which
now takes its bone names from the injected family map.

Done by A2.11 (2026-08-26): the artifact can no longer vouch for itself. Content
identity is canonical (skeleton space, pinned rest pose, one declared stored
precision, whole-payload coverage) and now reproduces across a separate Godot
process and the scaling/scene contexts that previously diverged; live-mesh
binding is mandatory and is the assembler's first action, with the expected
identity derived from the asset rather than the payload; the ingestion chain from
import to grip ground truth is owned, callable and documented
(`tools/assetgen/rig_ingest.py`, `ingest-rig`) with a 0/2/1 exit protocol; the
family owns its bone-name aliases so a0 is no longer called fingerless; and the
0.08 margin is declared CALIBRATING data in its own versioned owner. No pose,
socket parameter, surface gate or contact angle was changed: right A2.7 parity,
the A2.6 `tau = −90°` rejection and the left fail-close are unchanged.

Done by A2.13b (2026-08-27): the compiled thumb surface stopped depending on how
the humanoid was delivered. The winding decision moved from per-triangle
frame-mismatched comparison to one surface-level consensus in a canonical rest
space, normals are carried by the inverse-transposed blended skin basis, and the
"is this the right surface" question moved out of the fixture's self-comparison
into `thumb_surface_anatomy.gd`, which both the compiler and the runtime bind ask
from the live rig's own frame. Both deliveries of the reference humanoid now
resolve the same 4 nail / 10 pad plates and certify against unchanged gates, with
the achieved metrics agreeing to ~5·10⁻⁵ and the R4 axial margin at ~1% on both.
The A2.8 authored **left** reference fixture is refused by the new validation as
anatomically wrong, which is a finding rather than a regression; left remains
unsolved.

Bilateral runtime is **not** established: only the right hand passes.
Multi-unit batch certification has **not** started; the breadth run over the
existing humanoid assets is diagnostic only. Two deliveries agreeing is
representation invariance, not batch robustness.

Remaining next slices (in no fixed order):

1. resolve the left T2/distal-station conflict without weakening the accepted gates, then pass the complete left wrap + contour + surface pipeline;
2. batch certification of the compiler across several independent rigs (see the CALIBRATING → BATCH_CERTIFICATION → PRODUCTION_CERTIFIED stages above);
3. secondary-hand IK when a two-handed policy is actually needed.

## Known production gap (separate slice)

The production Meshy club path still uses `one_handed_palm_frame.gd` (det = −1, unverified normal) and `test_generated_warrior_equipment.gd` (“club points grip→head along palm +Y”). Migrating production to this contract must not be done as a side effect.
