# Empire of Minds — World coordinate contract

**Status:** approved target architecture (slice **N0**, 2026-08). The **projection module** (`HexWorldProjection`) and **`WorldMap`** loader under `game/domain/world/` implement this contract as **non-rendered foundation code** (slice **N1**, 2026-08). Gameplay wiring, server runtime, and 3D presentation remain future slices — see [MAP_MODEL.md](MAP_MODEL.md) and [CURRENT_ARCHITECTURE.md](CURRENT_ARCHITECTURE.md).

Related: axial cell identity (orientation-neutral) — [HEX_COORDINATES.md](HEX_COORDINATES.md). Map content ownership — [MAP_CONTENT.md](MAP_CONTENT.md).

---

## Stored values vs embeddings

Axial coordinates `(q, r)` are **orientation-neutral integers** that identify cells on a hex lattice. They do not, by themselves, define:

- pointy-top vs flat-top hex shape,
- which direction is geographic north,
- screen direction,
- or world-axis placement.

Those properties belong to an **embedding**: a deterministic map from axial values into a target space (Godot world coordinates, Blender world coordinates, or an image/drawing).

The Empire of Minds contract defines **one canonical runtime embedding** (Godot world space, below). Other embeddings exist only behind explicit, documented boundaries:

| Space | Role |
|-------|------|
| **Stored payload `(q, r)`** | Authoritative tile identity; orientation-neutral |
| **Legacy hand drawing (external)** | Historical flat-top presentation; `+q` down-left, `+r` up-left in image space — **not** a runtime authority |
| **Blender tooling frame** | TS-08 reference implementation; Z-up; internal baseline reflection is private to Blender code |
| **Godot runtime world** | Canonical gameplay/presentation embedding (this document) |

Do not conflate these spaces. Runtime gameplay code must never reference Blender-internal baseline coordinates or the legacy drawing’s image axes.

---

## Godot world-axis convention

| Axis | Meaning |
|------|---------|
| **+X** | geographic east |
| **−X** | geographic west |
| **−Z** | geographic north |
| **+Z** | geographic south |
| **+Y** | physical elevation / up |

The horizontal ground plane is **X/Z**. Geographic north is **fixed in world space** and does **not** rotate with the camera.

**Hex orientation under this embedding:** pointy-top — one vertex of each hex faces geographic north (`−Z`), the opposite vertex faces south (`+Z`). Flat edges face east and west.

**Camera independence:** the orbit camera holds only its own transform (yaw, pitch, distance, target). Camera orientation never changes map coordinates, tile identity, geographic directions, or the formulas below.

---

## Canonical direction deltas

Neighbor offsets match [HEX_COORDINATES.md](HEX_COORDINATES.md) / `HexCoord` (E through SE):

| Direction | (Δq, Δr) | World displacement (ΔX, ΔZ) at scale S |
|-----------|----------|------------------------------------------|
| E | (+1, 0) | (+√3·S, 0) |
| NE | (+1, −1) | (+√3/2·S, −1.5·S) |
| NW | (0, −1) | (−√3/2·S, −1.5·S) |
| W | (−1, 0) | (−√3·S, 0) |
| SW | (−1, +1) | (−√3/2·S, +1.5·S) |
| SE | (0, +1) | (+√3/2·S, +1.5·S) |

This corresponds to the standard axial pointy-top layout with `+r` toward geographic south-east.

---

## Hex size and spacing

- **`S`** = hex **circumradius** (center to corner), in world units.
- **Approved value: `S = 1.0`** (= Blender `DEFAULT_HEX_RADIUS` in the TS-08 reference chain). Keeps the reference dataset and elevation step at accepted proportions.
- Center-to-neighbor distance: **`√3 · S`**.
- Row pitch (adjacent rows in the `+r` direction): **`1.5 · S`**.

