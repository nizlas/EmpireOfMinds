# Engine science accumulation: routes per-turn yield to explicit current_research_id or deterministic auto-target.
# Phase 5.1.10 — science_bonus when lightning-tree observation bonus is granted (always toward controlled_fire).
# Phase 5.1.12c — multi-science routing via ScienceAvailability; lightning bonus unchanged.
# See docs/PROGRESSION_MODEL.md
class_name ScienceTick
extends RefCounted

const SCHEMA_VERSION: int = 1
## Lightning-tree observation bonus always applies to this id (independent of current research target).
const LIGHTNING_BONUS_PROGRESS_ID: String = "controlled_fire"
const PER_CITY_YIELD: int = 1
const OBSERVATION_BONUS: int = 4
const BONUS_ID_LIGHTNING_SCARRED_TREE: String = "lightning_scarred_tree"

const ProgressDefinitionsScript = preload("res://domain/content/progress_definitions.gd")
const ProgressUnlockResolverScript = preload("res://domain/progress_unlock_resolver.gd")
const ScienceAvailabilityScript = preload("res://domain/science_availability.gd")
const MoveUnitScript = preload("res://domain/actions/move_unit.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")


static func _resolve_tick_target(progress_state, owner_id: int) -> String:
	if progress_state == null:
		return ""
	var cur = progress_state.current_research_for(owner_id)
	if cur != "" and ScienceAvailabilityScript.is_available(progress_state, owner_id, cur):
		return cur
	var avail = ScienceAvailabilityScript.available_for(progress_state, owner_id)
	if avail.is_empty():
		return ""
	return str(avail[0])


static func apply_for_player(progress_state, scenario, owner_id: int) -> Dictionary:
	if progress_state == null or scenario == null:
		return {"progress_state": progress_state, "events": []}
	var target_id = _resolve_tick_target(progress_state, owner_id)
	if target_id == "":
		var no_ev: Dictionary = {}
		no_ev["schema_version"] = SCHEMA_VERSION
		no_ev["action_type"] = "science_no_target"
		no_ev["source"] = "engine"
		no_ev["result"] = "accepted"
		no_ev["actor_id"] = owner_id
		return {"progress_state": progress_state, "events": [no_ev]}
	var cities = scenario.cities()
	var n = 0
	var i = 0
	while i < cities.size():
		if int(cities[i].owner_id) == owner_id:
			n = n + 1
		i = i + 1
	var delta = PER_CITY_YIELD * n
	if delta == 0:
		return {"progress_state": progress_state, "events": []}
	return _add_progress_and_maybe_complete(progress_state, owner_id, delta, target_id)


