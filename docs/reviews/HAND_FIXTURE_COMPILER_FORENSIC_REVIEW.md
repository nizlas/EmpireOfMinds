# Forensic review — automatic hand-fixture compiler (A2.10)

Independent audit. **No production code, test or steering document was changed
by this review.** Temporary probes and generated artifacts were removed
afterwards. No commit.

Scope: is the new compiler genuinely generic, oracle-independent, free of
hidden single-mesh constants, integrity-protected, actually used by the live
grip path, safe on other rigs, and a real basis for automatic multi-unit
certification. Not a visual grip review and not a left-hand T2 implementation.

---

## 1. Baseline and diff boundary

`HEAD = aa5418ae4837877e32a97360c8ba1c6d2a5be6e4` ("Generative units PoC").
The worktree is intentionally dirty: **A2.9b, A2.10 and C1 are all uncommitted
at the same time**, so "what this slice changed" cannot be read from git alone
and had to be attributed by content.

| Profile | Result |
| --- | --- |
| `slice a1` | 71 checks, OK |
| `slice a2` | 1482 checks over 5 files, OK (222 / 68 / 106 / 289 / 797) |
| `slice c1` | 22 checks, OK |
| `pytest tools/assetgen/tests` | 68 passed |

Attribution of the dirty worktree:

- **C1 (asset provider)** — `tools/assetgen/**` except `hand_fixture_ingest*`,
  `docs/ASSET_PROVIDER_PIPELINE.md`, `scripts/scan-secrets.py`, `.env.example`,
  `game/presentation/diagnostics/shield_inspection_diagnostic.*`,
  `test_shield_inspection_diagnostic.gd`, `artifacts/assetgen/**`.
- **A2.9b (previous slice)** — `power_grip_1h_policy.gd`,
  `grip_interaction_profile.gd` reduced to a registry, the move of
  `uthana_warrior_hand_fixture.gd` out of the generic core,
  `equipment_assembler.gd` policy resolution, `uthana_a2_power_grip.gd`,
  `test_uthana_a2_power_grip_parity.gd`, plus `.uid` churn.
- **A2.10 (under audit)** — `hand_fixture_compiler.gd`,
  `compiled_hand_fixture.gd`, `hand_fixture_artifact.gd`,
  `power_grip_1h_calibration.gd`, `tools/compile_hand_fixture_headless.gd`,
  `uthana_a2_hand_fixture.tres`, `humanoid_hand_profile.gd` (`derive_frame` /
  `skinned_palm_flesh_probe` extraction), the composition switch to the
  artifact, `test_hand_fixture_compiler.gd`,
  `tools/assetgen/hand_fixture_ingest.py` + its test, and the doc updates.

Nothing was stashed, reverted or reformatted.

---

## 2. Dataflow from rigged mesh to selected patches

Established by reading and then re-deriving independently (see §4):

```
family.bone_map(side)                     [injected, no names in the compiler]
  -> _verify_chains                       hand + 5 digits resolve
  -> _verify_thumb_belongs_to_hand        distal thumb within 4 hand spans
  -> HandProfile.derive_frame(use_rest=false)
        longitudinal = knuckle - wrist
        radial       = index MCP - pinky MCP            (this hand's own bones)
        volar        = radial x longitudinal, sign from the thumb column
  -> _verify_volar                        thumb column vs skinned palm flesh
  -> reset THUMB chain to rest, force_update_all_bone_transforms
  -> _gather_thumb_triangles              dominance >= 0.40 on T2/T3, >=2 on T3,
                                          rest winding flip vs imported normals
  -> _connected_components                shared vertex indices only
  -> qualify: component with an opposed nail face AND a volar pad face
  -> _select_patch(d_nail >= 0.35, dorsal) / _select_patch(d_volar >= 0.45)
        each requires margin >= 0.08 to the best rejected candidate
  -> confidence = min(component, nail, pad, opposition, bone_weight) >= 0.35
  -> artifact + content hash
```

No branch reads the oracle, an asset path, a texture, a UV value as evidence,
or a hardcoded index.

---

## 3. Oracle independence — decisive test

The hand-authored oracle (`uthana_warrior_hand_fixture.gd`), its `.uid` **and
the committed artifact** were physically moved out of the project, and the
headless compile step was then run on the rigged GLB:

