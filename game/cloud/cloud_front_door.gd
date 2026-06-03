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
## Resume rows: server lobby summaries filtered by local credentials for active server_url.
var _saved_rows: Array = []
var _saved_selected_index: int = -1
var _server_lobby_load_failed: bool = false
## Latest token-free **GET /v1/matches** rows for duplicate checks and default naming.
var _lobby_matches: Array = []
var _display_name_key_map: Dictionary = {}


func _ready() -> void:
	_server_url = _resolve_server_url()
	if BootIntentScript.should_skip_front_door_for_env():
		BootIntentScript.apply_env_cloud_to_boot_intent()
		get_tree().change_scene_to_file(MAIN_SCENE)
		return
	_build_ui()
	call_deferred("_reload_lobby_from_server")


func _resolve_server_url() -> String:
	var env_u: String = OS.get_environment("EOM_CLOUD_BASE_URL").strip_edges()
	if env_u.length() > 0:
		return CloudCredentialStoreScript.normalize_server_url(env_u)
	return CloudCredentialStoreScript.normalize_server_url(DEFAULT_SERVER_URL)


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
	lobby_btn.text = "Refresh cloud matches"
	lobby_btn.pressed.connect(_on_refresh_lobby)
	row1.add_child(lobby_btn)
	_status_label = Label.new()
	_status_label.text = "Choose an option."
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_status_label)
	var saved_hdr := Label.new()
	saved_hdr.text = "Your matches on this server"
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
	lobby_hdr.text = "Open staging matches"
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


func _server_default_create_label() -> String:
	return CloudCredentialStoreScript.generate_unique_default_label_from_server(_lobby_matches)


func _refresh_display_name_key_map() -> void:
	_display_name_key_map = CloudCredentialStoreScript.display_name_key_map_from_lobby(_lobby_matches)


func _await_name_dialog(title: String, hint: String, prefill: String, validate: Callable) -> Dictionary:
	var result: Dictionary = CloudCredentialStoreScript.empty_dialog_result(prefill)
	var win := Window.new()
	win.title = title
	win.unresizable = true
	win.popup_window = true
	win.size = Vector2i(520, 200)
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
	var validation_lbl := Label.new()
	validation_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(validation_lbl)
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

	var sync_validation := func() -> void:
		var v: Dictionary = validate.call(edit.text)
		ok_btn.disabled = not bool(v.get("ok", false))
		validation_lbl.text = str(v.get("message", ""))

	var commit_ok := func() -> void:
		if bool(result.get("confirmed", false)):
			return
		var v: Dictionary = validate.call(edit.text)
		if not bool(v.get("ok", false)):
			return
		result["confirmed"] = true
		result["text"] = str(v.get("effective", edit.text))
		win.hide()

	var commit_cancel := func() -> void:
		if bool(result.get("confirmed", false)):
			return
		result["confirmed"] = false
		result["text"] = edit.text
		win.hide()

	edit.text_changed.connect(func(_new_text: String) -> void: sync_validation.call())
	ok_btn.pressed.connect(commit_ok)
	edit.text_submitted.connect(
		func(_new_text: String) -> void:
			if not ok_btn.disabled:
				commit_ok.call()
	)
	cancel_btn.pressed.connect(commit_cancel)
	win.close_requested.connect(
		func() -> void:
			result = CloudCredentialStoreScript.apply_close_requested_to_dialog_result(result)
			if bool(result.get("confirmed", false)):
				return
			win.hide()
	)
	sync_validation.call()
	while win.visible:
		await get_tree().process_frame
	win.queue_free()
	return result


func _prompt_create_display_name(default_label: String) -> Dictionary:
	var validate := func(user_text: String) -> Dictionary:
		return CloudCredentialStoreScript.validate_create_display_name(
			user_text,
			default_label,
			_display_name_key_map,
		)
	var dialog_result: Dictionary = await _await_name_dialog(
		"Name this cloud match",
		"Choose a unique name (visible in the open match list). Empty uses the suggested default.",
		default_label,
		validate,
	)
	if _cloud_debug_enabled():
		print(
			"SliceC14c create_dialog default=%s confirmed=%s raw_text=%s"
			% [
				default_label,
				str(dialog_result.get("confirmed", false)),
				str(dialog_result.get("text", "")),
			]
		)
	var interpreted: Dictionary = CloudCredentialStoreScript.interpret_create_dialog_result(
		dialog_result,
		default_label,
		STORE_PATH,
	)
	if _cloud_debug_enabled():
		print(
			"SliceC14c create_dialog cancelled=%s final_display_name=%s"
			% [
				str(interpreted.get("cancelled", true)),
				str(interpreted.get("display_name", "")),
			]
		)
	return interpreted


