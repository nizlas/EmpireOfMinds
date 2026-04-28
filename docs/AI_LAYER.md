# Empire of Minds — AI layer (Phase 1.8)

## Overview

Phase 1.8 adds **legal-action enumeration** in the domain, a **rule-based AI** under `game/ai/`, and a **debug input controller** in presentation. The AI never mutates **`Scenario`**, **`Unit`**, **`TurnState`**, or **`GameState`** directly; it only submits **`Dictionary`** actions through **`GameState.try_apply`**, same as human input.

See [ARCHITECTURE_PRINCIPLES.md](ARCHITECTURE_PRINCIPLES.md) (AI layer), [ACTIONS.md](ACTIONS.md), [AI_DESIGN.md](AI_DESIGN.md).

## Components

| Piece | Location | Role |
|--------|----------|------|
| **LegalActions** | [legal_actions.gd](../game/domain/legal_actions.gd) | Pure static **`for_current_player(game_state) -> Array`**: deterministic **`[MoveUnit..., EndTurn]`** for **`game_state.turn_state.current_player_id()`**, or **`[]`** if **`game_state`** is **`null`**. |
| **RuleBasedAIPolicy** | [rule_based_ai_policy.gd](../game/ai/rule_based_ai_policy.gd) | Pure static **`has_actor_moved_this_turn(action_log, actor_id)`**: scans **`ActionLog`** **newest to oldest**; first **`end_turn`** ⇒ **false**; first **`move_unit`** with matching **`actor_id`** ⇒ **true**; else **false**. |
| **RuleBasedAIPlayer** | [rule_based_ai_player.gd](../game/ai/rule_based_ai_player.gd) | **`decide(game_state, legal_actions) -> Dictionary`**: if **`game_state`** and policy says the current player already moved this turn, return first **`end_turn`** in **`legal_actions`**; else first **`move_unit`**, else first **`end_turn`**, else **`{}`**. |
| **AITurnController** | [ai_turn_controller.gd](../game/presentation/ai_turn_controller.gd) | **`KEY_A`** (no echo): **`LegalActions.for_current_player`** → **`RuleBasedAIPlayer.decide`** → **`try_apply`**; on accept refreshes views and **`TurnLabel`**; empty decision → **`push_warning`** only. |

## Action pipeline

```text
KEY_A (once)
  -> LegalActions.for_current_player(game_state)
  -> RuleBasedAIPlayer.decide(game_state, legal_actions)
  -> if decision nonempty: GameState.try_apply(decision)
  -> on accept: presentation syncs scenario refs, redraw, turn_label.refresh()
```

No **`_process`**, **`Tween`**, **`Timer`**, or chained automation: **one key press = one decision**.

## Deterministic ordering

**LegalActions** builds **`MoveUnit`** entries by:

1. Units owned by the current player from **`scenario.units()`**, sorted ascending by **`unit.id`**.
2. For each unit, **`MovementRules.legal_destinations`**, sorted by **`(q, r)`** lexicographically.
3. **`EndTurn.make(current_player_id)`** appended **last**.

**RuleBasedAIPlayer** picks the **first** **`move_unit`** when the current player has **not** yet accepted a **`move_unit`** since the last **`end_turn`** in the log; otherwise it picks **`end_turn`**.

## Phase 1.8b — Turn policy

**One accepted `move_unit` per actor per “turn segment”** (since the last log **`end_turn`**): **`RuleBasedAIPolicy.has_actor_moved_this_turn`** walks the **`ActionLog`** from **newest to oldest** and treats the first **`end_turn`** encountered as the **boundary** of the current segment. If a **`move_unit`** for the queried **`actor_id`** appears **before** that **`end_turn`** in this backward scan, the actor has already moved this segment.

- **No schema change** — policy uses existing **`action_type`**, **`actor_id`**, and log order only.
- **`LegalActions`** is unchanged and still lists **all** legal **`MoveUnit`** entries plus **`EndTurn`**; humans and the selection overlay are unaffected.
- **Two **`KEY_A`** presses** on the canonical scenario typically complete one AI player’s turn: first press **`MoveUnit`**, second **`EndTurn`**.

## Explicitly deferred

- LLM / OpenAI / Ollama adapters.
- Strategic planner, personalities, diplomacy.
- Combat, production, cities, fog of war.
- Multi-step pathfinding or movement points.
- Background workers, automatic “play AI until end” loops, networking.
- Stochastic or seeded random play.
- **`action_plan`** / multi-action returns from **`decide`** (future interface evolution behind [AI_DESIGN.md](AI_DESIGN.md)).
