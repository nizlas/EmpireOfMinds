# `game/presentation/` — presentation layer (Empire of Minds)

This folder holds **Godot-facing** code: nodes, drawing, and future camera/UI. It is allowed to use `Node`, `Node2D`, `Control`, and canvas APIs.

**Rules**

- The presentation layer must **not** own **authoritative gameplay state**. `HexMap` and other types under `game/domain/` remain the source of truth.
- It must **not** mutate the domain: no writing into `HexMap` internals, no inventing map cells, no replacing domain objects with node state.
- It **consumes the domain read-only** (e.g. `make_tiny_test_map()`, `coords()`, `terrain_at()`) to decide what to draw.
- **Rendered** polygons and labels are **display only**; if something should exist in the game world, it must exist in the domain first.

For coordinate math used only for screen layout, see `hex_layout.gd` and [docs/RENDERING.md](../../docs/RENDERING.md).
