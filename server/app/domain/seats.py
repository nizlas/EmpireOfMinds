"""Per-match seat tokens, host credential, and lobby staging metadata (C13a/C14b)."""

from __future__ import annotations

import copy
import secrets
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any

from app.domain import factions

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


def _new_match_seed() -> str:
    return secrets.token_hex(16)


def generate_seats(player_ids: list[int], *, claimed: bool = False) -> list[dict[str, Any]]:
    """One seat row per player_id (sorted for stable storage)."""
    rows: list[dict[str, Any]] = []
    for pid in sorted({int(p) for p in player_ids}):
        rows.append(
            {
                "actor_id": pid,
                "token": _new_seat_token(),
                "claimed": claimed,
                "faction_id": None,
                "ready": False,
            },
        )
    return rows


def short_match_id(match_id: str, *, max_len: int = 12) -> str:
    mid = str(match_id).strip()
    if len(mid) <= max_len:
        return mid
    return mid[:max_len] + "…"


def default_display_name(match_id: str) -> str:
    return f"Match {short_match_id(match_id)}"


def normalize_display_name(match_id: str, raw: Any) -> str:
    if isinstance(raw, str):
        name = raw.strip()
        if name:
            return name
    return default_display_name(match_id)


def display_name_from_meta(meta: dict[str, Any], match_id: str) -> str:
    return normalize_display_name(match_id, meta.get("display_name"))


