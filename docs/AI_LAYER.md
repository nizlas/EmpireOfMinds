# Empire of Minds — AI layer (Phase 1.8)

## Overview

Phase 1.8 adds **legal-action enumeration** in the domain, a **rule-based AI** under `game/ai/`, and a **debug input controller** in presentation. The AI never mutates **`Scenario`**, **`Unit`**, **`TurnState`**, or **`GameState`** directly; it only submits **`Dictionary`** actions through **`GameState.try_apply`**, same as human input.

See [ARCHITECTURE_PRINCIPLES.md](ARCHITECTURE_PRINCIPLES.md) (AI layer), [ACTIONS.md](ACTIONS.md), [AI_DESIGN.md](AI_DESIGN.md).

## Components

| Piece | Location | Role |
|--------|----------|------|
| **LegalActions** | [legal_actions.gd](../game/domain/legal_actions.gd) | Pure static **`for_current_player(game_state) -> Array`**: deterministic **`[MoveUnit..., FoundCity..., SetCityProduction..., EndTurn]`** for **`game_state.turn_state.current_player_id()`** (Phase **2.5**), or **`[]`** if **`game_state`** is **`null`**. Legality only: no policy filtering; **`production_progress`** / **`unit_produced`** are never enumerated. |
| **RuleBasedAIPolicy** | [rule_based_ai_policy.gd](../game/ai/rule_based_ai_policy.gd) | Pure static **`has_actor_moved_this_turn(action_log, actor_id)`**: scans **`ActionLog`** **newest to oldest**; first **`end_turn`** ⇒ **false**; first **`move_unit`** with matching **`actor_id`** ⇒ **true**; else **false**. |
| **RuleBasedAIPlayer** | [rule_based_ai_player.gd](../game/ai/rule_based_ai_player.gd) | **`decide(game_state, legal_actions) -> Dictionary`**: **Phase 2.5** — if the current player owns **no** cities, first **`found_city`** in **`legal_actions`**; else if any owned city has **`current_project == null`**, first **`set_city_production`**; else unchanged **1.8b** policy (**`move_unit`** once per segment, then **`end_turn`**). **`FoundCity`** / **`SetCityProduction`** do **not** count as movement. |
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

**LegalActions** builds entries in order:

1. **`MoveUnit`**: units owned by the current player from **`scenario.units()`**, sorted ascending by **`unit.id`**; for each unit, **`MovementRules.legal_destinations`**, sorted by **`(q, r)`** lexicographically.
2. **`FoundCity`**: same unit order; **`FoundCity.make`** at each unit’s tile, kept only when **`FoundCity.validate`** passes (e.g. not **WATER**, not already a city).
3. **`SetCityProduction`**: cities owned by the current player, sorted by **`city.id`**; for each city with **`current_project == null`**, **`produce_unit`** only, kept only when **`SetCityProduction.validate`** passes. No **`"none"`** clears in this enumeration.
4. **`EndTurn.make(current_player_id)`** appended **exactly once**, **last**.

**RuleBasedAIPlayer** (Phase **2.5**) prefers the **city loop** first when legal; then the **first** **`move_unit`** when the current player has **not** yet accepted a **`move_unit`** since the last **`end_turn`** in the log; otherwise it picks **`end_turn`**.

## Phase 1.8b — Turn policy

**One accepted `move_unit` per actor per “turn segment”** (since the last log **`end_turn`**): **`RuleBasedAIPolicy.has_actor_moved_this_turn`** walks the **`ActionLog`** from **newest to oldest** and treats the first **`end_turn`** encountered as the **boundary** of the current segment. If a **`move_unit`** for the queried **`actor_id`** appears **before** that **`end_turn`** in this backward scan, the actor has already moved this segment.

- **No schema change** — policy uses existing **`action_type`**, **`actor_id`**, and log order only.
- **`LegalActions`** still lists **all** legal **`MoveUnit`** destinations and does **not** hide moves after the AI has moved; **Phase 2.5** adds **`found_city`** and **`set_city_production`** in fixed order before **`end_turn`**.
- **Phase 2.5:** more **`KEY_A`** presses are typically needed on the canonical scenario: **`found_city`** → **`set_city_production`** → **`move_unit`** → **`end_turn`** for a player who starts with **no** cities.

## Phase 2.5 — LegalActions + rule-based city loop

**`LegalActions`** enumerates **`found_city`** and **`set_city_production`** (with existing validators only). **No** AI policy inside **`LegalActions`** (e.g. a player with cities still sees every legal **`found_city`** for each unit). **`RuleBasedAIPlayer`** alone applies the preference order above. Engine log types remain **out** of **`legal_actions`**.

End-to-end AI core-loop smoke: [`test_core_loop_ai_smoke.gd`](../game/ai/tests/test_core_loop_ai_smoke.gd).

## Explicitly deferred

- LLM / OpenAI / Ollama adapters.
- Strategic planner, personalities, diplomacy.
- Combat, fog of war, scoring / lookahead.
- Multi-step pathfinding or movement points.
- Background workers, automatic “play AI until end” loops, networking.
- Stochastic or seeded random play.
- **`action_plan`** / multi-action returns from **`decide`** (future interface evolution behind [AI_DESIGN.md](AI_DESIGN.md)).
