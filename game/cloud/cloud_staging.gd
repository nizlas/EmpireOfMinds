# Slice C14d-3: cloud match staging (claim, faction, ready) before gameplay.
extends Control

const BootIntentScript = preload("res://cloud/boot_intent.gd")
const CloudSessionScript = preload("res://cloud/cloud_session.gd")
const CloudClientScript = preload("res://cloud/cloud_client.gd")
const CloudCredentialStoreScript = preload("res://cloud/cloud_credential_store.gd")
const CloudStagingParsersScript = preload("res://cloud/cloud_staging_parsers.gd")

const FRONT_DOOR_SCENE: String = "res://cloud/cloud_front_door.tscn"
const MAIN_SCENE: String = "res://main.tscn"
const STORE_PATH: String = CloudCredentialStoreScript.DEFAULT_PATH

var _server_url: String = ""
var _match_id: String = ""
var _host_token: String = ""
var _seat_token: String = ""
var _local_actor_id: int = -1
var _display_name: String = ""
var _busy: bool = false

var _title_label: Label
var _status_label: Label
var _slots_box: VBoxContainer
var _slot_panels: Array = []


func _ready() -> void:
	var boot: Dictionary = BootIntentScript.consume_for_main()
	if str(boot.get("mode", "")) != BootIntentScript.MODE_CLOUD_STAGING:
		get_tree().change_scene_to_file(FRONT_DOOR_SCENE)
		return
	_server_url = str(boot.get("server_url", ""))
	_match_id = CloudCredentialStoreScript.normalize_match_id(str(boot.get("match_id", "")))
	_host_token = str(boot.get("host_token", "")).strip_edges()
	_seat_token = str(boot.get("seat_token", "")).strip_edges()
	_local_actor_id = int(boot.get("actor_id", -1))
	_display_name = str(boot.get("display_name", "")).strip_edges()
	_hydrate_from_store()
	_build_ui()
	call_deferred("_refresh_from_server")


func _hydrate_from_store() -> void:
	var cred: Dictionary = CloudCredentialStoreScript.find(STORE_PATH, _server_url, _match_id)
	if cred.is_empty():
		return
	if _host_token.is_empty():
		_host_token = CloudCredentialStoreScript.host_token_from_entry(cred)
	var st: String = CloudCredentialStoreScript.gameplay_token_from_entry(cred)
	if _seat_token.is_empty() and not st.is_empty():
		_seat_token = st
	if _local_actor_id < 0 and cred.has("actor_id") and int(cred["actor_id"]) >= 0:
		var aid: int = int(cred["actor_id"])
		if st.length() > 0 or aid >= 0:
			_local_actor_id = aid
	if _display_name.is_empty():
		_display_name = CloudCredentialStoreScript.full_display_name(cred, {})


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
	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.pressed.connect(_on_back)
	vbox.add_child(back_btn)
	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 24)
	vbox.add_child(_title_label)
	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_status_label)
	var refresh_btn := Button.new()
	refresh_btn.text = "Refresh"
	refresh_btn.pressed.connect(_on_refresh)
	vbox.add_child(refresh_btn)
	_slots_box = VBoxContainer.new()
	_slots_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_slots_box)
	var si: int = 0
	while si < CloudStagingParsersScript.EXPECTED_SLOT_COUNT:
		_slot_panels.append(_make_slot_panel(si))
		_slots_box.add_child(_slot_panels[si] as Control)
		si += 1


