# Phase **5.2.6a** — prototype hotseat seat labels (**player id** → **`FactionDefinitions`** debug row). Presentation-only; **ids** stay **int** in domain.
class_name PlaytestPlayerDisplay
extends RefCounted

const FactionDefinitionsScript = preload("res://domain/content/faction_definitions.gd")

const PROTOTYPE_PLAYER_0_FACTION_ID: String = "debug_vasterviksjavlarna"
const PROTOTYPE_PLAYER_1_FACTION_ID: String = "debug_malmofubikkarna"


static func display_name_for_player_id(player_id: int) -> String:
	var pid: int = int(player_id)
	match pid:
		0:
			var n0: String = FactionDefinitionsScript.display_name(PROTOTYPE_PLAYER_0_FACTION_ID)
			return n0 if n0 != "" else "Player 0"
		1:
			var n1: String = FactionDefinitionsScript.display_name(PROTOTYPE_PLAYER_1_FACTION_ID)
			return n1 if n1 != "" else "Player 1"
		_:
			return "Player %d" % pid
