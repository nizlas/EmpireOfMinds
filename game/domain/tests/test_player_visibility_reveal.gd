# Headless: godot --headless --path game -s res://domain/tests/test_player_visibility_reveal.gd
extends SceneTree

const GameStateScript = preload("res://domain/game_state.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const HexMapScript = preload("res://domain/hex_map.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const UnitScript = preload("res://domain/unit.gd")
const CityScript = preload("res://domain/city.gd")
const MoveUnitScript = preload("res://domain/actions/move_unit.gd")
const FoundCityScript = preload("res://domain/actions/found_city.gd")
const EndTurnScript = preload("res://domain/actions/end_turn.gd")
const PlayerVisibilityStateScript = preload("res://domain/player_visibility_state.gd")

var _total: int = 0
var _any_fail: bool = false


func _init() -> void:
	call_deferred("_run")


func _disk_coords(center, radius: int, mp) -> Array:
	var out: Array = []
	var coords: Array = mp.coords()
	var i: int = 0
	while i < coords.size():
		var c = coords[i]
		if HexCoordScript.axial_distance(center, c) <= radius:
			out.append(c)
		i = i + 1
	return out


func _same_explored_p0(prev_vis, after_gs) -> bool:
	var mp = after_gs.scenario.map
	var coords: Array = mp.coords()
	var i: int = 0
	while i < coords.size():
		var c = coords[i]
		if prev_vis.is_explored(0, c) != after_gs.visibility_state.is_explored(0, c):
			return false
		i = i + 1
	return true


func _proj_ready_warrior() -> Dictionary:
	var d: Dictionary = {}
	d["project_type"] = "produce_unit"
	d["progress"] = 2
	d["cost"] = 2
	d["ready"] = true
	return d


func _count_units_owned(scen, oid: int) -> int:
	var n: int = 0
	var ulist: Array = scen.units()
	var i: int = 0
	while i < ulist.size():
		if int((ulist[i] as Object).owner_id) == oid:
			n += 1
		i = i + 1
	return n


func _run() -> void:
	var gs0 = GameStateScript.make_tiny_test_state()
	var mp0 = gs0.scenario.map
	_check(not gs0.visibility_state.is_explored(0, HexCoordScript.new(-99, 42)), "clamp no ghost keys")

	var p0_disk_union: Dictionary = {}
	var u_p0 = gs0.scenario.units_owned_by(0)
	var ui: int = 0
	while ui < u_p0.size():
		var u = u_p0[ui]
		var cells: Array = _disk_coords(u.position, PlayerVisibilityStateScript.UNIT_SIGHT_RADIUS, mp0)
		var ci: int = 0
		while ci < cells.size():
			var k: Vector2i = Vector2i(int((cells[ci] as HexCoord).q), int((cells[ci] as HexCoord).r))
			p0_disk_union[k] = true
			ci = ci + 1
		ui = ui + 1
	var p0_expl: Array = gs0.visibility_state.explored_for_player(0)
	var ei: int = 0
	while ei < p0_expl.size():
		var hc: HexCoord = p0_expl[ei] as HexCoord
		var vk := Vector2i(int(hc.q), int(hc.r))
		_check(p0_disk_union.has(vk), "P0 initial covers unit disks")
		ei = ei + 1

	var p1_disk_union: Dictionary = {}
	var u_p1 = gs0.scenario.units_owned_by(1)
	var uj: int = 0
	while uj < u_p1.size():
		var u1 = u_p1[uj]
		var cells1: Array = _disk_coords(u1.position, PlayerVisibilityStateScript.UNIT_SIGHT_RADIUS, mp0)
		var cj: int = 0
		while cj < cells1.size():
			var k1: Vector2i = Vector2i(int((cells1[cj] as HexCoord).q), int((cells1[cj] as HexCoord).r))
			p1_disk_union[k1] = true
			cj = cj + 1
		uj = uj + 1
	var p1_expl_disk: Array = gs0.visibility_state.explored_for_player(1)
	var ek: int = 0
	while ek < p1_expl_disk.size():
		var hc1: HexCoord = p1_expl_disk[ek] as HexCoord
		var vk1 := Vector2i(int(hc1.q), int(hc1.r))
		_check(p1_disk_union.has(vk1), "P1 initial covers unit disks")
		ek = ek + 1

	var p1_expl_init: Array = gs0.visibility_state.explored_for_player(1)
	var p0_expl_init: Array = gs0.visibility_state.explored_for_player(0)
	_check(p0_expl_init.size() > 0 and p1_expl_init.size() > 0, "both players start with some explored")
	var asym_p0_only: Variant = null
	var ci_sym: int = 0
	while ci_sym < mp0.coords().size():
		var cx = mp0.coords()[ci_sym] as HexCoord
		if gs0.visibility_state.is_explored(0, cx) and not gs0.visibility_state.is_explored(1, cx):
			asym_p0_only = cx
			break
		ci_sym += 1
	if asym_p0_only != null:
		_check(true, "P0-only explored tile exists on fixture")
	else:
		_check(
			p0_expl_init.size() == mp0.coords().size() and p1_expl_init.size() == mp0.coords().size(),
			"tiny map: radius-2 from all starts may cover every tile",
		)
	var mv = MoveUnitScript.make(0, 2, 1, 0, 1, -1)
	_check(gs0.try_apply(mv)["accepted"], "move warrior")
	var dest: HexCoord = HexCoordScript.new(1, -1)
	var after_cells: Array = _disk_coords(dest, PlayerVisibilityStateScript.UNIT_SIGHT_RADIUS, gs0.scenario.map)
	var aci: int = 0
	while aci < after_cells.size():
		var cx = after_cells[aci] as HexCoord
		_check(gs0.visibility_state.is_explored(0, cx), "move reveals dest disk")
		aci = aci + 1
	_check(gs0.visibility_state.is_explored(0, HexCoordScript.new(1, 0)), "previous warrior hex stays explored")

	var gs_fc = GameStateScript.make_tiny_test_state()
	var p1_expl_before: Dictionary = {}
	var peb: Array = gs_fc.visibility_state.explored_for_player(1)
	var pbi: int = 0
	while pbi < peb.size():
		var hh: HexCoord = peb[pbi] as HexCoord
		p1_expl_before[Vector2i(int(hh.q), int(hh.r))] = true
		pbi += 1
	var fc = FoundCityScript.make(0, 1, 0, 0)
	_check(gs_fc.try_apply(fc)["accepted"], "found city")
	var p1_expl_after: Dictionary = {}
	var pea: Array = gs_fc.visibility_state.explored_for_player(1)
	var pai: int = 0
	while pai < pea.size():
		var ha: HexCoord = pea[pai] as HexCoord
		p1_expl_after[Vector2i(int(ha.q), int(ha.r))] = true
		pai += 1
	_check(p1_expl_before == p1_expl_after, "P1 explored unchanged by P0 FoundCity")

	var founded: Variant = null
	var c_all: Array = gs_fc.scenario.cities()
	var fk: int = 0
	while fk < c_all.size():
		var cx = c_all[fk]
		if int(cx.owner_id) == 0:
			founded = cx
			break
		fk += 1
	_check(founded != null, "found P0 city")
	var anchors: Array = [founded.position]
	var oti: int = 0
	while oti < founded.owned_tiles.size():
		anchors.append(founded.owned_tiles[oti])
		oti = oti + 1
	var ai: int = 0
	while ai < anchors.size():
		var ac = anchors[ai]
		var ring: Array = _disk_coords(ac, PlayerVisibilityStateScript.CITY_SIGHT_RADIUS, gs_fc.scenario.map)
		var ri: int = 0
		while ri < ring.size():
			_check(
				gs_fc.visibility_state.is_explored(0, ring[ri] as HexCoord),
				"found city reveals center+owned ring"
			)
			ri = ri + 1
		ai = ai + 1
	var coords_fc: Array = gs_fc.scenario.map.coords()
	var cj: int = 0
	while cj < coords_fc.size():
		var cc = coords_fc[cj] as HexCoord
		_check(
			p1_expl_before.has(Vector2i(int(cc.q), int(cc.r)))
			== gs_fc.visibility_state.is_explored(1, cc),
			"P1 per-hex identity after P0 FoundCity"
		)
		cj = cj + 1

	var m2 = HexMapScript.make_tiny_test_map()
	var us2: Array = [
		UnitScript.new(1, 0, HexCoordScript.new(0, 0), "settler"),
		UnitScript.new(2, 0, HexCoordScript.new(1, 0), "warrior"),
		UnitScript.new(3, 1, HexCoordScript.new(0, -1), "settler"),
	]
	var c_p1 = CityScript.new(
		10,
		1,
		HexCoordScript.new(0, 1),
		_proj_ready_warrior(),
		"P1Cap",
		true,
		["palace"],
		null,
		1,
		[],
		0,
	)
	var sc2 = ScenarioScript.new(m2, us2, [c_p1], -1, -1)
	var gs_et = GameStateScript.new(sc2)
	var vis_before_et = gs_et.visibility_state
	var u1_before: int = _count_units_owned(gs_et.scenario, 1)
	var et = EndTurnScript.make(0)
	_check(gs_et.try_apply(et)["accepted"], "end turn P0 to P1")
	_check(gs_et.turn_state.current_player_id() == 1, "now P1")
	_check(_same_explored_p0(vis_before_et, gs_et), "P0 memory unchanged after EndTurn")
	_check(_count_units_owned(gs_et.scenario, 1) == u1_before + 1, "delivery added P1 unit")
	var vis_re = PlayerVisibilityStateScript.recompute_for_actor(
		vis_before_et,
		gs_et.scenario,
		1,
	)
	_check(gs_et.visibility_state.equals(vis_re), "EndTurn visibility matches manual recompute P1")

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
	var line: String = "FAIL: %s" % message
	print(line)
	push_error(line)
