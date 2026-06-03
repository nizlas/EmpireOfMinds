# Per-slot staging UI state (C14d-3). Independent of OptionButton widget timing.
extends RefCounted

const ParsersScript = preload("res://cloud/cloud_staging_parsers.gd")


var actor_id: int = -1
var owned_by_me: bool = false
var server_faction_id: String = ""
var pending_faction_id: String = ""
var ready: bool = false
var match_staging: bool = false
var faction_choices: Array = []
var can_ready: bool = false


static func from_slot_view(slot: Dictionary, match_status: String, local_actor_id: int = -1) -> RefCounted:
	var state: RefCounted = load("res://cloud/cloud_staging_slot_state.gd").new()
	state.sync_from_server_slot(slot, match_status, local_actor_id)
	return state


func sync_from_server_slot(slot: Dictionary, match_status: String, local_actor_id: int = -1) -> void:
	actor_id = int(slot.get("actor_id", -1))
	owned_by_me = bool(slot.get("is_mine", false))
	if local_actor_id >= 0:
		owned_by_me = actor_id == local_actor_id
	ready = bool(slot.get("ready", false))
	server_faction_id = ParsersScript.normalize_seat_faction_id(slot.get("faction_id"))
	match_staging = str(match_status).strip_edges() == ParsersScript.STATUS_STAGING
	faction_choices = []
	var raw_choices = slot.get("faction_choices", [])
	if typeof(raw_choices) == TYPE_ARRAY:
		faction_choices = (raw_choices as Array).duplicate(true)
	if server_faction_id.is_empty():
		pending_faction_id = ""
	else:
		pending_faction_id = server_faction_id
	recompute_can_ready()


## Poll refresh: keep uncommitted local faction pick until server confirms a new faction_id.
func sync_from_server_slot_preserving_local_pending(
	slot: Dictionary,
	match_status: String,
	local_actor_id: int = -1,
) -> void:
	var prev_pending: String = pending_faction_id
	var prev_server: String = server_faction_id
	sync_from_server_slot(slot, match_status, local_actor_id)
	if not owned_by_me or ready or not match_staging:
		return
	if not server_faction_id.is_empty() and server_faction_id != prev_server:
		return
	if not prev_pending.is_empty() and prev_pending != server_faction_id:
		pending_faction_id = prev_pending
		recompute_can_ready()


func on_dropdown_selected(option_index: int) -> String:
	pending_faction_id = ParsersScript.faction_id_for_dropdown_option_index(
		faction_choices,
		option_index,
		true,
	)
	recompute_can_ready()
	return pending_faction_id


func dropdown_option_index_for_pending() -> int:
	return ParsersScript.dropdown_option_index_for_faction_id(faction_choices, pending_faction_id, true)


func recompute_can_ready() -> void:
	can_ready = ParsersScript.compute_slot_can_ready(
		owned_by_me,
		match_staging,
		ready,
		pending_faction_id,
		faction_choices,
	)


func plan_ready_commit() -> Dictionary:
	return ParsersScript.plan_ready_commit(server_faction_id, pending_faction_id)


func apply_render_select() -> Dictionary:
	return {
		"option_index": dropdown_option_index_for_pending(),
		"pending_faction_id": pending_faction_id,
		"cleared_pending": pending_faction_id.is_empty(),
	}


func debug_dict() -> Dictionary:
	return {
		"actor_id": actor_id,
		"server_faction_id": server_faction_id,
		"pending_faction_id": pending_faction_id,
		"ready": ready,
		"can_ready": can_ready,
	}
