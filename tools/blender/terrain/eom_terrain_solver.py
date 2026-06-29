# Empire of Minds — TerrainSolver framework (TS-01).
# Pluggable height backends over TerrainModel; behavior-preserving wrappers only.

from __future__ import annotations

from abc import ABC, abstractmethod
from enum import Enum
from typing import Any, Callable

from eom_terrain_math_core import (
    DEFAULT_HEX_RADIUS,
    DEFAULT_SURFACE_SUBDIVISIONS,
    pos_key,
    sample_smooth_domain_surface_world,
    shared_edge_z_at,
)
from eom_hexpatch_surface import sample_hexpatch_surface_world


class TerrainBackend(str, Enum):
    idw = "idw"
    hexpatch_v1 = "hexpatch_v1"
    legacy_sector = "legacy_sector"
    global_biharmonic = "global_biharmonic"
    variational_spline = "variational_spline"
    fem_thin_plate = "fem_thin_plate"


class TerrainSolver(ABC):
    backend: TerrainBackend

    @abstractmethod
    def prepare(self, model: Any, *, radius: float = DEFAULT_HEX_RADIUS) -> None:
        """Precompute solver state (no-op for analytic backends)."""

    @abstractmethod
    def sample_world(
        self,
        wx: float,
        wy: float,
        q: int,
        r: int,
        *,
        sector: int | None = None,
        at_corner: bool = False,
        at_sector_outer_edge: bool = False,
        idw_fallback: Callable[..., float] | None = None,
        legacy_fallback: Callable[..., float] | None = None,
    ) -> float:
        """Sample top-surface height at world (wx, wy) owned by tile (q, r)."""

    @property
    def stats(self) -> dict[str, int] | None:
        return None


class IdwTerrainSolver(TerrainSolver):
    backend = TerrainBackend.idw

    def __init__(self) -> None:
        self._model: Any | None = None
        self._radius: float = DEFAULT_HEX_RADIUS

    def prepare(self, model: Any, *, radius: float = DEFAULT_HEX_RADIUS) -> None:
        self._model = model
        self._radius = radius

    def sample_world(
        self,
        wx: float,
        wy: float,
        q: int,
        r: int,
        *,
        sector: int | None = None,
        at_corner: bool = False,
        at_sector_outer_edge: bool = False,
        idw_fallback: Callable[..., float] | None = None,
        legacy_fallback: Callable[..., float] | None = None,
    ) -> float:
        assert self._model is not None
        return sample_hexpatch_surface_world(
            wx,
            wy,
            q,
            r,
            self._model,
            radius=self._radius,
        )


class LegacySectorTerrainSolver(TerrainSolver):
    backend = TerrainBackend.legacy_sector

    def __init__(self) -> None:
        self._model: Any | None = None
        self._radius: float = DEFAULT_HEX_RADIUS

    def prepare(self, model: Any, *, radius: float = DEFAULT_HEX_RADIUS) -> None:
        self._model = model
        self._radius = radius

    def sample_world(
        self,
        wx: float,
        wy: float,
        q: int,
        r: int,
        *,
        sector: int | None = None,
        at_corner: bool = False,
        at_sector_outer_edge: bool = False,
        idw_fallback: Callable[..., float] | None = None,
        legacy_fallback: Callable[..., float] | None = None,
    ) -> float:
        assert self._model is not None
        wz = sample_smooth_domain_surface_world(
            wx,
            wy,
            q,
            r,
            self._model,
            radius=self._radius,
            sector=sector,
            at_sector_corner=at_corner,
        )
        if at_sector_outer_edge:
            shared_z = shared_edge_z_at(self._model, pos_key(wx, wy))
            if shared_z is not None:
                wz = shared_z
        return wz


