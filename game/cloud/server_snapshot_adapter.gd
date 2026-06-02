# Rebuilds Godot domain types from Cloud 0.1 snapshot schema v2 (read-only adapter).
# Slice C8 — local hotseat unchanged; this is used only for server-authoritative sessions.
extends RefCounted
class_name ServerSnapshotAdapter

const HexMapScript = preload("res://domain/hex_map.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const UnitScript = preload("res://domain/unit.gd")
const CityScript = preload("res://domain/city.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const TurnStateScript = preload("res://domain/turn_state.gd")
const ProgressStateScript = preload("res://domain/progress_state.gd")
const GameStateScript = preload("res://domain/game_state.gd")
const PlayerVisibilityStateScript = preload("res://domain/player_visibility_state.gd")


static func _terrain_from_string(s: String) -> int:
	var u = str(s).to_upper()
	match u:
		"WATER":
			return HexMapScript.Terrain.WATER
		"GRASSLAND":
			return HexMapScript.Terrain.GRASSLAND
		_:
			return HexMapScript.Terrain.PLAINS


static func hex_map_from_server_cells(cells: Array) -> Object:
	var cell_map: Dictionary = {}
	var landforms: Dictionary = {}
	var woods: Dictionary = {}
	var i: int = 0
	while i < cells.size():
		var row = cells[i]
		i += 1
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var q: int = int(row.get("q", 0))
		var r: int = int(row.get("r", 0))
		var k: Vector2i = Vector2i(q, r)
		cell_map[k] = _terrain_from_string(str(row.get("terrain", "plains")))
		var lf: String = str(row.get("landform", "flat")).to_upper()
		if lf == "HILLS":
			landforms[k] = HexMapScript.Landform.HILLS
		if bool(row.get("woods", false)):
			woods[k] = true
	return HexMapScript.new(cell_map, landforms, woods)


static func _coord_pair(arr) -> Object:
	if typeof(arr) != TYPE_ARRAY or (arr as Array).size() < 2:
		return null
	var a: Array = arr as Array
	return HexCoordScript.new(int(a[0]), int(a[1]))


static func units_from_server(rows: Array) -> Array:
	var out: Array = []
	var i: int = 0
	while i < rows.size():
		var row = rows[i]
		i += 1
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var pos = _coord_pair(row.get("position", null))
		if pos == null:
			continue
		out.append(
			UnitScript.new(
				int(row.get("id", 0)),
				int(row.get("owner_id", 0)),
				pos,
				str(row.get("type_id", "warrior")),
				int(row.get("remaining_movement", -1)),
				int(row.get("current_hp", -1)),
			)
		)
	return out


static func cities_from_server(rows: Array) -> Array:
	var out: Array = []
	var i: int = 0
	while i < rows.size():
		var row = rows[i]
		i += 1
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var pos = _coord_pair(row.get("position", null))
		if pos == null:
			continue
		var owned: Array = []
		var ot_raw = row.get("owned_tiles", [])
		if typeof(ot_raw) == TYPE_ARRAY:
			var oi: int = 0
			var ota: Array = ot_raw as Array
			while oi < ota.size():
				var hc = _coord_pair(ota[oi])
				if hc != null:
					owned.append(hc)
				oi += 1
		var manual: Array = []
		var mt_raw = row.get("manual_worked_tiles", [])
		if typeof(mt_raw) == TYPE_ARRAY:
			var mi: int = 0
			var mta: Array = mt_raw as Array
			while mi < mta.size():
				var h2 = _coord_pair(mta[mi])
				if h2 != null:
					manual.append(h2)
				mi += 1
		var proj = row.get("current_project", null)
		out.append(
			CityScript.new(
				int(row.get("id", 0)),
				int(row.get("owner_id", 0)),
				pos,
				proj,
				str(row.get("city_name", "")),
				bool(row.get("is_capital", false)),
				row.get("building_ids", []),
				owned,
				int(row.get("population", 1)),
				manual,
				int(row.get("food_stored", 0)),
				str(row.get("worked_tiles_mode", CityScript.WORKED_TILES_MODE_AUTO)),
			)
		)
	return out


static func scenario_from_server_dict(d: Dictionary) -> Object:
	var cells = d.get("map", {})
	if typeof(cells) != TYPE_DICTIONARY:
		push_error("ServerSnapshotAdapter: missing scenario.map")
		return null
	var cell_rows = cells.get("cells", [])
	if typeof(cell_rows) != TYPE_ARRAY:
		push_error("ServerSnapshotAdapter: missing map.cells")
		return null
	var hm = hex_map_from_server_cells(cell_rows as Array)
	var units: Array = []
	var u_raw = d.get("units", [])
	if typeof(u_raw) == TYPE_ARRAY:
		units = units_from_server(u_raw as Array)
	var cities: Array = []
	var c_raw = d.get("cities", [])
	if typeof(c_raw) == TYPE_ARRAY:
		cities = cities_from_server(c_raw as Array)
	var nu: int = int(d.get("next_unit_id", -1))
	var nc: int = int(d.get("next_city_id", -1))
	var lt_raw = d.get("lightning_tree_hex", null)
	var lt = null
	if lt_raw != null and typeof(lt_raw) == TYPE_ARRAY:
		var lta: Array = lt_raw as Array
		if lta.size() >= 2:
			lt = HexCoordScript.new(int(lta[0]), int(lta[1]))
	return ScenarioScript.new(hm, units, cities, nu, nc, lt)


static func turn_state_from_server_dict(d: Dictionary) -> Object:
	var pl: Array = []
	var pr = d.get("players", [])
	if typeof(pr) == TYPE_ARRAY:
		var ii: int = 0
		var pra: Array = pr as Array
		while ii < pra.size():
			pl.append(int(pra[ii]))
			ii += 1
	return TurnStateScript.new(pl, int(d.get("current_index", 0)), int(d.get("turn_number", 1)))


static func progress_state_from_server_dict(d: Dictionary) -> Object:
	var by_rows = d.get("by_owner", [])
	if typeof(by_rows) != TYPE_ARRAY:
		return ProgressStateScript.new({})
	var built: Dictionary = {}
	var i: int = 0
	var bra: Array = by_rows as Array
	while i < bra.size():
		var row = bra[i]
		i += 1
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var oid: int = int(row.get("owner_id", 0))
		built[oid] = {
			"unlocked_targets": row.get("unlocked_targets", []),
			"completed_progress_ids": row.get("completed_progress_ids", []),
			"science_progress": row.get("science_progress", {}),
			"science_observation_flags": row.get("science_observation_flags", {}),
			"current_research_id": str(row.get("current_research_id", "")),
		}
	return ProgressStateScript.new(built)


static func visibility_state_from_server_dict(d: Dictionary) -> Object:
	var rows = d.get("by_owner", [])
	if typeof(rows) != TYPE_ARRAY:
		return null
	var bo: Dictionary = {}
	var i: int = 0
	var ra: Array = rows as Array
	while i < ra.size():
		var row = ra[i]
		i += 1
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var oid: int = int(row.get("owner_id", 0))
		var inner: Dictionary = {}
		var explored = row.get("explored", [])
		if typeof(explored) == TYPE_ARRAY:
			var ei: int = 0
			var ea: Array = explored as Array
			while ei < ea.size():
				var pair = ea[ei]
				ei += 1
				if typeof(pair) == TYPE_ARRAY and (pair as Array).size() >= 2:
					var pa: Array = pair as Array
					inner[Vector2i(int(pa[0]), int(pa[1]))] = true
		bo[oid] = inner
	if bo.is_empty():
		return null
	return PlayerVisibilityStateScript.new(bo)


## Top-level API snapshot object (the `snapshot` field from GET match / POST action).
static func build_game_state_from_api_snapshot(snap: Dictionary) -> Object:
	if snap.is_empty():
		return null
	var scen_dict = snap.get("scenario", null)
	if typeof(scen_dict) != TYPE_DICTIONARY:
		push_error("ServerSnapshotAdapter: snapshot missing scenario")
		return null
	var scen = scenario_from_server_dict(scen_dict)
	if scen == null:
		return null
	var ts_d = snap.get("turn_state", {})
	if typeof(ts_d) != TYPE_DICTIONARY:
		push_error("ServerSnapshotAdapter: snapshot missing turn_state")
		return null
	var ts = turn_state_from_server_dict(ts_d)
	var prog_d = snap.get("progress_state", {})
	var prog = null
	if typeof(prog_d) == TYPE_DICTIONARY:
		prog = progress_state_from_server_dict(prog_d)
	else:
		prog = ProgressStateScript.with_default_unlocks_for_players(ts.players)
	var gs = GameStateScript.new(scen, prog, ts, true)
	var vis_d = snap.get("visibility_state", null)
	if typeof(vis_d) == TYPE_DICTIONARY:
		var vis = visibility_state_from_server_dict(vis_d as Dictionary)
		if vis != null:
			gs.visibility_state = vis
	return gs
