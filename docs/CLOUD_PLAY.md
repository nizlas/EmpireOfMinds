# Empire of Minds — Cloud Play Strategy

**Long-term direction (authority model, async/live-feel, action vocabulary, roadmap labels, AI parity):** [CLOUD_PLAY_DIRECTION.md](CLOUD_PLAY_DIRECTION.md). This page stays focused on **product/strategy** (modes, BYOS); the direction doc is the **canonical architecture checkpoint** for cloud/multiplayer/AI without implementation detail.

**Authority pivot:** The project is **migrating** canonical gameplay authority to **Python/FastAPI** under `server/` while preserving a **legacy** Godot-domain path until cutover is proven. **Slices, rollback, and “local = localhost authority”** are defined in [AUTHORITY_PIVOT.md](AUTHORITY_PIVOT.md). Local hotseat and future cloud play share the **same** server rules; they differ only by **base URL / transport**.

## Vision

Empire of Minds should support asynchronous play-by-cloud.

Players should be able to participate in a long-running turn-based game without being online at the same time.

## Initial Cloud Principle

Do not start by hosting all player games officially.

The project should support Bring Your Own Server / Private Cloud first.

## Supported Modes Over Time

### Local / Hotseat

Single machine. Useful for Phase 1 and early testing.

### Current state as of Phase 5.2.0

The **shipping playable embryo** today is a **local hotseat prototype**: **one** client process, **no** network multiplayer, **no** lobby, **no** accounts, and **no** **remote-seat** concept in code. **All** gameplay changes still go through **`GameState.try_apply`** with the usual **`actor_id == current_player_id()`** gate **until** the **Authority pivot** cutover ([AUTHORITY_PIVOT.md](AUTHORITY_PIVOT.md)); after cutover, the same actions go through **`POST /v1/matches/.../actions`** on the **localhost** or **remote** authority. **Slice C8 (opt-in)** adds a **Godot cloud-client prototype**: **`Main.use_cloud_server`** or **`EOM_CLOUD_CLIENT=1`** boots **`POST /v1/matches`**, **`GET .../legal-actions`**, and **`POST .../actions`** for **`end_turn` / `move_unit` / `found_city` / `set_city_production`**, then replaces presentation from the **response snapshot** — **no** auth, **no** websocket/SSE, **no** **`attack_unit`** parity yet, **no** AI driving server turns. By default, **`Main.cloud_base_url`** is **`http://127.0.0.1:8000`** (not **`http://localhost:8000`**) so Windows Godot builds are less likely to stall on IPv6 **`::1`** before falling back to IPv4; **`EOM_CLOUD_BASE_URL`** and the inspector export still override. Until the first snapshot is applied, the client shows a **loading overlay** and **does not** treat local prototype state as playable; **`create-match`** failure surfaces an **error** instead of silently reverting to hotseat. Default editor play remains **local try_apply**. A **FastAPI** authority prototype (`server/`, [CLOUD_API_V0.md](CLOUD_API_V0.md)) exists today with a **minimal** snapshot (`end_turn` only in the shipped v0 wire); it will grow to hold the full loop. UI copy such as **“Waiting for remote Player N”** belongs to a **future** slice, **not** to the current **local hotseat prototype** (the HUD uses **`Player N's turn`** instead).

### Connect to Existing Server

Client connects to a backend URL.

### Private Cloud / Self-Hosted

User runs their own backend, likely via Docker Compose.

### Official Cloud

Optional future service if the project becomes commercial or widely used.

## Cloud Architecture Concept

```text
Godot Client
  -> HTTPS API
  -> Backend
  -> PostgreSQL
  -> Worker for AI turns / notifications
```

Alignment with [ARCHITECTURE_PRINCIPLES.md](ARCHITECTURE_PRINCIPLES.md): in cloud mode, the server owns canonical state; clients submit candidate actions; validation and application happen server-side. Phase 1 remains local-only; concrete backend work is deferred to the phase where it is in scope ([PHASE_PLAN.md](PHASE_PLAN.md)).

## RuleSet snapshot stability (Phase 5.0a)

**Concept-only** — no backend schema, protocol, storage format, or wire-format commitment in this subphase.

- **Saved games** and **async / cloud** sessions must **capture or reference** the **RuleSet** identity concepts **[CONTENT_MODEL.md](CONTENT_MODEL.md)**: **RuleSet id**, **content hash**, **`schema_version`**.
- Purpose: an **`ActionLog`** **replays** against the **same** **EffectiveRules**, not ad hoc definition code drift.
- **Server-authoritative** play replays the **validated RuleSet / EffectiveRules** for the session, not raw definition modules alone.
- **Seed** and **generator version** may help reproducibility for generative worlds, but **saved / replayed** games need a **stable content snapshot identity**.
