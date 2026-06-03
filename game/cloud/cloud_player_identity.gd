# C14d-4g: staging faction_id per actor_id → display names (cloud + hotseat override from snapshot).
extends RefCounted
class_name CloudPlayerIdentity

const FactionDefinitionsScript = preload("res://domain/content/faction_definitions.gd")

const UNKNOWN_DISPLAY: String = "Unknown civilization"

const DISPLAY_BY_FACTION_ID: Dictionary = {
	"malmo": "Malmöfubikkarna",
	"vastervik": "Västerviksjävlarna",
	"paris": "Pajasarna från Paris",
}

## Distinct accents per chosen civilization (not per actor slot).
const ACCENT_BY_FACTION_ID: Dictionary = {
	"vastervik": Color(0.38, 0.56, 0.62, 1.0),
	"malmo": Color(0.58, 0.32, 0.36, 1.0),
	"paris": Color(0.52, 0.44, 0.58, 1.0),
}

static var _faction_by_player_id: Dictionary = {}


static func clear_registry() -> void:
	_faction_by_player_id = {}


static func has_registry() -> bool:
	return not _faction_by_player_id.is_empty()


static func faction_id_for_player_id(player_id: int) -> String:
	return str(_faction_by_player_id.get(int(player_id), "")).strip_edges()


static func apply_from_snapshot(snap: Dictionary) -> void:
	clear_registry()
	var raw = snap.get("player_factions", null)
	if typeof(raw) != TYPE_DICTIONARY:
		return
	var d: Dictionary = raw as Dictionary
	for key in d.keys():
		var aid: int = int(key)
		var fid: String = str(d[key]).strip_edges()
		if aid < 0 or fid.is_empty():
			continue
		if not DISPLAY_BY_FACTION_ID.has(fid):
			push_warning("CloudPlayerIdentity: unknown faction_id '%s' for actor %d" % [fid, aid])
		_faction_by_player_id[aid] = fid


static func display_name_for_faction_id(faction_id: String) -> String:
	var fid: String = str(faction_id).strip_edges()
	if fid.is_empty():
		return ""
	if DISPLAY_BY_FACTION_ID.has(fid):
		return str(DISPLAY_BY_FACTION_ID[fid])
	return UNKNOWN_DISPLAY


static func display_name_for_player_id(player_id: int) -> String:
	var fid: String = faction_id_for_player_id(player_id)
	if fid.is_empty():
		return ""
	return display_name_for_faction_id(fid)


static func accent_color_for_player_id(player_id: int) -> Color:
	var fid: String = faction_id_for_player_id(player_id)
	if ACCENT_BY_FACTION_ID.has(fid):
		return ACCENT_BY_FACTION_ID[fid] as Color
	return Color(0.45, 0.45, 0.5, 1.0)