func _make_slot_panel(slot_index: int) -> PanelContainer:
	var panel := PanelContainer.new()
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)
	var vb := VBoxContainer.new()
	margin.add_child(vb)
	var hdr := Label.new()
	hdr.name = "SlotHeader"
	hdr.text = "Seat %d" % (slot_index + 1)
	vb.add_child(hdr)
	var state_lbl := Label.new()
	state_lbl.name = "SlotState"
	vb.add_child(state_lbl)
	var claim_btn := Button.new()
	claim_btn.name = "ClaimBtn"
	claim_btn.text = "Claim this slot"
	claim_btn.visible = false
	claim_btn.pressed.connect(_on_claim_pressed.bind(slot_index))
	vb.add_child(claim_btn)
	var faction_row := HBoxContainer.new()
	faction_row.name = "FactionRow"
	faction_row.visible = false
	var faction_opt := OptionButton.new()
	faction_opt.name = "FactionOption"
	faction_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	faction_row.add_child(faction_opt)
	var faction_btn := Button.new()
	faction_btn.name = "FactionApplyBtn"
	faction_btn.text = "Choose faction"
	faction_btn.pressed.connect(_on_faction_apply_pressed.bind(slot_index))
	faction_row.add_child(faction_btn)
	vb.add_child(faction_row)
	var ready_row := HBoxContainer.new()
	ready_row.name = "ReadyRow"
	ready_row.visible = false
	var ready_btn := Button.new()
	ready_btn.name = "ReadyBtn"
	ready_btn.text = "Ready"
	ready_btn.pressed.connect(_on_ready_pressed.bind(slot_index, true))
	ready_row.add_child(ready_btn)
	var unready_btn := Button.new()
	unready_btn.name = "UnreadyBtn"
	unready_btn.text = "Unready"
	unready_btn.pressed.connect(_on_ready_pressed.bind(slot_index, false))
	ready_row.add_child(unready_btn)
	vb.add_child(ready_row)
	panel.set_meta("slot_index", slot_index)
	return panel


func _set_status(msg: String) -> void:
	if _status_label != null:
		_status_label.text = msg


func _set_busy(on: bool) -> void:
	_busy = on


func _make_session(gameplay_token: String = "") -> Node:
	var sess = CloudSessionScript.new()
	sess.base_url = _server_url
	sess.match_id = _match_id
	var tok: String = gameplay_token if not gameplay_token.is_empty() else _seat_token
	sess.seat_token = tok
	add_child(sess)
	return sess


func _on_back() -> void:
	get_tree().change_scene_to_file(FRONT_DOOR_SCENE)


func _on_refresh() -> void:
	await _refresh_from_server()


func _title_text(lobby_row: Dictionary) -> String:
	var dn: String = str(lobby_row.get("display_name", "")).strip_edges()
	if dn.is_empty():
		dn = _display_name
	return CloudCredentialStoreScript.player_visible_display_name(dn)


func _refresh_from_server() -> void:
	if _busy or _match_id.is_empty():
		return
	_set_busy(true)
	_set_status("Loading staging state…")
	var sess = _make_session()
	var raw: Dictionary = await sess.get_matches_list("")
	sess.queue_free()
	_set_busy(false)
	var parsed: Dictionary = CloudClientScript.parse_lobby_list_response(raw)
	if parsed.has("_error"):
		_set_status("Could not load match from server.")
		_render_empty_slots()
		return
	var row: Dictionary = CloudStagingParsersScript.find_lobby_row(
		parsed.get("matches", []) as Array,
		_match_id,
	)
	if row.is_empty():
		_set_status("This match is not on the server list.")
		_render_empty_slots()
		return
	var view: Dictionary = CloudStagingParsersScript.build_staging_view(row, _local_actor_id)
	if not bool(view.get("ok", false)):
		var err: String = str(view.get("error", "unknown"))
		if err == "missing_available_factions":
			_set_status("Server did not provide available factions.")
		else:
			_set_status("Could not read staging state.")
		_render_empty_slots()
		return
	await _apply_staging_view(view, row)


func _render_empty_slots() -> void:
	if _title_label != null:
		_title_label.text = CloudCredentialStoreScript.player_visible_display_name(_display_name)


