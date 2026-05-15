# Deterministic enumeration of legal action dictionaries for the current player only.
# See docs/AI_LAYER.md, docs/ACTIONS.md
class_name LegalActions
extends RefCounted

const MovementRulesScript = preload("res://domain/movement_rules.gd")
const MoveUnitScript = preload("res://domain/actions/move_unit.gd")
const EndTurnScript = preload("res://domain/actions/end_turn.gd")
const FoundCityScript = preload("res://domain/actions/found_city.gd")
const SetCityProductionScript = preload("res://domain/actions/set_city_production.gd")
const SetCityWorkedTilesScript = preload("res://domain/actions/set_city_worked_tiles.gd")
const CityYieldsScript = preload("res://domain/city_yields.gd")
const CityScript = preload("res://domain/city.gd")
const EffectiveRulesScript = preload("res://domain/effective_rules.gd")

static func _sort_units_by_id(units: Array) -> void:
	var a = 0
	while a < units.size():
		var b = a + 1
		while b < units.size():
			var ua = units[a]
			var ub = units[b]
			if ub.id < ua.id:
				var t = units[a]
				units[a] = units[b]
				units[b] = t
			b = b + 1
		a = a + 1


static func _sort_cities_by_id(cities: Array) -> void:
	var a = 0
	while a < cities.size():
		var b = a + 1
		while b < cities.size():
			var ca = cities[a]
			var cb = cities[b]
			if cb.id < ca.id:
				var tc = cities[a]
				cities[a] = cities[b]
				cities[b] = tc
			b = b + 1
		a = a + 1


static func _sort_coords_by_qr(coords: Array) -> void:
	var a = 0
	while a < coords.size():
		var b = a + 1
		while b < coords.size():
			var ca = coords[a]
			var cb = coords[b]
			if cb.q < ca.q or (cb.q == ca.q and cb.r < ca.r):
				var t = coords[a]
				coords[a] = coords[b]
				coords[b] = t
			b = b + 1
		a = a + 1


static func for_current_player(game_state, effective_rules = null) -> Array:
	if game_state == null:
		return []
	var er = effective_rules
	if er == null:
		er = EffectiveRulesScript.with_baseline_registries()
	var scenario = game_state.scenario
	var cp = game_state.turn_state.current_player_id()
	var owned = []
	var ulist = scenario.units()
	var i = 0
	while i < ulist.size():
		var u = ulist[i]
		if u.owner_id == cp:
			owned.append(u)
		i = i + 1
	_sort_units_by_id(owned)
	var out = []
	var ui = 0
	while ui < owned.size():
		var u2 = owned[ui]
		var dests = MovementRulesScript.legal_destinations(scenario, u2.id)
		_sort_coords_by_qr(dests)
		var di = 0
		while di < dests.size():
			var d = dests[di]
			out.append(
				MoveUnitScript.make(cp, u2.id, u2.position.q, u2.position.r, d.q, d.r)
			)
			di = di + 1
		ui = ui + 1
	var fi = 0
	while fi < owned.size():
		var u3 = owned[fi]
		var fc = FoundCityScript.make(cp, u3.id, u3.position.q, u3.position.r)
		var fv = FoundCityScript.validate(scenario, fc)
		if fv["ok"]:
			out.append(fc)
		fi = fi + 1
	var p0cities = scenario.cities_owned_by(cp)
	_sort_cities_by_id(p0cities)
	var cj = 0
	while cj < p0cities.size():
		var cy = p0cities[cj]
		if cy.current_project == null:
			var candidate_pids = [
				SetCityProductionScript.PROJECT_ID_PRODUCE_UNIT_WARRIOR,
				SetCityProductionScript.PROJECT_ID_PRODUCE_UNIT_SETTLER,
			]
			var pi = 0
			while pi < candidate_pids.size():
				var pid = candidate_pids[pi]
				if not er.is_city_project_supported(pid):
					pi = pi + 1
					continue
				var sp = SetCityProductionScript.make(cp, cy.id, pid)
				var sv = SetCityProductionScript.validate(scenario, sp)
				if sv["ok"]:
					if (
						game_state.progress_state == null
						or game_state.progress_state.has_unlocked_target(cp, "city_project", pid)
					):
						out.append(sp)
				pi = pi + 1
		cj = cj + 1
	var ck: int = 0
	while ck < p0cities.size():
		var cz = p0cities[ck]
		var elig: Array = []
		var ej: int = 0
		while ej < cz.owned_tiles.size():
			var oh = cz.owned_tiles[ej]
			ej += 1
			if oh == null:
				continue
			if oh.q == cz.position.q and oh.r == cz.position.r:
				continue
			var rw2: Dictionary = CityYieldsScript.raw_terrain_yield(scenario.map, oh)
			if not CityYieldsScript._raw_yield_nonzero(rw2):
				continue
			elig.append(oh)
		_sort_coords_by_qr(elig)
		var eq: int = 0
		while eq < elig.size():
			var ehx = elig[eq]
			var sw_a = SetCityWorkedTilesScript.make(cp, cz.id, [[ehx.q, ehx.r]])
			var sw_v = SetCityWorkedTilesScript.validate(scenario, sw_a)
			if bool(sw_v["ok"]):
				out.append(sw_a)
			eq += 1
		if (
			str(cz.worked_tiles_mode) == CityScript.WORKED_TILES_MODE_MANUAL
			and cz.manual_worked_tiles.size() > 0
		):
			var sw_c = SetCityWorkedTilesScript.make(cp, cz.id, [])
			if bool(SetCityWorkedTilesScript.validate(scenario, sw_c)["ok"]):
				out.append(sw_c)
		ck += 1
	out.append(EndTurnScript.make(cp))
	return out
