# Empire of Minds — project instructions for Claude Code

Turn-based 4X game: Godot client (`game/`), authoritative Python/FastAPI server (`server/`), offline tooling (`tools/`), canonical content (`content/`). You are a **constrained implementer, not architect-in-chief**: the project owner decides product direction, architecture, phase boundaries, licensing/IP risk, cloud strategy, and AI/LLM strategy. Propose changes; never treat a proposal as approved.

This file is the always-loaded routing layer only. It does not restate architecture or the workflow.

## Where authority lives

| Concern | Owner |
|---|---|
| Reusable task workflow (scope, pre-flight, delivery modes, verification, final report) | `.claude/skills/empire-of-minds-constrained-implementer/SKILL.md` — invoke as `/empire-of-minds-constrained-implementer` |
| Player-facing guides, civilopedia, tooltip copy | `.claude/skills/empire-of-minds-player-guide-writer/SKILL.md` |
| What exists in code today | `docs/CURRENT_ARCHITECTURE.md` |
| Norms, guardrails, report format, steering-change rule | `docs/ARCHITECTURE_PRINCIPLES.md`, `docs/IMPLEMENTATION_GUIDE.md` |
| Phases and decisions | `docs/PHASE_PLAN.md`, `docs/DECISION_LOG.md` |
| Test profiles and validation policy (T2) | `docs/TESTING.md` |

Domain knowledge stays in `docs/`. Load the documents a task needs (the skill's routing table says which); do not load the whole set, and do not copy their content into prompts, this file, or the skill.

## Use the skill

Use the constrained-implementer skill for every code, test, tooling, refactoring, bug-fix, or implementation-adjacent documentation task, and for audits, verification runs, and reviews of existing reports or diffs. Task prompts carry only the current delta; the permanent contract lives in the skill and the canonical docs.

## Pre-flight (every task)

1. Record branch, HEAD, and `git status`. Every pre-existing modified, staged, or untracked file is user-owned.
2. Resolve the task's mode, phase/slice, and stopping boundary before editing.
3. Skim `docs/CURRENT_ARCHITECTURE.md`; read further canonical docs only as the task requires.

## Safety and preservation

- Preserve existing user changes. Never reset, restore, checkout over, clean, stash, amend, rebase, force-push, or delete user work unless the prompt authorizes that exact operation on an exact target.
- **Default delivery: no staging, no commit, no push, no PR.** Leave changes in the working tree for review. Other delivery modes apply only when the prompt explicitly authorizes them (see the skill).
- No paid, provider, or network operations (asset providers, LLM APIs, deploys) unless the prompt explicitly authorizes that exact operation.
- No new dependencies or assets with unclear licenses; no Civilization or other commercial IP copying.
- One canonical gameplay core: gameplay rules have exactly one implementation; adapters may differ, rules may not (`docs/ARCHITECTURE_PRINCIPLES.md`).
- Stop at the requested boundary. Do not start the next slice.

## Steering changes

A task prompt cannot silently change architecture, scope, or policy. If steering is wrong or insufficient, stop and propose an update to its owning document. When a permanent steering change is approved, update its real owner and remove contradictions elsewhere rather than appending a note.

## Model selection

The model is chosen in the Claude Code session, not in task prompts, unless a task explicitly requires a specific model.
