# N7d world interaction state (client-side presentation/session state only).
#
# Deterministic, network-free state machine for the world-play interaction
# loop: own-unit selection from terrain picks, revision/selection-bound
# served legality, End Turn gating, and out-of-turn poll gating. The scene
# (cloud_world_play.gd) owns the actual HTTP calls; this class only decides
# WHAT to do and guards the locked contracts:
#
# - Served legality only: this class never computes destinations. It stores
#   the exact served `move_unit` rows and hands one back verbatim for
#   submission; every marker/submission maps one-to-one to a served row.
# - Locked served-legality freshness (docs/PHASE_PLAN.md "Planned N7d–N8d"):
#   a legal-actions result is valid only for its returned `revision` AND the
#   selection that requested it. Stale asynchronous responses (superseded
#   request serial, selection changed, or revision moved on) are discarded,
#   never rendered. Every newer snapshot clears the served rows immediately
#   (apply_snapshot) and reports what to refetch. A served row is NEVER
#   submitted when its bound revision differs from the held snapshot
#   revision — move_row_for_tile / can_submit_end_turn return nothing then.
# - Locked N4 pick semantics feed selection: own-unit tile pick selects,
#   miss clears, cliff pick leaves selection unchanged. Out-of-turn picks
#   never change interaction state (action input is disabled out of turn).
# - No combat, cities, animation, or client-side legality (N7f/N7g/N8).
extends RefCounted

const CloudTurnOwnershipScript = preload("res://cloud/cloud_turn_ownership.gd")
const CloudPlayerIdentityScript = preload("res://cloud/cloud_player_identity.gd")

# Directives returned by apply_snapshot / classify_pick.
const REFETCH_NONE := ""
const REFETCH_SUMMARY := "summary"
const REFETCH_SELECTION := "selection"

const PICK_NONE := "none"
const PICK_CLEAR := "clear"
const PICK_SELECT_UNIT := "select_unit"
const PICK_SUBMIT_MOVE := "submit_move"

const NO_SELECTION := -1

var my_actor_id: int = -1

# Held authoritative snapshot state (mirrors, never mutated locally).
var revision: int = -1
var turn_state: Dictionary = {}
var units: Array = []

# Presentation-only selection state (unit id; NO_SELECTION = none).
var selected_unit_id: int = NO_SELECTION

# Served legality, bound to the revision + selection that requested it.
var served_move_rows: Array = []
var served_move_revision: int = -1
var served_move_selection: int = NO_SELECTION
var end_turn_row: Dictionary = {}
var end_turn_revision: int = -1

# Freshness bookkeeping for asynchronous legal-actions requests.
var _fetch_serial: int = 0
var _pending_serial: int = -1
var _pending_selection: int = NO_SELECTION
var _pending_revision: int = -1


func _init(p_my_actor_id: int = -1) -> void:
	my_actor_id = int(p_my_actor_id)


static func current_player_id(ts: Dictionary) -> int:
	var players_variant = ts.get("players", null)
	if typeof(players_variant) != TYPE_ARRAY:
		return -1
	var players: Array = players_variant
	var index := int(ts.get("current_index", -1))
	if index < 0 or index >= players.size():
		return -1
	return int(players[index])


func is_my_turn() -> bool:
	if my_actor_id < 0 or turn_state.is_empty():
		return false
	return current_player_id(turn_state) == my_actor_id


func unit_by_id(unit_id: int) -> Dictionary:
	for row_variant in units:
		if typeof(row_variant) == TYPE_DICTIONARY and int((row_variant as Dictionary).get("id", -1)) == unit_id:
			return row_variant
	return {}


# Own unit standing on `tile` (world occupancy: at most one unit per tile).
func own_unit_id_at(tile: Vector2i) -> int:
	for row_variant in units:
		if typeof(row_variant) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_variant
		var pos_variant = row.get("position", null)
		if typeof(pos_variant) != TYPE_ARRAY or (pos_variant as Array).size() != 2:
			continue
		var pos: Array = pos_variant
		if Vector2i(int(pos[0]), int(pos[1])) != tile:
			continue
		if int(row.get("owner_id", -1)) == my_actor_id:
			return int(row.get("id", -1))
		return NO_SELECTION
	return NO_SELECTION


# Applies a (newer or initial) authoritative snapshot. Per the locked
# freshness contract every held served row is cleared immediately; the
# return value says what the caller should refetch for the new state.
func apply_snapshot(snap: Dictionary) -> String:
	revision = int(snap.get("revision", -1))
	var ts_variant = snap.get("turn_state", null)
	turn_state = (ts_variant as Dictionary).duplicate(true) if typeof(ts_variant) == TYPE_DICTIONARY else {}
	var units_variant = snap.get("units", null)
	units = (units_variant as Array).duplicate(true) if typeof(units_variant) == TYPE_ARRAY else []

	_clear_served_rows()
	end_turn_row = {}
	end_turn_revision = -1

	if not is_my_turn():
		selected_unit_id = NO_SELECTION
		return REFETCH_NONE
	if selected_unit_id != NO_SELECTION:
		var unit := unit_by_id(selected_unit_id)
		if unit.is_empty() or int(unit.get("owner_id", -1)) != my_actor_id:
			selected_unit_id = NO_SELECTION
	return REFETCH_SELECTION if selected_unit_id != NO_SELECTION else REFETCH_SUMMARY


func is_newer_snapshot(snap: Dictionary) -> bool:
	return int(snap.get("revision", -1)) > revision


# Registers one outgoing legal-actions request for the CURRENT selection and
# revision. Returns the serial the response must present to be accepted.
func begin_legal_fetch() -> int:
	_fetch_serial += 1
	_pending_serial = _fetch_serial
	_pending_selection = selected_unit_id
	_pending_revision = revision
	return _pending_serial


