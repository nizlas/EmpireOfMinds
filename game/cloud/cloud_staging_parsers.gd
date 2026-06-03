# Pure staging lobby view model (C14d-3). No HTTP; testable headless.
extends RefCounted
class_name CloudStagingParsers

const CloudCredentialStoreScript = preload("res://cloud/cloud_credential_store.gd")

const EXPECTED_SLOT_COUNT: int = 2
const STATUS_STAGING: String = CloudCredentialStoreScript.STATUS_STAGING
const STATUS_ONGOING: String = "ongoing"
const DROPDOWN_PLACEHOLDER_LABEL: String = "Choose faction…"
const DROPDOWN_PLACEHOLDER_INDEX: int = 0


static func find_lobby_row(matches: Array, match_id: String) -> Dictionary:
	var mid: String = CloudCredentialStoreScript.normalize_match_id(match_id)
	if mid.is_empty():
		return {}
	var i: int = 0
	while i < matches.size():
		var row = matches[i]
		i += 1
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = row as Dictionary
		if CloudCredentialStoreScript.normalize_match_id(str(d.get("match_id", ""))) == mid:
			return d.duplicate(true)
	return {}


static func normalize_seat_faction_id(raw) -> String:
	if raw == null:
		return ""
	if typeof(raw) == TYPE_STRING:
		return str(raw).strip_edges()
	return str(raw).strip_edges()


static func option_index_for_faction_id(faction_choices: Array, faction_id) -> int:
	var fid: String = normalize_seat_faction_id(faction_id)
	if fid.is_empty():
		return -1
	var i: int = 0
	while i < faction_choices.size():
		var row = faction_choices[i]
		if typeof(row) != TYPE_DICTIONARY:
			i += 1
			continue
		if str((row as Dictionary).get("id", "")).strip_edges() == fid:
			return i
		i += 1
	return -1


static func faction_id_for_choice_index(faction_choices: Array, choice_index: int) -> String:
	return faction_id_for_dropdown_option_index(faction_choices, choice_index)


static func faction_id_for_faction_choice_index(faction_choices: Array, choice_index: int) -> String:
	if choice_index < 0:
		return ""
	var seen: int = 0
	var i: int = 0
	while i < faction_choices.size():
		var row = faction_choices[i]
		i += 1
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if seen == choice_index:
			return str((row as Dictionary).get("id", "")).strip_edges()
		seen += 1
	return ""


static func faction_choice_index_for_faction_id(faction_choices: Array, faction_id) -> int:
	var fid: String = normalize_seat_faction_id(faction_id)
	if fid.is_empty():
		return -1
	var seen: int = 0
	var i: int = 0
	while i < faction_choices.size():
		var row = faction_choices[i]
		i += 1
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if str((row as Dictionary).get("id", "")).strip_edges() == fid:
			return seen
		seen += 1
	return -1


static func count_faction_choice_rows(faction_choices: Array) -> int:
	var seen: int = 0
	var i: int = 0
	while i < faction_choices.size():
		var row = faction_choices[i]
		i += 1
		if typeof(row) == TYPE_DICTIONARY:
			seen += 1
	return seen


static func dropdown_item_count_for_choices(faction_choices: Array, with_placeholder: bool = true) -> int:
	var count: int = count_faction_choice_rows(faction_choices)
	if with_placeholder:
		count += 1
	return count


static func is_valid_dropdown_option_index(
	faction_choices: Array,
	option_index: int,
	with_placeholder: bool = true,
) -> bool:
	if option_index < 0:
		return false
	return option_index < dropdown_item_count_for_choices(faction_choices, with_placeholder)


static func faction_id_for_dropdown_option_index(
	faction_choices: Array,
	option_index: int,
	with_placeholder: bool = true,
) -> String:
	if not is_valid_dropdown_option_index(faction_choices, option_index, with_placeholder):
		return ""
	if with_placeholder:
		if option_index <= DROPDOWN_PLACEHOLDER_INDEX:
			return ""
		option_index -= 1
	return faction_id_for_faction_choice_index(faction_choices, option_index)


