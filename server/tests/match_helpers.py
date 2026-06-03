"""Shared helpers for seated-match API tests (C13a/C14d-2)."""

from __future__ import annotations

import hashlib
from typing import Any

from fastapi.testclient import TestClient

from app.storage import file_store

SEAT_TOKEN_HEADER = "X-Empire-Seat-Token"

_STAGING_FACTIONS = ("malmo", "vastervik", "paris")


def _match_seed_for_first_player_index(player_count: int, want_index: int = 0) -> str:
    for n in range(10000):
        seed = f"{n:032x}"
        digest = hashlib.sha256(f"{seed}:first_player".encode()).hexdigest()
        if int(digest, 16) % player_count == want_index:
            return seed
    raise RuntimeError("no test seed found for first player index")


def _auto_start_via_staging_api(client: TestClient, match_id: str, player_ids: list[int]) -> None:
    """Claim, faction, and ready all seats so gameplay tests can post actions (C14d-2)."""
    ordered = sorted({int(p) for p in player_ids})
    for i, actor_id in enumerate(ordered):
        claim = client.post(f"/v1/matches/{match_id}/seats/{actor_id}/claim")
        assert claim.status_code == 200, claim.text
        token = str(claim.json()["seat_token"])
        faction_id = _STAGING_FACTIONS[i % len(_STAGING_FACTIONS)]
        headers = {SEAT_TOKEN_HEADER: token}
        fr = client.post(
            f"/v1/matches/{match_id}/seats/{actor_id}/faction",
            json={"faction_id": faction_id},
            headers=headers,
        )
        assert fr.status_code == 200, fr.text
        rr = client.post(
            f"/v1/matches/{match_id}/seats/{actor_id}/ready",
            json={"ready": True},
            headers=headers,
        )
        assert rr.status_code == 200, rr.text


def create_seated_match(
    client: TestClient,
    body: dict[str, Any] | None = None,
    *,
    start_ongoing: bool = True,
) -> dict[str, Any]:
    payload = body if body is not None else {}
    r = client.post("/v1/matches", json=payload)
    assert r.status_code == 200, r.text
    data = r.json()
    host = data["host_token"]
    match_id = data["match_id"]
    player_ids = payload.get("player_ids", [0, 1])
    if start_ongoing and isinstance(player_ids, list) and len(player_ids) >= 1:
        ordered = sorted({int(p) for p in player_ids})
        meta = file_store.read_meta(match_id)
        if meta is not None:
            meta["match_seed"] = _match_seed_for_first_player_index(len(ordered), 0)
            file_store.write_meta(match_id, meta)
        _auto_start_via_staging_api(client, match_id, player_ids)
    return {
        "match_id": match_id,
        "host_token": host,
        "headers": {SEAT_TOKEN_HEADER: host},
        "data": data,
    }


def create_staging_match(client: TestClient, body: dict[str, Any] | None = None) -> dict[str, Any]:
    """Create a match left in staging (no auto-start)."""
    return create_seated_match(client, body, start_ongoing=False)


def post_match_action(
    client: TestClient,
    match_id: str,
    action: dict[str, Any],
    headers: dict[str, str] | None = None,
):
    return client.post(
        f"/v1/matches/{match_id}/actions",
        json=action,
        headers=headers or {},
    )