```
ISOLATION oracle_present=False artifact_present=False
HAND_FIXTURE_INGEST {"content_hash":"54DE1B64D6F2E798B907EEC0472CEE4294C13A7297795BD412BF2A047B7CEA29",
  "sides":{"right":{"compiled":true,"nail_tris":4,"pad_tris":10,...},
           "left":{"compiled":false,"error_class":"PAD_PATCH_AMBIGUOUS",...}}}
```

Byte-identical content hash to the committed artifact, same 4 nail / 10 pad
triangles, same left classification, with the oracle unreachable. Files were
restored immediately. **Oracle independence is proven, not asserted.**

The oracle appears only in tests, the walking-preview development HUD and the
left-reference regression path. The production composition's code contains no
reference to it (structurally checked by
`test_equipment_interaction_pipeline.gd`).

---

## 4. Surface derivation, re-derived independently

The audit re-implemented the candidate gathering and component grouping in a
throwaway probe (own dominance loop, own vertex-sharing union) rather than
trusting the compiler's own evidence block.

**The three-component claim is true.** Right hand, 30 candidate triangles:

| Component | Triangles | Area (µ) | Mean UV | carries nail | carries pad | max d_nail | max d_volar |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 0 | 4 | 9.91 | (0.184, 0.303) | no | yes | 0.108 | 0.988 |
| **1 (tip)** | **20** | **33.31** | **(0.933, 0.024)** | **yes** | **yes** | **0.883** | **0.996** |
| 2 | 6 | 17.15 | (0.768, 0.012) | yes | no | 0.890 | −0.307 |

