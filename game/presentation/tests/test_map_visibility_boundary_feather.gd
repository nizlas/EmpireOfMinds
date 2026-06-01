# Headless: Phase **5.2.4m** — unexplored/explored boundary feather edge helper.
# Usage: godot --headless --path game -s res://presentation/tests/test_map_visibility_boundary_feather.gd
extends SceneTree

const GameStateScript = preload("res://domain/game_state.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const MapVisibilityViewScript = preload("res://presentation/map_visibility_view.gd")
const PlayerVisibilityStateScript = preload("res://domain/player_visibility_state.gd")
const EndTurnScript = preload("res://domain/actions/end_turn.gd")

var _total: int = 0
var _any_fail: bool = false


func _init() -> void:
	call_deferred("_run")


func _feather_fixture_state():
	# Unit sight on the 7-hex fixture covers everything — seed partial visibility instead.
	var gs = GameStateScript.make_tiny_test_state()
	var vis = PlayerVisibilityStateScript.empty_for_players([0, 1])
	vis = vis.with_revealed(0, [HexCoordScript.new(0, 0)])
	vis = vis.with_revealed(1, [HexCoordScript.new(0, -1)])
	gs.visibility_state = vis
	return gs


func _run() -> void:
	var layout = HexLayoutScript.new()
	_check(
		MapVisibilityViewScript.compute_unexplored_boundary_edges_for_current_player(null, layout).is_empty(),
		"null gs -> empty edges",
	)
	var gs = _feather_fixture_state()
	_check(
		MapVisibilityViewScript.compute_unexplored_boundary_edges_for_current_player(gs, null).is_empty(),
		"null layout -> empty edges",
	)

	var edges_p0: Array = MapVisibilityViewScript.compute_unexplored_boundary_edges_for_current_player(gs, layout)
	_check(edges_p0.size() > 0, "P0 partial visibility yields boundary edges")

	var unexplored_u: HexCoordScript = null
	var explored_e: HexCoordScript = null
	var coords: Array = gs.scenario.map.coords()
	var ci: int = 0
	while ci < coords.size():
		var c: HexCoordScript = coords[ci] as HexCoordScript
		ci += 1
		if gs.visibility_state.is_explored(0, c):
			var di: int = 0
			while di < 6:
				var n = c.neighbor(di)
				di += 1
				if not gs.scenario.map.has(n):
					continue
				if gs.visibility_state.is_explored(0, n):
					continue
				unexplored_u = n
				explored_e = c
				break
			if unexplored_u != null:
				break

	_check(unexplored_u != null and explored_e != null, "found unexplored U adjacent to explored E for P0")

	var boundary_count: int = 0
	var ei: int = 0
	while ei < edges_p0.size():
		var ed: Dictionary = edges_p0[ei] as Dictionary
		ei += 1
		if int(ed["uq"]) == int(unexplored_u.q) and int(ed["ur"]) == int(unexplored_u.r):
			if int(ed["eq"]) == int(explored_e.q) and int(ed["er"]) == int(explored_e.r):
				boundary_count += 1
	_check(boundary_count == 1, "exactly one feather edge for unexplored U -> explored E side")

	var ej: int = 0
	while ej < edges_p0.size():
		var ed2: Dictionary = edges_p0[ej] as Dictionary
		ej += 1
		if int(ed2["uq"]) == int(explored_e.q) and int(ed2["ur"]) == int(explored_e.r):
			_fail_msg("explored cell must not emit feather edge as unexplored U")
			break

	var unexplored_neighbor: HexCoordScript = null
	var nk: int = 0
	while nk < 6:
		var nn = unexplored_u.neighbor(nk)
		nk += 1
		if not gs.scenario.map.has(nn):
			continue
		if gs.visibility_state.is_explored(0, nn):
			continue
		if int(nn.q) == int(explored_e.q) and int(nn.r) == int(explored_e.r):
			continue
		unexplored_neighbor = nn
		break
	if unexplored_neighbor != null:
		var uu_count: int = 0
		var ek: int = 0
		while ek < edges_p0.size():
			var ed3: Dictionary = edges_p0[ek] as Dictionary
			ek += 1
			if int(ed3["uq"]) == int(unexplored_u.q) and int(ed3["ur"]) == int(unexplored_u.r):
				if int(ed3["eq"]) == int(unexplored_neighbor.q) and int(ed3["er"]) == int(unexplored_neighbor.r):
					uu_count += 1
		_check(uu_count == 0, "unexplored/unexplored neighbor produces no feather edge")

	var keys_p0: Dictionary = {}
	var si: int = 0
	while si < edges_p0.size():
		var edk: Dictionary = edges_p0[si] as Dictionary
		keys_p0["%d,%d,%d" % [int(edk["uq"]), int(edk["ur"]), int(edk["direction_index"])]] = true
		si += 1
	_check(gs.try_apply(EndTurnScript.make(0))["accepted"], "end turn to P1")
	var edges_p1: Array = MapVisibilityViewScript.compute_unexplored_boundary_edges_for_current_player(gs, layout)
	var same_set: bool = edges_p0.size() == edges_p1.size()
	if same_set:
		var sj: int = 0
		while sj < edges_p1.size():
			var edp1: Dictionary = edges_p1[sj] as Dictionary
			var k1: String = "%d,%d,%d" % [int(edp1["uq"]), int(edp1["ur"]), int(edp1["direction_index"])]
			if not keys_p0.has(k1):
				same_set = false
				break
			sj += 1
	_check(not same_set, "P1 edge set differs from P0 after EndTurn")

	if edges_p0.size() > 0:
		var sample: Dictionary = edges_p0[0] as Dictionary
		var uq: int = int(sample["uq"])
		var ur: int = int(sample["ur"])
		var eq: int = int(sample["eq"])
		var er: int = int(sample["er"])
		var geom = MapVisibilityViewScript._shared_edge_world(uq, ur, eq, er, layout)
		_check(abs(float(sample["edge_p0"].x) - float(geom["edge_p0"].x)) < 0.01, "edge_p0 matches shared-edge helper")
		var c_u: Vector2 = layout.hex_to_world(uq, ur)
		var c_e: Vector2 = layout.hex_to_world(eq, er)
		var toward_e: Vector2 = (c_e - c_u).normalized()
		var dot_out: float = float(sample["outward"].dot(toward_e))
		_check(dot_out > 0.99, "outward points toward explored neighbor")

	var mvv = MapVisibilityViewScript.new()
	_check(mvv.unexplored_edge_feather_enabled, "default feather enabled")
	_check(absf(mvv.unexplored_edge_feather_width_px - 20.0) < 0.01, "default width ~20 px")
	_check(mvv.unexplored_edge_feather_steps == 6, "default steps 6")
	_check(absf(mvv.unexplored_edge_feather_inner_overlap_px - 4.0) < 0.01, "default inner overlap ~4 px")
	_check(not mvv.unexplored_edge_feather_irregularity_enabled, "default irregularity off")
	mvv.queue_free()

	var span0: Dictionary = MapVisibilityViewScript.feather_strip_distance_range_world(4.0, 20.0, 1.0, 0, 6)
	_check(absf(float(span0["d_min"]) + 4.0) < 0.01, "first strip span starts -inner_overlap world")
	_check(absf(float(span0["d_max"]) - 20.0) < 0.01, "strip span ends at +width world")
	_check(float(span0["inner_d"]) < -0.01, "step 0 inner_d is inside unexplored side")
	var span_last: Dictionary = MapVisibilityViewScript.feather_strip_distance_range_world(4.0, 20.0, 1.0, 5, 6)
	_check(absf(float(span_last["outer_d"]) - 20.0) < 0.01, "last strip outer_d reaches +width")
	var span1: Dictionary = MapVisibilityViewScript.feather_strip_distance_range_world(4.0, 20.0, 1.0, 1, 6)
	_check(
		absf(float(span0["outer_d"]) - float(span1["inner_d"])) < 0.0001,
		"adjacent strips share edges without gap",
	)
	_check(
		absf(MapVisibilityViewScript.feather_alpha_at_outward_distance(0.0, 20.0, 1.0, 0.75) - 1.0) < 0.001,
		"alpha at shared edge matches solid overlay peak",
	)
	_check(
		MapVisibilityViewScript.feather_alpha_at_outward_distance(20.0, 20.0, 1.0, 0.75) < 0.001,
		"alpha at outer width is ~0",
	)

	if _any_fail:
		call_deferred("quit", 1)
	else:
		print("PASS %d/%d" % [_total, _total])
		call_deferred("quit", 0)


func _check(cond: bool, message: String) -> void:
	_total += 1
	if cond:
		return
	_any_fail = true
	var line = "FAIL: %s" % message
	print(line)
	push_error(line)


func _fail_msg(message: String) -> void:
	_check(false, message)
