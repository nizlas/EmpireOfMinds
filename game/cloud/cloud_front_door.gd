# Slice C14c: in-game front door for local hotseat and cloud lobby entry.
extends Control

const BootIntentScript = preload("res://cloud/boot_intent.gd")
const CloudSessionScript = preload("res://cloud/cloud_session.gd")
const CloudClientScript = preload("res://cloud/cloud_client.gd")
const CloudCredentialStoreScript = preload("res://cloud/cloud_credential_store.gd")

const MAIN_SCENE: String = "res://main.tscn"
const DEFAULT_SERVER_URL: String = "http://127.0.0.1:8000"

var _server_url: String = DEFAULT_SERVER_URL
var _status_label: Label
var _lobby_list: ItemList
var _saved_list: ItemList
var _busy: bool = false
var _lobby_claim_targets: Array = []
var _saved_rows: Array = []


func _ready() -> void:
	_server_url = _resolve_server_url()
	if BootIntentScript.should_skip_front_door_for_env():
		BootIntentScript.apply_env_cloud_to_boot_intent()
		get_tree().change_scene_to_file(MAIN_SCENE)
		return
	_build_ui()
	_refresh_saved_list()


func _resolve_server_url() -> String:
	var env_u: String = OS.get_environment("EOM_CLOUD_BASE_URL").strip_edges()
	if env_u.length() > 0:
		return env_u.rstrip("/")
	return DEFAULT_SERVER_URL


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 24)
	root.add_theme_constant_override("margin_right", 24)
	root.add_theme_constant_override("margin_top", 24)
	root.add_theme_constant_override("margin_bottom", 24)
	add_child(root)
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(vbox)
	var title := Label.new()
	title.text = "Empire of Minds"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	vbox.add_child(title)
	var url_lbl := Label.new()
	url_lbl.text = "Cloud server: %s" % _server_url
	url_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(url_lbl)
	var row1 := HBoxContainer.new()
	vbox.add_child(row1)
	var hotseat_btn := Button.new()
	hotseat_btn.text = "Local Hotseat"
	hotseat_btn.pressed.connect(_on_local_hotseat)
	row1.add_child(hotseat_btn)
	var create_btn := Button.new()
	create_btn.text = "Create Cloud Match"
	create_btn.pressed.connect(_on_create_cloud)
	row1.add_child(create_btn)
	var lobby_btn := Button.new()
	lobby_btn.text = "Cloud Matches (Refresh)"
	lobby_btn.pressed.connect(_on_refresh_lobby)
	row1.add_child(lobby_btn)
	_status_label = Label.new()
	_status_label.text = "Choose an option."
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_status_label)
	var lobby_hdr := Label.new()
	lobby_hdr.text = "Public staging matches (no tokens shown):"
	vbox.add_child(lobby_hdr)
	_lobby_list = ItemList.new()
	_lobby_list.custom_minimum_size = Vector2(0, 180)
	_lobby_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_lobby_list.item_selected.connect(_on_lobby_item_selected)
	vbox.add_child(_lobby_list)
	var saved_hdr := Label.new()
	saved_hdr.text = "Saved matches on this server:"
	vbox.add_child(saved_hdr)
	_saved_list = ItemList.new()
	_saved_list.custom_minimum_size = Vector2(0, 120)
	_saved_list.item_selected.connect(_on_saved_item_selected)
	vbox.add_child(_saved_list)


func _set_status(msg: String) -> void:
	if _status_label != null:
		_status_label.text = msg


func _set_busy(on: bool) -> void:
	_busy = on


func _go_main() -> void:
	get_tree().change_scene_to_file(MAIN_SCENE)


func _on_local_hotseat() -> void:
	BootIntentScript.set_local_hotseat()
	_go_main()


func _make_session() -> Node:
	var sess = CloudSessionScript.new()
	sess.base_url = _server_url
	add_child(sess)
	return sess


func _on_create_cloud() -> void:
	if _busy:
		return
	_set_busy(true)
	_set_status("Creating cloud match…")
	var sess = _make_session()
	var resp: Dictionary = await sess.post_create_match("prototype_play")
	sess.queue_free()
	_set_busy(false)
	if resp.has("_error") or str(resp.get("match_id", "")) == "":
		_set_status("Could not create match. Check server and URL.")
		return
	var host_tok: String = CloudClientScript.host_token_from_create_response(resp)
	if host_tok.is_empty():
		_set_status("Create succeeded but host token was missing.")
		return
	CloudCredentialStoreScript.upsert(
		CloudCredentialStoreScript.DEFAULT_PATH,
		CloudClientScript.credential_from_create_response(_server_url, resp),
	)
	BootIntentScript.set_cloud_create(_server_url, host_tok, "prototype_play")
	_go_main()