Two facts make the topology step load-bearing rather than decorative:
component 0 contains triangles at `d_volar` 0.988, so a threshold-only pad rule
would absorb weight bleed into the pad; and component 2 contains the **highest**
`d_nail` value in the entire soup (0.890 > the tip's 0.883), so a "best nail
score wins" rule would pick the wrong patch outright. Left hand: 24 candidates
in 2 components, the 16-triangle component at UV (0.152, 0.669) qualifying.

**Threshold classification (honest).** Sorted score distributions were measured:

- Right pad: kept worst 0.5698, best rejected 0.3189 → any threshold in
  `(0.319, 0.570]` gives the identical answer. Plateau width **0.251**.
- Right nail: kept worst 0.6679, best rejected 0.1122 → plateau `(0.112, 0.668]`,
  width **0.556**.
- Left pad: 0.4971, 0.4733, 0.4460, 0.4007 … — a continuum with no gap.

Verdict per constant:

| Constant | Honest class |
| --- | --- |
| `NAIL_BISECTOR_MIN` 0.35 | **plausibly generic anatomy** — sits mid-plateau, 0.556 wide on the reference. Still one-asset evidence. |
| `PAD_VOLAR_MIN` 0.45 | **plausibly generic anatomy** — mid-plateau, 0.251 wide. |
| `MIN_CLASSIFICATION_MARGIN` 0.08 | **Uthana calibration presented as generic.** The left pad margin on this asset is 0.0511; the constant was raised from 0.05 to 0.08 during implementation, which is precisely what decides the reference asset's own left-hand outcome. See finding H5. |
| `MIN_BONE_DOMINANCE` 0.40, `MIN_DISTAL_VERTS` 2 | family/rig-quality assumptions, undeclared as such |
| `MIN_STRUCTURE_CONFIDENCE` 0.35 | **fitted**: accepted right = 0.456, radially inverted right = 0.141 (see H6) |
| `NAIL_PAD_MAX_DOT` 0.50, `COMPONENT_AREA_TIE_RATIO` 0.02 | generic geometric sanity |

---

## 5. Surface ground truth (A2.6/A2.7 conventions)

Verified by reading `power_grip_1h_engine.gd` around `_bind_patches`,
`measure_thumb_surface_truth` and `evaluate_thumb_surface_truth`:

| Convention | Status |
| --- | --- |
| CPU-skinned triangles at the achieved final pose | held (`Skinning.skinned_vertex_world` per patch triangle, per frame) |
| Renderer-equivalent bind matrices | held (`skin.get_bind_bone` / `get_bind_name` map, same as the mesh probe) |
| Rest-anchored winding, stored, never auto-flipped | held (`ng.normalized() * ref["flip"]`; the flip is only ever *compared*, never re-derived toward an expectation) |
| Imported shading normal ≠ authored cross product | held: bind sanity requires `ng · (skinned imported normal) ≥ 0` at rest |
| Per-triangle radial at its own centroid | held (`radial = c - (o + d_axis * (c-o)·d_axis)` per triangle) |
| Real separate nail/pad patches | held (independent `_patch_refs["nail"]` / `["pad"]`, and a triangle in both plates is refused at compile time) |
| Nail never accepted as the contact patch | held (`thumb_nail_is_contact_surface` + `closest_patch`) |
| Pose freshness | held (`pose_stamp` compared inside the gate, empty stamp fails) |
| Old constant bone normals cannot grant acceptance | held: `legacy_nail_out` / `legacy_pad_in` are computed only when the fixture carries superseded refs, and are never read by the gate. The compiled artifact carries none. |
| Compiled patches re-verified against the live mesh | held at the *triangle* level (UV centroid within tolerance, T2/T3 dominance, aggregate rest normal vs stored normal). **Not** at the artifact level — see B2. |

---

## 6. Artifact integrity — per-field tamper matrix

Each field was tampered separately and the hash recomputed.

| Field | Covered by content hash | Otherwise bound? |
| --- | --- | --- |
| `sides.*.nail_tris` / `pad_tris` (si, indices, flip, uvc) | yes | yes — bind sanity |
| `sides.*.nail_normal_local` / `pad_normal_local` | yes | yes — aggregate rest-normal check |
| `sides.*.pad_marker_local` / `nail_marker_local` | yes | no |
| `sides.*.rest_nail_pad_dot` | yes | reported in the gate |
| `sides.*.compiled` / `error_class` | yes | per-side load check |
| `family_id`, `family_version`, `schema`, `compiler_version`, `source_mesh_sha256` | yes | family id checked on load; **mesh sha not checked on the live path (B2)**; family_version is always "1" (H3) |
| top-level `ok` | **no** | nothing |
| `skeleton_bone_count` | **no** | nothing |
| `sides.*.confidence` | **no** | nothing (not re-gated at load) |
| `sides.*.evidence` | **no** | nothing |
| `sides.*.source` | **no** | nothing |

Deliberate exclusion of diagnostics is defensible in principle. It is not
harmless in practice, because confidence and evidence are exactly what the
preview HUD and the ingestion report present as certification evidence, and
they are unsigned.

**The 1e-6 quantisation does not do what it was introduced to do.** See B1.

---

## 7. The live path

Traced through `uthana_a2_walking_preview.gd` → `Composition.make_assembler` →
`EquipmentAssembler.assemble` → `HandProfile.compile` → the injected fixture.

Confirmed good:

- the assembler consumes the **compiled** artifact; `Composition` contains no
  reference to the authored fixture;
- exactly one transform owner (`WeaponSocket_*` ancestor count must equal 1);
- the HUD reads provenance off `assembler.fixture_script()` and the socket
  numbers off `assembler.policy_script()`, i.e. the objects that actually ran;
- requiring the left side through the production loader fails closed with the
  compiler's own `PAD_PATCH_AMBIGUOUS`.

Sabotage results, all constructed exactly as the composition constructs the
fixture:

| Sabotage | Live-path outcome |
| --- | --- |
| missing artifact file | refused `FIXTURE_ARTIFACT_MISSING`, fixture null, assembler `FIXTURE_REQUIRED`. **No fallback to the authored fixture.** |
| broken content hash | refused (`FIXTURE_ARTIFACT_HASH_MISMATCH` in the loader / `FIXTURE_SCHEMA_UNSUPPORTED` in the adapter) |
| foreign `family_id` | refused `FIXTURE_FAMILY_MISMATCH` |
| left side required | refused `PAD_PATCH_AMBIGUOUS` |
| nail/pad swapped, winding inverted, other hand's patches, unbound indices | refused by bind sanity / surface ground truth (covered by existing tests, re-confirmed) |
| **artifact declaring a foreign source mesh** | **loads and assembles successfully — accepted** (B2) |
| **artifact declaring `compiler_version` v0, passed in memory** | **accepted by the adapter** (M2) |

---

## 8. Headless ingestion, executed for real

Driven through `tools/assetgen/hand_fixture_ingest.py` from a fresh process
against the real rigged GLB (not the fake runner used in its unit tests):

| Run | Verdict | Exit | Notes |
| --- | --- | --- | --- |
| right required | ACCEPTED | **2** | 1.8 s, artifact written, hash `54DE1B64` |
| repeat | ACCEPTED | 2 | idempotent, identical hash |
| right+left required | CLASSIFIED | 2 | `left=PAD_PATCH_AMBIGUOUS` |
| missing asset | STEP_FAILED | 1 | `INGEST_ASSET_MISSING` |
| unknown `--family` | STEP_FAILED | 1 | `FIXTURE_FAMILY_MISMATCH` |
| 1 s timeout | STEP_FAILED | — | treated as hung |
| repo fingerless rig (`warrior_3d.glb`) | STEP_FAILED | 1 | `FIXTURE_FAMILY_MISMATCH` — **not classified** (H2) |

No editor, no F6, no manual file nomination, no Blender, no network call, no
paid API. Import, family identification, compile and artifact write are
automatic and reproducible. Steps 5–7 of the requirement (bind sanity, grip
profile, accept/fail-close) are **not** in the chain, and nothing calls the
module (H1).

A classified FAIL artifact cannot later pass as approved: the per-side
`compiled` flag and its `error_class` are inside the hashed identity view, and
`from_artifact(required_sides=[...])` rejects the side by name.

---

## 9. Every reachable humanoid asset, read-only

| Asset | Bones | Mapped finger bones | Right | Left | Deterministic | Crash |
| --- | --- | --- | --- | --- | --- | --- |
| `a1_uthana_target.glb` | 52 | 30 | COMPILED | `PAD_PATCH_AMBIGUOUS` | yes | no |
| `generated_warrior_3d_uthana_rigged.glb` | 52 | 30 | `HAND_SKELETON_INCOMPLETE` ("hand bone") | same | yes | no |
| `a1_meshy_walking_source.glb` | 24 | 0 | `HAND_SKELETON_INCOMPLETE` | same | yes | no |
| `generated_warrior_3d.glb` | 24 | 0 | `HAND_SKELETON_INCOMPLETE` | same | yes | no |
| `bronze_armed_warrior_3d.glb` | 24 | 0 | `HAND_SKELETON_INCOMPLETE` | same | yes | no |
| `warrior_3d.glb` | 24 | 0 | `HAND_SKELETON_INCOMPLETE` | same | yes | no |
| `settler.glb` | 24 | 0 | `HAND_SKELETON_INCOMPLETE` | same | yes | no |
| `niclas_3d.glb` | 24 | 0 | `HAND_SKELETON_INCOMPLETE` | same | yes | no |

Nothing crashed, nothing passed that should not, every result reproduced. The
fingerless 24-bone provider rigs are classified when the family is injected
directly — but see H2 for what the real chain reports.

The second row matters: that is **the same Uthana rig** with all 30 finger
bones present, refused because its wrist is still `mixamorig_RightHand`
instead of the post-import `RightHand` the family expects (H4). This is not
batch certification: the repo contains exactly one asset that satisfies the
family.

---

## 10. Left hand

- Uses `Family.bone_map("left")`; no `mixamorig_LeftHandThumb*` literal remains
  in the fixture logic (structurally checked, re-confirmed by reading).
- Not a copy of the right: the left frame resolves distinct bones, distinct palm
  centre, and the left candidate soup is a different size (24 vs 30) with a
  different component structure (2 vs 3).
- Fails closed `PAD_PATCH_AMBIGUOUS` (`margin 0.0511 below 0.08, worst kept
  0.4971, best rejected 0.4460`), reproducibly, whether compiled alone or with
  the right hand.
- The downstream T2/distal-station conflict is untouched: it is reached only
  through the authored left reference, whose fail-close is unchanged.
- The authored left reference's own divergence (nail island facing ulnar,
  `n·radial = −0.8609`) is **reported, not reproduced**. The production compiler
  never reads it, so the faulty left oracle affects comparison diagnostics only.

