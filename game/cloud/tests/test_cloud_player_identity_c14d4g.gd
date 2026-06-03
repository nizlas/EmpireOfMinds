# C14d-4g: staging faction choices → ongoing player display names (no actor default fallback).
extends SceneTree

const CloudPlayerIdentityScript = preload("res://cloud/cloud_player_identity.gd")
const PlaytestPlayerDisplayScript = preload("res://presentation/playtest_player_display.gd")
const PlayerContactStripScript = preload("res://presentation/player_contact_strip.gd")
const TurnOwnershipScript = preload("res://cloud/cloud_turn_ownership.gd")
const PresentationVisibilityScript = preload("res://presentation/presentation_visibility.gd")
const ServerSnapshotAdapterScript = preload("res://cloud/server_snapshot_adapter.gd")
const GameStateScript = preload("res://domain/game_state.gd")

const NAME_PARIS: String = "Pajasarna från Paris"
const NAME_MALMO: String = "Malmöfubikkarna"
const NAME_VASTERVIK: String = "Västerviksjävlarna"

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


func _run() -> int:
	var failed: int = 0
	failed += _test_snapshot_adapter_paris_and_vastervik()
	failed += _test_no_silent_paris_to_malmo_fallback()
	failed += _test_hotseat_defaults_without_registry()
	failed += _test_contact_strip_and_visibility_unchanged()
	return failed


func _test_snapshot_adapter_paris_and_vastervik() -> int:
	var failed: int = 0
	var snap := {
		"schema_version": 2,
		"revision": 1,
		"scenario_id": "tiny_test",
		"player_factions": {"0": "vastervik", "1": "paris"},
		"scenario": _minimal_scenario_dict(),
		"turn_state": {"players": [0, 1], "current_index": 0, "turn_number": 1},
		"progress_state": {"by_owner": []},
	}
	var gs = ServerSnapshotAdapterScript.build_game_state_from_api_snapshot(snap)
	failed += _check(gs != null, "adapter builds gs")
	failed += _check(
		PlaytestPlayerDisplayScript.display_name_for_player_id(0) == NAME_VASTERVIK,
		"actor 0 vastervik display",
	)
	failed += _check(
		PlaytestPlayerDisplayScript.display_name_for_player_id(1) == NAME_PARIS,
		"actor 1 paris display",
	)
	failed += _check(
		PlaytestPlayerDisplayScript.display_name_for_player_id(1) != NAME_MALMO,
		"actor 1 not default malmo",
	)
	var strip_vm: Dictionary = PlayerContactStripScript.compute_view_model(gs)
	var entries: Array = strip_vm.get("entries", []) as Array
	var by_id: Dictionary = {}
	var ei: int = 0
	while ei < entries.size():
		var ed: Dictionary = entries[ei] as Dictionary
		by_id[int(ed.get("player_id", -1))] = str(ed.get("label_short", ""))
		ei += 1
	failed += _check(by_id.get(1, "") == NAME_PARIS, "contact strip paris")
	failed += _check(not str(by_id.get(1, "")).contains("paris"), "no raw id in UI")
	return failed


func _test_no_silent_paris_to_malmo_fallback() -> int:
	var failed: int = 0
	CloudPlayerIdentityScript.clear_registry()
	CloudPlayerIdentityScript.apply_from_snapshot(
		{"player_factions": {"0": "paris", "1": "vastervik"}},
	)
	failed += _check(
		PlaytestPlayerDisplayScript.display_name_for_player_id(0) == NAME_PARIS,
		"paris on actor 0",
	)
	failed += _check(
		PlaytestPlayerDisplayScript.display_name_for_player_id(0) != NAME_MALMO,
		"not malmo on actor 0",
	)
	failed += _check(
		CloudPlayerIdentityScript.display_name_for_faction_id("bogus_civ") == "Unknown civilization",
		"unknown faction display",
	)
	return failed


func _test_hotseat_defaults_without_registry() -> int:
	var failed: int = 0
	PlaytestPlayerDisplayScript.clear_player_faction_registry()
	failed += _check(
		PlaytestPlayerDisplayScript.display_name_for_player_id(0) == NAME_VASTERVIK,
		"hotseat P0 default",
	)
	failed += _check(
		PlaytestPlayerDisplayScript.display_name_for_player_id(1) == NAME_MALMO,
		"hotseat P1 default",
	)
	return failed


func _test_contact_strip_and_visibility_unchanged() -> int:
	var failed: int = 0
	var snap := {
		"schema_version": 2,
		"scenario": _minimal_scenario_dict(),
		"player_factions": {"0": "malmo", "1": "paris"},
		"turn_state": {"players": [0, 1], "current_index": 1, "turn_number": 1},
		"progress_state": {"by_owner": []},
	}
	var gs = ServerSnapshotAdapterScript.build_game_state_from_api_snapshot(snap)
	PresentationVisibilityScript.viewing_player_id_override = 0
	failed += _check(
		PresentationVisibilityScript.effective_viewing_player_id(gs) == 0,
		"fog uses local actor_id override",
	)
	failed += _check(
		int(gs.turn_state.current_player_id()) == 1,
		"current actor still from turn_state",
	)
	failed += _check(
		TurnOwnershipScript.is_cloud_waiting_readonly(true, 0, gs.turn_state),
		"waiting compares actor ids",
	)
	failed += _check(
		not TurnOwnershipScript.is_my_cloud_turn(0, gs.turn_state),
		"local 0 waiting when current 1",
	)
	PresentationVisibilityScript.viewing_player_id_override = -1
	return failed


func _minimal_scenario_dict() -> Dictionary:
	return {
		"map": {
			"cells": [{"q": 0, "r": 0, "terrain": "plains", "landform": "flat", "woods": false}],
		},
		"units": [],
		"cities": [],
		"next_unit_id": 1,
		"next_city_id": 1,
		"lightning_tree_hex": null,
	}
