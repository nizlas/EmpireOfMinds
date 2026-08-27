# Targeted review — fixture identity, live-mesh binding and raw-Uthana ingestion (A2.11 repair)

Independent audit of the blocker repair performed after
[HAND_FIXTURE_COMPILER_FORENSIC_REVIEW.md](HAND_FIXTURE_COMPILER_FORENSIC_REVIEW.md).

**Audit only.** No production code, test or existing steering document was
changed. All probes were removed after the run and the four baseline profiles
were re-run afterwards. No commit. No external service, provider or credential
was contacted; every measurement below comes from local assets, local Godot
processes and mocked subprocess runners.

Stage remains **CALIBRATING**.

---

## 1. Baseline and diff boundary

`HEAD = aa5418a` ("Generative units PoC"). Worktree intentionally dirty; nothing
was stashed, reset or overwritten.

| Slice | Files |
| --- | --- |
| **A2.9b** | `grip_interaction_profile.gd` (registry-only), `power_grip_1h_policy.gd`, the move of `uthana_warrior_hand_fixture.gd` out of the core into `uthana_a2/`, `uthana_a2_power_grip.gd` |
| **A2.10 / A2.11 (under audit)** | `hand_fixture_compiler.gd`, `hand_fixture_compiler_calibration.gd`, `hand_fixture_artifact.gd`, `compiled_hand_fixture.gd`, `equipment_assembler.gd`, `humanoid_hand_profile.gd`, `mixamo_52_hand_family.gd`, `skinned_mesh_geometry.gd`, `power_grip_1h_calibration.gd`, `tools/certify_hand_fixture_headless.gd`, `uthana_a2_equipment_composition.gd`, `uthana_a2_walking_preview.gd`, `uthana_a2_hand_fixture.tres`, `test_hand_fixture_compiler.gd`, `test_hand_fixture_identity.gd`, `test_equipment_interaction_pipeline.gd`, `test_uthana_a2_power_grip_parity.gd`, `tools/assetgen/hand_fixture_ingest.py`, `tools/assetgen/rig_ingest.py` + tests, `cli.py`, `run-godot-tests.ps1`, the six doc files |
| **C1** | `tools/assetgen/**` except `hand_fixture_ingest*`/`rig_ingest*`, `shield_inspection_diagnostic.*`, `test_shield_inspection_diagnostic.gd`, `docs/ASSET_PROVIDER_PIPELINE.md`, `scan-secrets.py`, `.env.example` |

Baseline, before any probe:

| Profile | Result |
| --- | --- |
| `slice a1` | exit 0 — 71 checks OK |
| `slice a2` | exit 0 — 222 + 68 + 113 + 77 + 291 + 797 = **1568 checks OK** |
| `slice c1` | exit 0 |
| `pytest tools/assetgen/tests` | **87 passed** |

---

## 2. B1 — canonical identity, independently verified

The forensic finding was a hash that differed between contexts
(`4D8D3B5DCC…` in test, `54DE1B64D6…` headless). The repair's claim is that the
cause was world-space, achieved-pose geometry derivation, fixed by compiling in
skeleton space with the skeleton pinned to rest.

**Verification method.** Rather than re-running the repo's own test, one context
per **separate Godot process** (six processes), each compiling the same GLB with
the same side set and printing the content hash:

| Process | Context | Content hash | Pose restored | Left |
| --- | --- | --- | --- | --- |
| 1 | scale 1.0 | `2A07A3FA4F61B3B4…` | yes | `PAD_PATCH_AMBIGUOUS` |
| 2 | preview scale 0.30 | `2A07A3FA4F61B3B4…` | yes | `PAD_PATCH_AMBIGUOUS` |
| 3 | uniform scale 7.25 | `2A07A3FA4F61B3B4…` | yes | `PAD_PATCH_AMBIGUOUS` |
| 4 | scale 0.75 + translate (12,−3,7.5) + yaw 1.1 | `2A07A3FA4F61B3B4…` | yes | `PAD_PATCH_AMBIGUOUS` |
| 5 | **active non-rest pose** at scale 1.0 | `2A07A3FA4F61B3B4…` | yes | `PAD_PATCH_AMBIGUOUS` |
| 6 | active non-rest pose at scale 0.30 | `2A07A3FA4F61B3B4…` | yes | `PAD_PATCH_AMBIGUOUS` |
| 7 | headless ingestion step (`certify_hand_fixture_headless.gd`) | `2A07A3FA4F61B3B4…` | n/a | `PAD_PATCH_AMBIGUOUS` |
| 8 | CLI (`python -m tools.assetgen ingest-rig`) | `2A07A3FA4F61B3B4…` | n/a | `PAD_PATCH_AMBIGUOUS` |

