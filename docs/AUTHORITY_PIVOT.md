# Empire of Minds — Authority Pivot

**Steering / execution charter.** This document commits the project to moving **canonical gameplay authority** from Godot’s **`game/domain/`** layer to **Python/FastAPI** under [`server/`](../server/). It coordinates [ARCHITECTURE_PRINCIPLES.md](ARCHITECTURE_PRINCIPLES.md), [CLOUD_PLAY.md](CLOUD_PLAY.md), [CLOUD_PLAY_DIRECTION.md](CLOUD_PLAY_DIRECTION.md), and [CLOUD_API_V0.md](CLOUD_API_V0.md).

**Behavioral contract during the pivot:** [ACTIONS.md](ACTIONS.md), [TURNS.md](TURNS.md), [CITIES.md](CITIES.md), [UNITS.md](UNITS.md), and existing **Godot headless tests** under `game/domain/tests/` and `game/presentation/tests/` (where they encode acceptance). **Porting rule:** no semantic change—port as-is first; redesign only in later phases after parity is proven.

**Out of scope until post-cutover:** new gameplay, AI/LLM, realtime, auth, lobby, deployment polish, large frameworks on the server. Unrelated feature work pauses until the **current playable loop** runs through localhost authority.

---

## Target architecture

| Role | Owner |
|------|--------|
| **Canonical rules, validation, apply, action log, snapshots, `state_hash`** | **`server/`** (Python/FastAPI) |
| **Client:** input, rendering, animation, local UI state (selection, camera, panels) | **Godot** (`game/presentation/`, `game/main.gd`) |
| **Local hotseat** | Same Godot client → **`http://127.0.0.1:...`** (or configured base URL) |
| **Cloud play** (later) | Same client → **remote base URL**; **same** HTTP shapes—not a second rules engine |

**Difference between local and cloud:** **address and transport only**, not gameplay architecture.

---

## Dual path and rollback (until cutover is proven)

1. **Legacy path:** Godot **`GameState.try_apply`** + **`game/domain/`** remains in the tree and shippable until an explicit cutover slice is **proven** (tests + real playtest).
2. **Server path:** Authority grows under **`server/`**; Godot eventually consumes **snapshots** and **`POST /v1/matches/{id}/actions`** only.
3. **Rollback:** If the cutover fails, revert the Godot wiring slice and keep using legacy domain authority. **Do not delete `game/domain/`** until post-cutover cleanup ([Slice G](#slice-g-post-cutover)).

A client flag (working name: **`EMPIRE_AUTHORITY=server` | `legacy`**) will gate the server path once wired; see implementation slices below.

---

## Consolidated migration slices

Large, reviewable slices. Each slice lands with **contract tests** (initial state + action(s) + expected snapshot/event/reason). No new gameplay in any slice.

### Slice A — Authority Pivot Docs (this commit)

Update steering docs only. **No** Godot binary behavior change. **No** server behavior change.

### Slice B — Server world model

Port or add on the server: content registries required by the **current** loop, **`hex_coord` / `hex_map`**, prototype map factory parity, **`unit` / `city` / `scenario`**, **`turn_state`**, **action log shape**, **`progress_state`** (and related skeletons) if the snapshot requires it, **snapshot schema v2**, unchanged **`state_hash`** derivation ([CLOUD_API_V0.md](CLOUD_API_V0.md) `canonical_json`).

**Tests:** pytest parity/contract tests for registries and initial snapshot; update existing Cloud 0.1 tests if the snapshot shape changes.

### Slice C — Server core actions

**`move_unit`**, **`attack_unit`**, **`combat_rules`**, **`end_turn`** including **movement refresh** for the new current player, accepted **event** shapes aligned with [ACTIONS.md](ACTIONS.md).

**Tests:** pytest mirroring key GDScript tests; API integration: create match → move → attack → end_turn.

### Slice D — Server current-loop systems

Port **only** systems the **current playtest** already uses: e.g. **`found_city`**, city state needed for that loop, **`set_city_production`**, **`production_tick` / `production_delivery`**, **`food_growth_tick`** if visible in the loop, science/research/progress **only to the extent** already exercised—**avoid** porting subsystems “because they exist” if they are not on the minimal path.

**Tests:** pytest contract: e.g. create match → found city → set production → turns tick → delivery where supported.

### Slice E — Godot read-only server snapshot

Godot **`EMPIRE_AUTHORITY=server`** (or equivalent): load and **render** snapshot from localhost; **no** action submission. Presentation views consume **decoded** server DTOs. Legacy path remains default until F.

### Slice F — Godot localhost action cutover

Controllers submit actions to FastAPI; refresh snapshot/events after accept. **Full current loop** through server (move, attack, HP, CLASH effect timing from events, end_turn, founding/production as included in D). **`EMPIRE_AUTHORITY=server`** becomes the **testable** primary path; **legacy** remains for rollback.

### Slice G — Post-cutover

Server-side **fog** / **redacted snapshots** (if not already done earlier), **`legal_actions`** / **AI** against server, **archive or remove** legacy `game/domain/` after cutover survives real playtesting, remote hosting (separate phase—**not** part of this pivot charter).

---

## Wire and persistence

- **Evolution of [CLOUD_API_V0.md](CLOUD_API_V0.md):** the current **`/v1`** match + snapshot + revision + `state_hash` + events model remains the spine; **action types** and **snapshot fields** grow in slices B–D. Rejected actions stay **unlogged**; **`accepted: false`** with HTTP 200 mirrors **`GameState.try_apply`**.
- **Persistence:** continue file-backed **`snapshot.json`** + **`events.jsonl`** under `server/data/matches/…` (or `EMPIRE_SERVER_DATA_DIR`) unless a later phase moves storage.

---

## References

- **Direction:** [CLOUD_PLAY_DIRECTION.md](CLOUD_PLAY_DIRECTION.md) — actions/intentions not outcomes; server-authoritative cloud.
- **Gameplay schemas:** [ACTIONS.md](ACTIONS.md) — action dictionaries, validation order, log shapes.
- **Current runtime map (pre-cutover):** [CURRENT_ARCHITECTURE.md](CURRENT_ARCHITECTURE.md).
- **Python prototype today:** [server/README.md](../server/README.md), [CLOUD_API_V0.md](CLOUD_API_V0.md).
