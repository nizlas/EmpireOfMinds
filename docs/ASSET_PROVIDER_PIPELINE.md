# Asset provider pipeline (tooling)

**Status:** infrastructure established (C1). No shield candidate has been generated yet.

This document describes `tools/assetgen`, the backend/tooling package that talks
to external asset providers: image generation, image-to-3D reconstruction, and
character auto-rigging.

Everything here is **tooling, never gameplay**. Nothing under `tools/` is
imported by the Godot client or the authority server, and provider credentials
are read from the environment by this package alone. A provider outage, a rate
limit, or a bad generation can therefore never change a gameplay rule.

Provider specifics in this document are **operational facts about a vendor**, not
design rules. When a vendor changes its API, this document changes. The canonical
equipment contract lives in `docs/EQUIPMENT_INTERACTION.md`.

---

## 1. Credentials

| Variable | Used by | Purpose |
|---|---|---|
| `MESHY_API_KEY` | meshy adapter | images and image-to-3D meshes |
| `UTHANA_API_KEY` | uthana adapter | character auto-rig |
| `MESHY_API_BASE` | meshy adapter | optional host override (mock/staging) |
| `UTHANA_API_BASE` | uthana adapter | optional host override |

Copy `.env.example` to `.env` and fill it in locally. `.env` is git-ignored.

Rules enforced in code, not just by convention:

- Credentials are read only through `secret_guard.load_credential()`, which
  registers the value with a scrubber.
- Every string written to a manifest, a log line, an exception message or a
  response snapshot passes through `secret_guard.scrub()`. A leaked key is
  replaced with `__REDACTED__`.
- A missing credential is a **blocked job**, never a fabricated result. The job
  is recorded as `BLOCKED_MISSING_CREDENTIAL` with no provider task id.
- `scripts/scan-secrets.py` statically scans changed files for key-shaped
  content and never echoes a candidate value in its own output.

```powershell
python scripts/scan-secrets.py          # changed + untracked files
python scripts/scan-secrets.py --all    # whole tracked worktree
```

---

## 2. Free vs paid commands

Nothing reaches a provider without `--live`. Without it, commands still run,
validate and report, and refuse at the network boundary. That is what keeps the
default test suite from ever creating a paid task.

| Command | Network | Cost |
|---|---|---|
| `shield-plan` | no | free |
| `validate-shield` | no | free |
| `humanoid-gate` | no | free |
| `status`, `inspect`, `list` | no | free |
| `shield-multiview` (no `--submit`) | no | free — dry run |
| `shield-3d` (no `--submit`) | no | free — dry run |
| `autorig` (no `--submit`) | no | free — dry run + gate |
| `auth-smoke --live` | yes | free, read-only |
| `shield-multiview --submit --live` | yes | **paid** image task |
| `shield-3d --submit --live` | yes | **paid** 3D task |
| `autorig --submit --live` | yes | **paid** character slot |
| `poll`, `resume`, `download` | yes | free for an already-paid task |
| `cancel` | yes | destructive, explicit only |

`cancel` is never invoked by retry logic, error handling or cleanup. A failed
poll leaves the remote task alone precisely so it stays resumable.

---

## 3. Auth smoke

```powershell
python -m tools.assetgen auth-smoke --live
```

Read-only per provider: a balance/account query that creates nothing. Without a
credential it reports `BLOCKED_MISSING_CREDENTIAL`; without `--live` it reports
`NOT_ATTEMPTED` so the command stays free by default.

---

## 4. Job model

Long-running provider work is orchestrated by `tools/assetgen/orchestrator.py`,
which supports `dry-run`, `submit`, `status`, `poll`, `resume`, `download`,
`inspect` and `cancel`.

The orchestrator owns three guarantees:

1. **No double spend.** Identity is the idempotency key; an identical request
   with an existing task id resumes instead of paying again.
2. **No lost artifact.** Provider output URLs are signed and short-lived, so a
   successful poll downloads immediately and records local paths plus SHA-256.
   A signed URL is not storage.
3. **No silent visual claim.** `visual_status` is always `PENDING_USER_REVIEW`.
   No code path may set it to anything else.

### Statuses

`CREATED`, `DRY_RUN`, `SUBMITTED`, `IN_PROGRESS`, `SUCCEEDED`, `DOWNLOADED`,
`FAILED`, `CANCELED`, `BLOCKED_MISSING_CREDENTIAL`, `BLOCKED_PREFLIGHT`.