func _prompt_rename_display_name(prefill_full: String, own_match_id: String) -> Dictionary:
	var validate := func(user_text: String) -> Dictionary:
		return CloudCredentialStoreScript.validate_rename_display_name(
			user_text,
			own_match_id,
			_display_name_key_map,
		)
	var dialog_result: Dictionary = await _await_name_dialog(
		"Rename cloud match",
		"Choose a unique name (visible in the open match list).",
		prefill_full,
		validate,
	)
	if _cloud_debug_enabled():
		print(
			"SliceC14c rename_dialog prefill=%s confirmed=%s raw_text=%s"
			% [
				prefill_full,
				str(dialog_result.get("confirmed", false)),
				str(dialog_result.get("text", "")),
			]
		)
	return CloudCredentialStoreScript.interpret_rename_dialog_result(dialog_result)


func _save_credential_with_label(entry: Dictionary) -> void:
	CloudCredentialStoreScript.upsert(STORE_PATH, entry)


func _on_create_cloud() -> void:
	if _busy:
		return
	var default_label: String = _server_default_create_label()
	var create_dialog: Dictionary = await _prompt_create_display_name(default_label)
	if bool(create_dialog.get("cancelled", true)):
		_set_status("Create cancelled.")
		return
	var requested_name: String = str(create_dialog.get("display_name", "")).strip_edges()
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
	var body: Dictionary = CloudClientScript.build_create_match_body("prototype_play", requested_name)
	if _cloud_debug_enabled():
		print(
			(
				"SliceC14c create_flow requested_display_name=%s body_display_name=%s "
				+ "response_match_id=%s response_display_name=%s"
			)
			% [
				requested_name,
				str(body.get("display_name", "")),
				mid,
				CloudClientScript.display_name_from_create_response(resp),
			]
		)
	if _cloud_debug_enabled() and display_name != requested_name:
		push_warning(
			"SliceC14c2 create using response display_name=%s (requested=%s)"
			% [display_name, requested_name]
		)
	var entry: Dictionary = CloudClientScript.credential_from_create_response(
		_server_url,
		resp,
		display_name,
		STORE_PATH,
	)
	_save_credential_with_label(entry)
	if _cloud_debug_enabled():
		print(
			(
				"SliceC14c create_flow saved_credential match_id=%s label=%s "
				+ "boot_intent_match_id=%s"
			)
			% [str(entry.get("match_id", "")), str(entry.get("label", "")), mid]
		)
	BootIntentScript.set_cloud_play_from_create_response(_server_url, resp, "prototype_play")
	if _cloud_debug_enabled():
		print(
			"SliceC14c create_flow boot_intent mode=%s match_id=%s"
			% [BootIntentScript.mode, BootIntentScript.match_id]
		)
	_go_main()


func _on_refresh_lobby() -> void:
	await _reload_lobby_from_server()


func _on_lobby_item_selected(index: int) -> void:
	if index < 0 or index >= _lobby_claim_targets.size() or _busy:
		return
	var target: Dictionary = _lobby_claim_targets[index] as Dictionary
	await _claim_and_play(target)


func _claim_and_play(target: Dictionary) -> void:
	if _busy:
		return
	var match_id: String = str(target.get("match_id", "")).strip_edges()
	var actor_id: int = int(target.get("actor_id", -1))
	var lobby_row: Dictionary = target.get("lobby_row", {}) as Dictionary
	var claim_name: String = CloudCredentialStoreScript.player_visible_display_name(
		CloudClientScript.display_name_from_lobby_row(lobby_row)
	)
	_set_busy(true)
	_set_status("Claiming seat for %s…" % claim_name)
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


