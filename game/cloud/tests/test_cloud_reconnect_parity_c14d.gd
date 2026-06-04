# Headless: C14d reconnect parity — seat identity, fog perspective, waiting poll, banner gating.
extends SceneTree

const GameStateScript = preload("res://domain/game_state.gd")
const EndTurnScript = preload("res://domain/actions/end_turn.gd")
const TurnOwnershipScript = preload("res://cloud/cloud_turn_ownership.gd")
const CloudCredentialStoreScript = preload("res://cloud/cloud_credential_store.gd")
const CloudClientScript = preload("res://cloud/cloud_client.gd")
const PresentationVisibilityScript = preload("res://presentation/presentation_visibility.gd")
const BootIntentScript = preload("res://cloud/boot_intent.gd")

const SERVER: String = "http://127.0.0.1:8000"
const MID: String = "m_reconnect_parity"

var _total = 0
var _any_fail = false


func _init() -> void:
	_test_profile_credentials_restore_actor_and_seat()
	_test_resolve_seat_token_rejects_host_inspector()
	_test_persist_after_bootstrap_preserves_seat_actor()
	_test_reconnect_visibility_before_fog()
	_test_reconnect_waiting_and_active_ownership()
	_test_reconnect_banner_gating()
	_test_two_locals_cannot_both_be_active()
	_test_host_token_boot_no_gameplay_identity()
	_test_waiting_poll_after_reconnect_turn_flip()
	_test_space_blocked_while_waiting_policy()
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


func _test_profile_credentials_restore_actor_and_seat() -> void:
	var path_a: String = CloudCredentialStoreScript.store_path_for_profile_name("A")
	var path_b: String = CloudCredentialStoreScript.store_path_for_profile_name("B")
	CloudCredentialStoreScript.upsert(
		path_a,
		CloudCredentialStoreScript.make_entry(
			SERVER, MID, 0, "st_profile_a", false, 1, CloudCredentialStoreScript.STATUS_ONGOING
		),
	)
	CloudCredentialStoreScript.upsert(
		path_b,
		CloudCredentialStoreScript.make_entry(
			SERVER, MID, 1, "st_profile_b", false, 2, CloudCredentialStoreScript.STATUS_ONGOING
		),
	)
	var cred_a: Dictionary = CloudCredentialStoreScript.find(path_a, SERVER, MID)
	var cred_b: Dictionary = CloudCredentialStoreScript.find(path_b, SERVER, MID)
	_check(
		CloudCredentialStoreScript.gameplay_token_from_entry(cred_a) == "st_profile_a",
		"profile A seat_token restored",
	)
	_check(TurnOwnershipScript.gameplay_actor_id_from_credential(cred_a) == 0, "profile A actor_id 0")
	_check(
		CloudCredentialStoreScript.gameplay_token_from_entry(cred_b) == "st_profile_b",
		"profile B seat_token restored",
	)
	_check(TurnOwnershipScript.gameplay_actor_id_from_credential(cred_b) == 1, "profile B actor_id 1")
	var view_a: Dictionary = CloudClientScript.build_resume_row_view(
		{"match_id": MID, "status": CloudCredentialStoreScript.STATUS_ONGOING},
		cred_a,
		SERVER,
	)
	var view_b: Dictionary = CloudClientScript.build_resume_row_view(
		{"match_id": MID, "status": CloudCredentialStoreScript.STATUS_ONGOING},
		cred_b,
		SERVER,
	)
	_check(int(view_a.get("actor_id", -1)) == 0, "resume row A actor_id")
	_check(int(view_b.get("actor_id", -1)) == 1, "resume row B actor_id")


func _test_resolve_seat_token_rejects_host_inspector() -> void:
	var resolved: Dictionary = CloudCredentialStoreScript.resolve_seat_token_for_boot(
		SERVER,
		MID,
		"",
		"ht_inspector_only",
		CloudCredentialStoreScript.DEFAULT_PATH,
		"",
	)
	_check(str(resolved.get("value", "")).is_empty(), "host inspector token not gameplay seat token")
	var boot_st: Dictionary = CloudCredentialStoreScript.resolve_seat_token_for_boot(
		SERVER,
		MID,
		"",
		"",
		CloudCredentialStoreScript.DEFAULT_PATH,
		"st_boot",
	)
	_check(str(boot_st.get("value", "")) == "st_boot", "boot seat token wins")


func _test_persist_after_bootstrap_preserves_seat_actor() -> void:
	var path: String = "user://cloud_reconnect_persist_test.json"
	CloudCredentialStoreScript.upsert(
		path,
		CloudCredentialStoreScript.make_entry(
			SERVER, "m_persist", 1, "st_persist", false, 1, CloudCredentialStoreScript.STATUS_ONGOING
		),
	)
	CloudCredentialStoreScript.persist_after_bootstrap(
		path, SERVER, "m_persist", "st_persist", false, {"revision": 3}, 1
	)
	var e: Dictionary = CloudCredentialStoreScript.find(path, SERVER, "m_persist")
	_check(int(e.get("actor_id", -1)) == 1, "persist_after_bootstrap keeps seat actor_id")


