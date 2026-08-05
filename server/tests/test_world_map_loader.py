"""N5: server WorldMap model + canonical content loader (parity with Godot).

Goldens mirror game/domain/tests/test_world_map_foundation.gd. Any future
edge-rule change must update the Python loader, the GDScript loader, and the
pinned EDGE_STREAM_DIGEST constant in BOTH test suites together.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

import pytest

from app.domain.map_content_loader import (
    DuplicateMapIdError,
    InvalidContentRootError,
    InvalidMapContentError,
    UnknownMapIdError,
    load_world_map,
    resolve_content_root,
)
from app.domain.world_map import (
    EDGE_CLIFF,
    EDGE_SMOOTH,
    WorldMap,
    compare_tile_coords,
    normalized_edge_key,
)

REFERENCE_MAP_ID = "handdrawn_test_map_full_01"
REFERENCE_HASH = "16cc82c3392c66f1e47273e7da94cf8a804ae9885a051fc81c4b0a9a4261d8c6"
# Shared canonical edge-stream digest; the same constant is pinned in
# game/domain/tests/test_world_map_foundation.gd.
EDGE_STREAM_DIGEST = "b3f613b49ef518cd4ee229ac7e89c12560e145cb235916dbc7d301e6d040cb7f"
TILE_COUNT_GOLDEN = 168
TOTAL_EDGE_GOLDEN = 452
CLIFF_EDGE_GOLDEN = 78
SMOOTH_EDGE_GOLDEN = 374


def _edge_stream_digest(world_map: WorldMap) -> str:
    digest = hashlib.sha256()
    for edge in world_map.all_edges():
        line = (
            f"{edge.tile_a[0]};{edge.tile_a[1]};"
            f"{edge.tile_b[0]};{edge.tile_b[1]};{edge.transition}"
        )
        digest.update(line.encode("utf-8"))
        digest.update(b"\n")
    return digest.hexdigest()


def _minimal_envelope(map_id: str = "fixture_two_tile_01") -> dict[str, Any]:
    return {
        "schema_version": 1,
        "origin": "reference",
        "provenance": "Inline fixture for server loader tests.",
        "logical_map": {
            "id": map_id,
            "orientation": "pointy_top_custom_axes",
            "elevation_step": 0.4,
            "edge_rule": {"default": "smooth", "cliff_if_abs_delta_greater_than": 1},
            "edge_overrides": [],
            "tiles": [
                {"q": 0, "r": 0, "elevation": 1},
                {"q": 1, "r": 0, "elevation": 3},
            ],
        },
    }


def _write_envelope(
    root: Path,
    envelope: dict[str, Any],
    *,
    category: str = "reference",
    filename: str = "fixture.json",
) -> Path:
    path = root / category / filename
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(envelope), encoding="utf-8")
    return path


@pytest.fixture
def content_root(tmp_path, monkeypatch) -> Path:
    root = tmp_path / "maps"
    root.mkdir()
    monkeypatch.setenv("EMPIRE_MAP_CONTENT_DIR", str(root))
    return root


# --- Reference-map goldens (packaged server/content/maps, no env override) ---


def test_reference_map_goldens(monkeypatch) -> None:
    monkeypatch.delenv("EMPIRE_MAP_CONTENT_DIR", raising=False)
    world_map = load_world_map(REFERENCE_MAP_ID)

    assert world_map.identity.map_id == REFERENCE_MAP_ID
    assert world_map.identity.schema_version == 1
    assert world_map.identity.content_hash == REFERENCE_HASH

    assert world_map.tile_count() == TILE_COUNT_GOLDEN
    assert world_map.edge_count() == TOTAL_EDGE_GOLDEN
    assert world_map.cliff_edge_count() == CLIFF_EDGE_GOLDEN
    assert world_map.smooth_edge_count() == SMOOTH_EDGE_GOLDEN
    assert world_map.elevation_range() == (1, 6)
    assert world_map.bounds_q() == (-7, 10)
    assert world_map.bounds_r() == (0, 15)
    assert world_map.elevation_base == 1
    assert world_map.elevation_step == pytest.approx(0.4)


def test_reference_map_edge_stream_digest(monkeypatch) -> None:
    monkeypatch.delenv("EMPIRE_MAP_CONTENT_DIR", raising=False)
    world_map = load_world_map(REFERENCE_MAP_ID)
    assert _edge_stream_digest(world_map) == EDGE_STREAM_DIGEST


def test_reference_map_load_is_deterministic(monkeypatch) -> None:
    monkeypatch.delenv("EMPIRE_MAP_CONTENT_DIR", raising=False)
    first = load_world_map(REFERENCE_MAP_ID)
    second = load_world_map(REFERENCE_MAP_ID)
    assert first.identity == second.identity
    assert first.tile_coords() == second.tile_coords()
    assert first.all_edges() == second.all_edges()
    assert _edge_stream_digest(first) == _edge_stream_digest(second)


# --- Content-root override contract -----------------------------------------


def test_env_override_is_used_exclusively(content_root: Path) -> None:
    _write_envelope(content_root, _minimal_envelope())
    world_map = load_world_map("fixture_two_tile_01")
    assert world_map.tile_count() == 2
    # No fallback: the packaged reference map must NOT be reachable while the
    # override is set.
    with pytest.raises(UnknownMapIdError):
        load_world_map(REFERENCE_MAP_ID)


def test_env_override_missing_dir_fails_without_fallback(tmp_path, monkeypatch) -> None:
    monkeypatch.setenv("EMPIRE_MAP_CONTENT_DIR", str(tmp_path / "does_not_exist"))
    with pytest.raises(InvalidContentRootError):
        resolve_content_root()
    with pytest.raises(InvalidContentRootError):
        load_world_map(REFERENCE_MAP_ID)


def test_env_override_file_path_fails_without_fallback(tmp_path, monkeypatch) -> None:
    not_a_dir = tmp_path / "file.txt"
    not_a_dir.write_text("not a directory", encoding="utf-8")
    monkeypatch.setenv("EMPIRE_MAP_CONTENT_DIR", str(not_a_dir))
    with pytest.raises(InvalidContentRootError):
        load_world_map(REFERENCE_MAP_ID)


# --- Discovery / indexing -----------------------------------------------------


def test_unknown_map_id(content_root: Path) -> None:
    _write_envelope(content_root, _minimal_envelope())
    with pytest.raises(UnknownMapIdError, match="no_such_map"):
        load_world_map("no_such_map")


def test_duplicate_map_id_same_category(content_root: Path) -> None:
    first = _write_envelope(content_root, _minimal_envelope(), filename="aaa.json")
    second = _write_envelope(content_root, _minimal_envelope(), filename="bbb.json")
    with pytest.raises(DuplicateMapIdError) as exc_info:
        load_world_map("fixture_two_tile_01")
    message = str(exc_info.value)
    assert "fixture_two_tile_01" in message
    assert str(first) in message
    assert str(second) in message
    assert message.index(str(first)) < message.index(str(second))


def test_duplicate_map_id_across_categories(content_root: Path) -> None:
    _write_envelope(content_root, _minimal_envelope(), category="reference")
    authored = _minimal_envelope()
    authored["origin"] = "authored"
    _write_envelope(content_root, authored, category="authored")
    with pytest.raises(DuplicateMapIdError):
        load_world_map("fixture_two_tile_01")


def test_origin_folder_mismatch_rejected(content_root: Path) -> None:
    envelope = _minimal_envelope()
    envelope["origin"] = "authored"
    _write_envelope(content_root, envelope, category="reference")
    with pytest.raises(InvalidMapContentError, match="does not match category folder"):
        load_world_map("fixture_two_tile_01")


def test_invalid_utf8_rejected_as_map_content_error(content_root: Path) -> None:
    bad = content_root / "reference" / "bad_bytes.json"
    bad.parent.mkdir(parents=True, exist_ok=True)
    bad.write_bytes(b'\xff\xfe{"schema_version": 1}')
    with pytest.raises(InvalidMapContentError, match="not valid UTF-8"):
        load_world_map("fixture_two_tile_01")


def test_malformed_json_rejected(content_root: Path) -> None:
    bad = content_root / "reference" / "bad.json"
    bad.parent.mkdir(parents=True, exist_ok=True)
    bad.write_text("{not valid json", encoding="utf-8")
    with pytest.raises(InvalidMapContentError, match="Invalid JSON"):
        load_world_map("fixture_two_tile_01")


# --- Strict schema v1 validation ----------------------------------------------


def _mutated(mutate) -> dict[str, Any]:
    envelope = _minimal_envelope()
    mutate(envelope)
    return envelope


@pytest.mark.parametrize(
    ("label", "mutate"),
    [
        ("missing schema_version", lambda e: e.pop("schema_version")),
        ("string schema_version", lambda e: e.update(schema_version="1")),
        ("unsupported schema_version", lambda e: e.update(schema_version=2)),
        ("bool schema_version", lambda e: e.update(schema_version=True)),
        ("missing provenance", lambda e: e.pop("provenance")),
        ("empty provenance", lambda e: e.update(provenance="   ")),
        ("missing logical_map", lambda e: e.pop("logical_map")),
        ("missing id", lambda e: e["logical_map"].pop("id")),
        ("missing orientation", lambda e: e["logical_map"].pop("orientation")),
        (
            "bad orientation",
            lambda e: e["logical_map"].update(orientation="flat_top"),
        ),
        ("missing tiles", lambda e: e["logical_map"].pop("tiles")),
        ("empty tiles", lambda e: e["logical_map"].update(tiles=[])),
        ("missing edge_rule", lambda e: e["logical_map"].pop("edge_rule")),
        (
            "bad edge_rule default",
            lambda e: e["logical_map"]["edge_rule"].update(default="cliff"),
        ),
        (
            "missing threshold",
            lambda e: e["logical_map"]["edge_rule"].pop("cliff_if_abs_delta_greater_than"),
        ),
        (
            "negative threshold",
            lambda e: e["logical_map"]["edge_rule"].update(
                cliff_if_abs_delta_greater_than=-1
            ),
        ),
        (
            "string threshold",
            lambda e: e["logical_map"]["edge_rule"].update(
                cliff_if_abs_delta_greater_than="1"
            ),
        ),
        (
            "fractional tile q",
            lambda e: e["logical_map"]["tiles"][0].update(q=0.5),
        ),
        (
            "string tile elevation",
            lambda e: e["logical_map"]["tiles"][0].update(elevation="1"),
        ),
        (
            "missing tile r",
            lambda e: e["logical_map"]["tiles"][0].pop("r"),
        ),
        (
            "duplicate tiles",
            lambda e: e["logical_map"]["tiles"].append({"q": 0, "r": 0, "elevation": 2}),
        ),
        (
            "zero elevation_step",
            lambda e: e["logical_map"].update(elevation_step=0.0),
        ),
        (
            "string elevation_step",
            lambda e: e["logical_map"].update(elevation_step="0.4"),
        ),
        (
            "null edge_overrides",
            lambda e: e["logical_map"].update(edge_overrides=None),
        ),
        (
            "object edge_overrides",
            lambda e: e["logical_map"].update(edge_overrides={}),
        ),
    ],
)
def test_envelope_violation_rejected(content_root: Path, label: str, mutate) -> None:
    _write_envelope(content_root, _mutated(mutate))
    with pytest.raises(InvalidMapContentError):
        load_world_map("fixture_two_tile_01")


def test_nonempty_edge_overrides_rejected(content_root: Path) -> None:
    envelope = _minimal_envelope()
    envelope["logical_map"]["edge_overrides"] = [
        {"edge": [{"q": 0, "r": 0}, {"q": 1, "r": 0}], "transition": "cliff"}
    ]
    _write_envelope(content_root, envelope)
    with pytest.raises(InvalidMapContentError, match="reserved and must be empty"):
        load_world_map("fixture_two_tile_01")


# --- Edge derivation + WorldMap unit behavior ----------------------------------


def test_two_tile_fixture_derives_one_cliff_edge(content_root: Path) -> None:
    # |1 - 3| = 2 > threshold 1 -> cliff (strict >).
    _write_envelope(content_root, _minimal_envelope())
    world_map = load_world_map("fixture_two_tile_01")
    assert world_map.edge_count() == 1
    edge = world_map.edge_between((0, 0), (1, 0))
    assert edge.transition == EDGE_CLIFF
    assert edge.tile_a == (0, 0)
    assert edge.tile_b == (1, 0)


def test_delta_equal_to_threshold_is_smooth(content_root: Path) -> None:
    envelope = _minimal_envelope()
    envelope["logical_map"]["tiles"] = [
        {"q": 0, "r": 0, "elevation": 1},
        {"q": 1, "r": 0, "elevation": 2},
    ]
    _write_envelope(content_root, envelope)
    world_map = load_world_map("fixture_two_tile_01")
    edge = world_map.edge_between((0, 0), (1, 0))
    assert edge.transition == EDGE_SMOOTH
    assert world_map.smooth_edge_count() == world_map.edge_count() - world_map.cliff_edge_count()


def test_normalized_edge_key_ordering() -> None:
    assert normalized_edge_key((1, 0), (0, 0)) == "0,0|1,0"
    assert normalized_edge_key((0, 0), (1, 0)) == "0,0|1,0"
    assert normalized_edge_key((0, 1), (0, -1)) == "0,-1|0,1"
    assert compare_tile_coords((0, 0), (0, 0)) == 0
    assert compare_tile_coords((-1, 5), (0, 0)) == -1
    assert compare_tile_coords((0, 1), (0, 0)) == 1
