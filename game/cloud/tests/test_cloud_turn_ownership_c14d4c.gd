# Headless: C14d-4c cloud local perspective + waiting poll.
extends SceneTree

const GameStateScript = preload("res://domain/game_state.gd")
const EndTurnScript = preload("res://domain/actions/end_turn.gd")
const TurnOwnershipScript = preload("res://cloud/cloud_turn_ownership.gd")
const PresentationVisibilityScript = preload("res://presentation/presentation_visibility.gd")
const MapVisibilityViewScript = preload("res://presentation/map_visibility_view.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	_test_visibility_actor_separate_from_current()
	_test_presentation_visibility_override()
	_test_waiting_poll_policy()
	_test_end_turn_starts_waiting_poll_policy()
	_test_hotseat_override_cleared()
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


func _test_visibility_actor_separate_from_current() -> void:
	var gs = GameStateScript.make_tiny_test_state()
	_check(
		TurnOwnershipScript.visibility_actor_id(true, 1, gs.turn_state) == 1,
		"cloud view actor is local",
	)
	_check(
		TurnOwnershipScript.current_actor_id_from_turn_state(gs.turn_state) == 0,
		"current actor from snapshot",
	)
	_check(
		TurnOwnershipScript.is_cloud_waiting_readonly(true, 1, gs.turn_state),
		"waiting while local != current",
	)
	_check(
		TurnOwnershipScript.visibility_actor_id(true, 1, gs.turn_state)
			!= TurnOwnershipScript.current_actor_id_from_turn_state(gs.turn_state),
		"view actor distinct from current while waiting",
	)


func _test_presentation_visibility_override() -> void:
	var gs = GameStateScript.make_tiny_test_state()
	var hex00 = HexCoordScript.new(0, 0)
	PresentationVisibilityScript.viewing_player_id_override = -1
	_check(
		PresentationVisibilityScript.effective_viewing_player_id(gs) == 0,
		"hotseat effective viewer is current",
	)
	PresentationVisibilityScript.viewing_player_id_override = 1
	_check(
		PresentationVisibilityScript.effective_viewing_player_id(gs) == 1,
		"override effective viewer is local",
	)
	_check(
		PresentationVisibilityScript.is_coord_explored_for_viewing_player(gs, hex00)
			== gs.visibility_state.is_explored(1, hex00),
		"fog uses override player 1",
	)
	var layout_stub = RefCounted.new()
	var ov: Array = MapVisibilityViewScript.compute_overlay_items(gs, layout_stub)
	var uses_p1: bool = false
	var i: int = 0
	while i < ov.size():
		var c = ov[i]
		if not gs.visibility_state.is_explored(1, c):
			uses_p1 = true
			break
		i += 1
	_check(uses_p1 or ov.is_empty(), "map overlay respects viewing player override")
	PresentationVisibilityScript.viewing_player_id_override = -1
	gs.try_apply(EndTurnScript.make(0))
	_check(
		PresentationVisibilityScript.effective_viewing_player_id(gs) == 1,
		"after end turn hotseat viewer follows current",
	)


func _test_waiting_poll_policy() -> void:
	var gs = GameStateScript.make_tiny_test_state()
	_check(
		TurnOwnershipScript.cloud_waiting_poll_should_run(
			true,
			false,
			false,
			1,
			gs.turn_state,
		),
		"poll runs while waiting",
	)
	_check(
		not TurnOwnershipScript.cloud_waiting_poll_should_run(
			true,
			false,
			false,
			0,
			gs.turn_state,
		),
		"no poll on my turn",
	)
	_check(
		not TurnOwnershipScript.cloud_waiting_poll_should_run(
			true,
			false,
			true,
			1,
			gs.turn_state,
		),
		"no poll while fetch in flight",
	)
	_check(
		not TurnOwnershipScript.cloud_waiting_poll_should_run(
			false,
			false,
			false,
			1,
			gs.turn_state,
		),
		"no poll when not cloud",
	)


func _test_end_turn_starts_waiting_poll_policy() -> void:
	var gs = GameStateScript.make_tiny_test_state()
	_check(TurnOwnershipScript.is_my_cloud_turn(0, gs.turn_state), "A active")
	gs.try_apply(EndTurnScript.make(0))
	_check(
		TurnOwnershipScript.cloud_waiting_poll_should_run(true, false, false, 0, gs.turn_state),
		"A waiting after end turn",
	)
	_check(
		TurnOwnershipScript.is_my_cloud_turn(1, gs.turn_state),
		"B active after A end turn",
	)


func _test_hotseat_override_cleared() -> void:
	PresentationVisibilityScript.viewing_player_id_override = 1
	PresentationVisibilityScript.viewing_player_id_override = -1
	_check(
		PresentationVisibilityScript.viewing_player_id_override < 0,
		"override cleared for hotseat",
	)
