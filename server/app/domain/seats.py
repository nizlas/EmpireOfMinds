"""Per-match seat tokens and host credential (C13a). Not gameplay; not accounts."""

from __future__ import annotations

import secrets
from typing import Any

META_SCHEMA_VERSION = 1
SEAT_TOKEN_PREFIX = "st_"
HOST_TOKEN_PREFIX = "ht_"


def _new_seat_token() -> str:
    return f"{SEAT_TOKEN_PREFIX}{secrets.token_hex(16)}"


def _new_host_token() -> str:
    return f"{HOST_TOKEN_PREFIX}{secrets.token_hex(16)}"


def generate_seats(player_ids: list[int]) -> list[dict[str, Any]]:
    """One seat row per player_id (sorted for stable storage)."""
    rows: list[dict[str, Any]] = []
    for pid in sorted({int(p) for p in player_ids}):
        rows.append({"actor_id": pid, "token": _new_seat_token()})
    return rows


def build_meta(match_id: str, player_ids: list[int]) -> dict[str, Any]:
    return {
        "match_id": match_id,
        "schema_version": META_SCHEMA_VERSION,
        "seats": generate_seats(player_ids),
        "host_token": _new_host_token(),
    }


def seat_actor_ids(meta: dict[str, Any]) -> list[int]:
    seats = meta.get("seats")
    if not isinstance(seats, list):
        return []
    out: list[int] = []
    for row in seats:
        if isinstance(row, dict) and isinstance(row.get("actor_id"), int):
            out.append(int(row["actor_id"]))
    return sorted(set(out))


def allowed_actor_ids(meta: dict[str, Any], token: str | None) -> list[int] | None:
    if not token or not isinstance(token, str):
        return None
    t = token.strip()
    if not t:
        return None
    host = meta.get("host_token")
    if isinstance(host, str) and t == host:
        return seat_actor_ids(meta)
    seats = meta.get("seats")
    if isinstance(seats, list):
        for row in seats:
            if isinstance(row, dict) and row.get("token") == t:
                aid = row.get("actor_id")
                if isinstance(aid, int):
                    return [aid]
    return None


def public_seats_from_meta(meta: dict[str, Any]) -> list[dict[str, Any]]:
    """Seat rows for create response (actor_id only; tokens included for alpha invite)."""
    seats = meta.get("seats")
    if not isinstance(seats, list):
        return []
    return [
        {"actor_id": int(row["actor_id"]), "token": str(row["token"])}
        for row in seats
        if isinstance(row, dict) and isinstance(row.get("actor_id"), int) and row.get("token")
    ]
