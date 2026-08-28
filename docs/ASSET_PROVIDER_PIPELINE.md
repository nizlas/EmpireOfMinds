# Asset provider pipeline (tooling)

**Status:** infrastructure established (C1); offline provider readiness established
(C2). **No provider call has ever been made from this repository.** No shield
candidate has been generated, no character has been auto-rigged live, and no paid
batch is open. Certification stage remains `CALIBRATING`.

**Offline is the default and it is enforced, not assumed.** A live provider call
requires three independent barriers (§2a). Nothing about this pipeline has been
verified against a live endpoint: the adapters were written against published
documentation and are exercised against an offline protocol double.

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
| `EOM_ALLOW_PAID_PROVIDER_CALLS` | live gate (§2a) | per-machine spend opt-in; **not** a credential |

Copy `.env.example` to `.env` and fill it in locally. `.env` is git-ignored.

### When a credential is read

**Only on the final live path, after all three barriers in §2a have passed.** This
is an ordering guarantee, not a style preference:

- Constructing a provider adapter reads **nothing**. Every offline command
  (`provider-plan`, `dry-run`, `list`, `inspect`, `status`) builds an adapter, so a
  constructor that loaded a key would mean those commands read credentials.
- `has_credential` reports `present` / `missing` by probing for a non-empty value.
  It never materialises, registers or returns the value.
- The value is loaded lazily, in exactly one place per adapter (`_headers()`),
  which is reached only when a request is actually being formed.
- A run refused at any barrier therefore has **nothing to leak**, and a refusal
  message can never depend on whether a key happens to be configured. Reversing
  this order would make an unauthorized run on a configured machine report
  `PROVIDER_CREDENTIAL_MISSING`, which reads as "configure a key and it will run".

Rules enforced in code, not just by convention:

- Credentials are read only through `secret_guard.load_credential()`, which
  registers the value with a scrubber.
- **No credential is ever a CLI argument.** A key in `argv` lands in shell history
  and in process listings. A regression walks every subcommand's real option
  strings to prove none accepts one.
- **No credential value reaches a provider plan.** A plan names the environment
  variables a live run would read and says nothing else — not even whether they
  are set, because a plan is a document meant to be pasted into a review.
- **Tests never use a real credential.** `tools/assetgen/tests/conftest.py` clears
  every provider variable and the opt-in before each test, so a green suite cannot
  depend on the developer's own configuration. Tests inject obviously synthetic
  values. Masking does not depend on a value looking like a real key: any value
  registered as secret is scrubbed, however short or malformed.
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

Nothing reaches a provider without `--live`, and `--live` alone is no longer
enough — see §2a. Without authorization, commands still run, validate and report,
and refuse at the network boundary. That is what keeps the default test suite from
ever creating a paid task.

Every subcommand declares exactly one **risk class** in
`tools/assetgen/command_risk.py`, and the central gate — not the command — decides
what that class requires. A command with no declaration fails a structural test, so
the default for a new command is "does not build", never "unguarded".

| Command | Risk class | Network | Cost |
|---|---|---|---|
| `provider-plan` | `OFFLINE` | no | free — canonical pre-plan + digest |
| `shield-plan` | `OFFLINE` | no | free |
| `validate-shield` | `OFFLINE` | no | free |
| `humanoid-gate` | `OFFLINE` | no | free |
| `ingest-rig` | `OFFLINE` | no | free |
| `status`, `inspect`, `list` | `OFFLINE` | no | free |
| `shield-multiview` (no `--submit`) | `PAID_CREATE` | no | free — dry run |
| `shield-3d` (no `--submit`) | `PAID_CREATE` | no | free — dry run |
| `autorig` (no `--submit`) | `PAID_CREATE` | no | free — dry run + gate |
| `auth-smoke` | `NETWORK_READ` | yes | free, read-only |
| `poll`, `resume`, `download` | `NETWORK_READ` | yes | free for an already-paid task |
| `cancel` | `REMOTE_MUTATION` | yes | destructive, explicit only |
| `shield-multiview --submit` | `PAID_CREATE` | yes | **paid** image task |
| `shield-3d --submit` | `PAID_CREATE` | yes | **paid** 3D task |
| `autorig --submit` | `PAID_CREATE` | yes | **paid** character slot |

What each class requires:

| Class | Requires |
|---|---|
| `OFFLINE` | nothing; it cannot mint a capability at all |
| `NETWORK_READ` | `--live` **and** `EOM_ALLOW_PAID_PROVIDER_CALLS=1` |
| `REMOTE_MUTATION` | the same two barriers |
| `PAID_CREATE` | both barriers **plus** a current executable plan, its exact `--confirm-plan <digest>`, and an acquired submission claim |

A paid command keeps its `PAID_CREATE` declaration even without `--submit`, because
that is what the command is *for*; the flag only decides whether this invocation
exercises the paid path. `--confirm-plan` exists on all three paid commands, not
just `autorig`.

`cancel` is never invoked by retry logic, error handling or cleanup. A failed
poll leaves the remote task alone precisely so it stays resumable.

---

## 2a. The three barriers (C2)

`--live` used to be the entire barrier, which made every run's safety depend on
one flag being absent. That is too easy to satisfy by accident: a flag gets copied
out of a doc or added by an agent that read the help text and wanted the command to
work. A machine with an exported `UTHANA_API_KEY` was one word away from spending.

A live provider call now needs three **independent** things, checked in this order:

| # | Barrier | Kind of evidence | Refusal code |
|---|---|---|---|
| 1 | `--live` on the command line | per-command intent | `LIVE_PROVIDER_MODE_REQUIRED` |
| 2 | `EOM_ALLOW_PAID_PROVIDER_CALLS=1` | per-machine permission | `PAID_PROVIDER_OPT_IN_REQUIRED` |
| 3 | `--confirm-plan <sha256>` | per-plan approval | `PROVIDER_PLAN_CONFIRMATION_REQUIRED` |

They are deliberately different kinds of evidence. The flag cannot travel in an
environment; the opt-in cannot travel in a command; the digest cannot be guessed —
it must be copied from a plan generated offline and read.

Further classified refusals, all raised **before** any network or credential
access:

| Code | Cause |
|---|---|
| `PROVIDER_PLAN_DIGEST_MISMATCH` | wrong or stale digest — the plan changed after approval |
| `PROVIDER_PLAN_NOT_EXECUTABLE` | the plan's own preflight refuses the input |
| `PROVIDER_CREDENTIAL_MISSING` | all barriers passed, the key is not configured |
| `PROVIDER_SUBMISSION_ALREADY_RECORDED` | this plan was already submitted |
| `PROVIDER_SUBMISSION_OUTCOME_UNKNOWN` | a create may or may not have been accepted |
| `PROVIDER_NETWORK_FORBIDDEN` | the test tripwire caught an outbound connection |

Non-negotiables:

- **Absence of authorization is never a question.** An interactive prompt would be
  answered `yes` by CI, so there is no prompt — only a classified refusal.
- **No environment variable opens traffic on its own.** The opt-in without `--live`
  refuses with `LIVE_PROVIDER_MODE_REQUIRED`.
- **Only the exact opt-in value counts.** `0`, `false`, `yes`, `true`, `2` and an
  empty string are all refusals; truthiness is not permission.
- **No best-effort, no provider fallback.** A refusal never degrades to a second
  provider or a partial run.
- Barriers 1 and 2 are enforced at the outbound boundary (§2c), so a caller that
  constructs an orchestrator or adapter directly gets the same refusal as the CLI.
  Barrier 3 applies to anything that **creates** paid work; `poll`, `resume` and
  `download` act on an already-paid task and stop at barriers 1 and 2.

### The pre-plan

```powershell
python -m tools.assetgen provider-plan <glb> --name <character> --out <path>
```

Fully offline: reads the file to hash it, evaluates the free pre-upload gate, and
emits the canonical plan plus its digest. It cannot submit anything. Exit 0 when
the plan is executable, 3 when its own preflight refuses the input.

The plan records the provider, the operation and its parameters, the local input
with SHA-256 and size, the output destination, whether the operation is paid, the
submission and retry limits, the timeouts, the credential variable **names**, the
cost, every local step that follows the paid call, and its own SHA-256.

`digest_covers` in the plan lists exactly which fields the digest binds, so what an
approval covers is auditable rather than implied. Behaviour-affecting fields are
inside it: provider, operation, operation parameters (including
`include_fingers`, which the hand pipeline depends on), input hash, output
destination, limits, timeouts, credential names, cost, local steps, and whether the
preflight allows the upload. Description-only fields — notes, the plan's own path —
are outside, so regenerating an unchanged plan reproduces the same digest.

