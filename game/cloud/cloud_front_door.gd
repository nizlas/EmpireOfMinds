# Slice C14c: in-game front door for local hotseat and cloud lobby entry.
extends Control

const BootIntentScript = preload("res://cloud/boot_intent.gd")
const CloudSessionScript = preload("res://cloud/cloud_session.gd")
const CloudClientScript = preload("res://cloud/cloud_client.gd")
const CloudCredentialStoreScript = preload("res://cloud/cloud_credential_store.gd")

const MAIN_SCENE: String = "res://main.tscn"
const STAGING_SCENE: String = "res://cloud/cloud_staging.tscn"
const CloudStagingParsersScript = preload("res://cloud/cloud_staging_parsers.gd")
const CloudLobbyPollScript = preload("res://cloud/cloud_lobby_poll.gd")
const DEFAULT_SERVER_URL: String = "http://127.0.0.1:8000"
const FRONT_DOOR_POLL_INTERVAL_SEC: float = 2.0
## C14d-visual: full-viewport backdrop; menus in lower half only.
const FRONT_DOOR_BACKGROUND_TEXTURE_PATH: String = (
	"res://assets/prototype/ui/backgrounds/empire_of_minds_title_page.png"
)
const FRONT_DOOR_BACKGROUND_NODE_NAME: String = "FrontDoorBackground"
const FRONT_DOOR_UI_ROOT_NODE_NAME: String = "FrontDoorUiRoot"
const FRONT_DOOR_UI_WIDTH_FRACTION: float = 0.25
const FRONT_DOOR_UI_TOP_ANCHOR: float = 0.5
const FRONT_DOOR_LOBBY_ROW_HEIGHT_PX: int = 24
const FRONT_DOOR_LOBBY_MIN_VISIBLE_ROWS: int = 3
const FRONT_DOOR_LOBBY_LIST_MIN_HEIGHT_PX: int = (
	FRONT_DOOR_LOBBY_MIN_VISIBLE_ROWS * FRONT_DOOR_LOBBY_ROW_HEIGHT_PX + 8
)
const FRONT_DOOR_LOBBY_LIST_MAX_HEIGHT_PX: int = 168
const FRONT_DOOR_SAVED_MIN_VISIBLE_ROWS: int = 2
const FRONT_DOOR_SAVED_MAX_VISIBLE_ROWS: int = 7
const FRONT_DOOR_SAVED_LIST_MIN_HEIGHT_PX: int = (
	FRONT_DOOR_SAVED_MIN_VISIBLE_ROWS * FRONT_DOOR_LOBBY_ROW_HEIGHT_PX + 8
)
const FRONT_DOOR_SAVED_LIST_MAX_HEIGHT_PX: int = (
	FRONT_DOOR_SAVED_MAX_VISIBLE_ROWS * FRONT_DOOR_LOBBY_ROW_HEIGHT_PX + 8
)

var _server_url: String = DEFAULT_SERVER_URL
var _status_label: Label
var _lobby_list: ItemList
var _saved_list: ItemList
var _saved_resume_btn: Button
var _saved_rename_btn: Button
var _busy: bool = false
var _lobby_fetch_in_flight: bool = false
var _poll_stopped: bool = true
var _poll_timer: Timer = null
var _lobby_join_targets: Array = []
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
	CloudCredentialStoreScript.log_resolved_store_if_debug("front_door")
	_start_front_door_polling()
	call_deferred("_reload_lobby_from_server")


func _exit_tree() -> void:
	_stop_front_door_polling()


func _start_front_door_polling() -> void:
	if _poll_timer != null:
		return
	_poll_stopped = false
	_poll_timer = Timer.new()
	_poll_timer.wait_time = FRONT_DOOR_POLL_INTERVAL_SEC
	_poll_timer.autostart = true
	_poll_timer.timeout.connect(_on_front_door_poll_timeout)
	add_child(_poll_timer)


func _stop_front_door_polling() -> void:
	_poll_stopped = true
	if _poll_timer != null:
		_poll_timer.stop()
		_poll_timer.queue_free()
		_poll_timer = null


func _on_front_door_poll_timeout() -> void:
	if not CloudLobbyPollScript.front_door_should_run_poll(
		_poll_stopped,
		_lobby_fetch_in_flight,
		_busy,
	):
		return
	_reload_lobby_from_server(true)


func _resolve_server_url() -> String:
	var env_u: String = OS.get_environment("EOM_CLOUD_BASE_URL").strip_edges()
	if env_u.length() > 0:
		return CloudCredentialStoreScript.normalize_server_url(env_u)
	return CloudCredentialStoreScript.normalize_server_url(DEFAULT_SERVER_URL)


func _cloud_debug_enabled() -> bool:
	return OS.get_environment("EOM_CLOUD_DEBUG").strip_edges() == "1"


