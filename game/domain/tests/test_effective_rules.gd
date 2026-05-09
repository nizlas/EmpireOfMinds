# Headless: godot --headless --path game -s res://domain/tests/test_effective_rules.gd
extends SceneTree

const EffectiveRulesScript = preload("res://domain/effective_rules.gd")
const CityProjectDefinitionsScript = preload("res://domain/content/city_project_definitions.gd")
const SetCityProductionScript = preload("res://domain/actions/set_city_production.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	var er = EffectiveRulesScript.with_baseline_registries()
	_check(
		er.is_city_project_supported(SetCityProductionScript.PROJECT_ID_PRODUCE_UNIT_WARRIOR),
		"warrior project supported"
	)
	_check(
		er.is_city_project_supported(SetCityProductionScript.PROJECT_ID_PRODUCE_UNIT_SETTLER),
		"settler project supported"
	)
	_check(er.is_city_project_supported(CityProjectDefinitionsScript.PROJECT_ID_NONE) == false, "none unsupported")
	_check(er.is_city_project_supported("") == false, "empty unsupported")
	_check(er.is_city_project_supported("clearly_not_a_real_id") == false, "garbage unsupported")

	var a = EffectiveRulesScript.with_baseline_registries()
	var b = EffectiveRulesScript.with_baseline_registries()
	_check(a != b, "distinct instances")
	var wid = SetCityProductionScript.PROJECT_ID_PRODUCE_UNIT_WARRIOR
	_check(a.is_city_project_supported(wid) == b.is_city_project_supported(wid), "independent instances same results")

	if _any_fail:
		call_deferred("quit", 1)
	else:
		print("PASS %d/%d" % [_total, _total])
		call_deferred("quit", 0)


func _check(cond, message) -> void:
	_total = _total + 1
	if cond:
		return
	_any_fail = true
	var line = "FAIL: %s" % message
	print(line)
	push_error(line)