`S` is owned by one domain module (`HexWorldProjection`, planned slice N1). Map files supply **`elevation_step`** per map; see [Elevation](#elevation-source-precision-and-world-y).

---

## Axial center → world position (forward)

For tile `(q, r)` with integer elevation `e`:

```
world_x = S · √3 · (q + r / 2)
world_z = S · 1.5 · r
world_y = (e − elevation_base) · elevation_step
```

**Origin policy:** axial `(0, 0)` is centered at world `(0, world_y, 0)` in X/Z. The reference map is **not recentered** — camera framing adjusts to map bounds instead.

**Unit facing convention:** identity rotation at spawn = facing **−Z** (north), matching Godot’s default forward (−Z).

---

## World position → axial (inverse)

Given ground-plane coordinates `(world_x, world_z)`:

```
qf = (√3/3 · world_x − 1/3 · world_z) / S
rf = (2/3 · world_z) / S
```

Convert fractional axial `(qf, rf)` to integer `(q, r)` via **cube coordinates** and rounding:

```
cube_q = qf
cube_r = rf
cube_s = −qf − rf
(round q, round r, round s); if any sum ≠ 0, reset the component with largest rounding error
```

Use this inverse for top-surface picking where the hit projects injectively onto a single tile footprint. **Do not** use plain X/Z cube-rounding alone for vertical cliff faces — see [MAP_MODEL.md](MAP_MODEL.md) and the cliff-picking decision in [DECISION_LOG.md](DECISION_LOG.md).

---

## Elevation source precision and world Y

Separate these concepts:

| Concept | Source | Notes |
|---------|--------|-------|
| **Per-tile elevation** | `logical_map.tiles[].elevation` (integer) | Authoritative source value |
| **`elevation_step`** | `logical_map.elevation_step` (float) | Present in the reference payload (**0.4**) |
| **`elevation_base`** | Optional payload field; **absent** in the current reference file | Effective base **1** comes from the parser default in `eom_terrain_math_core.py` (`DEFAULT_ELEVATION_BASE = 1`) until an explicit payload field is added |
| **`world_y` (rules height)** | `(elevation − elevation_base) · elevation_step` | Domain/rules-level tile height |
| **Sampled surface Y** | Continuous TS-08 terrain mesh | Presentation refinement for foot placement and anchors; **never** gameplay authority |

Adding explicit `"elevation_base": 1` to the canonical JSON is an **approved future hygiene change** (subject to TS-08 regression validation). It is **not** part of slice N0.

**Pinned examples** (base = 1, step = 0.4):

| elevation | world_y |
|-----------|---------|
| 1 | 0.0 |
| 4 | 1.2 |
| 6 | 2.0 |

---

## Worked placement examples (S = 1.0)

Axial center positions in world X/Z (elevation examples use base 1, step 0.4):

| Tile (q, r) | world_x | world_z | Notes |
|-------------|---------|---------|-------|
| (0, 0) | 0 | 0 | origin |
| (1, 0) | √3 ≈ 1.732 | 0 | due east of (0,0) |
| (0, 1) | √3/2 ≈ 0.866 | 1.5 | south-east |
| (1, −1) | √3/2 ≈ 0.866 | −1.5 | north-east |
| (0, −1) | −√3/2 ≈ −0.866 | −1.5 | north-west |
| (−1, 0) | −√3 ≈ −1.732 | 0 | due west |

---

## Default strategic home view

The canonical **home** orbit-camera view frames the map with **screen-up ≈ geographic north** (−Z). Exact pitch, distance, and margin are presentation parameters owned by the camera module; they do not alter the contract above.

---

## Import boundary — reference payload

For `handdrawn_test_map_full_01`:

- **Value transform at load:** **identity** — stored `(q, r)` values are used directly as canonical axial coordinates.
- **World embedding:** the formulas in this document (which match the accepted Blender TS-08 placement up to the axis rename below).
- **Legacy drawing:** the external hand drawing used a flat-top image embedding (`+q` down-left, `+r` up-left). That embedding differs from the canonical runtime embedding but does **not** require transforming stored coordinates — the drawing never entered the repository as authoritative data.

The payload field `"orientation": "pointy_top_custom_axes"` is a **historical label**, not a runtime branch. Orientation is defined by embeddings, not by this string. A future schema may introduce a properly named field such as `coordinate_convention`; renaming the existing string to `axial_v1` is **not** approved (`axial_v1` is not an orientation name).

---

## Blender ↔ Godot axis conversion

Blender tooling uses **Z-up** with top-view **+Y treated as north** during TS-08 review. Conversion at the **reference-dataset export boundary only**:

```
(x_g, y_g, z_g) = (x_b, z_b, −y_b)
```

- `x_b, y_b` = Blender horizontal placement from the TS-08 chain
- `z_b` = Blender vertical (elevation)

**Blender-internal baseline reflection** (`handdrawn_to_baseline_axial(q,r) = (q+r, −r)`) is private to Blender tooling (`eom_terrain_math_core.py`). It must **not** leak into Godot gameplay, server rules, or picking logic. Godot receives coordinates only through the canonical loader → `WorldMap` path after the identity import boundary.

---

## Verification status

The worked examples and import-boundary identity claim are derived from repository code (`eom_terrain_math_core.py`, `HexCoord`, canonical JSON payload structure). **No runtime Godot verification has been performed** as of slice N0 — headless tests are planned for slice N1.
