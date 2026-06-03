# Slice C14c: in-game front door for local hotseat and cloud lobby entry.
extends Control

const BootIntentScript = preload("res://cloud/boot_intent.gd")
const CloudSessionScript = preload("res://cloud/cloud_session.gd")
const CloudClientScript = preload("res://cloud/cloud_client.gd")
const CloudCredentialStoreScript = preload("res://cloud/cloud_credential_store.gd")

const MAIN_SCENE: String = "res://main.tscn"
const DEFAULT_SERVER_URL: String = "http://127.0.0.1:8000"
const STORE_PATH: String = CloudCredentialStoreScript.DEFAULT_PATH

var _server_url: String = DEFAULT_SERVER_URL
var _status_label: Label
var _lobby_list: ItemList
var _saved_list: ItemList
var _saved_resume_btn: Button
var _saved_rename_btn: Button
var _busy: bool = false
var _lobby_claim_targets: Array = []
## Saved row view models (see CloudCredentialStore.build_saved_row_view).
var _saved_rows: Array = []
var _saved_selected_index: int = -1
## match_id -> server display_name (merge updates; never cleared before fetch).
var _server_display_names: Dictionary = {}


func _ready() -> void:
	_server_url = _resolve_server_url()
	if BootIntentScript.should_skip_front_door_for_env():
		BootIntentScript.apply_env_cloud_to_boot_intent()
		get_tree().change_scene_to_file(MAIN_SCENE)
		return
	_build_ui()
	_populate_saved_list_from_store()
	call_deferred("_enrich_saved_list_from_server")


func _resolve_server_url() -> String:
	var env_u: String = OS.get_environment("EOM_CLOUD_BASE_URL").strip_edges()
	if env_u.length() > 0:
		return env_u.rstrip("/")
	return DEFAULT_SERVER_URL


func _cloud_debug_enabled() -> bool:
	return OS.get_environment("EOM_CLOUD_DEBUG").strip_edges() == "1"


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
	lobby_btn.text = "Refresh open matches"
	lobby_btn.pressed.connect(_on_refresh_lobby)
	row1.add_child(lobby_btn)
	_status_label = Label.new()
	_status_label.text = "Choose an option."
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_status_label)
	var saved_hdr := Label.new()
	saved_hdr.text = "Your saved cloud matches (local credentials; names from server when online):"
	vbox.add_child(saved_hdr)
	_saved_list = ItemList.new()
	_saved_list.custom_minimum_size = Vector2(0, 120)
	_saved_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_saved_list.item_selected.connect(_on_saved_item_selected)
	vbox.add_child(_saved_list)
	var saved_row := HBoxContainer.new()
	vbox.add_child(saved_row)
	_saved_resume_btn = Button.new()
	_saved_resume_btn.text = "Resume saved match"
	_saved_resume_btn.disabled = true
	_saved_resume_btn.pressed.connect(_on_resume_saved)
	saved_row.add_child(_saved_resume_btn)
	_saved_rename_btn = Button.new()
	_saved_rename_btn.text = "Rename"
	_saved_rename_btn.disabled = true
	_saved_rename_btn.pressed.connect(_on_rename_saved)
	saved_row.add_child(_saved_rename_btn)
	var lobby_hdr := Label.new()
	lobby_hdr.text = "Join open cloud matches (server staging list; no tokens shown):"
	vbox.add_child(lobby_hdr)
	_lobby_list = ItemList.new()
	_lobby_list.custom_minimum_size = Vector2(0, 180)
	_lobby_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lobby_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_lobby_list.item_selected.connect(_on_lobby_item_selected)
	vbox.add_child(_lobby_list)


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


func _await_text_dialog(title: String, hint: String, prefill: String, cancel_to_prefill: bool) -> String:
	var edited: String = prefill
	var confirmed: bool = false
	var win := Window.new()
	win.title = title
	win.unresizable = true
	win.popup_window = true
	win.size = Vector2i(520, 168)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	win.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(vbox)
	var hint_lbl := Label.new()
	hint_lbl.text = hint
	hint_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(hint_lbl)
	var edit := LineEdit.new()
	edit.text = prefill
	edit.placeholder_text = prefill
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.expand_to_text_length = true
	vbox.add_child(edit)
	var btn_row := HBoxContainer.new()
	vbox.add_child(btn_row)
	var ok_btn := Button.new()
	ok_btn.text = "OK"
	btn_row.add_child(ok_btn)
	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	btn_row.add_child(cancel_btn)
	add_child(win)
	win.popup_centered()
	edit.grab_focus()
	edit.caret_column = edit.text.length()
	ok_btn.pressed.connect(
		func() -> void:
			edited = edit.text
			confirmed = true
			win.hide()
	)
	cancel_btn.pressed.connect(
		func() -> void:
			confirmed = false
			win.hide()
	)
	win.close_requested.connect(
		func() -> void:
			if not confirmed:
				win.hide()
	)
	while win.visible:
		await get_tree().process_frame
	win.queue_free()
	return CloudCredentialStoreScript.finalize_dialog_text(
		edited,
		prefill,
		confirmed,
		cancel_to_prefill,
	)


