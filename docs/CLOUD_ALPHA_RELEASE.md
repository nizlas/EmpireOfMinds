# Empire of Minds — Cloud alpha release (external testers)

**Checkpoint:** Slice **C14d-final** (docs-only). **Status:** first successful **external** two-player cloud test (June 2026) — Windows client on another home network against **`https://cloud.thewizardsapprentice.org`**.

**Product/strategy context:** [CLOUD_PLAY.md](CLOUD_PLAY.md) (C14d cloud-alpha milestone). **Deploy:** [DEPLOY_HETZNER.md](DEPLOY_HETZNER.md). **Manual validation:** [VALIDATION_CHECKLIST.md](VALIDATION_CHECKLIST.md) (Slice C14d-final).

---

## What this alpha is

- A **zip** of an **unsigned** Godot **Windows** export — **not** an installer.
- Connects to the **Hetzner** FastAPI authority behind **Caddy** at **`https://cloud.thewizardsapprentice.org`**.
- **Two human players**, **async-friendly** staging → auto-start → turn-based ongoing play (no accounts, no invite codes in alpha).

**Deferred (not in this alpha):** code signing, Windows installer, Smart App Control policy workarounds beyond tester guidance, official cloud hosting as a product.

---

## Distribution package

1. **Export** Godot **Windows** build (project under `game/`).
2. **Zip** the export folder, including at minimum:
   - **`EmpireOfMinds.exe`** (and **`.pck`** if the export splits it)
   - **`Start Empire Cloud Alpha.bat`** (or equivalent name used by the team)
3. Send the zip to testers (e.g. shared drive, chat, email).

### `Start Empire Cloud Alpha.bat`

The batch file should set the cloud server URL for normal testers:

```bat
@echo off
set EOM_CLOUD_BASE_URL=https://cloud.thewizardsapprentice.org
start "" "%~dp0EmpireOfMinds.exe"
```

**Optional per tester / per machine instance:**

```bat
set EOM_CLOUD_PROFILE=A
```

Use **different** profile names when running **two instances on the same PC** so each window gets its own credential file (see below).

### Do **not** set for normal external testers

| Variable | Why |
|----------|-----|
| **`EOM_CLOUD_MATCH_ID`** | Bypasses lobby; dev reconnect only |
| **`EOM_CLOUD_SEAT_TOKEN`** | Bypasses claim/save flow; dev only |
| **`EOM_CLOUD_CLIENT=1`** | Skips front door; editor/CI dev |
| **`EOM_CLOUD_DEBUG=1`** | Verbose logs; support sessions only |

Testers should use the **front door**: create match, join staging, claim seat, resume saved match.

---

## `EOM_CLOUD_PROFILE` (local only)

- Selects which **local** credential file is used, e.g. **`user://cloud_matches_A.json`** vs default **`user://cloud_matches.json`**.
- **Never sent to the server** — server sees only **seat/host tokens** on authenticated requests.
- **Same machine, two windows:** use **different** profiles (e.g. **`A`** and **`B`**).
- **Different machines:** any profile name is fine; each machine keeps its own saved credentials.

---

## Player-facing quick start

1. Unzip the alpha folder.
2. Run **`Start Empire Cloud Alpha.bat`** (not raw exe unless you know the URL env is set).
3. **Host:** **Create Cloud Match** → enter display name → staging.
4. **Guest:** wait for the match to appear in the lobby list (polls every ~2s) → **Join** → staging.
5. Each player: **claim** a different seat → choose a **civilization** (Malmöfubikkarna, Västerviksjävlarna, or Pajasarna från Paris) → **Ready**.
6. When both are ready, the match **auto-starts** (no host Start button).
7. Play turns; the non-current player sees **Other player's turn** and the map stays visible; their client updates when it becomes their turn.
8. To return later: **Resume match** on the front door (same profile / same machine).

---

## Windows Smart App Control (external test setup)

During the first external test, **Windows blocked the exported executable**. This was **Smart App Control** (policy), **not** a server or game bug.

- **`Unblock-File`** on the zip/exe **did not** resolve the block in that test.
- This is **separate** from classic **SmartScreen** “More info → Run anyway.”
- **Practical workaround for testers:** use a machine where **Smart App Control does not block unknown apps**, or disable SAC for the test session per Microsoft guidance for that Windows edition.
- The alpha build is **unsigned**; **code signing** and a proper **installer** are **future** work.

If Windows blocks the app, check whether **Smart App Control** is enabled before reporting a connectivity bug.

---

## Known alpha limitations

- **Unsigned** Windows binary; SAC/SmartScreen friction expected.
- **Zip only** — no auto-update, no installer.
- **Plaintext** local credentials (`user://` JSON); not encrypted.
- **Public staging** on the alpha server — anyone with the URL can see/join open staging matches.
- **No** accounts, invite codes, private matches, or host delete/abandon in UI (host-token admin deferred).
- **No** websocket/SSE; waiting clients use **polling** (~2s) while out of turn.
- **Two seats** in normal alpha flow; third civ exists for registry/tests.
- **Local hotseat** in the same build is unchanged but is **not** the cloud-alpha test path.

---

## Support checklist (organizer)

- [ ] Server healthy at **`https://cloud.thewizardsapprentice.org`** (see deploy doc).
- [ ] Fresh zip built from current export.
- [ ] `.bat` points at production URL.
- [ ] Tester brief mentions SAC if install fails immediately.
- [ ] Two testers use **different seats** and **different civs**; confirm auto-start and turn handoff.
- [ ] Optional: close both clients and **Resume** — fog and turn ownership should match each seat (C14d reconnect parity).
