# Slice C14a: local plaintext cloud match credentials (user://). Not gameplay; not server state.
extends RefCounted
class_name CloudCredentialStore

const DEFAULT_PATH: String = "user://cloud_matches.json"
const STORE_VERSION: int = 1
const STATUS_UNKNOWN: String = "unknown"
const STATUS_STAGING: String = "staging"
const STATUS_ONGOING: String = "ongoing"
## Host/dev single-client flow: actor_id 0 when saving host_token from create.
const HOST_ACTOR_ID: int = 0
const HOST_TOKEN_PREFIX: String = "ht_"
const SEAT_TOKEN_PREFIX: String = "st_"
const UNSET_ACTOR_ID: int = -1
const DEFAULT_LABEL_PREFIX: String = "Match "
const MSG_DUPLICATE_DISPLAY_NAME: String = "A match with this name already exists."
const MSG_EMPTY_DISPLAY_NAME: String = "Match name cannot be empty."
const FALLBACK_UNNAMED_MATCH: String = "Unnamed match"


static func empty_store() -> Dictionary:
	return {"version": STORE_VERSION, "matches": []}


static func normalize_server_url(url: String) -> String:
	return str(url).rstrip("/")


static func normalize_match_id(match_id: String) -> String:
	return str(match_id).strip_edges()


static func _now_updated_at() -> String:
	return Time.get_datetime_string_from_system()


