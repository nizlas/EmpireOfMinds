# N3c.4 presentation/integration-side terrain collision builder.
#
# Consumes the accepted N3c.1 Ts08SurfaceGeometry output and emits
# deterministic ConcavePolygonShape3D collision as two independently
# identifiable shapes (top surface, cliff walls) under one clearly named
# StaticBody3D. Collision is DERIVED presentation data: it never becomes
# terrain or gameplay authority (WorldMap stays the logical authority; rules
# must never infer passability or tile identity from collision hits — see
# docs/MAP_MODEL.md).
#
# Exactness contract (locked):
# - top faces flatten the exact solver-generated top positions through the
#   accepted Y-up top triangles in the rendered index order (a, c, b — the
#   same reversal the preview mesh bakes for Godot's clockwise front faces);
# - wall faces are the identical vertex stream the wall rendering bakes:
#   TerrainCliffWallMaterial.build_wall_mesh_arrays' deterministic fan
#   triangulation of the accepted wall-face records ((p0, p2, p1) per fan
#   triangle) — correspondence with the rendered geometry by construction;
# - no resampling, height approximation, simplification, or topology change.
#
# Keeping the rendered winding makes the physics face normals equal the
# render-front normals (Godot planes from three points use
# (v2 - v0) x (v1 - v0)): top faces face up, wall faces face outward toward
# the lower tile, so default single-sided collision behaves correctly.
#
# Deterministic: pure per-triangle functions of the (deterministic) geometry;
# bit-identical across independent builds. Inputs are read-only — nothing
# here writes to WorldMap, the lattice, heights, or the geometry result.
# No chunking, LOD, caching, or optimization in this slice.
extends RefCounted

const TerrainCliffWallMaterialScript = preload("res://presentation/terrain_cliff_wall_material.gd")

const BODY_NAME := "TerrainCollision"
const TOP_SHAPE_NAME := "TopSurfaceCollision"
const WALL_SHAPE_NAME := "CliffWallCollision"


# Flattened top-surface collision faces in the rendered index order.
static func build_top_faces(geometry) -> PackedVector3Array:
	var positions: PackedVector3Array = geometry.top_positions
	var triangles: PackedInt32Array = geometry.top_triangles
	var faces := PackedVector3Array()
	faces.resize(triangles.size())
	var cursor := 0
	for t in triangles.size() / 3:
		faces[cursor] = positions[triangles[3 * t]]
		faces[cursor + 1] = positions[triangles[3 * t + 2]]
		faces[cursor + 2] = positions[triangles[3 * t + 1]]
		cursor += 3
	return faces


# Wall collision faces: exactly the rendered wall vertex stream (same
# deterministic fan triangulation, winding, and degenerate handling).
static func build_wall_faces(geometry) -> PackedVector3Array:
	if geometry.wall_faces.is_empty():
		return PackedVector3Array()
	var arrays: Dictionary = TerrainCliffWallMaterialScript.build_wall_mesh_arrays(
		geometry.top_positions, geometry.wall_faces
	)
	return arrays["vertices"]


# Two independently identifiable concave shapes plus memory-relevant counts.
static func build_shapes(geometry) -> Dictionary:
	var top_faces := build_top_faces(geometry)
	var wall_faces := build_wall_faces(geometry)
	var top_shape := ConcavePolygonShape3D.new()
	top_shape.set_faces(top_faces)
	var wall_shape: ConcavePolygonShape3D = null
	if wall_faces.size() > 0:
		wall_shape = ConcavePolygonShape3D.new()
		wall_shape.set_faces(wall_faces)
	return {
		"top_shape": top_shape,
		"wall_shape": wall_shape,
		"top_triangle_count": top_faces.size() / 3,
		"wall_triangle_count": wall_faces.size() / 3,
	}


# One clearly named static terrain body with separate, named top/wall
# collision shapes (shape index 0 = top, 1 = walls).
static func build_static_body(geometry) -> StaticBody3D:
	var shapes := build_shapes(geometry)
	var body := StaticBody3D.new()
	body.name = BODY_NAME
	var top := CollisionShape3D.new()
	top.name = TOP_SHAPE_NAME
	top.shape = shapes["top_shape"]
	body.add_child(top)
	if shapes["wall_shape"] != null:
		var wall := CollisionShape3D.new()
		wall.name = WALL_SHAPE_NAME
		wall.shape = shapes["wall_shape"]
		body.add_child(wall)
	return body
