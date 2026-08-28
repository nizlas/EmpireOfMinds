# Independent verification — provider execution boundary after the live-safety repair

Second-pass review of the repair that answers
`docs/reviews/ASSET_PROVIDER_LIVE_SAFETY_REVIEW.md`. Written in a fresh context
against the code, not against the implementation report: every claim below was
re-measured with instruments this review owns, kept outside the repository, and
every number in it comes from a run recorded during this pass.

**Verdict: no BLOCKER and no HIGH remains.** Three LOW findings and one
documented MEDIUM limitation are recorded in section 13. The commit was
therefore taken, and it authorizes nothing: no credential was read, no socket
left the process, and both known plan digests remain non-executable.

---

## 1. Method — why these measurements count as evidence

The repair ships its own test suites. Those suites are exactly what a re-review
may not lean on, so this pass used a separate harness in a temporary directory
that imports the production modules directly and never touches the repository's
fixtures, helpers or `conftest.py`:

| Instrument | What it measures | Why it is stronger than a returned error |
| --- | --- | --- |
| `OutboundCounter` | every call that reaches the transport seam | a refusal that still built and dispatched a request is visible here and invisible in an error code |
| `EnvironmentRecorder` | reads of watched names on `os.environ` itself | patching `load_credential` proves one function was not called; this catches any route, including `os.environ.get` inside an adapter |
| `record_file_targets` | absolute target of every `os.open` and `os.replace` | containment proven on the syscall, not on a string the caller returned |
| real subprocesses | two independent processes racing one approved plan | in-process locks cannot fake an `O_EXCL` result |
| session socket/DNS tripwire | `getaddrinfo`, `gethostbyname`, `create_connection`, `socket.connect`, `connect_ex` | armed at plugin import, before collection, never disarmed |

158 independent probes, all green, **0 non-loopback attempts** across the whole
verification session. The repository's own 241 tests were additionally re-run
with the tripwire armed from collection through teardown: also 0 attempts.

---

## 2. Snapshot and baseline

| Item | Value |
| --- | --- |
| HEAD | `5baebd2b885279733985da1d122c8242faa7273f` |
| Staged before this pass | nothing |
| Modified | 16 files |
| Untracked | 15 files (14 intended + the first review) |
| Diff vs `5baebd2` | 16 files, +1689 / −145 |

Modified: `.env.example`, `.gitignore`, `docs/ASSET_PROVIDER_PIPELINE.md`,
`docs/CURRENT_ARCHITECTURE.md`, `docs/DECISION_LOG.md`, `docs/TESTING.md`,
`tools/assetgen/{cli,manifest,orchestrator,secret_guard,store,transport}.py`,
`tools/assetgen/providers/{__init__,meshy,uthana}.py`,
`tools/assetgen/tests/test_provider_pipeline.py`.

Untracked, with SHA-256 prefixes recorded at verification time:

| File | SHA-256 (first 16) | Lines |
| --- | --- | --- |
| `docs/reviews/ASSET_PROVIDER_LIVE_SAFETY_REVIEW.md` | `0f81e859b45604bc` | 672 |
| `tools/assetgen/artifact_paths.py` | `fd8de0b1a756370d` | 164 |
| `tools/assetgen/capability.py` | `e780c0240cacccf6` | 265 |
| `tools/assetgen/command_risk.py` | `1935bce4c35db5c1` | 75 |
| `tools/assetgen/endpoint.py` | `c5943dadcec8237a` | 125 |
| `tools/assetgen/live_gate.py` | `7267822a378e7d0a` | 291 |
| `tools/assetgen/net_guard.py` | `d4bd4233dfcd1ffc` | 70 |
| `tools/assetgen/paid_executor.py` | `4b668d02346f26e1` | 147 |
| `tools/assetgen/provider_plan.py` | `20fc5e674917aadd` | 460 |
| `tools/assetgen/tests/authorization_support.py` | `412ad75a64444d07` | 82 |
| `tools/assetgen/tests/conftest.py` | `781a2e30396333e1` | 64 |
| `tools/assetgen/tests/multipart_oracle.py` | `87be9eee18246335` | 189 |
| `tools/assetgen/tests/provider_double.py` | `8cf943510fa6eaef` | 201 |
| `tools/assetgen/tests/test_provider_capability_boundary.py` | `c87aa92b1563633c` | 946 |
| `tools/assetgen/tests/test_provider_live_barriers.py` | `7635ea0a84ff70b8` | 968 |

