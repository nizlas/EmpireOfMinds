"""Per-player explored-tile memory (parity with game/domain/player_visibility_state.gd)."""

from __future__ import annotations

from typing import Any

from app.domain.hex_coord import HexCoord
from app.domain.scenario import Scenario

UNIT_SIGHT_RADIUS = 2
CITY_SIGHT_RADIUS = 2

# owner_id -> set of (q, r)
ExploredByOwner = dict[int, set[tuple[int, int]]]


def empty_for_players(player_ids: list[int]) -> ExploredByOwner:
    uniq = sorted({int(p) for p in player_ids})
    return {pid: set() for pid in uniq}


def _explored_coords_for_actor(scenario: Scenario, actor_id: int) -> set[tuple[int, int]]:
    out: set[tuple[int, int]] = set()
    map_coords = list(scenario.map.coords())
    for u in scenario.units():
        if int(u.owner_id) != int(actor_id):
            continue
        for mc in map_coords:
            if HexCoord.axial_distance(u.position, mc) <= UNIT_SIGHT_RADIUS:
                out.add((mc.q, mc.r))
    for cty in scenario.cities():
        if int(cty.owner_id) != int(actor_id):
            continue
        anchors: list[HexCoord] = [cty.position]
        anchors.extend(list(cty.owned_tiles))
        for ac in anchors:
            for mc in map_coords:
                if HexCoord.axial_distance(ac, mc) <= CITY_SIGHT_RADIUS:
                    out.add((mc.q, mc.r))
    return out


def recompute_for_actor(
    prev: ExploredByOwner,
    scenario: Scenario,
    actor_id: int,
) -> ExploredByOwner:
    new_bo = {oid: set(tiles) for oid, tiles in prev.items()}
    if actor_id not in new_bo:
        new_bo[actor_id] = set()
    new_bo[actor_id] |= _explored_coords_for_actor(scenario, actor_id)
    return new_bo


def seed_all_players(
    prev: ExploredByOwner,
    scenario: Scenario,
    player_ids: list[int],
) -> ExploredByOwner:
    out = prev
    for pid in sorted({int(p) for p in player_ids}):
        out = recompute_for_actor(out, scenario, pid)
    return out


def serialize_visibility(by_owner: ExploredByOwner) -> dict[str, Any]:
    rows: list[dict[str, Any]] = []
    for owner_id in sorted(by_owner.keys()):
        explored = sorted(by_owner[owner_id])
        rows.append(
            {
                "owner_id": owner_id,
                "explored": [[q, r] for q, r in explored],
            }
        )
    return {"by_owner": rows}


def visibility_from_snapshot_dict(
    raw: dict[str, Any] | None,
    scenario: Scenario,
    player_ids: list[int],
) -> ExploredByOwner:
    """Load persisted visibility or seed from current scenario (legacy snapshots)."""
    if not raw or not isinstance(raw.get("by_owner"), list):
        base = empty_for_players(player_ids)
        return seed_all_players(base, scenario, player_ids)
    out = empty_for_players(player_ids)
    for row in raw["by_owner"]:
        if not isinstance(row, dict):
            continue
        oid = int(row["owner_id"])
        if oid not in out:
            out[oid] = set()
        explored = row.get("explored", [])
        if isinstance(explored, list):
            for pair in explored:
                if isinstance(pair, (list, tuple)) and len(pair) >= 2:
                    out[oid].add((int(pair[0]), int(pair[1])))
    return out


def apply_visibility_for_actor(
    snap: dict[str, Any],
    scenario: Scenario,
    actor_id: int,
) -> dict[str, Any]:
    ts = snap["turn_state"]
    players: list[int] = list(ts["players"])  # type: ignore[assignment]
    vis = visibility_from_snapshot_dict(snap.get("visibility_state"), scenario, players)
    vis = recompute_for_actor(vis, scenario, actor_id)
    return {**snap, "visibility_state": serialize_visibility(vis)}