static func apply_faction_dropdown_selection(
	owned_by_me: bool,
	actor_id: int,
	local_actor_id: int,
	dropdown_index: int,
	faction_choices: Array,
	with_placeholder: bool = true,
) -> Dictionary:
	if actor_id < 0 or actor_id >= EXPECTED_SLOT_COUNT:
		return {"apply": false, "reason": "invalid_actor", "faction_id": ""}
	if not owned_by_me or local_actor_id < 0 or actor_id != local_actor_id:
		return {"apply": false, "reason": "not_owned", "faction_id": ""}
	if not is_valid_dropdown_option_index(faction_choices, dropdown_index, with_placeholder):
		return {"apply": false, "reason": "invalid_index", "faction_id": ""}
	var fid: String = faction_id_for_dropdown_option_index(faction_choices, dropdown_index, with_placeholder)
	return {"apply": true, "reason": "ok", "faction_id": fid}


static func dropdown_option_index_for_faction_id(
	faction_choices: Array,
	faction_id,
	with_placeholder: bool = true,
) -> int:
	var choice_idx: int = faction_choice_index_for_faction_id(faction_choices, faction_id)
	if with_placeholder:
		if choice_idx < 0:
			return DROPDOWN_PLACEHOLDER_INDEX
		return choice_idx + 1
	return choice_idx


static func dropdown_option_ids_for_debug(faction_choices: Array, with_placeholder: bool = true) -> Array:
	var out: Array = []
	if with_placeholder:
		out.append("")
	var i: int = 0
	while i < faction_choices.size():
		var row = faction_choices[i]
		i += 1
		if typeof(row) != TYPE_DICTIONARY:
			continue
		out.append(str((row as Dictionary).get("id", "")).strip_edges())
	return out


static func ready_enabled_after_dropdown_select(
	server_faction_id,
	faction_choices: Array,
	option_index: int,
) -> bool:
	var pending: String = faction_id_for_dropdown_option_index(faction_choices, option_index)
	return compute_slot_can_ready(true, true, false, pending, faction_choices)


static func compute_slot_can_ready(
	owned_by_me: bool,
	match_staging: bool,
	seat_ready: bool,
	pending_faction_id,
	faction_choices: Array,
) -> bool:
	if not owned_by_me or not match_staging or seat_ready:
		return false
	var pending: String = normalize_seat_faction_id(pending_faction_id)
	if pending.is_empty():
		return false
	if not is_valid_available_faction(pending, faction_choices):
		return false
	if is_faction_taken_for_me(pending, faction_choices):
		return false
	return true


static func is_valid_available_faction(faction_id: String, faction_choices: Array) -> bool:
	var fid: String = normalize_seat_faction_id(faction_id)
	if fid.is_empty():
		return false
	var i: int = 0
	while i < faction_choices.size():
		var row = faction_choices[i]
		i += 1
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if str((row as Dictionary).get("id", "")).strip_edges() == fid:
			return true
	return false


static func is_faction_taken_for_me(faction_id: String, faction_choices: Array) -> bool:
	var fid: String = normalize_seat_faction_id(faction_id)
	var i: int = 0
	while i < faction_choices.size():
		var row = faction_choices[i]
		i += 1
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = row as Dictionary
		if str(d.get("id", "")).strip_edges() == fid:
			return bool(d.get("taken", false))
	return true


static func faction_display_name_from_pending(faction_choices: Array, pending_faction_id: String) -> String:
	var fid: String = normalize_seat_faction_id(pending_faction_id)
	if fid.is_empty():
		return ""
	var i: int = 0
	while i < faction_choices.size():
		var row = faction_choices[i]
		i += 1
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = row as Dictionary
		if str(d.get("id", "")).strip_edges() == fid:
			return str(d.get("display_name", fid)).strip_edges()
	return fid


static func build_faction_post_body(faction_id: String) -> Dictionary:
	return {"faction_id": normalize_seat_faction_id(faction_id)}


static func build_ready_post_body(ready: bool) -> Dictionary:
	return {"ready": bool(ready)}


static func can_press_ready(server_faction_id, selected_faction_id, faction_choices: Array = []) -> bool:
	return compute_slot_can_ready(
		true,
		true,
		false,
		normalize_seat_faction_id(selected_faction_id),
		faction_choices,
	)