The digest is always **recomputed from the plan's content**, never read from the
file and trusted, so editing a plan's recorded digest does not make it confirmable.

`cost: unknown` means unknown. It does **not** mean free: it means neither the
provider nor this repository declares a per-operation price, and the operation
still consumes a paid slot or credits.

### Submission and retry safety

A timeout or transport fault must never turn one approved job into two charges.

- **One creating submission per plan**, enforced by an `O_CREAT | O_EXCL` claim
  file under `artifacts/assetgen/submissions/<plan-sha256>.json`. The OS guarantees
  exactly one caller wins, which gives three properties from one primitive: a
  rerun cannot pay twice, two concurrent runs cannot both submit, and the claim
  exists on disk **before** the request goes out — so a crash mid-submission leaves
  evidence rather than a clean slate that invites a retry.
- **A create is never retried.** `transport.NO_RETRY` is mandatory for every
  creating call in every adapter. Neither Meshy nor Uthana publishes an
  idempotency key for task creation, so there is no safe retry to make. If one
  ever does, reusing the same key must be proven by a test before any retry is
  re-enabled.
- **An ambiguous create is `submission_outcome: UNKNOWN`, not `FAILED`.** A
  transport fault or 5xx on a create may have been accepted upstream and be
  billing right now. `FAILED` would read as safe to rerun; `UNKNOWN` requires a
  human to check the provider.
- **Poll and download may retry, boundedly.** They read an already-paid task and
  create nothing. Both a wall-clock deadline and an attempt cap apply.
- **A restart resumes the same job.** The provider task id is written durably
  before polling begins, and `resume` continues from it. Verified by a regression
  that discards the in-memory orchestrator and continues from the store alone.
- **Overriding the one-submission rule is not used in this slice.** Creating a
  genuinely new asset requires a new, explicitly authorized plan.

### The offline provider double

`tools/assetgen/tests/provider_double.py` answers `HttpRequest`s the way the
documented Uthana endpoint does, so the **production adapter runs unmodified** on
top of it. Mocking the adapter would have proven only that the orchestrator calls
it; the double exercises the multipart encoding, the GraphQL-200-with-`errors`
quirk, the "no bundle asset yet means still rigging" polling rule and the
authenticated bundle download — the places where a wrong assumption becomes a
wasted paid character.

It scripts submit, job id, pending, success, classified provider failure, timeout,
download, corrupt download, missing report and resume after restart, and it
**counts every call**, so regressions assert `create_calls == 1` rather than
trusting a status field that claims it.

The double routes a create by **protocol, not by substring**. It used to accept any
body containing the bytes `create_character`, which meant a request with `operations`
renamed to `ops` — a request the real endpoint would reject outright — still looked
like a successful create in every test. `tools/assetgen/tests/multipart_oracle.py` is
an independent parser of the GraphQL multipart-request specification, written from
the specification rather than from the production encoder, and it verifies the exact
`operations` and `map` field names, the file field, that both payloads are valid
JSON, that the map points at a part that exists, that the mapped variable path
resolves and is `null`, and the content-disposition structure. Renaming any required
field, remapping the variable path or changing the operation's parameters now fails
tests for the correct reason. The oracle shares no constants with the encoder it
judges.

On top of that, `tools/assetgen/net_guard.py` arms a socket-level tripwire for the
whole suite. Any attempt to leave the process — including DNS resolution of a
provider hostname — raises `NetworkForbidden` and fails the test that caused it.
Loopback stays allowed, since a local address cannot reach a provider. This catches
what transport injection cannot: a new adapter calling `urllib` directly, or a
library doing its own fetch.

---

## 2c. The capability boundary

The forensic review in `docs/reviews/ASSET_PROVIDER_LIVE_SAFETY_REVIEW.md` measured
three ways to reach a provider with less than the documented policy, and all three
had the same shape: authorization was checked wherever it was convenient rather than
where traffic leaves. `auth-smoke` consulted its own `--live` flag and sent a real
request with the machine opt-in absent; the two shield submits created paid Meshy
tasks with no plan confirmation and no ledger claim; and
`JobOrchestrator(live=True, opt_in=True).submit(...)` built a paid request from two
booleans a caller could type. None was an attack. All three were accidents of
structure.

