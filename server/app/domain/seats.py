"""Per-match seat tokens, host credential, and lobby staging metadata (C13a/C14b)."""

from __future__ import annotations

import copy
import secrets
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any

META_SCHEMA_VERSION = 2
META_SCHEMA_VERSION_V1 = 1
SEAT_TOKEN_PREFIX = "st_"
HOST_TOKEN_PREFIX = "ht_"
STATUS_STAGING = "staging"
STATUS_ONGOING = "ongoing"


def _new_seat_token() -> str:
    return f"{SEAT_TOKEN_PREFIX}{secrets.token_hex(16)}"


def _new_host_token() -> str:
    return f"{HOST_TOKEN_PREFIX}{secrets.token_hex(16)}"


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def generate_seats(player_ids: list[int], *, claimed: bool = False) -> list[dict[str, Any]]:
    """One seat row per player_id (sorted for stable storage)."""
    rows: list[dict[str, Any]] = []
    for pid in sorted({int(p) for p in player_ids}):
        rows.append(
            {"actor_id": pid, "token": _new_seat_token(), "claimed": claimed},
        )
    return rows


def build_meta(
    match_id: str,
    player_ids: list[int],
    scenario_id: str = "prototype_play",
    *,
    status: str = STATUS_STAGING,
) -> dict[str, Any]:
    return {
        "match_id": match_id,
        "schema_version": META_SCHEMA_VERSION,
        "status": status,
        "created_at": _utc_now_iso(),
        "scenario_id": str(scenario_id),
        "seats": generate_seats(player_ids, claimed=False),
        "host_token": _new_host_token(),
    }


def match_status(meta: dict[str, Any]) -> str:
    """C13 v1 and legacy rows without status are treated as ongoing."""
    if int(meta.get("schema_version", META_SCHEMA_VERSION_V1)) < META_SCHEMA_VERSION:
        return STATUS_ONGOING
    st = meta.get("status")
    if isinstance(st, str) and st.strip():
        return st.strip()
    return STATUS_ONGOING


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
    """Seat rows for create response (actor_id + token; alpha invite)."""
    seats = meta.get("seats")
    if not isinstance(seats, list):
        return []
    return [
        {"actor_id": int(row["actor_id"]), "token": str(row["token"])}
        for row in seats
        if isinstance(row, dict) and isinstance(row.get("actor_id"), int) and row.get("token")
    ]


def _seat_claimed(row: dict[str, Any], meta: dict[str, Any]) -> bool:
    if int(meta.get("schema_version", META_SCHEMA_VERSION_V1)) < META_SCHEMA_VERSION:
        return True
    return bool(row.get("claimed", False))


def public_seat_summary(meta: dict[str, Any]) -> list[dict[str, Any]]:
    """Token-free seat rows for lobby list."""
    seats = meta.get("seats")
    if not isinstance(seats, list):
        return []
    out: list[dict[str, Any]] = []
    for row in seats:
        if not isinstance(row, dict) or not isinstance(row.get("actor_id"), int):
            continue
        out.append({"actor_id": int(row["actor_id"]), "claimed": _seat_claimed(row, meta)})
    return sorted(out, key=lambda r: int(r["actor_id"]))


def open_seat_count(meta: dict[str, Any]) -> int:
    return sum(1 for s in public_seat_summary(meta) if not bool(s["claimed"]))


def turn_number_from_snapshot(snap: dict[str, Any]) -> int:
    ts = snap.get("turn_state")
    if isinstance(ts, dict) and isinstance(ts.get("turn_number"), int):
        return int(ts["turn_number"])
    return 1


def lobby_summary(match_id: str, meta: dict[str, Any], snap: dict[str, Any]) -> dict[str, Any]:
    seat_rows = public_seat_summary(meta)
    return {
        "match_id": match_id,
        "status": match_status(meta),
        "scenario_id": str(meta.get("scenario_id", snap.get("scenario_id", ""))),
        "created_at": meta.get("created_at", ""),
        "player_count": len(seat_rows),
        "seats": seat_rows,
        "open_seat_count": open_seat_count(meta),
        "revision": int(snap.get("revision", 0)),
        "turn_number": turn_number_from_snapshot(snap),
    }


def summary_has_no_tokens(summary: dict[str, Any]) -> bool:
    forbidden = ("host_token", "seat_token", "token")
    for key in summary.keys():
        if key in forbidden or key.endswith("_token"):
            return False
    for seat in summary.get("seats", []):
        if not isinstance(seat, dict):
            continue
        for key in seat.keys():
            if key in forbidden or "token" in key:
                return False
    return True


@dataclass(frozen=True)
class ClaimSeatResult:
    ok: bool
    reason: str = ""
    meta: dict[str, Any] | None = None
    seat_token: str = ""


def try_claim_seat(meta: dict[str, Any], actor_id: int) -> ClaimSeatResult:
    if match_status(meta) != STATUS_STAGING:
        return ClaimSeatResult(ok=False, reason="match_not_in_staging")
    seats_list = meta.get("seats")
    if not isinstance(seats_list, list):
        return ClaimSeatResult(ok=False, reason="seat_not_found")
    new_meta = copy.deepcopy(meta)
    new_seats: list[dict[str, Any]] = []
    found = False
    token_out = ""
    for row in seats_list:
        if not isinstance(row, dict):
            continue
        r = copy.deepcopy(row)
        if int(r.get("actor_id", -1)) == int(actor_id):
            found = True
            if _seat_claimed(r, meta):
                return ClaimSeatResult(ok=False, reason="seat_already_claimed")
            r["claimed"] = True
            token_out = str(r.get("token", ""))
        new_seats.append(r)
    if not found:
        return ClaimSeatResult(ok=False, reason="seat_not_found")
    if not token_out:
        return ClaimSeatResult(ok=False, reason="seat_not_found")
    new_meta["seats"] = new_seats
    return ClaimSeatResult(ok=True, meta=new_meta, seat_token=token_out)