`SUBMITTED`, `IN_PROGRESS` and `SUCCEEDED` are resumable, because in all three a
provider task id exists and the work is either still running or still
downloadable.

### Manifest

One `manifest.json` per job under `artifacts/assetgen/jobs/<job_id>/`:

| Field | Meaning |
|---|---|
| `job_id` | internal id, derived from provider, label, attempt and key |
| `provider`, `task_type`, `provider_endpoint` | neutral task type plus the concrete endpoint used |
| `provider_task_id` | the remote id a resume needs |
| `provider_model_version`, `contract_version` | what the result was produced against |
| `prompt_version`, `prompt_hash`, `prompt_text` | prompt identity |
| `inputs[]` | relative path, role, order and SHA-256 per input |
| `request_parameters` | generation parameters, secret-free |
| `status`, `progress`, `retry_count` | lifecycle |
| `created_at`, `started_at`, `finished_at` | timing |
| `error` | classified failure: kind, provider, http status, retryable |
| `reported_credits` | only when the provider reports it |
| `output_urls` | last known signed URLs (volatile) |
| `outputs[]` | downloaded artifacts: relative path, SHA-256, size, source host |
| `structural_validation` | validator result when one has been attached |
| `visual_status` | always `PENDING_USER_REVIEW` |
| `notes[]` | append-only audit trail of decisions taken |

Manifests are versioned in git; downloaded binaries and response snapshots are
git-ignored. A clean checkout can therefore still resume or re-download a job.

### Idempotency

The key is a SHA-256 over:

```
provider + task type + provider/model version + contract version
+ prompt hash + ordered input hashes + generation parameters + attempt id
```

`submit` looks for an existing manifest with that key. If one holds a provider
task id, it resumes. A genuinely new attempt requires `--force-new-attempt`,
which allocates the next unused attempt id and therefore a different key.

Editing the prompt or any generation parameter changes the key by construction,
so a changed request can never silently reuse an old result.

### Rate limits and retries

`RetryPolicy` implements bounded exponential backoff with equal jitter:
5 attempts, 1 s base, 30 s ceiling. `Retry-After` is honoured and still clamped
to the local ceiling.

Only `RATE_LIMIT`, `TRANSIENT` (5xx), `TIMEOUT` and `TRANSPORT` are retried.
`AUTH`, `PAYMENT`, `INVALID_REQUEST`, `UNPROCESSABLE`, `PROVIDER_FAILURE`,
`CONTRACT` and `MISSING_OUTPUT` are blocking — retrying them would spend money
or loop forever. Retries reuse the same request and never create a second task
id while the existing one is still resumable.

### Resuming an interrupted job

```powershell
python -m tools.assetgen list
python -m tools.assetgen inspect <job_id>
python -m tools.assetgen resume <job_id> --live
```

`resume` reads the stored `provider_task_id`. If outputs are already on disk and
their hashes match, it does nothing. If the task succeeded but the signed URLs
have expired, it re-fetches the task to obtain fresh URLs and downloads again.

---

## 5. Shield multiview contract

`generate_multi_view` and `multi_view_thumbnails` are unrelated and are
constantly confused:

| Parameter | Stage | Effect |
|---|---|---|
| `generate_multi_view` | **image** job input | asks the image model for several consistent camera angles of one subject. This is what produces reconstruction input. |
| `multi_view_thumbnails` | **3D** job output | renders front/right/back/left previews of a finished mesh. It has no influence on reconstruction. |

Setting `multi_view_thumbnails` and expecting multiview *input* is a silent
no-op that yields a single-view reconstruction.

Contract details:

- `generate_multi_view` cannot be combined with `aspect_ratio`; the adapter
  rejects that combination locally, before spending.
- The prompt (`shield_pipeline.SHIELD_MULTIVIEW_PROMPT`, version
  `shield-multiview-v1`) demands a rigid cylindrical handgrip as real 3D
  geometry with empty clearance, and forbids painted decoration, shadow,
  embossing, shallow relief, and any generated hand or arm.
- Retry budget: **at most one** stricter image regeneration. If the automatic
  multiview still lacks a readable rear, generate an explicit back view and
  combine ordered `image_urls`: front first, then explicit back, then the best
  three-quarter/side.
- Local images are inlined as data URIs, so reference art never needs a public
  bucket.

### Multiview preflight

Preflight separates what a file can prove from what only an eye can:

**Mechanical (automated):** at least two views returned, views are distinct
files, all views meet the minimum resolution.

