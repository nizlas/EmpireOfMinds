# Headless: godot --headless --path game -s res://domain/tests/test_complete_progress.gd
extends SceneTree

const CompleteProgressScript = preload("res://domain/actions/complete_progress.gd")
const ProgressStateScript = preload("res://domain/progress_state.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	var m = CompleteProgressScript.make(7, "foraging_systems")
	var mks = m.keys()
	_check(mks.size() == 4, "make key count")
	_check(m.has("schema_version") and m.has("action_type") and m.has("actor_id") and m.has("progress_id"), "make keys")
	_check(m["schema_version"] == CompleteProgressScript.SCHEMA_VERSION, "make schema")
	_check(m["action_type"] == CompleteProgressScript.ACTION_TYPE, "make type")
	_check(m["actor_id"] == 7 and m["progress_id"] == "foraging_systems", "make pass through")

	var ps0 = ProgressStateScript.new({})
	_check(
		not CompleteProgressScript.validate(null, m)["ok"]
		and CompleteProgressScript.validate(null, m)["reason"] == "progress_state_null",
		"null progress_state"
	)
	_check(
		not CompleteProgressScript.validate(ps0, null)["ok"]
		and CompleteProgressScript.validate(ps0, null)["reason"] == "wrong_action_type",
		"null action"
	)
	var r42 = CompleteProgressScript.validate(ps0, 42)
	_check(not r42["ok"] and r42["reason"] == "wrong_action_type", "not dict")
	var miss_type: Dictionary = {"schema_version": 1, "actor_id": 0, "progress_id": "x"}
	_check(
		not CompleteProgressScript.validate(ps0, miss_type)["ok"]
		and CompleteProgressScript.validate(ps0, miss_type)["reason"] == "wrong_action_type",
		"missing action_type"
	)
	var bad_type = m.duplicate(true)
	bad_type["action_type"] = "other"
	_check(
		not CompleteProgressScript.validate(ps0, bad_type)["ok"]
		and CompleteProgressScript.validate(ps0, bad_type)["reason"] == "wrong_action_type",
		"wrong action_type"
	)
	var miss_ver = CompleteProgressScript.make(0, "foraging_systems")
	miss_ver.erase("schema_version")
	_check(
		not CompleteProgressScript.validate(ps0, miss_ver)["ok"]
		and CompleteProgressScript.validate(ps0, miss_ver)["reason"] == "unsupported_schema_version",
		"missing schema_version"
	)
	var bad_ver = CompleteProgressScript.make(0, "foraging_systems")
	bad_ver["schema_version"] = 999
	_check(
		not CompleteProgressScript.validate(ps0, bad_ver)["ok"]
		and CompleteProgressScript.validate(ps0, bad_ver)["reason"] == "unsupported_schema_version",
		"bad schema_version"
	)
	var miss_actor = CompleteProgressScript.make(0, "foraging_systems")
	miss_actor.erase("actor_id")
	_check(
		not CompleteProgressScript.validate(ps0, miss_actor)["ok"]
		and CompleteProgressScript.validate(ps0, miss_actor)["reason"] == "malformed_action",
		"missing actor_id"
	)
	var bad_actor = CompleteProgressScript.make(0, "foraging_systems")
	bad_actor["actor_id"] = "nope"
	_check(
		not CompleteProgressScript.validate(ps0, bad_actor)["ok"]
		and CompleteProgressScript.validate(ps0, bad_actor)["reason"] == "malformed_action",
		"non-int actor_id"
	)
	var miss_pid = CompleteProgressScript.make(0, "foraging_systems")
	miss_pid.erase("progress_id")
	_check(
		not CompleteProgressScript.validate(ps0, miss_pid)["ok"]
		and CompleteProgressScript.validate(ps0, miss_pid)["reason"] == "malformed_action",
		"missing progress_id"
	)
	var bad_pid = CompleteProgressScript.make(0, "foraging_systems")
	bad_pid["progress_id"] = 99
	_check(
		not CompleteProgressScript.validate(ps0, bad_pid)["ok"]
		and CompleteProgressScript.validate(ps0, bad_pid)["reason"] == "malformed_action",
		"non-string progress_id"
	)
	var empty_pid = CompleteProgressScript.make(0, "")
	_check(
		not CompleteProgressScript.validate(ps0, empty_pid)["ok"]
		and CompleteProgressScript.validate(ps0, empty_pid)["reason"] == "malformed_action",
		"empty progress_id"
	)
	_check(
		not ps0.has_completed_progress(0, "foraging_systems"),
		"empty state not completed"
	)
	var unk = CompleteProgressScript.make(0, "nope")
	var ru = CompleteProgressScript.validate(ps0, unk)
	_check(not ru["ok"] and ru["reason"] == "unknown_progress_id", "unknown progress_id")
	var ps_done = ps0.with_progress_id_completed(0, "foraging_systems")
	var again = CompleteProgressScript.validate(ps_done, CompleteProgressScript.make(0, "foraging_systems"))
	_check(not again["ok"] and again["reason"] == "progress_already_completed", "already completed")

	var ok1 = CompleteProgressScript.validate(ps0, CompleteProgressScript.make(0, "foraging_systems"))
	_check(ok1["ok"] and str(ok1["reason"]) == "", "accept empty state")
	var def = ProgressStateScript.with_default_unlocks_for_players([0, 1])
	var ok2 = CompleteProgressScript.validate(def, CompleteProgressScript.make(0, "foraging_systems"))
	_check(ok2["ok"], "accept default seeded")

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
