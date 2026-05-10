# Headless: godot --headless --path game -s res://domain/tests/test_progress_definitions.gd
extends SceneTree

const ProgressDefinitionsScript = preload("res://domain/content/progress_definitions.gd")

var _total = 0
var _any_fail = false

## Column order for registry `ids()` — not alphabetic; availability helpers sort alphabetically instead.
const _EXPECTED_IDS: Array = [
	"foraging_systems",
	"stone_tools",
	"controlled_fire",
	"oral_surveying",
	"animal_tracking",
	"seasonal_calendars",
	"pottery_craft",
	"textile_work",
	"basic_mining",
	"timber_working",
	"agrarian_practice",
	"counting_marks",
	"mudbrick_construction",
	"simple_levers",
	"pastoral_herding",
	"river_irrigation",
	"bronze_alloying",
	"wheelwrighting",
	"glyphic_records",
]


func _dfs_cycle_from(
	sid: String,
	visiting: Dictionary,
	visited: Dictionary,
	progress_definitions
) -> bool:
	if visiting.has(sid):
		return true
	if visited.has(sid):
		return false
	visiting[sid] = true
	var req = progress_definitions.prerequisites(sid) as Array
	var ri = 0
	while ri < req.size():
		var p = str(req[ri])
		if _dfs_cycle_from(p, visiting, visited, progress_definitions):
			return true
		ri = ri + 1
	visiting.erase(sid)
	visited[sid] = true
	return false


func _has_prerequisite_cycle(progress_definitions) -> bool:
	var visited: Dictionary = {}
	var ids = progress_definitions.ids() as Array
	var ii = 0
	while ii < ids.size():
		var sid = str(ids[ii])
		if visited.has(sid):
			ii = ii + 1
			continue
		var visiting: Dictionary = {}
		if _dfs_cycle_from(sid, visiting, visited, progress_definitions):
			return true
		ii = ii + 1
	return false