func _prompt_create_display_name(default_label: String) -> String:
	var raw: String = await _await_text_dialog(
		"Name this cloud match",
		"Public display name on the server (visible to others in the open match list).",
		default_label,
		false,
	)
	if raw.is_empty():
		return ""
	return CloudCredentialStoreScript.resolve_label_for_save(raw, STORE_PATH)


func _prompt_rename_display_name(prefill_full: String) -> String:
	var raw: String = await _await_text_dialog(
		"Rename cloud match",
		"Public display name on the server (visible to others in the open match list).",
		prefill_full,
		false,
	)
	return CloudCredentialStoreScript.rename_submit_body(raw)


func _save_credential_with_label(entry: Dictionary) -> void:
	CloudCredentialStoreScript.upsert(STORE_PATH, entry)


func _on_create_cloud() -> void:
	if _busy:
		return
	var requested_name: String = await _prompt_create_display_name(
		CloudCredentialStoreScript.generate_default_label(STORE_PATH)
	)
	if requested_name.is_empty():
		_set_status("Create cancelled.")
		return
	_set_busy(true)
	_set_status("Creating cloud match…")
	var sess = _make_session()
	var resp: Dictionary = await sess.post_create_match("prototype_play", requested_name)
	sess.queue_free()
	_set_busy(false)
	if resp.has("_error") or str(resp.get("match_id", "")) == "":
		_set_status("Could not create match. Check server and URL.")
		return
	var host_tok: String = CloudClientScript.host_token_from_create_response(resp)
	if host_tok.is_empty():
		_set_status("Create succeeded but host token was missing.")
		return
	var mid: String = str(resp.get("match_id", "")).strip_edges()
	var display_name: String = CloudClientScript.pick_create_credential_display_name(
		requested_name,
		resp,
	)
	if _cloud_debug_enabled() and display_name != requested_name:
		push_warning(
			"SliceC14c2 create using response display_name=%s (requested=%s)"
			% [display_name, requested_name]
		)
	_server_display_names[mid] = display_name
	var entry: Dictionary = CloudClientScript.credential_from_create_response(
		_server_url,
		resp,
		display_name,
		STORE_PATH,
	)
	_save_credential_with_label(entry)
	BootIntentScript.set_cloud_play_from_create_response(_server_url, resp, "prototype_play")
	_go_main()