static func load_store(path: String = DEFAULT_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return empty_store()
	var txt: String = FileAccess.get_file_as_string(path)
	if txt.is_empty():
		return empty_store()
	var j := JSON.new()
	if j.parse(txt) != OK:
		return empty_store()
	if typeof(j.data) != TYPE_DICTIONARY:
		return empty_store()
	var d: Dictionary = j.data as Dictionary
	if int(d.get("version", 0)) != STORE_VERSION:
		return empty_store()
	var matches = d.get("matches")
	if typeof(matches) != TYPE_ARRAY:
		return empty_store()
	return d


static func save_store(path: String, data: Dictionary) -> void:
	var out: Dictionary = {
		"version": STORE_VERSION,
		"matches": data.get("matches", []) if typeof(data.get("matches")) == TYPE_ARRAY else [],
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("CloudCredentialStore: could not write %s" % path)
		return
	f.store_string(JSON.stringify(out))
	f.close()


## match_id (normalized) -> credential entry for one active server target.
static func credentials_map_for_server(path: String, server_url: String) -> Dictionary:
	var out: Dictionary = {}
	var entries: Array = entries_for_server(path, server_url)
	var i: int = 0
	while i < entries.size():
		var entry = entries[i]
		i += 1
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var mid: String = normalize_match_id(str((entry as Dictionary).get("match_id", "")))
		if mid.length() > 0:
			out[mid] = entry
	return out


static func entries_for_server(path: String, server_url: String) -> Array:
	var store := load_store(path)
	var su := normalize_server_url(server_url)
	var out: Array = []
	var matches: Array = store["matches"] as Array
	var i: int = 0
	while i < matches.size():
		var row = matches[i]
		i += 1
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = row as Dictionary
		if normalize_server_url(str(d.get("server_url", ""))) != su:
			continue
		var norm: Dictionary = normalize_entry(d)
		if host_token_from_entry(norm).is_empty() and seat_token_from_entry(norm).is_empty():
			continue
		out.append(norm)
	return out


static func _parse_match_number_from_label(label: String) -> int:
	var s: String = str(label).strip_edges()
	if not s.begins_with(DEFAULT_LABEL_PREFIX):
		return 0
	var rest: String = s.substr(DEFAULT_LABEL_PREFIX.length()).strip_edges()
	if rest.is_valid_int():
		return int(rest)
	return 0


## Next local default number: max existing **Match N** + 1 (custom labels do not consume numbers).
static func next_match_number(path: String = DEFAULT_PATH) -> int:
	var store := load_store(path)
	var matches: Array = store["matches"] as Array
	var max_n: int = 0
	var i: int = 0
	while i < matches.size():
		var row = matches[i]
		i += 1
		if typeof(row) != TYPE_DICTIONARY:
			continue
		max_n = maxi(max_n, _parse_match_number_from_label(str((row as Dictionary).get("label", ""))))
	return max_n + 1


static func next_match_number_from_display_names(display_names: Array) -> int:
	var max_n: int = 0
	var i: int = 0
	while i < display_names.size():
		max_n = maxi(max_n, _parse_match_number_from_label(str(display_names[i])))
		i += 1
	return max_n + 1


static func generate_default_label(path: String = DEFAULT_PATH) -> String:
	return "%s%d" % [DEFAULT_LABEL_PREFIX, next_match_number(path)]


static func normalize_display_name_key(name: String) -> String:
	return str(name).strip_edges().to_lower()


static func lobby_row_display_name(row: Dictionary) -> String:
	if typeof(row) != TYPE_DICTIONARY:
		return ""
	return str(row.get("display_name", "")).strip_edges()


## Case-insensitive duplicate map: normalized display_name -> match_id (from server lobby rows).
static func display_name_key_map_from_lobby(lobby_matches: Array) -> Dictionary:
	var out: Dictionary = {}
	var i: int = 0
	while i < lobby_matches.size():
		var row = lobby_matches[i]
		i += 1
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = row as Dictionary
		var dn: String = lobby_row_display_name(d)
		var key: String = normalize_display_name_key(dn)
		if key.is_empty():
			continue
		out[key] = normalize_match_id(str(d.get("match_id", "")))
	return out


static func display_names_from_lobby(lobby_matches: Array) -> Array:
	var out: Array = []
	var i: int = 0
	while i < lobby_matches.size():
		var row = lobby_matches[i]
		i += 1
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var dn: String = lobby_row_display_name(row as Dictionary)
		if dn.length() > 0:
			out.append(dn)
	return out


## Suggest **Match N** from server names only; skip keys already taken (case-insensitive).
static func generate_unique_default_label_from_server(lobby_matches: Array) -> String:
	var names: Array = display_names_from_lobby(lobby_matches)
	var key_map: Dictionary = display_name_key_map_from_lobby(lobby_matches)
	var n: int = next_match_number_from_display_names(names)
	while n < 100000:
		var candidate: String = "%s%d" % [DEFAULT_LABEL_PREFIX, n]
		if not key_map.has(normalize_display_name_key(candidate)):
			return candidate
		n += 1
	return "%s%d" % [DEFAULT_LABEL_PREFIX, n]


static func effective_create_display_name(user_text: String, default_label: String) -> String:
	var trimmed: String = str(user_text).strip_edges()
	if trimmed.length() > 0:
		return trimmed
	return str(default_label).strip_edges()


static func validate_create_display_name(
	user_text: String,
	default_label: String,
	name_key_map: Dictionary,
) -> Dictionary:
	var effective: String = effective_create_display_name(user_text, default_label)
	if effective.is_empty():
		return {"ok": false, "message": MSG_EMPTY_DISPLAY_NAME, "effective": ""}
	var key: String = normalize_display_name_key(effective)
	if typeof(name_key_map) == TYPE_DICTIONARY and name_key_map.has(key):
		return {"ok": false, "message": MSG_DUPLICATE_DISPLAY_NAME, "effective": effective}
	return {"ok": true, "message": "", "effective": effective}


static func validate_rename_display_name(
	user_text: String,
	own_match_id: String,
	name_key_map: Dictionary,
) -> Dictionary:
	var effective: String = rename_submit_body(user_text)
	if effective.is_empty():
		return {"ok": false, "message": MSG_EMPTY_DISPLAY_NAME, "effective": ""}
	var key: String = normalize_display_name_key(effective)
	var own_mid: String = normalize_match_id(own_match_id)
	if typeof(name_key_map) == TYPE_DICTIONARY and name_key_map.has(key):
		var owner: String = str(name_key_map[key])
		if owner != own_mid:
			return {"ok": false, "message": MSG_DUPLICATE_DISPLAY_NAME, "effective": effective}
	return {"ok": true, "message": "", "effective": effective}


static func resolve_label_for_save(user_input: String, path: String = DEFAULT_PATH) -> String:
	var custom: String = str(user_input).strip_edges()
	if custom.length() > 0:
		return custom
	return generate_default_label(path)


## Explicit dialog result: **confirmed** + raw **text** (never conflate cancel with empty OK).
static func empty_dialog_result(prefill: String = "") -> Dictionary:
	return {"confirmed": false, "text": str(prefill)}


## **close_requested** / outside-popup must not cancel after OK (**confirmed** already true).
static func apply_close_requested_to_dialog_result(result: Dictionary) -> Dictionary:
	var out: Dictionary = result.duplicate()
	if bool(out.get("confirmed", false)):
		return out
	out["confirmed"] = false
	return out


static func interpret_create_dialog_result(
	result: Dictionary,
	default_if_empty: String = "",
	path: String = DEFAULT_PATH,
) -> Dictionary:
	if not bool(result.get("confirmed", false)):
		return {"cancelled": true, "display_name": ""}
	var display_name: String = str(result.get("text", "")).strip_edges()
	if display_name.is_empty():
		display_name = str(default_if_empty).strip_edges()
	if display_name.is_empty():
		display_name = resolve_label_for_save("", path)
	if display_name.is_empty():
		return {"cancelled": true, "display_name": ""}
	return {"cancelled": false, "display_name": display_name}


static func interpret_rename_dialog_result(result: Dictionary) -> Dictionary:
	if not bool(result.get("confirmed", false)):
		return {"cancelled": true, "display_name": ""}
	var display_name: String = rename_submit_body(str(result.get("text", "")))
	if display_name.is_empty():
		return {"cancelled": true, "display_name": ""}
	return {"cancelled": false, "display_name": display_name}


## Legacy helper for tests simulating finalize paths.
static func finalize_dialog_text(
	edited_text: String,
	prefill: String,
	confirmed: bool,
	cancel_to_prefill: bool,
) -> String:
	if confirmed:
		return str(edited_text).strip_edges()
	if cancel_to_prefill:
		return str(prefill).strip_edges()
	return ""


static func seed_display_names_from_entries(entries: Array) -> Dictionary:
	var out: Dictionary = {}
	var i: int = 0
	while i < entries.size():
		var row = entries[i]
		i += 1
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = row as Dictionary
		var mid: String = normalize_match_id(str(d.get("match_id", "")))
		var lbl: String = str(d.get("label", "")).strip_edges()
		if mid.length() > 0 and lbl.length() > 0:
			out[mid] = lbl
	return out


static func display_label(entry: Dictionary) -> String:
	if typeof(entry) != TYPE_DICTIONARY:
		return ""
	var lbl: String = str(entry.get("label", "")).strip_edges()
	if lbl.length() > 0:
		return lbl
	return normalize_match_id(str(entry.get("match_id", "")))


## Full untruncated title: server map → local label → full match_id (never UI ellipsis).
static func full_display_name(entry: Dictionary, server_names: Dictionary = {}) -> String:
	if typeof(entry) != TYPE_DICTIONARY:
		return ""
	var mid: String = normalize_match_id(str(entry.get("match_id", "")))
	var lbl: String = str(entry.get("label", "")).strip_edges()
	var from_server: String = ""
	if mid.length() > 0 and typeof(server_names) == TYPE_DICTIONARY:
		from_server = str(server_names.get(mid, "")).strip_edges()
	if from_server.is_empty():
		if lbl.length() > 0:
			return lbl
		return mid
	return from_server


static func resolved_display_name(entry: Dictionary, server_names: Dictionary = {}) -> String:
	return full_display_name(entry, server_names)


static func short_match_id(entry: Dictionary) -> String:
	var mid: String = normalize_match_id(str(entry.get("match_id", "")))
	if mid.is_empty():
		return ""
	if mid.length() <= 24:
		return mid
	return mid.substr(0, 24) + "…"


static func format_saved_row_text(entry: Dictionary, server_names: Dictionary = {}) -> String:
	return format_saved_row_text_from_view(build_saved_row_view(entry, "", server_names))


## Saved-list row model (rename/prefill must use **display_name**, not **row_text**).
static func build_saved_row_view(
	entry: Dictionary,
	server_url: String,
	server_names: Dictionary = {},
) -> Dictionary:
	var mid: String = normalize_match_id(str(entry.get("match_id", "")))
	var su: String = normalize_server_url(
		str(entry.get("server_url", server_url)) if str(entry.get("server_url", "")) else server_url
	)
	var server_dn: String = ""
	if mid.length() > 0 and typeof(server_names) == TYPE_DICTIONARY:
		server_dn = str(server_names.get(mid, "")).strip_edges()
	var local_lbl: String = str(entry.get("label", "")).strip_edges()
	var display_full: String = full_display_name(entry, server_names)
	var view := {
		"match_id": mid,
		"server_url": su,
		"actor_id": int(entry.get("actor_id", 0)),
		"is_host": bool(entry.get("is_host", false)),
		"host_token": host_token_from_entry(entry),
		"seat_token": seat_token_from_entry(entry),
		"display_name": display_full,
		"label_local": local_lbl,
		"server_display_name": server_dn,
		"credential": entry.duplicate(true),
	}
	view["row_text"] = format_saved_row_text_from_view(view)
	return view


static func player_visible_display_name(raw_name: String) -> String:
	var name: String = str(raw_name).strip_edges()
	if name.is_empty():
		return FALLBACK_UNNAMED_MATCH
	return name


static func format_saved_row_text_from_view(view: Dictionary) -> String:
	if typeof(view) != TYPE_DICTIONARY:
		return ""
	return player_visible_display_name(str(view.get("display_name", "")))


static func row_text_hides_match_id(row_text: String, match_id: String) -> bool:
	var mid: String = normalize_match_id(match_id)
	if mid.is_empty():
		return true
	return not str(row_text).contains(mid)


static func apply_rename_to_view(view: Dictionary, new_display_name: String) -> Dictionary:
	var out: Dictionary = view.duplicate(true)
	var name: String = str(new_display_name).strip_edges()
	out["display_name"] = name
	out["server_display_name"] = name
	out["label_local"] = name
	var cred = out.get("credential", {})
	if typeof(cred) == TYPE_DICTIONARY:
		var c: Dictionary = (cred as Dictionary).duplicate(true)
		c["label"] = name
		out["credential"] = c
	out["row_text"] = format_saved_row_text_from_view(out)
	return out


static func rename_submit_body(user_text: String) -> String:
	return str(user_text).strip_edges()


static func update_label_cache(
	path: String,
	server_url: String,
	match_id: String,
	display_name: String,
) -> void:
	var existing: Dictionary = find(path, server_url, match_id)
	if existing.is_empty():
		return
	existing["label"] = str(display_name).strip_edges()
	upsert(path, existing)


static func row_text_has_no_token(row_text: String, entry: Dictionary) -> bool:
	var norm: Dictionary = normalize_entry(entry)
	for tok in [host_token_from_entry(norm), seat_token_from_entry(norm)]:
		if not tok.is_empty() and str(row_text).contains(tok):
			return false
	return true


static func rename_entry(
	path: String,
	server_url: String,
	match_id: String,
	new_label: String,
) -> bool:
	var existing: Dictionary = find(path, server_url, match_id)
	if existing.is_empty():
		return false
	var merged: Dictionary = existing.duplicate(true)
	merged["label"] = str(new_label).strip_edges()
	upsert(path, merged)
	return true


static func find(path: String, server_url: String, match_id: String) -> Dictionary:
	var store := load_store(path)
	var su := normalize_server_url(server_url)
	var mid := normalize_match_id(match_id)
	if mid.is_empty():
		return {}
	var matches: Array = store["matches"] as Array
	var i: int = 0
	while i < matches.size():
		var row = matches[i]
		i += 1
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = row as Dictionary
		if normalize_server_url(str(d.get("server_url", ""))) == su:
			if normalize_match_id(str(d.get("match_id", ""))) == mid:
				return d.duplicate(true)
	return {}


static func upsert(path: String, entry: Dictionary) -> void:
	var store := load_store(path)
	var matches: Array = (store["matches"] as Array).duplicate(true)
	var su := normalize_server_url(str(entry.get("server_url", "")))
	var mid := normalize_match_id(str(entry.get("match_id", "")))
	if mid.is_empty():
		return
	var existing: Dictionary = find(path, su, mid)
	var merged: Dictionary = merge_entry(existing, entry)
	merged["server_url"] = su
	merged["match_id"] = mid
	if not merged.has("updated_at") or str(merged.get("updated_at", "")).is_empty():
		merged["updated_at"] = _now_updated_at()
	var replaced := false
	var i: int = 0
	while i < matches.size():
		var row = matches[i]
		if typeof(row) != TYPE_DICTIONARY:
			i += 1
			continue
		var d: Dictionary = row as Dictionary
		if (
			normalize_server_url(str(d.get("server_url", ""))) == su
			and normalize_match_id(str(d.get("match_id", ""))) == mid
		):
			matches[i] = merged
			replaced = true
			break
		i += 1
	if not replaced:
		matches.append(merged)
	store["matches"] = matches
	save_store(path, store)


static func normalize_entry(entry: Dictionary) -> Dictionary:
	if typeof(entry) != TYPE_DICTIONARY:
		return {}
	var e: Dictionary = entry.duplicate(true)
	var ht: String = str(e.get("host_token", "")).strip_edges()
	var st: String = str(e.get("seat_token", "")).strip_edges()
	if ht.is_empty() and st.is_empty():
		var legacy: String = str(e.get("seat_token", "")).strip_edges()
		if legacy.begins_with(HOST_TOKEN_PREFIX):
			e["host_token"] = legacy
			e["seat_token"] = ""
		elif legacy.begins_with(SEAT_TOKEN_PREFIX):
			e["seat_token"] = legacy
	elif st.begins_with(HOST_TOKEN_PREFIX) and ht.is_empty():
		e["host_token"] = st
		e["seat_token"] = ""
	elif ht.begins_with(SEAT_TOKEN_PREFIX) and st.is_empty():
		e["seat_token"] = ht
		e["host_token"] = ""
	e["host_token"] = str(e.get("host_token", "")).strip_edges()
	e["seat_token"] = str(e.get("seat_token", "")).strip_edges()
	return e


static func host_token_from_entry(entry: Dictionary) -> String:
	return str(normalize_entry(entry).get("host_token", "")).strip_edges()


static func seat_token_from_entry(entry: Dictionary) -> String:
	var st: String = str(normalize_entry(entry).get("seat_token", "")).strip_edges()
	if st.begins_with(HOST_TOKEN_PREFIX):
		return ""
	return st


static func admin_token_from_entry(entry: Dictionary) -> String:
	return host_token_from_entry(entry)


static func gameplay_token_from_entry(entry: Dictionary) -> String:
	return seat_token_from_entry(entry)


static func merge_entry(existing: Dictionary, patch: Dictionary) -> Dictionary:
	var base: Dictionary = normalize_entry(existing) if not existing.is_empty() else {}
	var out: Dictionary = base.duplicate(true)
	if typeof(patch) != TYPE_DICTIONARY:
		return normalize_entry(out)
	var p: Dictionary = patch.duplicate(true)
	if p.has("server_url"):
		out["server_url"] = normalize_server_url(str(p["server_url"]))
	if p.has("match_id"):
		out["match_id"] = normalize_match_id(str(p["match_id"]))
	if p.has("host_token"):
		var ht: String = str(p["host_token"]).strip_edges()
		if not ht.is_empty():
			out["host_token"] = ht
	if p.has("seat_token"):
		var st: String = str(p["seat_token"]).strip_edges()
		if not st.is_empty() and not st.begins_with(HOST_TOKEN_PREFIX):
			out["seat_token"] = st
		elif not st.is_empty() and st.begins_with(HOST_TOKEN_PREFIX) and host_token_from_entry(out).is_empty():
			out["host_token"] = st
	if p.has("is_host"):
		out["is_host"] = bool(p["is_host"])
	if p.has("actor_id") and int(p["actor_id"]) >= 0:
		out["actor_id"] = int(p["actor_id"])
	if p.has("last_seen_revision"):
		out["last_seen_revision"] = int(p["last_seen_revision"])
	if p.has("last_seen_status"):
		out["last_seen_status"] = str(p["last_seen_status"])
	if p.has("label"):
		var lbl: String = str(p["label"]).strip_edges()
		if not lbl.is_empty():
			out["label"] = lbl
	if p.has("updated_at"):
		out["updated_at"] = str(p["updated_at"])
	return normalize_entry(out)


static func make_entry(
	server_url: String,
	match_id: String,
	actor_id: int = UNSET_ACTOR_ID,
	seat_token: String = "",
	is_host: bool = false,
	last_seen_revision: int = -1,
	last_seen_status: String = STATUS_UNKNOWN,
	label: String = "",
	host_token: String = "",
) -> Dictionary:
	var ht: String = str(host_token).strip_edges()
	var st: String = str(seat_token).strip_edges()
	if ht.is_empty() and st.begins_with(HOST_TOKEN_PREFIX):
		ht = st
		st = ""
	return normalize_entry(
		{
			"server_url": normalize_server_url(server_url),
			"match_id": normalize_match_id(match_id),
			"actor_id": int(actor_id),
			"host_token": ht,
			"seat_token": st,
			"is_host": is_host,
			"last_seen_status": str(last_seen_status),
			"last_seen_revision": last_seen_revision,
			"label": str(label),
			"updated_at": _now_updated_at(),
		}
	)


static func merge_host_create(
	server_url: String,
	match_id: String,
	host_token: String,
	label: String = "",
	last_seen_revision: int = -1,
	last_seen_status: String = STATUS_STAGING,
	path: String = DEFAULT_PATH,
) -> Dictionary:
	var existing: Dictionary = find(path, server_url, match_id)
	var patch: Dictionary = {
		"server_url": server_url,
		"match_id": match_id,
		"host_token": host_token,
		"is_host": true,
		"last_seen_revision": last_seen_revision,
		"last_seen_status": last_seen_status,
	}
	if not label.is_empty():
		patch["label"] = label
	var merged: Dictionary = merge_entry(existing, patch)
	upsert(path, merged)
	return merged


static func merge_seat_claim(
	server_url: String,
	match_id: String,
	seat_token: String,
	actor_id: int,
	label: String = "",
	last_seen_status: String = STATUS_STAGING,
	path: String = DEFAULT_PATH,
) -> Dictionary:
	var existing: Dictionary = find(path, server_url, match_id)
	var patch: Dictionary = {
		"server_url": server_url,
		"match_id": match_id,
		"seat_token": seat_token,
		"actor_id": int(actor_id),
		"last_seen_status": last_seen_status,
	}
	if not label.is_empty():
		patch["label"] = label
	var merged: Dictionary = merge_entry(existing, patch)
	upsert(path, merged)
	return merged


## Conservative boot resolution: env → BootIntent → inspector → saved (match_id required for store).
static func resolve_seat_token_for_boot(
	server_url: String,
	match_id: String,
	env_token: String,
	inspector_token: String,
	store_path: String = DEFAULT_PATH,
	boot_token: String = "",
) -> Dictionary:
	var et: String = str(env_token).strip_edges()
	if et.length() > 0 and et.begins_with(SEAT_TOKEN_PREFIX):
		return {"value": et, "source": "EOM_CLOUD_SEAT_TOKEN"}
	var bt: String = str(boot_token).strip_edges()
	if bt.length() > 0 and bt.begins_with(SEAT_TOKEN_PREFIX):
		return {"value": bt, "source": "BootIntent"}
	var it: String = str(inspector_token).strip_edges()
	if it.length() > 0:
		return {"value": it, "source": "Main.cloud_seat_token"}
	var mid: String = normalize_match_id(match_id)
	if mid.is_empty():
		return {"value": "", "source": ""}
	var saved: Dictionary = find(store_path, server_url, mid)
	if saved.is_empty():
		return {"value": "", "source": ""}
	var tok: String = gameplay_token_from_entry(saved)
	if tok.length() > 0:
		return {"value": tok, "source": "cloud_credential_store"}
	return {"value": "", "source": ""}


static func resolve_host_token_for_admin(
	server_url: String,
	match_id: String,
	store_path: String = DEFAULT_PATH,
	boot_host_token: String = "",
) -> Dictionary:
	var bt: String = str(boot_host_token).strip_edges()
	if bt.length() > 0 and bt.begins_with(HOST_TOKEN_PREFIX):
		return {"value": bt, "source": "BootIntent"}
	var mid: String = normalize_match_id(match_id)
	if mid.is_empty():
		return {"value": "", "source": ""}
	var saved: Dictionary = find(store_path, server_url, mid)
	if saved.is_empty():
		return {"value": "", "source": ""}
	var tok: String = admin_token_from_entry(saved)
	if tok.length() > 0:
		return {"value": tok, "source": "cloud_credential_store"}
	return {"value": "", "source": ""}


static func revision_from_response(resp: Dictionary) -> int:
	if typeof(resp) != TYPE_DICTIONARY:
		return -1
	if resp.has("revision"):
		return int(resp["revision"])
	var snap = resp.get("snapshot")
	if typeof(snap) == TYPE_DICTIONARY:
		return int((snap as Dictionary).get("revision", -1))
	return -1


static func persist_after_bootstrap(
	path: String,
	server_url: String,
	match_id: String,
	seat_token: String,
	is_host: bool,
	resp: Dictionary,
	actor_id: int = HOST_ACTOR_ID
) -> void:
	var mid := normalize_match_id(match_id)
	if mid.is_empty():
		return
	var tok: String = str(seat_token).strip_edges()
	if tok.is_empty():
		return
	var rev: int = revision_from_response(resp)
	var existing: Dictionary = find(path, server_url, mid)
	var label: String = ""
	if not existing.is_empty():
		label = str(existing.get("label", "")).strip_edges()
	if label.is_empty() and typeof(resp) == TYPE_DICTIONARY:
		label = str(resp.get("display_name", "")).strip_edges()
	var status: String = STATUS_UNKNOWN
	if not existing.is_empty():
		status = str(existing.get("last_seen_status", STATUS_UNKNOWN))
	var patch: Dictionary = {
		"server_url": server_url,
		"match_id": mid,
		"is_host": is_host,
		"last_seen_revision": rev,
		"last_seen_status": status,
	}
	if not label.is_empty():
		patch["label"] = label
	if tok.begins_with(HOST_TOKEN_PREFIX):
		patch["host_token"] = tok
	elif tok.begins_with(SEAT_TOKEN_PREFIX):
		patch["seat_token"] = tok
		if int(actor_id) >= 0:
			patch["actor_id"] = int(actor_id)
	upsert(path, merge_entry(existing, patch))


static func touch_revision(
	path: String,
	server_url: String,
	match_id: String,
	seat_token: String,
	revision: int,
	is_host: bool = false,
	actor_id: int = HOST_ACTOR_ID
) -> void:
	if revision < 0:
		return
	var existing: Dictionary = find(path, server_url, match_id)
	var patch: Dictionary = {
		"server_url": server_url,
		"match_id": match_id,
		"last_seen_revision": revision,
	}
	if not existing.is_empty():
		patch["last_seen_status"] = str(existing.get("last_seen_status", STATUS_UNKNOWN))
		if str(existing.get("label", "")).strip_edges().length() > 0:
			patch["label"] = str(existing.get("label", ""))
	var tok: String = str(seat_token).strip_edges()
	if tok.is_empty() and not existing.is_empty():
		tok = gameplay_token_from_entry(existing)
	if tok.begins_with(SEAT_TOKEN_PREFIX):
		patch["seat_token"] = tok
	if int(actor_id) >= 0:
		patch["actor_id"] = int(actor_id)
	if is_host:
		patch["is_host"] = true
	upsert(path, merge_entry(existing, patch))
