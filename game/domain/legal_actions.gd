# Deterministic enumeration of legal action dictionaries for the current player only.
# See docs/AI_LAYER.md, docs/ACTIONS.md
class_name LegalActions
extends RefCounted

const MovementRulesScript = preload("res://domain/movement_rules.gd")
const MoveUnitScript = preload("res://domain/actions/move_unit.gd")
const EndTurnScript = preload("res://domain/actions/end_turn.gd")

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

static func for_current_player(game_state) -> Array:
	if game_state == null:
		return []
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
	out.append(EndTurnScript.make(cp))
	return out
