"""Generic mesh measurements shared by the asset validators.

Nothing here knows what a shield or a humanoid is. These are the primitives the
domain-specific validators build their judgements from, kept separate so the same
measurement can be reused and unit-tested on synthetic geometry.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np


@dataclass(frozen=True)
class Frame:
    """A local orthonormal frame ordered by descending extent."""

    center: np.ndarray  # (3,)
    axes: np.ndarray  # (3, 3), rows are unit vectors, row 0 = longest extent
    extents: np.ndarray  # (3,) full extent along each axis

    def project(self, points: np.ndarray) -> np.ndarray:
        """Coordinates of `points` in this frame."""
        return (points - self.center) @ self.axes.T


def bounds(points: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    return points.min(axis=0), points.max(axis=0)


def triangle_areas(vertices: np.ndarray, triangles: np.ndarray) -> np.ndarray:
    if triangles.shape[0] == 0:
        return np.zeros(0)
    a = vertices[triangles[:, 0]]
    b = vertices[triangles[:, 1]]
    c = vertices[triangles[:, 2]]
    return 0.5 * np.linalg.norm(np.cross(b - a, c - a), axis=1)


def weld_labels(vertices: np.ndarray, epsilon: float) -> np.ndarray:
    """Map duplicate/near-duplicate positions onto shared labels.

    Exporters split vertices along UV and normal seams, so raw index adjacency
    reports one solid object as dozens of pieces. Welding on position first is
    what makes 'disconnected components' mean something physical.
    """
    if vertices.shape[0] == 0:
        return np.zeros(0, dtype=np.int64)
    quantised = np.round(vertices / max(epsilon, 1e-12)).astype(np.int64)
    _unique, labels = np.unique(quantised, axis=0, return_inverse=True)
    return labels.astype(np.int64)


def suggested_weld_epsilon(vertices: np.ndarray) -> float:
    """Welding tolerance scaled to the model, not to an assumed unit system."""
    if vertices.shape[0] == 0:
        return 1e-6
    low, high = bounds(vertices)
    diagonal = float(np.linalg.norm(high - low))
    return max(diagonal * 1e-5, 1e-9)


class _UnionFind:
    def __init__(self, size: int) -> None:
        self._parent = np.arange(size, dtype=np.int64)

    def find(self, item: int) -> int:
        parent = self._parent
        root = item
        while parent[root] != root:
            root = parent[root]
        while parent[item] != root:
            parent[item], item = root, parent[item]
        return int(root)

    def union(self, left: int, right: int) -> None:
        a, b = self.find(left), self.find(right)
        if a != b:
            self._parent[b] = a


def connected_components(
    triangles: np.ndarray, labels: np.ndarray, label_count: int
) -> np.ndarray:
    """Component id per triangle, using welded vertex labels for adjacency."""
    if triangles.shape[0] == 0:
        return np.zeros(0, dtype=np.int64)
    union = _UnionFind(label_count)
    welded = labels[triangles]
    for tri in welded:
        union.union(int(tri[0]), int(tri[1]))
        union.union(int(tri[1]), int(tri[2]))
    roots = np.array([union.find(int(tri[0])) for tri in welded], dtype=np.int64)
    _unique, component_ids = np.unique(roots, return_inverse=True)
    return component_ids.astype(np.int64)


def label_components(labels: np.ndarray, triangles: np.ndarray, label_count: int) -> np.ndarray:
    """Component id per WELDED LABEL, for vertex-set clustering."""
    union = _UnionFind(label_count)
    for tri in labels[triangles]:
        union.union(int(tri[0]), int(tri[1]))
        union.union(int(tri[1]), int(tri[2]))
    roots = np.array([union.find(i) for i in range(label_count)], dtype=np.int64)
    _unique, ids = np.unique(roots, return_inverse=True)
    return ids.astype(np.int64)


def principal_frame(points: np.ndarray) -> Frame:
    """Best-fit oriented frame via PCA, axes sorted by descending extent.

    PCA gives the orientation; the extent is then measured as the true span along
    each axis rather than a variance, because a plate's thickness is what matters
    and variance would understate it.
    """
    center = points.mean(axis=0)
    centred = points - center
    if points.shape[0] < 3:
        axes = np.eye(3)
    else:
        # SVD on the centred cloud: right singular vectors are the principal axes.
        _u, _s, vt = np.linalg.svd(centred, full_matrices=False)
        axes = vt
        if np.linalg.det(axes) < 0:
            axes = axes.copy()
            axes[2] = -axes[2]
    projected = centred @ axes.T
    extents = projected.max(axis=0) - projected.min(axis=0)
    order = np.argsort(-extents)
    axes = axes[order]
    extents = extents[order]
    # Recentre on the oriented bounding box centre so projections are symmetric.
    projected = (points - center) @ axes.T
    box_centre_local = (projected.max(axis=0) + projected.min(axis=0)) / 2.0
    center = center + box_centre_local @ axes
    return Frame(center=center, axes=axes, extents=extents)


def degenerate_triangle_mask(
    vertices: np.ndarray, triangles: np.ndarray, *, relative_area_floor: float = 1e-10
) -> np.ndarray:
    """Triangles with effectively zero area, scaled to the model size."""
    areas = triangle_areas(vertices, triangles)
    if areas.size == 0:
        return np.zeros(0, dtype=bool)
    low, high = bounds(vertices)
    scale = float(np.linalg.norm(high - low)) or 1.0
    return areas < (relative_area_floor * scale * scale)


def component_report(
    vertices: np.ndarray,
    triangles: np.ndarray,
    component_ids: np.ndarray,
    *,
    max_components: int = 24,
) -> list[dict]:
    """Per-component geometry summary, largest surface area first."""
    if triangles.shape[0] == 0:
        return []
    areas = triangle_areas(vertices, triangles)
    reports: list[dict] = []
    for component in np.unique(component_ids):
        mask = component_ids == component
        tris = triangles[mask]
        used = np.unique(tris)
        points = vertices[used]
        low, high = bounds(points)
        frame = principal_frame(points)
        reports.append(
            {
                "component_id": int(component),
                "triangle_count": int(mask.sum()),
                "vertex_count": int(used.size),
                "surface_area": float(areas[mask].sum()),
                "bounds_min": [float(v) for v in low],
                "bounds_max": [float(v) for v in high],
                "aabb_extents": [float(v) for v in (high - low)],
                "obb_extents": [float(v) for v in frame.extents],
                "centroid": [float(v) for v in points.mean(axis=0)],
            }
        )
    reports.sort(key=lambda item: -item["surface_area"])
    return reports[:max_components]
