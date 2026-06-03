"""C14d-4g: staging faction_id per seat copied into snapshot player_factions on auto-start."""

from __future__ import annotations

from fastapi.testclient import TestClient

from app.domain import factions, seats
from app.storage import file_store
from match_helpers import create_staging_match
from tests.test_auto_start import _claim_token, _faction, _ready


def test_auto_start_snapshot_player_factions_malmo_and_paris(client: TestClient) -> None:
    m = create_staging_match(client, {"scenario_id": "tiny_test", "player_ids": [0, 1]})
    mid = m["match_id"]
    token0 = _claim_token(client, mid, 0)
    token1 = _claim_token(client, mid, 1)
    _faction(client, mid, 0, token0, factions.FACTION_MALMO)
    _faction(client, mid, 1, token1, factions.FACTION_PARIS)
    _ready(client, mid, 0, token0, True)
    r = _ready(client, mid, 1, token1, True)
    assert r.status_code == 200
    assert r.json()["status"] == seats.STATUS_ONGOING

    meta = file_store.read_meta(mid)
    snap = file_store.read_snapshot(mid)
    assert meta is not None and snap is not None
    assert seats.player_factions_from_meta(meta) == {"0": factions.FACTION_MALMO, "1": factions.FACTION_PARIS}
    assert snap["player_factions"] == {"0": factions.FACTION_MALMO, "1": factions.FACTION_PARIS}

    seat0 = next(s for s in meta["seats"] if s["actor_id"] == 0)
    seat1 = next(s for s in meta["seats"] if s["actor_id"] == 1)
    assert seat0["faction_id"] == factions.FACTION_MALMO
    assert seat1["faction_id"] == factions.FACTION_PARIS


def test_player_factions_from_meta_ignores_unclaimed_factions(client: TestClient) -> None:
    m = create_staging_match(client, {"scenario_id": "tiny_test", "player_ids": [0, 1]})
    mid = m["match_id"]
    meta = file_store.read_meta(mid)
    assert meta is not None
    assert seats.player_factions_from_meta(meta) == {}