Five checks, provider and proxy variables cleared:

| Check | Result |
| --- | --- |
| `slice a1` | 71 checks, OK |
| `slice a2` | 2044 checks across 9 tests, OK |
| `slice c1` | 22 checks, OK |
| `pytest tools/assetgen/tests -q` | 241 passed |
| `scripts/scan-secrets.py` | 31 files scanned, no secret-shaped content |

`slice a2` was run in a child PowerShell with `$ErrorActionPreference='Continue'`
so the intentional `CLUB_MISSING` stderr from `test_uthana_a2_preview_runtime`
could not abort the profile, exactly as `docs/TESTING.md` requires.

### 2.1 The a2 count: 2044 reconciled, not accepted

Per-test counts measured this pass: 222 + 68 + 141 + 90 + 73 + 82 + 279 + 292 +
797 = **2044**.

The earlier `1996` cannot be attributed to the provider work, and the argument
does not rely on trusting either report:

1. **The diff cannot reach a2.** `git diff --name-only 5baebd2` contains no path
   under `game/` or `scripts/`. The a2 profile runs nine GDScript files under
   `game/presentation/tests/`, all byte-identical to HEAD.
2. **a2 never calls the changed code.** Grepping the nine scripts for `python`,
   `tools/assetgen`, `OS.execute` and `create_process` finds two call sites, both
   `OS.execute(OS.get_executable_path(), ...)` — the same Godot binary on
   `res://` scripts. No a2 test can observe `tools/assetgen/` at all.
3. **The count is not environment-dependent.** The only input outside `game/` is
   Godot's `user://` directory. It was moved aside (22 `.tres` files) and a2 was
   re-run from a cold user state: **2044, with byte-identical per-test counts**.
   The files were restored afterwards.
4. **Where the dynamic counts come from.** The source-driven assertions are loops
   over production constants — `Certification.REQUIRED_CHAIN` (twice in
   `test_hand_fixture_certification.gd`, once in `test_hand_fixture_identity.gd`),
   `Certification.REPORT_BOUND_FIELDS`, `Policy.RESERVED` — plus the per-delivery
   and per-context comparisons added by `5baebd2` itself
   (`test_thumb_surface_invariance.gd`, the dual-delivery certification runs).
   Those constants live in `game/presentation/equipment/`, which this work does
   not touch, so the number is fixed at 2044 for this tree.

`1996` is therefore a stale figure carried between reports, not a regression and
not a change of behaviour. It could not be reproduced in this environment, and
nothing in the provider slice is capable of producing it. Recorded as a
measurement-hygiene note: future reports should quote the nine per-test counts,
which localise any change immediately.

---

## 3. Every former BLOCKER and HIGH, re-exploited

Each row was attempted the way the first review measured it. "Outbound" is the
count at the transport seam; "credential reads" is the count on `os.environ`.

