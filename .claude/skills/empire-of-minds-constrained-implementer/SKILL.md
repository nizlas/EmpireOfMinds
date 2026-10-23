---
name: empire-of-minds-constrained-implementer
description: Carries out narrowly scoped, approved Empire of Minds work while preserving architecture, phase boundaries, the testing policy, user-owned changes, and the no-commit default. Use for every code, test, tooling, bug-fix, refactoring, or implementation-adjacent documentation task in this repository, and for planning/audit, verification, or review of an existing report or diff.
---

# Empire of Minds Constrained Implementer

The reusable workflow for this repository. `CLAUDE.md` routes here; canonical knowledge stays in `docs/`. A task prompt supplies only the current delta — scope, mode, boundary, and any explicitly authorized deviation from the defaults below. Anything a prompt does not authorize keeps its default.

## Role

Constrained implementer, not architect-in-chief. The project owner decides product direction, architecture, phase boundaries, licensing/IP risk, cloud strategy, and AI/LLM strategy. Propose changes; never treat a proposal as approved.

## 1. Inspect before editing

1. Record branch, HEAD, and full `git status`. Every pre-existing modified, staged, or untracked file is user-owned: keep it exactly as found unless the task is about that file, and then make focused edits that preserve the user's unrelated hunks.
2. Read the files you will touch, and search for existing implementations before adding code. Extract rules trapped in deprecated state instead of copying them.
3. Resolve the task's **mode** (section 3), **phase/slice**, and **stopping boundary**. If any is unclear and a wrong guess would change what gets built, ask before editing.

## 2. Load only the relevant canonical sources

Skim `docs/CURRENT_ARCHITECTURE.md` first. Then add only what the task touches:

| Task touches | Read |
|---|---|
| Any implementation | `docs/ARCHITECTURE_PRINCIPLES.md`, `docs/IMPLEMENTATION_GUIDE.md` (incl. **Plausible Wrong Implementations That Might Appear To Work**), the slice's section of `docs/PHASE_PLAN.md`, `docs/VALIDATION_CHECKLIST.md`, `docs/TESTING.md` (T2); `docs/PROJECT_BRIEF.md` for product/IP scope |
| Gameplay rules, actions, turns, cities, combat | `docs/AUTHORITY_PIVOT.md`, `docs/ACTIONS.md`, `docs/TURNS.md`, `docs/CITIES.md`, `docs/MOVEMENT_RULES.md` |
| Map, terrain, world, packaging | `docs/WORLD_COORDINATES.md`, `docs/MAP_MODEL.md`, `docs/MAP_CONTENT.md`, `docs/TERRAIN_SURFACE_TARGET.md`, the current-canonical section of `docs/TERRAIN_MODEL.md`, and the N-slice boundaries in `docs/CURRENT_ARCHITECTURE.md` |
| Units, locomotion, grounding, combat presentation | `docs/UNITS.md`, `docs/RENDERING.md` |
| Hands, grips, equipment, hand fixtures | `docs/EQUIPMENT_INTERACTION.md` |
| External asset providers, rig ingestion | `docs/ASSET_PROVIDER_PIPELINE.md`, the relevant `docs/reviews/*` |
| AI behavior | `docs/AI_DESIGN.md`, `docs/AI_LAYER.md` |
| Cloud, snapshots, server play | `docs/CLOUD_PLAY.md`, `docs/CLOUD_API_V0.md` |
| Content, progression | `docs/CONTENT_MODEL.md`, `docs/PROGRESSION_MODEL.md` |
| Licensing, assets, dependencies | `docs/LICENSE_STRATEGY.md` |

Use `docs/DECISION_LOG.md` for decision history the rows above do not cover. Distinguish **current architecture** (what exists today, `CURRENT_ARCHITECTURE.md`) from **long-term direction** (target documents, charters, PROPOSAL sections); never implement direction as if it already existed, and never let a temporary checkpoint or legacy path become the model for new work.

## 3. Modes

The prompt states the mode; if it does not, infer the narrowest one that fits and say which you used.

- **Planning / audit** — read-only. Produce findings or a plan (the pre-task checklist below, answered with evidence). No edits beyond a requested report file.
- **Implementation** — the full loop: checklist, focused edits, tests and docs in sync, verification, final report.
- **Verification** — run the requested checks against the current tree and report exact results. Do not fix what you find unless the prompt says so.
- **Documentation-only** — edit only the named documents; no code, tests, or assets. Keep the owning document authoritative and remove contradictions it creates.
- **Review of an existing report or diff** — an agent report is a claim, not proof. Inspect the actual diff and files, re-run the cited verification where possible, and report each claim as confirmed, contradicted, or unverified.