Authorization is now a **capability**: an immutable ticket
(`tools/assetgen/capability.py`) naming exactly one operation class, one provider,
one operation and one endpoint. It can only be produced by the central gate after
the barriers pass, and it is demanded at three descending layers:

1. the **CLI** classifies the command and asks the gate for a ticket;
2. the **adapter** requires one *before* it reads a credential or builds a request;
3. the **production transport** requires one before it sends, and also requires the
   request's host to be the one the ticket approved.

Layer 3 is the lowest enforced boundary in repository-owned code. A paid ticket
additionally binds the confirmed plan digest and the acquired claim, cannot be
minted without both, and is single-use — reserved before the request goes out and
consumed afterwards, so nothing in the process can retry with it.

**The threat model, stated honestly.** This is not a sandbox and makes no
cryptographic claim. Python cannot stop code inside this process from importing the
private mint token, monkeypatching the check, or reading `os.environ` and calling
`urllib` itself. A hostile local process with repository access can always spend
money, because it can always read the same credential the legitimate path reads.
What the design does prevent is an alternative, incomplete or newly written
repository call path reaching a provider with less policy than the documented one —
which is exactly what happened three times.

### One executor for all paid creates

`autorig`, `shield-multiview --submit` and `shield-3d --submit` share one path in
`tools/assetgen/paid_executor.py`, in this fixed order:

1. recompute the plan from the files on disk right now;
2. verify the plan's own preflight says it is executable;
3. verify `--confirm-plan` matches the recomputed digest;
4. resolve the endpoint from current configuration and require it to match the plan;
5. acquire the universal `O_EXCL` submission claim;
6. mint the paid capability, binding digest and claim;
7. perform exactly one create;
8. durably record the task id, or `UNKNOWN`.

There is no paid-create path that accepts anything less. A new paid command inherits
the whole policy by being unable to submit without going through this function.

### The universal ledger and `UNKNOWN`

The claim covers every paid create, not only `autorig`. Claim files are written with
`O_CREAT | O_EXCL`, flushed and `fsync`ed, and the parent directory is synced where
the platform supports it; later transitions use atomic replacement. Disk-full,
permission and corrupt-ledger errors fail closed.

A recorded `submission_outcome: UNKNOWN` for the same paid identity refuses any
further attempt with `PROVIDER_SUBMISSION_OUTCOME_UNKNOWN`. `UNKNOWN`, an accepted
task id and a completed claim are all non-replayable, and this slice deliberately
implements **no** override — recovering from `UNKNOWN` is a human procedure that has
yet to be designed.

**The unavoidable limitation.** Neither provider offers an idempotency key or a
lookup by client submission id. A network failure after the provider accepted a
create but before we received the task id therefore cannot be distinguished locally
from a create that never arrived. The safe response is a permanent `UNKNOWN` that a
human resolves in the provider's UI, not a retry. Local design can guarantee
at-most-once; it cannot guarantee exactly-once across an unreliable network.

### Endpoint identity is part of the approval

The plan digest previously survived a change of `UTHANA_API_BASE`: the same approval
covered an authenticated upload to a different host. The plan now carries a
canonical endpoint identity — scheme, normalised host, port, base path and provider
— inside `digest_covers`, and submission recomputes it from current configuration
and requires exact agreement.

- `https` is mandatory for live traffic; an insecure endpoint cannot mint a ticket.
- A credential is never sent to a host the ticket did not approve.
- A cross-origin redirect on an authenticated request is refused rather than
  followed.
- Environment proxies are **not** inherited. The transport builds its opener with
  proxies explicitly disabled, so `HTTP_PROXY`, `HTTPS_PROXY` and `ALL_PROXY` cannot
  silently move provider traffic — a redirection the loopback-permitting network
  tripwire would not have caught.
- A fake endpoint remains reachable only through explicitly test-owned
  configuration, never as an accidental live override.

### Local filenames come from trusted data

A provider id, filename or URL component is never used as a local filename. The
review turned Uthana's `f"{character_id}_rigged.glb"` into a write inside
`C:\Windows\Temp` simply by naming a character `C:/Windows/Temp/...`. Names are now
built from data this repository owns — the local run id, our neutral artifact kind
and a fixed extension — and the provider's suggestion is kept beside the artifact as
metadata (`provider_suggested_filename`) for the audit trail.