| Former finding | Attempt | Outbound | Credential reads | Result |
| --- | --- | --- | --- | --- |
| BLOCKER 1 `auth-smoke` bypass | `--live auth-smoke`, both keys set, no opt-in | **0** | **0** | `PAID_PROVIDER_OPT_IN_REQUIRED` per provider |
| BLOCKER 1 (mirror) | `auth-smoke` with opt-in but no `--live` | **0** | **0** | `LIVE_PROVIDER_MODE_REQUIRED` |
| BLOCKER 2 paid Meshy | `--live shield-multiview --submit`, opt-in set, no digest | **0** | 1 presence probe (LOW 1) | `PROVIDER_PLAN_CONFIRMATION_REQUIRED`, no ledger entry |
| BLOCKER 2 paid Meshy | `--live shield-3d --submit --confirm-visual-review`, opt-in set, no digest | **0** | 1 presence probe (LOW 1) | `PROVIDER_PLAN_CONFIRMATION_REQUIRED`, no ledger entry |
| HIGH 4 direct orchestrator | `JobOrchestrator(...).submit(request)` with no capability | **0** | — | `PROVIDER_CAPABILITY_REQUIRED` |
| HIGH 4 direct adapter | `UthanaProvider(...).submit(request)` with no capability | **0** | **0** | `PROVIDER_CAPABILITY_REQUIRED` |
| HIGH 4 direct transport | `UrllibTransport().send(request)` with no capability | **0** | — | `PROVIDER_CAPABILITY_REQUIRED` |
| HIGH 4 forged ticket | hand-constructed `ProviderCapability` into the production transport | **0** | — | `PROVIDER_CAPABILITY_INVALID` |
| HIGH 5 UNKNOWN replay | ambiguous create, then a fresh orchestrator, fresh claim, same work | **1 total** (the original) | — | `PROVIDER_SUBMISSION_OUTCOME_UNKNOWN`; **zero additional creates** |
| HIGH 3 hostile filename | 15 provider-controlled names through the write path | — | — | every one refused; no `os.open`/`os.replace` outside the temporary root |
| HIGH 6 endpoint drift | `UTHANA_API_BASE=https://staging.uthana.example` after approval | **0** | — | `PROVIDER_ENDPOINT_NOT_APPROVED`, and the re-planned digest differs |
| HIGH 7 Basic-auth leak | `repr`, `str`, f-string, `%`, `format`, `describe`, `safe_headers`, `scrub_obj(raw headers)` | — | — | no raw key, no `base64(key:)`, padded or unpadded, in any rendering |
| HIGH 8 renamed multipart | `operations → ops`, `map → m` | — | — | oracle refuses and names the missing part |

The `--live` flag and the opt-in were also swept independently: `true`, `yes`,
`2`, `0`, `false`, `01`, `""` and `1 1` are all refused with
`PAID_PROVIDER_OPT_IN_REQUIRED` and zero outbound.

---

## 4. Capability scope

Tested past presence, on the object itself and at the transport:

* a hand-built look-alike is refused — `PROVIDER_CAPABILITY_INVALID` — because
  the mint token is checked, not merely the type;
* a `NETWORK_READ` ticket presented for a paid create is refused —
  `PROVIDER_CAPABILITY_CLASS_INSUFFICIENT`;
* the gate itself refuses to mint a paid ticket through the network route;
* a Meshy ticket cannot authorize Uthana, and a `poll` ticket cannot authorize
  `cancel` — `PROVIDER_CAPABILITY_SCOPE_MISMATCH`;
* endpoint binding is exact: port `8443`, host `api.uthana.com`, base path `/v2`
  and a near-miss host `uthana.co` are all refused against a ticket minted for
  `https://uthana.com`;
* a paid ticket refuses reuse after `reserve()` + `consume()` —
  `PROVIDER_CAPABILITY_ALREADY_CONSUMED`;
* `OperationClass.OFFLINE` can never hold a ticket, and only `https` can mint one;
* eight threads released from a barrier against one paid ticket, 60 trials:
  **maximum one winner in every trial**.

The transport does more than look for a marker: it verifies the token, the class,
the provider/operation pair, single-use state, that an *authenticated* request is
on the ticket's approved origin, and that the URL is `https`. Unauthenticated
artifact fetches are deliberately allowed to leave the API origin — a signed CDN
download carries no credential — which is the documented and correct split.

**What a hostile local Python process can still do.** Everything. It can import
`_MINT_TOKEN`, monkeypatch `verify`, read the same environment variable the
legitimate path reads, and call `urllib` itself. `dataclasses.replace()` on a
minted ticket also preserves the token, so a read ticket can be copied into a
paid-classed one that passes `authorizes()` (MEDIUM 4). None of that is reachable
from any repository-owned call path, and the ledger claim rather than the ticket
is what bounds spending. The boundary this design is for — an alternative,
incomplete or newly written repository path reaching a provider with less policy
than the documented one — is complete.