static func add_observation_bonus_if_eligible(
	progress_state,
	scenario,
	owner_id: int,
	action_log
) -> Dictionary:
	if progress_state == null or scenario == null or action_log == null:
		return {"progress_state": progress_state, "events": []}
	if progress_state.has_completed_progress(owner_id, LIGHTNING_BONUS_PROGRESS_ID):
		return {"progress_state": progress_state, "events": []}
	var tree_hex = scenario.lightning_tree_hex
	if tree_hex == null:
		return {"progress_state": progress_state, "events": []}
	if progress_state.has_observation_bonus_granted(owner_id, LIGHTNING_BONUS_PROGRESS_ID):
		return {"progress_state": progress_state, "events": []}
	if not action_log.has_method("size") or not action_log.has_method("get_entry"):
		return {"progress_state": progress_state, "events": []}
	var sz = action_log.size()
	if sz <= 0:
		return {"progress_state": progress_state, "events": []}
	var entry = action_log.get_entry(sz - 1)
	if typeof(entry) != TYPE_DICTIONARY:
		return {"progress_state": progress_state, "events": []}
	var d = entry as Dictionary
	if str(d.get("result", "")) != "accepted":
		return {"progress_state": progress_state, "events": []}
	if str(d.get("action_type", "")) != MoveUnitScript.ACTION_TYPE:
		return {"progress_state": progress_state, "events": []}
	if not d.has("actor_id") or typeof(d["actor_id"]) != TYPE_INT:
		return {"progress_state": progress_state, "events": []}
	if int(d["actor_id"]) != owner_id:
		return {"progress_state": progress_state, "events": []}
	if not d.has("to") or typeof(d["to"]) != TYPE_ARRAY:
		return {"progress_state": progress_state, "events": []}
	var to_a = d["to"] as Array
	if to_a.size() != 2:
		return {"progress_state": progress_state, "events": []}
	if typeof(to_a[0]) != TYPE_INT or typeof(to_a[1]) != TYPE_INT:
		return {"progress_state": progress_state, "events": []}
	var to_c = HexCoordScript.new(int(to_a[0]), int(to_a[1]))
	if not _hex_on_or_adjacent(to_c, tree_hex):
		return {"progress_state": progress_state, "events": []}
	var ps2 = progress_state.with_observation_bonus_granted(owner_id, LIGHTNING_BONUS_PROGRESS_ID)
	var inner = _add_progress_and_maybe_complete(ps2, owner_id, OBSERVATION_BONUS, LIGHTNING_BONUS_PROGRESS_ID)
	var inner_ev = inner["events"] as Array
	if inner_ev.is_empty():
		return inner
	var ev0 = inner_ev[0] as Dictionary
	var target_cost = ProgressDefinitionsScript.cost(LIGHTNING_BONUS_PROGRESS_ID)
	var bonus_ev: Dictionary = {}
	bonus_ev["schema_version"] = SCHEMA_VERSION
	bonus_ev["action_type"] = "science_bonus"
	bonus_ev["source"] = "engine"
	bonus_ev["result"] = "accepted"
	bonus_ev["actor_id"] = owner_id
	bonus_ev["progress_id"] = LIGHTNING_BONUS_PROGRESS_ID
	bonus_ev["bonus_id"] = BONUS_ID_LIGHTNING_SCARRED_TREE
	bonus_ev["delta"] = int(ev0.get("delta", OBSERVATION_BONUS))
	bonus_ev["total"] = int(ev0.get("total", 0))
	bonus_ev["cost"] = target_cost
	var out_ev: Array = [bonus_ev]
	var oi = 0
	while oi < inner_ev.size():
		out_ev.append(inner_ev[oi])
		oi = oi + 1
	return {"progress_state": inner["progress_state"], "events": out_ev}


static func _hex_on_or_adjacent(cell, tree_hex) -> bool:
	if cell.equals(tree_hex):
		return true
	var neigh = tree_hex.neighbors()
	var ni = 0
	while ni < neigh.size():
		if cell.equals(neigh[ni]):
			return true
		ni = ni + 1
	return false


static func _add_progress_and_maybe_complete(ps, owner_id: int, delta: int, target_progress_id: String) -> Dictionary:
	if delta == 0:
		return {"progress_state": ps, "events": []}
	if ps.has_completed_progress(owner_id, target_progress_id):
		return {"progress_state": ps, "events": []}
	var target_cost = ProgressDefinitionsScript.cost(target_progress_id)
	var cur = ps.science_progress_for(owner_id, target_progress_id)
	var new_total = cur + delta
	var next_ps = ps.with_science_progress_added(owner_id, target_progress_id, delta)
	var evp: Dictionary = {}
	evp["schema_version"] = SCHEMA_VERSION
	evp["action_type"] = "science_progress"
	evp["source"] = "engine"
	evp["result"] = "accepted"
	evp["actor_id"] = owner_id
	evp["progress_id"] = target_progress_id
	evp["delta"] = delta
	evp["total"] = new_total
	evp["cost"] = target_cost
	var events: Array = [evp]
	if new_total < target_cost:
		return {"progress_state": next_ps, "events": events}
	var res = ProgressUnlockResolverScript.complete_progress(next_ps, owner_id, target_progress_id)
	if not bool(res["ok"]):
		return {"progress_state": next_ps, "events": events}
	var final_ps = res["progress_state"]
	var unlocked = res["unlocked_targets"] as Array
	var evc: Dictionary = {}
	evc["schema_version"] = SCHEMA_VERSION
	evc["action_type"] = "science_completed"
	evc["source"] = "engine"
	evc["result"] = "accepted"
	evc["actor_id"] = owner_id
	evc["progress_id"] = target_progress_id
	evc["unlocked_targets"] = unlocked
	evc["total"] = new_total
	evc["cost"] = target_cost
	events.append(evc)
	return {"progress_state": final_ps, "events": events}