static func plan_ready_commit(server_faction_id, selected_faction_id) -> Dictionary:
	var server_fid: String = normalize_seat_faction_id(server_faction_id)
	var selected_fid: String = normalize_seat_faction_id(selected_faction_id)
	if selected_fid.is_empty() and server_fid.is_empty():
		return {
			"ok": false,
			"error": "choose_faction",
			"post_faction": false,
			"faction_id": "",
			"post_ready": false,
		}
	var post_faction: bool = not selected_fid.is_empty() and selected_fid != server_fid
	return {
		"ok": true,
		"post_faction": post_faction,
		"faction_id": selected_fid if post_faction else "",
		"post_ready": true,
	}


static func plan_unready_commit() -> Dictionary:
	return {"ok": true, "post_ready": true, "ready": false}


static func build_my_slot_ui_controls(slot: Dictionary, selected_faction_id: String = "") -> Dictionary:
	var is_mine: bool = bool(slot.get("is_mine", false))
	var claimed: bool = bool(slot.get("claimed", false))
	var ready: bool = bool(slot.get("ready", false))
	var show_mine_controls: bool = is_mine and claimed
	var server_fid: String = normalize_seat_faction_id(slot.get("faction_id"))
	return {
		"show_apply_faction_button": false,
		"show_faction_row": show_mine_controls,
		"show_ready_row": show_mine_controls,
		"faction_dropdown_editable": show_mine_controls and not ready,
		"show_ready_button": show_mine_controls and not ready,
		"show_unready_button": show_mine_controls and ready,
		"ready_button_enabled": (
			show_mine_controls
			and not ready
			and compute_slot_can_ready(
				is_mine,
				true,
				ready,
				normalize_seat_faction_id(selected_faction_id),
				slot.get("faction_choices", []) as Array,
			)
		),
	}


static func staging_user_visible_messages() -> Array:
	return [
		"Staging — claim a slot, choose a faction, then Ready.",
		"All players ready — waiting for server to start…",
		"Choose a faction before Ready.",
		"That faction is already taken — choose another.",
		"Claim a slot before entering the match.",
		"Choose a player slot before entering the match.",
		"Loading staging state…",
		"Saving faction…",
		"Marking ready…",
		"Marking not ready…",
	]


static func player_visible_text_has_no_secrets(text: String) -> bool:
	var t: String = str(text).strip_edges()
	if t.is_empty():
		return true
	var lower: String = t.to_lower()
	if lower.contains("http://") or lower.contains("https://"):
		return false
	if lower.contains("token") or lower.contains("seat_token") or lower.contains("host_token"):
		return false
	if t.begins_with("ht_") or t.begins_with("st_"):
		return false
	return true


static func seat_faction_id_from_summary(summary: Dictionary, actor_id: int) -> String:
	var seats = summary.get("seats", [])
	if typeof(seats) != TYPE_ARRAY:
		return ""
	var i: int = 0
	while i < (seats as Array).size():
		var row = (seats as Array)[i]
		i += 1
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = row as Dictionary
		if int(d.get("actor_id", -1)) == int(actor_id):
			return normalize_seat_faction_id(d.get("faction_id"))
	return ""


static func faction_display_name(available_factions: Array, faction_id: String) -> String:
	var fid: String = str(faction_id).strip_edges()
	if fid.is_empty():
		return ""
	var i: int = 0
	while i < available_factions.size():
		var row = available_factions[i]
		i += 1
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = row as Dictionary
		if str(d.get("id", "")).strip_edges() == fid:
			return str(d.get("display_name", fid)).strip_edges()
	return fid


static func taken_faction_ids(seats: Array, except_actor_id: int = -1) -> Dictionary:
	var out: Dictionary = {}
	var i: int = 0
	while i < seats.size():
		var row = seats[i]
		i += 1
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = row as Dictionary
		var aid: int = int(d.get("actor_id", -1))
		if except_actor_id >= 0 and aid == except_actor_id:
			continue
		var fid: String = str(d.get("faction_id", "")).strip_edges()
		if fid.length() > 0:
			out[fid] = true
	return out


