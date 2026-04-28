# Derives whether an actor already accepted a MoveUnit since the most recent EndTurn in the log.
# Newest-first scan: EndTurn seen first => false; matching MoveUnit first => true.
# See docs/AI_LAYER.md
class_name RuleBasedAIPolicy
extends RefCounted

const MoveUnitScript = preload("res://domain/actions/move_unit.gd")
const EndTurnScript = preload("res://domain/actions/end_turn.gd")

static func has_actor_moved_this_turn(action_log, actor_id: int) -> bool:
	if action_log == null:
		return false
	var i = action_log.size() - 1
	while i >= 0:
		var e = action_log.get_entry(i)
		var t = e.get("action_type", "")
		if t == EndTurnScript.ACTION_TYPE:
			return false
		if t == MoveUnitScript.ACTION_TYPE and int(e.get("actor_id", -1)) == actor_id:
			return true
		i = i - 1
	return false
