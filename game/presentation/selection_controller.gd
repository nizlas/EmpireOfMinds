# Mouse input: legal-destination MoveUnit (when selected) before unit re-selection; shared city/own-unit hex alternates city then unit; then unit pick on other hexes; else clear.
# Phase **5.2.5a:** after accepted **MoveUnit**, the same unit stays selected when it still exists so multi-step MP moves do not require re-picking the unit; **0** MP leaves the unit selected with no legal destinations (ring only).
# Submits actions only via game_state.try_apply. Does not mutate Scenario or Unit directly.
# See docs/SELECTION.md, docs/ACTIONS.md
class_name SelectionController
extends Node2D

const HexCoordScript = preload("res://domain/hex_coord.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const SelectionStateScript = preload("res://presentation/selection_state.gd")
const GameStateScript = preload("res://domain/game_state.gd")
const MoveUnitScript = preload("res://domain/actions/move_unit.gd")
const AttackUnitScript = preload("res://domain/actions/attack_unit.gd")
const MovementRulesScript = preload("res://domain/movement_rules.gd")
const FoundCityScript = preload("res://domain/actions/found_city.gd")
const SetCityProductionScript = preload("res://domain/actions/set_city_production.gd")
const SetCityWorkedTilesScript = preload("res://domain/actions/set_city_worked_tiles.gd")
const CompleteProgressScript = preload("res://domain/actions/complete_progress.gd")
const ProgressCandidateFilterScript = preload("res://domain/progress_candidate_filter.gd")
const CityYieldsScript = preload("res://domain/city_yields.gd")
const MapPlaneProjectionScript = preload("res://presentation/map_plane_projection.gd")
const MapCameraScript = preload("res://presentation/map_camera.gd")
const DiscoveryPopupScript = preload("res://presentation/discovery_popup.gd")
const TurnViewSyncScript = preload("res://presentation/turn_view_sync.gd")
const CloudClientScript = preload("res://cloud/cloud_client.gd")

var scenario
var game_state
var layout
## Phase 4.5m: shared **MapCamera**; Phase 4.5f — tile picks use projected hex geometry in layer-local space.
var camera
var selection
var selection_view
var units_view
var cities_view
## Phase 4.6c: optional; **scenario** / **map** / **redraw** when units move (same **GameState.scenario** as other views).
var terrain_foreground_view
## Phase 5.1.11: nameplates follow unit positions; redraw with terrain sync / map refresh.
var unit_nameplate_view
## Phase 5.1.15: city name banners follow **Scenario.cities()**.
var city_nameplate_view
## Phase 5.1.16f: map-anchored yield overlay reads **Scenario** only.
var yield_overlay_view
## Phase **5.1.17k:** terrain edge blend (**map** only); sync redraw with **`TurnViewSync`**.
var terrain_edge_blend_view
## Phase **5.2.3:** parchment overlay from **current_player_id** explored tiles.
var map_visibility_view
## Phase **5.2.4k:** lightning stump uses same visibility gating as parchment (**TurnViewSync** assigns **game_state**).
var lightning_tree_view
## Phase 5.1.16i: selected-city territory outline (**tiles_owned_by_city**); redraw with selection / sync.
var city_territory_view
## Phase **5.1.17h**: always-on owner-union perimeter (**EmpireBorderView**); redraw with terrain sync / scenario assigns.
var empire_border_view
## Phase 5.1.17e: selected-city **auto-worked** hex markers (**yield_breakdown_for_city**.worked_tiles); redraw with territory.
var city_worked_tiles_view
var turn_label
var log_view
var city_production_panel
var discovery_action_panel
var science_panel
var discovery_popup
var science_completed_popup
var city_view_state = null
## Phase **Local Combat 0.1b:** transient melee **CLASH** burst (presentation-only).
var combat_clash_burst_view
## Slice C8: server-authoritative cloud prototype (see **main.gd**).
var use_cloud_server: bool = false
var cloud_play_host = null
## Keys `"q,r"` -> submit-ready **move_unit** dict from last server legal-actions.
var cloud_move_action_by_hex: Dictionary = {}
## Slice C10: keys `"q,r"` -> submit-ready **attack_unit** dict (defender hex).
var cloud_attack_action_by_hex: Dictionary = {}
@export var marker_hit_radius_ratio: float = 0.35

## Sentinels for **shared city / own-unit hex** click alternation (see **plan_shared_hex_pick**).
const SHARED_HEX_TRACK_NONE: int = -2147483648
var _shared_track_q: int = SHARED_HEX_TRACK_NONE
var _shared_track_r: int = 0
var _shared_phase: int = 0

## Phase 4.5f — true if [pres_pt] lies inside the hex cell's **projected** polygon (matches drawn terrain); same layer-local space as [to_local] mouse.
static func projected_hex_contains(layout, camera, q: int, r: int, pres_pt: Vector2) -> bool:
	if layout == null or camera == null:
		return false
	var center = layout.hex_to_world(q, r)
	var corners = layout.hex_corners(center)
	var poly = PackedVector2Array()
	poly.resize(6)
	var i = 0
	while i < 6:
		poly[i] = camera.to_presentation(corners[i])
		i = i + 1
	return Geometry2D.is_point_in_polygon(pres_pt, poly)


## Pick the first **map** hex (centers iterated in scenario order) whose **projected** polygon contains **local_point** (Slice C8 cloud move hit-test; shared with overlay geometry).
static func pick_map_hex_at_point(scen, layout, camera, local_point: Vector2):
	if scen == null or scen.map == null or layout == null or camera == null:
		return null
	var coords = scen.map.coords()
	var hi = 0
	while hi < coords.size():
		var h = coords[hi]
		hi += 1
		if h == null:
			continue
		if projected_hex_contains(layout, camera, int(h.q), int(h.r), local_point):
			return h
	return null


## Phase **5.1.19d** — PLANNING click: toggle/add/replace **manual_worked_tiles** (order preserved; append at end; at capacity replace **last** slot).
## Returns **`Array`** of **`[q,r]`** pairs for **`SetCityWorkedTiles.make`**. Removing the last manual yields **`[]`** (auto).
static func planning_manual_worked_tiles_payload(city, clicked_q: int, clicked_r: int) -> Array:
	var manual: Array = city.manual_worked_tiles
	var idx: int = -1
	var mi: int = 0
	while mi < manual.size():
		var h = manual[mi]
		mi += 1
		if h != null and int(h.q) == int(clicked_q) and int(h.r) == int(clicked_r):
			idx = mi - 1
			break
	if idx >= 0:
		var out_remove: Array = []
		var mj: int = 0
		while mj < manual.size():
			if mj == idx:
				mj += 1
				continue
			var hx = manual[mj]
			if hx != null:
				out_remove.append([int(hx.q), int(hx.r)])
			mj += 1
		return out_remove
	var pop: int = int(city.population)
	var ms: int = manual.size()
	if ms < pop:
		var out_append: Array = []
		var mk: int = 0
		while mk < manual.size():
			var hy = manual[mk]
			if hy != null:
				out_append.append([int(hy.q), int(hy.r)])
			mk += 1
		out_append.append([int(clicked_q), int(clicked_r)])
		return out_append
	var out_replace: Array = []
	var mk2: int = 0
	while mk2 < manual.size():
		var hz = manual[mk2]
		if mk2 == ms - 1:
			out_replace.append([int(clicked_q), int(clicked_r)])
		else:
			if hz != null:
				out_replace.append([int(hz.q), int(hz.r)])
		mk2 += 1
	return out_replace


func _sort_city_ids_asc(ids: Array) -> void:
	var a = 0
	while a < ids.size():
		var b = a + 1
		while b < ids.size():
			if (ids[b] as int) < (ids[a] as int):
				var t = ids[a]
				ids[a] = ids[b]
				ids[b] = t
			b = b + 1
		a = a + 1


func _reset_shared_hex_cycle() -> void:
	_shared_track_q = SHARED_HEX_TRACK_NONE
	_shared_phase = 0


## Phase **5.2.5a** — presentation-only: after an accepted **MoveUnit**, keep **moved_unit_id** selected when that unit still exists (**`select`** clears city focus). If the unit vanished (**should not** on move), clear selection.
static func apply_post_accepted_move_unit_selection(a_selection, a_scenario, moved_unit_id: int) -> void:
	if a_selection == null or a_scenario == null:
		return
	var mu = a_scenario.unit_by_id(int(moved_unit_id))
	if mu != null:
		a_selection.select(int(mu.id))
	else:
		a_selection.clear()


## Pure helper: **shared** tile = city + current-player unit on that hex. Alternates **city** then **unit** (lowest **unit id**) on repeated clicks **same** **(q,r)**; new hex resets to **city** first. See **docs/SELECTION.md**.
static func plan_shared_hex_pick(
	track_q: int,
	track_r: int,
	phase: int,
	click_q: int,
	click_r: int,
	city_id: int,
	own_unit_ids_sorted: Array
) -> Dictionary:
	var nq: int = track_q
	var nr: int = track_r
	var ph: int = phase
	if nq != click_q or nr != click_r or nq == SHARED_HEX_TRACK_NONE:
		nq = click_q
		nr = click_r
		ph = 0
	if ph == 0:
		return {
			"pick": "city",
			"city_id": city_id,
			"next_track_q": nq,
			"next_track_r": nr,
			"next_phase": 1,
		}
	if own_unit_ids_sorted.is_empty():
		return {
			"pick": "city",
			"city_id": city_id,
			"next_track_q": nq,
			"next_track_r": nr,
			"next_phase": 1,
		}
	return {
		"pick": "unit",
		"city_id": city_id,
		"unit_id": int(own_unit_ids_sorted[0]),
		"next_track_q": nq,
		"next_track_r": nr,
		"next_phase": 0,
	}


func _refresh_city_territory_view() -> void:
	if city_territory_view != null:
		city_territory_view.queue_redraw()
	if city_worked_tiles_view != null:
		city_worked_tiles_view.queue_redraw()


func _refresh_city_production_panel() -> void:
	_refresh_city_territory_view()
	if city_production_panel != null:
		city_production_panel.refresh()
	_refresh_discovery_action_panel()
	_refresh_science_panel()


func _refresh_discovery_action_panel() -> void:
	if discovery_action_panel != null:
		discovery_action_panel.refresh()


func _sync_city_view_state_after_selection_change(previous_city_id: int) -> void:
	if city_view_state == null or not city_view_state.is_planning():
		return
	if not selection.has_city():
		city_view_state.reset_to_normal()
		return
	if previous_city_id >= 0 and previous_city_id != selection.city_id:
		city_view_state.reset_to_normal()


func _refresh_science_panel() -> void:
	if science_panel != null:
		science_panel.refresh()


func _after_accepted(prev_log_size: int) -> void:
	DiscoveryPopupScript.run_engine_popups_after_apply(
		game_state,
		discovery_popup,
		science_completed_popup,
		prev_log_size
	)


func _sync_terrain_foreground_from_game_state() -> void:
	if game_state == null:
		return
	TurnViewSyncScript.sync_terrain_related_views(
		game_state.scenario,
		terrain_foreground_view,
		unit_nameplate_view,
		city_nameplate_view,
		yield_overlay_view,
		city_territory_view,
		city_worked_tiles_view,
		empire_border_view,
		terrain_edge_blend_view,
		game_state,
		map_visibility_view,
		lightning_tree_view,
	)


func _cloud_blocks_actions() -> bool:
	return (
		use_cloud_server
		and cloud_play_host != null
		and cloud_play_host.has_method("cloud_blocks_gameplay_actions")
		and cloud_play_host.cloud_blocks_gameplay_actions()
	)


func _cloud_schedule_legal_refresh() -> void:
	if use_cloud_server and cloud_play_host != null:
		if _cloud_blocks_actions():
			return
		cloud_play_host.call_deferred("cloud_refresh_legal_async_entry")


func _unhandled_input(event):
	assert(HexCoordScript != null)
	assert(MoveUnitScript != null)
	assert(MovementRulesScript != null)
	assert(FoundCityScript != null)
	assert(SetCityProductionScript != null)
	assert(SetCityWorkedTilesScript != null)
	assert(CompleteProgressScript != null)
	assert(ProgressCandidateFilterScript != null)
	assert(CityYieldsScript != null)
	if (
		cloud_play_host != null
		and cloud_play_host.has_method("cloud_session_blocks_map_input")
		and cloud_play_host.cloud_session_blocks_map_input()
	):
		return
	if game_state == null or layout == null or selection == null or selection_view == null or units_view == null:
		return
	if event is InputEventKey:
		var ek = event as InputEventKey
		if use_cloud_server:
			if ek.pressed and not ek.echo and (ek.keycode == KEY_P or ek.keycode == KEY_G or ek.keycode == KEY_H):
				return
		if ek.pressed and not ek.echo and ek.keycode == KEY_ESCAPE:
			if city_view_state != null and city_view_state.is_planning():
				city_view_state.exit_planning()
				_refresh_city_territory_view()
				if city_production_panel != null:
					city_production_panel.refresh()
				get_viewport().set_input_as_handled()
				_cloud_schedule_legal_refresh()
				return
		if ek.pressed and not ek.echo and ek.keycode == KEY_F:
			if use_cloud_server:
				if selection.is_empty() or cloud_play_host == null:
					return
				var u_check = game_state.scenario.unit_by_id(selection.unit_id)
				if u_check == null:
					return
				var fc_cloud = cloud_play_host.cloud_pick_found_city_action()
				if fc_cloud.is_empty():
					push_warning("Cloud: no legal found_city on server list (refresh legal-actions)")
					return
				if not _cloud_blocks_actions():
					cloud_play_host.call_deferred("cloud_post_action_async_entry", fc_cloud)
				return
			if selection.is_empty():
				return
			var u_fc = game_state.scenario.unit_by_id(selection.unit_id)
			if u_fc == null:
				var prev_c_nf = selection.city_id
				selection.clear()
				if selection_view != null:
					selection_view.queue_redraw()
				if units_view != null:
					units_view.queue_redraw()
				_sync_city_view_state_after_selection_change(prev_c_nf)
				_refresh_city_production_panel()
				return
			var fc_action = FoundCityScript.make(u_fc.owner_id, u_fc.id, u_fc.position.q, u_fc.position.r)
			var prev_log_fc = game_state.log.size()
			var fc_result = game_state.try_apply(fc_action)
			if fc_result["accepted"]:
				scenario = game_state.scenario
				if selection_view != null:
					selection_view.scenario = game_state.scenario
				if units_view != null:
					units_view.scenario = game_state.scenario
				if cities_view != null:
					cities_view.scenario = game_state.scenario
				_sync_terrain_foreground_from_game_state()
				var prev_c_fc = selection.city_id
				selection.clear()
				if selection_view != null:
					selection_view.queue_redraw()
				if units_view != null:
					units_view.queue_redraw()
				if cities_view != null:
					cities_view.queue_redraw()
				_sync_city_view_state_after_selection_change(prev_c_fc)
				if turn_label != null:
					turn_label.refresh()
				if log_view != null:
					log_view.refresh()
				_refresh_city_production_panel()
				_after_accepted(prev_log_fc)
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
			var prev_log_sp = game_state.log.size()
			var sp_result = game_state.try_apply(sp_action)
			if sp_result["accepted"]:
				scenario = game_state.scenario
				if cities_view != null:
					cities_view.scenario = game_state.scenario
					cities_view.queue_redraw()
				_sync_terrain_foreground_from_game_state()
				if turn_label != null:
					turn_label.refresh()
				if log_view != null:
					log_view.refresh()
				_refresh_city_production_panel()
				_after_accepted(prev_log_sp)
			else:
				push_warning("SetCityProduction rejected: %s" % sp_result["reason"])
			return
		if ek.pressed and not ek.echo and ek.keycode == KEY_G:
			var pid = game_state.turn_state.current_player_id()
			var action = CompleteProgressScript.make(pid, "foraging_systems")
			var prev_log_g = game_state.log.size()
			var result = game_state.try_apply(action)
			if result["accepted"]:
				if turn_label != null:
					turn_label.refresh()
				if log_view != null:
					log_view.refresh()
				_refresh_city_production_panel()
				if discovery_popup != null:
					discovery_popup.maybe_show_for_log_index(int(result["index"]))
				_after_accepted(prev_log_g)
			else:
				push_warning("CompleteProgress rejected: %s" % result["reason"])
			return
		if ek.pressed and not ek.echo and ek.keycode == KEY_H:
			var candidates = ProgressCandidateFilterScript.for_current_player(game_state)
			if candidates.is_empty():
				push_warning("No progress detector candidates for current player")
				return
			var prev_log_h = game_state.log.size()
			var result_h = game_state.try_apply(candidates[0])
			if result_h["accepted"]:
				if turn_label != null:
					turn_label.refresh()
				if log_view != null:
					log_view.refresh()
				_refresh_city_production_panel()
				if discovery_popup != null:
					discovery_popup.maybe_show_for_log_index(int(result_h["index"]))
				_after_accepted(prev_log_h)
			else:
				push_warning("CompleteProgress (detector) rejected: %s" % result_h["reason"])
			return
	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var scen = game_state.scenario
			if camera == null:
				var mc = MapCameraScript.new()
				mc.projection = MapPlaneProjectionScript.new()
				camera = mc
			var local_point = to_local(get_global_mouse_position())
			if not selection.is_empty():
				var pid_atk: int = game_state.turn_state.current_player_id()
				var atk_u = scen.unit_by_id(selection.unit_id)
				if not use_cloud_server:
					if (
						atk_u != null
						and str(atk_u.type_id) == AttackUnitScript.WARRIOR_TYPE
						and int(atk_u.owner_id) == pid_atk
					):
						var def_candidates: Array = []
						var u_all_atk = scen.units()
						var ua: int = 0
						while ua < u_all_atk.size():
							var ux = u_all_atk[ua]
							if SelectionController.projected_hex_contains(
								layout, camera, ux.position.q, ux.position.r, local_point
							):
								if (
									int(ux.owner_id) != pid_atk
									and str(ux.type_id) == AttackUnitScript.WARRIOR_TYPE
									and HexCoordScript.axial_distance(atk_u.position, ux.position) == 1
								):
									def_candidates.append(int(ux.id))
							ua = ua + 1
						_sort_city_ids_asc(def_candidates)
						if def_candidates.size() > 0:
							var def_id: int = int(def_candidates[0])
							var def_u_pre = scen.unit_by_id(def_id)
							if def_u_pre == null:
								return
							var atk_q: int = int(atk_u.position.q)
							var atk_r: int = int(atk_u.position.r)
							var def_q: int = int(def_u_pre.position.q)
							var def_r: int = int(def_u_pre.position.r)
							var atk_act = AttackUnitScript.make(pid_atk, int(atk_u.id), def_id)
							var prev_log_atk = game_state.log.size()
							var atk_res = game_state.try_apply(atk_act)
							if atk_res["accepted"]:
								if combat_clash_burst_view != null:
									combat_clash_burst_view.show_burst_hex_centers(atk_q, atk_r, def_q, def_r)
								scenario = game_state.scenario
								if selection_view != null:
									selection_view.scenario = game_state.scenario
								if units_view != null:
									units_view.scenario = game_state.scenario
								_sync_terrain_foreground_from_game_state()
								_reset_shared_hex_cycle()
								var prev_c_atk = selection.city_id
								selection.clear()
								if selection_view != null:
									selection_view.queue_redraw()
								if units_view != null:
									units_view.queue_redraw()
								_sync_city_view_state_after_selection_change(prev_c_atk)
								if turn_label != null:
									turn_label.refresh()
								if log_view != null:
									log_view.refresh()
								_refresh_city_production_panel()
								_after_accepted(prev_log_atk)
							else:
								push_warning("AttackUnit rejected: %s" % atk_res["reason"])
							return
				if use_cloud_server:
					var picked_hex = pick_map_hex_at_point(scen, layout, camera, local_point)
					var dest_key = ""
					if picked_hex != null:
						dest_key = CloudClientScript.hex_action_key(int(picked_hex.q), int(picked_hex.r))
					var act_attack: Dictionary = {}
					if dest_key.length() > 0:
						var raw_atk = cloud_attack_action_by_hex.get(dest_key, null)
						if raw_atk != null and typeof(raw_atk) == TYPE_DICTIONARY:
							act_attack = raw_atk as Dictionary
					if not act_attack.is_empty() and cloud_play_host != null and not _cloud_blocks_actions():
						cloud_play_host.cloud_input_diag_log(
							"click_cloud_attack_action_before_post",
							{"action_json": JSON.stringify(act_attack)}
						)
						cloud_play_host.call_deferred("cloud_post_action_async_entry", act_attack.duplicate(true))
						get_viewport().set_input_as_handled()
						return
					var act_cloud: Dictionary = {}
					if dest_key.length() > 0:
						var raw_act = cloud_move_action_by_hex.get(dest_key, null)
						if raw_act != null and typeof(raw_act) == TYPE_DICTIONARY:
							act_cloud = raw_act as Dictionary
					var ok_cloud_move: bool = not act_cloud.is_empty()
					if cloud_play_host != null:
						cloud_play_host.cloud_input_diag_log(
							"click_cloud_move",
							{
								"unit_id": selection.unit_id,
								"dest_key_clicked": dest_key,
								"hex_keys_in_map": cloud_move_action_by_hex.keys(),
								"found_action": ok_cloud_move,
							}
						)
					if ok_cloud_move and cloud_play_host != null and not _cloud_blocks_actions():
						cloud_play_host.cloud_input_diag_log(
							"click_cloud_move_action_before_post",
							{"action_json": JSON.stringify(act_cloud)}
						)
						cloud_play_host.call_deferred("cloud_post_action_async_entry", act_cloud.duplicate(true))
						get_viewport().set_input_as_handled()
						return
					var pending = cloud_play_host != null and cloud_play_host.cloud_legal_actions_pending()
					var has_highlights = selection_view != null and (
						selection_view.cloud_destination_coords.size() > 0
						or selection_view.cloud_attack_target_coords.size() > 0
					)
					if pending and not has_highlights and not selection.is_empty():
						if cloud_play_host != null:
							cloud_play_host.cloud_input_diag_log(
								"cloud_legal_actions_pending_skip_clear",
								{"unit_id": selection.unit_id}
							)
						get_viewport().set_input_as_handled()
						return
				if not use_cloud_server:
					var dests = MovementRulesScript.legal_destinations(scen, selection.unit_id)
					var dest_hit = null
					var di = 0
					while di < dests.size():
						var dcell = dests[di]
						if SelectionController.projected_hex_contains(layout, camera, dcell.q, dcell.r, local_point):
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
						var prev_log_mv = game_state.log.size()
						var moved_unit_id: int = int(u.id)
						var result = game_state.try_apply(action)
						if result["accepted"]:
							scenario = game_state.scenario
							selection_view.scenario = game_state.scenario
							units_view.scenario = game_state.scenario
							_sync_terrain_foreground_from_game_state()
							_reset_shared_hex_cycle()
							var prev_c_mv = selection.city_id
							apply_post_accepted_move_unit_selection(selection, game_state.scenario, moved_unit_id)
							selection_view.queue_redraw()
							units_view.queue_redraw()
							_sync_city_view_state_after_selection_change(prev_c_mv)
							if turn_label != null:
								turn_label.refresh()
							if log_view != null:
								log_view.refresh()
							_refresh_city_production_panel()
							_after_accepted(prev_log_mv)
						else:
							push_warning("MoveUnit rejected: %s" % result["reason"])
						return
			if (
				not use_cloud_server
				and city_view_state != null
				and city_view_state.is_planning()
				and selection.has_city()
			):
				var c_plan = scen.city_by_id(selection.city_id)
				if (
					c_plan != null
					and int(c_plan.owner_id) == int(game_state.turn_state.current_player_id())
				):
					var pi2: int = 0
					var hit_plan: bool = false
					while pi2 < c_plan.owned_tiles.size():
						var pht = c_plan.owned_tiles[pi2]
						pi2 += 1
						if pht == null:
							continue
						if pht.q == c_plan.position.q and pht.r == c_plan.position.r:
							continue
						if not SelectionController.projected_hex_contains(
							layout, camera, pht.q, pht.r, local_point
						):
							continue
						var raw_hit: Dictionary = CityYieldsScript.raw_terrain_yield(scen.map, pht)
						var is_manual_tile: bool = false
						var mk: int = 0
						while mk < c_plan.manual_worked_tiles.size():
							var mm = c_plan.manual_worked_tiles[mk]
							mk += 1
							if mm != null and mm.q == pht.q and mm.r == pht.r:
								is_manual_tile = true
								break
						if not is_manual_tile and not CityYieldsScript._raw_yield_nonzero(raw_hit):
							continue
						var pay: Array = SelectionController.planning_manual_worked_tiles_payload(
							c_plan,
							int(pht.q),
							int(pht.r)
						)
						var sw_act = SetCityWorkedTilesScript.make(
							int(game_state.turn_state.current_player_id()),
							int(c_plan.id),
							pay
						)
						var sw_res = game_state.try_apply(sw_act)
						if sw_res["accepted"]:
							scenario = game_state.scenario
							if selection_view != null:
								selection_view.scenario = game_state.scenario
							if units_view != null:
								units_view.scenario = game_state.scenario
							if cities_view != null:
								cities_view.scenario = game_state.scenario
							_sync_terrain_foreground_from_game_state()
							if turn_label != null:
								turn_label.refresh()
							if log_view != null:
								log_view.refresh()
							_refresh_city_production_panel()
						get_viewport().set_input_as_handled()
						hit_plan = true
						break
					if hit_plan:
						return
			var city_hits: Array = []
			var cj = 0
			var c_all = scen.cities()
			while cj < c_all.size():
				var cc = c_all[cj]
				if SelectionController.projected_hex_contains(
					layout, camera, cc.position.q, cc.position.r, local_point
				):
					city_hits.append(cc.id)
				cj = cj + 1
			_sort_city_ids_asc(city_hits)
			if city_hits.size() > 0:
				var primary_cid: int = city_hits[0] as int
				var primary_cty = scen.city_by_id(primary_cid)
				if primary_cty == null:
					return
				var pq: int = int(primary_cty.position.q)
				var pr: int = int(primary_cty.position.r)
				var pid_move: int = game_state.turn_state.current_player_id()
				var own_ids_on_tile: Array = []
				var u_all = scen.units()
				var uk: int = 0
				while uk < u_all.size():
					var ux = u_all[uk]
					if int(ux.position.q) == pq and int(ux.position.r) == pr:
						if int(ux.owner_id) == pid_move:
							own_ids_on_tile.append(ux.id)
					uk = uk + 1
				_sort_city_ids_asc(own_ids_on_tile)
				var is_shared_tile: bool = own_ids_on_tile.size() > 0
				if is_shared_tile:
					var plan: Dictionary = SelectionController.plan_shared_hex_pick(
						_shared_track_q,
						_shared_track_r,
						_shared_phase,
						pq,
						pr,
						primary_cid,
						own_ids_on_tile
					)
					_shared_track_q = int(plan["next_track_q"])
					_shared_track_r = int(plan["next_track_r"])
					_shared_phase = int(plan["next_phase"])
					var prev_c_sh = selection.city_id
					if str(plan["pick"]) == "city":
						selection.select_city(int(plan["city_id"]))
					else:
						selection.select(int(plan["unit_id"]))
					_sync_city_view_state_after_selection_change(prev_c_sh)
					selection_view.queue_redraw()
					if units_view != null:
						units_view.queue_redraw()
					_refresh_city_production_panel()
					_cloud_schedule_legal_refresh()
					return
				_reset_shared_hex_cycle()
				var prev_c_pb = selection.city_id
				selection.select_city(primary_cid)
				_sync_city_view_state_after_selection_change(prev_c_pb)
				selection_view.queue_redraw()
				if units_view != null:
					units_view.queue_redraw()
				_refresh_city_production_panel()
				_cloud_schedule_legal_refresh()
				return
			_reset_shared_hex_cycle()
			var ulist = scen.units()
			var found = false
			var i = 0
			while i < ulist.size():
				var u2 = ulist[i]
				if SelectionController.projected_hex_contains(layout, camera, u2.position.q, u2.position.r, local_point):
					_reset_shared_hex_cycle()
					var prev_c_us = selection.city_id
					selection.select(u2.id)
					_sync_city_view_state_after_selection_change(prev_c_us)
					found = true
					break
				i = i + 1
			if found:
				selection_view.queue_redraw()
				if units_view != null:
					units_view.queue_redraw()
				_refresh_city_production_panel()
				_cloud_schedule_legal_refresh()
				return
			var prev_c_bg = selection.city_id
			selection.clear()
			_reset_shared_hex_cycle()
			_sync_city_view_state_after_selection_change(prev_c_bg)
			selection_view.queue_redraw()
			if units_view != null:
				units_view.queue_redraw()
			_refresh_city_production_panel()
			_cloud_schedule_legal_refresh()
