# Headless: debug scenario preplaces Niclas + Bronze-Armed Warrior for player 0 only.
extends SceneTree

const ScenarioScript = preload("res://domain/scenario.gd")
const UnitDefinitionsScript = preload("res://domain/content/unit_definitions.gd")
const MoveUnitScript = preload("res://domain/actions/move_unit.gd")
const GameStateScript = preload("res://domain/game_state.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")

var _total: int = 0
var _any_fail: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_normal_scenario_excludes_debug_units()
	_test_with_debug_character_units()
	_test_move_unit_updates_game_state()
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


func _unit_by_type(scenario, type_id: String):
	var ulist: Array = scenario.units()
	var i: int = 0
	while i < ulist.size():
		if str(ulist[i].type_id) == type_id:
			return ulist[i]
		i += 1
	return null


func _test_normal_scenario_excludes_debug_units() -> void:
	var base = ScenarioScript.make_prototype_play_scenario()
	_check(_unit_by_type(base, "niclas") == null, "prototype play excludes Niclas")
	_check(
		_unit_by_type(base, "bronze_armed_warrior") == null,
		"prototype play excludes Bronze-Armed Warrior",
	)


func _test_with_debug_character_units() -> void:
	var base = ScenarioScript.make_prototype_play_scenario()
	var debug_sc = ScenarioScript.with_debug_character_units(base)
	_check(debug_sc.units().size() == 5, "debug scenario adds two units")
	var niclas = _unit_by_type(debug_sc, "niclas")
	var bronze = _unit_by_type(debug_sc, "bronze_armed_warrior")
	_check(niclas != null, "Niclas exists in debug scenario")
	_check(bronze != null, "Bronze-Armed Warrior exists in debug scenario")
	_check(int(niclas.owner_id) == 0, "Niclas belongs to player 0")
	_check(int(bronze.owner_id) == 0, "Bronze belongs to player 0")
	_check(
		int(niclas.position.q) == ScenarioScript.DEBUG_NICLAS_HEX_Q
			and int(niclas.position.r) == ScenarioScript.DEBUG_NICLAS_HEX_R,
		"Niclas at deterministic hex",
	)
	_check(
		int(bronze.position.q) == ScenarioScript.DEBUG_BRONZE_HEX_Q
			and int(bronze.position.r) == ScenarioScript.DEBUG_BRONZE_HEX_R,
		"Bronze at deterministic hex",
	)
	_check(
		debug_sc.units_at(HexCoordScript.new(0, 0)).size() == 1,
		"settler hex unchanged",
	)
	_check(
		debug_sc.units_at(HexCoordScript.new(1, 0)).size() == 1,
		"warrior hex unchanged",
	)
	_check(UnitDefinitionsScript.has_gameplay_type("niclas"), "Niclas gameplay type resolves")
	_check(
		UnitDefinitionsScript.has_gameplay_type("bronze_armed_warrior"),
		"Bronze gameplay type resolves",
	)
	_check(
		UnitDefinitionsScript.max_movement_for_type("niclas") == 2,
		"Niclas movement from definitions",
	)


func _test_move_unit_updates_game_state() -> void:
	var debug_sc = ScenarioScript.with_debug_character_units(
		ScenarioScript.make_tiny_test_scenario()
	)
	var gs = GameStateScript.new(debug_sc)
	var niclas = _unit_by_type(gs.scenario, "niclas")
	_check(niclas != null, "tiny debug scenario has Niclas")
	var dest_q: int = -1
	var dest_r: int = 1
	var result: Dictionary = gs.try_apply(
		MoveUnitScript.make(
			0,
			int(niclas.id),
			int(niclas.position.q),
			int(niclas.position.r),
			dest_q,
			dest_r,
		)
	)
	_check(result["accepted"], "MoveUnit accepted for Niclas")
	var moved = gs.scenario.unit_by_id(int(niclas.id))
	_check(int(moved.position.q) == dest_q and int(moved.position.r) == dest_r, "Niclas hex updated")
