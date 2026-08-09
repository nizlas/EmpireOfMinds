# Empire of Minds — Test profiles (T1) and validation policy (T2)

The project has a large server (pytest) and Godot headless regression suite. **Profiles** run a subset during day-to-day work. **`full`** is unchanged and still runs every test when explicitly requested; it is **not** the default for small focused slices.

No profile deletes or weakens tests. Failures are not suppressed.

## Validation policy (T2) — default for agents and implementation prompts

**During implementation:** run **only** the profile that matches the slice you are changing.

```text
.\scripts\run-godot-tests.ps1 slice c14c
.\scripts\run-godot-tests.ps1 slice c14d
.\scripts\run-godot-tests.ps1 slice c14d-dev
.\scripts\run-server-tests.ps1 slice c14b
```

**Final report on a small/local slice:** run the **slice** profile again; add **smoke** only when shared boot/session/helper code was touched. **Do not** run **cloud**, **presentation**, or **full** unless the user explicitly asks or you are doing a release/deploy checkpoint (see below).

**Future Composer/Cursor prompts** should state the intended validation level, for example:

```text
Validation:
- During implementation, run only the slice profile.
- For final report, run slice and optionally smoke.
- Do not run full/cloud/presentation unless explicitly requested.
```

### Agent final-report checklist

Report:

1. **Focused tests run** (commands + pass/fail).
2. **Broader tests intentionally skipped** (e.g. cloud, full, presentation).
3. **Why** broader tests were skipped (slice-local change; user did not request full regression).
4. Whether **full** validation is **recommended** before commit/deploy for this change.

### When to use each profile

| Profile | Use when |
|--------|----------|
| **slice \<id\>** | **Default** while implementing and reporting on a focused slice (e.g. **c14c**, **c14b**, **c14d**) |
| **smoke** | Small change touches **shared** setup/boot/session/helper code; quick sanity without full regression |
| **cloud** | Broad cloud client/server change; shared **CloudSession** / **CloudClient** behavior across flows; cloud deploy prep; **user explicitly requests** broader cloud validation |
| **presentation** | Broad map/presentation/rendering changes; UI rendering outside a narrow menu slice; **user explicitly requests** presentation validation |
| **full** | **User explicitly requests**; final commit/deploy for a **large** slice; after a **large refactor**; suspected **cross-cutting** regression; release-like checkpoint |

### Slice-specific defaults (small changes)

**Godot front door / menu / labels / credential-store UX (e.g. C14c):**

- Normally: `.\scripts\run-godot-tests.ps1 slice c14c
.\scripts\run-godot-tests.ps1 slice c14d
.\scripts\run-godot-tests.ps1 slice c14d-dev`
- If **BootIntent** or **main.gd** boot flow changed: also `.\scripts\run-godot-tests.ps1 smoke`
- **Do not** run **full**, **cloud**, or **presentation** unless explicitly requested.

**Small server endpoint/model slice (e.g. C14b, C14d-1):**

- Normally: `.\scripts\run-server-tests.ps1 slice <slice_id>` (e.g. **`c14d`** for staging faction/ready)
- If shared match/action plumbing changed: also `.\scripts\run-server-tests.ps1 smoke`
- **Do not** run **full** or broad Godot **cloud** unless explicitly requested or preparing deploy.

**Docs-only / decision checkpoint slice (e.g. C14d-0, C14d-final):**

- **No** runtime suites — the diff touches only `docs/`.
- If a docs-only task implies code changes, **stop and report** instead of writing code.
- **C14d-final (cloud-alpha external checkpoint):** documents the passed external two-player test, zip + `.bat` distribution, Smart App Control tester notes, and manual checklist in **`docs/VALIDATION_CHECKLIST.md`** / **`docs/CLOUD_ALPHA_RELEASE.md`**. Agents: final report must state **tests not run** (T2 docs-only).

### What not to do

