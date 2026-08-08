"""N8b world production rules data (server-owned, WorldMap path only).

Flat yields v2 (locked 2026-08-06, docs/PHASE_PLAN.md N8b): production is a
constant **1 per city on each accepted owner end_turn**. The constant is
established here so N8c can tick from rules data without reading tile or
elevation properties. N8b itself does not accrue progress — processing is
N8c. Explicitly a balance placeholder, not final balance.

Separate from legacy city_yields / production_rules (those import Scenario /
HexMap terrain and worked-tile math).
"""

from __future__ import annotations

# Flat production yield applied per city on each accepted owner end_turn (N8c).
FLAT_PRODUCTION_PER_CITY: int = 1
