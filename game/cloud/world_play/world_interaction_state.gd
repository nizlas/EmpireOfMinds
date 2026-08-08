# N7d world interaction state (client-side presentation/session state only).
#
# Deterministic, network-free state machine for the world-play interaction
# loop: own-unit selection from terrain picks, revision/selection-bound
# served legality, End Turn gating, and out-of-turn poll gating. The scene
# (cloud_world_play.gd) owns the actual HTTP calls; this class only decides
# WHAT to do and guards the locked contracts:
#
# - Served legality only: this class never computes destinations and never
#   constructs actions client-side (including end_turn). It stores the exact
#   served rows and hands one back verbatim for submission; every marker and
#   submission maps one-to-one to a served row.
# - Two INDEPENDENT served-state slots, both bound to the CURRENT revision:
#   the summary-mode `end_turn` row and the selected-unit `move_unit` rows.
#   Every new own-turn snapshot revision refetches the summary row, and —
#   when a valid selection survives — the selection rows as well. Accepting
#   one response never clears the other; a newer snapshot clears BOTH
#   immediately; a selection change refetches only selection legality while
#   a fresh same-revision summary row stays usable. Nothing is ever retained
#   across revisions.
# - Locked served-legality freshness (docs/PHASE_PLAN.md "Planned N7d–N8d"):
#   every response is bound to its request serial, its returned `revision`,
#   the requesting actor, and the REQUESTED selection mode — the response's
#   echoed `selected_unit_id` must match the request (null for summary mode,
#   the exact unit id for selection mode). Stale or mismatched asynchronous
#   responses are discarded, never rendered, never submitted. A served row
#   is NEVER submitted when its bound revision differs from the held
#   snapshot revision.
# - Locked pick semantics feed selection ON THE OWN TURN ONLY: own-unit tile
#   pick selects, miss clears, cliff pick leaves selection unchanged. Out of
#   turn EVERY pick — including an empty miss — is completely inert (turn
#   ownership is checked before any miss-clear semantics).
# - N7g.3 attack rows: the selection slot additionally stores the served
#   `attack_unit` rows (same revision/selection binding as the move rows).
#   Attack-target tiles are looked up from the held snapshot's defender
#   positions for MARKER PLACEMENT ONLY — legality stays entirely served;
#   picking a marked defender tile submits that exact served row.
# - N7g.3 combat gate: while an accepted attack's presentation runs, BOTH
#   served slots are invalidated immediately and every gameplay pick /
#   End Turn / row render is inert. The scene enters the gate on the
#   accepted response and the gate clears on the next snapshot apply (the
#   deferred combat apply, or any superseding authoritative snapshot —
#   which also cancels the presentation itself in the view). Presentation
#   pacing only, never gameplay authority.
# - N8a cities: snapshot `cities` mirror + OWN-city selection only (same
#   ownership rule as units — foreign cities stay visible but never become
#   local selection). Locked shared-tile cycle applies only when an own
#   unit shares an OWN city tile (unit first, then alternate; changing tile
#   or clearing resets). An own unit on an enemy city tile never cycles
#   into that city. Snapshot reconcile clears `selected_city_id` when the
#   city is missing OR no longer owned by `my_actor_id` (covers one-PC
#   actor rebinding before selection validation). Served `found_city` rows
#   live in the selection slot; Found City submits the exact served row —
#   never client-built, never optimistic city create / settler consume.
#   Consumed selected settlers clear selection safely on the next snapshot
#   apply.
extends RefCounted

const CloudTurnOwnershipScript = preload("res://cloud/cloud_turn_ownership.gd")
const CloudPlayerIdentityScript = preload("res://cloud/cloud_player_identity.gd")

const PICK_NONE := "none"
const PICK_CLEAR := "clear"
const PICK_SELECT_UNIT := "select_unit"
const PICK_SELECT_CITY := "select_city"
const PICK_SUBMIT_MOVE := "submit_move"
const PICK_SUBMIT_ATTACK := "submit_attack"

const NO_SELECTION := -1

var my_actor_id: int = -1

