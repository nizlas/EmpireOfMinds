# Empire of Minds — Implementation Guide

This document defines how implementation work must be carried out in Empire of Minds.

The agent is a constrained implementer, not architect-in-chief. It may only implement within the documented architecture envelope.

If gaps, ambiguities, hidden assumptions, or architectural risks are found, the correct action is:

1. stop implementation planning
2. surface the issue explicitly
3. propose required steering-document updates
4. treat those updates as proposals until explicitly approved
5. reassess
6. only then continue

## Steering Document Change Rule

The agent must not silently rewrite its own steering constraints as part of implementation work.

If implementation reveals a problem in the current steering documents, the agent must:

- identify the issue explicitly
- explain why the current steering is insufficient or ambiguous
- propose a concrete document update
- treat that update as a proposal until explicitly approved by the user

Implementation must not proceed on the basis of a changed architecture envelope until that change has been explicitly approved and reflected in the steering documents.

## Core Working Mode

Work must proceed in narrow, well-defined, preferably testable phases.

Every phase must be small enough that:

- its goal is clear
- its out-of-scope boundaries are clear
- its architecture risks are reviewable
- its result can be validated against steering documents

Implementation is not allowed to silently broaden the project.

## Mandatory Phase Loop

### Before a phase

Before implementation begins, do all of the following:

1. define narrow scope
2. define explicit out-of-scope
3. run planning mode
4. identify:
   - gaps
   - ambiguities
   - hidden assumptions
   - risks
   - likely technical debt
5. if any are found, propose steering-doc updates first
6. treat those updates as pending until explicitly approved
7. reassess whether the phase is now stable
8. only then switch to implementation mode

### After a phase

After implementation, do all of the following:

1. validate against `docs/PROJECT_BRIEF.md`
2. validate against `docs/ARCHITECTURE_PRINCIPLES.md`
3. validate against `docs/VALIDATION_CHECKLIST.md`
4. state what remains weak, risky, or provisional
5. state what must change before the next phase
6. propose document updates if needed before proceeding

## The Agent Must Not

The agent must not:

- invent architecture outside documented scope
- silently broaden scope
- introduce a new subsystem without explicit approval
- introduce a new abstraction layer without explicit approval
- introduce a new persistent state owner without explicit approval
- introduce networking/cloud/database dependencies unless explicitly requested
- introduce OpenAI/Ollama/LLM dependencies unless explicitly requested
- make Godot nodes the hidden source of truth for game rules
- let UI callbacks directly mutate gameplay state without actions
- let AI directly mutate gameplay state
- treat a temporary shortcut as acceptable if it creates hidden architectural debt
- copy Civilization IP, names, icons, text, leader concepts, UI, or exact systems
- add assets or dependencies with unclear licenses

## Required Planning Output Before Implementation

Before each phase is implemented, the planning step must produce:

### 1. Phase scope

A short statement of exactly what is being built now.

### 2. Out-of-scope list

A short list of things explicitly not being built in this phase.

### 3. Gap and risk analysis

A short list of:

- unclear areas
- assumptions
- likely failure modes
- architectural risks
- possible debt introduced by the proposed approach

### 4. Proposed implementation shape

A short explanation of:

- which responsibilities will exist
- which classes/files/scripts are expected to change
- why this split is appropriate for this phase

### 5. Validation plan

A short explanation of how the phase result will be checked.

If this planning output is not clear, implementation should not begin.

## Required Implementation Outputs Per Phase

Every phase must leave behind outputs that make the repository understandable without reading every line of code.

At minimum, provide:

### 1. Short flow map

A short explanation of how control and data move through the new implementation.

Example questions it should answer:

- what triggers what?
- what calls what?
- what state changes where?
- what drives rendering?
- what drives action validation?
- what is logged?
- what is deterministic?

### 2. Responsibility map

A short list of new or modified files/classes/scripts and what each one is responsible for.

### 3. “Why this split” explanation

A short explanation of why responsibilities were split this way rather than merged or split differently.

### 4. Next-phase support note

A short note explaining how the chosen design supports the next likely phase.

## Required Explicit Questions For Every Phase

The agent must explicitly answer:

### What are the plausible wrong implementations that might appear to work?

For Empire of Minds, examples include:

- directly moving a Godot unit sprite and updating rules later
- storing unit position only in scene coordinates
- letting AI call movement functions that bypass validation
- making end-turn just a UI state toggle
- adding a text log rather than structured action log
- hard-coding player 1/player 2 everywhere
- assuming local client authority in ways that break cloud mode later