---

## 5. Command-risk completeness

Subcommand names were read out of the parser (`build_parser()._actions`, all
`choices` dictionaries) and compared against `COMMAND_RISK` without consulting
the implementation report. **Sixteen commands, sixteen classifications, no
stale entries, no duplicates**:

| Class | Commands |
| --- | --- |
| `OFFLINE` | `provider-plan`, `shield-plan`, `status`, `inspect`, `list`, `validate-shield`, `humanoid-gate`, `ingest-rig` |
| `NETWORK_READ` | `auth-smoke`, `poll`, `resume`, `download` |
| `REMOTE_MUTATION` | `cancel` |
| `PAID_CREATE` | `autorig`, `shield-multiview`, `shield-3d` |

* All eight `OFFLINE` commands were run with `--live` **and** the machine opt-in
  set, against an outbound counter: **0 requests** from each.
* All four network/mutation commands were run with no flags and with `--live`
  alone: **0 requests and 0 credential reads** in all eight combinations, with
  the expected `LIVE_PROVIDER_MODE_REQUIRED` / `PAID_PROVIDER_OPT_IN_REQUIRED`.
* An unregistered command name raises `UnclassifiedCommand`, so the default for a
  new command is refusal rather than silence.
* No handler reads `args.live`: the only reference in `cli.py` is the central
  `getattr(args, "live", False)` inside `authorization_for`.

---

## 6. Paid convergence, claim and UNKNOWN

* `execute_paid_submission(` appears exactly **once** in `cli.py`, and each of
  `cmd_autorig`, `cmd_shield_multiview`, `cmd_shield_3d` reaches it through
  `run_paid_command`. `mint_paid_capability` is called from exactly one module
  outside `live_gate.py`: `paid_executor.py`.
* **Two real processes, one approved plan**: two `python` subprocesses were
  released simultaneously against a shared artifact root through the real
  executor, each logging every outbound attempt with `fsync`. The log contains
  **exactly one create**; the loser refused with
  `PROVIDER_SUBMISSION_ALREADY_RECORDED`.
* Replay was attempted against a claim in `CLAIMED`, `CREATE_IN_FLIGHT`,
  `CREATED`, `OUTCOME_UNKNOWN` and `COMPLETED`. All five refuse with **0
  outbound**; `OUTCOME_UNKNOWN` gets its own code, which is right because its
  remedy is a human looking at the provider's task list.
* A corrupt claim reads back as `{"unreadable": true}` rather than as absent.
* A permission failure on the ledger directory and an `ENOSPC` during the claim
  write both raise `LedgerUnavailable` **before** anything outbound, and the
  half-written claim is removed rather than left to look valid.
* `NO_RETRY.max_attempts == 1`, and the sabotage matrix confirms four independent
  tests fail the moment a create becomes retryable.
* Durable ordering, measured by journalling the store calls around one successful
  create: `claim CLAIMED` → `update CREATE_IN_FLIGHT` → `manifest CREATED` →
  **outbound create** → `update CREATED` with the task id, then `find_resumable`
  returns that job. `claim_submission` uses `O_CREAT|O_EXCL` + `fsync`;
  `update_submission` writes a temporary file, `fsync`s it and `os.replace`s it,
  verified through the `os.replace` spy.

Remote exactly-once is **not** claimed anywhere, and the documentation states the
residual correctly: without provider idempotency or lookup by client submission
id, a failure after remote acceptance but before the task id arrives is locally
indistinguishable from a request that never landed, so the safe answer is a
permanent `UNKNOWN` rather than a retry.

---

## 7. Endpoint, redirect and proxy

Identity comparisons, all measured: `:443` collapses with the default,
case-folds, tolerates a trailing slash, and treats a trailing-dot host, a
non-default port, a different subdomain, a different base path and a different
provider as different destinations. IPv6 literals compare case-insensitively and
distinguish different addresses.