# N7d one-PC debug (locked dual-entry direction): when true, the effective
# actor ALWAYS follows the authoritative snapshot's current player, so one
# Godot client controls both players in turn against a local authoritative
# server. Set only by the explicit dev-only opt-in (cloud_world_play guards
# EOM_CLOUD_ONE_PC_DEBUG=1 + world_map + loopback + host token); normal
# multiplayer keeps a fixed seat identity with this flag false. Response
# binding still verifies actor/revision/mode, so responses fetched for the
# PREVIOUS actor can never render or submit after a turn change.
var one_pc_debug := false

# Held authoritative snapshot state (mirrors, never mutated locally).
var revision: int = -1
var turn_state: Dictionary = {}
var units: Array = []
var cities: Array = []

# Presentation-only selection state (unit id / city id; NO_SELECTION = none).
# At most one of unit/city is selected at a time.
var selected_unit_id: int = NO_SELECTION
var selected_city_id: int = NO_SELECTION

# Served selection legality (move + N7g.3 attack + N8a found_city rows),
# bound to revision + selection (one binding — all arrive in the same
# response). City selections carry empty action lists until N8b.
var served_move_rows: Array = []
var served_attack_rows: Array = []
var served_found_city_row: Dictionary = {}
var served_move_revision: int = -1
var served_move_selection: int = NO_SELECTION
var served_city_selection: int = NO_SELECTION

# Served summary legality (end_turn row), bound to revision — independent of
# the selection slot; both may be fresh at the same time.
var end_turn_row: Dictionary = {}
var end_turn_revision: int = -1

# Independent freshness bookkeeping per request mode.
var _serial_counter: int = 0
var _pending_summary_serial: int = -1
var _pending_summary_revision: int = -1
var _pending_selection_serial: int = -1
var _pending_selection_unit: int = NO_SELECTION
var _pending_selection_city: int = NO_SELECTION
var _pending_selection_revision: int = -1

# N7f.1 arrival gate (presentation pacing only — NEVER gameplay authority
# or anti-skip enforcement; see CLOUD_PLAY.md). Entered ONLY after an
# accepted move_unit response with a usable authoritative snapshot, bound
# to the exact moved unit id and accepted revision. While active, every
# gameplay pick is inert, End Turn is disabled, no destination rows render
# or submit, and no legality is fetched — released only by the matching
# unit's real visual arrival (or a safe cancellation: the gated unit
# vanishing, turn loss, or a different-revision authoritative snapshot
# superseding the gate). Transport activity (_request_busy in the scene)
# is a deliberately separate concern.
var arrival_gate_unit_id: int = NO_SELECTION
var arrival_gate_revision: int = -1

# N7g.3 combat gate (presentation pacing only — NEVER gameplay authority).
# Entered ONLY when an accepted attack_unit's character presentation begins
# (the scene defers the accepted snapshot until the sequence ends). While
# active every gameplay pick is inert, End Turn is disabled, no rows render
# or submit, and no legality is fetched. Cleared by EVERY snapshot apply:
# the deferred combat apply on completion, or any superseding authoritative
# snapshot (which also cancels the view's presentation).
var combat_gate_active := false


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


func city_by_id(city_id: int) -> Dictionary:
	for row_variant in cities:
		if typeof(row_variant) == TYPE_DICTIONARY and int((row_variant as Dictionary).get("id", -1)) == city_id:
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


# Own city standing on `tile` (at most one city center per tile — N8a).
# Mirrors `own_unit_id_at`: a foreign city on the tile is never selectable.
func city_id_at(tile: Vector2i) -> int:
	for row_variant in cities:
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


func arrival_gate_active() -> bool:
	return arrival_gate_unit_id != NO_SELECTION


# Enters the arrival gate for one accepted move (the caller applies the
# accepted snapshot immediately afterwards — gameplay state is never
# delayed; only further local input waits for the visual arrival).
func enter_arrival_gate(unit_id: int, accepted_revision: int) -> void:
	arrival_gate_unit_id = int(unit_id)
	arrival_gate_revision = int(accepted_revision)


func clear_arrival_gate() -> void:
	arrival_gate_unit_id = NO_SELECTION
	arrival_gate_revision = -1


# Accepts one arrival completion. Releases and returns true ONLY when the
# gate is active and the arriving unit is exactly the gated one — stale or
# unrelated completions change nothing and return false.
func try_release_arrival_gate(unit_id: int) -> bool:
	if not arrival_gate_active() or int(unit_id) != arrival_gate_unit_id:
		return false
	clear_arrival_gate()
	return true


