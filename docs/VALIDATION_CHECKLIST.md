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

## Phase 5.1.19c — Growth / play loop smoke (prototype map)

Manual validation in the Godot editor (`main.tscn`); **no** new visuals required. Confirms **5.1.19b** growth + **Manage Citizens** + production/delivery loop on the curated island.

- [ ] Launch **Play** / open **`main.tscn`** with the prototype scenario path used by local play.
- [ ] Found capital (**F** or equivalent) at the opening settler position.
- [ ] Open **City Hub**; confirm **Growth:** line shows `stored / threshold (+N/turn)`.
- [ ] **End Turn** repeatedly as P0; confirm **`food_stored`** / growth line climbs when surplus is positive (watch hub or **Action Log** `food_growth_progress`).
- [ ] **Manage Citizens**, click another **owned** non-center tile (planning); return to hub and confirm **`(+N/turn)`** changes **if** the tile differs from AUTO worked choice (if map gives no differing eligible tile, note equality).
- [ ] Continue until **population reaches 2** on the capital (hub **Pop** + optional `city_grew` in log).
- [ ] Queue **settler** production; **End Turn** until settler **delivers**; move settler to a distant legal land hex; found **second city** (**F**).
- [ ] Select second city; confirm **Growth** line appears and **food / stored** begin moving when surplus is positive.

For scripted coverage, run **`scripts/run-godot-tests.ps1`** — includes **`test_growth_play_loop_smoke.gd`** (headless, **Deterministic-first**).

## Phase 5.1.19f — Turn status HUD (hotseat wording + player accent)

Manual check in **`main.tscn`** / local play (**no** domain changes).

- [ ] **Lower-right** **Turn** strip shows **`Player 0's turn`** at start (or equivalent **“now playing”** copy — **no** **“Waiting for Player …”** in local hotseat).
- [ ] **End Turn** → strip shows **`Player 1's turn`**; P1 can act immediately in the **same** run.
- [ ] Panel **orb / border / tint** matches the **same** owner accent family as **empire border** and **unit/city nameplate** strips (teal/cyan vs rose for P0/P1 in the prototype palette).
- [ ] Turn strip stays **visible** and updates **without** opening **City Hub** / city selection.

## Phase 5.2.0 — Local hotseat readiness

Manual validation for **local hotseat prototype** builds (external playtest / “Niklas minigame” style). **No** server, lobby, or remote opponent — one human controls **whichever `TurnState` seat is current**.

- [ ] App starts and **`TurnStatusPanel`** shows **`Player 0's turn`** with the **P0** nameplate/empire accent family.
- [ ] **Capital** can be **founded**, **grown**, and queue **warrior** + **settler** (per current rules).
- [ ] **Space** ends turn; the HUD flips to **`Player 1's turn`** with the **P1** accent.
- [ ] **P1** can act on **P1** units in the **same** app instance without restart.
- [ ] Trying to act on the **wrong** player's unit/city is either **disabled** in UI or fails readably (e.g. **`not_current_player`** in reject paths / log).
- [ ] Selecting an **opponent** city does **not** allow **production** / **Manage Citizens** (hub explains **not your city** or equivalent).
- [ ] **`KEY_A`** is understood as **“AI plays one action for whoever is current”** — **not** autopilot; document for testers ([PLAYTEST_GUIDE.md](player/PLAYTEST_GUIDE.md)).
- [ ] **20–50** **`EndTurn`** cycles can run without **null** dereference or stack trace.
- [ ] **City Hub** **Close** clears city selection (expected today).
- [ ] **`scripts/run-godot-tests.ps1`** is green before handing off a build.

## Phase 5.2.1 — Hotseat: **`EndTurn`** clears **City Hub** selection

Manual check in **`main.tscn`** (**local hotseat prototype**).

- [ ] Select **P0** capital; open **Manage Citizens** (**PLANNING**); press **Space** (**End Turn**).
- [ ] **City Hub** closes (or is hidden); **citizen** markers leave the map (**PLANNING** off).
- [ ] **`TurnStatusPanel`** shows **`Player 1's turn`** (accent matches **P1**).
- [ ] **P1** can select and act immediately without seeing **P0**’s hub from the prior turn.

Validation: **`scripts/run-godot-tests.ps1`** — **`test_hotseat_endturn_selection_clear.gd`**.

## Phase 5.2.2 — Player / contact strip v0 (upper-right seats)

Manual check in **`main.tscn`** (**local hotseat prototype**).

- [ ] **Upper-right** strip shows **P0** and **P1** (one chip per **`TurnState`** seat).
- [ ] **Current** seat has a **stronger** border/fill than the inactive seat(s).
- [ ] Press **Space** (**End Turn**): highlight moves to the **next** player; **no** **“Waiting for Player …”** copy on the strip.
- [ ] Chip **accent** colors match the same **player** tint family as **`TurnStatusPanel`** / **empire** / **nameplates**.
- [ ] Strip stays **separate** from **lower-right** **`TurnStatusPanel`** and **City Hub** on the default viewport.

Validation: **`scripts/run-godot-tests.ps1`** — **`test_player_contact_strip.gd`**.
