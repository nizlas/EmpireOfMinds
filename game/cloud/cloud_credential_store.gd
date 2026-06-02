# Slice C14a: local plaintext cloud match credentials (user://). Not gameplay; not server state.
extends RefCounted
class_name CloudCredentialStore

const DEFAULT_PATH: String = "user://cloud_matches.json"
const STORE_VERSION: int = 1
const STATUS_UNKNOWN: String = "unknown"
## Host/dev single-client flow: actor_id 0 when saving host_token from create.
const HOST_ACTOR_ID: int = 0


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


## Conservative boot resolution: env/inspector token wins; else saved token only when match_id is known.
static func resolve_seat_token_for_boot(
	server_url: String,
	match_id: String,
	env_token: String,
	inspector_token: String,
	store_path: String = DEFAULT_PATH
) -> Dictionary:
	var et: String = str(env_token).strip_edges()
	if et.length() > 0:
		return {"value": et, "source": "EOM_CLOUD_SEAT_TOKEN"}
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