func _apply_staging_view(view: Dictionary, lobby_row: Dictionary) -> void:
	if _title_label != null:
		_title_label.text = _title_text(lobby_row)
	var status: String = str(view.get("status", "")).strip_edges()
	var has_seat: bool = not _seat_token.is_empty()
	if CloudStagingParsersScript.can_enter_gameplay_from_staging(has_seat, status):
		_enter_gameplay()
		return
	if CloudStagingParsersScript.host_only_needs_claim(not _host_token.is_empty(), has_seat, status):
		_set_status("Choose a player slot before entering the match.")
	elif status == CloudCredentialStoreScript.STATUS_STAGING:
		if bool(view.get("ready_to_start", false)):
			_set_status("All players ready — waiting for server to start…")
		else:
			_set_status("Staging — claim a slot, choose a faction, then Ready.")
	else:
		_set_status("Match status: %s" % status)
	var slots: Array = view.get("slots", []) as Array
	var i: int = 0
	while i < _slot_panels.size() and i < slots.size():
		_render_slot(_slot_panels[i] as PanelContainer, slots[i] as Dictionary)
		i += 1


func _render_slot(panel: PanelContainer, slot: Dictionary) -> void:
	var vb: VBoxContainer = (panel.get_child(0) as MarginContainer).get_child(0) as VBoxContainer
	var state_lbl: Label = vb.get_node("SlotState") as Label
	var claim_btn: Button = vb.get_node("ClaimBtn") as Button
	var faction_row: HBoxContainer = vb.get_node("FactionRow") as HBoxContainer
	var ready_row: HBoxContainer = vb.get_node("ReadyRow") as HBoxContainer
	var faction_opt: OptionButton = faction_row.get_node("FactionOption") as OptionButton
	var faction_btn: Button = faction_row.get_node("FactionApplyBtn") as Button
	var ready_btn: Button = ready_row.get_node("ReadyBtn") as Button
	var unready_btn: Button = ready_row.get_node("UnreadyBtn") as Button
	var aid: int = int(slot.get("actor_id", -1))
	var claimed: bool = bool(slot.get("claimed", false))
	var is_mine: bool = bool(slot.get("is_mine", false))
	if claimed:
		if is_mine:
			var fn: String = str(slot.get("faction_display", "")).strip_edges()
			var rd: String = "Ready" if bool(slot.get("ready", false)) else "Not ready"
			if fn.is_empty():
				state_lbl.text = "Your slot — choose a faction. (%s)" % rd
			else:
				state_lbl.text = "Your slot — %s (%s)" % [fn, rd]
		else:
			var other_fn: String = str(slot.get("faction_display", "")).strip_edges()
			if other_fn.is_empty():
				state_lbl.text = "Claimed — setting up"
			else:
				state_lbl.text = "Claimed — %s" % other_fn
	else:
		state_lbl.text = "Open"
	claim_btn.visible = bool(slot.get("can_claim", false))
	faction_row.visible = is_mine and claimed
	ready_row.visible = is_mine and claimed
	claim_btn.set_meta("actor_id", aid)
	faction_opt.clear()
	var choices: Array = slot.get("faction_choices", []) as Array
	var sel: int = 0
	var ci: int = 0
	while ci < choices.size():
		var ch = choices[ci]
		ci += 1
		if typeof(ch) != TYPE_DICTIONARY:
			continue
		var cd: Dictionary = ch as Dictionary
		var fid: String = str(cd.get("id", ""))
		var label: String = str(cd.get("display_name", fid))
		if bool(cd.get("taken", false)):
			label += " (taken)"
		faction_opt.add_item(label)
		faction_opt.set_item_metadata(faction_opt.item_count - 1, fid)
		faction_opt.set_item_disabled(faction_opt.item_count - 1, bool(cd.get("taken", false)))
		if fid == str(slot.get("faction_id", "")):
			sel = faction_opt.item_count - 1
	if faction_opt.item_count > 0:
		faction_opt.select(sel)
	faction_btn.disabled = faction_opt.item_count == 0
	ready_btn.disabled = str(slot.get("faction_id", "")).is_empty()
	unready_btn.disabled = not bool(slot.get("ready", false))


