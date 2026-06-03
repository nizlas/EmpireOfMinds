# Pure URL / payload helpers for tests and documentation parity (Slice C8).
extends RefCounted
class_name CloudClient

const CloudCredentialStoreScript = preload("res://cloud/cloud_credential_store.gd")

const SEAT_TOKEN_HEADER: String = "X-Empire-Seat-Token"


static func host_token_from_create_response(response: Dictionary) -> String:
	if typeof(response) != TYPE_DICTIONARY:
		return ""
	return str(response.get("host_token", "")).strip_edges()


static func display_name_from_create_response(response: Dictionary) -> String:
	if typeof(response) != TYPE_DICTIONARY:
		return ""
	return str(response.get("display_name", "")).strip_edges()


static func display_name_from_lobby_row(row: Dictionary) -> String:
	if typeof(row) != TYPE_DICTIONARY:
		return ""
	return str(row.get("display_name", "")).strip_edges()


static func patch_display_name_path(match_id: String) -> String:
	return "/v1/matches/%s/display-name" % str(match_id).strip_edges()


static func parse_rename_display_response(resp: Dictionary) -> Dictionary:
	if typeof(resp) != TYPE_DICTIONARY:
		return {"ok": false, "_error": "invalid_response"}
	if resp.has("_error"):
		return {"ok": false, "_error": resp["_error"]}
	var name: String = str(resp.get("display_name", "")).strip_edges()
	if name.is_empty():
		return {"ok": false, "_error": "missing_display_name"}
	return {
		"ok": true,
		"match_id": str(resp.get("match_id", "")).strip_edges(),
		"display_name": name,
	}


static func lobby_open_row_text(row: Dictionary, actor_id: int) -> String:
	var title: String = display_name_from_lobby_row(row)
	if title.is_empty():
		title = CloudCredentialStoreScript.short_match_id(
			{"match_id": str(row.get("match_id", ""))}
		)
	return "Join %s as Player %d" % [title, int(actor_id)]


static func seat_token_for_actor(response: Dictionary, actor_id: int) -> String:
	var seats = response.get("seats", null)
	if typeof(seats) != TYPE_ARRAY:
		return ""
	var sa: Array = seats as Array
	var i: int = 0
	while i < sa.size():
		var row = sa[i]
		i += 1
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = row as Dictionary
		if int(d.get("actor_id", -1)) == actor_id:
			return str(d.get("token", "")).strip_edges()
	return ""


static func matches_base(base_url: String, path: String) -> String:
	return str(base_url).rstrip("/") + path


## Slice **C9**: empty match id → create; non-empty → reconnect via **GET /v1/matches/{id}**.
static func should_create_match(match_id: String) -> bool:
	return str(match_id).strip_edges().is_empty()


static func get_match_path(match_id: String) -> String:
	return "/v1/matches/%s" % str(match_id).strip_edges()


static func list_matches_path(status_filter: String = "") -> String:
	var st: String = str(status_filter).strip_edges()
	if st.is_empty():
		return "/v1/matches"
	return "/v1/matches?status=%s" % st


static func claim_seat_path(match_id: String, actor_id: int) -> String:
	return "/v1/matches/%s/seats/%d/claim" % [str(match_id).strip_edges(), int(actor_id)]


static func _forbidden_token_keys() -> Array:
	return ["host_token", "seat_token", "token"]


static func lobby_row_has_no_tokens(row: Dictionary) -> bool:
	if typeof(row) != TYPE_DICTIONARY:
		return false
	for key in row.keys():
		var ks: String = str(key)
		if ks in _forbidden_token_keys() or ks.find("token") >= 0:
			return false
	var seats = row.get("seats")
	if typeof(seats) == TYPE_ARRAY:
		var i: int = 0
		while i < (seats as Array).size():
			var seat = (seats as Array)[i]
			i += 1
			if typeof(seat) != TYPE_DICTIONARY:
				continue
			for sk in (seat as Dictionary).keys():
				var sks: String = str(sk)
				if sks in _forbidden_token_keys() or sks.find("token") >= 0:
					return false
	return true


static func parse_lobby_list_response(resp: Dictionary) -> Dictionary:
	if typeof(resp) != TYPE_DICTIONARY:
		return {"matches": [], "_error": "invalid_response"}
	if resp.has("_error"):
		return {"matches": [], "_error": resp["_error"]}
	var raw = resp.get("matches")
	if typeof(raw) != TYPE_ARRAY:
		return {"matches": [], "_error": "invalid_response"}
	var out: Array = []
	var i: int = 0
	while i < (raw as Array).size():
		var row = (raw as Array)[i]
		i += 1
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = (row as Dictionary).duplicate(true)
		if lobby_row_has_no_tokens(d):
			out.append(d)
	return {"matches": out}


