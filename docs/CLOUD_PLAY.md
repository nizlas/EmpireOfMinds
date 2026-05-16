# Empire of Minds — Cloud Play Strategy

**Long-term direction (authority model, async/live-feel, action vocabulary, roadmap labels, AI parity):** [CLOUD_PLAY_DIRECTION.md](CLOUD_PLAY_DIRECTION.md). This page stays focused on **product/strategy** (modes, BYOS); the direction doc is the **canonical architecture checkpoint** for cloud/multiplayer/AI without implementation detail.

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

The **shipping playable embryo** today is a **local hotseat prototype**: **one** client process, **no** network multiplayer, **no** authoritative server, **no** lobby, **no** accounts, **no** fog-of-war / **privacy** partition between players, and **no** **remote-seat** concept in code. **All** gameplay changes still go through **`GameState.try_apply`** with the usual **`actor_id == current_player_id()`** gate. A **future server / cloud** mode should remain **authoritative** and reuse the same **action validation / application** model at the session boundary; UI copy such as **“Waiting for remote Player N”** belongs to that **future** slice, **not** to the current **local hotseat prototype** (the HUD uses **`Player N's turn`** instead).

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
