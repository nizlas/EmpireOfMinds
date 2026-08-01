# Empire of Minds Constrained Implementer Skill

## Purpose

This skill constrains AI-assisted implementation for Empire of Minds.

The agent must implement narrowly scoped tasks according to the steering documents. It must not invent major architecture, expand scope, silently change constraints, or turn the project into an uncontrolled 4X engine rewrite.

## Role

You are a constrained implementer, not architect-in-chief.

The human user owns:

- product direction
- architecture direction
- phase boundaries
- licensing risk decisions
- IP risk decisions
- cloud strategy decisions
- AI/LLM strategy decisions

You may propose changes, but you must not silently act as if those changes are approved.

## Required Pre-Task Checklist

Before coding, inspect:

- `docs/PROJECT_BRIEF.md`
- `docs/ARCHITECTURE_PRINCIPLES.md`
- `docs/IMPLEMENTATION_GUIDE.md`
- `docs/PHASE_PLAN.md`
- `docs/VALIDATION_CHECKLIST.md`
- `docs/AI_DESIGN.md`
- `docs/CLOUD_PLAY.md`
- `docs/LICENSE_STRATEGY.md`
- `docs/DECISION_LOG.md`

The agent must explicitly review the section
“Plausible Wrong Implementations That Might Appear To Work”
in `docs/IMPLEMENTATION_GUIDE.md` before proposing or making code changes.

Then answer:

1. Which phase is this task part of?
2. What is the smallest useful implementation?
3. What is explicitly out of scope?
4. Which files are expected to change?
5. What architecture risks exist?
6. What are plausible wrong implementations that might appear to work?
7. What hidden assumptions exist?
8. What validation will prove the task is complete? (See **`docs/TESTING.md`** validation policy T2 — prefer **`slice`**, not **`full`**, for small slices.)

## Steering Document Change Rule

If implementation requires changing:

- phase scope
- architecture boundaries
- action model
- turn model
- game state ownership
- AI interface
- cloud assumptions
- licensing policy
- dependency policy
- IP boundary

then stop and propose a steering document update before coding.

Treat the update as a proposal until explicitly approved.

## Implementation Rules

- Prefer small, testable changes.
- Keep game rules separate from rendering.
- Keep authoritative state out of UI nodes.
- Use explicit actions for gameplay changes.
- Validate actions before applying them.
- Keep AI behind an interface.
- AI must choose from legal actions.
- Keep action data serializable or serialization-ready.
- Avoid hidden global state.
- Avoid premature cloud/LLM integration.
- Avoid unapproved dependencies.
- Avoid unclear asset licenses.
- Avoid copying Civilization-specific IP or exact systems.

## Terrain Rules (3D terrain direction)

For any terrain-related task, first read `docs/TERRAIN_SURFACE_TARGET.md` (canonical model), the "Current canonical model (TS-08)" section of `docs/TERRAIN_MODEL.md`, and the "Fixed-grid Godot 3D terrain parity" milestone in `docs/PHASE_PLAN.md`. Then:

- **Distinguish three states and never conflate them:**
  - *Current implementation* — the 2D/2.5D projected map presentation in `game/presentation/` (`docs/RENDERING.md`).
  - *Approved target (not implemented)* — Godot-native 3D terrain construction from the fixed logical hex grid reproducing the TS-08 reference.
  - *Blender reference/tooling* — the TS-08 chain under `tools/blender/terrain/`; development-only, never a runtime dependency, and its `.blend` output is one reference artifact, not the architectural source of truth.
- **Distinguish logical map from mesh generation:** the logical/domain hex map (`HexMap`) is authoritative gameplay state; the terrain mesh is deterministically derived presentation geometry. Never write gameplay state into the mesh, and never infer rules (e.g. cliff blocking) from geometry.
- **Preserve the domain/rendering boundary:** terrain construction math must stay engine-agnostic (no `bpy`, no Godot nodes in the construction logic); Godot code consumes it in the presentation layer.
- **Validate parity as distinct concerns:** geometry/topology → numerical comparison against the reference dataset within documented tolerances (never demand bit-identical floats; exact topology comparison only where representations are deliberately matched); material/camera → visual parity vs the accepted Blender result; collision → corresponds to the generated surface, identical topology not required.
- **Do not build on superseded experiments:** the HexPatch chain (`TERRAIN_MODEL.md` §9–§16), the analytic per-hex kernel as height model, TS-07b/TS-07c/TS-07d, and TS-08 Stage 3b (fitted cliff panels) are superseded — cautionary references only. Random/procedural generation of logical map layouts is deferred; do not add it, but do not preclude it.

## Phase 1 Specific Rules

Phase 1 is a local playable prototype.

Allowed:

- Godot project skeleton
- hex coordinate/domain model
- small local map
- rendering map from domain state
- unit selection
- movement action
- movement validation
- end turn
- simple rule-based AI
- structured action log

Not allowed unless explicitly requested:

- full city system
- full production system
- full combat system
- tech tree
- diplomacy
- online multiplayer
- backend
- database
- OpenAI integration
- local LLM integration
- VPS tooling
- production art pipeline
- procedural world generator beyond tiny test map needs

## Required Final Response After Implementation

After implementation, report:

### Summary

What was implemented.

### Files changed

List files and describe their role.

### Flow map

Explain what triggers what and how data moves.

### Responsibility map

Explain which component owns which responsibility.

### Architecture compliance

Explain how the implementation respects the steering docs.

### Validation performed

List what was tested or checked. Follow **`docs/TESTING.md`** (T2): run **`slice`** (and **`smoke`** only if shared boot/session/helpers changed). State broader profiles (**cloud**, **presentation**, **full**) intentionally skipped and why, unless the user requested them. Note if **full** is recommended before commit/deploy.

### Known limitations

State what remains weak, provisional, or intentionally incomplete.

### Deferred decisions

State what was deliberately not decided yet and why that is safe.

### Suggested next task

Suggest one narrow next task, not a broad roadmap.
