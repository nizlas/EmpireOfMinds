# Async HTTP helper for Cloud 0.1 authority (Slice C8 prototype). Parent should add this node to the tree.
extends Node
class_name CloudSession

const CloudClientScript = preload("res://cloud/cloud_client.gd")
const CloudCredentialStoreScript = preload("res://cloud/cloud_credential_store.gd")

var base_url: String = "http://127.0.0.1:8000"
var match_id: String = ""
## Slice C13a: seat or host credential for POST /actions (X-Empire-Seat-Token).
var seat_token: String = ""
var _http: HTTPRequest


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 60.0
	add_child(_http)


func _method_name(m: int) -> String:
	if m == HTTPClient.METHOD_GET:
		return "GET"
	if m == HTTPClient.METHOD_POST:
		return "POST"
	if m == HTTPClient.METHOD_PATCH:
		return "PATCH"
	return str(m)


func _cloud_debug_enabled() -> bool:
	return OS.get_environment("EOM_CLOUD_DEBUG").strip_edges() == "1"


func _is_create_match_post(method: int, path: String) -> bool:
	return method == HTTPClient.METHOD_POST and path == "/v1/matches"


func _body_snippet(body_bytes: PackedByteArray, max_len: int = 160) -> String:
	var s := body_bytes.get_string_from_utf8()
	if s.length() > max_len:
		return s.substr(0, max_len) + "…"
	return s


func _create_match_snapshot_debug_fields(out: Dictionary) -> Dictionary:
	var sid := "?"
	var cell_n := -1
	var snap = out.get("snapshot", null)
	if typeof(snap) == TYPE_DICTIONARY:
		var sd := snap as Dictionary
		sid = str(sd.get("scenario_id", "?"))
		var scen = sd.get("scenario", null)
		if typeof(scen) == TYPE_DICTIONARY:
			var mp = (scen as Dictionary).get("map", null)
			if typeof(mp) == TYPE_DICTIONARY:
				var cells = (mp as Dictionary).get("cells", null)
				if typeof(cells) == TYPE_ARRAY:
					cell_n = int((cells as Array).size())
	return {"snapshot_scenario_id": sid, "map_cells": cell_n}


func http_json_request(method: int, path: String, body: String = "") -> Dictionary:
	var base_norm := str(base_url).rstrip("/")
	var full_url := base_norm + path
	var dbg := _cloud_debug_enabled()
	var is_cm := _is_create_match_post(method, path)
	var is_rename := method == HTTPClient.METHOD_PATCH and path.find("/display-name") >= 0
	var t0 := Time.get_ticks_msec()
	var headers := PackedStringArray()
	if method == HTTPClient.METHOD_POST or method == HTTPClient.METHOD_PATCH:
		headers.append("Content-Type: application/json")
	var tok := str(seat_token).strip_edges()
	if tok.length() > 0:
		headers.append("%s: %s" % [CloudClientScript.SEAT_TOKEN_HEADER, tok])
	var err := _http.request(full_url, headers, method, body)
	if err != OK:
		var el := Time.get_ticks_msec() - t0
		push_error("CloudSession: failed to start request err=%s" % err)
		if dbg and is_cm:
			print(
				(
					"SliceC8TIME create_match_transport_error t=%d elapsed_ms=%d request_err=%d path=%s full_url=%s"
					% [Time.get_ticks_msec(), el, err, path, full_url]
				)
			)
		return {"_error": "request_start", "code": err, "_path": path, "_full_url": full_url}
	var args = await _http.request_completed
	var elapsed := Time.get_ticks_msec() - t0
	var code := int(args[1])
	var body_bytes: PackedByteArray = args[3]
	print("CloudSession ", _method_name(method), " ", path, " -> HTTP ", code)
	if code < 200 or code >= 300:
		var err_txt := _body_snippet(body_bytes, 300)
		print("CloudSession error body: ", err_txt)
		var snippet_err := _body_snippet(body_bytes, 160)
		if dbg and is_cm:
			print(
				(
					"SliceC8TIME create_match_response_http_error t=%d elapsed_ms=%d http=%d path=%s full_url=%s body_snippet=%s"
					% [Time.get_ticks_msec(), elapsed, code, path, full_url, snippet_err]
				)
			)
		if dbg and is_rename:
			print(
				"SliceC14c2 rename_display_name_http_error http=%d path=%s snippet=%s"
				% [code, path, snippet_err]
			)
		return {
			"_error": "http",
			"_http_code": code,
			"_path": path,
			"_full_url": full_url,
			"_body_snippet": snippet_err,
		}
	var txt := body_bytes.get_string_from_utf8()
	var j := JSON.new()
	if j.parse(txt) != OK:
		push_warning("CloudSession: JSON parse failed for ", path)
		if dbg and is_cm:
			print(
				(
					"SliceC8TIME create_match_json_parse_failed t=%d elapsed_ms=%d http=%d path=%s snippet=%s"
					% [Time.get_ticks_msec(), elapsed, code, path, _body_snippet(body_bytes, 120)]
				)
			)
		return {}
	var data = j.data
	if typeof(data) != TYPE_DICTIONARY:
		if dbg and is_cm:
			print(
				"SliceC8TIME create_match_json_not_object t=%d elapsed_ms=%d http=%d path=%s"
				% [Time.get_ticks_msec(), elapsed, code, path]
			)
		return {}
	var out := data as Dictionary
	if dbg and is_cm:
		var sf = _create_match_snapshot_debug_fields(out)
		print(
			(
				"SliceC8TIME create_match_response_received t=%d elapsed_ms=%d http=%d snapshot_scenario_id=%s map_cells=%d"
				% [Time.get_ticks_msec(), elapsed, code, sf["snapshot_scenario_id"], sf["map_cells"]]
			)
		)
	var p = str(path)
	if p.find("/actions") >= 0:
		print(
			(
				"  … POST action accepted="
				+ str(out.get("accepted"))
				+ " reason="
				+ str(out.get("reason", ""))
				+ " revision="
				+ str(out.get("revision", "?"))
			)
		)
	elif p.find("legal-actions") >= 0:
		var ac = out.get("actions")
		var cnt = (ac as Array).size() if typeof(ac) == TYPE_ARRAY else -1
		print("  … legal-actions count=", cnt, " revision=", out.get("revision", "?"))
	return out


