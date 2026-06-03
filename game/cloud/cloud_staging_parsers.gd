# Pure staging lobby view model (C14d-3). No HTTP; testable headless.
extends RefCounted
class_name CloudStagingParsers

const CloudCredentialStoreScript = preload("res://cloud/cloud_credential_store.gd")

const EXPECTED_SLOT_COUNT: int = 2
const STATUS_STAGING: String = CloudCredentialStoreScript.STATUS_STAGING
const STATUS_ONGOING: String = "ongoing"


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
		var faction_id: String = str(seat_row.get("faction_id", "")).strip_edges()
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