static func parse_claim_response(resp: Dictionary) -> Dictionary:
	if typeof(resp) != TYPE_DICTIONARY:
		return {"ok": false, "_error": "invalid_response"}
	if resp.has("_error"):
		return {"ok": false, "_error": resp["_error"]}
	var tok: String = str(resp.get("seat_token", "")).strip_edges()
	if tok.is_empty():
		return {"ok": false, "_error": "missing_seat_token"}
	return {
		"ok": true,
		"match_id": str(resp.get("match_id", "")).strip_edges(),
		"actor_id": int(resp.get("actor_id", -1)),
		"seat_token": tok,
		"status": str(resp.get("status", "")).strip_edges(),
		"display_name": str(resp.get("display_name", "")).strip_edges(),
	}


static func credential_from_create_response(
	server_url: String,
	resp: Dictionary,
	label: String = "",
	store_path: String = CloudCredentialStoreScript.DEFAULT_PATH,
) -> Dictionary:
	var mid: String = str(resp.get("match_id", "")).strip_edges()
	var host_tok: String = host_token_from_create_response(resp)
	var lbl: String = str(label).strip_edges()
	if lbl.is_empty():
		lbl = display_name_from_create_response(resp)
	if lbl.is_empty():
		lbl = CloudCredentialStoreScript.generate_default_label(store_path)
	return CloudCredentialStoreScript.make_entry(
		server_url,
		mid,
		CloudCredentialStoreScript.HOST_ACTOR_ID,
		host_tok,
		true,
		CloudCredentialStoreScript.revision_from_response(resp),
		CloudCredentialStoreScript.STATUS_STAGING,
		lbl,
	)


static func credential_from_claim_response(
	server_url: String,
	parsed: Dictionary,
	label: String = "",
	store_path: String = CloudCredentialStoreScript.DEFAULT_PATH,
) -> Dictionary:
	var lbl: String = str(label).strip_edges()
	if lbl.is_empty():
		lbl = str(parsed.get("display_name", "")).strip_edges()
	if lbl.is_empty():
		lbl = CloudCredentialStoreScript.generate_default_label(store_path)
	return CloudCredentialStoreScript.make_entry(
		server_url,
		str(parsed.get("match_id", "")),
		int(parsed.get("actor_id", 0)),
		str(parsed.get("seat_token", "")),
		false,
		-1,
		str(parsed.get("status", CloudCredentialStoreScript.STATUS_STAGING)),
		lbl,
	)


## Stable key for **cloud_move_action_by_hex** / server **move_unit** destination (axial q,r).
static func hex_action_key(q: int, r: int) -> String:
	return "%d,%d" % [q, r]


## Slice C8: **Space** means cloud **end_turn** when cloud mode is on (used with **Main._input** early routing).
static func is_cloud_space_end_turn_shortcut(cloud_mode: bool, event: InputEvent) -> bool:
	if not cloud_mode or event == null or not (event is InputEventKey):
		return false
	var ek = event as InputEventKey
	return ek.pressed and not ek.echo and ek.keycode == KEY_SPACE


static func legal_actions_path(
	match_id: String,
	actor_id: int,
	selected_unit_id: int = -1,
	selected_city_id: int = -1,
) -> String:
	var q = "?actor_id=%d" % actor_id
	if selected_unit_id >= 0:
		q += "&selected_unit_id=%d" % selected_unit_id
	if selected_city_id >= 0:
		q += "&selected_city_id=%d" % selected_city_id
	return "/v1/matches/%s/legal-actions%s" % [match_id, q]


## True only when the client should replace local presentation from `snapshot` (Slice C8 gate).
static func should_apply_snapshot(response: Dictionary) -> bool:
	if response == null or typeof(response) != TYPE_DICTIONARY:
		return false
	if response.has("_error"):
		return false
	if not bool(response.get("accepted", false)):
		return false
	return typeof(response.get("snapshot")) == TYPE_DICTIONARY


## Godot **JSON.parse** maps JSON numbers to **float**; FastAPI+Pydantic expects **int** for **actor_id** / **unit_id**
## and **move_unit** **from**/**to** (see **server/app/domain/actions/move_unit.py**). Normalize before **POST /actions**.
static func _normalize_qr_array(v) -> Array:
	if typeof(v) != TYPE_ARRAY:
		return []
	var a: Array = v
	if a.size() < 2:
		return []
	return [int(a[0]), int(a[1])]