func post_create_match(scenario_id: String, display_name: String = "") -> Dictionary:
	var dbg := _cloud_debug_enabled()
	var path := "/v1/matches"
	var base_norm := str(base_url).rstrip("/")
	var full_url := base_norm + path
	if dbg:
		print(
			(
				"SliceC8TIME create_match_request_start t=%d base_url=%s path=%s full_url=%s scenario_id=%s"
				% [Time.get_ticks_msec(), base_norm, path, full_url, scenario_id]
			)
		)
	var body: Dictionary = CloudClientScript.build_create_match_body(scenario_id, display_name)
	var payload := JSON.stringify(body)
	if dbg:
		var keys: PackedStringArray = PackedStringArray()
		for k in body.keys():
			keys.append(str(k))
		print(
			(
				"SliceC14c2 create_match_request scenario_id=%s requested_display_name=%s body_keys=%s"
				% [scenario_id, str(body.get("display_name", "")), ",".join(keys)]
			)
		)
	var resp: Dictionary = await http_json_request(HTTPClient.METHOD_POST, path, payload)
	if dbg:
		if resp.has("_error"):
			print(
				"SliceC14c2 create_match_failed error=%s http=%s"
				% [str(resp.get("_error", "")), str(resp.get("_http_code", ""))]
			)
		else:
			var resp_dn: String = CloudClientScript.display_name_from_create_response(resp)
			print(
				"SliceC14c2 create_match_ok match_id=%s response_display_name=%s"
				% [str(resp.get("match_id", "")), resp_dn]
			)
			if body.has("display_name") and resp_dn != str(body["display_name"]):
				push_warning(
					"SliceC14c2 create_match display_name mismatch requested=%s response=%s"
					% [str(body["display_name"]), resp_dn]
				)
	return resp


func patch_display_name(match_id: String, display_name: String) -> Dictionary:
	var path: String = CloudClientScript.patch_display_name_path(match_id)
	var body: Dictionary = {
		"display_name": CloudCredentialStoreScript.rename_submit_body(display_name),
	}
	if _cloud_debug_enabled():
		print(
			"SliceC14c2 rename_display_name_request match_id=%s requested_name=%s path=%s"
			% [str(match_id).strip_edges(), body["display_name"], path]
		)
	var resp: Dictionary = await http_json_request(HTTPClient.METHOD_PATCH, path, JSON.stringify(body))
	if _cloud_debug_enabled():
		if resp.has("_error"):
			print(
				"SliceC14c2 rename_display_name_failed match_id=%s error=%s http=%s"
				% [
					str(match_id).strip_edges(),
					str(resp.get("_error", "")),
					str(resp.get("_http_code", "")),
				]
			)
		else:
			print(
				"SliceC14c2 rename_display_name_ok match_id=%s response_display_name=%s"
				% [str(match_id).strip_edges(), str(resp.get("display_name", ""))]
			)
	return resp


func get_match() -> Dictionary:
	return await http_json_request(
		HTTPClient.METHOD_GET,
		CloudClientScript.get_match_path(match_id),
	)


func get_matches_list(status_filter: String = "") -> Dictionary:
	return await http_json_request(
		HTTPClient.METHOD_GET,
		CloudClientScript.list_matches_path(status_filter),
	)


func post_claim_seat(actor_id: int) -> Dictionary:
	return await http_json_request(
		HTTPClient.METHOD_POST,
		CloudClientScript.claim_seat_path(match_id, actor_id),
	)


func post_seat_faction(actor_id: int, faction_id: String) -> Dictionary:
	var path: String = CloudClientScript.seat_faction_path(match_id, actor_id)
	var body: String = JSON.stringify({"faction_id": str(faction_id).strip_edges()})
	return await http_json_request(HTTPClient.METHOD_POST, path, body)


func post_seat_ready(actor_id: int, ready: bool) -> Dictionary:
	var path: String = CloudClientScript.seat_ready_path(match_id, actor_id)
	var body: String = JSON.stringify({"ready": bool(ready)})
	return await http_json_request(HTTPClient.METHOD_POST, path, body)


func get_legal_actions(actor_id: int, selected_unit_id: int = -1, selected_city_id: int = -1) -> Dictionary:
	var q = "?actor_id=%d" % actor_id
	if selected_unit_id >= 0:
		q += "&selected_unit_id=%d" % selected_unit_id
	if selected_city_id >= 0:
		q += "&selected_city_id=%d" % selected_city_id
	return await http_json_request(
		HTTPClient.METHOD_GET,
		"/v1/matches/%s/legal-actions%s" % [match_id, q],
	)


func post_action(action: Dictionary) -> Dictionary:
	var payload: Dictionary = CloudClientScript.normalize_api_action_for_post(action)
	var body: String = JSON.stringify(payload)
	if _cloud_debug_enabled():
		print("SliceC8DBG post_action_json_body ", body)
	return await http_json_request(
		HTTPClient.METHOD_POST,
		"/v1/matches/%s/actions" % match_id,
		body,
	)