* Only `https` can mint; `http://`, `ftp://` and an empty base URL are refused at
  parse time.
* Every redirect is refused, same-origin included, so no 3xx can move an approved
  request anywhere.
* An authenticated request aimed off the approved origin is refused at the
  transport — `PROVIDER_CAPABILITY_SCOPE_MISMATCH`.
* `HTTP_PROXY`, `HTTPS_PROXY`, `ALL_PROXY` and the lowercase forms were each set
  to `http://127.0.0.1:8888`. `urllib.request.getproxies()` sees them, which is
  what makes the check meaningful; the transport's opener carries a `ProxyHandler`
  with `proxies == {}` and no other handler holds a proxy, so a loopback proxy —
  the one shape a non-loopback tripwire would not catch — cannot be used at all.
* The endpoint is inside the digest payload, so changing the base URL changes the
  digest; and at submission the recomputed endpoint must equal the approved one.

---

## 8. Artifact path confinement

Fifteen hostile provider-controlled names were pushed through the write path
inside temporary directories: `C:/Windows/Temp/...`, `C:\Windows\Temp\...`, a UNC
path, `/etc/passwd`, `/tmp/...`, `../`, `..\`, mixed separators, an NTFS
alternate data stream (`x.glb:stream`), reserved device names (`CON`, `NUL`,
`PRN.glb`, `COM1.glb`, `LPT9`, `aux.txt`), a BOM-prefixed traversal, a NUL byte,
one-dot-leader and full-width Unicode traversals. Every one raised
`PROVIDER_OUTPUT_PATH_UNSAFE`, and the `os.open`/`os.replace` spy recorded **no
target outside the trusted root** in any case.

Percent-encoded traversals (`%2e%2e`, `%2e%2e%2fescape.glb`, `..%2f..%2fx.glb`)
are treated as literal filenames rather than decoded — the safe outcome — and the
recorded write target stayed inside the root.

A reparse point was tested for real: a directory junction on Windows (no
elevation needed) pointing out of the root makes `resolve_within` refuse, because
containment is decided after resolution rather than by string prefix.

Trusted naming cannot itself be steered: `trusted_artifact_name` was fed
`run_id="../../escape"`, `kind="../rigged"`, `extension="../glb"`, `"CON"`,
`".."`, `""`, a 500-character run id, `"x:y"` and Unicode leaders, and every
result was a single safe component with the fixed extension and no reserved
device name.

---

## 9. Secret boundary

With a synthetic key, each of these forms is removed by `scrub` and `scrub_obj`,
including inside nested containers: the raw key, `base64(key + ":")`,
`base64(key)`, both padded and unpadded, and the percent-encoded form. A
`ProviderError` chained from an inner exception carrying the key serialises
clean. A `Credential` never prints its value in `repr`, `str`, f-strings or
`format`. A deliberately short key (`abcd`) is still masked, so a mistyped key
cannot slip through the length floor.

Environment access is observed on `os.environ` itself, not on `load_credential`:
constructing both adapters reads **nothing**, and offline plan building reads
**nothing** while still naming `UTHANA_API_KEY` in the plan. The sabotage that
adds a direct `os.environ.get` to adapter construction turns two tests red, so
the property is enforced rather than asserted.

The one exception is measured and recorded as LOW 1: a refused
`shield-multiview`/`shield-3d --submit` performs a single presence probe on
`MESHY_API_KEY` while building the plan's `credential_present` field.

---

## 10. Multipart-oracle independence

`tools/assetgen/tests/multipart_oracle.py` imports nothing from `providers`, does
not reference `_build_multipart` or `CREATE_CHARACTER_MUTATION`, and types out
`"operations"` and `"map"` itself. It parses the declared boundary, requires the
leading and closing delimiters, requires a blank line between headers and data,
requires `Content-Disposition: form-data`, and validates that the map points at a
part that exists and at a variable path that is `null` in the operations
document.

Independently exercised against 15 malformed uploads: non-multipart content type,
a body without a boundary parameter, a truncated body, a prefixed body, a body
containing every required *word* but no structure, invalid JSON in either part,
a map pointing at a missing part, a map pointing at a non-existent variable, an
empty path list, an empty map, a non-null variable, a missing `query`, missing
`variables`, a file part without a filename, and both field renames. All refused,
each naming the offending part.

Both former sabotages were re-introduced in memory against the production
encoder: `operations → ops` and `map → m` each turn **19 tests** red.

---

## 11. Sabotage matrix

Fourteen defects, injected one at a time into the production modules before the
repository's own 241 tests ran. Every one was detected:

| Sabotage | Tests failed | Representative failure |
| --- | --- | --- |
| opt-in removed | 11 | `test_live_without_the_machine_opt_in_refuses_before_reading_a_credential` |
| create retries re-enabled | 4 | `test_a_5xx_on_a_paid_create_is_never_retried_into_a_second_task` |
| adapter capability check bypassed | 5 | `test_a_direct_provider_submit_without_a_capability_refuses` |
| transport capability check bypassed | 3 | `test_the_production_transport_refuses_an_unauthorized_request` |
| endpoint dropped from digest | 1 | `test_changing_the_provider_base_url_changes_the_plan_digest` |
| claim no longer `O_EXCL` | 1 | `test_the_same_plan_cannot_be_claimed_twice` |
| UNKNOWN replay allowed | 1 | `test_an_unknown_outcome_refuses_a_second_create_for_the_same_identity` |
| adapter re-derives its filename from the URL | 9 | `test_an_adapter_writes_only_where_the_orchestrator_told_it_to` |
| path validation removed | 14 | `test_a_provider_controlled_name_can_never_become_a_path` |
| leaky request `repr` restored | 1 | `test_a_request_repr_never_exposes_an_authorization_header` |
| eager `os.environ` credential read | 2 | `test_every_refused_live_permutation_leaves_the_credential_unread` |
| derived secret forms not registered | 1 | `test_a_percent_encoded_credential_is_scrubbed` |
| multipart `operations → ops` | 19 | `test_exactly_one_create_happens_for_one_approved_plan` |
| multipart `map → m` | 19 | `test_exactly_one_create_happens_for_one_approved_plan` |

Three of the fourteen are detected by a single test each (endpoint-in-digest,
`O_EXCL`, UNKNOWN replay). That is thin coverage rather than absent coverage, and
those three tests were read to confirm they assert the property directly instead
of a side effect. Noted as LOW 3.

Production provider code launches no process: `subprocess` does not appear in
`providers/uthana.py`, `providers/meshy.py`, `transport.py`, `orchestrator.py`,
`paid_executor.py` or `capability.py`. The only spawns in the tree are the local
Godot binary from `rig_ingest.py` and `hand_fixture_ingest.py`, which do local
asset work and are unreachable from an adapter.

---

## 12. Candidate and readiness status (read-only)

* `game/assets/prototype/3d/units/warrior/warrior_3d.glb`: 10,199,504 bytes,
  **30,126 triangles**, `skins` and `animations` both present — already rigged
  and animated, therefore not valid auto-rig input.
* The humanoid gate refuses it on `no_existing_rig` and `no_animation` among
  five blocking checks.
* The plan produced by the real offline command reproduces the documented digest
  exactly: `d9d3bbe17e41c0dfe80fbd89a9d6c1872e90fd83019b678fa524ffd3a80f726e`,
  `executable: false`. Confirming it is refused with
  `PROVIDER_PLAN_NOT_EXECUTABLE`. The v1 digest `57c633…` belongs to the previous
  plan schema and is likewise unauthorizable.
* `cost` is stated as `unknown`, with the note that unknown is not free.
* `artifacts/assetgen/submissions/` and `artifacts/assetgen/jobs/` do not exist:
  nothing has ever been claimed or submitted from this repository.
* The candidate is a possible **morphological calibration probe** only. It is not
  production-batch evidence, and no polygon-budget rule was added here.
* Stage remains **`CALIBRATING`**.

---

## 13. Findings

No BLOCKER. No HIGH.

### MEDIUM 4 — a minted ticket can be copied into a wider one in-process

*Where:* `tools/assetgen/capability.py`, `ProviderCapability`.
*Reproduction:* `dataclasses.replace(read_ticket, operation_class=PAID_CREATE)`
preserves `_token`, and the copy passes `authorizes()` for the paid class.
Separately, `reserve()` performs a check-then-add on two module-level sets with
no lock; the sequence is interruptible in principle, though 60 trials × 8 threads
never produced a second winner.
*Contract:* the ticket is described as immutable authority for one operation.
*Actual risk:* low, and outside the declared threat model. Reaching it requires
code that already runs in-process and could call `urllib` directly; no
repository path constructs or replaces a capability, the paid executor mints one
ticket per submission, and at-most-once rests on the atomic `O_EXCL` claim rather
than on the ticket. `capability.py` already refuses to claim cryptographic
sandboxing.
*Why the tests miss it:* they cover forged and reused tickets, which are the
accidental shapes; a deliberate `replace()` is not an accident.
*Minimum correction (optional hardening, not required for this commit):* bind the
token to the class and scope at mint time — e.g. store a keyed digest of the
scope alongside the token and re-derive it in `authorizes()` — and guard the
reservation sets with a `threading.Lock`.

### LOW 1 — a refused paid shield command performs one credential presence probe

*Where:* `tools/assetgen/cli.py` (`cmd_shield_multiview`, `cmd_shield_3d`) via
`provider.has_credential` → `live_gate.credential_state`.
*Reproduction:* with the environment recorder installed,
`--live shield-multiview --submit` without a confirmed digest records one read of
`MESHY_API_KEY` before the refusal.
*Contract:* "refused before credential access".
*Actual risk:* very low. `credential_state` reads the variable only to decide
`present`/`missing`, keeps no reference, and the boolean is all that reaches the
plan; nothing is logged, written or sent, the outbound count stays 0 and no
ledger entry is created. `auth-smoke` and offline plan building read nothing at
all.
*Why the tests miss it:* the repository's own probes assert zero reads for
`auth-smoke` and for `build_plan`, which are the paths where a value could
plausibly leak; they do not watch the shield commands.
*Minimum correction:* let `shield_plan` take presence from a keys-only check, or
move the presence probe after authorization as `paid_executor` already does.

### LOW 2 — the machine opt-in is whitespace-tolerant

*Where:* `LiveAuthorization.from_environment`, which `.strip()`s the raw value.
*Reproduction:* `EOM_ALLOW_PAID_PROVIDER_CALLS=" 1 "` counts as permission; the
outbound counter then records the request that the barriers now allow.
*Actual risk:* negligible — no value other than `1` modulo surrounding
whitespace grants anything, and `true`, `yes`, `2`, `0`, `false`, `01` and
`1 1` are all refused. It is recorded only because the documentation says
"exact".
*Minimum correction:* compare the raw value, or document the strip.

### LOW 3 — endpoint identity ignores userinfo, and three properties rest on one test each

*Where:* `tools/assetgen/endpoint.py` `parse_endpoint`, plus test coverage depth.
*Reproduction:* `https://user:secret@uthana.com` and `https://uthana.com`
produce the same identity, so adding userinfo to a base URL does not change the
plan digest.
*Actual risk:* low. The dangerous shape is the reverse —
`https://uthana.com@evil.example` — and that resolves to host `evil.example`,
changes the identity and is refused. A userinfo base URL would place the
userinfo in the request URL, where `urllib` treats the whole authority literally
and fails to resolve, so no credential reaches an unapproved host.
Separately, the endpoint-in-digest, `O_EXCL` and UNKNOWN-replay properties are
each caught by exactly one test.
*Minimum correction:* refuse a base URL containing userinfo in `parse_endpoint`,
and add a second, differently-shaped assertion for each of the three
single-test properties.

