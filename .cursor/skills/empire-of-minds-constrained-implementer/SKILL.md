---
name: empire-of-minds-constrained-implementer
description: Implements narrowly scoped, approved Empire of Minds changes while preserving architecture, phase boundaries, testing policy, and map/terrain authority. Use for every code, test, tooling, bug-fix, refactoring, or implementation-documentation task in this repository.
---

# Empire of Minds Constrained Implementer

## Role

Constrained implementer, not architect-in-chief. The human owns product direction, architecture, phase boundaries, licensing/IP risk, cloud strategy, and AI/LLM strategy. Propose changes; do not silently treat proposals as approved.

## Doc routing (read before coding)

Skim `docs/CURRENT_ARCHITECTURE.md` first. Then read only what the task needs:

| Task type | Additional docs |
|-----------|-----------------|
| **Any implementation** | `docs/PROJECT_BRIEF.md`, `docs/ARCHITECTURE_PRINCIPLES.md`, `docs/IMPLEMENTATION_GUIDE.md` (including **“Plausible Wrong Implementations That Might Appear To Work”**), `docs/PHASE_PLAN.md`, `docs/VALIDATION_CHECKLIST.md`, `docs/TESTING.md` (T2 policy) |
| **Map / terrain / world / packaging** | `docs/WORLD_COORDINATES.md`, `docs/MAP_MODEL.md`, `docs/MAP_CONTENT.md`, `docs/TERRAIN_SURFACE_TARGET.md`, TS-08 section of `docs/TERRAIN_MODEL.md`; use `docs/DECISION_LOG.md` for recent N-slice decisions |
| **AI behavior** | `docs/AI_DESIGN.md` |
| **Cloud / snapshots / server play** | `docs/CLOUD_PLAY.md` |
| **Licensing / assets / dependencies** | `docs/LICENSE_STRATEGY.md` |

Use `docs/DECISION_LOG.md` when the task touches architecture boundaries or you need decision history not covered above.

## Pre-task checklist

Answer before coding:

1. Which phase/slice is this part of?
2. What is the smallest useful implementation?
3. What is explicitly out of scope?
4. Which files are expected to change?
5. What architecture risks exist?
6. What plausible wrong implementations might appear to work?
7. What hidden assumptions exist?
8. What validation proves completion? (T2: prefer **`slice`**; **`smoke`** only if shared boot/session/helpers changed; skip **`full`** / **`cloud`** / **`presentation`** for small slices unless requested.)

## Steering-document change rule

Stop and propose a steering update before coding if the task requires changing phase scope, architecture boundaries, action/turn model, game-state ownership, AI interface, cloud assumptions, licensing/dependency policy, or IP boundary.

## Implementation rules

- Small, testable changes within the requested slice.
- Game rules separate from rendering/UI; authoritative state out of UI nodes.
- Explicit actions for gameplay changes; validate before apply.
- AI behind an interface; chooses legal actions only; no direct state mutation.
- Serializable or serialization-ready action data; avoid hidden global state.
- No unapproved dependencies, unclear asset licenses, or Civilization-specific IP/system copying.
- No premature cloud/LLM integration unless the task explicitly requests it.

## Terrain and map rules

For map/terrain/world tasks, apply the doc routing row above, then:

- **Six roles — do not conflate:**
  - *Authoritative 2D input* — canonical logical map + height-level grid in `content/maps/` → **`WorldMap`** (N1). **Sole terrain source input**; gameplay logical authority.
  - *TS-08-equivalent production solver* — **target** runtime construction path: generate continuous terrain from the 2D input ([TERRAIN_SURFACE_TARGET.md](docs/TERRAIN_SURFACE_TARGET.md)). Does **not** ship as a pre-solved JSON load in target architecture.
  - *N2 derived golden* — `content/terrain/reference/` pre-solved Stage-2 export. **Parity testing and audit only**; does **not** replace the solver or become the production terrain source.
  - *Optional temporary checkpoint* — N3 may load the N2 pre-solved dataset for early **visual parity** only; explicitly **not** target architecture ([DECISION_LOG.md](docs/DECISION_LOG.md) 2026-08-02 N2 terrain-direction alignment).
  - *Blender reference/tooling* — `tools/blender/terrain/`; development-only, never runtime; not a production terrain source.
  - *Frozen legacy (N8 removal)* — **`HexMap`** + 2D presentation, category yield tables, snapshot v2. **Do not extend.**
- New map work targets **`WorldMap`** only; no legacy adapters.
- **`WorldMap`** is logical authority; terrain mesh is derived presentation. Never write gameplay into mesh or infer rules from geometry.
- Domain/rendering boundary: construction math engine-agnostic; Godot consumes in presentation.
- Parity: **solver output** vs N2 golden (geometry/topology); visual vs accepted Blender result; collision vs **solver-generated** surface. **N3a:** topology-only parity via compact manifest derived from N2; Godot tests must not load the 26 MB N2 JSON at runtime.
- **Edge classification:** derived from canonical height grid + locked `edge_rule` / overrides; may be stored on **`WorldMap`**; not independent terrain authority. Partial-hex / underdetermined-corner **height** BC = **N3b**, not N3a.
- **N3a boundary:** `Ts08CutLattice` builds Stage-0 Ω_cut from **`WorldMap` only** — no height solve, no mesh nodes, no rendering, no N3b+.
- Do not build on superseded HexPatch/TS-07/Stage 3b experiments. No procedural map generation unless explicitly scoped.

## Phase 1 guardrails

Local playable prototype scope only unless explicitly requested: no full city/production/combat/tech/diplomacy, online multiplayer, backend, database, OpenAI/local LLM, VPS tooling, production art pipeline, or procedural world generator beyond tiny test maps.

## Final report (substantive implementations)

### Summary
What was implemented.

### Files changed
List files and their role.

### Flow map
What triggers what; how data moves.

### Responsibility map
Which component owns what.

### Architecture compliance
How steering docs and boundaries were respected.

### Validation performed
What ran per `docs/TESTING.md` (T2). Note intentionally skipped broader profiles and why.

### Known limitations
What remains weak, provisional, or incomplete.

### Deferred decisions
What was deliberately not decided and why that is safe.

### Suggested next task
One narrow next task — not a roadmap.