func _debug_log_resume_saved(
	view: Dictionary,
	match_id: String,
	actor_id: int,
	seat_tok: String,
	host_tok: String,
	status: String,
) -> void:
	if not _cloud_debug_enabled():
		return
	CloudCredentialStoreScript.log_resolved_store_if_debug("front_door_resume")
	print(
		(
			"SliceC14dReconnect front_door_resume profile=%s store_path=%s match_id=%s "
			+ "actor_id=%d has_seat_token=%s has_host_token=%s status=%s"
		)
		% [
			CloudCredentialStoreScript.profile_from_environment(),
			CloudCredentialStoreScript.resolved_store_path(),
			match_id,
			actor_id,
			str(seat_tok.begins_with(CloudCredentialStoreScript.SEAT_TOKEN_PREFIX)),
			str(host_tok.begins_with(CloudCredentialStoreScript.HOST_TOKEN_PREFIX)),
			status,
		]
	)


func _build_front_door_background() -> void:
	var tex: Texture2D = load(FRONT_DOOR_BACKGROUND_TEXTURE_PATH) as Texture2D
	if tex == null:
		push_warning("Front door: missing background at %s" % FRONT_DOOR_BACKGROUND_TEXTURE_PATH)
		return
	var bg := TextureRect.new()
	bg.name = FRONT_DOOR_BACKGROUND_NODE_NAME
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bg.grow_vertical = Control.GROW_DIRECTION_BOTH
	bg.texture = tex
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_front_door_background()
	var col_left: float = (1.0 - FRONT_DOOR_UI_WIDTH_FRACTION) * 0.5
	var col_right: float = col_left + FRONT_DOOR_UI_WIDTH_FRACTION
	var root := MarginContainer.new()
	root.name = FRONT_DOOR_UI_ROOT_NODE_NAME
	root.anchor_left = col_left
	root.anchor_top = FRONT_DOOR_UI_TOP_ANCHOR
	root.anchor_right = col_right
	root.anchor_bottom = 1.0
	root.offset_left = 0
	root.offset_top = 16
	root.offset_right = 0
	root.offset_bottom = -24
	root.grow_horizontal = Control.GROW_DIRECTION_BOTH
	root.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(root)
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	root.add_child(vbox)
	var actions_col := VBoxContainer.new()
	actions_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(actions_col)
	var hotseat_btn := Button.new()
	hotseat_btn.text = "Local Hotseat"
	hotseat_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hotseat_btn.pressed.connect(_on_local_hotseat)
	actions_col.add_child(hotseat_btn)
	var create_btn := Button.new()
	create_btn.text = "Create Cloud Match"
	create_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create_btn.pressed.connect(_on_create_cloud)
	actions_col.add_child(create_btn)
	var lobby_btn := Button.new()
	lobby_btn.text = "Refresh cloud matches"
	lobby_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lobby_btn.pressed.connect(_on_refresh_lobby)
	actions_col.add_child(lobby_btn)
	_status_label = Label.new()
	_status_label.text = "Choose an option."
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_status_label)
	var saved_hdr := Label.new()
	saved_hdr.text = "Your matches on this server"
	saved_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(saved_hdr)
	_saved_list = ItemList.new()
	_saved_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_saved_list.item_selected.connect(_on_saved_item_selected)
	vbox.add_child(_saved_list)
	_resize_saved_list()
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
	lobby_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(lobby_hdr)
	_lobby_list = ItemList.new()
	_lobby_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lobby_list.item_selected.connect(_on_lobby_item_selected)
	vbox.add_child(_lobby_list)
	_resize_lobby_list()


func _resize_lobby_list() -> void:
	if _lobby_list == null:
		return
	var rows: int = maxi(_lobby_list.item_count, FRONT_DOOR_LOBBY_MIN_VISIBLE_ROWS)
	var h: int = clampi(
		rows * FRONT_DOOR_LOBBY_ROW_HEIGHT_PX + 8,
		FRONT_DOOR_LOBBY_LIST_MIN_HEIGHT_PX,
		FRONT_DOOR_LOBBY_LIST_MAX_HEIGHT_PX,
	)
	_lobby_list.custom_minimum_size = Vector2(0, h)


func _resize_saved_list() -> void:
	if _saved_list == null:
		return
	var rows: int = maxi(_saved_list.item_count, FRONT_DOOR_SAVED_MIN_VISIBLE_ROWS)
	var h: int = clampi(
		rows * FRONT_DOOR_LOBBY_ROW_HEIGHT_PX + 8,
		FRONT_DOOR_SAVED_LIST_MIN_HEIGHT_PX,
		FRONT_DOOR_SAVED_LIST_MAX_HEIGHT_PX,
	)
	_saved_list.custom_minimum_size = Vector2(0, h)