---

## 14. Verdicts

| Area | Verdict | Basis |
| --- | --- | --- |
| Command-risk completeness | **PASS** | 16/16 from the parser itself, no stale entries, unclassified refuses, no `args.live` in handlers |
| Outbound capability boundary | **PASS** | token, class, scope, endpoint, single use and https all enforced at the transport; forged and reused tickets refused |
| Paid-command convergence | **PASS** | one `execute_paid_submission` call site; all three commands reach it; one paid minter |
| Direct-call bypass resistance | **PASS** | orchestrator, adapter and transport each refuse with 0 outbound and 0 credential reads |
| Plan/endpoint binding | **PASS** | endpoint inside the digest, recomputed and compared at submission; base-URL change invalidates the approval (LOW 3 userinfo note) |
| Universal at-most-once claim | **PASS** | two real processes, exactly one create; `O_EXCL` + fsync; failure to record refuses before spending |
| UNKNOWN replay safety | **PASS** | all five recorded states non-replayable; UNKNOWN keeps its own code; zero additional creates |
| Crash durability | **PASS** | claim before request, task id before polling, atomic replace verified on the syscall; Windows directory-fsync limitation documented, not claimed |
| Artifact path confinement | **PASS** | 15 hostile names refused, junction escape refused, real open/replace targets inside the root, trusted naming unsteerable |
| Secret non-disclosure | **PASS** | raw, base64 (both forms, padded and unpadded), percent-encoded, headers, `repr`/`str`, nested exceptions all clean (LOW 1 presence probe) |
| Multipart-oracle independence | **PASS** | no shared code or constants; structural parsing; 15 malformed uploads refused; both renames turn 19 tests red |
| Network isolation | **PASS** | 0 non-loopback attempts across 158 probes and the 241 repository tests; environment proxies unusable; no networking subprocess |
| Test independence | **PASS** | 14/14 sabotages detected (LOW 3 notes three single-test properties) |
| First live-smoke readiness | **UNPROVEN** | intended: no static unrigged candidate exists; both known digests are `executable: false` |
| Paid-batch readiness | **UNPROVEN** | intended: never claimed; no production-representative candidate and no polygon-budget contract |