The compiler does not mask the left problem. It also does not reach it: the
refusal happens one step earlier, in patch selection.

---

## 11. Do the tests prove anything?

| Claim | Value produced by | Compared against | Independent? | Sabotage that reddens it |
| --- | --- | --- | --- | --- |
| exact right patch parity | compiler | hand-authored A2.6/A2.7 constants | **yes** | any change to selection order/threshold; verified via the radial-swap case shifting nail confidence 0.855 → 0.141 |
| determinism / content hash | compiler | **the compiler in the same process and scale** | **no — tautological** | proven red by this audit: a different compile context gives a different hash (B1) |
| compiler PASS but grip FAIL | tampered artifact | engine bind sanity + surface gate | yes | removing the UV/dominance/rest-normal checks |
| A2.6 `tau = −90°` rejected | calibration constant | oracle's `REJECTED_A26_THUMB_ANAT` | yes (equality against an independently recorded rejected value) | copying the rejected dict into the calibration |
| full 4×3 matrix, yaw invariance | live engine | pinned A2.7 numbers | yes | any pose/threshold recalibration |
| live preview owner | assembler accessors | structural assertions on the composition source | yes | re-adding the authored fixture to the composition |
| ingestion exit codes | **fake `runner`** | hand-written fake stdout | **no — the Godot step is never executed in the suite** | proven partially red here: a real run of the fingerless rig returns a different verdict than the Godot-level test implies (H2) |
| named fail-closed classes | compiler | permissive `in [...]` lists of 4–8 classes | **weak** | changing the diagnosis to another listed class stays green (M1) |