func _set_status(msg: String) -> void:
	if _status_label != null:
		_status_label.text = msg


func _set_busy(on: bool) -> void:
	_busy = on


func _go_main() -> void:
	_stop_front_door_polling()
	get_tree().change_scene_to_file(MAIN_SCENE)


func _go_staging() -> void:
	_stop_front_door_polling()
	get_tree().change_scene_to_file(STAGING_SCENE)


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
		CloudCredentialStoreScript.resolved_store_path(),
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
	CloudCredentialStoreScript.upsert(CloudCredentialStoreScript.resolved_store_path(), entry)


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
	CloudCredentialStoreScript.merge_host_create(
		_server_url,
		mid,
		host_tok,
		display_name,
		CloudCredentialStoreScript.revision_from_response(resp),
		CloudCredentialStoreScript.STATUS_STAGING,
		CloudCredentialStoreScript.resolved_store_path(),
	)
	if _cloud_debug_enabled():
		print("SliceC14d3 create_flow staging match_id=%s" % mid)
	BootIntentScript.set_cloud_staging(
		_server_url,
		mid,
		host_tok,
		"",
		-1,
		display_name,
		"prototype_play",
	)
	_go_staging()


func _on_refresh_lobby() -> void:
	await _reload_lobby_from_server(false)


func _on_lobby_item_selected(index: int) -> void:
	if index < 0 or index >= _lobby_join_targets.size() or _busy:
		return
	var target: Dictionary = _lobby_join_targets[index] as Dictionary
	_enter_staging_for_match(target)


func _enter_staging_for_match(target: Dictionary) -> void:
	var match_id: String = str(target.get("match_id", "")).strip_edges()
	var lobby_row: Dictionary = target.get("lobby_row", {}) as Dictionary
	var dn: String = CloudClientScript.display_name_from_lobby_row(lobby_row)
	var cred: Dictionary = CloudCredentialStoreScript.find(CloudCredentialStoreScript.resolved_store_path(), _server_url, match_id)
	var host_tok: String = CloudCredentialStoreScript.host_token_from_entry(cred)
	var seat_tok: String = CloudCredentialStoreScript.gameplay_token_from_entry(cred)
	var aid: int = int(cred.get("actor_id", -1)) if not cred.is_empty() else -1
	if seat_tok.is_empty():
		aid = -1
	BootIntentScript.set_cloud_staging(_server_url, match_id, host_tok, seat_tok, aid, dn)
	_go_staging()


func _reload_lobby_from_server(silent: bool = false) -> void:
	if not CloudLobbyPollScript.front_door_should_begin_fetch(_lobby_fetch_in_flight):
		return
	if not silent and _busy:
		return
	_lobby_fetch_in_flight = true
	_server_lobby_load_failed = false
	if not silent:
		_set_status("Loading matches from server…")
		_saved_rows.clear()
		_lobby_join_targets.clear()
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
	_lobby_fetch_in_flight = false
	var parsed: Dictionary = CloudClientScript.parse_lobby_list_response(raw)
	if parsed.has("_error"):
		_server_lobby_load_failed = true
		if silent:
			_set_status("Unable to refresh cloud matches. Will retry…")
		else:
			_render_lobby_load_failed(str(parsed["_error"]))
		return
	var matches: Array = parsed.get("matches", []) as Array
	_lobby_matches = matches
	_refresh_display_name_key_map()
	var cred_map: Dictionary = CloudCredentialStoreScript.credentials_map_for_server(
		CloudCredentialStoreScript.resolved_store_path(),
		_server_url,
	)
	_saved_rows = CloudClientScript.build_resume_rows_from_lobby(matches, cred_map, _server_url)
	var resume_ids: Dictionary = CloudClientScript.resume_match_id_set(_saved_rows)
	_lobby_join_targets = CloudClientScript.build_open_staging_join_targets(matches, resume_ids)
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
	_resize_saved_list()
	_resize_lobby_list()
	_set_status("Unable to load cloud matches. Could not reach cloud server.")
	if _saved_resume_btn != null:
		_saved_resume_btn.disabled = true
	if _saved_rename_btn != null:
		_saved_rename_btn.disabled = true