func _reload_lobby_from_server() -> void:
	if _busy:
		return
	_set_busy(true)
	_server_lobby_load_failed = false
	_set_status("Loading matches from server…")
	_saved_rows.clear()
	_lobby_claim_targets.clear()
	_saved_list.clear()
	_lobby_list.clear()
	_saved_selected_index = -1
	if _saved_resume_btn != null:
		_saved_resume_btn.disabled = true
	if _saved_rename_btn != null:
		_saved_rename_btn.disabled = true
	var sess = _make_session()
	var raw: Dictionary = await sess.get_matches_list("")
	sess.queue_free()
	_set_busy(false)
	var parsed: Dictionary = CloudClientScript.parse_lobby_list_response(raw)
	if parsed.has("_error"):
		_server_lobby_load_failed = true
		_render_lobby_load_failed(str(parsed["_error"]))
		return
	var matches: Array = parsed.get("matches", []) as Array
	_lobby_matches = matches
	_refresh_display_name_key_map()
	var cred_map: Dictionary = CloudCredentialStoreScript.credentials_map_for_server(
		STORE_PATH,
		_server_url,
	)
	_saved_rows = CloudClientScript.build_resume_rows_from_lobby(matches, cred_map, _server_url)
	var resume_ids: Dictionary = CloudClientScript.resume_match_id_set(_saved_rows)
	_lobby_claim_targets = CloudClientScript.build_open_staging_claim_targets(matches, resume_ids)
	_render_saved_list()
	_render_open_list()
	_log_resume_rows_debug()
	_set_lobby_load_status()


func _log_resume_rows_debug() -> void:
	if not _cloud_debug_enabled():
		return
	var i: int = 0
	while i < _saved_rows.size():
		var view: Dictionary = _saved_rows[i] as Dictionary
		i += 1
		print(
			"SliceC14c lobby_resume_row match_id=%s display_name=%s server_status=%s"
			% [
				str(view.get("match_id", "")),
				str(view.get("display_name", "")),
				str(view.get("server_status", "")),
			]
		)


func _render_lobby_load_failed(_detail: String) -> void:
	_lobby_matches.clear()
	_display_name_key_map.clear()
	_saved_list.clear()
	_lobby_list.clear()
	_set_status("Unable to load cloud matches. Could not reach cloud server.")
	if _saved_resume_btn != null:
		_saved_resume_btn.disabled = true
	if _saved_rename_btn != null:
		_saved_rename_btn.disabled = true


func _set_lobby_load_status() -> void:
	if _server_lobby_load_failed:
		return
	if _saved_rows.is_empty() and _lobby_claim_targets.is_empty():
		_set_status("No saved matches on this server. No open staging seats.")
		return
	if _saved_rows.is_empty():
		_set_status(
			"No saved matches found on this server. Open staging: %d seat(s)."
			% _lobby_claim_targets.size()
		)
		return
	if _lobby_claim_targets.is_empty():
		_set_status("Your matches: %d. No open staging seats." % _saved_rows.size())
		return
	_set_status(
		"Your matches: %d. Open staging: %d claimable seat(s)."
		% [_saved_rows.size(), _lobby_claim_targets.size()]
	)


func _render_saved_list() -> void:
	_saved_list.clear()
	var i: int = 0
	while i < _saved_rows.size():
		var view: Dictionary = _saved_rows[i] as Dictionary
		i += 1
		_saved_list.add_item(str(view.get("row_text", "")))
	if _saved_rows.is_empty() and not _server_lobby_load_failed:
		_saved_list.add_item("(No saved matches found on this server.)")


func _render_open_list() -> void:
	_lobby_list.clear()
	var i: int = 0
	while i < _lobby_claim_targets.size():
		var target: Dictionary = _lobby_claim_targets[i] as Dictionary
		i += 1
		var row: Dictionary = target.get("lobby_row", {}) as Dictionary
		var aid: int = int(target.get("actor_id", -1))
		_lobby_list.add_item(CloudClientScript.lobby_open_row_text(row, aid))
	if _lobby_claim_targets.is_empty() and not _server_lobby_load_failed:
		_lobby_list.add_item("(No open staging matches on this server.)")


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
	var rename_dialog: Dictionary = await _prompt_rename_display_name(old_name, mid)
	if bool(rename_dialog.get("cancelled", true)):
		_set_status("Rename cancelled.")
		return
	var requested: String = str(rename_dialog.get("display_name", "")).strip_edges()
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
	await _reload_lobby_from_server()
	_set_status("Renamed to \"%s\"." % server_name)
