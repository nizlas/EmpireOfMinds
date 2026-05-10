# Headless: godot --headless --path game -s res://presentation/tests/test_discovery_popup.gd
extends SceneTree

const DiscoveryPopupScript = preload("res://presentation/discovery_popup.gd")
const CompleteProgressScript = preload("res://domain/actions/complete_progress.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	var h0 = DiscoveryPopupScript.compute_view_model(null)
	_check(not bool(h0.get("visible", true)), "null -> hidden")
	_check(typeof(h0.get("visible")) == TYPE_BOOL, "visible is bool")
	var h1 = DiscoveryPopupScript.compute_view_model(42)
	_check(not h1["visible"], "int -> hidden")
	var h2 = DiscoveryPopupScript.compute_view_model("complete_progress")
	_check(not h2["visible"], "String -> hidden")
	var h3 = DiscoveryPopupScript.compute_view_model([])
	_check(not h3["visible"], "Array -> hidden")
	var h4 = DiscoveryPopupScript.compute_view_model({})
	_check(not h4["visible"], "empty dict -> hidden")
	var move_e = {
		"index": 0,
		"action_type": "move_unit",
		"actor_id": 0,
	}
	_check(not DiscoveryPopupScript.compute_view_model(move_e)["visible"], "non-complete_progress -> hidden")
	var foraging = {
		"action_type": CompleteProgressScript.ACTION_TYPE,
		"actor_id": 0,
		"progress_id": "foraging_systems",
		"unlocked_targets": [
			{"target_type": "building", "target_id": "scout_camp"},
		],
	}
	_check(not DiscoveryPopupScript.compute_view_model(foraging)["visible"], "no train unlocks -> hidden")
	var cf_meta = {
		"action_type": CompleteProgressScript.ACTION_TYPE,
		"actor_id": 0,
		"progress_id": "controlled_fire",
		"unlocked_targets": [
			{"target_type": "building", "target_id": "hearth"},
			{"target_type": "action", "target_id": "camp_clearing"},
		],
	}
	_check(
		not DiscoveryPopupScript.compute_view_model(cf_meta)["visible"],
		"controlled_fire metadata-only (no train) -> hidden"
	)
	# Synthetic row: Discovery still keys off city_project train lines only (regression guard).
	var cf_train = {
		"action_type": CompleteProgressScript.ACTION_TYPE,
		"actor_id": 0,
		"progress_id": "controlled_fire",
		"unlocked_targets": [
			{"target_type": "city_project", "target_id": "produce_unit:warrior"},
			{"target_type": "building", "target_id": "hearth"},
		],
	}
	var v_cf = DiscoveryPopupScript.compute_view_model(cf_train)
	_check(v_cf["visible"], "controlled_fire + train row -> visible")
	_check(str(v_cf["title"]) == "Discovery completed", "title")
	_check(str(v_cf["heading"]) == "Controlled Fire", "heading")
	_check(
		str(v_cf["body"]).find("hearths hold heat") >= 0,
		"controlled_fire body contains curated phrase",
	)
	_check(str(v_cf["unlock_block"]).find("Train Warrior") >= 0, "unlock lists Train Warrior")
	_check(str(v_cf["unlock_block"]).find("Unlocked:") >= 0, "unlock heading")
	var st = {
		"action_type": CompleteProgressScript.ACTION_TYPE,
		"actor_id": 0,
		"progress_id": "stone_tools",
		"unlocked_targets": [
			{"target_type": "city_project", "target_id": "produce_unit:warrior"},
		],
	}
	var v_st = DiscoveryPopupScript.compute_view_model(st)
	_check(v_st["visible"], "stone_tools warrior -> visible")
	_check(str(v_st["heading"]) == "Stone Tools", "humanized fallback heading")
	_check(
		str(v_st["body"]).find("new knowledge") >= 0,
		"generic fallback body",
	)
	_check(str(v_st["unlock_block"]).find("Train Warrior") >= 0, "Train Warrior bullet")
	var bad_action = {
		"action_type": "complete_progress_typo",
		"progress_id": "controlled_fire",
		"unlocked_targets": [
			{"target_type": "city_project", "target_id": "produce_unit:settler"},
		],
	}
	_check(not DiscoveryPopupScript.compute_view_model(bad_action)["visible"], "wrong action_type string -> hidden")
	var tree_bonus = {
		"action_type": "science_bonus",
		"source": "engine",
		"result": "accepted",
		"actor_id": 0,
		"progress_id": "controlled_fire",
		"bonus_id": "lightning_scarred_tree",
		"delta": 4,
		"total": 4,
		"cost": 6,
	}
	var v_tree = DiscoveryPopupScript.compute_view_model(tree_bonus)
	_check(v_tree["visible"], "lightning tree bonus visible")
	_check(str(v_tree["title"]) == "Discovery", "tree bonus title")
	_check(str(v_tree["heading"]) == "Lightning-Scarred Tree", "tree bonus heading")
	var body_tree = str(v_tree["body"])
	_check(body_tree.find("tree split by lightning") >= 0, "tree bonus body phrase 1")
	_check(body_tree.find("flame can be carried") >= 0, "tree bonus body phrase 2")
	_check(str(v_tree["practical_line"]) == "Progress toward Controlled Fire +4", "practical line")
	_check(str(v_tree.get("unlock_block", "x")).is_empty(), "no unlock block")
	var wrong_bonus_id = tree_bonus.duplicate(true)
	wrong_bonus_id["bonus_id"] = "other"
	_check(not DiscoveryPopupScript.compute_view_model(wrong_bonus_id)["visible"], "wrong bonus_id hidden")
	var tree_rejected = tree_bonus.duplicate(true)
	tree_rejected["result"] = "rejected"
	_check(not DiscoveryPopupScript.compute_view_model(tree_rejected)["visible"], "non-accepted science_bonus hidden")
	var tree_delta = tree_bonus.duplicate(true)
	tree_delta["delta"] = 3
	_check(str(DiscoveryPopupScript.compute_view_model(tree_delta)["practical_line"]) == "Progress toward Controlled Fire +3", "practical uses delta")
	if _any_fail:
		call_deferred("quit", 1)
	else:
		print("PASS %d/%d" % [_total, _total])
		call_deferred("quit", 0)


func _check(cond: bool, message: String) -> void:
	_total = _total + 1
	if cond:
		return
	_any_fail = true
	var line = "FAIL: %s" % message
	print(line)
	push_error(line)
