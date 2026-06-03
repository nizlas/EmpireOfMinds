# Phase **5.2.6a** — seat labels (**player id** / actor_id → display name). Presentation-only; **ids** stay **int** in domain.
# C14d-4g: when snapshot has **player_factions**, use staging civ names (malmo/vastervik/paris); else hotseat debug defaults.
class_name PlaytestPlayerDisplay
extends RefCounted

const FactionDefinitionsScript = preload("res://domain/content/faction_definitions.gd")
const CloudPlayerIdentityScript = preload("res://cloud/cloud_player_identity.gd")

const PROTOTYPE_PLAYER_0_FACTION_ID: String = "debug_vasterviksjavlarna"
const PROTOTYPE_PLAYER_1_FACTION_ID: String = "debug_malmofubikkarna"


static func clear_player_faction_registry() -> void:
	CloudPlayerIdentityScript.clear_registry()


static func apply_player_factions_from_snapshot(snap: Dictionary) -> void:
	CloudPlayerIdentityScript.apply_from_snapshot(snap)


static func display_name_for_player_id(player_id: int) -> String:
	var pid: int = int(player_id)
	if CloudPlayerIdentityScript.has_registry():
		var cloud_name: String = CloudPlayerIdentityScript.display_name_for_player_id(pid)
		if not cloud_name.is_empty():
			return cloud_name
	match pid:
		0:
			var n0: String = FactionDefinitionsScript.display_name(PROTOTYPE_PLAYER_0_FACTION_ID)
			return n0 if n0 != "" else "Player 0"
		1:
			var n1: String = FactionDefinitionsScript.display_name(PROTOTYPE_PLAYER_1_FACTION_ID)
			return n1 if n1 != "" else "Player 1"
		_:
			return "Player %d" % pid


static func accent_color_for_player_id(player_id: int) -> Color:
	if CloudPlayerIdentityScript.has_registry():
		return CloudPlayerIdentityScript.accent_color_for_player_id(player_id)
	if player_id == 0:
		return Color(0.38, 0.56, 0.62, 1.0)
	if player_id == 1:
		return Color(0.58, 0.32, 0.36, 1.0)
	if player_id == 2:
		return Color(0.44, 0.50, 0.38, 1.0)
	if player_id == 3:
		return Color(0.52, 0.44, 0.58, 1.0)
	var seed: int = int(abs(player_id * 1103515245 + 12345)) % 100000
	var hue: float = float(seed % 360) / 360.0
	return Color.from_hsv(hue, 0.35, 0.55, 1.0)
