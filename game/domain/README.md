# `game/domain/` — domain layer (Empire of Minds)

This folder holds **game rules and domain data** that must stay independent of how things are drawn or driven by the Godot editor.

**Purpose:** represent concepts such as map topology, hex coordinates, units, and turn state (in later phases) without depending on `Node` subclasses used for presentation.

**Do not** depend on, import, or call into:

- Godot **scene** nodes (`Node`, `Node2D`, `Control`, `Sprite2D`, `Camera2D`, etc.)
- **Rendering** (`CanvasItem`, `_draw`, shaders, viewports for gameplay)
- **UI** and **input** (buttons, click handlers)
- **Networking**, **HTTP**, **file persistence** for gameplay
- **LLM** or external runtimes

Domain scripts should use `RefCounted` / plain data where appropriate, not `Node` lifecycle (`_ready`, `_process`, etc.).
