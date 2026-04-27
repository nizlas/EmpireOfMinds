# Empire of Minds — Decision Log

## 2026-04-27 — Initial Engine Direction

Decision:
Use Godot as the initial prototyping engine.

Rationale:
- permissive MIT license
- good fit for 2D/strategy prototyping
- low licensing risk
- fast iteration
- no revenue share/runtime fee

Caveat:
The architecture must not make core rules inseparable from Godot scenes.

## 2026-04-27 — AI Direction

Decision:
Start with deterministic rule-based AI.

Rationale:
- debuggable
- testable
- works offline
- creates legal-action interface needed for future LLM AI

Caveat:
LLM adapters may be explored later, but must choose from generated legal actions.

## 2026-04-27 — Cloud Direction

Decision:
Design for asynchronous play-by-cloud, but do not build official hosting first.

Rationale:
- async turns fit 4X gameplay
- avoids early operational burden
- enables Bring Your Own Server / Private Cloud

Caveat:
Server-authoritative architecture must be preserved for future cloud mode.

## 2026-04-27 — Scripting language for Godot (Phase 1.x)

Decision:
Phase 1.x uses Godot 4.x with GDScript as the default scripting language; C# is deferred to avoid introducing a .NET dependency during early prototyping.

Rationale:
- GDScript ships with Godot; no separate .NET SDK or Mono build required on the machine or in the repo for contributors to open and run the project.

Caveat:
C# may be reconsidered later only with an explicit steering decision to accept the .NET dependency.
