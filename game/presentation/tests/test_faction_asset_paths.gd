# Headless: godot --headless --path game -s res://presentation/tests/test_faction_asset_paths.gd
extends SceneTree

const FactionAssetPathsScript = preload("res://presentation/faction_asset_paths.gd")

var _total: int = 0
var _any_fail: bool = false


func _init() -> void:
	_check(
		FactionAssetPathsScript.banner_path("debug_vasterviksjavlarna")
		== "res://assets/prototype/factions/banners/debug_vasterviksjavlarna.png",
		"path vastervik"
	)
	_check(
		FactionAssetPathsScript.banner_path("debug_malmofubikkarna")
		== "res://assets/prototype/factions/banners/debug_malmofubikkarna.png",
		"path malmo"
	)
	_check(
		FactionAssetPathsScript.banner_path("debug_pajasarna_fran_paris")
		== "res://assets/prototype/factions/banners/debug_pajasarna_fran_paris.png",
		"path paris"
	)
	_check(FactionAssetPathsScript.banner_path("nope") == "", "unknown path empty")
	_check(FactionAssetPathsScript.banner_path("") == "", "empty id")

	var m: Dictionary = FactionAssetPathsScript.banner_paths_by_id()
	_check(m.size() == 3, "by_id size 3")
	_check(m.has("debug_vasterviksjavlarna"), "has vastervik")
	_check(m.has("debug_malmofubikkarna"), "has malmo")
	_check(m.has("debug_pajasarna_fran_paris"), "has paris")
	_check(
		String(m["debug_vasterviksjavlarna"])
		== "res://assets/prototype/factions/banners/debug_vasterviksjavlarna.png",
		"map vastervik"
	)
	_check(
		String(m["debug_malmofubikkarna"])
		== "res://assets/prototype/factions/banners/debug_malmofubikkarna.png",
		"map malmo"
	)
	_check(
		String(m["debug_pajasarna_fran_paris"])
		== "res://assets/prototype/factions/banners/debug_pajasarna_fran_paris.png",
		"map paris"
	)

	m["bogus"] = "res://bogus.png"
	var m2: Dictionary = FactionAssetPathsScript.banner_paths_by_id()
	_check(m2.size() == 3, "by_id fresh not mutated size")
	_check(not m2.has("bogus"), "by_id fresh no bogus key")

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