func _test_reconnect_visibility_before_fog() -> void:
	var gs = GameStateScript.make_tiny_test_state()
	PresentationVisibilityScript.viewing_player_id_override = -1
	_check(
		PresentationVisibilityScript.effective_viewing_player_id(gs) == 0,
		"without override fog follows current actor",
	)
	PresentationVisibilityScript.viewing_player_id_override = 1
	_check(
		TurnOwnershipScript.visibility_actor_id(true, 1, gs.turn_state) == 1,
		"visibility_actor_id is local before current",
	)
	_check(
		PresentationVisibilityScript.effective_viewing_player_id(gs) == 1,
		"override set before fog read uses local",
	)
	PresentationVisibilityScript.viewing_player_id_override = -1


func _test_reconnect_waiting_and_active_ownership() -> void:
	var gs = GameStateScript.make_tiny_test_state()
	_check(
		TurnOwnershipScript.is_cloud_waiting_readonly(true, 1, gs.turn_state),
		"reconnect waiting when local 1 current 0",
	)
	_check(
		TurnOwnershipScript.cloud_waiting_poll_should_run(true, false, false, 1, gs.turn_state),
		"waiting poll should start after reconnect",
	)
	_check(
		not TurnOwnershipScript.cloud_waiting_poll_should_run(true, false, false, 0, gs.turn_state),
		"active seat no waiting poll",
	)
	_check(not TurnOwnershipScript.is_cloud_waiting_readonly(true, 0, gs.turn_state), "active not waiting")


func _test_reconnect_banner_gating() -> void:
	var gs = GameStateScript.make_tiny_test_state()
	var cur: int = TurnOwnershipScript.current_actor_id_from_turn_state(gs.turn_state)
	_check(
		not CloudClientScript.should_show_turn_start_banner(cur, cur, true, 1),
		"waiting client no banner when prev equals current",
	)
	_check(
		not CloudClientScript.should_show_turn_start_banner(null, cur, true, 1),
		"waiting client no banner on reconnect-style null prev",
	)
	_check(
		CloudClientScript.should_show_turn_start_banner(null, cur, true, 0),
		"active client may show banner when local matches current",
	)
	_check(
		not CloudClientScript.should_show_turn_start_banner(null, cur, true, 1),
		"waiting client no Your turn banner for other civ",
	)


func _test_two_locals_cannot_both_be_active() -> void:
	var gs = GameStateScript.make_tiny_test_state()
	var a_active: bool = TurnOwnershipScript.is_my_cloud_turn(0, gs.turn_state)
	var b_active: bool = TurnOwnershipScript.is_my_cloud_turn(1, gs.turn_state)
	_check(a_active and not b_active, "only one local active for snapshot")
	_check(not (a_active and b_active), "two actor_ids cannot both be active")


func _test_host_token_boot_no_gameplay_identity() -> void:
	_check(
		TurnOwnershipScript.gameplay_actor_id_from_boot(
			{"seat_token": "ht_only", "actor_id": 0}
		)
			< 0,
		"host-token-only boot has no gameplay actor",
	)
	BootIntentScript.set_cloud_reconnect(SERVER, MID, "ht_only", 0)
	var snap: Dictionary = BootIntentScript.consume_for_main()
	_check(
		TurnOwnershipScript.gameplay_actor_id_from_boot(
			{"seat_token": str(snap.get("seat_token", "")), "actor_id": int(snap.get("actor_id", -1))}
		)
			< 0,
		"consumed host reconnect boot not gameplay identity",
	)


func _test_waiting_poll_after_reconnect_turn_flip() -> void:
	var gs = GameStateScript.make_tiny_test_state()
	_check(
		TurnOwnershipScript.cloud_waiting_poll_should_run(true, false, false, 1, gs.turn_state),
		"poll while B waiting",
	)
	gs.try_apply(EndTurnScript.make(0))
	_check(
		TurnOwnershipScript.is_my_cloud_turn(1, gs.turn_state),
		"B active after poll snapshot flip",
	)
	_check(
		not TurnOwnershipScript.cloud_waiting_poll_should_run(true, false, false, 1, gs.turn_state),
		"poll stops when turn becomes local",
	)


func _test_space_blocked_while_waiting_policy() -> void:
	var gs = GameStateScript.make_tiny_test_state()
	_check(
		TurnOwnershipScript.is_cloud_waiting_readonly(true, 1, gs.turn_state),
		"waiting blocks gameplay actions",
	)
	_check(CloudClientScript.is_cloud_space_end_turn_shortcut(true, _fake_space_key()), "space routed in cloud")
	_check(
		TurnOwnershipScript.is_cloud_waiting_readonly(true, 1, gs.turn_state),
		"waiting still blocks before deferred end_turn handler",
	)


func _test_hotseat_unaffected() -> void:
	PresentationVisibilityScript.viewing_player_id_override = -1
	var gs = GameStateScript.make_tiny_test_state()
	_check(
		not TurnOwnershipScript.is_cloud_waiting_readonly(false, 1, gs.turn_state),
		"hotseat not waiting-readonly",
	)
	_check(
		PresentationVisibilityScript.effective_viewing_player_id(gs)
			== gs.turn_state.current_player_id(),
		"hotseat fog follows current",
	)


func _fake_space_key() -> InputEventKey:
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.echo = false
	ev.keycode = KEY_SPACE
	return ev