`tools/assetgen/artifact_paths.py` is the second line: it rejects absolute paths,
drive and UNC paths, separators and alternate separators, `..`, NTFS alternate data
streams, reserved device names and Unicode forms that fold into any of those, then
resolves the destination and proves it is beneath the artifact root, refusing
symlink and reparse-point escapes. Writes are atomic — temporary file beside the
final destination inside the same proven root, fsync, replace — so a truncated
download is never visible under the artifact name.

### Request diagnostics are safe by construction

`HttpRequest` no longer inherits a generated `repr`; secret-bearing headers are
replaced by name, so `Authorization`, `Cookie` and friends cannot appear in a log,
report, exception or nested diagnostic even when the value has never been
registered. Redaction is by header semantics rather than by searching for the raw
key, because the review found the base64 HTTP Basic token surviving a raw-substring
scrub intact. Derived forms — base64 of `key:`, base64 of the key, percent-encoded
forms, padded and unpadded — are registered when a credential is loaded, and the
minimum registered length is low enough that a short or mistyped test key is still
masked.

Offline planning does not read a credential value at all. The plan's own
leak self-check works from the patterns and from values something in this process
has already loaded, so naming a variable in a plan never materialises it.

---

## 2b. The first live smoke (planned, NOT executed)

**Nothing here has been run.** No credential was read, no plan was executed, Uthana
was not contacted and no job exists.

The intended first live call is deliberately minimal: **one Uthana auto-rig on one
already-present local humanoid mesh.** Not OpenAI, not Meshy, not a batch. That
isolates the single open question — whether the grip and R4 gates hold on a
genuinely different hand morphology — at the smallest possible cost.

### Candidate inventory (offline `humanoid-gate`, 10 local meshes)

The honest result is **`NO_SAFE_UNRIGGED_CHARACTER_INPUT`: no local mesh currently
qualifies.** Every humanoid in the repository is a Meshy delivery that is *already*
skinned to a 24-joint fingerless rig and carries animation clips, so all ten fail
`no_existing_rig`, `no_animation` and `not_a_fingerless_provider_rig`.

| Mesh | Size | Tris | Why it is not the candidate |
|---|---|---|---|
| `units/warrior/warrior_3d.glb` | 10.2 MB | 30126 | **Best candidate.** Blocked only by being a rigged/animated bundle |
| `units/settler/settler.glb` | 29.4 MB | 30522 | Also fails `neutral_a_or_t_pose` (0.74); near the 30 MB ceiling |
| `units/niclas/niclas_3d.glb` | 40.9 MB | 30946 | Over the 30 MB upload limit |
| `units/bronze_armed_warrior/*.glb` | 60.5 MB | 31122 | Over the 30 MB upload limit |
| `generated_warrior/**` (4 files) | 7.4–8.5 MB | 6392–6400 | **This IS a0/a1** — same humanoid, different representation |
| `*_animations.glb` (3 files) | 10.6–57 MB | — | Motion sources, never rig input |

### Recommended candidate and its precondition

