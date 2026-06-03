"""C14d-4e: staging civilization display names (player-facing; ids unchanged)."""

from __future__ import annotations

from fastapi.testclient import TestClient

from app.domain import factions
from match_helpers import create_staging_match


def test_staging_faction_ids_unchanged() -> None:
    assert factions.FACTION_MALMO == "malmo"
    assert factions.FACTION_VASTERVIK == "vastervik"
    assert factions.FACTION_PARIS == "paris"


def test_canonical_display_names() -> None:
    assert factions.display_name_for_faction(factions.FACTION_MALMO) == factions.DISPLAY_MALMO
    assert factions.display_name_for_faction(factions.FACTION_VASTERVIK) == factions.DISPLAY_VASTERVIK
    assert factions.display_name_for_faction(factions.FACTION_PARIS) == factions.DISPLAY_PARIS


def test_available_factions_public_uses_canonical_names(client: TestClient) -> None:
    m = create_staging_match(client, {"scenario_id": "tiny_test"})
    mid = m["match_id"]
    listed = client.get("/v1/matches").json()
    row = next(r for r in listed["matches"] if r["match_id"] == mid)
    by_id = {f["id"]: f["display_name"] for f in row["available_factions"]}
    assert by_id[factions.FACTION_MALMO] == factions.DISPLAY_MALMO
    assert by_id[factions.FACTION_VASTERVIK] == factions.DISPLAY_VASTERVIK
    assert by_id[factions.FACTION_PARIS] == factions.DISPLAY_PARIS
