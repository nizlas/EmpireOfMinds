# Headless: C14d-4b cloud ongoing waiting/read-only turn ownership.
extends SceneTree

const GameStateScript = preload("res://domain/game_state.gd")
const EndTurnScript = preload("res://domain/actions/end_turn.gd")
const TurnOwnershipScript = preload("res://cloud/cloud_turn_ownership.gd")
const CloudCredentialStoreScript = preload("res://cloud/cloud_credential_store.gd")
const PlayerContactStripScript = preload("res://presentation/player_contact_strip.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	_test_current_and_local_actor()
	_test_waiting_status_text()
	_test_seat_not_allowed_response()
	_test_gameplay_actor_from_boot_and_credential()
	_test_end_turn_enters_waiting()
	_test_refresh_reenables_when_turn_returns()
	_test_player_contact_strip_waiting_label()
	_test_hotseat_unaffected()
	if _any_fail:
		call_deferred("quit", 1)
	else:
		print("PASS %d/%d" % [_total, _total])
		call_deferred("quit", 0)


func _check(cond: bool, message: String) -> void:
	_total += 1
	if cond:
		return
	_any_fail = true
	var line := "FAIL: %s" % message
	print(line)
	push_error(line)


func _test_current_and_local_actor() -> void:
	var gs = GameStateScript.make_tiny_test_state()
	_check(TurnOwnershipScript.current_actor_id_from_turn_state(gs.turn_state) == 0, "current actor 0")
	_check(TurnOwnershipScript.is_my_cloud_turn(0, gs.turn_state), "local 0 is current")
	_check(not TurnOwnershipScript.is_my_cloud_turn(1, gs.turn_state), "local 1 not current")
	_check(
		TurnOwnershipScript.is_cloud_waiting_readonly(true, 1, gs.turn_state),
		"cloud waiting when local 1 not current",
	)
	_check(
		not TurnOwnershipScript.is_cloud_waiting_readonly(false, 1, gs.turn_state),
		"hotseat path not cloud waiting flag",
	)
	_check(
		TurnOwnershipScript.is_cloud_waiting_readonly(true, -1, gs.turn_state),
		"missing local actor is waiting",
	)


func _test_waiting_status_text() -> void:
	var gs = GameStateScript.make_tiny_test_state()
	_check(
		TurnOwnershipScript.waiting_status_text(true, 1, gs.turn_state)
			== TurnOwnershipScript.WAITING_STATUS_TEXT,
		"out-of-turn waiting text",
	)
	_check(
		TurnOwnershipScript.waiting_status_text(true, 0, gs.turn_state).is_empty(),
		"my turn hides waiting",
	)
	gs.try_apply(EndTurnScript.make(0))
	_check(
		TurnOwnershipScript.waiting_status_text(true, 0, gs.turn_state)
			== TurnOwnershipScript.WAITING_STATUS_TEXT,
		"waiting shows friendly text",
	)
	_check(
		TurnOwnershipScript.waiting_status_text(true, 0, gs.turn_state).find("actor") < 0,
		"no actor id in waiting text",
	)


func _test_seat_not_allowed_response() -> void:
	_check(
		TurnOwnershipScript.is_seat_not_allowed_response({"accepted": false, "reason": "seat_not_allowed"}),
		"seat_not_allowed detected",
	)
	_check(
		not TurnOwnershipScript.is_seat_not_allowed_response({"accepted": true, "snapshot": {}}),
		"accepted not seat_not_allowed",
	)


func _test_gameplay_actor_from_boot_and_credential() -> void:
	var boot_ok: Dictionary = {"seat_token": "st_abc", "actor_id": 1}
	_check(TurnOwnershipScript.gameplay_actor_id_from_boot(boot_ok) == 1, "boot seat actor")
	_check(
		TurnOwnershipScript.gameplay_actor_id_from_boot({"seat_token": "ht_host", "actor_id": 0}) < 0,
		"host token not gameplay actor",
	)
	var cred: Dictionary = CloudCredentialStoreScript.make_entry(
		"http://127.0.0.1:8000",
		"m1",
		1,
		"st_play",
		false,
		-1,
		CloudCredentialStoreScript.STATUS_ONGOING,
		"",
		"ht_admin",
	)
	_check(TurnOwnershipScript.gameplay_actor_id_from_credential(cred) == 1, "credential seat actor")
	_check(
		TurnOwnershipScript.gameplay_actor_id_from_credential(
			{"seat_token": "ht_only", "actor_id": 0, "is_host": true}
		)
			< 0,
		"host-only credential no gameplay actor",
	)


func _test_end_turn_enters_waiting() -> void:
	var gs = GameStateScript.make_tiny_test_state()
	_check(TurnOwnershipScript.is_my_cloud_turn(0, gs.turn_state), "A starts active")
	gs.try_apply(EndTurnScript.make(0))
	_check(not TurnOwnershipScript.is_my_cloud_turn(0, gs.turn_state), "A waiting after end turn")
	_check(TurnOwnershipScript.is_my_cloud_turn(1, gs.turn_state), "B becomes active")


func _test_refresh_reenables_when_turn_returns() -> void:
	var gs = GameStateScript.make_tiny_test_state()
	gs.try_apply(EndTurnScript.make(0))
	_check(
		TurnOwnershipScript.is_cloud_waiting_readonly(true, 0, gs.turn_state),
		"waiting before refresh snapshot",
	)
	gs.try_apply(EndTurnScript.make(1))
	_check(TurnOwnershipScript.is_my_cloud_turn(0, gs.turn_state), "after B end turn A active again")


func _test_player_contact_strip_waiting_label() -> void:
	var gs = GameStateScript.make_tiny_test_state()
	var strip = PlayerContactStripScript.new()
	strip.game_state = gs
	strip.cloud_waiting_status_text = TurnOwnershipScript.WAITING_STATUS_TEXT
	strip._ready()
	strip.refresh()
	_check(strip._waiting_label != null, "waiting label node exists")
	_check(strip._waiting_label.text == TurnOwnershipScript.WAITING_STATUS_TEXT, "waiting label text")
	_check(strip._waiting_label.visible, "waiting label visible")
	strip.cloud_waiting_status_text = ""
	strip.refresh()
	_check(not strip._waiting_label.visible, "waiting label hidden when active")
	_check(strip._waiting_label.text.is_empty(), "waiting label cleared")
	strip.free()


func _test_hotseat_unaffected() -> void:
	var gs = GameStateScript.make_tiny_test_state()
	_check(
		not TurnOwnershipScript.is_cloud_waiting_readonly(false, 1, gs.turn_state),
		"non-cloud never waiting-readonly",
	)
	_check(
		TurnOwnershipScript.waiting_status_text(false, 1, gs.turn_state).is_empty(),
		"non-cloud no waiting status text",
	)