One identity across eight independent producers, including two with a real
non-rest pose applied before compilation. The divergence is **eliminated at the
root, not hidden by test data**: the invariance is structural (skeleton space +
pinned rest) and survives contexts the repo's own test does not exercise
(scale 7.25, a multi-bone posed skeleton).

**Sub-checks, all confirmed:**

- *Skeleton space* — `skinned_vertex_local()` omits `skeleton.to_global()`;
  `derive_frame(..., SPACE_SKELETON)` uses raw bone transforms.
- *Rest pose pinned* — `_pin_rest_pose()`/`_restore_pose()` around the whole
  side loop.
- *Restoration on early FAIL* — verified per process: compiling with a bone map
  whose thumb chain resolves to nothing classifies
  `HAND_SKELETON_INCOMPLETE` for both sides and still restores every bone pose
  (`restored_after_fail=true` in all six processes). Every `_failed_artifact`
  early return happens *before* pinning, so no path leaves the skeleton pinned.
- *Stored == hashed == used* — `_artifact()` canonicalises the payload and
  **then** hashes it, so runtime consumes the same grid points that were hashed.
  Round-tripping through `.tres` is stable: synthetic markers at magnitudes
  1, 10, 100 and 1000 all reload with a matching hash, so float storage does not
  push a snapped value across a quantum boundary.
- *Whole payload covered* — `IDENTITY_EXCLUDED_KEYS` is exactly
  `["content_hash", "source_asset"]` and the filter is top-level, so a new
  behaviour field is inside identity **by default**. Adding any key to a stored
  payload changes the hash and is rejected on load.
- *Above the quantum changes identity, below it does not* — confirmed both by
  the repo's test and by construction.

**`source_asset` exclusion is legitimate.** It is written once
(`certify_hand_fixture_headless.gd:160`) and read by nothing: a repository-wide
search finds no consumer in mesh selection, binding, pose, policy or acceptance.
It is a filesystem path, i.e. provenance only.

**Verdict: `CANONICAL FIXTURE IDENTITY` = PASS, `CROSS-PROCESS DETERMINISM` =
PASS, `WHOLE-PAYLOAD INTEGRITY` = PASS.**

---

## 3. B2 — live-mesh binding, independently verified

Traced path, confirmed by execution:
`uthana_a2_equipment_composition.compiled_fixture()` →
`Compiler.mesh_identity_of_asset(SOURCE_GLB_PATH)` →
`CompiledHandFixture.from_artifact(..., expected)` →
`EquipmentAssembler.assemble()` → `_verify_fixture_binding()` →
`fixture.verify_against_mesh(find_skinned_mesh(character))`.

The expected identity is derived from the asset, not from the payload under
test, and the composition contains no copied hash (the only hard-coded 64-hex
string in `game/` is `GLB_SHA256` in the authored oracle — see L-2).

Sabotage matrix, all executed against the real classes:

