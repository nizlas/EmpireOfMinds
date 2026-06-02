# Empire of Minds — Test profiles (T1)

The project has a large server (pytest) and Godot headless regression suite. **Profiles** run a subset during day-to-day work; **`full`** is unchanged and remains the default before deploy or large refactors.

No profile deletes or weakens tests. Failures are not suppressed.

## When to use each profile

| Profile | Use when |
|--------|----------|
| **smoke** | Quick local iteration — “is anything obviously broken?” |
| **slice \<id\>** | Repeated checks while implementing a focused slice (e.g. **c13a**) |
| **cloud** | Before cloud/server/client deploy-related changes |
| **presentation** | Before visual / presentation / headless UI changes (Godot only) |
| **full** | Before committing a larger slice, before deploy, after refactors, when chasing regressions |

## Server

From the **repository root** (requires `pytest` on PATH; install deps under `server/` first).

```powershell
.\scripts\run-server-tests.ps1              # full (pytest -q in server/)
.\scripts\run-server-tests.ps1 full
.\scripts\run-server-tests.ps1 smoke
.\scripts\run-server-tests.ps1 cloud
.\scripts\run-server-tests.ps1 slice c13a
.\scripts\run-server-tests.ps1 slice c14b
.\scripts\run-server-tests.ps1 presentation   # prints Godot-only notice, exit 0
```

Equivalent manual full run: `cd server` then `pytest -q`.

### What each profile runs

- **full** — all tests under `server/tests/`.
- **smoke** — `test_end_turn_flow.py` (health, create match, end turn), `test_legal_actions_endpoint.py`.
- **cloud** — API/action flows: create match, move, end turn, found city, production, attack, combat rules, legal-actions, production/food/science ticks, snapshot v2, player visibility, seats / seat-token flow.
- **slice c13a** — `test_seats.py`, `test_seat_token_flow.py`.
- **slice c14b** — `test_lobby_list.py`, `test_seat_claim.py`, `test_seats.py`.

Unknown slice ids print supported ids and exit non-zero.

## Godot

From the **repository root** (requires Godot console build; see script header for `GODOT_EXE` / PATH).

```powershell
.\scripts\run-godot-tests.ps1              # full (142 tests, same order as before T1 + C14a)
.\scripts\run-godot-tests.ps1 full
.\scripts\run-godot-tests.ps1 smoke
.\scripts\run-godot-tests.ps1 cloud
.\scripts\run-godot-tests.ps1 presentation
.\scripts\run-godot-tests.ps1 slice c13a
.\scripts\run-godot-tests.ps1 slice c14a
```

### What each profile runs

- **full** — entire ordered list in `scripts/run-godot-tests.ps1` (domain, presentation, AI, cloud).
- **smoke** — `test_cloud_client_payloads.gd`, `test_main_default_cloud_base_url.gd`, `test_main_tscn_map_layer_sibling_order.gd`.
- **cloud** — all `res://cloud/tests/*.gd` entries in the full list (currently 11 files).
- **presentation** — all `res://presentation/tests/*.gd` entries in the full list.
- **slice c13a** — `test_cloud_seat_token.gd`.
- **slice c14a** — `test_cloud_credential_store.gd`.

## Known noisy output (not hidden)

Some Godot cloud negative tests use `::not-a-url::` so HTTP fails immediately; tests **pass** but Godot logs red `ERROR: Error parsing URL` lines. That is intentional test harness noise, not a profile failure.

Image-load `WARNING` lines (e.g. combat burst, territory stump) may appear in presentation tests; they are not suppressed.

## Extending profiles

Add new slice ids to `$Script:SliceTests` / `$Script:SupportedSlices` in the runner scripts. Prefer explicit file lists for **smoke** and **slice**; **cloud** / **presentation** on Godot filter the full list by path prefix so new files under those folders are picked up automatically when added to the full suite.
