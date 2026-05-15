# Headless: godot --headless --path game -s res://domain/tests/test_city.gd
extends SceneTree
const CityScript = preload("res://domain/city.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")

var _total = 0
var _any_fail = false

func _init() -> void:
	var c = CityScript.new(10, 0, HexCoordScript.new(1, -2))
	_check(c.id == 10 and c.owner_id == 0, "construction sets id and owner")
	_check(c.city_name == "", "default city_name empty")
	_check(not c.is_capital, "default not capital")
	_check(c.building_ids.is_empty(), "default no buildings")
	_check(c.population == 1, "default population is 1")
	_check(
		c.position != null and c.position.q == 1 and c.position.r == -2,
		"construction sets position"
	)
	_check(c.owned_tiles.size() == 1 and c.owned_tiles[0].equals(c.position), "default owned_tiles is center only")
	_check(c.manual_worked_tiles.is_empty(), "default manual_worked_tiles empty")
	_check(c.food_stored == 0, "default food_stored is 0")
	_check(c.worked_tiles_mode == CityScript.WORKED_TILES_MODE_AUTO, "default worked_tiles_mode auto")
	var c_neg = CityScript.new(20, 0, HexCoordScript.new(0, 0), null, "", false, null, null, 1, [], -5)
	_check(c_neg.food_stored == 0, "food_stored clamps negative to 0")
	var custom_tiles: Array = [HexCoordScript.new(1, 1), HexCoordScript.new(1, 0)]
	var c_custom = CityScript.new(11, 0, HexCoordScript.new(0, 0), null, "", false, null, custom_tiles)
	_check(c_custom.owned_tiles.size() == 3, "custom owned_tiles adds neighbors with center first")
	_check(c_custom.owned_tiles[0].equals(HexCoordScript.new(0, 0)), "owned center first")
	_check(c_custom.owned_tiles[1].equals(HexCoordScript.new(1, 1)), "owned extra 1")
	_check(c_custom.owned_tiles[2].equals(HexCoordScript.new(1, 0)), "owned extra 2")
	custom_tiles.pop_back()
	_check(c_custom.owned_tiles.size() == 3, "owned_tiles is defensive copy of input array")
	var dupe_tiles: Array = [HexCoordScript.new(0, 0), HexCoordScript.new(1, 0)]
	var c_dupe = CityScript.new(12, 0, HexCoordScript.new(0, 0), null, "", false, null, dupe_tiles)
	_check(c_dupe.owned_tiles.size() == 2, "duplicate axial coords deduped in owned_tiles")
	var c2 = CityScript.new(10, 1, HexCoordScript.new(0, 0))
	_check(c.equals(c2), "equals matches on id only")
	_check(c.equals_id(10), "equals_id true")
	_check(not c.equals_id(11), "equals_id false")
	var c3 = CityScript.new(11, 0, HexCoordScript.new(0, 0))
	_check(not c.equals(c3), "different id not equals")
	var own_m: Array = [HexCoordScript.new(0, 0), HexCoordScript.new(1, 1)]
	var man_dup: Array = [[1, 1], HexCoordScript.new(1, 1), [0, 0]]
	var c_man = CityScript.new(
		13,
		0,
		HexCoordScript.new(0, 0),
		null,
		"",
		false,
		null,
		own_m,
		2,
		man_dup
	)
	_check(c_man.manual_worked_tiles.size() == 1, "manual dedupes and drops center")
	_check((c_man.manual_worked_tiles[0] as HexCoord).equals(HexCoordScript.new(1, 1)), "manual keeps owned non-center")
	var own_keep: Array = [HexCoordScript.new(0, 0), HexCoordScript.new(2, 2)]
	var c_pres = CityScript.new(
		14,
		0,
		HexCoordScript.new(0, 0),
		null,
		"",
		false,
		null,
		own_keep,
		1,
		[HexCoordScript.new(2, 2)],
		7
	)
	_check(c_pres.manual_worked_tiles.size() == 1, "manual preserves valid owned hex")
	_check(c_pres.food_stored == 7, "food_stored preserved when trailing arg set")
	var c_pres_f0 = CityScript.new(
		15,
		0,
		HexCoordScript.new(0, 0),
		null,
		"",
		false,
		null,
		own_keep,
		1,
		[HexCoordScript.new(2, 2)],
		0
	)
	_check(c_pres_f0.food_stored == 0, "explicit zero food_stored")
	var c_mode_m = CityScript.new(
		16,
		0,
		HexCoordScript.new(0, 0),
		null,
		"",
		false,
		null,
		own_keep,
		1,
		[HexCoordScript.new(2, 2)],
		0,
		CityScript.WORKED_TILES_MODE_MANUAL
	)
	_check(c_mode_m.worked_tiles_mode == CityScript.WORKED_TILES_MODE_MANUAL, "constructor accepts manual mode")
	# Immutability: no public mutators; fields are plain var but convention matches Unit.
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
