# Mouse input: legal-destination MoveUnit (when selected) before unit re-selection; then unit pick; else clear.
# Submits actions only via game_state.try_apply. Does not mutate Scenario or Unit directly.
# See docs/SELECTION.md, docs/ACTIONS.md
class_name SelectionController
extends Node2D

const HexCoordScript = preload("res://domain/hex_coord.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const SelectionStateScript = preload("res://presentation/selection_state.gd")
const GameStateScript = preload("res://domain/game_state.gd")
const MoveUnitScript = preload("res://domain/actions/move_unit.gd")
const MovementRulesScript = preload("res://domain/movement_rules.gd")
const FoundCityScript = preload("res://domain/actions/found_city.gd")
const SetCityProductionScript = preload("res://domain/actions/set_city_production.gd")
const CompleteProgressScript = preload("res://domain/actions/complete_progress.gd")
const ProgressCandidateFilterScript = preload("res://domain/progress_candidate_filter.gd")
const MapPlaneProjectionScript = preload("res://presentation/map_plane_projection.gd")

var scenario
var game_state
var layout
## Phase 4.5c: shared projection; Phase 4.5f — tile picks use projected hex geometry in layer-local space.
var projection
var selection
var selection_view
var units_view
var cities_view
var turn_label
var log_view
@export var marker_hit_radius_ratio: float = 0.35

## Phase 4.5f — true if [pres_pt] lies inside the hex cell's **projected** polygon (matches drawn terrain); same layer-local space as [to_local] mouse.
static func projected_hex_contains(layout, projection, q: int, r: int, pres_pt: Vector2) -> bool:
	if layout == null or projection == null:
		return false
	var center = layout.hex_to_world(q, r)
	var corners = layout.hex_corners(center)
	var poly = PackedVector2Array()
	poly.resize(6)
	var i = 0
	while i < 6:
		poly[i] = projection.to_presentation(corners[i])
		i = i + 1
	return Geometry2D.is_point_in_polygon(pres_pt, poly)

func _unhandled_input(event):
	assert(HexCoordScript != null)
	assert(MoveUnitScript != null)
	assert(MovementRulesScript != null)
	assert(FoundCityScript != null)
	assert(SetCityProductionScript != null)
	assert(CompleteProgressScript != null)
	assert(ProgressCandidateFilterScript != null)
	if game_state == null or layout == null or selection == null or selection_view == null or units_view == null:
		return
	if event is InputEventKey:
		var ek = event as InputEventKey
		if ek.pressed and not ek.echo and ek.keycode == KEY_F:
			if selection.is_empty():
				return
			var u_fc = game_state.scenario.unit_by_id(selection.unit_id)
			if u_fc == null:
				selection.clear()
				if selection_view != null:
					selection_view.queue_redraw()
				if units_view != null:
					units_view.queue_redraw()
				return
			var fc_action = FoundCityScript.make(u_fc.owner_id, u_fc.id, u_fc.position.q, u_fc.position.r)
			var fc_result = game_state.try_apply(fc_action)
			if fc_result["accepted"]:
				scenario = game_state.scenario
				if selection_view != null:
					selection_view.scenario = game_state.scenario
				if units_view != null:
					units_view.scenario = game_state.scenario
				if cities_view != null:
					cities_view.scenario = game_state.scenario
				selection.clear()
				if selection_view != null:
					selection_view.queue_redraw()
				if units_view != null:
					units_view.queue_redraw()
				if cities_view != null:
					cities_view.queue_redraw()
				if turn_label != null:
					turn_label.refresh()
				if log_view != null:
					log_view.refresh()
			else:
				push_warning("FoundCity rejected: %s" % fc_result["reason"])
			return
		if ek.pressed and not ek.echo and ek.keycode == KEY_P:
			var pid = game_state.turn_state.current_player_id()
			var owned = game_state.scenario.cities_owned_by(pid)
			var pick_id = -1
			var oi = 0
			while oi < owned.size():
				var cy = owned[oi]
				if cy.current_project == null:
					if pick_id < 0 or cy.id < pick_id:
						pick_id = cy.id
				oi = oi + 1
			if pick_id < 0:
				push_warning("SetCityProduction: no eligible city")
				return
			var sp_action = SetCityProductionScript.make(pid, pick_id, SetCityProductionScript.PROJECT_ID_PRODUCE_UNIT_WARRIOR)
			var sp_result = game_state.try_apply(sp_action)
			if sp_result["accepted"]:
				scenario = game_state.scenario
				if cities_view != null:
					cities_view.scenario = game_state.scenario
					cities_view.queue_redraw()
				if turn_label != null:
					turn_label.refresh()
				if log_view != null:
					log_view.refresh()
			else:
				push_warning("SetCityProduction rejected: %s" % sp_result["reason"])
			return
		if ek.pressed and not ek.echo and ek.keycode == KEY_G:
			var pid = game_state.turn_state.current_player_id()
			var action = CompleteProgressScript.make(pid, "foraging_systems")
			var result = game_state.try_apply(action)
			if result["accepted"]:
				if turn_label != null:
					turn_label.refresh()
				if log_view != null:
					log_view.refresh()
			else:
				push_warning("CompleteProgress rejected: %s" % result["reason"])
			return
		if ek.pressed and not ek.echo and ek.keycode == KEY_H:
			var candidates = ProgressCandidateFilterScript.for_current_player(game_state)
			if candidates.is_empty():
				push_warning("No progress detector candidates for current player")
				return
			var result_h = game_state.try_apply(candidates[0])
			if result_h["accepted"]:
				if turn_label != null:
					turn_label.refresh()
				if log_view != null:
					log_view.refresh()
			else:
				push_warning("CompleteProgress (detector) rejected: %s" % result_h["reason"])
			return
	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var scen = game_state.scenario
			if projection == null:
				projection = MapPlaneProjectionScript.new()
			var local_point = to_local(get_global_mouse_position())
			if not selection.is_empty():
				var dests = MovementRulesScript.legal_destinations(scen, selection.unit_id)
				var dest_hit = null
				var di = 0
				while di < dests.size():
					var dcell = dests[di]
					if SelectionController.projected_hex_contains(layout, projection, dcell.q, dcell.r, local_point):
						dest_hit = dcell
						break
					di = di + 1
				if dest_hit != null:
					var u = scen.unit_by_id(selection.unit_id)
					var action = MoveUnitScript.make(
						u.owner_id,
						u.id,
						u.position.q,
						u.position.r,
						dest_hit.q,
						dest_hit.r
					)
					var result = game_state.try_apply(action)
					if result["accepted"]:
						scenario = game_state.scenario
						selection_view.scenario = game_state.scenario
						units_view.scenario = game_state.scenario
						selection.clear()
						selection_view.queue_redraw()
						units_view.queue_redraw()
						if turn_label != null:
							turn_label.refresh()
						if log_view != null:
							log_view.refresh()
					else:
						push_warning("MoveUnit rejected: %s" % result["reason"])
					return
			var ulist = scen.units()
			var found = false
			var i = 0
			while i < ulist.size():
				var u2 = ulist[i]
				if SelectionController.projected_hex_contains(layout, projection, u2.position.q, u2.position.r, local_point):
					selection.select(u2.id)
					found = true
					break
				i = i + 1
			if found:
				selection_view.queue_redraw()
				if units_view != null:
					units_view.queue_redraw()
				return
			selection.clear()
			selection_view.queue_redraw()
			if units_view != null:
				units_view.queue_redraw()