# Enters the combat gate for one accepted attack whose presentation just
# began: served legality is invalidated IMMEDIATELY (both slots), so
# nothing bound to the pre-attack state can render or submit while the
# sequence plays. The snapshot itself is deferred by the scene.
func enter_combat_gate() -> void:
	combat_gate_active = true
	_clear_served_move_rows()
	_clear_served_end_turn()


func clear_combat_gate() -> void:
	combat_gate_active = false


# Applies a (newer or initial) authoritative snapshot. Per the locked
# freshness contract BOTH served slots are cleared immediately; the return
# value says what the caller must refetch for the new revision:
# {"summary": bool, "selection": bool} — summary on every own-turn snapshot,
# selection additionally when a valid selection survives. While the
# arrival gate stays active the directives are {false, false}: no legality
# is fetched until the gated unit's real arrival.
func apply_snapshot(snap: Dictionary) -> Dictionary:
	revision = int(snap.get("revision", -1))
	var ts_variant = snap.get("turn_state", null)
	turn_state = (ts_variant as Dictionary).duplicate(true) if typeof(ts_variant) == TYPE_DICTIONARY else {}
	var units_variant = snap.get("units", null)
	units = (units_variant as Array).duplicate(true) if typeof(units_variant) == TYPE_ARRAY else []
	var cities_variant = snap.get("cities", null)
	cities = (cities_variant as Array).duplicate(true) if typeof(cities_variant) == TYPE_ARRAY else []

	# N7g.3: EVERY snapshot apply resolves the combat gate — the deferred
	# combat apply on sequence completion, and any superseding authoritative
	# snapshot (the scene cancels the view's presentation for those). The
	# gate can never outlive the state it paced.
	combat_gate_active = false

	# One-PC debug: rebind the effective actor to the snapshot's current
	# player BEFORE selection validation, so an actor change invalidates the
	# previous player's selection through the normal ownership rule and all
	# stale previous-actor responses fail the actor binding.
	if one_pc_debug:
		var current := current_player_id(turn_state)
		if current >= 0:
			my_actor_id = current

	_clear_served_move_rows()
	_clear_served_end_turn()

	# Arrival-gate housekeeping: a DIFFERENT-revision authoritative
	# snapshot supersedes the gate (external reconciliation wins; also
	# guarantees reconnect/bootstrap snapshots never keep one), and a gate
	# whose unit vanished or whose turn was lost resolves safely.
	if arrival_gate_active():
		if revision != arrival_gate_revision:
			clear_arrival_gate()
		else:
			var gated := unit_by_id(arrival_gate_unit_id)
			if gated.is_empty() or int(gated.get("owner_id", -1)) != my_actor_id or not is_my_turn():
				clear_arrival_gate()

	if not is_my_turn():
		selected_unit_id = NO_SELECTION
		selected_city_id = NO_SELECTION
		return {"summary": false, "selection": false}
	# N8a: a consumed settler (or any vanished/unowned unit) clears unit
	# selection safely — never retain a stale unit id after founding.
	if selected_unit_id != NO_SELECTION:
		var unit := unit_by_id(selected_unit_id)
		if unit.is_empty() or int(unit.get("owner_id", -1)) != my_actor_id:
			selected_unit_id = NO_SELECTION
	# Clear when missing OR no longer owned (one-PC rebinds my_actor_id
	# before this check, so the previous actor's city cannot survive).
	if selected_city_id != NO_SELECTION:
		var city := city_by_id(selected_city_id)
		if city.is_empty() or int(city.get("owner_id", -1)) != my_actor_id:
			selected_city_id = NO_SELECTION
	if arrival_gate_active():
		return {"summary": false, "selection": false}
	var has_selection := (
		selected_unit_id != NO_SELECTION or selected_city_id != NO_SELECTION
	)
	return {"summary": true, "selection": has_selection}


func is_newer_snapshot(snap: Dictionary) -> bool:
	return int(snap.get("revision", -1)) > revision


# Registers one outgoing SUMMARY-mode legal-actions request (no selection
# parameter). Returns the serial the response must present.
func begin_summary_fetch() -> int:
	_serial_counter += 1
	_pending_summary_serial = _serial_counter
	_pending_summary_revision = revision
	return _pending_summary_serial


