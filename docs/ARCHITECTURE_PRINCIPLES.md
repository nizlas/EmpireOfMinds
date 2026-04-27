# Empire of Minds — Architecture Principles

This document is the single canonical architecture envelope for Empire of Minds. The implementer is a constrained implementer, not architect-in-chief. Architecture must be made explicit in documents before it is implemented in code. Process, approval steps, and the steering-document change rule are defined in [IMPLEMENTATION_GUIDE.md](IMPLEMENTATION_GUIDE.md).

## Core game-domain principle

Empire of Minds must be built as a game-domain-first project, not as a pile of Godot scenes.

Godot is the initial client/engine choice, but core game rules, action validation, AI decision-making, save/load, and future cloud play must be conceptually separable from rendering and UI.

## Phase 1 architectural framing

Phase 1 must not be treated as “just a Godot hex-map prototype”.

It must be treated as:

**a small turn-based strategy rules engine that currently happens to render one local hex-map scenario in Godot.**

The design must support a logical growth path toward later phases (multiple players, cities, combat, fog of war, AI, deterministic action logs, save/load, async cloud play, server-authoritative validation) without introducing subsystems that are out of scope for the current phase. Scope for each phase is defined in [PHASE_PLAN.md](PHASE_PLAN.md) and the project brief.

## Architectural layers

### 1. Domain / game rules

Owns:

- map data
- hex coordinates
- terrain
- units
- cities
- players
- turn state
- legal action generation
- action validation
- action application
- deterministic action log
- game state versioning

Must not depend on:

- Godot rendering nodes
- UI controls
- animations
- network transport
- LLM provider APIs

### 2. Presentation / client

Owns:

- rendering map tiles
- unit visuals
- selection feedback
- movement animation
- camera
- UI panels
- input handling

May ask the domain layer:

- what is selected?
- what actions are legal?
- what changed after an action?

Must not bypass validation.

### 3. AI layer

Owns:

- choosing actions from legal actions
- simple rule-based AI
- future planner AI
- future LLM adapters

Must not:

- mutate game state directly
- invent illegal commands
- execute arbitrary tool commands
- bypass action validation

### 4. Backend / cloud layer

Owns (future cloud mode; not built in early phases except as design constraints):

- authenticated cloud games
- persistent game records
- submitted turn actions
- server-authoritative validation
- AI worker scheduling
- notifications
- backup/export

Must treat clients as untrusted.

## Game-state source of truth

Game state must have a clear source of truth.

In local Phase 1, the authoritative state may live in a local domain/session object.

In future cloud play, the authoritative state must move to the backend/server.

The architecture must not assume that the Godot client will always be authoritative.

## Action model

Clients and AI submit actions, not arbitrary full game state. Gameplay changes must be expressed as explicit actions.

Example action concepts (not an exhaustive or binding list for a given phase):

- MoveUnit
- FoundCity
- ProduceUnit
- EndTurn
- AttackUnit
- ResearchTechnology

Each action must have:

- schema version
- actor/player id
- action type
- parameters
- deterministic validation result
- deterministic state transition where practical

UI input, AI choices, and future network requests must all go through the same conceptual path:

```text
intent/request
  -> legal action generation
  -> action validation
  -> action application
  -> action log entry
  -> updated state/rendering
```

## Server-authoritative cloud principle

In cloud games:

- the server owns canonical state
- clients submit candidate actions
- server validates legal actions
- server applies accepted actions
- server persists action log and/or snapshots
- clients receive updated state

## Determinism principle

The project should use deterministic action logs where practical.

Randomness must be:

- seeded
- explicit
- replayable
- included in action log or state transition metadata

## Save/load principle

Save/load must be versioned from the start.

Supported early approach:

- snapshot + action log

Avoid:

- unversioned opaque save blobs
- state that only exists inside scenes
- hidden singletons with gameplay state

## Engine dependency rule

Godot-specific code is allowed in the client layer.

Godot-specific code should not leak into:

- core rules
- AI decision interfaces
- cloud/backend protocol definitions
- save schema

## Steering document change rule

If implementation reveals that this architecture is wrong, incomplete, or blocking, the implementer must propose a steering document change before coding around the problem. Follow [IMPLEMENTATION_GUIDE.md](IMPLEMENTATION_GUIDE.md) for the full process.
