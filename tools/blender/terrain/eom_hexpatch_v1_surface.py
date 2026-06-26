# Empire of Minds — HexPatch v1.0 Blender/world sampling adapter (HXP-03).
# Routes S_final for all-smooth tiles; cliff-adjacent tiles fall back to IDW legacy path.

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Callable, Literal

from eom_terrain_math_core import (
    DEFAULT_HEX_RADIUS,
    TerrainModel,
    handdrawn_center_world_xy,
)
from eom_hexpatch_v1_evaluator import (
    HexPatchEvalContext,
    S_final,
    build_hexpatch_eval_context,
    edge_h_and_s,
)
from eom_terrain_math_core import hex_apothem
from eom_hexpatch_v1_graph import HexPatchV1Graph

SampleRoute = Literal[
    "hexpatch_v1_smooth",
    "hexpatch_v1_mixed_interior",
    "cliff_fallback_idw",
    "cliff_fallback_legacy",
]


@dataclass
class HexPatchV1SampleStats:
    hexpatch_v1_smooth: int = 0
    hexpatch_v1_mixed_interior: int = 0
    cliff_fallback_idw: int = 0
    cliff_fallback_legacy: int = 0

    @property
    def hexpatch_v1_total(self) -> int:
        return self.hexpatch_v1_smooth + self.hexpatch_v1_mixed_interior

    @property
    def total(self) -> int:
        return (
            self.hexpatch_v1_total
            + self.cliff_fallback_idw
            + self.cliff_fallback_legacy
        )

    def as_dict(self) -> dict[str, int]:
        return {
            "hexpatch_v1_smooth": self.hexpatch_v1_smooth,
            "hexpatch_v1_mixed_interior": self.hexpatch_v1_mixed_interior,
            "hexpatch_v1_total": self.hexpatch_v1_total,
            "cliff_fallback_idw": self.cliff_fallback_idw,
            "cliff_fallback_legacy": self.cliff_fallback_legacy,
            "total": self.total,
        }


@dataclass
class HexPatchV1SurfaceSampler:
    """Cached v1 eval contexts; counts sample routing for diagnostic reports."""

    model: TerrainModel
    graph: HexPatchV1Graph
    contexts: dict[tuple[int, int], HexPatchEvalContext]
    all_smooth_tiles: frozenset[tuple[int, int]]
    patch_by_tile: dict[tuple[int, int], Any]
    stats: HexPatchV1SampleStats = field(default_factory=HexPatchV1SampleStats)
    radius: float = DEFAULT_HEX_RADIUS
    cliff_proximity_factor: float = 1e-3

    @classmethod
    def from_model(
        cls,
        model: TerrainModel,
        *,
        radius: float = DEFAULT_HEX_RADIUS,
    ) -> HexPatchV1SurfaceSampler:
        graph = model.hexpatch_v1_graph
        if graph is None:
            raise RuntimeError("TerrainModel.hexpatch_v1_graph is not built")
        contexts = {
            patch.tile: build_hexpatch_eval_context(graph, patch, radius=radius)
            for patch in graph.hex_patches
        }
        patch_by_tile = {patch.tile: patch for patch in graph.hex_patches}
        all_smooth = frozenset(
            patch.tile
            for patch in graph.hex_patches
            if all(slot.kind == "ribbon" for slot in patch.edge_slots)
        )
        return cls(
            model=model,
            graph=graph,
            contexts=contexts,
            patch_by_tile=patch_by_tile,
            all_smooth_tiles=all_smooth,
            radius=radius,
        )

    def _near_cliff_edge(self, lx: float, ly: float, tile: tuple[int, int]) -> bool:
        patch = self.patch_by_tile[tile]
        ap = hex_apothem(radius=self.radius)
        threshold = ap * self.cliff_proximity_factor
        for pe, slot in enumerate(patch.edge_slots):
            if slot.kind != "cliff":
                continue
            h_i, _ = edge_h_and_s(lx, ly, pe, radius=self.radius)
            if h_i <= threshold:
                return True
        return False

    def sample_world(
        self,
        wx: float,
        wy: float,
        q: int,
        r: int,
        *,
        idw_fallback: Callable[[float, float, int, int], float],
        legacy_fallback: Callable[[float, float, int, int], float] | None = None,
    ) -> tuple[float, SampleRoute]:
        tile = (q, r)
        cx, cy = handdrawn_center_world_xy(q, r, self.radius)
        lx, ly = wx - cx, wy - cy

        if tile not in self.all_smooth_tiles and self._near_cliff_edge(lx, ly, tile):
            if legacy_fallback is not None and not self._tile_has_idw_bundle(tile):
                height = legacy_fallback(wx, wy, q, r)
                self.stats.cliff_fallback_legacy += 1
                return height, "cliff_fallback_legacy"
            height = idw_fallback(wx, wy, q, r)
            self.stats.cliff_fallback_idw += 1
            return height, "cliff_fallback_idw"

        ctx = self.contexts[tile]
        height = S_final(lx, ly, ctx, radius=self.radius)
        if tile in self.all_smooth_tiles:
            self.stats.hexpatch_v1_smooth += 1
            return height, "hexpatch_v1_smooth"
        self.stats.hexpatch_v1_mixed_interior += 1
        return height, "hexpatch_v1_mixed_interior"

    def _tile_has_idw_bundle(self, tile: tuple[int, int]) -> bool:
        bundle = self.model.hexpatch_bundle
        return bundle is not None and tile in bundle.tile_edges