func _on_refresh_lobby() -> void:
	if _busy:
		return
	_set_busy(true)
	_set_status("Loading lobby list…")
	_lobby_claim_targets.clear()
	_lobby_list.clear()
	var sess = _make_session()
	var raw: Dictionary = await sess.get_matches_list("staging")
	sess.queue_free()
	_set_busy(false)
	var parsed: Dictionary = CloudClientScript.parse_lobby_list_response(raw)
	if parsed.has("_error"):
		_set_status("Lobby list failed: %s" % str(parsed["_error"]))
		return
	var matches: Array = parsed["matches"] as Array
	var idx: int = 0
	while idx < matches.size():
		var row: Dictionary = matches[idx] as Dictionary
		idx += 1
		var mid: String = str(row.get("match_id", ""))
		var seats = row.get("seats", [])
		if typeof(seats) != TYPE_ARRAY:
			continue
		var si: int = 0
		while si < (seats as Array).size():
			var seat = (seats as Array)[si]
			si += 1
			if typeof(seat) != TYPE_DICTIONARY:
				continue
			var sd: Dictionary = seat as Dictionary
			if bool(sd.get("claimed", true)):
				continue
			var aid: int = int(sd.get("actor_id", -1))
			_lobby_claim_targets.append({"match_id": mid, "actor_id": aid})
			_lobby_list.add_item("Join %s as Player %d" % [mid, aid])
	_set_status(
		"Lobby: %d claimable seat(s). Select a line to join." % _lobby_claim_targets.size()
	)


func _on_lobby_item_selected(index: int) -> void:
	if index < 0 or index >= _lobby_claim_targets.size() or _busy:
		return
	var target: Dictionary = _lobby_claim_targets[index] as Dictionary
	await _claim_and_play(str(target.get("match_id", "")), int(target.get("actor_id", -1)))


func _claim_and_play(match_id: String, actor_id: int) -> void:
	if _busy:
		return
	_set_busy(true)
	_set_status("Claiming seat %d on %s…" % [actor_id, match_id])
	var sess = _make_session()
	sess.match_id = match_id
	var raw: Dictionary = await sess.post_claim_seat(actor_id)
	sess.queue_free()
	_set_busy(false)
	var parsed: Dictionary = CloudClientScript.parse_claim_response(raw)
	if not bool(parsed.get("ok", false)):
		_set_status("Claim failed: %s" % str(parsed.get("_error", "unknown")))
		return
	CloudCredentialStoreScript.upsert(
		CloudCredentialStoreScript.DEFAULT_PATH,
		CloudClientScript.credential_from_claim_response(_server_url, parsed),
	)
	BootIntentScript.set_cloud_reconnect(
		_server_url,
		str(parsed["match_id"]),
		str(parsed["seat_token"]),
		int(parsed["actor_id"]),
	)
	_go_main()


func _refresh_saved_list() -> void:
	_saved_rows.clear()
	_saved_list.clear()
	_saved_rows = CloudCredentialStoreScript.entries_for_server(
		CloudCredentialStoreScript.DEFAULT_PATH,
		_server_url,
	)
	var i: int = 0
	while i < _saved_rows.size():
		var row: Dictionary = _saved_rows[i] as Dictionary
		var label := "%s actor %d%s" % [
			str(row.get("match_id", "")),
			int(row.get("actor_id", 0)),
			" (host)" if bool(row.get("is_host", false)) else "",
		]
		_saved_list.add_item(label)
		i += 1
	if _saved_rows.is_empty():
		_saved_list.add_item("(no saved matches for this server)")


func _on_saved_item_selected(index: int) -> void:
	if index < 0 or index >= _saved_rows.size() or _busy:
		return
	var row: Dictionary = _saved_rows[index] as Dictionary
	var mid: String = str(row.get("match_id", ""))
	var tok: String = str(row.get("seat_token", "")).strip_edges()
	if mid.is_empty() or tok.is_empty():
		_set_status("Saved entry is incomplete.")
		return
	BootIntentScript.set_cloud_reconnect(
		_server_url,
		mid,
		tok,
		int(row.get("actor_id", 0)),
	)
	_go_main()