**Visual (`REQUIRES_HUMAN`):** same design in every view; an unambiguous rear or
three-quarter-rear view; a rigid grip visible as geometry rather than paint; real
empty clearance; room for a hand with curled fingers; no generated hand or arm;
no perspective or silhouette collapse.

`shield-3d` refuses to submit until `--confirm-visual-review` records that a
human checked the visual list. Automating that judgement is the cheapest way to
waste a paid 3D job on a flat plate.

---

## 6. Shield structural validation

```powershell
python -m tools.assetgen validate-shield <glb> `
  --compare-pre-remesh <pre_remeshed.glb> `
  --out artifacts/assetgen/shield/<name>.json
```

Reports GLB parse result, mesh/surface/triangle/vertex counts, materials and
texture paths, bounds, disconnected components, degenerate and thin geometry,
the estimated shield body and plate frame, handle candidates with length,
diameter and clearance, and suggested `shield_grip`, `forearm_contact` and
`shield_forward` markers.

Handle detection samples the **surface** densely rather than reading vertices, so
a 1 000-triangle export and a 100 000-triangle export measure the same. A void
counts only when the surfaces bounding it face *into* it, which is what separates
an open channel a hand can enter from the shield's own solid interior.

Classifications: `HANDHELD_CANDIDATE`, `FOREARM_FALLBACK_ONLY`,
`NO_READABLE_HANDLE`, `REMESH_DESTROYED_HANDLE`, `NEEDS_USER_VISUAL_REVIEW`,
`UNPARSEABLE`.

`production_approved` is always `false` and `visual_status` is always
`PENDING_USER_REVIEW`. The validator produces a candidate, never an approval.
Suggested markers are **diagnostics**; they do not become runtime markers.

Why the pre-remeshed mesh is always kept: a 1 000-triangle remesh can merge a
thin grip into the plate. Comparing pre and post is the only way to tell "the
grip was never generated" from "the grip was generated and then decimated away",
and those two failures need opposite fixes.

---

## 7. Character auto-rig chain (Meshy → Uthana)

The intended chain for a new humanoid:

1. Generate or author a **static, textured, unrigged** humanoid mesh in a
   neutral A- or T-pose.
2. Run the pre-upload gate.
3. Auto-rig it with `include_fingers=true`.
4. Retarget motion onto the resulting rig separately.

```powershell
python -m tools.assetgen humanoid-gate <glb> --out artifacts/assetgen/humanoid/gate.json
python -m tools.assetgen autorig <glb> --name <character>            # dry run
python -m tools.assetgen autorig <glb> --name <character> --submit --live
```

### `include_fingers=true` is mandatory

The equipment pipeline grips with fingers. A rig without finger joints cannot
express any grip pose, so a fingerless rig is unusable no matter how good the
mesh is. The adapter rejects `include_fingers=false` locally.

### An already-rigged or animated GLB is not valid input

A provider bundle that arrives skinned and animated is a **motion source**, not
rig input. Auto-rigging it again produces a second skeleton over an existing one.
The gate refuses:

- an existing skin (`no_existing_rig`)
- any animation channel (`no_animation`)
- a compact skeleton with no finger joints, i.e. a provider auto-rig
  (`not_a_fingerless_provider_rig`)
- unsupported format, or a file at or above 30 MB
- a mesh with no base-colour texture
- proportions inconsistent with an upright standing figure, or an arm-span ratio
  outside both the A-pose and T-pose bands

Two checks are reported `UNVERIFIABLE` rather than passed: whether the mesh is
genuinely **bipedal**, and whether **hands and legs are separated** well enough
to rig. Neither can be established from geometry by this tooling, so they need an
explicit human waiver. The gate is fail-closed: an unverifiable claim blocks the
upload instead of being assumed.

When nothing in the worktree qualifies, the gate reports
`NO_SAFE_UNRIGGED_CHARACTER_INPUT`.

### Post-rig ingestion: rigged humanoid → ACCEPTED or classified FAIL (A2.10–A2.12)

Once the provider returns the finger-rigged humanoid, the equipment pipeline
still needs to know which triangles are that unit's thumb nail plate and volar
pad. That is compiled automatically rather than hand-authored per unit — and
compiling is only the middle of the chain, not the acceptance.

**Canonical entry point:** `tools/assetgen/rig_ingest.py`, exposed as

```powershell
python -m tools.assetgen ingest-rig res://path/to/rigged.glb `
  --asset-id my_unit --publish res://path/to/my_unit_hand_fixture.tres