Two structural notes. The `FORBIDDEN_IN_COMPILER` scan is a genuine and cheap
guard, and it does what it claims. The negative-family classes
(`SwappedRadialFamily`, `OffThumbFamily`, `CrossedThumbFamily`) are good ideas
whose assertions are too loose to pin the mechanism they document — two of the
three are caught by a different mechanism than their comments state.

---

## 12. Findings

### BLOCKER

**B1 — the artifact's content hash is not reproducible for the same mesh, so it
cannot detect staleness.**
`hand_fixture_compiler.gd` → `content_hash` / `_identity_view` / `HASH_QUANTUM`.

Evidence: compiling the same GLB in the test context and in the headless
context yields `4D8D3B5DCC…` vs `54DE1B64D6…`, with identical
`source_mesh_sha256`, identical patch triangle IDs, and per-field deltas of
5.3e-7 to 1.1e-6 (`rest_nail_pad_dot` −0.017715901 vs −0.017714798;
`pad_normal_local` distance 1.07e-6). `HASH_QUANTUM = 1e-6` is the same order
as the noise it was introduced to absorb, so values straddle the rounding
boundary. The headless path is self-consistent (two runs, same hash), so the
divergence is between compile *contexts* (parent scale / pose), which is exactly
the case the quantisation comment claims to have solved.

Broken contract: §7 "samma input ska ge byte-identiskt eller semantiskt
hash-identiskt resultat" and the invalidation requirement — the hash changes
when nothing changed, so it cannot be trusted when something does.

Why tests miss it: `test_hand_fixture_compiler.gd:295` recompiles inside the
same process and scale, which is the one case that cannot fail. No test
compares a fresh compile with the committed `.tres`.

Minimal fix: hash only scale- and pose-invariant identity (surface index,
vertex triple, flip, family, schema, mesh sha) or widen the quantum to ~1e-4,
and add a test asserting a fresh compile reproduces the committed artifact hash.

**B2 — the live path never binds the artifact to the mesh it poses.**
`uthana_a2_equipment_composition.gd:36` passes `expected_mesh_sha256 = ""`;
`compiled_hand_fixture.gd:77 verify_against_mesh` has **zero** production
callers.

Evidence: an artifact whose `source_mesh_sha256` was replaced with `AAAA…` and
whose content hash was recomputed loads (`load_ok=true`) and drives a
successful grip (`assemble_ok=true`) through the composition's own construction
path.

Broken contract: §6 (`FIXTURE_MESH_HASH_MISMATCH` as a reachable fail-closed
class) and §7 (a changed mesh must clearly invalidate the artifact). Honest
mitigation: the engine's bind sanity would very likely reject a *materially*
different mesh at the referenced triangles — but it would report
`thumb_patch_frame_mismatch`, i.e. the wrong diagnosis, and the declared class
is unreachable in production.

Why tests miss it: the only test of the check calls `verify_against_mesh`
directly on a `BoxMesh` instead of going through the assembler.

Minimal fix: have the composition (or the assembler, after it resolves the
skinned mesh) pass/compare `Compiler.mesh_identity(live mesh)`, and assert the
live path refuses.

### HIGH