| Sabotage | Result | Verdict |
| --- | --- | --- |
| empty expected identity | `FIXTURE_MESH_IDENTITY_REQUIRED` | correct |
| `source_mesh_sha256 = AAAA…`, **content hash recomputed correctly** | `FIXTURE_MESH_HASH_MISMATCH` at `from_artifact` | correct |
| same forged artifact **and** a caller fooled into expecting `AAAA…` | assembler returns `reason=fixture_mesh_binding_failed`, `error_class=FIXTURE_MESH_HASH_MISMATCH` | correct — never reaches `thumb_patch_frame_mismatch` |
| valid fixture, different actual `MeshInstance3D` (a1 fixture on a0's mesh) | `FIXTURE_MESH_HASH_MISMATCH`, live `0B4264AA…` vs expected `1B2B52C8…` | correct |
| vertex data edited behind an unchanged payload | mesh sha `1B2B52C8…` → `8FC1AD00…`, rejected | correct |
| foreign family id | `FIXTURE_FAMILY_MISMATCH` | correct |
| **foreign family _version_** (`"999"`, correctly rehashed) | **loads OK** | **H-2** |
| missing artifact | `FIXTURE_ARTIFACT_MISSING` | correct |
| no fixture injected | `FIXTURE_REQUIRED` | correct |
| **skeleton rest changed behind unchanged mesh arrays** | mesh sha **unchanged**, binding **passes**, recompile yields a different content hash | **H-1** |

The check order is proven, not asserted: the fooled-caller case is the only way
to reach the assembler with a forged artifact, and it stops at
`fixture_mesh_binding_failed` before any pose, socket or geometric bind sanity.

**Does `mesh_identity_of_asset(path)` bind to the mesh the assembler poses?**
Partially. Both sides call the same `find_skinned_mesh()` on the same asset, and
the live re-hash in `verify_against_mesh` closes the gap for mesh *arrays*. It
does **not** cover the skin bind poses or the skeleton rest, which every
compiled marker depends on (H-1), and neither side pins *which* surface index
the identity refers to (M-3).

**Verdict: `LIVE-MESH BINDING` = PARTIAL. `PRODUCTION CALLER ADOPTION` = PASS.**

---

## 4. Ingestion and publish safety

Call graph, confirmed by real subprocess argv capture:

```
python -m tools.assetgen ingest-rig
  → rig_ingest.ingest_rigged_humanoid
      → resolve_godot_executable            (missing toolchain = exit 1 + report)
      → godot --headless --import           (first call, before certification)
      → hand_fixture_ingest.certify_hand_fixture
          → godot --headless -s certify_hand_fixture_headless.gd --out=<STAGING>
              import → family_resolution → fixture_compilation
              → artifact_integrity → mesh_binding
              → bind_sanity (real EquipmentAssembler) → grip_ground_truth
      → publish to the composition path ONLY if ACCEPTED
      → artifacts/assetgen/rig_ingest/<asset>.json
```

Interruption sabotage, executed with a stubbed Godot:

| Injected failure | Result |
| --- | --- |
| import step exits non-zero | `STEP_FAILED`, exit 1, certification never attempted |
| classified rejection after an earlier acceptance | exit 2, `published=False`, **published file still holds the accepted artifact**, staged file holds the rejected one |
| accepted chain, staged artifact deleted before publish | `STEP_FAILED`, exit 1, nothing published |
| accepted chain, step never wrote a staged artifact | `STEP_FAILED`, exit 1 |
| identical rerun | byte-identical report, still published |
| rejection after acceptance, rerun | previous acceptance preserved, report records `published: false`, `accepted: false` |

Exit contract, measured with the **real** CLI on real assets:

| Case | Exit | Verdict | Error class | Stage |
| --- | --- | --- | --- | --- |
| a1 target, full chain | **0** | ACCEPTED | — | — |
| a0 raw rig | **2** | CLASSIFIED | `DEGENERATE_HEIGHT` | `grip_assembly` |
| settler (24 bones) | **2** | CLASSIFIED | `HAND_SKELETON_INCOMPLETE` | `family_resolution` |
| a1 target, `--required-sides left` | **2** | CLASSIFIED | `PAD_PATCH_AMBIGUOUS` | `fixture_compilation` |
| unknown policy | **1** | STEP_FAILED | `INGEST_POLICY_UNKNOWN` | `invocation` |
| unknown pinned family | **1** | STEP_FAILED | `INGEST_FAMILY_UNKNOWN` | `family_resolution` |
| missing weapon | **1** | STEP_FAILED | `CLUB_MISSING` | `grip_assembly` |

Compiler-PASS is genuinely not asset-ACCEPTED: a0 and the `--required-sides left`
case both have `compiler_pass=true` and are still exit 2 with nothing published.

**Verdict: `EXIT PROTOCOL` = PASS. `STAGING/PUBLISH SAFETY` = PARTIAL** (B-1, M-1).

---

## 5. Forensic diagnosis of `uthana_a0_rigged`

Step-by-step comparison, measured on both assets in one process:

| Property | `uthana_a0_rigged` (raw) | `a1_uthana_target` |
| --- | --- | --- |
| GLB root transform | identity | identity |
| `Armature` ancestor scale | **0.01** | 1.0 |
| Skeleton node | `Skeleton3D`, local transform identity | `GeneralSkeleton`, identity |
| Skeleton **global** transform | `[X:(0.01,0,0), Y:(0,0,0.01), Z:(0,−0.01,0)]` — 100× down-scale **plus** a −90° X rotation | identity |
| Mesh node / surfaces / skin binds | `mesh`, 1 surface, 52 binds | `mesh`, 1 surface, 52 binds |
| **Mesh AABB size** | **(0.998298, 1.020288, 0.302752)** | **(0.998298, 1.020288, 0.302752)** |
| Rest-bone extent in **skeleton space** | (97.264, 15.697, 88.874) | (0.9726, 0.8887, 0.15697) — same numbers, ÷100, Y/Z swapped |
| Bone naming | `mixamorig_Head`, `mixamorig_Hips`, `mixamorig_RightHand`, `mixamorig_LeftToeBase` | `Head`, `Hips`, `RightHand`, `LeftFoot` |
| `import_representation` | `raw_mixamo` | `godot_humanoid_retarget` |
| Family resolution | **resolves** (hand + all 15 finger bones) | resolves |
| Compiler | **PASS** — 4 nail, 7 pad triangles | PASS — 4 nail, 10 pad |
| Artifact integrity | PASS | PASS |
| Mesh binding | PASS | PASS |
| `measure_humanoid_height(HEIGHT_HEAD_CANDIDATES, HEIGHT_FLOOR_CANDIDATES)` | **0.000000000** | 0.888740689 |
| Same call with the head list run through the family's **own** `bone_name_candidates()` | **0.888740689** | 0.888740689 |
| Final ingestion | exit 2, `DEGENERATE_HEIGHT` | exit 0, ACCEPTED |

### Answers

1. **Is a0 geometrically degenerate? No.** Its mesh AABB is bit-identical to
   a1's, and its measured humanoid height is `0.888740689` — the *same value as
   the accepted asset* — the moment the head bone is looked up under the name it
   actually has.
2. **Is it an import/transform/coordinate-contract fault? Only indirectly.** a0
   does carry an unbaked `Armature` scale of 0.01 and a −90° X rotation, and its
   skeleton space is therefore 100× larger and axis-permuted relative to a1's.
   That difference is *correctly absorbed* everywhere it matters:
   `measure_humanoid_height` multiplies by `skeleton.global_transform`, the
   compiler works in skeleton space with scale-free ratio checks
   (`THUMB_REACH_HAND_SPANS`), and the identity is bound per mesh. The
   coordinate contract is not the failure.
3. **Is a normalization step missing? Yes — a name-normalization step.**
   `HEIGHT_FLOOR_CANDIDATES` was hand-patched with `mixamorig_LeftToeBase` /
   `mixamorig_RightToeBase`, so the floor resolves. `HEIGHT_HEAD_CANDIDATES` is
   `["head_end", "Head"]` with **no** alias, so the head does not. A2.11 taught
   the family to resolve aliases for `bone_map()` (`resolved_bone_map()`,
   `bone_name_candidates()`) but left the sibling `HEIGHT_*_CANDIDATES` constants
   — owned by the same family file and consumed by the same generic
   `measure_humanoid_height()` — outside that resolution. The alias fix is
   therefore incomplete rather than absent.
4. **Is `DEGENERATE_HEIGHT` the right gate in the wrong place? The gate is
   right; its input is wrong.** `measure_humanoid_height` returns `0.0` for
   *both* "the bones are degenerate" and "I could not find the head bone", and
   the assembler cannot tell those apart. So a truthful "this rig's head bone is
   spelled differently" is reported as an untruthful "this rig has no height".
5. **Would a new raw Uthana delivery follow a0 or a1? a0.** The provider returns
   raw Mixamo naming; `a1_uthana_target.glb` is a *processed* target asset whose
   bones are already Godot-humanoid renamed. Nothing in the pipeline performs
   that rename: `run_import()` only calls `godot --headless --import`, and the
   import profile that produces `Head`/`RightHand` is not established by the
   ingestion chain. Every fresh raw delivery is therefore expected to reach
   `DEGENERATE_HEIGHT`.

### Classification

**`INGESTION_NORMALIZATION_GAP`** — with a `GATE_BUG` component in the
`0.0`-means-two-things return of `measure_humanoid_height`. Not
`ASSET_SPECIFIC_VALID_REJECTION`: the asset's height is measurable and equals the
accepted asset's. Not `MESH_BINDING_COORDINATE_BUG`: binding passed and the
coordinate handling is correct.

Because every future raw Uthana delivery is expected to take this path, this is
a **blocker before any paid provider batch** (B-2).

---

## 6. Family resolution

| Requirement | Result |
| --- | --- |
| Alias data owned by `mixamo_52_hand_family.gd` | **PASS** — `NAME_ALIAS_PREFIXES`, `bone_name_candidates()`, `resolved_bone_map()`, `import_representation()` all live there |
| Generic compiler free of `mixamorig_*` / Uthana bone names | **PASS** — no bone-name match anywhere under `presentation/equipment/` outside the family file; the only "Uthana" occurrences are a comment and the CALIBRATING owner's id, which is honest naming of one-rig calibration data |
| Raw Mixamo and Godot-retargeted names resolve deterministically | **PASS** for the hand bone map (a0 resolves hand + all 15 finger bones); **FAIL** for the height candidates (B-2) |
| Genuinely fingerless 24-bone rigs still `HAND_SKELETON_INCOMPLETE` | **PASS** — six assets, exit 2, stage `family_resolution` |
| An unknown 52-bone rig not assumed compatible on bone count alone | **PASS** — `_family_match()` requires every mapped name to resolve; bone count is never a criterion. A rig whose wrist resolves but whose digits do not is `HAND_SKELETON_INCOMPLETE`; a rig whose wrist does not resolve is `FIXTURE_FAMILY_MISMATCH` |

**Verdict: `RAW MIXAMO FAMILY RESOLUTION` = PARTIAL** (hand map yes, height
candidates no). **`RAW UTHANA INGESTION READINESS` = FAIL.**

---

## 7. Test independence

| Test | Producer | Expected / oracle | Sabotage that reddens it | Assessment |
| --- | --- | --- | --- | --- |
| cross-process identity (`test_hand_fixture_identity.gd:138`) | in-test `Compiler.compile` | a **separate Godot process** running the real certify script, compared by hash | any context-dependence; historically observed red as `2A07A3FA…` vs `014C392D…` when the side sets differed | strong — a same-process recompile could not make this claim |
| scale/pose independence (`:67`) | four scene contexts + a posed wrist | mutual hash equality | any world-space term re-entering the compile | strong; this audit widened it to six separate processes and a multi-bone pose, same result |
| rehashed foreign-mesh sabotage (`:290`) | forged artifact, hash recomputed | `FIXTURE_MESH_HASH_MISMATCH` and `reason=fixture_mesh_binding_failed` | removing the assembler's first-action binding call | strong — the only test in the suite that proves check *order* |
| production caller (`:274`) | `Composition.dependencies()` + real `EquipmentAssembler` | `binding == "compiled_bound"`, `verified == true`, sha equals the asset-derived one | injecting a fixture without `verify_against_mesh` | strong for the compiled path |
| rejected artifact not loadable (`:365`) | artifacts with a failed *side* | side error class propagates | — | **overclaimed**: covers "the required side failed to compile", not "the asset was rejected downstream". See B-1 |
| authored-fixture-not-fallback (`:356`) | `deps["fixture"].SCHEMA_VERSION` | not equal to the oracle's schema string | changing a version string | **weak**: compares two strings; it does not show the oracle is unusable, and it is in fact assemble-able (H-3) |
| a0 family resolution (`:437`) | real compile on a0 | `error_class != HAND_SKELETON_INCOMPLETE || !detail.contains("hand bone")` | reintroducing that exact message | **weak**: a negative message check that passes for any other error class, and it never asserts that a0 compiles (the outcome is only printed) |
| publish-only-after-acceptance (`test_rig_ingest.py`) | stubbed Godot writing a staged file | `published` flag + destination file | returning exit 0 with `accepted:false` | adequate; the "staged artifact vanished before publish" branch has **no** test (verified only by this audit) |
| exit codes | real `subprocess` argv + return codes in pytest; real CLI subprocesses in this audit | verdict/exit mapping | any remap | strong |
| missing-Godot env isolation (`test_hand_fixture_ingest.py`) | `monkeypatch.delenv("GODOT_EXE")` + `setenv("PATH","")` | `GodotNotAvailable` | — | **fixed and effective**: the suite passes with `GODOT_EXE` set in the environment, so the test fails for the intended reason |
| a0 compiler-PASS but chain-FAIL | — | — | — | **no test**: only this audit's CLI run and the untracked `artifacts/assetgen/rig_ingest/uthana_a0_rigged.json` record it |
| A2.7 parity matrix | `Composition.make_assembler()` → real assembler with the compiled artifact | pinned A2.7 numbers, 4×3 matrix, surface ground truth, yaw invariance | any pose/socket/threshold change | strong, and confirmed to run through the production composition (797 checks) |

**Verdict: `TEST INDEPENDENCE` = PARTIAL. `A2.7 PARITY PRESERVATION` = PASS.**

---

## 8. Findings

### BLOCKER

#### B-1 — A rejected asset's staged artifact loads as a fully accepted fixture

*File/function:* `compiled_hand_fixture.gd:from_artifact`,
`hand_fixture_compiler.gd:load_artifact`, `rig_ingest.py` (publish gate).

*Evidence.* `uthana_a0_rigged` is a **classified-rejected** asset (exit 2,
`DEGENERATE_HEIGHT`). Its staged artifact
`res://artifacts/fixtures/staging/uthana_a0_rigged_hand_fixture.tres` was loaded
directly:

```
load_artifact ok=true
artifact ok_flag=false  acceptance_scope=compiler_surface_evidence_only  right_compiled=true
carries_chain_verdict=false
REJECTED_ASSET_LOADS_AS_FIXTURE ok=true  err=
  verify_against_live_a0_mesh={ "ok": true, "sha256": "0B4264AA5EAEEB29…" }
```

It loads, it passes level-1 binding against a0's own live mesh, and it is
indistinguishable from an accepted fixture. `from_artifact` never inspects the
artifact's own `ok` flag, and that flag would be useless anyway — the *accepted*
a1 artifact also has `ok:false`, because its left side is classified.

*Broken contract.* `docs/EQUIPMENT_INTERACTION.md` ("a rejected artifact can be
kept for diagnostics without ever becoming a loadable accepted fixture"),
`docs/DECISION_LOG.md` ("can never become an accepted fixture by sitting in the
right place"), and repair requirement §6 ("får aldrig kunna laddas som ett
accepterat fixture-artifact"). The only actual barrier is the *path convention* —
and `res://artifacts/fixtures/staging/` is inside the loadable project, so any
composition that names that path gets a rejected asset's fixture.

*Why tests miss it.* `_test_rejected_artifact_cannot_load_as_accepted` only
constructs artifacts whose **required side failed to compile**. The a0 shape —
compiler PASS, asset rejected by a later gate — is exactly the case the slice
introduced and is untested.

*Minimum fix.* Make acceptance a checkable property of the artifact rather than
of its location: have the ingestion chain write an acceptance receipt into the
artifact (chain steps completed, policy id, verdict) inside the hashed payload,
and have `from_artifact` require it. A staged artifact then carries no receipt
and fails closed by name (e.g. `FIXTURE_NOT_CERTIFIED`).

#### B-2 — Every raw-Mixamo rig fails the height gate on a name alias, not on geometry

*File/function:* `mixamo_52_hand_family.gd:HEIGHT_HEAD_CANDIDATES`, consumed by
`skinned_mesh_geometry.gd:measure_humanoid_height`, gated in
`equipment_assembler.gd:239`.

*Evidence.* See §5. a0's height is `0.000000000` with the shipped candidate list
and `0.888740689` — identical to the accepted asset — with the head list run
through the family's own `bone_name_candidates()`. a0's mesh AABB is bit-identical
to a1's. `HEIGHT_FLOOR_CANDIDATES` contains `mixamorig_*` entries; the head list
does not.

*Broken contract.* Repair requirement §7: "pipeline ska själv etablera eller
verifiera den importrepresentation som family-profilen kräver" and "samma
Uthana-skelett får inte klassificeras som fingerlöst endast på grund av
namnnormalisering". The hand map honours this; the height candidates do not, and
the resulting message (`DEGENERATE_HEIGHT`) is untrue about the asset. Because
raw naming is what a provider actually returns, this blocks paid batch runs.

*Why tests miss it.* No test calls `measure_humanoid_height` on a raw-Mixamo
skeleton, and the a0 assertion in `test_hand_fixture_identity.gd` stops at the
compiler and only forbids one obsolete message.

*Minimum fix.* Resolve `HEIGHT_HEAD_CANDIDATES` / `HEIGHT_FLOOR_CANDIDATES`
through the same family alias resolver the bone map uses (or expose a
`resolved_height_candidates(skeleton)`), and separate "head bone not found" from
"height is degenerate" so the two failures get different names.

### HIGH

#### H-1 — Source-mesh identity is blind to the skin bind poses and the skeleton rest

*File/function:* `hand_fixture_compiler.gd:mesh_identity`.

*Evidence.* Moving `RightHand`'s bone rest by 5 cm:

```
S5 sha_after_bone_rest_change=1B2B52C8BFA96DA9  unchanged=true
S5 verify_still_passes=true
S5 recompiled_hash=8227746F0ABCCFE7  semantic_changed=true
```

The identity that authorises the binding is unchanged, the binding passes, and
yet recompiling the *same mesh* under the new rest yields a different fixture.
Every compiled marker and normal lives in bone-local space, so the artifact is a
function of (mesh arrays, skin binds, skeleton rest) while level 1 hashes only
the mesh arrays.

*Broken contract.* Identity level 1 is documented as "the mesh that was compiled
and that must later be the mesh actually posed". A re-import or rig edit that
preserves vertex/normal/UV/bone/weight streams while changing the rest or bind
pose produces a **stale artifact that binds successfully** — the class of defect
this slice existed to close.

*Why tests miss it.* The sabotage matrix edits vertex data only; nothing edits
the rig behind an unchanged mesh.

*Minimum fix.* Fold `mi.skin` bind bones/names/poses and the referenced bones'
`get_bone_rest()` into `mesh_identity()`, or add a `source_rig_sha256` that
`verify_against_mesh` checks alongside the mesh hash.

#### H-2 — `family_version` is never verified when an artifact is loaded

*File/function:* `compiled_hand_fixture.gd:from_artifact` (checks `family_id`
only), `hand_fixture_compiler.gd:load_artifact`.

*Evidence.* An artifact with `family_version` rewritten to `"999"` and its
content hash correctly recomputed loads successfully:
`S11 foreign_family_version -> ok=true`.

*Broken contract.* Repair requirement §3 lists "artifact från annan
family-version" among the cases that must fail closed, and
`docs/EQUIPMENT_INTERACTION.md` claims "foreign family/family-version" is
fail-closed. It is not. The hash does change, so the *committed* artifact cannot
be swapped without recompiling — but an artifact genuinely produced under a
different family version is accepted at runtime, which is the case that matters
when the family map evolves.

*Why tests miss it.* `test_hand_fixture_compiler.gd` asserts `family_version` is
*present* in the artifact and hashed; no test asserts it is *verified*.

*Minimum fix.* Compare `artifact.family_version` against the injected family's
`FAMILY_VERSION` in `_verify_fixture_binding` (the assembler already holds the
family) and reject with `FIXTURE_FAMILY_MISMATCH`.

#### H-3 — Live-mesh binding is opt-in: a fixture without the method skips level 1 entirely

*File/function:* `equipment_assembler.gd:_verify_fixture_binding:157`.

*Evidence.* `if not fixture.has_method("verify_against_mesh"): return {"ok": true,
"binding": "authored_unbound", "verified": false}`. Assembling the hand-authored
oracle through the real assembler:

```
S7 authored_has_verify=false
S7 authored_assemble ok=true  binding={"ok": true, "binding": "authored_unbound", "verified": false}
```

*Broken contract.* "Live-mesh binding is mandatory" (docs) is true only for
fixtures that volunteer. There is no *automatic* fallback to the oracle — the
composition injects the compiled artifact and nothing else, so this is not an
active production hole — but there is also no structural prevention: a unit
whose compiled artifact is rejected can be made to work by injecting an
authored fixture, which is precisely the escape hatch the slice set out to
remove.

*Why tests miss it.* The relevant assertion compares two schema strings (see
§7); no test asserts that an unbound fixture is refused.

*Minimum fix.* Require `verify_against_mesh` on every injected fixture and fail
`FIXTURE_MESH_IDENTITY_REQUIRED` when it is absent; give the oracle a binding if
it must stay assemble-able in tests.

### MEDIUM

#### M-1 — Publishing is not atomic

*File/function:* `rig_ingest.py:ingest_rigged_humanoid` —
`destination.write_bytes(source.read_bytes())`, with no temp-file + `os.replace`.
A crash mid-write leaves a truncated `.tres` at the path a composition loads.
The consequence is fail-closed (the reader's schema/hash check refuses it), so
this is not a silent-acceptance risk, but the documented claim of "atomic or
otherwise fail-closed" publishing rests entirely on the reader. *Fix:* write to
`<dest>.tmp` and `os.replace()`.

#### M-2 — The independently derived expected identity is dropped from the machine report

*File/function:* `hand_fixture_ingest.py:HandFixtureIngestResult`. The Godot step
emits `expected_source_mesh_sha256`, but the dataclass has no such field, so the
published report shows it empty (`CLI expected =`). An auditor reading
`artifacts/assetgen/rig_ingest/*.json` cannot see that level 1 was checked
against an independent value. *Fix:* carry the field through `to_dict()`.

#### M-3 — Neither identity level pins which mesh/surface the fixture refers to

*File/function:* `skinned_mesh_geometry.gd:find_skinned_mesh` (first skinned
mesh in tree order), used by the compiler, `mesh_identity_of_asset` and the
assembler. They agree today because they share the helper and the same scene, but
a unit with a second skinned mesh (armour, cloth) could change which mesh is
"first", and the artifact records no mesh-node identity — only `si` per triangle.
*Fix:* record the chosen mesh node path / surface count in the hashed payload and
compare it during binding.

#### M-4 — A rejection can report a stage that is not part of the declared chain

*File/function:* `certify_hand_fixture_headless.gd:_stage_for` returns
`"grip_assembly"` as its fallback, overriding the tracked `_stage`. a0's report
therefore names a stage (`grip_assembly`) that appears in neither the documented
chain nor `chain`. *Fix:* map the fallback onto `bind_sanity`, or declare
`grip_assembly` as a chain step.

### LOW

- **L-1** `hand_fixture_compiler.gd:_failed_artifact` hashes its payload without
  calling `canonicalize` first, unlike `_artifact`. Harmless today (that payload
  contains no floats) but it breaks the "stored == hashed" invariant the moment a
  float is added.
- **L-2** `uthana_warrior_hand_fixture.gd:26` still carries a hand-copied
  `GLB_SHA256` constant that nothing verifies. Not on the production path, but it
  is the only hard-coded 64-hex hash left in `game/`.
- **L-3** Requiring a side the artifact never compiled reports
  `THUMB_SURFACE_CANDIDATES_MISSING`, conflating "never compiled" with "no
  candidates found". The real ingestion compiles both sides, so the production
  message is correct; only the partial-artifact case is misleading.
- **L-4** The a0 assertion in `test_hand_fixture_identity.gd:440` is a negative
  message check that passes for any other error class and never asserts that a0
  compiles; the outcome is only printed.
- **L-5** `test_hand_fixture_identity.gd:356` asserts the oracle "cannot become
  the production fixture" by comparing two schema-version strings.

---

## 9. Verdicts

| Area | Verdict |
| --- | --- |
| `CANONICAL FIXTURE IDENTITY` | **PASS** |
| `CROSS-PROCESS DETERMINISM` | **PASS** |
| `WHOLE-PAYLOAD INTEGRITY` | **PASS** |
| `LIVE-MESH BINDING` | **PARTIAL** (H-1, H-2, H-3) |
| `PRODUCTION CALLER ADOPTION` | **PASS** |
| `STAGING/PUBLISH SAFETY` | **PARTIAL** (B-1, M-1) |
| `EXIT PROTOCOL` | **PASS** |
| `RAW MIXAMO FAMILY RESOLUTION` | **PARTIAL** (hand map yes, height candidates no) |
| `RAW UTHANA INGESTION READINESS` | **FAIL** (B-2) |
| `A2.7 PARITY PRESERVATION` | **PASS** |
| `TEST INDEPENDENCE` | **PARTIAL** |
| `PAID BATCH READINESS` | **FAIL** (B-2 blocks; B-1 makes a rejected batch member loadable) |

Stage: **CALIBRATING.** Multi-unit batch certification has not started.

### What the repair genuinely achieved

B1 is fixed at the root, not papered over: one content hash across eight
independent producers, including two with a real non-rest pose, and pose
restoration verified even on a mid-loop classification failure. B2's hardest
case — a correctly rehashed artifact reaching a fooled caller — is stopped by
the live re-hash before any pose or geometric bind sanity, through the real
production assembler. The exit protocol is truthful in all seven real
subprocess cases, publishing is genuinely gated on full acceptance, and an
earlier acceptance survives a later rejection. A2.7 parity is untouched.

### What is not yet true

Acceptance is still a property of *where a file sits*, not of the artifact
(B-1). Level-1 identity covers the mesh arrays but not the rig they are skinned
to (H-1), and the binding is skippable by omission (H-3). Raw provider naming —
the only naming a real delivery will have — still fails on an incomplete alias
list and is reported with a false error class (B-2).

---

## 10. Recommended order before a paid batch

1. **B-2** — alias-resolve the height candidates and split "head bone not found"
   from "height degenerate". Without this every raw delivery is rejected for the
   wrong reason.
2. **B-1** — put an acceptance receipt inside the hashed payload so a rejected
   artifact fails closed by name wherever it sits.
3. **H-1** — extend level-1 identity to the skin binds and skeleton rest.
4. **H-2 / H-3** — verify `family_version`, and require a binding method on
   every injected fixture.
5. Re-run the breadth diagnostic and only then consider
   `CALIBRATING → BATCH_CERTIFICATION`.

Cleanup: all probes (`game/presentation/tests/zz_review_probe_*.gd`, `.review/`)
and every artifact they generated were removed; the four baseline profiles were
re-run afterwards and are green.