```

It is also called from the autorig `poll`/`download` path once a rigged GLB
lands inside `game/` (suppress with `--no-ingest-rig`). What it owns:

1. **import** — `godot --headless --import`, so the import representation the
   skeleton family needs is established by the pipeline. No editor visit.
2. **skeleton-family resolution** — the family resolves its own bone-name
   aliases against the rig (`RightHand` and `mixamorig_RightHand` are the same
   family), reports which representation it found, and distinguishes a foreign
   rig from an incomplete hand. An explicit `--family` is verified against the
   rig; no match and an ambiguous match both fail closed.
3. **humanoid normalization** — the semantic height landmarks (`head_top`,
   `foot_floor`) are resolved through the family and measured in a declared
   canonical space, so raw-Mixamo and Godot-retargeted deliveries of one humanoid
   measure the same height. Unfindable landmarks are
   `HUMANOID_HEIGHT_LANDMARKS_UNRESOLVED`; `DEGENERATE_HEIGHT` is reserved for
   geometry that really is flat.
4. **fixture compilation** — per side, in a canonical context (skeleton space,
   pinned rest pose) so the artifact's identity does not depend on the caller.
5. **artifact integrity** — the artifact is written, re-read from disk and its
   content hash re-verified.
6. **rig binding** — the evidence is bound to the *imported* asset's
   `source_geometry_sha256` **and** `source_rig_sha256`, both derived from the
   asset itself and never from the artifact's own payload. The rig identity
   covers skin bind poses, weights, bone indices, the bone hierarchy and every
   rest transform, so a re-import that preserves the vertex streams but moves the
   rig is caught.
7. **assemble and measure** — through the real `EquipmentAssembler` and grip
   engine, not a certification copy: live-rig binding, hand profile, socket, the
   grip invariants and the selected policy's achieved-geometry gate (for
   `power_grip_1h_v1`: the closest skinned patch to the handle must be the volar
   pad). Because the assembler accepts only a certified fixture, the chain mints a
   **bind-sanity bootstrap** envelope scoped to the steps completed so far; it
   carries a distinct acceptance schema and cannot be written to disk at all.

   Up to A2.12 this was reported as two chain links, `bind_sanity` and
   `grip_ground_truth`. It was always one measurement — the surface gate runs
   inside `assemble()` and the second "step" only re-read `closest_patch` out of
   the first's result — so A2.13a merged them rather than keep claiming two
   independent gates.
8. **certification** — only now does a runtime-loadable fixture come into
   existence, recording exactly what passed, for which identities, family version
   and policy version. Certification is the *consequence* of the chain, not a
   link in it, which is why it is not one of the required steps.
9. **one machine-readable result** — a `HAND_FIXTURE_INGEST` JSON line from the
   Godot step, plus a per-asset report under
   `artifacts/assetgen/rig_ingest/<asset-id>.json`.
10. **ACCEPTED, or a classified rejection with a named domain error class.**

Steps 1–8 run inside Godot, owned by
`presentation/equipment/hand_fixture_certification_authority.gd` and driven
through the CLI adapter
`presentation/equipment/tools/certify_hand_fixture_headless.gd`, which
`tools/assetgen/hand_fixture_ingest.py` invokes.

**Who runs the gates (A2.13a).** Up to A2.12 the CLI ran the chain and then told
`Certification.certify()` that the chain had completed and passed, so a caller
could pass `chain = REQUIRED_CHAIN` and `{"pass": true}` and mint a certificate
with nothing run. The chain now belongs to the certification authority: the CLI
supplies an asset path, a staging path, the hands, a policy id and a weapon, and
has **no argument** for a step, a gate result or a verdict. The authority
resolves the family and the policy from its own registries and performs every
step above itself, recording each step's own measurement. The acceptance report
is an output of those measurements, and the verdict is re-derived from them
whenever a certificate is read.

**A compiler PASS is not an accepted asset.** Steps 5–7 can still reject a rig
whose fixture compiled cleanly.

**Publishing is gated on acceptance, and file placement is not the gate (A2.12).**
Two files are staged under `res://artifacts/fixtures/staging/`, and they are not
the same kind of thing:

| Staged file | What it is | Runtime-valid? |
| --- | --- | --- |
| `<id>_hand_fixture.tres` | the compiler's **evidence** | never |
| `<id>_hand_fixture_certified.tres` | a **certificate**, minted only for a fully accepted chain | yes, and only this |

