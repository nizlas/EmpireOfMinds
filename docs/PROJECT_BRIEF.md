# Empire of Minds — Project Brief

## Status

Empire of Minds is an early hobby/experimental strategy game project by Niclas and Niklas. The project may remain a hobby prototype, but early technical, licensing, and architectural decisions must not unnecessarily block a future commercial release.

## Vision

Empire of Minds is a turn-based 4X strategy game inspired by the broad genre of Civilization-like games, but with original IP, original systems, original presentation, and a strong focus on better AI.

The game should eventually support:
- hex-based world map
- exploration
- expansion
- cities
- units
- technology/research
- diplomacy
- turn-based conflict
- asynchronous cloud play
- stronger computer opponents than typical 4X games

## IP Boundary

Empire of Minds must not copy Civilization or any other commercial game’s:
- name
- visual style
- UI layout
- icons
- leader identities
- lore
- text
- music
- exact mechanics
- progression systems

“Civilization-like” may be used internally as a rough genre reference only. Public-facing wording should describe Empire of Minds as an original turn-based 4X strategy game.

## First Product Goal

The first playable milestone is a very small local vertical slice, not a complete 4X game.

Phase 1 target:
- Godot project
- hex grid
- generated or static test map
- camera movement
- unit selection
- legal movement between hexes
- end turn
- simple rule-based AI turn
- deterministic action log
- basic save/load foundation

## Non-Goals for Early Phases

The early project is not trying to build:
- a full Civilization replacement
- real-time multiplayer
- production-quality art
- complete diplomacy
- complex combat
- full tech tree
- LLM-driven gameplay
- official hosted cloud infrastructure

## Strategic Priorities

1. Make a tiny playable game loop.
2. Keep game rules separate from rendering.
3. Keep AI separate from game rule execution.
4. Keep cloud-authoritative play possible.
5. Avoid licensing decisions that block future commercial release.
6. Use documentation to constrain AI-assisted implementation.
