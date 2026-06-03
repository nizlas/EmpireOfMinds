# C14d-4e: staging civilization display names and player-facing terminology.
extends SceneTree

const CloudStagingParsersScript = preload("res://cloud/cloud_staging_parsers.gd")

const ID_MALMO: String = "malmo"
const ID_VASTERVIK: String = "vastervik"
const ID_PARIS: String = "paris"
const NAME_MALMO: String = "Malmöfubikkarna"
const NAME_VASTERVIK: String = "Västerviksjävlarna"
const NAME_PARIS: String = "Pajasarna från Paris"


var _total: int = 0


func _init() -> void:
	var failed: int = _run()
	if failed == 0:
		print("PASS %d/%d" % [_total, _total])
	else:
		printerr("FAIL %d assertion(s) failed" % failed)
	quit(failed)


func _check(ok: bool, msg: String) -> int:
	_total += 1
	if ok:
		return 0
	printerr("FAIL: %s" % msg)
	return 1


func _canonical_available_factions() -> Array:
	return [
		{"id": ID_MALMO, "display_name": NAME_MALMO},
		{"id": ID_VASTERVIK, "display_name": NAME_VASTERVIK},
		{"id": ID_PARIS, "display_name": NAME_PARIS},
	]


func _run() -> int:
	var failed: int = 0
	failed += _test_placeholder_and_messages()
	failed += _test_slot_views_use_server_display_names()
	failed += _test_readonly_other_player_shows_canonical_name()
	failed += _test_taken_message_uses_civilization()
	failed += _test_ids_unchanged()
	return failed


func _test_placeholder_and_messages() -> int:
	var failed: int = 0
	failed += _check(
		CloudStagingParsersScript.DROPDOWN_PLACEHOLDER_LABEL == "Choose civilization…",
		"dropdown placeholder uses civilization",
	)
	var msgs: Array = CloudStagingParsersScript.staging_user_visible_messages()
	var combined: String = " ".join(msgs)
	failed += _check(not combined.to_lower().contains("faction"), "staging messages avoid faction wording")
	failed += _check(combined.contains("civilization"), "staging messages mention civilization")
	failed += _check(msgs.has("That civilization is already taken — choose another."), "taken message")
	return failed


func _test_slot_views_use_server_display_names() -> int:
	var failed: int = 0
	var lobby_row := {
		"match_id": "m_civ",
		"display_name": "Lobby",
		"status": "staging",
		"seats": [
			{"actor_id": 0, "claimed": true, "faction_id": ID_VASTERVIK, "ready": false},
			{"actor_id": 1, "claimed": true, "faction_id": ID_MALMO, "ready": false},
		],
		"available_factions": _canonical_available_factions(),
	}
	var view: Dictionary = CloudStagingParsersScript.build_staging_view(lobby_row, 0)
	var slots: Array = view.get("slots", []) as Array
	var slot0: Dictionary = slots[0] as Dictionary
	var choices: Array = slot0.get("faction_choices", []) as Array
	var by_id: Dictionary = {}
	var ci: int = 0
	while ci < choices.size():
		var row = choices[ci] as Dictionary
		by_id[str(row.get("id", ""))] = str(row.get("display_name", ""))
		ci += 1
	failed += _check(by_id[ID_VASTERVIK] == NAME_VASTERVIK, "dropdown vastervik canonical name")
	failed += _check(by_id[ID_MALMO] == NAME_MALMO, "dropdown malmo canonical name")
	failed += _check(by_id[ID_PARIS] == NAME_PARIS, "dropdown paris canonical name (Pajasarna från Paris)")
	failed += _check(str(slot0.get("faction_display", "")) == NAME_VASTERVIK, "mine slot faction_display")
	return failed


func _test_readonly_other_player_shows_canonical_name() -> int:
	var failed: int = 0
	var other: Dictionary = {
		"actor_id": 1,
		"claimed": true,
		"is_mine": false,
		"faction_display": NAME_MALMO,
		"ready": false,
	}
	failed += _check(
		CloudStagingParsersScript.slot_readonly_faction_display_text(other) == NAME_MALMO,
		"readonly other player malmo canonical",
	)
	return failed


func _test_taken_message_uses_civilization() -> int:
	var failed: int = 0
	var msgs: Array = CloudStagingParsersScript.staging_user_visible_messages()
	var taken_msg: String = ""
	var i: int = 0
	while i < msgs.size():
		var m: String = str(msgs[i])
		if m.contains("already taken"):
			taken_msg = m
		i += 1
	failed += _check(taken_msg.contains("civilization"), "taken validation uses civilization")
	failed += _check(not taken_msg.contains("faction"), "taken validation avoids faction")
	return failed


func _test_ids_unchanged() -> int:
	var failed: int = 0
	for fid in [ID_MALMO, ID_VASTERVIK, ID_PARIS]:
		failed += _check(
			CloudStagingParsersScript.normalize_seat_faction_id(fid) == fid,
			"stable id %s" % fid,
		)
	failed += _check(
		CloudStagingParsersScript.build_faction_post_body(ID_VASTERVIK)["faction_id"] == ID_VASTERVIK,
		"POST body still faction_id field",
	)
	return failed