static func normalize_api_action_for_post(action: Dictionary) -> Dictionary:
	var out: Dictionary = action.duplicate(true)
	if out.has("schema_version"):
		out["schema_version"] = int(out["schema_version"])
	if out.has("actor_id"):
		out["actor_id"] = int(out["actor_id"])
	var at: String = str(out.get("action_type", ""))
	match at:
		"move_unit":
			if out.has("unit_id"):
				out["unit_id"] = int(out["unit_id"])
			var fmq = _normalize_qr_array(out.get("from"))
			var tmq = _normalize_qr_array(out.get("to"))
			if fmq.size() == 2:
				out["from"] = fmq
			if tmq.size() == 2:
				out["to"] = tmq
		"found_city":
			if out.has("unit_id"):
				out["unit_id"] = int(out["unit_id"])
			var pos = _normalize_qr_array(out.get("position"))
			if pos.size() == 2:
				out["position"] = pos
		"set_city_production":
			if out.has("city_id"):
				out["city_id"] = int(out["city_id"])
			if out.has("project_id"):
				out["project_id"] = str(out["project_id"])
		"attack_unit":
			if out.has("attacker_id"):
				out["attacker_id"] = int(out["attacker_id"])
			if out.has("defender_id"):
				out["defender_id"] = int(out["defender_id"])
		_:
			pass
	return out


## Slice C10: build defender-hex attack target map from legal-actions rows + scenario lookup.
static func build_attack_maps_from_legal_actions(actions: Array, scenario) -> Dictionary:
	var attack_targets: Array = []
	var attack_map: Dictionary = {}
	var ai: int = 0
	while ai < actions.size():
		var row = actions[ai]
		ai += 1
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var ad: Dictionary = row as Dictionary
		if str(ad.get("action_type", "")) != "attack_unit":
			continue
		if scenario == null:
			continue
		var def_id: int = int(ad.get("defender_id", -1))
		var def_u = scenario.unit_by_id(def_id)
		if def_u == null:
			continue
		var hk: String = hex_action_key(int(def_u.position.q), int(def_u.position.r))
		if not attack_map.has(hk):
			attack_targets.append(def_u.position)
			attack_map[hk] = ad.duplicate(true)
		else:
			var existing: Dictionary = attack_map[hk] as Dictionary
			if def_id < int(existing.get("defender_id", 999999)):
				attack_map[hk] = ad.duplicate(true)
	return {"attack_targets": attack_targets, "attack_map": attack_map}


## Slice C11: cloud combat presentation — extract animation targets from accepted **attack_unit** POST response.
## Returns **should_animate** only when **event** has valid pre-combat hex positions; never infers damage/outcome.
static func combat_animation_request_from_response(response: Dictionary, action: Dictionary) -> Dictionary:
	var out := {
		"should_animate": false,
		"attacker_q": 0,
		"attacker_r": 0,
		"defender_q": 0,
		"defender_r": 0,
		"defender_damage_taken": 0,
		"retaliated": false,
	}
	if response == null or typeof(response) != TYPE_DICTIONARY:
		return out
	if typeof(action) != TYPE_DICTIONARY:
		return out
	if not bool(response.get("accepted", false)):
		return out
	if str(action.get("action_type", "")) != "attack_unit":
		return out
	var ev = response.get("event", null)
	if typeof(ev) != TYPE_DICTIONARY:
		return out
	var ed: Dictionary = ev as Dictionary
	if str(ed.get("action_type", "")) != "attack_unit":
		return out
	var atk_pos = _normalize_qr_array(ed.get("attacker_position"))
	var def_pos = _normalize_qr_array(ed.get("defender_position"))
	if atk_pos.size() < 2 or def_pos.size() < 2:
		return out
	out["should_animate"] = true
	out["attacker_q"] = int(atk_pos[0])
	out["attacker_r"] = int(atk_pos[1])
	out["defender_q"] = int(def_pos[0])
	out["defender_r"] = int(def_pos[1])
	out["defender_damage_taken"] = int(ed.get("defender_damage_taken", 0))
	out["retaliated"] = bool(ed.get("retaliated", false))
	return out


## Slice C8: show turn-start banner only on player change (or initial cloud bootstrap when **previous** is **null**).
static func should_show_turn_start_banner(previous_player_id, new_player_id: int) -> bool:
	if new_player_id < 0:
		return false
	if previous_player_id == null:
		return true
	return int(previous_player_id) != new_player_id