static func build_slot_views(
	lobby_row: Dictionary,
	local_actor_id: int,
) -> Array:
	var raw_seats = lobby_row.get("seats", [])
	if typeof(raw_seats) != TYPE_ARRAY:
		return []
	var seats: Array = raw_seats as Array
	var available: Array = []
	var raw_factions = lobby_row.get("available_factions", [])
	if typeof(raw_factions) == TYPE_ARRAY:
		available = raw_factions as Array
	var taken: Dictionary = taken_faction_ids(seats, local_actor_id)
	var out: Array = []
	var si: int = 0
	while si < EXPECTED_SLOT_COUNT:
		var aid: int = si
		var seat_row: Dictionary = {}
		var sj: int = 0
		while sj < seats.size():
			var cand = seats[sj]
			sj += 1
			if typeof(cand) != TYPE_DICTIONARY:
				continue
			if int((cand as Dictionary).get("actor_id", -1)) == aid:
				seat_row = cand as Dictionary
				break
		var claimed: bool = bool(seat_row.get("claimed", false))
		var faction_id: String = normalize_seat_faction_id(seat_row.get("faction_id"))
		var ready: bool = bool(seat_row.get("ready", false))
		var is_mine: bool = local_actor_id >= 0 and aid == local_actor_id
		var faction_choices: Array = []
		var fi: int = 0
		while fi < available.size():
			var fr = available[fi]
			fi += 1
			if typeof(fr) != TYPE_DICTIONARY:
				continue
			var fd: Dictionary = fr as Dictionary
			var fid: String = str(fd.get("id", "")).strip_edges()
			if fid.is_empty():
				continue
			var choice_taken: bool = taken.has(fid)
			faction_choices.append(
				{
					"id": fid,
					"display_name": str(fd.get("display_name", fid)).strip_edges(),
					"taken": choice_taken and not (is_mine and faction_id == fid),
				}
			)
		out.append(
			{
				"actor_id": aid,
				"claimed": claimed,
				"faction_id": faction_id,
				"faction_display": faction_display_name(available, faction_id),
				"ready": ready,
				"is_mine": is_mine,
				"can_claim": not claimed and (local_actor_id < 0),
				"faction_choices": faction_choices,
			}
		)
		si += 1
	return out


static func build_staging_view(lobby_row: Dictionary, local_actor_id: int) -> Dictionary:
	if typeof(lobby_row) != TYPE_DICTIONARY or lobby_row.is_empty():
		return {"ok": false, "error": "match_not_in_list"}
	var factions = lobby_row.get("available_factions", null)
	if typeof(factions) != TYPE_ARRAY or (factions as Array).is_empty():
		return {"ok": false, "error": "missing_available_factions"}
	return {
		"ok": true,
		"match_id": CloudCredentialStoreScript.normalize_match_id(str(lobby_row.get("match_id", ""))),
		"display_name": str(lobby_row.get("display_name", "")).strip_edges(),
		"status": str(lobby_row.get("status", "")).strip_edges(),
		"ready_to_start": bool(lobby_row.get("ready_to_start", false)),
		"first_player_id": int(lobby_row.get("first_player_id", -1)),
		"slots": build_slot_views(lobby_row, local_actor_id),
		"available_factions": factions,
	}


static func saved_resume_button_label(server_status: String, has_seat_token: bool) -> String:
	var st: String = str(server_status).strip_edges()
	if st == STATUS_ONGOING and has_seat_token:
		return "Resume match"
	if st == STATUS_STAGING:
		return "Continue setup"
	if has_seat_token:
		return "Resume match"
	return "Continue setup"


static func open_staging_row_text(lobby_row: Dictionary) -> String:
	var title: String = CloudCredentialStoreScript.player_visible_display_name(
		str(lobby_row.get("display_name", "")).strip_edges()
	)
	return "Join %s" % title


static func can_enter_gameplay_from_staging(has_seat_token: bool, status: String) -> bool:
	return has_seat_token and str(status).strip_edges() == STATUS_ONGOING


static func host_only_needs_claim(has_host_token: bool, has_seat_token: bool, status: String) -> bool:
	return (
		str(status).strip_edges() == STATUS_ONGOING
		and has_host_token
		and not has_seat_token
	)