class HexPatchV1TerrainSolver(TerrainSolver):
    backend = TerrainBackend.hexpatch_v1

    def __init__(self) -> None:
        self._model: Any | None = None
        self._radius: float = DEFAULT_HEX_RADIUS
        self._sampler: Any | None = None

    def prepare(self, model: Any, *, radius: float = DEFAULT_HEX_RADIUS) -> None:
        from eom_hexpatch_v1_surface import HexPatchV1SurfaceSampler

        self._model = model
        self._radius = radius
        self._sampler = HexPatchV1SurfaceSampler.from_model(model, radius=radius)

    def sample_world(
        self,
        wx: float,
        wy: float,
        q: int,
        r: int,
        *,
        sector: int | None = None,
        at_corner: bool = False,
        at_sector_outer_edge: bool = False,
        idw_fallback: Callable[..., float] | None = None,
        legacy_fallback: Callable[..., float] | None = None,
    ) -> float:
        assert self._model is not None
        assert self._sampler is not None

        if idw_fallback is None:
            model = self._model
            radius = self._radius

            def idw_fallback(
                fwx: float,
                fwy: float,
                fq: int,
                fr: int,
            ) -> float:
                return sample_hexpatch_surface_world(
                    fwx,
                    fwy,
                    fq,
                    fr,
                    model,
                    radius=radius,
                )

        if legacy_fallback is None:
            model = self._model
            radius = self._radius
            fsector = sector
            fat_corner = at_corner
            outer_edge = at_sector_outer_edge

            def legacy_fallback(
                fwx: float,
                fwy: float,
                fq: int,
                fr: int,
                *,
                fsector: int | None = fsector,
                fat_corner: bool = fat_corner,
            ) -> float:
                wz_legacy = sample_smooth_domain_surface_world(
                    fwx,
                    fwy,
                    fq,
                    fr,
                    model,
                    radius=radius,
                    sector=fsector,
                    at_sector_corner=fat_corner,
                )
                if outer_edge:
                    shared_z = shared_edge_z_at(model, pos_key(fwx, fwy))
                    if shared_z is not None:
                        wz_legacy = shared_z
                return wz_legacy

        height, _route = self._sampler.sample_world(
            wx,
            wy,
            q,
            r,
            idw_fallback=idw_fallback,
            legacy_fallback=legacy_fallback,
        )
        return height

    @property
    def stats(self) -> dict[str, int] | None:
        if self._sampler is None:
            return None
        return self._sampler.stats.as_dict()


def resolve_terrain_solver_backend(
    *,
    use_fem_thin_plate_surface: bool = False,
    use_variational_spline_surface: bool = False,
    use_global_biharmonic_surface: bool = False,
    use_hexpatch_v1_surface: bool,
    use_hexpatch_surface: bool,
    explicit_backend: TerrainBackend | str | None = None,
) -> TerrainBackend:
    if explicit_backend is not None:
        return TerrainBackend(explicit_backend)
    if use_fem_thin_plate_surface:
        return TerrainBackend.fem_thin_plate
    if use_variational_spline_surface:
        return TerrainBackend.variational_spline
    if use_global_biharmonic_surface:
        return TerrainBackend.global_biharmonic
    if use_hexpatch_v1_surface:
        return TerrainBackend.hexpatch_v1
    if use_hexpatch_surface:
        return TerrainBackend.idw
    return TerrainBackend.legacy_sector


def make_terrain_solver(
    backend: TerrainBackend | str,
    model: Any,
    *,
    radius: float = DEFAULT_HEX_RADIUS,
    baseline: Any | None = None,
    subdiv: int | None = None,
    global_biharmonic_tension: float = 0.5,
    global_biharmonic_iterations: int = 250,
    global_biharmonic_relaxation_omega: float = 0.4,
) -> TerrainSolver:
    resolved = TerrainBackend(backend)
    if resolved is TerrainBackend.global_biharmonic:
        from eom_terrain_global_biharmonic import GlobalBiharmonicTerrainSolver

        GlobalBiharmonicTerrainSolver.backend = TerrainBackend.global_biharmonic  # type: ignore[attr-defined]
        solver = GlobalBiharmonicTerrainSolver(
            tension=global_biharmonic_tension,
            max_iterations=global_biharmonic_iterations,
            relaxation_omega=global_biharmonic_relaxation_omega,
        )
        if subdiv is None:
            subdiv = DEFAULT_SURFACE_SUBDIVISIONS
        solver.prepare(model, radius=radius, baseline=baseline, subdiv=subdiv)
        return solver
    if resolved is TerrainBackend.variational_spline:
        from eom_terrain_variational_spline import VariationalSplineTerrainSolver

        VariationalSplineTerrainSolver.backend = TerrainBackend.variational_spline  # type: ignore[attr-defined]
        solver = VariationalSplineTerrainSolver()
        solver.prepare(model, radius=radius)
        return solver
    if resolved is TerrainBackend.fem_thin_plate:
        from eom_terrain_fem_thin_plate import FemThinPlateTerrainSolver

        FemThinPlateTerrainSolver.backend = TerrainBackend.fem_thin_plate  # type: ignore[attr-defined]
        solver = FemThinPlateTerrainSolver()
        if subdiv is None:
            subdiv = DEFAULT_SURFACE_SUBDIVISIONS
        solver.prepare(model, radius=radius, baseline=baseline, subdiv=subdiv)
        return solver
    if resolved is TerrainBackend.idw:
        solver: TerrainSolver = IdwTerrainSolver()
    elif resolved is TerrainBackend.hexpatch_v1:
        solver = HexPatchV1TerrainSolver()
    elif resolved is TerrainBackend.legacy_sector:
        solver = LegacySectorTerrainSolver()
    else:
        raise ValueError(f"unknown terrain backend: {resolved!r}")
    solver.prepare(model, radius=radius)
    return solver


