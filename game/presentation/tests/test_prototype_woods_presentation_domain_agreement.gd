# Headless: godot --headless --path game -s res://presentation/tests/test_prototype_woods_presentation_domain_agreement.gd
# Representative cells: **PlainsForestScript** prototype overlay agrees with **HexMap.has_woods** on the prototype play map.
extends SceneTree

const HexMapScript = preload("res://domain/hex_map.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const PlainsForestScript = preload("res://presentation/plains_forest_decoration.gd")
const PrototypeTerrainFeaturesScript = preload("res://domain/prototype_terrain_features.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	var pm = HexMapScript.make_prototype_play_map()
	var i = 0
	var lst: Array = PrototypeTerrainFeaturesScript.PROTOTYPE_WOODS_HEXES
	while i < lst.size():
		if i >= 8:
			break
		var v: Vector2i = lst[i]
		var q: int = v.x
		var r: int = v.y
		var hc = HexCoordScript.new(q, r)
		var dom = pm.has_woods(hc)
		var pres = PlainsForestScript.is_prototype_foreground_forest_hex(q, r)
		_check(
			dom == pres,
			"woods agreement at (%d,%d)" % [q, r]
		)
		i += 1
	var neg = HexCoordScript.new(0, 0)
	_check(
		not pm.has_woods(neg) and not PlainsForestScript.is_prototype_foreground_forest_hex(0, 0),
		"start hex has no woods in domain or presentation"
	)
	if _any_fail:
		call_deferred("quit", 1)
	else:
		print("PASS %d/%d" % [_total, _total])
		call_deferred("quit", 0)


func _check(cond: bool, message: String) -> void:
	_total += 1
	if cond:
		return
	_any_fail = true
	var line = "FAIL: %s" % message
	print(line)
	push_error(line)