Only the certificate is ever published, and only with an explicit `--publish`
destination. The publish is **atomic**: the bytes are written to a temporary file
beside the destination and then `os.replace`d over it, so a reader sees either
the previous artifact or the new one, never a truncated resource. An interrupted
publish can leave a leftover `.publishing` file but cannot damage the artifact
the game loads, and a rejection never overwrites or deletes an accepted one
because a rejected asset never reaches the publish step.

A rejected asset's evidence stays in staging as a diagnostic. It is not kept out
of the game by its directory: an evidence file copied or renamed onto the
published path is refused by the runtime loader, because it is the wrong resource
type and carries no certification envelope (`FIXTURE_NOT_CERTIFIED`).

**What the certificate binds.** A lone `certified = true` would be worthless, so
the envelope names the fixture content hash (with the evidence embedded
verbatim), the source geometry and rig identities, family id + version, compiler
version and evidence schema, compiler-calibration id + version, policy id +
version, policy-calibration id + version, acceptance schema + version, the
completed chain, the certified sides, and a digest of the acceptance report — all
covered by the certificate's own hash. A certificate that fails to record every
chain step cannot load, and a re-hashed certificate whose report is not a pass is
still refused.

**What the certificate proves, and what it does not (A2.13a).** The envelope
proves *integrity*: nothing drifted after minting, the certificate has the shape
only the canonical certification path produces, and it is bound to a specific
evidence payload, geometry, rig, family + version and policy + calibration. It
also proves internal consistency — the recorded verdict is re-derived from the
per-step measurements rather than read as a declaration, and the report's
identities must equal the envelope's, so a report borrowed from another asset or
naming a policy that does not exist is refused even with a correctly recomputed
digest.

It does **not** prove that the recorded measurements were taken. Without a
signing authority no local check can, so the certificate is prior acceptance
evidence and never a permission to skip a gate: the runtime re-derives geometry
and rig identity from the live mesh and skeleton, re-checks family and policy,
and re-runs bind sanity and the achieved-geometry gate every single time a
fixture is used. Both are required. Before A2.13a this section's predecessor
implied the envelope proved the chain had run; it proved the caller had said so.

**Exit protocol** (identical in the Godot step, the Python driver and the CLI):

| Exit | Meaning |
| --- | --- |
| `0` | the whole chain was accepted |
| `2` | expected, classified asset/fixture FAIL with a named domain error class |
| `1` | infrastructure / process / protocol / tooling error |

A fingerless or incomplete rig is exit `2` with `HAND_SKELETON_INCOMPLETE`, not a
generic step failure. Timeout, a missing or unparseable report, an unstartable
Godot and a missing toolchain are exit `1` with their own classes
(`INGEST_TIMEOUT`, `INGEST_REPORT_MISSING`, `INGEST_GODOT_START_FAILED`,
`INGEST_GODOT_NOT_AVAILABLE`) and still emit a report. There is no fallback to
another unit's fixture and no partial acceptance.

**Why Godot and not Python.** The compiler must see exactly the geometry the
renderer sees: the same importer, the same skin bind poses and the same CPU
skinning the grip gates measure against. A second implementation here would be a
second, silently diverging notion of the mesh. **Blender is still not a
dependency** and is not shipped with the game.

**What is not claimed.** No external provider callback invokes this chain
automatically. The provider round trip is `autorig` + `poll`/`download`; the
ingestion step then runs on the downloaded file, and whether it ran for a given
job is visible in the emitted report rather than assumed.

### Certification stages

`certification_stage()` distinguishes:

| Stage | Meaning |
| --- | --- |
| `CALIBRATING` | The compiler is proven on one reference rig, verified against a hand-authored oracle and a human-approved visual reference. **Current state.** |
| `BATCH_CERTIFICATION` | The same profile compiles and passes the grip gates across several independent rigs. |
| `PRODUCTION_CERTIFIED` | Batch-green across repeated runs, so production runs need no human approval step. |

A single certified unit is never reported above `CALIBRATING`. Section 9 below
still applies: for the shield/visual path nothing here accepts an asset.

**Multi-unit batch certification has not started.** The A2.11 read-only breadth
run over the eight existing humanoid GLBs is diagnostic: it verifies that
classifications are truthful and reproducible across fresh processes, not that
the profile is certified. One asset reached ACCEPTED (exit 0); one resolved its
family and compiled before failing a later grip gate (exit 2); six 24-joint rigs
are `HAND_SKELETON_INCOMPLETE` (exit 2).

