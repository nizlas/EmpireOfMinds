class_name FactionAssetPaths
extends RefCounted

const _BANNER_BY_ID: Dictionary = {
	"debug_vasterviksjavlarna": "res://assets/prototype/factions/banners/debug_vasterviksjavlarna.png",
	"debug_malmofubikkarna": "res://assets/prototype/factions/banners/debug_malmofubikkarna.png",
	"debug_pajasarna_fran_paris": "res://assets/prototype/factions/banners/debug_pajasarna_fran_paris.png",
}


static func banner_path(id: String) -> String:
	return String(_BANNER_BY_ID.get(id, ""))


static func banner_paths_by_id() -> Dictionary:
	return _BANNER_BY_ID.duplicate(true)