func _init() -> void:
	_check(_EXPECTED_IDS.size() == 19, "expected 19 ancient ids")
	var ii = 0
	while ii < _EXPECTED_IDS.size():
		var eid = str(_EXPECTED_IDS[ii])
		_check(ProgressDefinitionsScript.has(eid), "has %s" % eid)
		_check(ProgressDefinitionsScript.is_science(eid), "is_science %s" % eid)
		var c = ProgressDefinitionsScript.cost(eid)
		_check(c > 0, "cost positive %s" % eid)
		var pr = ProgressDefinitionsScript.prerequisites(eid) as Array
		var pi = 0
		while pi < pr.size():
			var pre = str(pr[pi])
			_check(ProgressDefinitionsScript.has(pre), "prereq exists %s <- %s" % [eid, pre])
			_check(
				ProgressDefinitionsScript.is_science(pre),
				"prereq is science %s <- %s" % [eid, pre]
			)
			pi = pi + 1
		ii = ii + 1

	_check(not ProgressDefinitionsScript.has("rail_logistics"), "no rail_logistics")

	var ids0 = ProgressDefinitionsScript.ids() as Array
	_check(ids0.size() == 19, "ids size 19")
	var jj = 0
	while jj < 19:
		_check(str(ids0[jj]) == str(_EXPECTED_IDS[jj]), "ids registry order %d" % jj)
		jj = jj + 1
	ids0.append("bogus")
	var ids1 = ProgressDefinitionsScript.ids() as Array
	_check(ids1.size() == 19, "ids duplicate safe size")

	_check(ProgressDefinitionsScript.cost("controlled_fire") == 6, "controlled_fire cost 6")
	var at_pr = ProgressDefinitionsScript.prerequisites("animal_tracking") as Array
	_check(
		at_pr.size() == 2
		and str(at_pr[0]) == "foraging_systems"
		and str(at_pr[1]) == "oral_surveying",
		"animal_tracking prerequisites order"
	)
	var tw_pr = ProgressDefinitionsScript.prerequisites("textile_work") as Array
	_check(tw_pr.size() == 1 and str(tw_pr[0]) == "foraging_systems", "textile_work prereqs")

	_check(not _has_prerequisite_cycle(ProgressDefinitionsScript), "prerequisite graph acyclic")

	_check(not ProgressDefinitionsScript.is_science("nope"), "is_science unknown false")

	var d = ProgressDefinitionsScript.get_definition("foraging_systems") as Dictionary
	_check(d["id"] == "foraging_systems", "def id")
	_check(int(d.get("cost", 0)) == 6, "def cost in row")
	_check((d.get("prerequisites", []) as Array).is_empty(), "foraging prereqs empty in def")
	_check(d["display_name"] == "Foraging Systems", "def display_name")
	_check(d["category"] == "science", "def category")
	_check(d["era_bucket"] == "ancient_foundations", "def era_bucket")
	_check(d["role"] == "early_food_scouting_survival", "def role")
	_check(
		d["description"] == "Early food gathering, camps, and simple survival practices.",
		"def description"
	)
	var cu = d["concrete_unlocks"] as Array
	var se = d["systemic_effects"] as Array
	var fd = d["future_dependencies"] as Array
	_check(cu.size() == 2 and se.size() == 2 and fd.size() == 2, "def array sizes")
	_check((cu[0] as Dictionary)["target_type"] == "building", "cu0 type")
	_check((cu[0] as Dictionary)["target_id"] == "scout_camp", "cu0 id")
	_check((cu[1] as Dictionary)["target_type"] == "specialist", "cu1 type")
	_check((cu[1] as Dictionary)["target_id"] == "forager", "cu1 id")
	_check((se[0] as Dictionary)["target_id"] == "forest_food_bonus", "se0 id")
	_check((fd[0] as Dictionary)["target_id"] == "survival_knowledge", "fd0 id")

	_check(ProgressDefinitionsScript.get_definition("nope") == null, "unknown null")

	var m0 = ProgressDefinitionsScript.get_definition("foraging_systems") as Dictionary
	m0["display_name"] = "X"
	var m1 = ProgressDefinitionsScript.get_definition("foraging_systems") as Dictionary
	_check(m1["display_name"] == "Foraging Systems", "get_definition deep copy")

	_check(ProgressDefinitionsScript.category("foraging_systems") == "science", "category ok")
	_check(ProgressDefinitionsScript.era_bucket("foraging_systems") == "ancient_foundations", "era ok")
	_check(ProgressDefinitionsScript.category("nope") == "", "category unknown")
	_check(ProgressDefinitionsScript.era_bucket("nope") == "", "era unknown")

	var cu_f = ProgressDefinitionsScript.concrete_unlocks("foraging_systems") as Array
	_check(cu_f.size() == 2, "concrete_unlocks size")
	_check((cu_f[0] as Dictionary)["target_type"] == "building", "concrete_unlocks sample type")
	_check((cu_f[0] as Dictionary)["target_id"] == "scout_camp", "concrete_unlocks sample id")
	var se_f = ProgressDefinitionsScript.systemic_effects("foraging_systems") as Array
	_check(se_f.size() == 2, "systemic_effects size")
	_check((se_f[1] as Dictionary)["target_id"] == "outside_borders_healing", "systemic sample id")
	var fd_f = ProgressDefinitionsScript.future_dependencies("foraging_systems") as Array
	_check(fd_f.size() == 2, "future_dependencies size")
	_check((fd_f[1] as Dictionary)["target_id"] == "woodland_logistics", "future sample id")

	_check((ProgressDefinitionsScript.concrete_unlocks("nope") as Array).is_empty(), "concrete nope")
	_check((ProgressDefinitionsScript.systemic_effects("nope") as Array).is_empty(), "systemic nope")
	_check((ProgressDefinitionsScript.future_dependencies("nope") as Array).is_empty(), "future nope")

	var cu_mut = ProgressDefinitionsScript.concrete_unlocks("foraging_systems") as Array
	cu_mut.append({"target_type": "x", "target_id": "y"})
	var cu_mut0 = cu_mut[0] as Dictionary
	cu_mut0["target_id"] = "corrupted"
	var cu_after = ProgressDefinitionsScript.concrete_unlocks("foraging_systems") as Array
	_check(cu_after.size() == 2, "concrete_unlocks mutate size restored")
	_check((cu_after[0] as Dictionary)["target_id"] == "scout_camp", "concrete_unlocks inner intact")

	var se_mut = ProgressDefinitionsScript.systemic_effects("foraging_systems") as Array
	se_mut.append({"target_type": "m", "target_id": "bogus_mod"})
	var se_mut0 = se_mut[0] as Dictionary
	se_mut0["target_id"] = "corrupted_mod"
	var se_after = ProgressDefinitionsScript.systemic_effects("foraging_systems") as Array
	_check(se_after.size() == 2, "systemic_mut size restored")
	_check((se_after[0] as Dictionary)["target_id"] == "forest_food_bonus", "systemic inner intact")

	var fd_mut = ProgressDefinitionsScript.future_dependencies("foraging_systems") as Array
	fd_mut.append({"target_type": "science", "target_id": "bogus_sci"})
	var fd_mut0 = fd_mut[0] as Dictionary
	fd_mut0["target_id"] = "corrupted_sci"
	var fd_after = ProgressDefinitionsScript.future_dependencies("foraging_systems") as Array
	_check(fd_after.size() == 2, "future_mut size restored")
	_check((fd_after[0] as Dictionary)["target_id"] == "survival_knowledge", "future inner intact")

	var cu_cf = ProgressDefinitionsScript.concrete_unlocks("controlled_fire") as Array
	_check(cu_cf.size() == 3, "controlled_fire concrete_unlocks size")
	_check((cu_cf[0] as Dictionary)["target_type"] == "building", "cf cu0 type")
	_check((cu_cf[0] as Dictionary)["target_id"] == "hearth", "cf cu0 id")
	_check((cu_cf[1] as Dictionary)["target_type"] == "action", "cf cu1 type")
	_check((cu_cf[1] as Dictionary)["target_id"] == "camp_clearing", "cf cu1 id")
	_check((cu_cf[2] as Dictionary)["target_type"] == "modifier", "cf cu2 type")
	_check((cu_cf[2] as Dictionary)["target_id"] == "controlled_fire_practice", "cf cu2 id")
	var se_cf = ProgressDefinitionsScript.systemic_effects("controlled_fire") as Array
	_check(se_cf.size() == 2, "controlled_fire systemic size")
	_check((se_cf[0] as Dictionary)["target_id"] == "cold_terrain_growth_bonus", "cf se0")
	_check((se_cf[1] as Dictionary)["target_id"] == "small_health_bonus", "cf se1")

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
