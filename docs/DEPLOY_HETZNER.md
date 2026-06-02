# Empire of Minds — Hetzner Cloud Alpha deploy (C12a)

Production-shaped deploy foundation for the FastAPI authority server on **empire-cloud-01** (Hetzner). **No** gameplay, auth, Postgres, or polling changes in this slice.

## Architecture

```text
Godot client (EOM_CLOUD_BASE_URL=https://cloud.thewizardsapprentice.org)
  -> HTTPS :443 (and :80 for ACME)
  -> Caddy container (caddy:2)
  -> reverse_proxy empire-server:8000 (Docker internal network only)
  -> FastAPI container (empire-server)
  -> named volume empire_match_store -> /app/data/matches/<match_id>/
```

- **Public URL:** `https://cloud.thewizardsapprentice.org`
- **Server IPv4:** `62.238.44.6`
- **FastAPI port 8000** is **not** published on the host; only Caddy exposes **80** and **443**.

## DNS (required)

| Host | Type | Value | Notes |
|------|------|-------|-------|
| `cloud.thewizardsapprentice.org` | A | `62.238.44.6` | Points to Hetzner; Caddy obtains TLS here |

**Do not** point `thewizardsapprentice.org` or `www.thewizardsapprentice.org` at Hetzner. WordPress stays on SiteGround with existing DNS.

Verify propagation:

```bash
dig +short cloud.thewizardsapprentice.org
# expect: 62.238.44.6
```

## Prerequisites on the server

- Docker and Docker Compose (v2 plugin) installed and working.
- Firewall: **TCP 22** (SSH, your IP), **TCP 80** and **TCP 443** from anywhere; **no** public **8000**.
- Full **git clone** of this repository (not only `deploy/hetzner`), because `docker-compose.yml` builds from `../../server`.

## One-time setup

```bash
git clone <your-repo-url> EmpireOfMinds
cd EmpireOfMinds/deploy/hetzner
```

## Deploy

```bash
cd deploy/hetzner
docker compose up --build -d
```

## Status and logs

```bash
docker compose ps
docker compose logs -f caddy
docker compose logs -f empire-server
```

## Update (new code)

```bash
cd /path/to/EmpireOfMinds
git pull
cd deploy/hetzner
docker compose up --build -d
```

## Stop without deleting match data

```bash
cd deploy/hetzner
docker compose down
```

Named volumes (`empire_match_store`, `caddy_data`, `caddy_config`) are **retained**.

## Warning — data loss

```bash
docker compose down -v
```

**Deletes named volumes**, including **`empire_match_store`**. All persisted match snapshots and event logs on that host are destroyed.

## HTTPS validation

From any machine with DNS resolved:

```bash
curl -fsS https://cloud.thewizardsapprentice.org/v1/healthz
```

Expected body: `{"ok":true}`

## Confirm port 8000 is not public

From outside the Hetzner host (should **fail** — connection refused or timeout):

```bash
curl -fsS http://62.238.44.6:8000/v1/healthz
```

Only `https://cloud.thewizardsapprentice.org/...` should reach the API.

## Match-store persistence validation

1. Create a match (Godot cloud client or API):

   ```bash
   curl -fsS -X POST https://cloud.thewizardsapprentice.org/v1/matches \
     -H "Content-Type: application/json" -d "{}"
   ```

   Note `match_id` from the response.

2. Confirm GET works:

   ```bash
   curl -fsS "https://cloud.thewizardsapprentice.org/v1/matches/<match_id>"
   ```

3. Restart only the API container:

   ```bash
   cd deploy/hetzner
   docker compose restart empire-server
   ```

4. Repeat GET — same `match_id`, snapshot, and revision should still be present.

Match files live in the **`empire_match_store`** volume at `/app/data/matches/<match_id>/` inside the container (`EMPIRE_SERVER_DATA_DIR=/app/data`).

## Caddy / ACME troubleshooting

1. **DNS first** — `dig +short cloud.thewizardsapprentice.org` must return `62.238.44.6` before expecting a valid cert.
2. **Firewall** — ports **80** and **443** must reach the host (Let's Encrypt HTTP-01 uses port 80).
3. **Logs** — `docker compose logs -f caddy` for certificate obtain/renew errors.
4. **Single site** — [deploy/hetzner/Caddyfile](../deploy/hetzner/Caddyfile) serves **only** `cloud.thewizardsapprentice.org`; root/www are not configured on this host.

## Godot remote validation

1. Start the game with cloud enabled:
   - `EOM_CLOUD_CLIENT=1`
   - `EOM_CLOUD_BASE_URL=https://cloud.thewizardsapprentice.org`
   - Optional: `EOM_CLOUD_DEBUG=1` (prints full **`host_token`** on create)
   - **Unset** `EOM_CLOUD_MATCH_ID` for a **new** match.
   - After create, set **`EOM_CLOUD_SEAT_TOKEN=<host_token>`** for reconnect (Slice C13a); Caddy forwards **`X-Empire-Seat-Token`** by default — no proxy change required.
2. Play: create match, **move**, **attack** (C10/C11), **end turn**.
3. Copy `match_id` from console; quit; relaunch with `EOM_CLOUD_MATCH_ID=<id>` — reconnect via GET should restore state.
4. Disable cloud (`EOM_CLOUD_CLIENT` unset) — local hotseat unchanged.

See also [VALIDATION_CHECKLIST.md](VALIDATION_CHECKLIST.md) (Slice C12a) and [CLOUD_PLAY.md](CLOUD_PLAY.md).

## Local Docker smoke (developer machine)

From repo root:

```powershell
docker build -t empire-server ./server
docker run --rm -p 8000:8000 empire-server
```

In another terminal:

```powershell
curl http://127.0.0.1:8000/v1/healthz
```

Compose config check (no running containers required):

```powershell
docker compose -f deploy/hetzner/docker-compose.yml config
```

Local dev without Docker remains: `cd server` then `python -m uvicorn app.main:app --reload --port 8000`.
