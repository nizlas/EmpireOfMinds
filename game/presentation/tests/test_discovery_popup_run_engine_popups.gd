# Headless: godot --headless --path game -s res://presentation/tests/test_discovery_popup_run_engine_popups.gd
extends SceneTree

const GameStateScript = preload("res://domain/game_state.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const HexMapScript = preload("res://domain/hex_map.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const UnitScript = preload("res://domain/unit.gd")
const CityScript = preload("res://domain/city.gd")
const MoveUnitScript = preload("res://domain/actions/move_unit.gd")
const DiscoveryPopupScript = preload("res://presentation/discovery_popup.gd")


class DiscoveryStub extends RefCounted:
	var armed_popup = null
	var armed_idx: int = -1
	var shown_bonus_idx: int = -1

	func arm_science_completed_chain(p_popup, log_index: int) -> void:
		armed_popup = p_popup
		armed_idx = log_index

	func maybe_show_for_log_index(index: int) -> void:
		shown_bonus_idx = index


class ScienceStub extends RefCounted:
	var shown_idx: int = -1

	func maybe_show_for_log_index(index: int) -> void:
		shown_idx = index


var _total = 0
var _any_fail = false


func _init() -> void:
	var m = HexMapScript.make_tiny_test_map()
	var u = [UnitScript.new(1, 0, HexCoordScript.new(0, 0), "warrior")]
	var city = CityScript.new(3, 0, HexCoordScript.new(1, -1), null)
	var tree = HexCoordScript.new(1, 0)
	var scen = ScenarioScript.new(m, u, [city], 10, 20, tree)
	var gs = GameStateScript.new(scen)
	var prev = gs.log.size()
	var disc = DiscoveryStub.new()
	var sci = ScienceStub.new()
	var mv = gs.try_apply(MoveUnitScript.make(0, 1, 0, 0, 1, 0))
	_check(mv["accepted"], "move accepted")
	var bonus_i = DiscoveryPopupScript.first_new_log_index_for_action(gs, prev, "science_bonus")
	_check(bonus_i >= 0, "found science_bonus index")
	DiscoveryPopupScript.run_engine_popups_after_apply(gs, disc, sci, prev)
	_check(disc.shown_bonus_idx == bonus_i, "discovery popup scan targets science_bonus")
	_check(disc.armed_idx < 0, "no science_completed when not finished")
	_check(sci.shown_idx < 0, "science popup deferred when only bonus")

	var gs2 = GameStateScript.new(scen)
	gs2.progress_state = gs2.progress_state.with_science_progress_added(0, "controlled_fire", 2)
	var prev2 = gs2.log.size()
	var disc2 = DiscoveryStub.new()
	var sci2 = ScienceStub.new()
	var mv2 = gs2.try_apply(MoveUnitScript.make(0, 1, 0, 0, 1, 0))
	_check(mv2["accepted"], "move 2 accepted")
	var bonus_i2 = DiscoveryPopupScript.first_new_log_index_for_action(gs2, prev2, "science_bonus")
	var done_i2 = DiscoveryPopupScript.first_new_log_index_for_action(gs2, prev2, "science_completed")
	_check(bonus_i2 >= 0 and done_i2 > bonus_i2, "bonus before completion in log")
	DiscoveryPopupScript.run_engine_popups_after_apply(gs2, disc2, sci2, prev2)
	_check(disc2.shown_bonus_idx == bonus_i2, "bonus shown first")
	_check(disc2.armed_idx == done_i2, "chain arms science_completed index")
	_check(sci2.shown_idx < 0, "science not shown until discovery OK")

	var gs3 = GameStateScript.new(scen)
	var prev3 = gs3.log.size()
	var disc3 = DiscoveryStub.new()
	var sci3 = ScienceStub.new()
	gs3.log.append({
		"action_type": "science_completed",
		"source": "engine",
		"result": "accepted",
		"actor_id": 0,
		"progress_id": "controlled_fire",
		"unlocked_targets": [],
	})
	DiscoveryPopupScript.run_engine_popups_after_apply(gs3, disc3, sci3, prev3)
	_check(disc3.shown_bonus_idx < 0, "no discovery arm without bonus")
	_check(sci3.shown_idx == prev3, "science_completed alone uses fallback scan")

	if _any_fail:
		call_deferred("quit", 1)
	else:
		print("PASS %d/%d" % [_total, _total])
		call_deferred("quit", 0)


func _check(cond: bool, message: String) -> void:
	_total = _total + 1
	if cond:
		return
	_any_fail = true
	var line = "FAIL: %s" % message
	print(line)
	push_error(line)