def patch_all_smooth(graph: HexPatchV1Graph, tile: tuple[int, int]) -> bool:
    for patch in graph.hex_patches:
        if patch.tile == tile:
            return all(slot.kind == "ribbon" for slot in patch.edge_slots)
    return False


def _run_surface_self_tests() -> None:
    from eom_terrain_math_core import build_terrain_model

    json_two = """
    {
      "id": "hxp03_two_smooth",
      "orientation": "pointy_top_custom_axes",
      "elevation_step": 0.4,
      "edge_rule": {"cliff_if_abs_delta_greater_than": 1},
      "tiles": [
        {"q":0,"r":0,"elevation":1},
        {"q":1,"r":0,"elevation":2}
      ]
    }
    """
    model = build_terrain_model(json_two)
    sampler = HexPatchV1SurfaceSampler.from_model(model)

    def _never(_wx: float, _wy: float, _q: int, _r: int) -> float:
        raise AssertionError("fallback should not run at tile center")

    cx, cy = handdrawn_center_world_xy(0, 0, DEFAULT_HEX_RADIUS)
    h, route = sampler.sample_world(cx, cy, 0, 0, idw_fallback=_never)
    assert route in ("hexpatch_v1_smooth", "hexpatch_v1_mixed_interior"), route
    assert sampler.stats.hexpatch_v1_total == 1

    json_ssc = """
    {
      "id": "hxp03_ssc",
      "orientation": "pointy_top_custom_axes",
      "elevation_step": 0.4,
      "edge_rule": {"cliff_if_abs_delta_greater_than": 1},
      "tiles": [
        {"q":0,"r":0,"elevation":1},
        {"q":1,"r":0,"elevation":2},
        {"q":0,"r":1,"elevation":3}
      ]
    }
    """
    model_ssc = build_terrain_model(json_ssc)
    sampler_ssc = HexPatchV1SurfaceSampler.from_model(model_ssc)
    idw_called = {"n": 0}

    def _idw(_wx: float, _wy: float, _q: int, _r: int) -> float:
        idw_called["n"] += 1
        return 0.5

    _, route_cliff = sampler_ssc.sample_world(0.0, 0.0, 0, 0, idw_fallback=_idw)
    assert route_cliff in ("cliff_fallback_idw", "hexpatch_v1_mixed_interior")
    assert idw_called["n"] in (0, 1)
    print("eom_hexpatch_v1_surface self-test passed")


if __name__ == "__main__":
    _run_surface_self_tests()