# Accepts or discards one legal-actions response (locked freshness rules).
# Returns true only when the response was stored.
func accept_legal_actions(serial: int, response: Dictionary) -> bool:
	if serial != _pending_serial:
		return false  # superseded by a newer request
	if response.has("_error"):
		return false
	if int(response.get("revision", -1)) != revision:
		return false  # bound to a revision we no longer hold
	if _pending_selection != selected_unit_id:
		return false  # selection changed while the request was in flight
	if _pending_revision != revision:
		return false  # snapshot advanced while the request was in flight

	var actions_variant = response.get("actions", null)
	var actions: Array = actions_variant if typeof(actions_variant) == TYPE_ARRAY else []
	var is_current := bool(response.get("is_current_player", false))

	if _pending_selection == NO_SELECTION:
		end_turn_row = {}
		end_turn_revision = -1
		if is_current:
			for row_variant in actions:
				if typeof(row_variant) == TYPE_DICTIONARY and str((row_variant as Dictionary).get("action_type", "")) == "end_turn":
					end_turn_row = (row_variant as Dictionary).duplicate(true)
					end_turn_revision = revision
					break
		return true

	_clear_served_rows()
	if is_current:
		for row_variant in actions:
			if typeof(row_variant) == TYPE_DICTIONARY and str((row_variant as Dictionary).get("action_type", "")) == "move_unit":
				served_move_rows.append((row_variant as Dictionary).duplicate(true))
		served_move_revision = revision
		served_move_selection = _pending_selection
	return true


func _served_rows_fresh() -> bool:
	return (
		served_move_revision == revision
		and served_move_selection == selected_unit_id
		and selected_unit_id != NO_SELECTION
	)


# Destination tiles of the fresh served move rows (marker input; empty when
# the binding is stale — stale rows are never rendered).
func destination_tiles() -> Array:
	if not _served_rows_fresh():
		return []
	var tiles: Array = []
	for row in served_move_rows:
		var to_variant = (row as Dictionary).get("to", null)
		if typeof(to_variant) == TYPE_ARRAY and (to_variant as Array).size() == 2:
			tiles.append(Vector2i(int(to_variant[0]), int(to_variant[1])))
	return tiles


# The EXACT served row targeting `tile`, or {} when none / stale binding.
# This is the only path to a move submission — never a client-built action.
func move_row_for_tile(tile: Vector2i) -> Dictionary:
	if not _served_rows_fresh():
		return {}
	for row in served_move_rows:
		var to_variant = (row as Dictionary).get("to", null)
		if typeof(to_variant) == TYPE_ARRAY and (to_variant as Array).size() == 2 \
				and Vector2i(int(to_variant[0]), int(to_variant[1])) == tile:
			return row
	return {}


func can_submit_end_turn() -> bool:
	return is_my_turn() and not end_turn_row.is_empty() and end_turn_revision == revision


# Classifies one terrain pick into an interaction directive.
# Locked semantics: own-unit tile selects, miss clears, cliff unchanged;
# a fresh served destination submits that exact row; out-of-turn picks
# never change interaction state.
func classify_pick(pick: Dictionary) -> Dictionary:
	if pick.is_empty():
		return {"kind": PICK_CLEAR}
	if str(pick.get("kind", "")) != "tile":
		return {"kind": PICK_NONE}
	if not is_my_turn():
		return {"kind": PICK_NONE}
	var tile: Vector2i = pick.get("tile", Vector2i.ZERO)
	var row := move_row_for_tile(tile)
	if not row.is_empty():
		return {"kind": PICK_SUBMIT_MOVE, "action": row}
	var own_id := own_unit_id_at(tile)
	if own_id >= 0:
		if own_id == selected_unit_id:
			return {"kind": PICK_NONE}
		return {"kind": PICK_SELECT_UNIT, "unit_id": own_id}
	return {"kind": PICK_CLEAR}


func select_unit(unit_id: int) -> void:
	selected_unit_id = int(unit_id)
	_clear_served_rows()


func clear_selection() -> void:
	selected_unit_id = NO_SELECTION
	_clear_served_rows()


# Tile of the selected unit (Variant: Vector2i or null) for the highlight.
func selected_tile():
	if selected_unit_id == NO_SELECTION:
		return null
	var unit := unit_by_id(selected_unit_id)
	var pos_variant = unit.get("position", null)
	if typeof(pos_variant) != TYPE_ARRAY or (pos_variant as Array).size() != 2:
		return null
	return Vector2i(int(pos_variant[0]), int(pos_variant[1]))


# Conservative waiting poll (C14d-4b pattern, dictionary turn_state): poll
# only while seated, out of turn, and no request is already in flight.
func should_poll(request_in_flight: bool) -> bool:
	if request_in_flight or my_actor_id < 0 or turn_state.is_empty():
		return false
	return not is_my_turn()


static func player_label(player_id: int) -> String:
	var display: String = CloudPlayerIdentityScript.display_name_for_player_id(player_id)
	if display.is_empty():
		return "Player %d" % player_id
	return display


# Minimal turn/status line (current player + own seat identity).
func status_text() -> String:
	if my_actor_id < 0:
		return "No seat identity — actions disabled (claim a seat and reconnect)."
	if turn_state.is_empty():
		return ""
	if is_my_turn():
		return "Your turn — %s (Player %d)" % [player_label(my_actor_id), my_actor_id]
	return (
		"%s — you are %s (Player %d)"
		% [
			CloudTurnOwnershipScript.WAITING_STATUS_TEXT,
			player_label(my_actor_id),
			my_actor_id,
		]
	)


func _clear_served_rows() -> void:
	served_move_rows = []
	served_move_revision = -1
	served_move_selection = NO_SELECTION