The two `UNPROVEN` verdicts are the expected state of a `CALIBRATING` stage, not
findings, and do not block the commit — the commit establishes the boundary, it
does not authorize a call.

---

## 15. Commit decision

No BLOCKER and no HIGH, so the provider-readiness unit was committed after the
five checks were re-run and the worktree was confirmed to contain only the
intended files. All verification probes, sabotage plugins, worker scripts, logs
and the temporary pristine worktree used for this pass live outside the
repository and were removed; the Godot `user://` files moved aside for the a2
determinism experiment were restored.

Re-run after cleanup, provider and proxy variables cleared:

| Check | Result |
| --- | --- |
| `slice a1` | 71 checks, OK |
| `slice a2` | 222 + 68 + 141 + 90 + 73 + 82 + 279 + 292 + 797 = 2044 checks across 9 tests, OK |
| `slice c1` | 22 checks, OK |
| `pytest tools/assetgen/tests -q` | 241 passed |
| `scripts/scan-secrets.py` | 32 files scanned, no secret-shaped content |

`scripts/scan-secrets.py` scans pending work — unstaged, staged and untracked
files — so the count moved from 31 to 32 when this review joined that set, and to
0 once everything was committed and the tree was clean. Both runs are clean, and
the second is a weaker statement than the first, which is why the pre-commit
figure is the one that matters. `pytest` was re-run after the commit: 241 passed.
`artifacts/assetgen/` holds only pre-existing rig-ingest and shield output, all
git-ignored; no plan, ledger or credential file remains anywhere in the tree.

The commit is `Establish fail-closed provider execution boundary`: 32 files,
+7918 / −145, the sole child of `5baebd2`, not pushed. Its hash is quoted in the
task report rather than here, because a document cannot contain the hash of the
commit that carries it.

The commit authorizes nothing. The next slice must prepare a static, unrigged
candidate and generate a new, non-executed plan; a first paid smoke stays closed
until that plan is read and its digest is confirmed by hand.
