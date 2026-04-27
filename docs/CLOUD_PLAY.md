# Empire of Minds — Cloud Play Strategy

## Vision

Empire of Minds should support asynchronous play-by-cloud.

Players should be able to participate in a long-running turn-based game without being online at the same time.

## Initial Cloud Principle

Do not start by hosting all player games officially.

The project should support Bring Your Own Server / Private Cloud first.

## Supported Modes Over Time

### Local / Hotseat

Single machine. Useful for Phase 1 and early testing.

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
