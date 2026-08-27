# Hand-fixture certification and a0 thumb representation — independent review

Audit only. No production code, test or existing steering document was changed.
No commit. Entirely local: no provider, network or credential access.

Scope: the slice that concludes with *"Raw Uthana ingestion and certified fixture
trust boundary established; paid provider batch not started."*

Stage: `CALIBRATING`.

## 1. Baseline

| Item | Value |
| --- | --- |
| HEAD | `aa5418a Generative units PoC` |
| Worktree | intentionally dirty, preserved unchanged (A2.9b–A2.12 + C1) |
| Change set | 19 tracked files modified/renamed, 2263 insertions / 275 deletions, plus untracked new files |

Confirmed baselines, before and after the review:

| Check | Expected | Observed |
| --- | --- | --- |
| `slice a1` | 71 | 71, OK |
| `slice a2` | 1720 | 1720 across 7 suites, OK |
| `slice c1` | 22 | 22, OK |
| `pytest tools/assetgen/tests` | 99 | 99 passed |
| `scripts/scan-secrets.py` | green | no secret-shaped content (79 files after cleanup; 93 while the temporary probes existed) |

### File attribution

**A2.9b–A2.12 (equipment / hand fixture / grip):**
`game/presentation/equipment/` — `hand_fixture_compiler.gd`,
`hand_fixture_compiler_calibration.gd`, `hand_fixture_certification.gd`,
`certified_hand_fixture_artifact.gd`, `hand_fixture_artifact.gd`,
`compiled_hand_fixture.gd`, `power_grip_1h_policy.gd`,
`power_grip_1h_calibration.gd`, `tools/certify_hand_fixture_headless.gd`,
and the modified `equipment_assembler.gd`, `grip_interaction_profile.gd`,
`humanoid_hand_profile.gd`, `mixamo_52_hand_family.gd`,
`skinned_mesh_geometry.gd`; the `uthana_a2/` composition, power-grip, preview
and relocated `uthana_warrior_hand_fixture.gd`; tests
`test_hand_fixture_certification.gd`, `test_hand_fixture_compiler.gd`,
`test_hand_fixture_identity.gd`, `test_equipment_interaction_pipeline.gd`,
`test_uthana_a2_power_grip_parity.gd`; `tools/assetgen/hand_fixture_ingest.py`,
`tools/assetgen/rig_ingest.py` and their tests;
`docs/EQUIPMENT_INTERACTION.md`, `A2_NOTES.md`.

**C1 (asset provider pipeline / shield):**
`tools/assetgen/` provider, transport, manifest, store, orchestrator, CLI,
`glb_reader.py`, `mesh_metrics.py`, `humanoid_gate.py`, `shield_analysis.py`,
`shield_pipeline.py`, `secret_guard.py`; `scripts/scan-secrets.py`;
`.env.example`; `game/presentation/diagnostics/shield_inspection_diagnostic.*`
and `test_shield_inspection_diagnostic.gd`;
`docs/ASSET_PROVIDER_PIPELINE.md`; `artifacts/assetgen/**`.

Shared/both: `docs/CURRENT_ARCHITECTURE.md`, `docs/DECISION_LOG.md`,
`docs/TESTING.md`, `scripts/run-godot-tests.ps1`, `.gitignore`.

## 2. Verdicts

| Area | Verdict |
| --- | --- |
| SEMANTIC HEIGHT RESOLUTION | PARTIAL |
| GEOMETRY IDENTITY | PASS |
| RIG/DEFORMATION IDENTITY | PASS |
| STAGING ISOLATION | PASS |
| CERTIFICATION ENVELOPE | PARTIAL |
| ACCEPTANCE REPORT INDEPENDENCE | FAIL |
| ATOMIC PUBLICATION | PASS |
| FAMILY VERSION ENFORCEMENT | PASS |
| MANDATORY RUNTIME VERIFICATION | PASS |
| AUTHORED ORACLE ISOLATION | PASS |
| A2.7 PARITY | PASS |
| A0 FAILURE DIAGNOSIS | FAIL |
| REPRESENTATION-GENERAL THUMB READINESS | UNPROVEN |
| PAID BATCH READINESS | FAIL |

## 3. Findings

### BLOCKER

#### B1. Certification records a verdict; it does not verify one

**File/function:** `hand_fixture_certification.gd::certify()` / `verify()`,
`tools/certify_hand_fixture_headless.gd:285-295, 380-386`.

**Evidence.** `certify()` takes `chain` and `acceptance_report` as caller
parameters and copies them into the envelope. `verify()` re-checks the
envelope's own hash, the embedded evidence's content hash, the two identity
hashes, the acceptance schema, `certified == true`, that `chain` contains every
entry of `REQUIRED_CHAIN`, and that `acceptance_report["pass"]` is true. It
re-derives nothing about the gates.

A probe that ran **no gate at all** — compile evidence, then call `certify()`
with `chain = REQUIRED_CHAIN.duplicate()` and
`acceptance_report = {"pass": true}` — produced a certificate that:

```
forge_mint = ok=true
forge_verify = true
forge_loads_as_runtime_fixture = ok=true
forge_assembles = ok=true verified=true binding=certified_bound
forge_saved = true
forge_reloads_from_disk = ok=true
```

A separate probe replaced a real certificate's acceptance report with one
naming a different asset, a different side and a non-existent policy, honestly
re-digested it and re-hashed the envelope:

```
foreign_acceptance_report_reused = verify_ok=true
foreign_report_loads = OK_LOADED
contentless_acceptance_report = verify_ok=true
```

**Broken contract.** The slice requires that only the complete acceptance chain
can produce the resource type and envelope runtime demands, and that an invented
`accepted = true` is insufficient. Both are violated: the certificate's
evidentiary content is exactly *"the minter had the real rigged mesh"*. Every
other claim in it — which gates ran, against which policy, with what result — is
an unverified assertion by whoever called `certify()`.

**Mitigation, stated honestly.** The production assembler re-runs bind sanity
and the grip gates on every assembly, so a forged certificate over a *failing*
asset still fails closed. The same probe pipeline applied to raw a0 yields
`assemble ok=false err=THUMB_OPPOSITION_GATE_FAILED` even though its forged
certificate loads and verifies. The trust boundary is therefore defended by the
runtime gates, not by the certificate. That is a materially weaker property than
the one documented.

**Why existing tests miss it.** They cannot catch it, because they *depend* on
it: `test_hand_fixture_certification.gd:879-893` (`_params()`),
`test_hand_fixture_identity.gd:465` and `test_hand_fixture_compiler.gd:776, 928`
all mint their positive-case certificates with a hand-written
`{"pass": true, "certified_side": ...}` report and a hardcoded
`REQUIRED_CHAIN.duplicate()`. The suite proves that a certificate whose report
says `pass: false` is refused, and that a *removed* chain step is refused, but
never that a report has to be the product of gates that ran.

