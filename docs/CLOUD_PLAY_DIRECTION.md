# Empire of Minds — Cloud play direction (canonical)

**Steering document.** This file locks **long-term** direction for cloud/multiplayer, authority, persistence, sync, and AI—so implementation slices stay coherent. It is **not** a protocol spec, backend design, or phase backlog.

**Related:** [ARCHITECTURE_PRINCIPLES.md](ARCHITECTURE_PRINCIPLES.md), [CLOUD_PLAY.md](CLOUD_PLAY.md), [AI_DESIGN.md](AI_DESIGN.md), [CONTENT_MODEL.md](CONTENT_MODEL.md) (EffectiveRules / RuleSet).

---

## Intent

- **Async-first** cloud play (turns complete without simultaneous presence).
- **Live-feel** when players are online at the same time (updates feel prompt; **no** commitment here to a specific transport or stack).
- **Server-authoritative** cloud rules: canonical state and validation live on the server in cloud mode.
- **Local / server gameplay parity:** same **action vocabulary** and rule concepts; **where** authority runs changes with mode—not the meaning of moves.
- **Deterministic-first:** replay-friendly logs, seeded randomness where used, **EffectiveRules**-aligned content identity for sessions ([CONTENT_MODEL.md](CONTENT_MODEL.md)).
- **Local hotseat is not throwaway:** it should **evolve toward** the same action-shaped domain rules that cloud play will validate.

---

## Actions and intentions, not outcomes

Clients (and AI) submit **actions** or **intentions**—never **resolved outcomes** owned by the client.

| Good (conceptual) | Bad (conceptual) |
|-------------------|------------------|
| `attack_unit(attacker_id, defender_id)` | “warrior_2 takes 6 damage” |

Resolution stays inside **domain rules** on the authority side (local process today; server in cloud mode)—e.g. **`CombatRules.resolve_attack(state, action) -> CombatResult`** as a **shape**, not an implementation mandate here.

---

## Credentials and authority (direction)

Two distinct cloud credentials with **different** authority (decision checkpoint **C14d-0**; detail in [CLOUD_PLAY.md](CLOUD_PLAY.md)):

- **Host-token** = match **owner/admin** (rename, manage staging/settings, delete/abandon, future admin/debug). It is **not** the normal gameplay identity; “host plays all seats” is **dev/debug only**.
- **Seat-token** = **gameplay identity** for exactly one seat/`actor_id` (claim slot, choose faction/civ, ready/unready, act for that actor once ongoing).

## Staging and start (direction)

- **Async, server-persistent staging:** a created match lives server-side as **staging**; players claim seats, choose faction/civ, and ready up **across separate sessions** (no co-presence required).
- **No manual host-start in normal UX:** when all required seats are **claimed + configured + ready**, the **server** auto-transitions staging → **ongoing**.
- **First player is server-chosen and deterministic** (seeded by match identity), **never** client-chosen and **not** implicitly the host.
- **Ongoing async UX** tolerates **manual refresh**; realtime is the later **live-feel** direction, not a v1 requirement.

## Persistence and sync (direction)

- **Action log** + **snapshot** persistence are the supported mental model (versioned; see [ARCHITECTURE_PRINCIPLES.md](ARCHITECTURE_PRINCIPLES.md)).
- **Delta sync** + **snapshot recovery** are the direction for catching up and repair—without prescribing wire formats or storage engines in this document.

---

## AI direction

- AI should use the **same action API** as humans (**legal actions** → **validate** → **apply**); **no** separate “AI mutates state” path.
- **Future LLM** assistance is **adapter-shaped** (suggestions / planning), not a parallel rules engine—see [AI_DESIGN.md](AI_DESIGN.md).

---

## Phased roadmap (labels only)

Order is **conceptual**, not a promise of schedule or scope creep. **No** implementation phases are defined **in this file**; [PHASE_PLAN.md](PHASE_PLAN.md) remains the phase backlog.

| Label | Rough meaning |
|-------|----------------|
| **v0** | Local hotseat (current embryo direction) |
| **v1** | Server-saved state |
| **v2** | Async cloud play |
| **v2.5** | Live-feel realtime-style updates when co-present |
| **v3** | Client-assigned AI (still **actions**, not outcomes) |
| **v4** | LLM-assisted AI (adapters; same authority model) |

---

## Out of scope here

Networking libraries, WebSockets, matchmaking, lobby systems, ECS rewrites, event-sourcing mandates, and concrete cloud vendor choices belong in **future** implementation specs—not in this direction doc.
