# Slice C14a: local plaintext cloud match credentials (user://). Not gameplay; not server state.
extends RefCounted
class_name CloudCredentialStore

const DEFAULT_PATH: String = "user://cloud_matches.json"
const STORE_VERSION: int = 1
const STATUS_UNKNOWN: String = "unknown"
const STATUS_STAGING: String = "staging"
## Host/dev single-client flow: actor_id 0 when saving host_token from create.
const HOST_ACTOR_ID: int = 0
const DEFAULT_LABEL_PREFIX: String = "Match "


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
		if str(d.get("seat_token", "")).strip_edges().is_empty():
			continue
		out.append(d.duplicate(true))
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


static func generate_default_label(path: String = DEFAULT_PATH) -> String:
	return "%s%d" % [DEFAULT_LABEL_PREFIX, next_match_number(path)]


static func resolve_label_for_save(user_input: String, path: String = DEFAULT_PATH) -> String:
	var custom: String = str(user_input).strip_edges()
	if custom.length() > 0:
		return custom
	return generate_default_label(path)


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
	if mid.length() > 0 and typeof(server_names) == TYPE_DICTIONARY:
		var from_server: String = str(server_names.get(mid, "")).strip_edges()
		if from_server.length() > 0:
			return from_server
	var lbl: String = str(entry.get("label", "")).strip_edges()
	if lbl.length() > 0:
		return lbl
	return mid


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
		"seat_token": str(entry.get("seat_token", "")).strip_edges(),
		"display_name": display_full,
		"label_local": local_lbl,
		"server_display_name": server_dn,
		"credential": entry.duplicate(true),
	}
	view["row_text"] = format_saved_row_text_from_view(view)
	return view


static func format_saved_row_text_from_view(view: Dictionary) -> String:
	if typeof(view) != TYPE_DICTIONARY:
		return ""
	var host_bit: String = " (host)" if bool(view.get("is_host", false)) else ""
	var id_hint: String = str(view.get("match_id", ""))
	return "%s — actor %d%s — %s" % [
		str(view.get("display_name", "")),
		int(view.get("actor_id", 0)),
		host_bit,
		id_hint,
	]


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
	var tok: String = str(entry.get("seat_token", "")).strip_edges()
	if tok.is_empty():
		return true
	return not str(row_text).contains(tok)


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
	var merged: Dictionary = entry.duplicate(true)
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


static func make_entry(
	server_url: String,
	match_id: String,
	actor_id: int,
	seat_token: String,
	is_host: bool,
	last_seen_revision: int = -1,
	last_seen_status: String = STATUS_UNKNOWN,
	label: String = ""
) -> Dictionary:
	return {
		"server_url": normalize_server_url(server_url),
		"match_id": normalize_match_id(match_id),
		"actor_id": actor_id,
		"seat_token": str(seat_token).strip_edges(),
		"is_host": is_host,
		"last_seen_status": str(last_seen_status),
		"last_seen_revision": last_seen_revision,
		"label": str(label),
		"updated_at": _now_updated_at(),
	}


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
	if et.length() > 0:
		return {"value": et, "source": "EOM_CLOUD_SEAT_TOKEN"}
	var bt: String = str(boot_token).strip_edges()
	if bt.length() > 0:
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
	var tok: String = str(saved.get("seat_token", "")).strip_edges()
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
	upsert(
		path,
		make_entry(
			server_url,
			mid,
			actor_id,
			tok,
			is_host,
			rev,
			STATUS_UNKNOWN,
		),
	)


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
	var tok: String = str(seat_token).strip_edges()
	if tok.is_empty() and not existing.is_empty():
		tok = str(existing.get("seat_token", "")).strip_edges()
	if tok.is_empty():
		return
	var ih: bool = is_host
	if not existing.is_empty():
		ih = bool(existing.get("is_host", is_host))
	var aid: int = actor_id
	if not existing.is_empty() and existing.has("actor_id"):
		aid = int(existing["actor_id"])
	upsert(
		path,
		make_entry(
			server_url,
			match_id,
			aid,
			tok,
			ih,
			revision,
			str(existing.get("last_seen_status", STATUS_UNKNOWN)) if not existing.is_empty() else STATUS_UNKNOWN,
			str(existing.get("label", "")) if not existing.is_empty() else "",
		),
	)