**A2.12 raw-Mixamo delivery result.** `generated_warrior_3d_uthana_rigged.glb`
now passes import, family resolution, humanoid normalization, right-hand
compilation (4 nail / 7 pad triangles), artifact integrity and rig binding, and
is classified `THUMB_OPPOSITION_GATE_FAILED` at the grip gate: verdict
`CLASSIFIED`, exit `2`, nothing published, no certificate minted. Its previous
`DEGENERATE_HEIGHT` rejection was a false claim caused by the height landmark
list, not by the asset. Under A2.13a the same result is reported at the honest
step name `assemble_and_measure`, and it names both `thumb_approach_axial` and
`thumb_approach_radially_outward`.

**The cause is the compiled surface, not the rest basis (corrected in A2.13a).**
A2.12 recorded that the thumb-chain rest orientations differ from the
representation the pose calibration was authored against. That is **refuted**:
the two deliveries reach the same anatomical joint pose to within ~1.5° despite a
90° difference in the hand's rest basis and a 100× armature scale, because the
pose is applied as rest-relative deltas about axes derived from the rig, so the
pipeline already normalises the representation difference. The real difference was
the compiled surface, and the compiled pad normal feeds the derived anatomical
axes, so the surface difference rotated the frame the approach is measured in.

**A2.13b — the raw delivery now certifies.** The divergence was one operation: the
per-triangle winding decision compared a **skeleton-space** face normal against
the imported shading normal carried by `pose · rest⁻¹`, which omits the bind pose
and uses the basis where the **inverse-transpose** is required. Whether that
flipped a triangle depended on the export's bind representation, which is the
entire 7-versus-10 pad result. Ingestion now classifies in one canonical rest
space with normals carried by the inverse-transposed blended skin basis, resolves
winding once per surface by consensus of two independent authorities, and adds an
**independent anatomical validation** step (`thumb_surface_anatomy.gd`) that both
the compiler and the runtime bind ask from the live rig's own frame rather than
from anything the fixture declares about itself.

Both deliveries of the reference humanoid now report:

| | raw delivery | retargeted delivery |
| --- | --- | --- |
| verdict | `ACCEPTED`, exit `0` | `ACCEPTED`, exit `0` |
| right-hand plates | 4 nail / 10 pad | 4 nail / 10 pad |
| achieved closest patch | `pad` | `pad` |
| `approach_axial_fraction` | 0.593724 (limit 0.60) | 0.593774 (limit 0.60) |
| `approach_radial_radii` | 0.055441 (limit 0.15) | 0.055421 (limit 0.15) |
| left hand | `PAD_PATCH_AMBIGUOUS` | `PAD_PATCH_AMBIGUOUS` |

The ingestion report now carries a `gate_metrics` block (limits, achieved
approach/contact values, joint pose and socket metrics) so a rejection or a thin
margin is readable from the report rather than from a log.

**The R4 axial margin is ~1% on both** (`0.0063`). Nothing was tuned; τ, σ, the
authored angles, the R4 limit and the approach thresholds are unchanged. Two
deliveries of **one** humanoid agreeing is representation invariance, not batch
robustness, so the stage is still `CALIBRATING` and the paid multi-unit batch
remains closed. No provider, credential or network call was involved in A2.13b.

---

## 8. Tests

```powershell
python -m pytest tools/assetgen/tests -q      # provider adapters + validator + gate + ingestion chain
.\scripts\run-godot-tests.ps1 slice c1        # shield inspection diagnostic scene
.\scripts\run-godot-tests.ps1 slice a2        # hand-fixture compiler + identity/binding + grip parity
python scripts/scan-secrets.py                # static secret scan
```

Every HTTP response in the suite is a fake. The fake transport raises on any URL
it was not primed for, so an accidental live call fails loudly instead of
quietly costing money. Real provider calls require `--live` and are never part of
the default suite.

The shield analyser is tested against synthetic meshes with a **known** answer,
including the adversarial case of a grip that is only embossed. A validator that
accepted a flat plate would be worse than none, because it would authorise
attaching a shield that can never be held.

---

## 9. Tomorrow's review is still required

Nothing in this pipeline can accept an asset. The cloud side produces a
candidate plus measurements; a human decides whether the geometry is real.
Open the diagnostic scene and work through its checklist:

```
game/presentation/diagnostics/shield_inspection_diagnostic.tscn
```

Orbit, zoom, jump to preset views, toggle the suggested marker gizmos, toggle a
hand-sized clearance probe, and toggle a cutaway that shows whether a "handle" is
a separate bar or a bump on the plate. The scene implements no hand pose and no
grip solve by design.