**Minimum correction.** Make the report structurally unforgeable rather than
declarative: have `certify()` require, for each entry of `REQUIRED_CHAIN`, a
corresponding sub-dictionary in the report carrying the step's own measured
evidence (the identity hashes it observed, the measured height, the invariant
verdict, the achieved `closest_patch`), and refuse when a step is present in
`chain` but has no evidence body, when a step's recorded identity hashes differ
from the envelope's, or when the report's `policy_id` differs from the
envelope's. That keeps `certify()` a pure function while removing the
"trust the caller's summary" hole.

#### B2. The recorded root cause of the a0 thumb rejection is refuted by measurement

**File/function:** `test_hand_fixture_certification.gd:789-815`,
plus the matching narrative in `A2_NOTES.md` and `docs/EQUIPMENT_INTERACTION.md`.

**Evidence.** The recorded diagnosis is:

> a0's thumb chain rest orientations are 90 degrees from the Godot-retargeted
> representation the A2.7 pose was calibrated on, so the authored joint angles
> put the thumb's APPROACH direction wrong while every magnitude invariant
> passes.

A full-chain probe assembled both representations through the real assembler and
read the achieved joint angles out of the grip engine's own diagnostics:

| achieved | a1 (accepted) | a0 (rejected) |
| --- | --- | --- |
| `cmc_flex_deg` | 26.846 | 25.352 |
| `cmc_twist_deg` | -58.635 | -58.783 |
| `mcp_flex_deg` | 8.288 | 8.662 |
| `ip_flex_deg` | 79.315 | 79.465 |

The authored calibration is `sigma 20, tau -60, flex_mcp 10, flex_ip 80`. Both
rigs reproduce it to within 1.5 degrees. A 90-degree representation error in
the applied pose cannot produce 1.5-degree agreement. The hand frame, socket,
finger poses, volar probe and every magnitude invariant come out numerically
identical between the two representations (`dot_da = 0.97814762592316`,
`hand_length = 0.06156502664089`, `radius_mean = 0.01325370240319`, identical
`mcp_projections` and `hinge_dots` on both). The pipeline already normalises the
representation difference — which is real: a0's `mixamorig_RightHand` rest basis
is a 90-degree X-axis permutation of a1's `RightHand` basis
(`REL_global_rest[hand] = 89.756 deg about (−0.012, 0.999, −0.047)`), and a0's
armature carries scale 0.01 against a1's 1.0.

