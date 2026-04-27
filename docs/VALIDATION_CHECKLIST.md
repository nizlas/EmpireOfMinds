# Empire of Minds — Validation Checklist

This checklist is used after each implementation step.

## Architecture Boundary Validation

- [ ] Game rules are not owned by Godot rendering nodes.
- [ ] Unit positions are stored in domain/game state, not only in sprites.
- [ ] Map/hex data is represented as domain data, not only as drawn tiles.
- [ ] UI requests actions rather than directly mutating gameplay state.
- [ ] AI chooses from legal actions and does not mutate state directly.
- [ ] Actions are validated before application.
- [ ] Action application updates authoritative state.
- [ ] Rendering reflects state rather than owning state.
- [ ] The implementation does not assume future cloud games are client-authoritative.

## Phase 1 Functional Validation

- [ ] A local map can be displayed.
- [ ] At least one unit exists in domain state.
- [ ] Unit selection works.
- [ ] Legal destination hexes can be determined.
- [ ] A legal move action succeeds.
- [ ] An illegal move action is rejected.
- [ ] End turn advances the turn state.
- [ ] A simple AI turn can choose at least one legal action.
- [ ] AI actions go through the same validation path as player actions.
- [ ] Action log records structured actions.

## Determinism / Replay Readiness

- [ ] Actions have structured data, not only human-readable text.
- [ ] Game state changes happen through actions.
- [ ] Randomness is absent, seeded, or explicitly recorded.
- [ ] The same initial state plus the same action sequence should produce the same result, within current phase limits.

## Cloud Readiness

- [ ] Actions are serializable or designed to become serializable.
- [ ] Game state is serializable or designed to become serializable.
- [ ] Player identity is explicit enough to support future cloud turns.
- [ ] Turn ownership is explicit enough to support future server validation.
- [ ] No Phase 1 shortcut makes server-authoritative validation impossible later.

## AI Readiness

- [ ] AI has a narrow interface.
- [ ] Rule-based AI works without network access.
- [ ] No OpenAI/Ollama dependency is required for gameplay.
- [ ] LLM integration, if discussed, remains behind future adapter boundaries.
- [ ] AI rejected actions are logged or diagnosable.

## IP / Licensing

- [ ] No Civilization names, icons, text, leaders, or exact UI/system copying.
- [ ] Any added dependency has an acceptable license.
- [ ] Any added asset has a known source and license.
- [ ] No AGPL/GPL dependency is added without explicit approval.
- [ ] No “free for personal use” asset is included in distributable content.

## Agent Behavior

- [ ] Agent stated the phase scope before implementation.
- [ ] Agent stated explicit out-of-scope items.
- [ ] Agent listed plausible wrong implementations.
- [ ] Agent listed hidden assumptions.
- [ ] Agent listed deferred decisions and why deferral is safe.
- [ ] Agent listed files changed.
- [ ] Agent explained responsibility split.
- [ ] Agent explained validation performed.
- [ ] Agent did not silently change steering documents.
- [ ] Agent proposed steering document updates when needed.