def build_meta(
    match_id: str,
    player_ids: list[int],
    scenario_id: str = "prototype_play",
    *,
    status: str = STATUS_STAGING,
    display_name: str | None = None,
) -> dict[str, Any]:
    dn = display_name.strip() if isinstance(display_name, str) and display_name.strip() else default_display_name(match_id)
    return {
        "match_id": match_id,
        "schema_version": META_SCHEMA_VERSION,
        "status": status,
        "created_at": _utc_now_iso(),
        "scenario_id": str(scenario_id),
        "display_name": dn,
        "match_seed": _new_match_seed(),
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


def seat_token_actor_id(meta: dict[str, Any], token: str | None) -> int | None:
    """Gameplay seat credential only — host token does not map to a seat (C14d-1)."""
    if not token or not isinstance(token, str):
        return None
    t = token.strip()
    if not t:
        return None
    host = meta.get("host_token")
    if isinstance(host, str) and t == host:
        return None
    seats_list = meta.get("seats")
    if isinstance(seats_list, list):
        for row in seats_list:
            if isinstance(row, dict) and row.get("token") == t:
                aid = row.get("actor_id")
                if isinstance(aid, int):
                    return aid
    return None


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


def player_factions_from_meta(meta: dict[str, Any]) -> dict[str, str]:
    """C14d-4g: actor_id (as str) → staging faction_id for snapshot / client UI."""
    out: dict[str, str] = {}
    for seat in meta.get("seats", []):
        if not isinstance(seat, dict):
            continue
        aid = seat.get("actor_id")
        fid = _seat_faction_id(seat)
        if isinstance(aid, int) and fid:
            out[str(int(aid))] = fid
    return out


def _seat_faction_id(row: dict[str, Any]) -> str | None:
    raw = row.get("faction_id")
    if isinstance(raw, str):
        fid = raw.strip()
        if fid:
            return fid
    return None


def _seat_ready(row: dict[str, Any]) -> bool:
    return bool(row.get("ready", False))


def public_seat_summary(meta: dict[str, Any]) -> list[dict[str, Any]]:
    """Token-free seat rows for lobby list."""
    seats_list = meta.get("seats")
    if not isinstance(seats_list, list):
        return []
    out: list[dict[str, Any]] = []
    for row in seats_list:
        if not isinstance(row, dict) or not isinstance(row.get("actor_id"), int):
            continue
        fid = _seat_faction_id(row)
        out.append(
            {
                "actor_id": int(row["actor_id"]),
                "claimed": _seat_claimed(row, meta),
                "faction_id": fid,
                "ready": _seat_ready(row),
            },
        )
    return sorted(out, key=lambda r: int(r["actor_id"]))


def derive_ready_to_start(meta: dict[str, Any]) -> bool:
    """True while staging when every seat is claimed, has faction, and is ready (C14d-1)."""
    if match_status(meta) != STATUS_STAGING:
        return False
    seats_list = meta.get("seats")
    if not isinstance(seats_list, list) or len(seats_list) < 1:
        return False
    for row in seats_list:
        if not isinstance(row, dict) or not isinstance(row.get("actor_id"), int):
            return False
        if not _seat_claimed(row, meta):
            return False
        if _seat_faction_id(row) is None:
            return False
        if not _seat_ready(row):
            return False
    return True


def open_seat_count(meta: dict[str, Any]) -> int:
    return sum(1 for s in public_seat_summary(meta) if not bool(s["claimed"]))


def turn_number_from_snapshot(snap: dict[str, Any]) -> int:
    ts = snap.get("turn_state")
    if isinstance(ts, dict) and isinstance(ts.get("turn_number"), int):
        return int(ts["turn_number"])
    return 1


def lobby_summary(match_id: str, meta: dict[str, Any], snap: dict[str, Any]) -> dict[str, Any]:
    seat_rows = public_seat_summary(meta)
    summary: dict[str, Any] = {
        "match_id": match_id,
        "display_name": display_name_from_meta(meta, match_id),
        "status": match_status(meta),
        "scenario_id": str(meta.get("scenario_id", snap.get("scenario_id", ""))),
        "created_at": meta.get("created_at", ""),
        "player_count": len(seat_rows),
        "seats": seat_rows,
        "open_seat_count": open_seat_count(meta),
        "ready_to_start": derive_ready_to_start(meta),
        "available_factions": factions.available_factions_public(),
        "revision": int(snap.get("revision", 0)),
        "turn_number": turn_number_from_snapshot(snap),
    }
    if match_status(meta) == STATUS_ONGOING:
        fp = meta.get("first_player_id")
        if isinstance(fp, int):
            summary["first_player_id"] = int(fp)
    return summary


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
    for faction in summary.get("available_factions", []):
        if not isinstance(faction, dict):
            continue
        for key in faction.keys():
            if key in forbidden or "token" in key:
                return False
    return True


@dataclass(frozen=True)
class ClaimSeatResult:
    ok: bool
    reason: str = ""
    meta: dict[str, Any] | None = None
    seat_token: str = ""


@dataclass(frozen=True)
class RenameDisplayNameResult:
    ok: bool
    reason: str = ""
    meta: dict[str, Any] | None = None
    display_name: str = ""


def try_rename_display_name(meta: dict[str, Any], match_id: str, token: str | None, raw_name: Any) -> RenameDisplayNameResult:
    if not token or not str(token).strip():
        return RenameDisplayNameResult(ok=False, reason="missing_seat_token")
    t = str(token).strip()
    host = meta.get("host_token")
    if not isinstance(host, str) or t != host:
        allowed = allowed_actor_ids(meta, t)
        if allowed is None:
            return RenameDisplayNameResult(ok=False, reason="invalid_seat_token")
        return RenameDisplayNameResult(ok=False, reason="not_host")
    new_meta = copy.deepcopy(meta)
    new_meta["display_name"] = normalize_display_name(match_id, raw_name)
    return RenameDisplayNameResult(
        ok=True,
        meta=new_meta,
        display_name=str(new_meta["display_name"]),
    )


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
            r["claimed_at"] = _utc_now_iso()
            token_out = str(r.get("token", ""))
        new_seats.append(r)
    if not found:
        return ClaimSeatResult(ok=False, reason="seat_not_found")
    if not token_out:
        return ClaimSeatResult(ok=False, reason="seat_not_found")
    new_meta["seats"] = new_seats
    return ClaimSeatResult(ok=True, meta=new_meta, seat_token=token_out)


@dataclass(frozen=True)
class SetFactionResult:
    ok: bool
    reason: str = ""
    meta: dict[str, Any] | None = None


@dataclass(frozen=True)
class SetReadyResult:
    ok: bool
    reason: str = ""
    meta: dict[str, Any] | None = None


def _find_seat_row(meta: dict[str, Any], actor_id: int) -> dict[str, Any] | None:
    seats_list = meta.get("seats")
    if not isinstance(seats_list, list):
        return None
    for row in seats_list:
        if isinstance(row, dict) and int(row.get("actor_id", -1)) == int(actor_id):
            return row
    return None


def _faction_taken_by_other(meta: dict[str, Any], faction_id: str, actor_id: int) -> bool:
    seats_list = meta.get("seats")
    if not isinstance(seats_list, list):
        return False
    for row in seats_list:
        if not isinstance(row, dict):
            continue
        if int(row.get("actor_id", -1)) == int(actor_id):
            continue
        if _seat_faction_id(row) == faction_id:
            return True
    return False


def try_set_seat_faction(meta: dict[str, Any], actor_id: int, raw_faction_id: Any) -> SetFactionResult:
    if match_status(meta) != STATUS_STAGING:
        return SetFactionResult(ok=False, reason="match_not_in_staging")
    if not isinstance(raw_faction_id, str) or not raw_faction_id.strip():
        return SetFactionResult(ok=False, reason="faction_unknown")
    faction_id = raw_faction_id.strip()
    if not factions.is_known_faction_id(faction_id):
        return SetFactionResult(ok=False, reason="faction_unknown")
    row = _find_seat_row(meta, actor_id)
    if row is None:
        return SetFactionResult(ok=False, reason="seat_not_found")
    if not _seat_claimed(row, meta):
        return SetFactionResult(ok=False, reason="seat_not_claimed")
    if _faction_taken_by_other(meta, faction_id, actor_id):
        return SetFactionResult(ok=False, reason="faction_taken")
    new_meta = copy.deepcopy(meta)
    new_seats: list[dict[str, Any]] = []
    for seat_row in new_meta.get("seats", []):
        if not isinstance(seat_row, dict):
            continue
        r = copy.deepcopy(seat_row)
        if int(r.get("actor_id", -1)) == int(actor_id):
            if _seat_ready(r):
                r["ready"] = False
                r.pop("ready_at", None)
            r["faction_id"] = faction_id
        new_seats.append(r)
    new_meta["seats"] = new_seats
    return SetFactionResult(ok=True, meta=new_meta)


def try_set_seat_ready(meta: dict[str, Any], actor_id: int, ready: bool) -> SetReadyResult:
    if match_status(meta) != STATUS_STAGING:
        return SetReadyResult(ok=False, reason="match_not_in_staging")
    row = _find_seat_row(meta, actor_id)
    if row is None:
        return SetReadyResult(ok=False, reason="seat_not_found")
    if not _seat_claimed(row, meta):
        return SetReadyResult(ok=False, reason="seat_not_claimed")
    if ready and _seat_faction_id(row) is None:
        return SetReadyResult(ok=False, reason="faction_required")
    new_meta = copy.deepcopy(meta)
    new_seats: list[dict[str, Any]] = []
    for seat_row in new_meta.get("seats", []):
        if not isinstance(seat_row, dict):
            continue
        r = copy.deepcopy(seat_row)
        if int(r.get("actor_id", -1)) == int(actor_id):
            r["ready"] = bool(ready)
            if ready:
                r["ready_at"] = _utc_now_iso()
            else:
                r.pop("ready_at", None)
        new_seats.append(r)
    new_meta["seats"] = new_seats
    return SetReadyResult(ok=True, meta=new_meta)
