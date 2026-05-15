This page is for **playtesters**. It describes what you can try in the **current prototype** in plain language. Design archives and technical detail live elsewhere in `docs/`.

# Empire of Minds Playtest Guide

## What you are testing

You are trying a **small ancient-era slice**: found a **first city**, use the **city production** panel, complete one early **discovery** (**Controlled Fire**) with a temporary shortcut, see the **discovery** message (**Discovery completed**, with **Controlled Fire** and a short story about hearths, habit, and pioneers—plus an **Unlocked** line that should mention **Train Settler**), then **produce a settler**, move them, and **found a second city**.

Empire of Minds is meant to be a turn-based 4X about how civilizations **learn**, with worlds that can emphasize different lessons over time. **Right now** you are not getting a full era or a finished game—only this early **embryo** on the test map.

## Local hotseat prototype — how turns work

This build is the **local hotseat prototype**: **one human** plays **both sides** in the **same** run (there is no online “waiting for another player” in this version).

- **Space** — ends the **current** player’s **turn** (production and growth still tick when the turn advances). If you have a **city** selected and the **City Hub** or **Manage Citizens** view open, **Space** also **closes that city focus** and drops out of planning so the next player’s turn does not inherit your panel.
- **Turn strip** — the small panel in the **lower-right** shows **who is current**, e.g. **Player 0’s turn** or **Player 1’s turn**, and updates as soon as the turn moves.
- **A** — optional: the **rule-based AI** does **one** legal action for **whoever is current** (try-it / debug only — **not** full autopilot).

**Found city → grow → produce → move → Manage Citizens** (when offered) is the core loop to exercise.

## Quick start

1. **Launch** the prototype (your host will tell you how).
2. **Click** the starting **settler** to select them.
3. Press **F** to **found your first city** on the settler’s tile (settler must be selected).
4. **Click** the **city** on the map to open the **city production** panel.
5. Choose **Train Warrior** (or another **Train …** option that is offered) to start production.
6. Press **H** once to complete the **Controlled Fire** discovery. **H is temporary prototype input**, not final design—it stands in until a real discovery flow exists. It only fits this early build after you have founded a city.
7. Read the **discovery** panel (**Discovery completed**, **Controlled Fire**, body text, **Unlocked** list) and press **OK**.
8. **Click** the city again when it has **no** active project (idle).
9. Choose **Train Settler** (it should appear after **Controlled Fire**).
10. Press **Space** to **end your turn** as needed until the **settler** appears (production finishes across turns).
11. **Click** the settler, then **click** a nearby tile the game **allows** for movement.
12. With the settler selected, press **F** again to **found a second city**.

If anything fails, note **where** you were in this list and what you expected to happen.

## What to look for

- Does the **city** panel feel understandable at a glance?
- Does the **discovery** panel read clearly? Does **OK** feel like enough to dismiss it?
- Is it obvious that **Controlled Fire** led to **Train Settler** (words + bullets)?
- Does **Train Settler** → move → **second city** feel like the **start of a loop** you might want to continue?
- On a hex that has **both** a city and a unit, do **repeated clicks** between **city** and **unit** make sense, or feel confusing?

## Current controls and prototype shortcuts

- **Click** a **unit** to select it.
- **Click** a **city** to open **production** (when the build supports it for that city).
- If a **unit** stands on the **same tile** as a **city**, **repeated clicks** on that hex **alternate** between selecting the **city** and the **unit**. This is a **prototype** rule, not promised final UX.
- **F** — **Found a city** while a **settler** (or eligible founder) is **selected**, on their current tile.
- **H** — **current prototype shortcut** to complete **Controlled Fire** after you have **founded a city** (temporary until a real discovery interface exists).
- **Space** — **End turn** for the **current** player; advances production and can **deliver** trained units. If the **City Hub** or **Manage Citizens** was open for a selected city, **Space** **closes** that focus when the turn ends (see **Local hotseat** above).

Other keys may exist for hosts or experiments—treat them as **prototype-only** unless your host says otherwise.

## What works today

- **Founding** at least one **city** from a **settler**.
- Opening a **minimal city production** panel from the map; **Train Warrior**-style options when the rules allow.
- Completing **Controlled Fire** via **H** in this embryo, then seeing the **discovery** panel with **Train Settler** unlocked.
- **Producing** a **settler**, **moving** them, and **founding** another **city**.
- **Cycling** selection between **city** and **unit** on a **shared** hex via **repeated clicks**.

## What does not work yet / known limitations

- No full **research** or **science** screen yet.
- No full **ancient era**—only this narrow playable thread.
- No real **science income** or full **research** loop on the map yet.
- No full **economy**—**food**, **growth**, **happiness**, **trade**, **diplomacy**, or **combat** as you would expect from a finished 4X.
- **AI** does not play this slice in a **smart**, teachable way yet.
- The **city production** panel is **minimal** (layout and copy will change).
- **H** is a **stand-in**, not how discoveries will work later.
- **Shared** city/unit selection is a **temporary** cycling rule.

## What we want feedback on

We care about **clarity**, **surprise** (good or bad), whether **production** options read well, whether **popup** wording helps or hinders, whether **selection** on crowded tiles confuses you, and whether this **tiny loop** makes you **curious** to see more—or where it **stops** feeling worth it.

Short notes and screenshots (if your host wants them) are welcome; **exact steps** (like the numbered list above) help us reproduce issues.

## Where to look if you are a developer

**Developer note:** Steering and mechanics live in internal docs, for example [PHASE_PLAN.md](../PHASE_PLAN.md), [CORE_LOOP.md](../CORE_LOOP.md), [CITIES.md](../CITIES.md), and [CONTENT_MODEL.md](../CONTENT_MODEL.md). Do not expect playtesters to read those.