func _set_lobby_load_status() -> void:
	if _server_lobby_load_failed:
		return
	if _saved_rows.is_empty() and _lobby_join_targets.is_empty():
		_set_status("No saved matches on this server. No open staging matches.")
		return
	if _saved_rows.is_empty():
		_set_status(
			"No saved matches found on this server. Open staging: %d match(es)."
			% _lobby_join_targets.size()
		)
		return
	if _lobby_join_targets.is_empty():
		_set_status("Your matches: %d. No open staging matches." % _saved_rows.size())
		return
	_set_status(
		"Your matches: %d. Open staging: %d match(es)."
		% [_saved_rows.size(), _lobby_join_targets.size()]
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
	_resize_saved_list()


func _render_open_list() -> void:
	_lobby_list.clear()
	var i: int = 0
	while i < _lobby_join_targets.size():
		var target: Dictionary = _lobby_join_targets[i] as Dictionary
		i += 1
		var row: Dictionary = target.get("lobby_row", {}) as Dictionary
		_lobby_list.add_item(CloudStagingParsersScript.open_staging_row_text(row))
	if _lobby_join_targets.is_empty() and not _server_lobby_load_failed:
		_lobby_list.add_item("(No open staging matches on this server.)")
	_resize_lobby_list()


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
		var st: String = str(view.get("server_status", "")).strip_edges()
		var has_seat: bool = not str(view.get("seat_token", "")).strip_edges().is_empty()
		_saved_resume_btn.text = CloudStagingParsersScript.saved_resume_button_label(st, has_seat)
	if _saved_rename_btn != null:
		var cred_row: Dictionary = view.get("credential", {}) as Dictionary
		_saved_rename_btn.disabled = CloudCredentialStoreScript.admin_token_from_entry(cred_row).is_empty()


func _on_resume_saved() -> void:
	if _saved_selected_index < 0 or _saved_selected_index >= _saved_rows.size() or _busy:
		return
	var view: Dictionary = _saved_rows[_saved_selected_index] as Dictionary
	var mid: String = str(view.get("match_id", ""))
	var cred: Dictionary = view.get("credential", {}) as Dictionary
	var seat_tok: String = CloudCredentialStoreScript.gameplay_token_from_entry(cred)
	if seat_tok.is_empty():
		seat_tok = str(view.get("seat_token", "")).strip_edges()
	var host_tok: String = CloudCredentialStoreScript.host_token_from_entry(cred)
	var st: String = str(view.get("server_status", "")).strip_edges()
	var dn: String = str(view.get("display_name", ""))
	if mid.is_empty():
		_set_status("Saved entry is incomplete.")
		return
	if st == CloudCredentialStoreScript.STATUS_ONGOING and not seat_tok.is_empty():
		var aid: int = int(view.get("actor_id", CloudCredentialStoreScript.UNSET_ACTOR_ID))
		if not seat_tok.begins_with(CloudCredentialStoreScript.SEAT_TOKEN_PREFIX):
			_set_status("Saved entry is missing a seat token. Claim a slot in staging first.")
			return
		if aid < 0:
			_set_status("Saved entry is missing seat actor identity. Re-claim your slot in staging.")
			return
		_debug_log_resume_saved(view, mid, aid, seat_tok, host_tok, st)
		BootIntentScript.set_cloud_reconnect(_server_url, mid, seat_tok, aid)
		_go_main()
		return
	if st == CloudCredentialStoreScript.STATUS_STAGING or seat_tok.is_empty():
		var aid: int = int(view.get("actor_id", -1))
		if seat_tok.is_empty():
			aid = -1
		BootIntentScript.set_cloud_staging(_server_url, mid, host_tok, seat_tok, aid, dn)
		_go_staging()
		return
	_set_status("Claim a slot in staging before resuming this match.")


func _on_rename_saved() -> void:
	if _saved_selected_index < 0 or _saved_selected_index >= _saved_rows.size() or _busy:
		return
	var view: Dictionary = _saved_rows[_saved_selected_index] as Dictionary
	var mid: String = str(view.get("match_id", ""))
	var cred: Dictionary = view.get("credential", {}) as Dictionary
	if CloudCredentialStoreScript.admin_token_from_entry(cred).is_empty():
		_set_status("Only the host can rename this match on the server.")
		return
	var tok: String = CloudCredentialStoreScript.admin_token_from_entry(cred)
	if tok.is_empty():
		tok = CloudCredentialStoreScript.host_token_from_entry(cred)
	if mid.is_empty() or tok.is_empty():
		_set_status("Only the host can rename this match (host credential missing).")
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
	CloudCredentialStoreScript.update_label_cache(CloudCredentialStoreScript.resolved_store_path(), _server_url, mid, server_name)
	_saved_rows[_saved_selected_index] = CloudCredentialStoreScript.apply_rename_to_view(view, server_name)
	_render_saved_list()
	var sel: int = _saved_selected_index
	if sel >= 0 and sel < _saved_rows.size():
		_saved_list.select(sel)
		if _saved_resume_btn != null:
			_saved_resume_btn.disabled = false
		if _saved_rename_btn != null:
			_saved_rename_btn.disabled = false
	await _reload_lobby_from_server(false)
	_set_status("Renamed to \"%s\"." % server_name)
