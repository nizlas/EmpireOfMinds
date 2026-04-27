# Empire of Minds — Architecture Principles

This document defines the architecture envelope for Empire of Minds.

The agent is not allowed to invent architecture outside this envelope. It may only implement within the structure, constraints, and scope explicitly documented here and in the other steering documents.

## Core Principle

The agent is a constrained implementer, not architect-in-chief.

Architecture must be made explicit in documents before it is implemented in code.

If architectural gaps, ambiguities, or risks are discovered, the correct action is:

1. surface the issue explicitly
2. propose steering document updates
3. wait for explicit approval
4. only then implement according to the updated architecture

## Phase 1 Architectural Framing

Phase 1 must not be treated as “just a Godot hex-map prototype”.

It must be treated as:

**a small turn-based strategy rules engine that currently happens to render one local hex-map scenario in Godot.**

This means the design must support a logical growth path toward:

- multiple players
- multiple units
- cities
- production
- combat
- fog of war
- AI players
- deterministic action logs
- save/load
- async cloud play
- server-authoritative validation

However, that future growth path must be supported without introducing premature subsystems outside the current phase scope.

## Core Separation Requirements

### Domain/game rules are separate from rendering

Godot scenes, nodes, cameras, sprites, animations, and UI controls must not own the authoritative game rules.

The domain layer owns:

- map topology
- hex coordinates
- terrain
- units
- players
- turn state
- legal action generation
- action validation
- action application
- action log

The presentation layer may display state and request actions, but it must not bypass the rules engine.

### Clear game-state source of truth

Game state must have a clear source of truth.

In local Phase 1, the authoritative state may live in a local domain/session object.

In future cloud play, the authoritative state must move to the backend/server.

The architecture must not assume that the Godot client will always be authoritative.

### Actions are the only way to change game state

Gameplay changes must be expressed as explicit actions.

Examples:

- MoveUnit
- EndTurn
- FoundCity
- ProduceUnit
- AttackUnit
- ResearchTechnology

UI input, AI choices, and future network requests must all go through the same conceptual path:

```text
intent/request
  -> legal action generation
  -> action validation
  -> action application
  -> action log entry
  -> updated state/rendering
  