func _on_claim_pressed(slot_index: int) -> void:
	if _busy:
		return
	var panel: PanelContainer = _slot_panels[slot_index] as PanelContainer
	var claim_btn: Button = ((panel.get_child(0) as MarginContainer).get_child(0) as VBoxContainer).get_node(
		"ClaimBtn"
	) as Button
	var actor_id: int = int(claim_btn.get_meta("actor_id", slot_index))
	_set_busy(true)
	_set_status("Claiming slot…")
	var sess = _make_session("")
	var raw: Dictionary = await sess.post_claim_seat(actor_id)
	sess.queue_free()
	_set_busy(false)
	var parsed: Dictionary = CloudClientScript.parse_claim_response(raw)
	if not bool(parsed.get("ok", false)):
		_set_status("Claim failed: %s" % str(parsed.get("_error", "unknown")))
		return
	_seat_token = str(parsed["seat_token"])
	_local_actor_id = int(parsed["actor_id"])
	CloudCredentialStoreScript.merge_seat_claim(
		_server_url,
		_match_id,
		_seat_token,
		_local_actor_id,
		str(parsed.get("display_name", "")),
	)
	await _refresh_from_server()


func _on_faction_apply_pressed(slot_index: int) -> void:
	if _busy or _local_actor_id < 0 or _seat_token.is_empty():
		return
	var panel: PanelContainer = _slot_panels[slot_index] as PanelContainer
	var faction_opt: OptionButton = (
		((panel.get_child(0) as MarginContainer).get_child(0) as VBoxContainer)
		.get_node("FactionRow") as HBoxContainer
	).get_node("FactionOption") as OptionButton
	if faction_opt.item_count < 1 or faction_opt.selected < 0:
		return
	var fid: String = str(faction_opt.get_item_metadata(faction_opt.selected))
	_set_busy(true)
	_set_status("Saving faction…")
	var sess = _make_session()
	var raw: Dictionary = await sess.post_seat_faction(_local_actor_id, fid)
	sess.queue_free()
	_set_busy(false)
	var parsed: Dictionary = CloudClientScript.parse_staging_summary_response(raw)
	if not bool(parsed.get("ok", false)):
		_set_status("Faction failed: %s" % str(parsed.get("_error", "unknown")))
		await _refresh_from_server()
		return
	await _apply_summary(parsed["summary"] as Dictionary)


func _on_ready_pressed(slot_index: int, ready: bool) -> void:
	if _busy or _local_actor_id < 0 or _seat_token.is_empty():
		return
	_set_busy(true)
	_set_status("Marking ready…" if ready else "Marking not ready…")
	var sess = _make_session()
	var raw: Dictionary = await sess.post_seat_ready(_local_actor_id, ready)
	sess.queue_free()
	_set_busy(false)
	var parsed: Dictionary = CloudClientScript.parse_staging_summary_response(raw)
	if not bool(parsed.get("ok", false)):
		_set_status("Ready update failed: %s" % str(parsed.get("_error", "unknown")))
		await _refresh_from_server()
		return
	await _apply_summary(parsed["summary"] as Dictionary)


func _apply_summary(summary: Dictionary) -> void:
	var row: Dictionary = summary.duplicate(true)
	var view: Dictionary = CloudStagingParsersScript.build_staging_view(row, _local_actor_id)
	if not bool(view.get("ok", false)):
		await _refresh_from_server()
		return
	await _apply_staging_view(view, row)


func _enter_gameplay() -> void:
	if _seat_token.is_empty() or _local_actor_id < 0:
		_set_status("Claim a slot before entering the match.")
		return
	BootIntentScript.set_cloud_reconnect(
		_server_url,
		_match_id,
		_seat_token,
		_local_actor_id,
	)
	get_tree().change_scene_to_file(MAIN_SCENE)
