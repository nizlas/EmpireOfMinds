# Empire of Minds — Cloud 0.1 local authority

Minimal **server-authoritative** HTTP slice: one match, `end_turn` only, snapshot + JSONL event log on disk. See [CLOUD_API_V0.md](../docs/CLOUD_API_V0.md).

## Run

From the `server/` directory:

```powershell
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8000
```

Override data directory (e.g. for tests):

```powershell
$env:EMPIRE_SERVER_DATA_DIR = "C:\path\to\data"
```

Files are written under `<EMPIRE_SERVER_DATA_DIR>/matches/<match_id>/` or, by default, `server/data/matches/<match_id>/`.

## Test

```powershell
cd server
pip install -r requirements.txt
pytest -q
```

## Run in Docker (local smoke)

From the **repository root** (build context is `server/`):

```powershell
docker build -t empire-server ./server
docker run --rm -p 8000:8000 empire-server
```

In another terminal:

```powershell
curl http://127.0.0.1:8000/v1/healthz
```

Expected: `{"ok":true}`. For Hetzner production (Caddy + internal API only), see [DEPLOY_HETZNER.md](../docs/DEPLOY_HETZNER.md).

## Smoke test (manual HTTP check)

Use this to repeat the Cloud 0.1 HTTP flow from PowerShell. The script **does not** start the server; run uvicorn first in another terminal.

1. Install deps (once):

   ```powershell
   cd server
   python -m pip install -r requirements.txt
   ```

2. Start the API (leave running; from `server/`):

   ```powershell
   python -m uvicorn app.main:app --reload --port 8000
   ```

3. In a **second** PowerShell, from `server/`:

   ```powershell
   .\scripts\smoke_cloud_01.ps1
   ```

   Optional base URL:

   ```powershell
   .\scripts\smoke_cloud_01.ps1 -BaseUrl "http://localhost:8000"
   ```

The script uses `Invoke-RestMethod` only (no extra dependencies). It prints **PASS/FAIL** lines, shows the created `match_id`, and exits with a non-zero code if any step fails.

## Scope

- Implemented: `end_turn`, current-player gate, revision, `state_hash`, events with `?since=`.
- Not implemented: Godot client, auth, lobby, realtime, `move_unit`, full rules parity with GDScript.