# Registers one outgoing SELECTION-mode legal-actions request for the
# CURRENT selection (unit or city). Returns the serial the response must
# present.
func begin_selection_fetch() -> int:
	_serial_counter += 1
	_pending_selection_serial = _serial_counter
	_pending_selection_unit = selected_unit_id
	_pending_selection_city = selected_city_id
	_pending_selection_revision = revision
	return _pending_selection_serial


# Shared response binding: serial, transport health, actor echo, and the
# returned revision must all match the held state.
func _response_binding_ok(response: Dictionary, expected_revision: int) -> bool:
	if response.has("_error"):
		return false
	if int(response.get("actor_id", -2147483648)) != my_actor_id:
		return false  # response for a different actor is never ours
	if int(response.get("revision", -1)) != revision:
		return false  # bound to a revision we no longer hold
	if expected_revision != revision:
		return false  # snapshot advanced while the request was in flight
	return true


# Accepts or discards one SUMMARY-mode response. The echoed selected_unit_id
# must be null (summary mode); a mismatched echo is discarded unrendered.
# Accepting never touches the selection slot. Returns true when stored.
func accept_summary_legal_actions(serial: int, response: Dictionary) -> bool:
	if serial != _pending_summary_serial:
		return false  # superseded by a newer summary request
	if not _response_binding_ok(response, _pending_summary_revision):
		return false
	if response.get("selected_unit_id", -1) != null:
		return false  # echoed selection does not match the summary request

	_clear_served_end_turn()
	if bool(response.get("is_current_player", false)):
		var actions_variant = response.get("actions", null)
		var actions: Array = actions_variant if typeof(actions_variant) == TYPE_ARRAY else []
		for row_variant in actions:
			if typeof(row_variant) == TYPE_DICTIONARY and str((row_variant as Dictionary).get("action_type", "")) == "end_turn":
				end_turn_row = (row_variant as Dictionary).duplicate(true)
				end_turn_revision = revision
				break
	return true


# Accepts or discards one SELECTION-mode response. Echoed selected_unit_id /
# selected_city_id must match the request, and that selection must still be
# current. Accepting never touches the summary slot. Returns true when stored.
func accept_selection_legal_actions(serial: int, response: Dictionary) -> bool:
	if serial != _pending_selection_serial:
		return false  # superseded by a newer selection request
	if not _response_binding_ok(response, _pending_selection_revision):
		return false
	if (
		_pending_selection_unit != selected_unit_id
		or _pending_selection_city != selected_city_id
	):
		return false  # selection changed while the request was in flight

	var echoed_unit = response.get("selected_unit_id", null)
	var echoed_city = response.get("selected_city_id", null)
	if _pending_selection_unit != NO_SELECTION:
		if typeof(echoed_unit) != TYPE_INT and typeof(echoed_unit) != TYPE_FLOAT:
			return false
		if int(echoed_unit) != _pending_selection_unit:
			return false
	elif _pending_selection_city != NO_SELECTION:
		if typeof(echoed_city) != TYPE_INT and typeof(echoed_city) != TYPE_FLOAT:
			return false
		if int(echoed_city) != _pending_selection_city:
			return false
	else:
		return false

	_clear_served_move_rows()
	if bool(response.get("is_current_player", false)):
		var actions_variant = response.get("actions", null)
		var actions: Array = actions_variant if typeof(actions_variant) == TYPE_ARRAY else []
		for row_variant in actions:
			if typeof(row_variant) != TYPE_DICTIONARY:
				continue
			var action_type := str((row_variant as Dictionary).get("action_type", ""))
			if action_type == "move_unit":
				served_move_rows.append((row_variant as Dictionary).duplicate(true))
			elif action_type == "attack_unit":
				served_attack_rows.append((row_variant as Dictionary).duplicate(true))
			elif action_type == "found_city" and served_found_city_row.is_empty():
				served_found_city_row = (row_variant as Dictionary).duplicate(true)
		served_move_revision = revision
		served_move_selection = _pending_selection_unit
		served_city_selection = _pending_selection_city
	return true


