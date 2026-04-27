# Empire of Minds — Architecture Principles

## Core Principle

Empire of Minds must be built as a game-domain-first project, not as a pile of Godot scenes.

Godot is the initial client/engine choice, but core game rules, action validation, AI decision-making, save/load, and future cloud play must be conceptually separable from rendering and UI.

## Architectural Layers

### 1. Domain / Game Rules

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

### 2. Presentation / Client

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

### 3. AI Layer

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

### 4. Backend / Cloud Layer

Owns:
- authenticated cloud games
- persistent game records
- submitted turn actions
- server-authoritative validation
- AI worker scheduling
- notifications
- backup/export

Must treat clients as untrusted.

## Action Model

Clients and AI submit actions, not arbitrary full game state.

Example action concepts:
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

## Server-Authoritative Cloud Principle

In cloud games:
- the server owns canonical state
- clients submit candidate actions
- server validates legal actions
- server applies accepted actions
- server persists action log and/or snapshots
- clients receive updated state

## Determinism Principle

The project should use deterministic action logs where practical.

Randomness must be:
- seeded
- explicit
- replayable
- included in action log or state transition metadata

## Save/Load Principle

Save/load must be versioned from the start.

Supported early approach:
- snapshot + action log

Avoid:
- unversioned opaque save blobs
- state that only exists inside scenes
- hidden singletons with gameplay state

## Engine Dependency Rule

Godot-specific code is allowed in the client layer.

Godot-specific code should not leak into:
- core rules
- AI decision interfaces
- cloud/backend protocol definitions
- save schema

## Steering Document Change Rule

If implementation reveals that this architecture is wrong, incomplete, or blocking, the implementer must propose a steering document change before coding around the problem.
