# Headless test: godot --headless --path game -s res://domain/tests/test_ts08_height_solver_components.gd
#
# N3b component and gauge routing on small synthetic WorldMaps, per the
# component contract in docs/TERRAIN_SURFACE_TARGET.md:
# - rank 1 -> analytic constant surface
# - rank 2 affine-consistent -> analytic plane, zero perpendicular tilt
# - rank 2 non-affine collinear -> deflated CG + exact gauge post-projection
# - rank 3 -> plain CG with no gauge machinery instantiated (structural proof)
# - cliff-cut map -> separate components, each routed independently
extends SceneTree

const WorldMapScript = preload("res://domain/world/world_map.gd")
const MapIdentityScript = preload("res://domain/world/map_identity.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const Ts08CutLattice = preload("res://domain/world/ts08_cut_lattice.gd")
const Ts08HeightSolver = preload("res://domain/world/ts08_height_solver.gd")
const Ts08TerrainMathScript = preload("res://domain/world/ts08_terrain_math.gd")

const ELEVATION_STEP := 0.4
const ELEVATION_BASE := 0
const CLIFF_THRESHOLD := 1

var _total := 0
var _any_fail := false


func _init() -> void:
	_test_rank1_constant()
	_test_rank2_affine_plane()
	_test_rank2_non_affine_deflated()
	_test_rank3_plain_no_gauge()
	_test_cliff_split_two_constants()
	_test_rank3_with_isolated_rank1()
	_finish()


func _make_world_map(tiles_elevation: Dictionary):
	var tiles_dict: Dictionary = {}
	for coord: Vector2i in tiles_elevation.keys():
		tiles_dict[coord] = WorldMapScript.WorldTile.new(
			coord.x, coord.y, tiles_elevation[coord]
		)
	var edges: Dictionary = {}
	for coord: Vector2i in tiles_dict.keys():
		for offset: Vector2i in HexCoordScript.DIRECTIONS:
			var neighbor := coord + offset
			if not tiles_dict.has(neighbor):
				continue
			var edge_key := WorldMapScript.normalized_edge_key(coord, neighbor)
			if edges.has(edge_key):
				continue
			var delta: int = absi(
				tiles_dict[coord].elevation - tiles_dict[neighbor].elevation
			)
			var transition := WorldMapScript.EDGE_SMOOTH
			if delta > CLIFF_THRESHOLD:
				transition = WorldMapScript.EDGE_CLIFF
			var pair: Array = WorldMapScript.parse_edge_key(edge_key)
			edges[edge_key] = WorldMapScript.WorldEdge.new(pair[0], pair[1], transition)
	var identity = MapIdentityScript.new("synthetic_component_test", 1, "synthetic")
	return WorldMapScript.new(
		identity, ELEVATION_STEP, ELEVATION_BASE, CLIFF_THRESHOLD, tiles_dict, edges
	)


func _solve(tiles_elevation: Dictionary) -> Array:
	var world_map = _make_world_map(tiles_elevation)
	var build = Ts08CutLattice.build_from_world_map(world_map)
	var solve = Ts08HeightSolver.solve(world_map, build)
	return [world_map, build, solve]


func _world_y(elevation: int) -> float:
	return Ts08TerrainMathScript.canonical_center_world_y(
		elevation, ELEVATION_STEP, ELEVATION_BASE
	)


func _max_pin_error(build, solve) -> float:
	var max_error := 0.0
	for node_index in build.pinned_world_y.keys():
		max_error = maxf(
			max_error,
			absf(solve.heights[node_index] - float(build.pinned_world_y[node_index]))
		)
	return max_error


func _test_rank1_constant() -> void:
	print("--- rank 1: single hex -> analytic constant ---")
	var parts := _solve({Vector2i(0, 0): 2})
	var build = parts[1]
	var solve = parts[2]
	_check(solve.connected_component_count == 1, "rank1: one component")
	_check(solve.deficient_component_count == 1, "rank1: deficient")
	_check(solve.component_reports[0]["pin_rank"] == 1, "rank1: pin rank 1")
	_check(
		solve.component_reports[0]["gauge_method"] == Ts08HeightSolver.GAUGE_ANALYTIC_CONSTANT,
		"rank1: analytic_constant route"
	)
	_check(solve.gauge_convention_applied_count == 1, "rank1: gauge convention applied once")
	_check(solve.deflation_instantiated_count == 0, "rank1: no deflation instantiated")
	var expected := _world_y(2)
	var max_error := 0.0
	for i in build.node_count:
		max_error = maxf(max_error, absf(solve.heights[i] - expected))
	_check(max_error == 0.0, "rank1: exactly constant surface at pinned height")


func _test_rank2_affine_plane() -> void:
	print("--- rank 2 affine: two hexes -> analytic plane ---")
	var parts := _solve({Vector2i(0, 0): 0, Vector2i(1, 0): 1})
	var build = parts[1]
	var solve = parts[2]
	_check(solve.connected_component_count == 1, "rank2 affine: one component")
	_check(solve.component_reports[0]["pin_rank"] == 2, "rank2 affine: pin rank 2")
	_check(
		not solve.component_reports[0]["collinear_non_affine"],
		"rank2 affine: affine-consistent"
	)
	_check(
		solve.component_reports[0]["gauge_method"] == Ts08HeightSolver.GAUGE_ANALYTIC_PLANE,
		"rank2 affine: analytic_plane route"
	)
	_check(solve.deflation_instantiated_count == 0, "rank2 affine: no deflation instantiated")
	_check(_max_pin_error(build, solve) <= 1e-12, "rank2 affine: pins exact")

	# Verify the exact two-pin plane formula at every node (zero perpendicular tilt).
	var pin_nodes: Array = build.pinned_world_y.keys()
	pin_nodes.sort()
	var x0: float = build.node_plane_x[pin_nodes[0]]
	var y0: float = build.node_plane_y[pin_nodes[0]]
	var x1: float = build.node_plane_x[pin_nodes[1]]
	var y1: float = build.node_plane_y[pin_nodes[1]]
	var z0: float = float(build.pinned_world_y[pin_nodes[0]])
	var z1: float = float(build.pinned_world_y[pin_nodes[1]])
	var dx := x1 - x0
	var dy := y1 - y0
	var dist := sqrt(dx * dx + dy * dy)
	var slope := (z1 - z0) / dist
	var max_error := 0.0
	for i in build.node_count:
		var t: float = (
			((build.node_plane_x[i] - x0) * dx + (build.node_plane_y[i] - y0) * dy) / dist
		)
		max_error = maxf(max_error, absf(solve.heights[i] - (z0 + slope * t)))
	_check(max_error <= 1e-12, "rank2 affine: exact two-pin plane at every node")


func _test_rank2_non_affine_deflated() -> void:
	print("--- rank 2 non-affine collinear -> deflated CG + post-projection ---")
	var parts := _solve({
		Vector2i(0, 0): 0,
		Vector2i(1, 0): 1,
		Vector2i(2, 0): 0,
		Vector2i(3, 0): 1,
	})
	var build = parts[1]
	var solve = parts[2]
	_check(solve.connected_component_count == 1, "deflated: one component")
	_check(solve.component_reports[0]["pin_rank"] == 2, "deflated: pin rank 2")
	_check(
		solve.component_reports[0]["collinear_non_affine"],
		"deflated: collinear non-affine detected"
	)
	_check(
		solve.component_reports[0]["gauge_method"] == Ts08HeightSolver.GAUGE_CG_DEFLATED,
		"deflated: cg_deflated route (no UNSUPPORTED_GAUGE_CASE)"
	)
	_check(solve.deflation_instantiated_count == 1, "deflated: deflation instantiated once")
	_check(solve.component_reports[0].get("converged", false), "deflated: CG converged")
	_check(_max_pin_error(build, solve) <= 1e-12, "deflated: pins exact")
	var projection: float = solve.component_reports[0]["mean_gradient_gauge_projection"]
	_check(
		absf(projection) <= 1e-9,
		"deflated: mean perpendicular gradient projected to zero (%s)"
		% String.num_scientific(projection)
	)
	var energy_pre: float = solve.component_reports[0]["discrete_bending_energy_pre_projection"]
	var energy_post: float = solve.component_reports[0]["discrete_bending_energy_post_projection"]
	print(
		"deflated: bending energy pre=%s post=%s"
		% [String.num_scientific(energy_pre), String.num_scientific(energy_post)]
	)
	_check(energy_pre > 0.0, "deflated: curved primary minimizer (energy > 0)")
	# The gauge mode is affine (zero curvature); only the boundary-row residue
	# of the discrete operator may shift the energy, and it must stay tiny.
	_check(
		absf(energy_post - energy_pre) <= 0.05 * energy_pre,
		"deflated: projection leaves bending energy essentially unchanged"
	)
	# Non-affine collinear pins force a curved along-line profile; the surface
	# must not have been flattened to a plane.
	var y_span: float = solve.y_max - solve.y_min
	_check(y_span > 0.0, "deflated: non-degenerate height span")


func _test_rank3_plain_no_gauge() -> void:
	print("--- rank 3: plain CG, gauge machinery never instantiated ---")
	var parts := _solve({
		Vector2i(0, 0): 0,
		Vector2i(1, 0): 1,
		Vector2i(0, 1): 1,
	})
	var build = parts[1]
	var solve = parts[2]
	_check(solve.connected_component_count == 1, "rank3: one component")
	_check(solve.component_reports[0]["pin_rank"] == 3, "rank3: pin rank 3")
	_check(solve.component_reports[0]["fully_determined"], "rank3: fully determined")
	_check(
		solve.component_reports[0]["gauge_method"] == Ts08HeightSolver.GAUGE_CG_PLAIN,
		"rank3: cg_plain route"
	)
	_check(solve.deficient_component_count == 0, "rank3: zero deficient components")
	# Structural proof that gauge handling never affects a rank-3 component:
	# neither the convention nor the deflation machinery may be instantiated.
	_check(solve.gauge_convention_applied_count == 0, "rank3: gauge convention never applied")
	_check(solve.deflation_instantiated_count == 0, "rank3: deflation never instantiated")
	_check(
		not solve.component_reports[0]["gauge_convention_applied"],
		"rank3: component report untouched by gauge"
	)
	_check(solve.converged, "rank3: CG converged")
	_check(solve.cg_final_rel_residual <= 1e-8, "rank3: relative residual <= 1e-8")
	_check(_max_pin_error(build, solve) <= 1e-12, "rank3: pins exact")
	_check(solve.energy_final <= solve.energy_initial + 1e-12, "rank3: energy non-increasing")


func _test_cliff_split_two_constants() -> void:
	print("--- cliff cut: two hexes split into two rank-1 components ---")
	var parts := _solve({Vector2i(0, 0): 0, Vector2i(1, 0): 2})
	var build = parts[1]
	var solve = parts[2]
	_check(solve.connected_component_count == 2, "cliff split: two components")
	_check(solve.deficient_component_count == 2, "cliff split: both deficient")
	_check(solve.gauge_convention_applied_count == 2, "cliff split: convention applied twice")
	for report in solve.component_reports:
		_check(
			report["gauge_method"] == Ts08HeightSolver.GAUGE_ANALYTIC_CONSTANT,
			"cliff split: component %d analytic_constant" % int(report["component_id"])
		)
	var audit := Ts08CutLattice.audit_topology(build)
	_check(audit["adjacency_cross_cliff_violations"] == 0, "cliff split: zero cross-cliff adjacency")
	# Every node must sit exactly at its own sheet's pinned height.
	var max_error := 0.0
	for node_index in build.pinned_world_y.keys():
		var component_id: int = build.component_ids[node_index]
		var expected: float = float(build.pinned_world_y[node_index])
		for i in build.node_count:
			if build.component_ids[i] == component_id:
				max_error = maxf(max_error, absf(solve.heights[i] - expected))
	_check(max_error == 0.0, "cliff split: each sheet exactly at its pinned height")


func _test_rank3_with_isolated_rank1() -> void:
	print("--- mixed: rank-3 component + isolated rank-1 hex ---")
	var parts := _solve({
		Vector2i(0, 0): 0,
		Vector2i(1, 0): 1,
		Vector2i(0, 1): 1,
		Vector2i(4, 0): 3,
	})
	var build = parts[1]
	var solve = parts[2]
	_check(solve.connected_component_count == 2, "mixed: two components")
	_check(solve.deficient_component_count == 1, "mixed: one deficient component")
	_check(solve.gauge_convention_applied_count == 1, "mixed: convention applied only once")
	var rank3_report: Dictionary = {}
	var rank1_report: Dictionary = {}
	for report in solve.component_reports:
		if report["pin_rank"] == 3:
			rank3_report = report
		elif report["pin_rank"] == 1:
			rank1_report = report
	_check(not rank3_report.is_empty(), "mixed: rank-3 component present")
	_check(not rank1_report.is_empty(), "mixed: rank-1 component present")
	_check(
		not rank3_report.get("gauge_convention_applied", true),
		"mixed: gauge convention did not touch the rank-3 component"
	)
	# The isolated hex must be exactly constant even though the global CG ran.
	var expected := _world_y(3)
	var max_error := 0.0
	for i in build.node_count:
		if build.component_ids[i] == int(rank1_report["component_id"]):
			max_error = maxf(max_error, absf(solve.heights[i] - expected))
	_check(max_error == 0.0, "mixed: isolated component exactly constant despite global CG")
	_check(_max_pin_error(build, solve) <= 1e-12, "mixed: all pins exact")
	_check(solve.converged, "mixed: converged")


func _check(condition: bool, label: String) -> void:
	_total += 1
	if condition:
		print("PASS ", label)
	else:
		_any_fail = true
		print("FAIL ", label)


func _finish() -> void:
	print("Ts08HeightSolver component tests: %d checks" % _total)
	if _any_fail:
		print("FAIL")
		quit(1)
	else:
		print("PASS")
		quit(0)