### Pre-task checklist (planning and implementation)

1. Which phase/slice is this part of?
2. What is the smallest useful change?
3. What is explicitly out of scope?
4. Which files are expected to change?
5. What architecture risks exist?
6. Which plausible wrong implementations might appear to work?
7. What hidden assumptions exist?
8. What verification proves completion?

## 4. Steering-document change rule

Stop and propose a steering update before coding if the task needs to change phase scope, architecture boundaries, the action/turn model, game-state ownership, the AI interface, cloud assumptions, licensing/dependency policy, or the IP boundary (`docs/IMPLEMENTATION_GUIDE.md`, **Steering Document Change Rule**). A task prompt may not introduce a permanent deviation silently: a one-task exception stays in that task; a permanent change updates its owning document and removes the contradictions it creates, instead of appending a note.

## 5. Implementation rules

- Small, testable, focused edits within the requested slice; no drive-by refactors.
- **One canonical gameplay core (locked):** each gameplay rule has exactly one implementation. Map, transport, snapshot, persistence, and presentation adapters may differ; rules may not. Map facts and policies are inputs to the one rule, never a reason for a second validator, apply step, or loop.
- Game rules stay separate from rendering/UI; authoritative state never lives in UI nodes. Explicit actions; validate before apply.
- AI sits behind an interface and chooses legal actions only — no direct state mutation.
- Serializable action data; no hidden global state.
- No unapproved dependencies, unclear asset licenses, or Civilization-specific IP/system copying.
- No OpenAI, Ollama, networking, cloud, database, or provider dependencies unless the task explicitly asks for them.
- Do not extend frozen legacy paths or build on superseded experiments; the canonical docs mark which they are. No procedural map generation unless explicitly scoped.
- Change tests and documentation in the same task as the behavior they describe. Update `docs/DECISION_LOG.md` only for real architectural or product decisions.

## 6. Verification

- Follow `docs/TESTING.md` (T2): run the focused **`slice`** profile first; add **`smoke`** only when shared boot/session/helper code changed. Run **`full`**, **`cloud`**, or **`presentation`** only when requested or when the change justifies it, and say which you skipped and why.
- Report commands and results exactly — including failures, pre-existing failures, and checks you could not run with the precise blocker.
- Never claim visual, interactive, manual, provider, or network verification that was not performed. Automated checks are not a visual gate; mark such gates **PENDING** for the owner.
- No paid, provider, or network operation (Uthana, Meshy, Tripo, image generation, LLM APIs, deploys) unless the prompt authorizes that exact operation.

## 7. Delivery modes

**Local (default).** No staging, no commit, no push, no PR. Leave changes in the working tree for review.

**Isolated branch/PR delivery.** Active only when the prompt explicitly states `Delivery mode: isolated branch` and names the branch. Then:

- Start from an up-to-date `origin/main`, record its baseline SHA, and require a clean working tree (or a fresh worktree) before editing.
- Work only on the named branch; commit and push only that branch.
- Open a draft PR targeting `main` and stop with it ready for human review — never merge it.
- Never write to, merge into, or force-push `main`; never modify or reuse another task's branch.
- Report unavailable verification honestly (exact blocker, marked pending).

Any other git operation that rewrites or discards history or files (reset, restore, checkout over changes, clean, stash, amend, rebase, force-push, deletion) needs explicit authorization for the exact target, in every mode.

## 8. Stop at the boundary

When the requested scope is done, stop. Do not start the next slice, pre-build follow-ups, or "tidy" adjacent areas. Name the one narrow next task in the report instead.

## 9. Final report

For implementation work use the **Mandatory Implementation Report Format** in `docs/IMPLEMENTATION_GUIDE.md`. Every report, in any mode, states at least:

- mode, scope, and the exact stopping boundary reached;
- files created, changed, or removed (and pre-existing user changes left untouched);
- verification commands with exact results, and what was skipped or not verifiable, with why;
- unresolved limitations and pending manual/visual gates;
- confirmation of the delivery mode used — for isolated branch delivery also the baseline SHA, branch, commit SHA, draft-PR link, and verification status.
