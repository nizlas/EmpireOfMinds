# WorldMap city visual asset catalog (presentation-only).
#
# Owns the production scene paths for modular Ancient Era city visuals.
# WorldCitiesView is the only production consumer today. The frozen legacy
# ancient_village path (warrior_3d_unit_experiment.city_scene_path) is
# intentionally NOT routed here and must remain available to the deprecated
# HexMap/2D presentation path.
class_name WorldCityVisualCatalog
extends RefCounted

const MAIN_BUILDING_SCENE_PATH := (
	"res://assets/prototype/3d/cities/ancient_era/buildings/main_building/"
	+ "ancient_era_city_main_building.glb"
)


static func main_building_scene_path() -> String:
	if ResourceLoader.exists(MAIN_BUILDING_SCENE_PATH):
		return MAIN_BUILDING_SCENE_PATH
	return ""


static func load_main_building_scene() -> PackedScene:
	var path := main_building_scene_path()
	if path.is_empty():
		return null
	return load(path) as PackedScene