- Do not run **cloud** or **full** “because the task mentioned cloud” when the diff is a narrow UI/credential/menu slice.
- Do not treat **full** as the default final step for every implementation report.
- Do not suppress failing tests or runner output to hide noise (see [Known noisy output](#known-noisy-output-not-hidden)).

## Server

From the **repository root** (requires `pytest` on PATH; install deps under `server/` first).

```powershell
.\scripts\run-server-tests.ps1              # full (pytest -q in server/)
.\scripts\run-server-tests.ps1 full
.\scripts\run-server-tests.ps1 smoke
.\scripts\run-server-tests.ps1 cloud
.\scripts\run-server-tests.ps1 slice c13a
.\scripts\run-server-tests.ps1 slice c14b
.\scripts\run-server-tests.ps1 slice c14d
.\scripts\run-server-tests.ps1 slice n5
.\scripts\run-server-tests.ps1 slice n6
.\scripts\run-server-tests.ps1 slice n7
.\scripts\run-server-tests.ps1 slice n8a
.\scripts\run-server-tests.ps1 slice n8b
.\scripts\run-server-tests.ps1 slice n8c
.\scripts\run-server-tests.ps1 presentation   # prints Godot-only notice, exit 0
```

Equivalent manual full run: `cd server` then `pytest -q`.

### What each profile runs

- **full** — all tests under `server/tests/`.
- **smoke** — `test_end_turn_flow.py` (health, create match, end turn), `test_legal_actions_endpoint.py`.
- **cloud** — API/action flows: create match, move, end turn, found city, production, attack, combat rules, legal-actions, production/food/science ticks, snapshot v2, player visibility, seats / seat-token flow.
- **slice c13a** — `test_seats.py`, `test_seat_token_flow.py`.
- **slice c14b** — `test_lobby_list.py`, `test_seat_claim.py`, `test_seats.py`, `test_display_name.py`.
- **slice c14d** (server) — `test_faction_display_names_c14d4e.py`, `test_player_factions_c14d4g.py`, `test_faction_select.py`, `test_seat_ready.py`, `test_auto_start.py`, `test_action_status_gate.py`, `test_seat_claim.py`, `test_seats.py`, `test_lobby_list.py`.
- **slice c14d** (Godot) — `test_cloud_staging_c14d.gd`, `test_cloud_staging_faction_ui.gd`, `test_cloud_staging_background_c14d.gd`, `test_cloud_staging_civ_terminology_c14d4e.gd`, `test_cloud_turn_panel_c14d4f.gd`, `test_cloud_player_identity_c14d4g.gd`, `test_cloud_reconnect_parity_c14d.gd`, `test_cloud_lobby_poll_c14d4a.gd`, `test_cloud_turn_ownership_c14d4b.gd`, `test_cloud_turn_ownership_c14d4c.gd`, `test_cloud_turn_banner.gd`, `test_cloud_credential_store.gd`, `test_cloud_front_door_boot_intent.gd`, `test_cloud_lobby_parsers.gd`.
- **slice c14d-dev** (Godot) — `test_cloud_credential_profile.gd` (**`EOM_CLOUD_PROFILE`** credential store paths; dev/test only).
- **slice n5** (server) — `test_world_map_loader.py`, `test_map_content_packaging.py` (server `WorldMap` foundation + canonical content packaging; related non-server checks: `python -m pytest tools/content/tests -q`, `python tools/content/sync_map_content.py check`, and the Godot parity test `test_world_map_foundation.gd`).
- **slice n6** (server) — `test_world_map_match_v3.py`, `test_world_map_loader.py`, `test_lobby_list.py`, `test_action_status_gate.py` (snapshot v3 `world_map` match kind: identity parity, create branching, world-only meta/lobby fields, staging reuse, legacy-untouched regressions; the interim gameplay 409 guards were removed in N7a/N7b).
- **slice n8a** (server) — `test_world_found_city_v3.py`, `test_world_legal_actions_v3.py`, `test_world_map_match_v3.py` (N8a world `found_city`: additive snapshot `cities`/`next_city_id`, successful founding with deterministic Capital/Settlement-N ids and names, atomic Settler consumption, locked rejection order and no-write rejects, duplicate/stale consume → `unknown_unit`, cities do not block movement, map-drift HTTP 500 without mutation, legal-actions found_city rows + city_summaries after founding, deterministic replay/matched-state).
- **slice n8b** (server) — `test_world_set_city_production_v3.py`, `test_world_found_city_v3.py`, `test_world_legal_actions_v3.py`, `test_world_map_actions_v3.py` (N8b world `set_city_production`: flat production constant 1, additive `current_project`, set/switch/clear with registry costs 2/2, locked rejection order, no unlock gating, atomicity, legal-actions production rows + city_summaries, map-drift HTTP 500, plus N8a founding regressions and emptied LEGACY_ONLY list).
- **slice n8c** (server) — `test_world_production_v3.py`, `test_city_rules_canonical.py`, `test_world_set_city_production_v3.py`, `test_world_map_actions_v3.py` (N8c authoritative production + deterministic spawn: flat accrual / completed-project stop, delivery only when owner becomes current, deferred retention + retry, city-tile and smooth-neighbor placement with occupancy updates, successful-only `next_unit_id` sequencing, Warrior/Settler snapshot fields, locked `production_progress*` → `end_turn` → `unit_produced*` event order with primary POST index on `end_turn`, content-drift HTTP 500 with no mutation, two-seat produce→spawn→act round; plus N8R canonical guards and N8b selection regressions).
- **slice n7** (server) — `test_world_map_actions_v3.py`, `test_world_combat_v3.py`, `test_world_legal_actions_v3.py`, `test_world_map_match_v3.py` (N7a world units + actions; N7g.1 World Combat 0.1 server authority — `test_world_combat_v3.py`: registry-derived `current_hp`/`has_attacked` snapshot fields with the additive-only shape pin, the complete locked `attack_unit` rejection order with exact-integer semantics, smooth-edge acceptance plus missing-edge/cliff fail-closed rejections through the shared movement edge source, exact shared-core Local Combat 0.1 math parity incl. clamps, retaliation/defender-elimination/attacker-elimination with deterministic unit ordering, the `has_attacked` turn gate (no second attack, `unit_already_attacked` move rejection, free pre-attack movement, End Turn reset), revision/persistence/event/state-hash/readback and no-write-on-rejection invariants, map drift HTTP 500 without mutation, and unchanged legacy v2 behavior; N7g.2 served attack legality — `test_world_legal_actions_v3.py`: smooth-edge adjacent enemy warriors advertised in the exact submit-ready wire shape with all attack rows BEFORE all move rows, multiple targets in canonical `DIRECTIONS` order, friendly/settler/non-adjacent/cliff/missing-edge targets excluded, attacked units advertising zero attacks and zero moves with the End Turn re-arm, summary counts equal to the selected-unit rows (attacks + moves), every advertised attack accepted by the N7g.1 POST path on an equivalent isolated match, and success/rejection strictly read-only with attack rows present: pinned spawn table and content cross-check, two-distinct-integer-player creation contract incl. duplicate/boolean rejection, snapshot-v3 `units`, locked world POST gate order, every literal move/end-turn rejection incl. real cliff edge, occupancy and exact-integer `schema_version`/`actor_id`/`unit_id` semantics, multi-step movement, end-turn handoff, fail-closed map-identity 500 with no mutation for both tampered snapshot identity and real byte-drifted content behind `EMPIRE_MAP_CONTENT_DIR`, legacy-untouched regressions. N7b world legal-actions: final 409 removal, host/seat/missing/invalid/wrong-seat credential gate, out-of-turn empty envelope, deterministic summaries and DIRECTIONS-ordered move rows pinned against canonical content, all selection errors, cliff/occupied exclusion, drift 500 read-only, a round trip proving every advertised action is accepted by the N7a POST path on an isolated equivalent match, and fail-closed missing-meta credentials on both world gameplay endpoints — 403 for GET, HTTP-200 rejection for POST, with snapshot/hash/events proven unchanged).

Unknown slice ids print supported ids and exit non-zero.

## Godot

From the **repository root** (requires Godot console build; see script header for `GODOT_EXE` / PATH).

```powershell
.\scripts\run-godot-tests.ps1              # full (175 tests, same order as before T1 + C14a/C14c)
.\scripts\run-godot-tests.ps1 full
.\scripts\run-godot-tests.ps1 smoke
.\scripts\run-godot-tests.ps1 cloud
.\scripts\run-godot-tests.ps1 presentation
.\scripts\run-godot-tests.ps1 slice c13a
.\scripts\run-godot-tests.ps1 slice c14a
.\scripts\run-godot-tests.ps1 slice c14c
.\scripts\run-godot-tests.ps1 slice c14d
.\scripts\run-godot-tests.ps1 slice c14d-dev
.\scripts\run-godot-tests.ps1 slice n6
.\scripts\run-godot-tests.ps1 slice n7
.\scripts\run-godot-tests.ps1 slice n7d
.\scripts\run-godot-tests.ps1 slice n7f
.\scripts\run-godot-tests.ps1 slice n7f1
.\scripts\run-godot-tests.ps1 slice n7g3
.\scripts\run-godot-tests.ps1 slice n8a
.\scripts\run-godot-tests.ps1 slice n8b
```

### What each profile runs

- **full** — entire ordered list in `scripts/run-godot-tests.ps1` (domain, presentation, AI, cloud).
- **smoke** — `test_cloud_client_payloads.gd`, `test_main_default_cloud_base_url.gd`, `test_main_tscn_map_layer_sibling_order.gd`.
- **cloud** — all `res://cloud/tests/*.gd` entries in the full list (currently 13 files).
- **presentation** — all `res://presentation/tests/*.gd` entries in the full list.
- **slice c13a** — `test_cloud_seat_token.gd`.
- **slice c14a** — `test_cloud_credential_store.gd`.
- **slice c14c** — `test_cloud_lobby_parsers.gd`, `test_cloud_front_door_boot_intent.gd`, `test_main_cloud_boot_intent_reconnect.gd`, `test_cloud_match_labels.gd`, `test_cloud_display_name.gd`.
- **slice c14d** (Godot) — `test_cloud_staging_c14d.gd`, `test_cloud_staging_faction_ui.gd`, `test_cloud_staging_background_c14d.gd`, `test_cloud_staging_civ_terminology_c14d4e.gd`, `test_cloud_turn_panel_c14d4f.gd`, `test_cloud_player_identity_c14d4g.gd`, `test_cloud_reconnect_parity_c14d.gd`, `test_cloud_lobby_poll_c14d4a.gd`, `test_cloud_turn_ownership_c14d4b.gd`, `test_cloud_turn_ownership_c14d4c.gd`, `test_cloud_turn_banner.gd`, `test_cloud_credential_store.gd`, `test_cloud_front_door_boot_intent.gd`, `test_cloud_lobby_parsers.gd`.
- **slice c14d-dev** (Godot) — `test_cloud_credential_profile.gd` (**`EOM_CLOUD_PROFILE`** credential store paths; dev/test only).
- **slice n6** (Godot) — `test_map_content_loader_by_id.gd`, `test_world_snapshot_bootstrap.gd`, `test_cloud_match_kind_routing.gd`, `test_cloud_world_play_smoke.gd`, `test_cloud_client_payloads.gd`, `test_cloud_front_door_boot_intent.gd` (manifest lookup by `map_id`, snapshot v3 parse + identity verification with explicit mismatch failure, `match_kind` preservation across all five client transitions, `cloud_world_play` smoke, legacy create-body/boot-intent regressions).
- **slice n7d** (Godot) — `test_world_interaction_state.gd`, `test_world_destination_markers.gd`, `test_cloud_world_play_interaction.gd`, `test_cloud_one_pc_debug.gd` (N7d client world interaction loop + one-PC debug mode, fast — no terrain build: debug activation guards — explicit `EOM_CLOUD_ONE_PC_DEBUG=1` only, world_map + loopback only, `EOM_CLOUD_DEBUG` logging-only, host-token authority only inside the mode; the fresh-create → normal-staging-APIs → ongoing sequence with deterministic first-two-distinct civ assignment and per-seat tokens; the same-client Player 0 → Player 1 → Player 0 controllability handoff with actor rebinding invalidating selection + both served slots and previous-actor responses; fixed-seat behavior proven unchanged when the mode is off; pick/selection semantics incl. cliff-unchanged/miss-clear and **full out-of-turn pick inertness incl. empty misses**; exact served-row destination/marker/payload mapping; the locked served-legality freshness contract — **independent summary/selection served slots** usable together in either arrival order, accepting one never clearing the other, newer snapshots clearing both, selection changes retaining the fresh same-revision summary row, End Turn re-enabled from a newly served summary row after an accepted move with the unit still selected, serial/revision/**actor**/**requested-mode** binding with the echoed `selected_unit_id` verified, mismatched/stale-response discard, no submission across revisions — End Turn gating, waiting-poll gates, End Turn UI wiring, and the visible mid-match map-identity drift failure).
- **slice n7** (Godot) — `test_world_units_view.gd`, `test_world_units_locomotion.gd`, `test_cloud_world_play_smoke.gd`, `test_world_units_combat.gd`, plus the four `n7d` tests above (N7c unit projection: stable per-unit-id roots placed exactly at the supplied tile anchors, exact instance count/ids, `ModelRoot` scale 0.5 with the audited idle clips, no duplicates on reapplied snapshots, both snapshot/anchor arrival orders, no origin fallback for missing anchors; the locked matte unit-render profile — per-instance duplicated materials with metallic 0.0 / roughness 0.85 / specular 0.3, preserved albedo textures, linear+mipmap filtering, untouched imported materials, `mipmaps/generate=true` albedo imports; plus the production `cloud_world_play` integration — live-snapshot units at `TerrainWorld.tile_anchors`, idempotent re-render, the N7f top-surface sampler injection, every production unit binding its N7f leg grounder, and the MSAA 2×/FXAA world-viewport AA profile).
- **slice n7f1** (Godot) — `test_world_interaction_state.gd`, `test_cloud_world_play_interaction.gd`, `test_world_units_arrival_event.gd` (N7f.1 deterministic client arrival gate, fast — no terrain build: gate entry only on an accepted `move_unit` with a usable snapshot, bound to the moved unit + accepted revision; every pick kind and End Turn inert while gated; destination rows hidden/unsubmittable and no summary/selection legality fetched during locomotion; the moved-unit selection preserved; release only by the gated unit's REAL visual arrival with exactly one summary + selected-unit refetch; wrong/stale arrivals inert; rejection/transport-failure/accepted-without-snapshot/non-move actions never gating; gated-unit removal, turn loss, and different-revision snapshots resolving without deadlock; the `WorldUnitsView.unit_arrived` event firing exactly once per completed glide at the exact final-anchor pose — never for spawn, idle, identical reapply, degenerate settlement, or mid-glide removal, once per retargeted glide at final settlement; and production-scene wiring proving rapid repeated clicks cannot produce a second POST).
- **slice n7f** (Godot) — `test_world_units_locomotion.gd` (N7f presentation-only unit locomotion, fast — no terrain build: deterministic yaw-only orientation math — orthonormal, upright +Y, −Z along the horizontal movement direction, identity fallback, vertical components never tilt; the EFFECTIVE rendered forward — toe-vs-ankle rest direction through the whole live transform chain — follows the movement for several directions and both rigs (moonwalk regression) and world −Z at spawn; immediate authoritative root snap with the visual gliding at `LOCOMOTION_SPEED_UNITS_PER_SEC`; semantic Walking while moving and Idle_3 on arrival through the audited per-type remap; glide height on a synthetic top-surface sampler whose mid-segment hump proves sampling (anchor-lerp fallback without a sampler); skeletal grounding (`WorldUnitLegGrounder`, incl. the 2026-08-07 uphill correction): rig binding for settler AND warrior, flat-ground no-op, sampler-miss inertness, independent per-foot terrain targets with the joint two-leg pelvis solve (baseline = lower target, reach-feasibility intervals, midpoint on conflict, absolute bound), preserved leg bone lengths, extension margins with finite poses on extreme targets, static joint-pelvis/reach-margin/pole-knee/sole-alignment/contact/swing-clearance math, both-rig REAL-clip sequences across flat/shallow/medium/steep/downhill (stable pole-signed knee side across frames — the regression that fails against the old current-bend-side rule — bounded knee angular continuity, upright root, exact absolute stance sole alignment with heading preserved and per-foot independent normals, gradual frame-rate-independent foot blending, flat/downhill zero swing clearance with positive uphill clearance), and engine `SkeletonModifier3D` invocation; the 2026-08-07 third-review follow-up on both rigs — the raw remapped idle clips provably hover and drift the feet (defect-existence checks), the POST-ALIGNMENT sole-plane contact invariants verified as FINAL GEOMETRY on flat, moderate, steep-uphill, steep-downhill, lateral, and mixed-XZ planes for planted feet: ankle distance dot(n, ankle − s) = d (d = the rig-derived rest ankle-to-sole-plane distance; fails the earlier vertical terrain + d target), the ACTUAL post-solver transformed sole normal equal to each foot's effective contact normal (equal to n itself on the always-in-clamp planes; fails the earlier delta model, which transplanted the ~0.10–0.21 rad clip-authored foot tilt onto every plane), and the rig-derived transformed sole-plane point lying ON the sampled plane (rejects gap AND penetration); exact effective-contact-normal reconstruction (in-clamp mixed-XZ normals returned unchanged, extreme slopes clamped) and tilted-pose correction statics; stance/flat final sole normals equal to the terrain normal/UP exactly with heading preserved; plus the walking-stance contact blend toward the corrected height on a steep slope, planted feet fixed in position AND orientation across idle poses while pelvis motion passes through, the view's locomotion gate releasing plants on glide begin and replanting on arrival, walking-stance height following the exact contact-weighted sole calibration, and gradual convergent timed replant blending (no snap); spawn snap, idempotent reapply preserving glide progress and never restarting clips, continuous mid-glide retarget without duplicates, clean mid-glide removal, and the EXACT final-anchor pose with facing retained; plus the production-path stride/slip regression — full Walking glides on both rigs with AnimationPlayers advanced in lockstep and the grounder applied per frame, asserting the FINAL post-transform planted-sole horizontal drift stays near zero AND signed per-stance displacement is centered (no one-way backward slide) at the stride-synchronized 0.445 translation scale).
- **slice n8a** (Godot) — `test_world_cities_view.gd`, `test_world_found_city_interaction.gd`, `test_world_interaction_state.gd` (N8a world cities + founding client, fast — no terrain build: stable per-city-id roots at supplied anchors with reused `ancient_village`, idempotent reapply/removal/missing-anchor skip; served `found_city` availability and exact-row submission only; authoritative snapshot reconciliation consuming the Settler and clearing its selection safely; shared-tile unit↔city selection cycle; city-only selection + status line; no optimistic city create; plus the existing world interaction-state regression suite).
- **slice n8b** (Godot) — `test_world_city_production_interaction.gd`, `test_world_found_city_interaction.gd`, `test_world_interaction_state.gd` (N8b production selection client, fast — no terrain build: served `set_city_production` rows only, exact payload submission, snapshot progress/cost display, authoritative reconcile without optimistic project changes, stale-row invalidation on revision/selection/actor change; plus founding and interaction-state regressions).
- **slice n7g3** (Godot) — `test_world_units_combat.gd`, `test_world_interaction_state.gd`, `test_world_destination_markers.gd`, `test_cloud_world_play_interaction.gd` (N7g.3 World Combat 0.1 client, fast — no terrain build: `present_combat(event, deferred_snapshot)` — melee approach at standoff 0.80, impact-timed non-fatal hit / fatal `Dead` at 0.5 s, clip blend 0.28, centralized `FACING_BLEND_SEC` 0.28 ordinary facing, combat-support grounding with final sole-to-surface checks + live-advanced strike-trajectory aim cases (the forward-kinematic club-tip endpoint vs the defender's cached `Head` contact — full 3D distance and signed vertical error at impact for above/below/equal supported elevations; the earlier single-frame `LeftHand.y → Spine01.y` reduction metric is rejected and removed; `Hit_Reaction_1` not retargeted; living ModelRoot upright; frozen Walking/Idle/`0.445`/`0.28` locomotion; identical authored `Hit_Reaction_1` both role directions; occupation keeps travel facing; matched lethal vs non-lethal downhill strikes proven trajectory/pitch/target-equivalent through the contact window — the killing swing rides its aim out through the victim's `Dead`), continuous corpse support during `Dead`, return vs capture travel, cancel/supersede cleanup, N7f locomotion/arrival after combat; interaction/markers/production gate wiring).

## Known noisy output (not hidden)

Some Godot cloud negative tests use `::not-a-url::` so HTTP fails immediately; tests **pass** but Godot logs red `ERROR: Error parsing URL` lines. That is intentional test harness noise, not a profile failure.

Image-load `WARNING` lines (e.g. combat burst, territory stump) may appear in presentation tests; they are not suppressed.

Headless runs of tests that free nodes carrying duplicated `StandardMaterial3D` overrides (e.g. `test_world_units_view.gd`) may log engine-internal `ERROR: Parameter "material" is null.` lines from the dummy rendering server; the tests pass and the errors do not occur in real (non-headless) rendering.

## Extending profiles

Add new slice ids to `$Script:SliceTests` / `$Script:SupportedSlices` in the runner scripts. Prefer explicit file lists for **smoke** and **slice**; **cloud** / **presentation** on Godot filter the full list by path prefix so new files under those folders are picked up automatically when added to the full suite.