**Broken contract.** The slice's own honesty requirement. The diagnosis is
recorded as fact in a passing test's comment, in the notes and in the
architecture documentation, and the documented next step ("retarget the
canonical grip pose through the rest representation") is therefore aimed at a
mechanism that is not the cause.

**Why existing tests miss it.** The a0 test asserts only the *shape* of the
rejection (`THUMB_OPPOSITION_GATE_FAILED`, the two approach failure names, and
that magnitude invariants pass). Nothing compares achieved thumb angles between
representations, which is the measurement that discriminates.

**Minimum correction.** Replace the comment and the notes with the measured
classification in §4 below. No code change is required for the correction
itself.

### HIGH

#### H1. The surface-consistency gate is self-referential, so "the surface is innocent" is unprovable by it

**File/function:** `power_grip_1h_engine.gd:1393-1399`;
assertion at `test_hand_fixture_certification.gd:809-812`.

**Evidence.** The gate is

```
absf(metrics["nail_pad_dot"] - metrics["rest_nail_pad_dot"]) > 0.15
    -> "thumb_surface_orientation_inconsistent"
```

`rest_nail_pad_dot` is read straight out of the fixture being validated. The
gate therefore asks "did posing preserve the compiled relationship", never "is
the compiled relationship right". It passes for any compiled surface. The
measured values show how much that hides:

| compiled surface | a1 | a0 |
| --- | --- | --- |
| pad triangles | 10 | 7 |
| `rest_nail_pad_dot` | -0.017715 | **-0.854106** |
| `nail_axis_dot` | 0.235 | 0.542 |
| candidate triangles / tip triangles | 30 / 20 | 30 / 20 (identical) |
| `winding_flips` | authored 0, flipped 30 | authored 7, flipped 23 |

The test nevertheless asserts `"a0's compiled thumb SURFACE is not the problem"`
purely from `thumb_surface_failures` being empty — exactly the inference the
audit brief warns against. The two rigs have the *same* thumb-tip topology (30
candidates, 20 tip triangles) yet the compiler classified different pad patches
and produced nail plates 55 degrees apart.

**Broken contract.** The fixture compiler owns surface evidence and the
ground-truth gates are supposed to judge achieved geometry against something
external. This gate has no external anchor.

**Minimum correction.** Anchor the nail/pad relationship to the family's
anatomical expectation rather than to the fixture's own recorded value: gate
`nail_pad_dot` against a family-level opposed-plate bound, and additionally
report `rest_nail_pad_dot` as a *compile-time* confidence input so that a value
near -0.85 versus near 0.0 is visible as a classification difference rather than
as a self-consistent fact.

#### H2. The R4 approach gate passes the accepted asset by a 1.0 percent margin

**File/function:** `power_grip_1h_engine.gd:33-34, 1376-1381`.

**Evidence.** `THUMB_APPROACH_AXIAL_FRAC_MAX = 0.60`. Measured
`approach_axial_fraction`: a1 = 0.593774 (passes with 0.0062 of headroom),
a0 = 0.608828 (fails). A sensitivity sweep on the **accepted** asset:

| perturbation of the authored calibration | axial | radial | gate |
| --- | --- | --- | --- |
| none | 0.593774 | 0.055421 | pass |
| sigma −1 | 0.595879 | 0.060053 | pass |
| sigma −2 | 0.597635 | 0.060109 | pass |
| sigma −4 | 0.601832 | 0.069161 | **fail** `thumb_approach_axial` |
| tau −3 | 0.563888 | -0.007539 | pass |
| tau −6 | 0.532268 | -0.072941 | **fail** `thumb_axial_travel_dominates` |
| tau +3 | 0.621618 | 0.115380 | **fail** `thumb_approach_axial` |
| tau +6 | 0.647251 | 0.172068 | **fail** both approach gates |

The accepted calibration sits in a window narrower than ±3 degrees of authored
`tau`, and `tau + 6` reproduces a0's exact failure pair. a0's deviation is
quantitatively equivalent to a few degrees of legitimate per-asset variation.

**Broken contract.** A ground-truth gate is meant to separate a correct grip
from a defective one. At this margin it separates *the calibrated asset* from
everything else, which is what a paid multi-unit batch would run into.

**Minimum correction.** Before the batch, establish the gate's intended
separation empirically on more than one asset and widen or re-express the axial
metric so that the accepted pose is not within 1 percent of rejection. Do not
change the threshold to admit a0 specifically.

#### H3. Thirteen envelope fields can be rewritten and honestly re-hashed without detection

**File/function:** `hand_fixture_certification.gd::verify()`,
`compiled_hand_fixture.gd::from_certified_artifact()`.

**Evidence.** Every listed field was tampered with twice: once without
re-hashing, once with an honest re-hash, then offered to `verify()` and to the
real loader.

Tampering without re-hashing is caught for every field
(`FIXTURE_CERTIFICATION_HASH_MISMATCH`). Honest re-hashing is caught for
`fixture_content_hash`, `source_geometry_sha256`, `source_rig_sha256`,
`acceptance_report_digest`, `certified`, `acceptance_schema`,
`acceptance_version` (refused by `verify()`) and for `family_id` /
`family_version` (refused by the loader, via the caller's independent
expectation). It is **not** caught for:

`family_bone_map_digest`, `compiler_version`, `evidence_schema`,
`compiler_calibration_id`, `compiler_calibration_version`, `policy_id`,
`policy_version`, `policy_calibration_id`, `policy_calibration_version`,
`chain` (additions), `certified_side` / `required_sides` (additions),
`rig_identity_schema` — all `honest = ACCEPTED, loader = OK_LOADED`.

**Broken contract.** The envelope is documented as binding all
behaviour-affecting certification metadata. Inclusion in the hash prevents
casual corruption but is not enforcement: no field above is ever compared with
an independently supplied expectation.

**Minimum correction.** Extend the caller-supplied expectation dictionary that
already works for family id/version to cover policy id/version and policy
calibration id/version, and cross-check the envelope's duplicated evidence
fields (`compiler_version`, `evidence_schema`, `compiler_calibration_*`) against
the embedded evidence payload inside `verify()`.

#### H4. The certificate's policy binding is never enforced, and the accessor for it is dead code

**File/function:** `compiled_hand_fixture.gd:216-219` (`certified_policy()`).

**Evidence.** `certified_policy()` has no callers anywhere in `game/` — not the
assembler, not the composition, not any test. The assembler verifies the
certified *family* (`equipment_assembler.gd`, `FIXTURE_FAMILY_VERSION_MISMATCH`
raised at assembly, confirmed by probe) but never the certified policy, even
though it knows `_policy_id` (`equipment_assembler.gd:36, 313-321`). A
certificate minted for `power_grip_1h_v1` can therefore be consumed by any
policy, and — per H3 — can claim any policy id.

**Broken contract.** A certified fixture is certified *for a policy and a
calibration*; the pose numbers only mean anything relative to them.

**Minimum correction.** Have the assembler compare `certified_policy()` against
the `policy_id` it is assembling with, and the certificate's
`policy_calibration_id` / `policy_calibration_version` against the calibration
actually injected, refusing on mismatch — the same shape as the existing family
check.

#### H5. The provisional certificate claims the whole chain, and `provisional` is never checked

**File/function:** `tools/certify_hand_fixture_headless.gd:285-313`.

**Evidence.** To run bind sanity through the real assembler the tool mints a
certificate with `"chain": Certification.REQUIRED_CHAIN.duplicate()` and
`acceptance_report = {"pass": true, "provisional": true, ...}` — before
`bind_sanity` and `grip_ground_truth` have run. Nothing in `verify()` or
`from_certified_artifact()` reads `provisional`; a probe confirmed a report of
`{"pass": true}` alone verifies. The object is a fully privileged certificate
distinguished from a real one only by a field no consumer inspects. It is not
written to disk on the paths inspected, but that is a property of this one
caller, not of the type.

**Broken contract.** "Only the complete chain yields a runtime-loadable
fixture."

**Minimum correction.** Give the provisional certificate a distinct
`acceptance_schema` (for example `hand_fixture_acceptance_provisional_v1`) that
`from_certified_artifact()` accepts only when the caller explicitly asks for a
bind-sanity-scoped fixture, and that `Certification.save()` refuses to write.

### MEDIUM

#### M1. The declared canonical height space is not invariant to ancestor transforms

**File/function:** `skinned_mesh_geometry.gd:135-232`
(`HEIGHT_MEASURE_SPACE := "skeleton_global_rest"`, `_rest_y()`).

**Evidence.** `_rest_y()` returns
`(skeleton.global_transform * skeleton.get_bone_global_rest(i)).origin.y`, so the
host's scale enters the number directly:

| host scale | a1 height | a0 height |
| --- | --- | --- |
| 1.0 | 0.888740688562 | 0.888740688562 |
| 0.3 (`PREVIEW_MODEL_SCALE`) | 0.266622222960 | 0.266622222960 |
| 2.5 | 2.221851766109 | 2.221851766109 |

The source comment is honest about this being deliberate (the number feeds weapon
normalisation in the same world-metric space). The A2.12 documentation and slice
report are not: they state that measuring in this space means ancestor scale and
placement cannot change the number. The pinned constant
`0.888740688562393` is a host-scale-1.0 value only.

Worth recording as a genuine strength: the a0/a1 agreement is *not* trivial.
a0's armature carries scale 0.01 and its bone rests are ~100x larger
(`REL_global_origin[hand]`: a0 `(−38.56, −5.97, −23.87)` vs a1
`(−0.386, 0.239, −0.060)`); the two cancel exactly, which is what makes the
identical measurement meaningful.

**Broken contract.** Documentation states an invariance the implementation does
not have.

**Minimum correction.** Correct the documentation to say the space is the
skeleton's own world space *including* the armature transform, and that equality
across representations holds at equal ancestor scale; note that the pinned
constant is tied to the test's `Vector3.ONE` host.

#### M2. A resolvable but anatomically wrong landmark alias passes with a plausible height

**File/function:** `mixamo_52_hand_family.gd:153-206`,
`skinned_mesh_geometry.gd:160-224`.

**Evidence.** Families that resolve `head_top` to `RightHand`, or
`floor_contact` to `Hips` — bones that exist and sit the right way round — are
accepted silently:

```
truth_height        = 0.888740688562
wrong_head_alias    = resolved_ok=true measure_ok=true height=0.778123 err= head=RightHand
wrong_floor_alias   = resolved_ok=true measure_ok=true height=0.349303 err= floor=["Hips"]
```

The suite covers aliases that resolve to *nothing* (`WrongAliasFamily`) but not
aliases that resolve to the wrong bone. There is no plausibility check (head is
not required to be the topmost landmark, floor not the lowest, no ratio bound).

**Broken contract.** The audit requirement that a wrong alias resolution must
not be able to pick an existing but anatomically wrong bone and still pass.

**Minimum correction.** Add a family-level plausibility assertion inside
`resolved_height_landmarks` or the measurement: the resolved head landmark must
be at or above every other resolved landmark and within a family-declared
fraction of the skeleton's own vertical extent; otherwise return
`HUMANOID_HEIGHT_LANDMARKS_IMPLAUSIBLE`.

#### M3. `approach_radial_radii` is not scale-invariant

**File/function:** `power_grip_1h_engine.gd:1085`.

**Evidence.** Same asset, same calibration, host scale only:

| host scale | `approach_radial_radii` (limit 0.15) |
| --- | --- |
| 1.0 | 0.055421 |
| 0.3 | 0.068857 |
| 0.5 | 0.069082 |
| 2.0 | 0.111768 |

At scale 2.0 the metric consumes 75 percent of the gate budget from placement
alone, although the gate is documented as coordinate-invariant.

**Minimum correction.** Establish where the residual scale dependence enters
(most likely a length compared against a non-scaled epsilon in the refinement)
and pin a regression that measures the metric at several host scales.

#### M4. An acceptance report from another asset or policy is accepted verbatim

Covered by the evidence in B1. Recorded separately because it is the narrower,
cheaper fix: nothing in the report ties it to the asset identity or the policy
identity, so a report may be moved between certificates freely once re-digested.

**Minimum correction.** Require the report to carry the two identity hashes and
the policy id, and have `verify()` compare them with the envelope's.

### LOW

- **L1.** The role constant is `LANDMARK_FLOOR_CONTACT := "floor_contact"`
  (`mixamo_52_hand_family.gd:148`), but the A2.12 documentation and slice report
  call the role `foot_floor`. Name drift only; fix the prose.
- **L2.** `geometry_identity()` (`hand_fixture_compiler.gd:795-815`) hashes
  vertex, normal, UV, bones, weights and index streams. Tangents, `TEX_UV2`,
  vertex colours, blend shapes and LOD arrays are not hashed. None are
  referenced by fixture patches today, so this is a documented-scope note rather
  than a defect; state the scope explicitly in the comment.
- **L3.** `Skeleton3D.motion_scale` is not part of the rig identity. It is 0.0
  on both current assets, so the probe could not produce a meaningful sabotage
  (`sabotage_motion_scale = rig_changed=false (was 0.0000)`); the result is
  inconclusive rather than a proven gap.
- **L4.** The envelope duplicates `compiler_version`, `evidence_schema` and
  `compiler_calibration_id/version` from the embedded evidence, and the loader
  reads the evidence copies while nothing cross-checks the two. The duplicates
  can silently disagree (see H3).
- **L5.** Skin binds on both assets are *named* (`bind_bone = -1` for all 52
  binds, `bind_name = ["Hips", "Spine", ...]`). The bind-index channel of
  `rig_identity` is therefore exercised by no current asset; the bind-name and
  `bind_to_skeleton_map` channels are, and both invalidate correctly.
- **L6.** The `grip_ground_truth` chain step largely duplicates a gate that has
  already run. `hand_grip_solver.attach()` executes the full
  `evaluate_thumb_surface_truth` inside `assemble()`, before `bind_sanity` is
  recorded; step 8 then re-reads `last_surface()` and applies the strict subset
  `closest_patch == "pad"`, and the report's `grip_ground_truth.pass` is derived
  from that same string rather than measured again. The step is honest but adds
  less independent evidence than its name suggests — worth stating, since it is
  the chain's only externally anchored behavioural gate.

## 4. Forensic a0/a1 comparison and the thumb diagnosis

### 4.1 a0's full-chain result, confirmed

Every claimed element of a0's outcome reproduced:

| claim | observed |
| --- | --- |
| compiler PASS | `compiled=true` |
| 4 nail / 7 pad | `nail=4 pad=7` |
| rig binding PASS | `binding=certified_bound, verified=true` |
| magnitude invariants PASS | `invariants.pass=true, failures=[]` |
| `THUMB_OPPOSITION_GATE_FAILED` | `assemble ok=false err=THUMB_OPPOSITION_GATE_FAILED` |
| `thumb_approach_axial` | in `thumb_wrap_gate.failures` |
| `thumb_approach_radially_outward` | in `thumb_wrap_gate.failures` |
| exit 2, no certificate, no publication | confirmed via the CLI baseline |

### 4.2 Side-by-side

| metric | a1 (accepted) | a0 (rejected) | limit |
| --- | --- | --- | --- |
| `approach_axial_fraction` | 0.593774 | 0.608828 | ≤ 0.60 |
| `approach_radial_radii` | 0.055421 | 0.177152 | ≤ 0.15 |
| `approach_tangential_winding_radii` | 0.732313 | 0.733128 | — |
| `wrap_deg` | 85.460 | 93.699 | ≥ 60 |
| `opposition_dot` | 0.387 | 0.515 | — |
| `nail_out_dot` | 0.750 | 0.840 | ≥ 0.3 |
| `nail_axis_dot` | 0.235 | 0.542 | ≤ 0.72 |
| `nail_pad_dot` / `rest_nail_pad_dot` | -0.0177 | -0.8541 | self-consistent |
| `distal_roll_deg` | 18.94 | 22.01 | ≤ 60 |
| `cmc_flex / cmc_twist / mcp_flex / ip_flex` | 26.85 / -58.64 / 8.29 / 79.32 | 25.35 / -58.78 / 8.66 / 79.46 | — |
| compiler confidence (overall) | 0.456 | 0.531 | — |
| `nail_margin` / `pad_margin` | 0.556 / 0.251 | 0.618 / 0.350 | — |
| `nail_best_rejected` | 0.112 | 0.050 | — |
| `winding_flips` | authored 0 / flipped 30 | authored 7 / flipped 23 | — |
| derived `volar_t3` / `radial_t3` / `nail_dir_t3` / `thumb_axis_t3` | identical to a0 | identical to a1 | — |
| resolved hand frame, socket, finger poses, volar probe | identical | identical | — |

### 4.3 The 7-versus-10 pad triangle question, answered

**Verdict: contributing cause, and quantitatively the dominant one for the
radial failure.** It is neither geometrically equivalent nor unproven.

The two rigs offer the compiler the *same* candidate set (30 candidate
triangles, 20 thumb-tip triangles, 3 components, 1 qualified) and the compiler's
derived anatomical directions in distal-bone space are bit-identical
(`volar_t3 = (0.199632, 0.082101, 0.976425)` on both). From that identical
starting point it selected different patches, with a materially different result:
`rest_nail_pad_dot` -0.0177 versus -0.8541, and nail plate normals 55 degrees
apart (`REL_nail_normal_dot = 0.566740`).

The causal link to the failing gate is numerical. Expressed in a common scale
(a0's bone-local units are 100x a1's), the compiled pad markers are

- a1 `(0.010229, -0.001610, 0.006254)`
- a0 `(0.010979, -0.000157, 0.006183)`

a separation of 0.0016369 in model units. Against
`radius_mean = 0.01325370` that is **0.1235 radii**. The measured difference in
`approach_radial_radii` between the two rigs is
`0.177152 − 0.055421 = 0.1217 radii`. The two agree to within 1.5 percent: the
radial approach failure *is* the compiled pad-marker difference, transported
through the solve.

The upstream reason the classification diverged is itself representation-linked,
but on the compiler side rather than the pose side: on a1 all 30 candidate
triangles required a winding flip against the outward test, on a0 seven of them
did not. That is a difference in how the two imports present triangle winding
and rest normals, and it lands squarely in the fixture compiler's surface
classification.

**A second, independent quantitative path to the same conclusion.** The compiled
pad normal does not merely locate the target contact; it *defines the axes the
authored angles rotate about*. In `_derive_thumb_anatomy`
(`power_grip_1h_engine.gd:791-829`):

```
var pad_rest_w := (t3_rest_basis * _pad_normal_local()).normalized()
...
var v_flesh := pad_rest_w - t_hat * pad_rest_w.dot(t_hat)
var f_hat := t_hat.cross(v_flesh).normalized()
var a_hat := t_hat.cross(f_hat)
```

`f_hat` is the flexion axis for MCP and IP and one basis vector of the CMC swing
axis. The two rigs' compiled pad normals differ by
`REL_pad_normal_dot = 0.993190`, i.e. **6.7 degrees**, so the entire anatomical
frame the calibration acts in is rotated by that much between the two
representations. The measured sensitivity from §H2 is that 3 degrees of authored
`tau` moves `approach_axial_fraction` by about 0.028; the observed a0/a1
difference is 0.015. A 6.7-degree rotation of the derived frame is therefore more
than sufficient to explain it.

Two independent measurements — the pad-marker offset matching the radial
approach delta to 1.5 percent, and the pad-normal rotation matching the axial
shift by sensitivity — converge on the compiled surface as the cause. Neither
requires, or is explained by, an error in the pose calibration's handling of rest
orientation.

**A third self-referential gate.** The bind-time sanity check immediately above
that derivation (`power_grip_1h_engine.gd:799`) is
`absf(_nail_normal_local().dot(_pad_normal_local()) - _rest_nail_pad_dot()) > 0.15`
— the fixture's own two normals compared against the fixture's own stored dot
product of them. Both a0 and a1 pass it trivially. It is the same tautology as
H1, one stage earlier, and it is the reason a compiled surface as different as
a0's raises no `thumb_distal_frame_invalid`.

### 4.4 Root-cause classification

**Primary: `SURFACE_CLASSIFICATION_DIFFERENCE`.**
**Enabling: `POSE_CALIBRATION_OVERFIT`.**
**Refuted: `REPRESENTATION_RETARGET_GAP` as the mechanism of the failure.**

`REPRESENTATION_RETARGET_GAP` is refuted for the pose path: the two rigs' rest
bases genuinely differ by a 90-degree X-axis convention plus a 100x armature
scale, and the pipeline already normalises both — proven by identical hand
frames, identical invariants, identical finger poses and achieved thumb angles
agreeing within 1.5 degrees. A representation gap of the kind described would
not survive as a 1.5-degree discrepancy.

`FAMILY_AXIS_MAPPING_GAP` is not supported: the family's derived thumb axes come
out identical on both rigs.
`ASSET_SPECIFIC_RIG_FAILURE` is not supported: the rig binds, the invariants
pass, the geometry is the same topology.
`GROUND_TRUTH_GATE_BUG` is not supported in the sense of a coding error, but the
self-referential surface gate (H1) and the 1 percent axial margin (H2) mean the
gate set is not fit for a multi-asset batch.
`UNPROVEN` does not apply: the causal chain is measured end to end.

### 4.5 Answers to the specific questions

1. **Are the numeric joint angles absolute bone-local orientations or semantic
   rotation deltas?** Semantic, rest-relative deltas. Every thumb joint is set as
   `set_bone_pose_rotation(bone, rest_rotation * q_anat)`
   (`power_grip_1h_engine.gd:586-622`), where `q_anat` is built from the authored
   degrees about the derived axes `t_l` / `f_l` / `a_l` — CMC as
   `Quaternion(swing_axis, sigma) * Quaternion(t_l, tau)` with
   `swing_axis = f_l·cos(phi) + a_l·sin(phi)`, MCP and IP as
   `Quaternion(f_l, flex)`. The rest orientation is stored at bind
   (`_rest_rotations[i] = get_bone_rest(i).basis.get_rotation_quaternion()`,
   line 534) and inverted again for readback
   (`q_rel = rest.inverse() * pose`, lines 1207-1210).
2. **Is the same local quaternion applied to two different rest bases?** No, and
   this is the design's real strength. Each rig contributes its own
   `rest_rotation` and its own derived axes, so the same authored numbers produce
   the same *anatomical* pose on both representations — confirmed by the
   achieved angles agreeing within 1.5 degrees. The calibration is therefore
   **not** representation-dependent. It is, however,
   **surface-evidence-dependent**, because the derived axes are a function of the
   compiled pad normal (§4.3). That is the substitution the slice's diagnosis
   missed: the fragile input is the fixture's surface, not the rig's rest frame.
3. **Can the difference be predicted from the rest transforms before the grip
   solve?** No. The rest-basis difference is predictable
   (`REL_global_rest[hand] = 89.756 deg`) but does not predict the failure. What
   does predict it, and is available before the solve, is the compiled surface
   evidence: `rest_nail_pad_dot = −0.854` versus `−0.018`, and the pad-marker
   offset of 0.1235 radii.
4. **Would a temporary correct basis conversion give the right approach without
   changing an angle or a gate?** No — refuted. The basis is already effectively
   converted; there is no residual rotation for a conversion to remove. Nor can
   the solver absorb the difference: `_refine_digit`
   (`power_grip_1h_engine.gd:638-707`) optimises only a scalar delta, clamped to
   ±15 degrees, distributed CMC-dominantly
   (`THUMB_REFINE_WEIGHTS = [1.0, 0.25, 0.1]`), against a pad-to-shaft gap band —
   it cannot re-derive an axis. Both rigs converged in 3 iterations, so
   refinement is not masking anything here either.
5. **Is this general retargeting of a canonical grip pose, or a new per-family
   calibration?** Neither. It is (a) representation-independent surface
   classification in the compiler and (b) gate/calibration robustness in the
   interaction policy.
6. **Which owner should carry the solution?** The **fixture compiler**, for
   making nail/pad classification and winding handling independent of how an
   import presents rest normals; and the **interaction policy**, for a gate
   window that separates correct from defective grips rather than separating one
   calibrated asset from everything else. The skeleton family and the
   representation adapter carry no part of this fix — they already work.

## 5. Area-by-area evidence

### 5.1 Semantic height landmarks — PARTIAL

Confirmed independently: `head_top` and `floor_contact` are roles, not names; the
family owns alias resolution through its own `bone_name_candidates`; generic
consumers carry no rig prefix (the suite greps the generic files for
`mixamorig`); a0 resolves `mixamorig_Head`, a1 resolves `Head`, and both measure
`0.888740688562` at equal ancestor scale; unresolved landmarks are a distinct
class from degenerate geometry, and a family with no landmark resolver fails
closed.

Sabotage results: missing head landmark, missing floor landmark and aliases
resolving to nothing all yield `HUMANOID_HEIGHT_LANDMARKS_UNRESOLVED` naming the
role; a flat rig and a head-below-floor rig yield `DEGENERATE_HEIGHT`; a
one-sided floor role still measures (`floor=["LeftToes", "LeftFoot"]`).
Downgraded to PARTIAL by M1 (space is not ancestor-invariant, contrary to the
documentation) and M2 (a wrong-but-resolvable alias passes).

### 5.2 Geometry and rig identity — PASS

`source_geometry_sha256` covers per-surface vertex, normal, UV, bone-index,
weight and index streams. `source_rig_sha256` covers the geometry identity plus
bind count, per-bind bone index, bind name and quantised bind pose, the
bind-to-skeleton map CPU skinning actually uses, every bone's name, parent and
quantised rest, the skeleton NodePath the mesh deforms against, and the mesh's
transform relative to the skeleton derived from local transforms only.

Independent sabotage, beyond what the suite covers:

| sabotage | rig identity |
| --- | --- |
| bind **name** changed | invalidated |
| mesh instance moved relative to the skeleton | invalidated |
| `mi.skeleton` NodePath cleared | invalidated |
| bind **bone index** swapped | unchanged — but see L5: all binds are named, `bind_bone = -1`, so the sabotage is a no-op rather than a miss |
| `Skeleton3D.motion_scale` doubled | unchanged — inconclusive, the value is 0.0 on both assets |

The suite already proves bone rest, hierarchy, bind pose and weight/bone-index
sabotage invalidate, and that runtime pose and ancestor scale/rotation/yaw do
not. Compilation and live verification share one implementation:
`rig_identity_of_asset()` and the assembler's live check both call
`rig_identity(mi, skeleton)`; there is no parallel near-duplicate hash function.

### 5.3 TOCTOU

| window | behaviour |
| --- | --- |
| asset changes after compilation, before certification | `certify()` compares the evidence's stored identities against the expectations derived at that moment; a mismatch is `FIXTURE_GEOMETRY_HASH_MISMATCH` / `FIXTURE_RIG_HASH_MISMATCH` |
| asset changes after certification, before assembly | refused at assembly: probe mutated a bone rest after minting and got `assemble_ok=false err=FIXTURE_RIG_HASH_MISMATCH` |
| published certificate swapped between load and verify | `load_certified()` re-reads from disk rather than serving a cached resource (`toctou_after_disk_swap = ok=true family_version=9999`, i.e. the swap was observed). Verification happens inside the same call as the load, so there is no exploitable window; the swapped-in certificate was then refused by the caller's family expectation |

### 5.4 Evidence versus rejected artifact versus certified fixture — PASS

The three states are genuinely distinct. `hand_fixture_compiler.gd` contains no
reference to `hand_fixture_certification.gd`, so the compiler structurally
cannot certify its own output. Valid, correctly bound staging evidence with a
correct content hash and a correct live rig binding is refused by the runtime
loader as `FIXTURE_NOT_CERTIFIED`, and remains refused after being copied to the
published path — the refusal is by resource type and envelope, never by
location. An honestly re-hashed rejected artifact is still refused, and an
invented `certified = true` alone yields `FIXTURE_NOT_CERTIFIED` once re-hashed.

The one thing not established is the *positive* claim: that only the full chain
can produce the envelope. It cannot (B1).

### 5.5 Acceptance report per chain step — FAIL

| step | producer | actual gate | reported by | certifier requires | what turns it red |
| --- | --- | --- | --- | --- | --- |
| `import` | headless tool, scene instantiation | mesh + skeleton found | `_step("import")` after success | membership in `chain` | missing rig/mesh |
| `family_resolution` | family registry match | hand bone resolves under some alias | `_step` after success | membership | unknown rig naming |
| `humanoid_normalization` | `family_height_landmarks` + measurement | landmarks resolve, height ≥ 1e-6 | `_step` after success | membership | missing/degenerate landmarks |
| `fixture_compilation` | `Compiler.compile` | per-side `compiled` true | `_step` after success | membership | unclassifiable thumb surface |
| `artifact_integrity` | `load_artifact` | stored content hash re-derives | `_step` after success | membership | hand-edited evidence |
| `rig_binding` | `rig_identity_of_asset` vs evidence | both identity hashes equal | `_step` after success | envelope identity equality — **externally anchored** | any rig/geometry edit |
| `bind_sanity` | real assembler via a **provisional certificate** | `assemble()` ok | `_step` after success | membership | any assembler refusal |
| `grip_ground_truth` | `grip.last_surface()` | `closest_patch == "pad"` — **achieved geometry** | `_step` after success | membership | thumb pad not the closest patch |

Within this one caller the chain is honest: each `_step()` is reached only after
its gate passed, and the final certificate's `chain` is
`_report["chain"]`, not a hardcoded list. Two steps are genuinely externally
anchored — `rig_binding` (identity hashes the certifier re-checks) and
`grip_ground_truth` (a measurement on the posed, skinned mesh). Compiler PASS
alone, bind PASS alone and assembler PASS alone are each insufficient, because
the chain requires all eight entries and the ground-truth gate runs last.

The failure is at the type level, not in this caller: `chain` and
`acceptance_report` are parameters, `verify()` reads only
`acceptance_report["pass"]`, reports are transferable between assets and
policies, a contentless report suffices, and the provisional certificate asserts
the whole chain before two of its steps have run. See B1, H5, M4.

### 5.6 Atomic publication — PASS

Failure injection against `rig_ingest.publish_atomically`:

| injection | result |
| --- | --- |
| error before temp write (source missing) | `ok=False INGEST_STAGED_ARTIFACT_MISSING`, destination byte-identical |
| error during temp write (half-written, then `OSError`) | `ok=False INGEST_PUBLISH_FAILED`, destination byte-identical, no `.publishing` leftover |
| error in `os.replace` | `ok=False INGEST_PUBLISH_FAILED`, destination byte-identical, temp cleaned |
| repeated publish with different bytes | last complete artifact wins; never a mixture |
| mechanics | temp is `published.tres.publishing` in the **same directory**, and the destination still holds the previous bytes at the moment `os.replace` is called |
| stale leftover temp from an earlier crash | consumed, not published; does not block (`ok=True`, destination is the new certificate) |

The destination is therefore always the old or the new complete artifact. A
rejection never reaches the publish step (a0 exits 2 before certification), and
a failed publish is an exit-1 infrastructure failure rather than a silent
acceptance. The 22 `test_rig_publish_safety.py` cases cover the same ground from
the Python side.

### 5.7 Family version and mandatory verification — PASS

Expected family id and version arrive from the runtime caller, not from the
artifact, and are checked at both load and assembly:

| sabotage | result |
| --- | --- |
| empty expected `family_id` | `FIXTURE_FAMILY_MISMATCH` |
| empty expected `family_version` | `FIXTURE_FAMILY_VERSION_MISMATCH` |
| empty expected geometry or rig hash | `FIXTURE_MESH_IDENTITY_REQUIRED` |
| foreign id / version in the expectation | refused |
| artifact self-declaring `family_version = "9999"`, honestly re-hashed | `verify()` accepts, loader refuses: `FIXTURE_FAMILY_VERSION_MISMATCH` |
| colluding caller that also expects `"9999"` | loads, then refused at assembly against the real family: `FIXTURE_FAMILY_VERSION_MISMATCH` |

The last row is the important one: two independent layers, and the artifact
cannot buy its way past both by re-hashing.

Verification is a declared contract, not method presence. A fixture that
implements `verify_against_rig` perfectly but declares no contract is refused; a
fixture declaring `something_invented_v9` is refused; a fixture returning
`ok = true` without `verified = true` is refused; identity is checked before
geometric bind sanity (`test_hand_fixture_compiler.gd` asserts exactly that
ordering); and normal composition accepts only `certified_runtime_v1`.

### 5.8 Authored oracle isolation — PASS

Full gate matrix, run through the real assembler with the real composition
dependencies:

| gates | result |
| --- | --- |
| none | `FIXTURE_NOT_CERTIFIED` |
| injected `reference_fixture_mode` only | `FIXTURE_REFERENCE_MODE_FORBIDDEN` |
| `EOM_ALLOW_REFERENCE_FIXTURE=1` only | `FIXTURE_NOT_CERTIFIED` |
| both, explicit test harness | `ok=true`, `binding=test_only_reference`, `verified=false` |

Neither gate alone suffices, and the environment variable alone cannot turn a
production composition into reference mode: the production composition neither
declares `reference_fixture_mode` (`composition_declares_reference_mode=false`)
nor uses the authored oracle as its fixture (`composition_fixture_is_oracle=false`).
With the environment variable set, production composition still assembles its
certified fixture normally. Reference mode is the one path that poses an
unverified fixture, which is why both gates matter; it is correctly reported as
`verified=false` rather than as a certified binding.

## 6. Requirements on the next thumb slice

Because the diagnosis is **not** representation-dependent in the pose path, the
retargeting-adapter work the slice report proposed is not the right next step.
The boundary the audit brief asks to preserve is nonetheless the correct one, and
the corrected work assignment respects it:

- **Interaction policy** keeps ownership of the desired physical grip pose. The
  authored `sigma/phi/tau/flex` numbers stay policy data. What must change is
  that the policy's *gate window* is established against more than one asset, so
  it separates a correct grip from a defective one rather than separating the
  calibrated asset from everything else (H2). The desired thumb approach
  direction must continue to come from policy/target and be verified against
  achieved geometry — never derived from the raw rest pose.
- **Family / representation layer** describes bone chains and local anatomical
  bases. No change: it already produces identical derived axes on both
  representations.
- **Representation adapter** maps canonical flexion/abduction/twist onto
  bone-local deltas. No change: the achieved-angle agreement shows this already
  works. Do not build a new adapter for a gap that is not there.
- **Fixture compiler** owns surface evidence, not pose calibration. This is where
  the work belongs: nail/pad classification and winding handling must not depend
  on how an import presents triangle winding and rest normals. The measurable
  target is that the same humanoid delivered in either representation yields the
  same patch selection, and consequently the same `rest_nail_pad_dot` and pad
  marker within the identity quantum. Today it yields 10 versus 7 triangles and
  −0.018 versus −0.854.
- **Ground-truth gates** judge achieved geometry and their thresholds are not to
  be moved to admit a0. The one gate that must change is not a threshold but an
  anchor: `thumb_surface_orientation_inconsistent` must stop comparing achieved
  geometry with the fixture's own recorded value (H1).

Explicitly excluded, and none of them is needed by the above: an Uthana, a0 or a1
branch; a new per-asset constant; a threshold change to make a0 pass; copying a1
quaternions to a0.

## 7. Evidential value of the new tests

| claim | producer | oracle | proven falsifiable |
| --- | --- | --- | --- |
| height roles | real family + real measurement on both GLBs | pinned `0.888740688562393`, tol 1e-9, plus cross-representation equality | yes — synthetic bare/flat/inverted skeletons and two negative families |
| geometry identity | real compiler on the real mesh | change/invariance relations, not absolute values | yes — weight/bone-index edit |
| rig identity | real compiler on the real rig | same | yes — rest, hierarchy, bind pose, weights |
| certification resource type | real compiler + real loader | named error class `FIXTURE_NOT_CERTIFIED` | yes — valid evidence, valid hash, valid rig binding, still refused |
| envelope hash | real `certify()` | recomputed `certification_hash` | yes — per-field tamper loop |
| acceptance report | **fabricated in the test** (`_params()`) | `report["pass"]` | only negatively (`pass: false`, removed chain step) |
| atomic publish | real `publish_atomically` | destination bytes | yes — 22 injection cases |
| family version | real loader + real assembler | caller-supplied expectation | yes — foreign, empty and self-declared versions |
| mandatory verification | real assembler | declared contract string | yes — duck-typed, lying and unverified doubles |
| oracle isolation | real assembler + real composition | named error classes per gate combination | yes — all four combinations |
| a0 CLI rejection | **separate Godot process**, real ingestion entrypoint | exit code 2 + parsed report | yes |
| a1 CLI acceptance | real ingestion entrypoint | certificate round trip | yes |
| cross-process determinism | second Godot process | in-process pinned constant | yes |

The suite is, on the whole, unusually strong for this kind of boundary: most
oracles are named error classes or invariance relations rather than recorded
outputs, the negative fixtures are real test doubles rather than mocks of the
production code, and the a0/a1 claims run the actual CLI in a separate process
and compare against an in-process constant. The following weaknesses matter:

1. **Self-oracle on the acceptance report.** `_params()` at
   `test_hand_fixture_certification.gd:879-893` fabricates
   `{"pass": true, "certified_side": ...}` and `REQUIRED_CHAIN.duplicate()` for
   every positive certificate in the suite (and the same shape appears in
   `test_hand_fixture_identity.gd:465` and `test_hand_fixture_compiler.gd:776,
   928`). The suite therefore cannot detect B1, because B1 is the mechanism it
   relies on to construct its own fixtures.
2. **A vacuous assertion.** `test_hand_fixture_certification.gd:809-812` asserts
   `"a0's compiled thumb SURFACE is not the problem"` from an empty
   `thumb_surface_failures`, which the self-referential gate of H1 guarantees to
   be empty regardless of the compiled surface. This assertion cannot fail for
   the reason it claims to test.
3. **A non-sequitur assertion.** Line 813-815 concludes from passing magnitude
   invariants that the failure "is a pose/rest fact". Passing invariants do not
   discriminate between a pose cause and a surface cause; §4 shows the surface is
   in fact implicated.
4. **Conditionally skipped assertions.** `if original_skin != null and
   original_skin.get_bind_count() > 0:` (line 318) and `if reweighted != null:`
   (line 343, where `_mesh_with_shifted_weights` returns null when the surface
   has no bone stream) silently drop four rig-identity assertions if the asset
   changes shape. They execute on today's asset; they would not announce their
   own absence.
5. **Untested identity channels.** Nothing sabotages the skin *binding* (which
   bone a bind targets), the mesh-to-skeleton relation, or `mi.skeleton`. All
   three are in the hash and all three were confirmed to invalidate by this
   audit's probes, so this is missing coverage rather than a defect.
6. **The pinned height constant records a host-scale-1.0 measurement.** It is a
   legitimate regression pin, and the cross-process a0 check makes it a genuinely
   independent one, but it does not pin what the documentation claims (see M1).
7. **A negative helper that passes when the negative never happened.**
   `_assemble_fails()` in `test_hand_fixture_compiler.gd:782-797` returns `true`
   — the "refused, as intended" answer — when `certify()` fails *or* when
   `load_certified()` fails, before the assembler is ever reached. A tampered-patch
   case therefore reports success whether the assembler refused it or the
   certificate simply never minted. The fix is to distinguish
   refused-at-certification from refused-at-assembly and require the latter.
8. **A two-class disjunction that could absorb a regression.**
   `test_hand_fixture_certification.gd:523-528` accepts either
   `FIXTURE_CERTIFICATION_HASH_MISMATCH` or
   `FIXTURE_ACCEPTANCE_SCHEMA_UNSUPPORTED` for every field in the tamper loop. A
   third class, or an `ok: true`, would need the surrounding assertion to be
   `not verify(edited).ok` to be caught. My own per-field probe showed the two
   classes do partition cleanly today, so this is latent rather than active.
9. **Asymmetric subprocess stdout handling.** The a0 test joins the whole
   captured output before parsing the report
   (`test_hand_fixture_certification.gd:735`), while the a1 cross-process check
   parses only the first stdout element
   (`test_hand_fixture_identity.gd:163`). The a1 form is flaky rather than
   vacuous — an unparsed report fails the non-empty assertion — but it should
   match the a0 pattern.
10. **Further conditional skips beyond those in item 4.** `test_hand_fixture_identity.gd:269-270`
    and `356-372`, `test_hand_fixture_certification.gd:516-517` and `613-630`, and
    `test_hand_fixture_compiler.gd:189-191` each abandon a block of assertions
    when a precondition object fails to load, while the test still reports OK.

## 8. Paid batch readiness

**FAIL.** Not because of the ingestion machinery, which is in good shape —
publication is atomic and rollback-safe, staging isolation holds, family-version
and verification enforcement are layered and behaviourally proven, and the
authored oracle is properly fenced — but for two reasons that would bite
immediately on a multi-unit purchase:

1. The R4 approach gate admits the calibrated asset by 1.0 percent of its
   threshold, and a few degrees of legitimate variation reproduces a0's exact
   rejection (H2). A paid batch would produce classified rejections that say
   nothing about asset quality.
2. Surface classification is not representation-stable: the same humanoid in two
   imports yields different pad patches and nail plates 55 degrees apart, and
   that difference alone accounts for the failing radial approach metric (§4.3).
   Batch throughput depends on this being stable.

The certification boundary itself should also be closed to the level it is
documented at (B1, H3, H4, H5) before it is relied on as the gate that decides
which purchased assets enter the game.

Stage remains `CALIBRATING`.

## 9. Audit method and cleanup

All experiments were local. No provider, network or credential access; no
credential was searched for, tested or printed. Four temporary Godot probe
scripts and one temporary Python probe were used and have been removed, together
with their output. The probes:

- measured heights at four host scales on both representations, and exercised
  three wrong-alias families;
- sabotaged bind name, bind bone index, mesh-to-skeleton transform, skeleton
  NodePath and `motion_scale`;
- minted a certificate with no gates run and drove it through the real loader,
  the real assembler and a save/load round trip;
- tampered with 22 envelope fields twice each (without and with an honest
  re-hash) and checked both `verify()` and the loader;
- ran the four-way oracle gate matrix and the family-version collusion matrix;
- profiled a0 and a1 through the real assembler and compared rest transforms,
  compiled surface evidence, achieved joint angles and every thumb-wrap metric;
- swept the authored calibration to map the R4 gate window;
- injected six failure points into `publish_atomically`.

Three read-only static traces complemented the probes: the acceptance chain step
by step through `certify_hand_fixture_headless.gd`, the thumb angle-application
path from authored calibration to `set_bone_pose_rotation`, and the evidential
structure of the six new test files. Where a static reading and a measurement
disagreed, the measurement was taken as authoritative — notably on whether the
calibration is representation-dependent, where the static shape of the code
(per-rig rest quaternions and per-rig derived axes) is suggestive but the
achieved-angle agreement across both representations is decisive.

No production code, test or existing steering document was modified. The five
required checks were re-run after cleanup and match the baseline in §1.