def sampler_label_for_backend(backend: TerrainBackend) -> str:
    if backend is TerrainBackend.fem_thin_plate:
        return "FEM cotan thin-plate on cliff-cut mesh (TS-04)"
    if backend is TerrainBackend.variational_spline:
        return "thin-plate variational spline (TS-03 affine-precision)"
    if backend is TerrainBackend.global_biharmonic:
        return "global fair-surface / biharmonic-with-tension (TS-02 diagnostic)"
    if backend is TerrainBackend.hexpatch_v1:
        return "hexpatch v1.0 S_final (HXP-03 diagnostic)"
    if backend is TerrainBackend.idw:
        return "hexpatch IDW (§§12–13)"
    if backend is TerrainBackend.legacy_sector:
        return "legacy sector/radial"
    return str(backend.value)


def _run_solver_self_tests() -> None:
    from eom_terrain_math_core import build_terrain_model, handdrawn_center_world_xy

    json_two = """
    {
      "id": "ts01_two_smooth",
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
    radius = DEFAULT_HEX_RADIUS

    idw = make_terrain_solver(TerrainBackend.idw, model, radius=radius)
    cx, cy = handdrawn_center_world_xy(0, 0, radius)
    h_idw = idw.sample_world(cx, cy, 0, 0)
    assert isinstance(h_idw, float)

    legacy = make_terrain_solver(TerrainBackend.legacy_sector, model, radius=radius)
    h_legacy = legacy.sample_world(cx, cy, 0, 0, sector=0, at_corner=False)
    assert isinstance(h_legacy, float)

    v1 = make_terrain_solver(TerrainBackend.hexpatch_v1, model, radius=radius)
    h_v1 = v1.sample_world(cx, cy, 0, 0)
    assert isinstance(h_v1, float)
    assert v1.stats is not None and v1.stats.get("total", 0) >= 1

    try:
        from eom_terrain_global_biharmonic import _minimal_baseline_stub

        gb = make_terrain_solver(
            TerrainBackend.global_biharmonic,
            model,
            radius=radius,
            baseline=_minimal_baseline_stub(radius),
            subdiv=4,
            global_biharmonic_iterations=30,
        )
        h_gb = gb.sample_world(cx, cy, 0, 0)
        assert isinstance(h_gb, float)
        assert gb.stats is not None
        assert gb.stats["max_center_constraint_error"] < 1e-9
    except ImportError:
        pass

    vs = make_terrain_solver(TerrainBackend.variational_spline, model, radius=radius)
    h_vs = vs.sample_world(cx, cy, 0, 0)
    assert isinstance(h_vs, float)
    assert vs.stats is not None
    assert vs.stats["max_center_interpolation_error"] < 1e-6
    assert vs.stats["affine_constant_ok"]
    assert vs.stats["affine_planar_ok"]

    try:
        from eom_terrain_fem_thin_plate import _minimal_baseline_stub

        fem = make_terrain_solver(
            TerrainBackend.fem_thin_plate,
            model,
            radius=radius,
            baseline=_minimal_baseline_stub(radius),
            subdiv=4,
        )
        h_fem = fem.sample_world(cx, cy, 0, 0)
        assert isinstance(h_fem, float)
        assert fem.stats is not None
        assert fem.stats["max_center_interpolation_error"] < 1e-5
        assert fem.stats["affine_constant_ok"]
        assert fem.stats["affine_planar_ok"]
        assert fem.stats["cliff_cut_two_tile_ok"]
    except ImportError:
        pass

    resolved = resolve_terrain_solver_backend(
        use_fem_thin_plate_surface=False,
        use_variational_spline_surface=False,
        use_global_biharmonic_surface=False,
        use_hexpatch_v1_surface=False,
        use_hexpatch_surface=True,
    )
    assert resolved is TerrainBackend.idw

    print("eom_terrain_solver self-test passed")


if __name__ == "__main__":
    _run_solver_self_tests()