### What assumptions are being made implicitly?

Examples:

- only one human player
- only one AI player
- all map tiles are visible
- all units have same movement rules
- no combat
- no city ownership
- no simultaneous turn submission
- no save migration yet

### What decisions are being deferred, and is that safe?

Examples:

- exact cloud backend framework
- final AI planner architecture
- final save format
- final art pipeline
- final combat model
- final diplomacy model

The agent must explain why deferring each decision is safe for the current phase.

## Empire of Minds-Specific Implementation Guardrails

Implementation must actively guard against:

- hidden coupling between Godot UI and game rules
- state that exists only in rendered nodes
- action validation mixed with animation code
- AI logic mixed with rule execution
- turn order hidden inside UI button state
- legal action generation scattered across presentation code
- cloud-hostile client-authoritative assumptions
- unversioned action/save schemas
- premature abstractions outside current phase
- Civilization-like copying beyond broad genre inspiration

## Phase 1 Interpretation Rule

Phase 1 must not be implemented as “just a Godot hex-grid demo”.

It must be implemented as:

**a tiny turn-based strategy action engine that currently supports one rendered local scenario.**

That means Phase 1 should already preserve conceptual separation between:

- domain/session state
- actions
- action validation
- action application
- turn management
- AI choice
- rendering/UI

But it must do so without introducing unnecessary general-purpose 4X systems.

## Change Discipline

Prefer small, reviewable changes.

Do not mix all of the following in one step unless clearly justified:

- architecture changes
- rendering changes
- action model changes
- AI behavior changes
- save/load changes
- cloud assumptions
- licensing/dependency changes
- UI redesign

Small phases are preferred over broad rewrites.

## Code Clarity

The code is part of the documentation.

Central project code should make responsibility and ownership visible.

For central files/scripts, include comments that explain:

- role in the system
- ownership
- what the code deliberately does not do
- whether code is domain, presentation, AI, or infrastructure
- any important coordinate-space distinction

Important coordinate spaces should be explicit, for example:

- hex coordinates
- map/world coordinates
- screen coordinates
- serialized action/state coordinates

Do not write comments that merely narrate syntax.

Write comments that help a future reader understand the system.

## Mandatory Implementation Report Format

Every implementation response must use this structure:

1. **Phase**
   - Which phase/step this belongs to.

2. **Scope implemented**
   - What was actually built.

3. **Explicitly not implemented**
   - What was intentionally left out.

4. **Files changed**
   - File-by-file summary.

5. **Flow map**
   - How control/data moves through the implementation.

6. **Responsibility map**
   - Which file/class owns what.

7. **Architecture compliance**
   - How this follows the steering docs.

8. **Plausible wrong implementations avoided**
   - Which tempting bad shortcuts were avoided.

9. **Validation**
   - What was run, tested, or manually checked.

10. **Known limitations**
   - What is still weak or temporary.

11. **Steering document impact**
   - Whether docs need updates.
   - If yes, propose exact changes but do not assume approval.

12. **Next narrow task**
   - One recommended next step.

## Plausible Wrong Implementations That Might Appear To Work

The agent must actively avoid implementations that appear functional but violate the long-term architecture.

Examples:

### 1. Sprite-first unit movement

Wrong:
- clicking a tile moves the Godot sprite
- unit position is updated implicitly from sprite position

Correct:
- movement is represented as a MoveUnit action
- action is validated
- domain state updates unit hex coordinate
- rendering animates from old state to new state

### 2. UI-owned turn logic

Wrong:
- End Turn button directly toggles local UI state

Correct:
- EndTurn is an action or explicit turn-controller request
- turn state is updated in the domain/session layer
- UI reflects the updated turn state

### 3. AI bypasses rules

Wrong:
- AI picks a unit node and changes its position

Correct:
- AI receives legal actions
- AI returns selected actions
- actions are validated and applied normally

### 4. Map exists only as visual tiles

Wrong:
- map is a collection of rendered hex nodes with terrain in node names

Correct:
- map is domain data
- renderer creates visual representation from map state

### 5. Text-only action log

Wrong:
- action log is only strings like “Unit moved east”

Correct:
- action log stores structured action records
- human-readable text can be derived later

### 6. Client-authoritative assumptions

Wrong:
- local client directly owns all future game truth

Correct:
- local Phase 1 can be authoritative locally
- action/state model remains compatible with future server authority
