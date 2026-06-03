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

**Docs-only / decision checkpoint slice (e.g. C14d-0):**

- **No** runtime suites — the diff touches only `docs/`.
- If a docs-only task implies code changes, **stop and report** instead of writing code.

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
- **slice c14d** (Godot) — `test_cloud_staging_c14d.gd`, `test_cloud_staging_faction_ui.gd`, `test_cloud_staging_civ_terminology_c14d4e.gd`, `test_cloud_turn_panel_c14d4f.gd`, `test_cloud_player_identity_c14d4g.gd`, `test_cloud_lobby_poll_c14d4a.gd`, `test_cloud_turn_ownership_c14d4b.gd`, `test_cloud_turn_ownership_c14d4c.gd`, `test_cloud_turn_banner.gd`, `test_cloud_credential_store.gd`, `test_cloud_front_door_boot_intent.gd`, `test_cloud_lobby_parsers.gd`.
- **slice c14d-dev** (Godot) — `test_cloud_credential_profile.gd` (**`EOM_CLOUD_PROFILE`** credential store paths; dev/test only).

Unknown slice ids print supported ids and exit non-zero.

## Godot

From the **repository root** (requires Godot console build; see script header for `GODOT_EXE` / PATH).

```powershell
.\scripts\run-godot-tests.ps1              # full (146 tests, same order as before T1 + C14a/C14c)
.\scripts\run-godot-tests.ps1 full
.\scripts\run-godot-tests.ps1 smoke
.\scripts\run-godot-tests.ps1 cloud
.\scripts\run-godot-tests.ps1 presentation
.\scripts\run-godot-tests.ps1 slice c13a
.\scripts\run-godot-tests.ps1 slice c14a
.\scripts\run-godot-tests.ps1 slice c14c
.\scripts\run-godot-tests.ps1 slice c14d
.\scripts\run-godot-tests.ps1 slice c14d-dev
```

### What each profile runs

- **full** — entire ordered list in `scripts/run-godot-tests.ps1` (domain, presentation, AI, cloud).
- **smoke** — `test_cloud_client_payloads.gd`, `test_main_default_cloud_base_url.gd`, `test_main_tscn_map_layer_sibling_order.gd`.
- **cloud** — all `res://cloud/tests/*.gd` entries in the full list (currently 13 files).
- **presentation** — all `res://presentation/tests/*.gd` entries in the full list.
- **slice c13a** — `test_cloud_seat_token.gd`.
- **slice c14a** — `test_cloud_credential_store.gd`.
- **slice c14c** — `test_cloud_lobby_parsers.gd`, `test_cloud_front_door_boot_intent.gd`, `test_main_cloud_boot_intent_reconnect.gd`, `test_cloud_match_labels.gd`, `test_cloud_display_name.gd`.
- **slice c14d** (Godot) — `test_cloud_staging_c14d.gd`, `test_cloud_staging_faction_ui.gd`, `test_cloud_staging_civ_terminology_c14d4e.gd`, `test_cloud_turn_panel_c14d4f.gd`, `test_cloud_player_identity_c14d4g.gd`, `test_cloud_lobby_poll_c14d4a.gd`, `test_cloud_turn_ownership_c14d4b.gd`, `test_cloud_turn_ownership_c14d4c.gd`, `test_cloud_turn_banner.gd`, `test_cloud_credential_store.gd`, `test_cloud_front_door_boot_intent.gd`, `test_cloud_lobby_parsers.gd`.
- **slice c14d-dev** (Godot) — `test_cloud_credential_profile.gd` (**`EOM_CLOUD_PROFILE`** credential store paths; dev/test only).

## Known noisy output (not hidden)

Some Godot cloud negative tests use `::not-a-url::` so HTTP fails immediately; tests **pass** but Godot logs red `ERROR: Error parsing URL` lines. That is intentional test harness noise, not a profile failure.

Image-load `WARNING` lines (e.g. combat burst, territory stump) may appear in presentation tests; they are not suppressed.

## Extending profiles

Add new slice ids to `$Script:SliceTests` / `$Script:SupportedSlices` in the runner scripts. Prefer explicit file lists for **smoke** and **slice**; **cloud** / **presentation** on Godot filter the full list by path prefix so new files under those folders are picked up automatically when added to the full suite.