**H1 — the "automatic ingestion chain" is a module, not a wired step, and it
accepts on compile alone.** `tools/assetgen/hand_fixture_ingest.py`;
`tools/assetgen/cli.py:cmd_autorig`; `orchestrator.py`.
`compile_hand_fixture` is imported by nothing except its own test — no CLI
subcommand, no orchestrator stage. `INGEST_ACCEPTED` is decided solely from
`missing = required_sides - certified`, derived from the compile report; steps 5
and 6 of §8 (bind sanity, grip profile) never run in the chain, and the Godot
step's own comment defers them to "the equipment slice tests". So an asset can
be ACCEPTED by ingestion without any grip gate having measured it.
Minimal fix: add the compile + a Godot-side gate run as an explicit post-autorig
stage, and make `accepted` require the gate result, not just compilation.

**H2 — a fingerless provider rig is `STEP_FAILED`, not classified, through the
real chain.** `compile_hand_fixture_headless.gd:_identify_family`.
Real run on `warrior_3d.glb`: `verdict=STEP_FAILED exit=1
detail=FIXTURE_FAMILY_MISMATCH`, identical to "asset missing" and to "Godot
could not start". The `HAND_SKELETON_INCOMPLETE` classification asserted by
`test_hand_fixture_compiler.gd` only happens when a family is injected by hand,
which production never does. §12 explicitly requires the Meshy fingerless rig to
be *classified*. No false accept, so this is a diagnosis and auditability
failure rather than a safety failure.
Minimal fix: when no family matches, still attempt (or record) a rig-shape
classification and report it as `CLASSIFIED` with a named class distinct from
infrastructure failure.

**H3 — family identity is unversioned, so editing a bone map does not invalidate
artifacts.** `hand_fixture_compiler.gd:630` falls back to `"1"` when the family
declares no `FAMILY_VERSION`, and **no family in the repo declares one**; the
committed artifact records `"family_version": "1"`. Changing
`mixamo_52_hand_family.gd`'s bone map changes what every compiled patch *means*
while `family_id` and `family_version` stay identical, so the stored artifact
keeps validating. Contract §7.
Minimal fix: require `FAMILY_VERSION` (fail closed when absent) or derive the
version from a hash of the bone map.

**H4 — the family is fitted to one Godot import configuration, and the chain
neither sets nor verifies it.** `mixamo_52_hand_family.gd:18` uses the
post-humanoid-retarget wrist name `RightHand` while every finger stays
`mixamorig_*`. Evidence: `generated_warrior_3d_uthana_rigged.glb` — the same
provider rig, 52 bones, all 30 mapped finger bones present — is refused with
`HAND_SKELETON_INCOMPLETE ("hand bone")` because its wrist is still
`mixamorig_RightHand`. So automatic compilation silently depends on an
editor-side import profile applied earlier by hand. Height candidates in the
same file *do* carry raw/renamed alternatives; the wrist does not.
Minimal fix: give `hand`/`forearm` the same candidate-list treatment as the
height bones, and have the ingestion step assert the import profile it requires.

**H5 — `MIN_CLASSIFICATION_MARGIN = 0.08` is asset calibration living in the
generic core as anatomy.** `hand_fixture_compiler.gd:56`. The measured left pad
margin on the reference asset is 0.0511; the constant was raised from 0.05 to
0.08 during implementation, and it is the sole reason the reference's left hand
is classified rather than compiled. The nail/pad thresholds sit in wide
plateaus (0.556 / 0.251) and are defensible; this one is a cut chosen after
seeing this asset's number. The left geometry *is* genuinely a continuum
(0.4971 / 0.4733 / 0.4460 / 0.4007), so the conclusion is right — but the
constant is one-asset evidence documented as generic.
Minimal fix: declare it as calibration with its provenance and the measured
margins it was set against, and re-derive it when the second rig lands.

**H6 — an inverted radial/ulnar derivation is stopped only by a scalar
confidence gate.** Baseline output: `SwappedRadialFamily` still finds a
component, still selects a nail and a pad, and is refused only by
`FIXTURE_CONFIDENCE_TOO_LOW: overall 0.1409` against `MIN_STRUCTURE_CONFIDENCE
0.35`. The accepted right hand scores 0.456. So correct anatomy and
mirror-inverted anatomy are separated by one tuned threshold with a 3.2×
margin, and the pad confidence is *identical* in both cases (0.45613) because
the pad does not depend on radial at all. No structural check rejects a mirrored
frame.
Minimal fix: add a direct check that the nail patch lies on the dorsal-radial
flank of the thumb axis (independent of score magnitude), so chirality errors
fail by name rather than by threshold.