func _served_rows_fresh() -> bool:
	# While the arrival or combat gate is active no rows render or submit —
	# markers may only return from the fresh post-release fetch.
	if arrival_gate_active() or combat_gate_active:
		return false
	if selected_unit_id == NO_SELECTION:
		return false
	return (
		served_move_revision == revision
		and served_move_selection == selected_unit_id
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


# Tile a served attack row targets: the row carries only defender_id (the
# exact N7g.1 wire shape), so the tile is the defender's position in the
# HELD authoritative snapshot — a presentation lookup for marker placement
# only, never legality. Returns null when the defender is not in the
# snapshot (the row is then unrenderable and unclickable).
func _attack_row_tile(row: Dictionary):
	var defender := unit_by_id(int(row.get("defender_id", -1)))
	var pos_variant = defender.get("position", null)
	if typeof(pos_variant) != TYPE_ARRAY or (pos_variant as Array).size() != 2:
		return null
	return Vector2i(int(pos_variant[0]), int(pos_variant[1]))


# Defender tiles of the fresh served attack rows (attack-marker input;
# empty when the binding is stale — stale rows are never rendered).
func attack_target_tiles() -> Array:
	if not _served_rows_fresh():
		return []
	var tiles: Array = []
	for row in served_attack_rows:
		var tile = _attack_row_tile(row as Dictionary)
		if tile != null:
			tiles.append(tile)
	return tiles


# The EXACT served attack row whose defender stands on `tile`, or {} when
# none / stale binding. The only path to an attack submission — never a
# client-built action.
func attack_row_for_tile(tile: Vector2i) -> Dictionary:
	if not _served_rows_fresh():
		return {}
	for row in served_attack_rows:
		if _attack_row_tile(row as Dictionary) == tile:
			return row
	return {}


func can_submit_end_turn() -> bool:
	if arrival_gate_active() or combat_gate_active:
		return false
	return is_my_turn() and not end_turn_row.is_empty() and end_turn_revision == revision


# Classifies one terrain pick into an interaction directive.
# Locked semantics: OUT OF TURN every pick — tile, cliff, or empty miss — is
# completely inert (turn ownership is checked before miss-clear). On the own
# turn: a fresh served attack target submits that exact attack row, a fresh
# served destination submits that exact move row, then the N8a shared-tile
# selection rule for an own unit + OWN city (unit first; repeated picks
# alternate), miss/foreign/empty/enemy-city tiles clear, cliffs leave
# selection unchanged.
func classify_pick(pick: Dictionary) -> Dictionary:
	# Arrival/combat gate: EVERY gameplay pick — destinations, attack
	# targets, other own units, empty tiles, misses, cliffs — is completely
	# inert until release. Selection stays untouched; camera gestures were
	# never picks (locked N4 input contract).
	if arrival_gate_active() or combat_gate_active:
		return {"kind": PICK_NONE}
	if not is_my_turn():
		return {"kind": PICK_NONE}
	if pick.is_empty():
		return {"kind": PICK_CLEAR}
	if str(pick.get("kind", "")) != "tile":
		return {"kind": PICK_NONE}
	var tile: Vector2i = pick.get("tile", Vector2i.ZERO)
	# A marked defender tile is enemy-occupied and can never also be a
	# served move destination (occupied tiles are never legal moves).
	var attack := attack_row_for_tile(tile)
	if not attack.is_empty():
		return {"kind": PICK_SUBMIT_ATTACK, "action": attack}
	var row := move_row_for_tile(tile)
	if not row.is_empty():
		return {"kind": PICK_SUBMIT_MOVE, "action": row}
	var own_id := own_unit_id_at(tile)
	var city_id := city_id_at(tile)
	if own_id >= 0 and city_id >= 0:
		# Locked shared-tile cycle: first pick → unit; same-tile repeats
		# alternate city ↔ unit. Changing tile resets via this branch.
		if selected_unit_id == own_id:
			return {"kind": PICK_SELECT_CITY, "city_id": city_id}
		if selected_city_id == city_id:
			return {"kind": PICK_SELECT_UNIT, "unit_id": own_id}
		return {"kind": PICK_SELECT_UNIT, "unit_id": own_id}
	if own_id >= 0:
		if own_id == selected_unit_id:
			return {"kind": PICK_NONE}
		return {"kind": PICK_SELECT_UNIT, "unit_id": own_id}
	if city_id >= 0:
		if city_id == selected_city_id:
			return {"kind": PICK_NONE}
		return {"kind": PICK_SELECT_CITY, "city_id": city_id}
	return {"kind": PICK_CLEAR}


# Selection changes touch ONLY the selection slot: the summary end_turn row
# stays usable while it remains bound to the current revision.
func select_unit(unit_id: int) -> void:
	selected_unit_id = int(unit_id)
	selected_city_id = NO_SELECTION
	_clear_served_move_rows()


func select_city(city_id: int) -> void:
	selected_city_id = int(city_id)
	selected_unit_id = NO_SELECTION
	_clear_served_move_rows()


func clear_selection() -> void:
	selected_unit_id = NO_SELECTION
	selected_city_id = NO_SELECTION
	_clear_served_move_rows()


# Tile of the selected unit or city (Variant: Vector2i or null) for the highlight.
func selected_tile():
	if selected_unit_id != NO_SELECTION:
		var unit := unit_by_id(selected_unit_id)
		var upos = unit.get("position", null)
		if typeof(upos) == TYPE_ARRAY and (upos as Array).size() == 2:
			return Vector2i(int(upos[0]), int(upos[1]))
		return null
	if selected_city_id != NO_SELECTION:
		var city := city_by_id(selected_city_id)
		var cpos = city.get("position", null)
		if typeof(cpos) == TYPE_ARRAY and (cpos as Array).size() == 2:
			return Vector2i(int(cpos[0]), int(cpos[1]))
	return null


func can_submit_found_city() -> bool:
	if arrival_gate_active() or combat_gate_active:
		return false
	if selected_unit_id == NO_SELECTION:
		return false
	if not _served_rows_fresh():
		return false
	return not served_found_city_row.is_empty()


# Exact served found_city row, or {} when none / stale.
func found_city_row() -> Dictionary:
	if not can_submit_found_city():
		return {}
	return served_found_city_row


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


# N7g.3 minimal selected-unit line for the status UI ("" when nothing is
# selected): authoritative type + id + current_hp straight from the held
# snapshot row (never client-computed; no max-HP invention — the snapshot
# carries current_hp only), plus the has_attacked state that explains an
# empty marker set after an attack.
func selected_unit_status_line() -> String:
	if selected_unit_id == NO_SELECTION:
		return ""
	var unit := unit_by_id(selected_unit_id)
	if unit.is_empty():
		return ""
	var line := "Selected: %s %d" % [str(unit.get("type_id", "unit")), selected_unit_id]
	if unit.has("current_hp"):
		line += " — HP %d" % int(unit.get("current_hp"))
	if bool(unit.get("has_attacked", false)):
		line += " (has attacked)"
	return line


# N8a minimal selected-city line ("" when no city is selected): authoritative
# name + id + owner from the held snapshot row only.
func selected_city_status_line() -> String:
	if selected_city_id == NO_SELECTION:
		return ""
	var city := city_by_id(selected_city_id)
	if city.is_empty():
		return ""
	return "Selected city: %s (#%d, owner %d)" % [
		str(city.get("name", "City")),
		selected_city_id,
		int(city.get("owner_id", -1)),
	]


# Minimal turn/status line (current player + own seat identity).
func status_text() -> String:
	if my_actor_id < 0:
		return "No seat identity — actions disabled (claim a seat and reconnect)."
	if turn_state.is_empty():
		return ""
	var moving_suffix := ""
	if combat_gate_active:
		moving_suffix = " — combat…"
	elif arrival_gate_active():
		moving_suffix = " — unit moving…"
	if one_pc_debug:
		return "One-PC debug — controlling %s (Player %d)%s" % [player_label(my_actor_id), my_actor_id, moving_suffix]
	if is_my_turn():
		return "Your turn — %s (Player %d)%s" % [player_label(my_actor_id), my_actor_id, moving_suffix]
	return (
		"%s — you are %s (Player %d)"
		% [
			CloudTurnOwnershipScript.WAITING_STATUS_TEXT,
			player_label(my_actor_id),
			my_actor_id,
		]
	)


func _clear_served_move_rows() -> void:
	served_move_rows = []
	served_attack_rows = []
	served_found_city_row = {}
	served_move_revision = -1
	served_move_selection = NO_SELECTION
	served_city_selection = NO_SELECTION


func _clear_served_end_turn() -> void:
	end_turn_row = {}
	end_turn_revision = -1