`game/assets/prototype/3d/units/warrior/warrior_3d.glb` maximises information value:
a genuinely different humanoid geometry (30126 triangles against a0/a1's ~6400),
comfortably under the upload ceiling at 10.2 MB, and it passes format, size,
texturing, upright proportions and the A/T-pose band.

Classified precisely, and no more strongly than that:

- **potentially useful as a morphological calibration probe** — a second hand
  morphology is exactly what the R4 margin has never been tested against;
- **already rigged and animated, therefore currently non-runnable** as autorig
  input;
- **approximately 30k triangles**, which is roughly five times the ~6400 of the
  existing generated humanoids;
- **not evidence of production-representative batch readiness.** The repository
  declares no polygon-budget contract, so this repair adds no triangle gate and
  makes no claim that a 30k mesh represents production work.

Its **only** blockers are consequences of it being a delivered bundle rather than
a source mesh. The precondition for the first live smoke is therefore a free, local,
offline step that does not exist yet: producing a static, un-rigged, un-animated
export of that geometry. That is a separate slice, and it is **not** implemented
here — inventing a GLB rig-stripper was outside this slice's scope.

Two checks would additionally need an explicit human waiver, because the tooling
refuses to guess them from geometry: `bipedal_humanoid` and
`hands_and_legs_separated`.

### The exact plan for that future call

```powershell
# Regenerate and read it (offline, free, deterministic):
python -m tools.assetgen provider-plan `
  game/assets/prototype/3d/units/warrior/warrior_3d.glb `
  --name eom_first_live_smoke_warrior `
  --out artifacts/assetgen/plans/first_live_smoke_warrior_3d.json
```

| Field | Value |
|---|---|
| provider / operation | `uthana` / `character_autorig` |
| input | `game/assets/prototype/3d/units/warrior/warrior_3d.glb` |
| input SHA-256 | `a8070743e639f04a037d4162a44f956092a2ab7252c996afd0b160be6fcafa62` |
| input size | 10 199 504 bytes (limit 31 457 280) |
| parameters | `auto_rig`, `auto_rig_front_facing`, `include_fingers` all true |
| max submissions | 1 (create retries: 0) |
| poll / download attempts | 60 / 3 |
| timeouts | submit 600 s, poll total 1800 s, download 600 s |
| credential needed | `UTHANA_API_KEY` (name only; no value read) |
| cost | **unknown** — one character slot, price not declared locally |
| endpoint | `uthana\|https://uthana.com:443` — now inside the digest |
| plan SHA-256 | `d9d3bbe17e41c0dfe80fbd89a9d6c1872e90fd83019b678fa524ffd3a80f726e` |
| `executable` | **false** — its own preflight refuses the input |

The digest recorded before the live-safety repair,
`57c6338999196d87a01ac9ff466f1be7973c7dc7dfbf81f89b1a897c6d52a6d0`, belonged to plan
schema v1. Binding endpoint identity into the digest moved every plan to
`provider_plan_v2`, so the old value no longer names anything. Both digests are
non-executable and neither may be authorized.

That digest is for the mesh **as it is today**. Once the static export precondition
is met the input hash changes, so the plan must be regenerated and re-read, and this
digest becomes invalid by design.

Because `executable` is false, confirming this digest today is refused with
`PROVIDER_PLAN_NOT_EXECUTABLE`. The plan is a document, not an authorization.

### Where the stop point is

**Niclas must give new, explicit authorization before any of this runs.** The
tooling cannot proceed on its own: it needs the static-export precondition, the two
human waivers, a regenerated plan, `--live`, `EOM_ALLOW_PAID_PROVIDER_CALLS=1` and
the new `--confirm-plan` digest. No paid batch is open, and the stage stays
`CALIBRATING`.

---

## 3. Auth smoke

```powershell
python -m tools.assetgen auth-smoke --live
```

Read-only per provider: a balance/account query that creates nothing. Without a
credential it reports `BLOCKED_MISSING_CREDENTIAL`; without `--live` it reports
`NOT_ATTEMPTED` so the command stays free by default.

Free is not the same as harmless: a read-only probe is still traffic to a paid
account and still proves a credential works, so it also needs barrier 2. It does
not need barrier 3, because it creates nothing to approve. **It has never been
run.**

---

## 4. Job model

Long-running provider work is orchestrated by `tools/assetgen/orchestrator.py`,
which supports `dry-run`, `submit`, `status`, `poll`, `resume`, `download`,
`inspect` and `cancel`.

The orchestrator owns three guarantees:

1. **No double spend.** Identity is the idempotency key; an identical request
   with an existing task id resumes instead of paying again. Since C2 a second,
   independent guard sits above it: the per-plan `O_EXCL` claim in §2a. The
   idempotency key stops an identical *request* from being paid twice; the claim
   stops one *approval* from being spent twice even if the request differs.
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

Two suites carry the live-safety contract:

- `test_provider_live_barriers.py` — the barrier permutations, plan digest coverage
  and TOCTOU binding, claim exclusivity, crash and resume, and the socket tripwire.
- `test_provider_capability_boundary.py` — one regression per BLOCKER, HIGH and
  MEDIUM finding in the forensic review, written the way the review *measured* each
  defect rather than the way the fix is structured, so a refactor that reintroduces
  one fails even if it satisfies the new code's own expectations.

Both count at the outbound boundary. `transport.sent == []` is evidence; a reported
refusal is not, because the review found `auth-smoke --live` reporting correctly
shaped JSON after a request had already left. Credential non-access is likewise
observed on `os.environ` itself rather than by patching the loader, since an adapter
reading the variable directly would sail past a patched `load_credential`.

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