### MEDIUM

**M1 — most named fail-closed classes are unproven.** Of the 14 required
classes, only `HAND_SKELETON_INCOMPLETE`, `PAD_PATCH_AMBIGUOUS`,
`THUMB_SURFACE_CANDIDATES_MISSING`, `FIXTURE_FAMILY_MISMATCH`,
`FIXTURE_MESH_HASH_MISMATCH` and `FIXTURE_SCHEMA_UNSUPPORTED` are asserted
exactly. `PATCH_WINDING_UNDERIVABLE` is asserted nowhere and appears
practically unreachable (it needs a degenerate aggregate normal after all
per-triangle area filters). `HAND_VOLAR_AMBIGUOUS` is documented as exercised
by `CrossedThumbFamily`, but the real outcome is `HAND_SKELETON_INCOMPLETE`
(`A2_10_NEG_VOLAR HAND_SKELETON_INCOMPLETE`) — the span check fires first, so
the volar dual-check has no negative test at all. `PATCH_BONE_WEIGHT_INSUFFICIENT`
is likewise documented for `OffThumbFamily` but the real outcome is
`FIXTURE_CONFIDENCE_TOO_LOW`.
Minimal fix: assert one exact class per negative, and add a case that reaches
the volar disagreement without tripping the span check.

**M2 — `from_artifact` does not gate `compiler_version`.** An artifact labelled
`hand_fixture_compiler_v0` is accepted by the adapter (`load_ok=true`); only
`load_artifact` checks it. Any consumer that already holds an artifact in
memory — including the tests — bypasses version invalidation.

**M3 — `ok`, `skeleton_bone_count`, `confidence`, `evidence` and `source` are
outside the hash and outside every other check.** Confidence and evidence are
what the HUD and the ingestion report present as certification evidence, so
they are unsigned certification data. Top-level `ok` can be flipped false→true
invisibly.

**M4 — UV0 is a hard requirement misreported as a bone-weight failure.**
`_gather_thumb_triangles` skips any surface whose `ARRAY_TEX_UV` is null, so a
mesh without UVs produces an empty soup and fails
`PATCH_BONE_WEIGHT_INSUFFICIENT` — a false diagnosis for a rig whose weights are
fine. The design explicitly says UV is identity only, never classification.

**M5 — the documented exit-code contract is misleading.** A fully accepted
Uthana ingestion exits **2**, because `compile_sides` defaults to both hands and
the left is always classified. Anything wired to the documented "exit 0 = every
requested side compiled" would read a successful ingestion as a refusal.

