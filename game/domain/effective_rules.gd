# Thin read-only façade over baseline content registries for the current match.
# Phase 5.1.1: first query path only; curated baseline delegates to static registries.
class_name EffectiveRules
extends RefCounted

const _CityProjectDefinitionsScript = preload("res://domain/content/city_project_definitions.gd")


static func with_baseline_registries() -> EffectiveRules:
	return (new() as EffectiveRules)


func is_city_project_supported(project_id: String) -> bool:
	if project_id == "" or project_id == _CityProjectDefinitionsScript.PROJECT_ID_NONE:
		return false
	return _CityProjectDefinitionsScript.has(project_id)