func _on_refresh_lobby() -> void:
	if _busy:
		return
	_set_busy(true)
	_set_status("Loading open staging matches…")
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
		var dn: String = CloudClientScript.display_name_from_lobby_row(row)
		if mid.length() > 0 and dn.length() > 0:
			_server_display_names[mid] = dn
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
			_lobby_claim_targets.append({"match_id": mid, "actor_id": aid, "lobby_row": row})
			_lobby_list.add_item(CloudClientScript.lobby_open_row_text(row, aid))
	_set_status(
		"Open matches: %d claimable seat(s). Select a line to join." % _lobby_claim_targets.size()
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
	var mid: String = str(parsed.get("match_id", "")).strip_edges()
	var server_name: String = str(parsed.get("display_name", "")).strip_edges()
	if server_name.length() > 0:
		_server_display_names[mid] = server_name
	var entry: Dictionary = CloudClientScript.credential_from_claim_response(
		_server_url,
		parsed,
		server_name,
		STORE_PATH,
	)
	_save_credential_with_label(entry)
	BootIntentScript.set_cloud_reconnect(
		_server_url,
		mid,
		str(parsed["seat_token"]),
		int(parsed["actor_id"]),
	)
	_go_main()


func _merge_server_display_names_from_lobby() -> void:
	var sess = _make_session()
	var raw: Dictionary = await sess.get_matches_list("")
	sess.queue_free()
	var parsed: Dictionary = CloudClientScript.parse_lobby_list_response(raw)
	if parsed.has("_error"):
		return
	var matches: Array = parsed.get("matches", []) as Array
	var i: int = 0
	while i < matches.size():
		var row = matches[i]
		i += 1
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = row as Dictionary
		var mid: String = str(d.get("match_id", "")).strip_edges()
		var dn: String = CloudClientScript.display_name_from_lobby_row(d)
		if mid.length() > 0 and dn.length() > 0:
			_server_display_names[mid] = dn


func _load_saved_row_views() -> void:
	_saved_rows.clear()
	var entries: Array = CloudCredentialStoreScript.entries_for_server(STORE_PATH, _server_url)
	var i: int = 0
	while i < entries.size():
		var entry: Dictionary = entries[i] as Dictionary
		i += 1
		_saved_rows.append(
			CloudCredentialStoreScript.build_saved_row_view(entry, _server_url, _server_display_names)
		)


func _render_saved_list() -> void:
	_saved_list.clear()
	var i: int = 0
	while i < _saved_rows.size():
		var view: Dictionary = _saved_rows[i] as Dictionary
		i += 1
		_saved_list.add_item(str(view.get("row_text", "")))
	if _saved_rows.is_empty():
		_saved_list.add_item("(no saved credentials for this server — create or claim a match)")


func _populate_saved_list_from_store() -> void:
	var entries: Array = CloudCredentialStoreScript.entries_for_server(STORE_PATH, _server_url)
	var seeded: Dictionary = CloudCredentialStoreScript.seed_display_names_from_entries(entries)
	for mid in seeded.keys():
		if not _server_display_names.has(mid):
			_server_display_names[mid] = seeded[mid]
	_load_saved_row_views()
	_render_saved_list()
	_saved_selected_index = -1
	if _saved_resume_btn != null:
		_saved_resume_btn.disabled = true
	if _saved_rename_btn != null:
		_saved_rename_btn.disabled = true


func _enrich_saved_list_from_server() -> void:
	if _busy:
		return
	await _merge_server_display_names_from_lobby()
	var sel: int = _saved_selected_index
	_load_saved_row_views()
	_render_saved_list()
	if sel >= 0 and sel < _saved_rows.size():
		_saved_selected_index = sel
		_saved_list.select(sel)
		if _saved_resume_btn != null:
			_saved_resume_btn.disabled = false
		if _saved_rename_btn != null:
			_saved_rename_btn.disabled = not bool((_saved_rows[sel] as Dictionary).get("is_host", false))


func _refresh_saved_list() -> void:
	_populate_saved_list_from_store()
	await _enrich_saved_list_from_server()


func _on_saved_item_selected(index: int) -> void:
	if index < 0 or index >= _saved_rows.size() or _busy:
		_saved_selected_index = -1
		if _saved_resume_btn != null:
			_saved_resume_btn.disabled = true
		if _saved_rename_btn != null:
			_saved_rename_btn.disabled = true
		return
	_saved_selected_index = index
	var view: Dictionary = _saved_rows[index] as Dictionary
	if _saved_resume_btn != null:
		_saved_resume_btn.disabled = false
	if _saved_rename_btn != null:
		_saved_rename_btn.disabled = not bool(view.get("is_host", false))


func _on_resume_saved() -> void:
	if _saved_selected_index < 0 or _saved_selected_index >= _saved_rows.size() or _busy:
		return
	var view: Dictionary = _saved_rows[_saved_selected_index] as Dictionary
	var mid: String = str(view.get("match_id", ""))
	var tok: String = str(view.get("seat_token", "")).strip_edges()
	if mid.is_empty() or tok.is_empty():
		_set_status("Saved entry is incomplete.")
		return
	BootIntentScript.set_cloud_reconnect(
		_server_url,
		mid,
		tok,
		int(view.get("actor_id", 0)),
	)
	_go_main()


func _on_rename_saved() -> void:
	if _saved_selected_index < 0 or _saved_selected_index >= _saved_rows.size() or _busy:
		return
	var view: Dictionary = _saved_rows[_saved_selected_index] as Dictionary
	if not bool(view.get("is_host", false)):
		_set_status("Only the host can rename this match on the server.")
		return
	var mid: String = str(view.get("match_id", ""))
	var tok: String = str(view.get("seat_token", "")).strip_edges()
	if mid.is_empty() or tok.is_empty():
		_set_status("Saved entry is incomplete.")
		return
	var old_name: String = str(view.get("display_name", ""))
	var requested: String = await _prompt_rename_display_name(old_name)
	if requested.is_empty():
		_set_status("Rename cancelled.")
		return
	if _cloud_debug_enabled():
		print(
			"SliceC14c2 rename_ui match_id=%s old_display_name=%s requested_display_name=%s"
			% [mid, old_name, requested]
		)
	_set_busy(true)
	_set_status("Renaming match on server…")
	var sess = _make_session()
	sess.match_id = mid
	sess.seat_token = tok
	var raw: Dictionary = await sess.patch_display_name(mid, requested)
	sess.queue_free()
	_set_busy(false)
	var parsed: Dictionary = CloudClientScript.parse_rename_display_response(raw)
	if not bool(parsed.get("ok", false)):
		var err_detail: String = str(parsed.get("_error", "unknown"))
		if parsed.has("_http_code"):
			err_detail += " (HTTP %s)" % str(parsed.get("_http_code"))
		_set_status("Rename failed: %s" % err_detail)
		return
	var server_name: String = str(parsed.get("display_name", ""))
	_server_display_names[mid] = server_name
	CloudCredentialStoreScript.update_label_cache(STORE_PATH, _server_url, mid, server_name)
	_saved_rows[_saved_selected_index] = CloudCredentialStoreScript.apply_rename_to_view(view, server_name)
	_render_saved_list()
	var sel: int = _saved_selected_index
	if sel >= 0 and sel < _saved_rows.size():
		_saved_list.select(sel)
		if _saved_resume_btn != null:
			_saved_resume_btn.disabled = false
		if _saved_rename_btn != null:
			_saved_rename_btn.disabled = false
	_set_status("Renamed to \"%s\"." % server_name)