**M6 — asset-measured constants were reintroduced into the generic core as
policy.** `power_grip_1h_calibration.gd` holds the A2.7/A2.8 numbers measured on
this one asset (its own comment says the left column was "derived independently
on the reference asset") in `presentation/equipment/`, the directory A2.9b
cleared of asset-specific data. The claim "shared by every unit of the profile"
is unproven with one unit. The pinning test only proves it equals the oracle,
which is the same asset's numbers.

**M7 — rest anchoring is partial.** Only the thumb chain is reset; the frame,
the volar probe and the skinned positions are taken at the current pose. Rotating
wrist/forearm/upper-arm by 25° still produced identical patch IDs (good), but a
different content hash (feeds B1). The code comment claims the evidence is
"anchored to rest and never to whatever pose happens to be current", which is
true only of the thumb.

### LOW

**L1** — with one family registered, `_identify_family`'s ambiguity branch is
unreachable and family discrimination is untested.
**L2** — `_tri_key`'s `%08d` silently loses ordering above 1e8 vertex indices.
**L3** — achieved grip metrics differ run-to-run at ~2e-6 (`nail_out_geom`
0.933695 vs 0.933697 across two baseline runs); tolerances absorb it, but
"identical" claims about achieved measurements should be avoided.
**L4** — `sort_custom` is not a stable sort; exact component-area ties resolve
arbitrarily. Bounded by `COMPONENT_AREA_TIE_RATIO`, hence low.
**L5** — `test_hand_fixture_ingest.py:161 test_missing_godot_is_an_explicit_error`
depends on ambient environment: it passes an unusable explicit path but does not
clear `GODOT_EXE`, so `resolve_godot_executable` falls through to the
environment and returns a real executable. Observed red during this audit purely
because the shell had `GODOT_EXE` set for the ingestion runs (`1 failed, 67
passed`), and green again once unset. Minimal fix: `monkeypatch.delenv("GODOT_EXE",
raising=False)` and an empty `PATH` for that test.

---

## 13. Verdicts

| Area | Verdict | Basis |
| --- | --- | --- |
| `GENERIC OWNERSHIP` | **PARTIAL** | compiler and adapter are clean of unit names, IDs, hashes, texture signals and asset paths; but the family bone map is fitted to one import profile (H4), one threshold is asset calibration (H5) and asset-measured pose constants sit in the core as policy (M6) |
| `ORACLE INDEPENDENCE` | **PASS** | identical artifact hash with the oracle and the committed artifact physically removed |
| `SURFACE CLASSIFICATION` | **PASS** | independently re-derived: 3 right components, only the 20-triangle tip carries both plates, and both threshold plateaus are wide; the bleed components contain the highest nail score, so topology is genuinely load-bearing |
| `ARTIFACT INTEGRITY` | **FAIL** | B1 (hash not reproducible), H3 (family version nominal), M2, M3 |
| `LIVE-PATH ADOPTION` | **PARTIAL** | the compiled artifact really drives the accepted grip with no authored fallback, but the artifact is never bound to the mesh it poses (B2) |
| `HEADLESS INGESTION` | **PARTIAL** | automatic, deterministic, timeout/missing/unparseable all refusals, no editor/Blender/network; but unwired (H1), accept without gates (H1), classification collapsed into STEP_FAILED (H2), misleading exit contract (M5) |
| `FAIL-CLOSED SAFETY` | **PARTIAL** | no false accept anywhere except the foreign-mesh artifact (B2); named-class specificity weak (M1, H6) |
| `TEST INDEPENDENCE` | **PARTIAL** | the oracle comparison and the tampered-artifact negatives are real independent evidence; the determinism test is tautological and was proven red by this audit; ingestion is tested only against a fake runner; negatives accept 4–8 alternative classes |
| `RIGHT A2.7 REFERENCE PARITY` | **PASS** | through the compiled artifact: `dot(D,A)` 0.978148, volar 1.199998r, `nail_out_geom` 0.933695, `pad_in_geom` 0.303290, `closest_patch = pad`, distal roll 1.10°, fresh stamp, full 4×3 matrix and yaw invariance, no recalibration |
| `LEFT FIXTURE STATUS` | **PASS** (correctly refused) | own bone map, own geometry, reproducible `PAD_PATCH_AMBIGUOUS` at margin 0.0511, downstream T2 conflict untouched and unmasked; the faulty authored left oracle affects diagnostics only |
| `MULTI-UNIT BATCH READINESS` | **FAIL** | exactly one asset in the repo satisfies the family; the second Uthana rig is refused on a bone-name difference (H4); ingestion is unwired and ungated (H1, H2) |
| `PRODUCTION CERTIFICATION READINESS` | **FAIL** | prerequisites B1, B2, H1–H4 unmet; stage remains `CALIBRATING` |

`CALIBRATING` is not raised. One reference rig passing is not certification, and
the documentation correctly says so.

### Recommended order of correction

1. B2, then B1 (artifact identity must mean something before it is trusted).
2. H3, H4 (family identity and rig-name robustness) — both are prerequisites for
   any second unit.
3. H1, H2 (wire the chain; classify rigs instead of failing the step).
4. H5, H6, M1 (declare the calibration honestly; make chirality and the named
   classes structural).
5. M2–M7, then the LOW items.

---

## 14. Cleanup

Temporary probes `probe_forensic_audit.gd`, `probe_audit_bones.gd`,
`tmp_audit_ingest.py` and the generated artifacts `tmp_audit_fixture.tres`,
`tmp_audit_isolated.tres` were deleted. The oracle script, its `.uid` and the
committed artifact were restored after the isolation test and verified present.

Baseline re-run after cleanup, identical to the opening baseline: `slice a1` 71
checks OK, `slice a2` 1482 checks OK over 5 files (222 / 68 / 106 / 289 / 797),
`slice c1` 22 checks OK, `pytest tools/assetgen/tests` 68 passed. The only
worktree difference from the start of the review is this document.

No production code, test or steering document was modified. No commit.
