# Headless: godot --headless --path game -s res://presentation/tests/test_prototype_forest_clusters.gd
# Authoritative acceptance for `PlainsForestScript.PROTOTYPE_FOREST_DECORATION_HEXES`:
# every entry must be Terrain.PLAINS on `HexMap.make_prototype_play_map()`, not (0,0), and connected-component
# sizes must include the prototype/visual-review mix (isolated singles, small patches, medium, large).
extends SceneTree
const HexMapScript = preload("res://domain/hex_map.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")
const PlainsForestScript = preload("res://presentation/plains_forest_decoration.gd")

var _total = 0
var _any_fail = false


func _forest_component_sizes(hex_set: Dictionary) -> Array:
	var sizes: Array = []
	var unseen: Dictionary = hex_set.duplicate()
	while unseen.size() > 0:
		var seed: Vector2i = unseen.keys()[0]
		var stack: Array[Vector2i] = [seed]
		var comp: Dictionary = {}
		while stack.size() > 0:
			var v: Vector2i = stack.pop_back()
			if comp.has(v):
				continue
			if not unseen.has(v):
				continue
			comp[v] = true
			var d: int = 0
			while d < 6:
				var o: Vector2i = HexCoordScript.DIRECTIONS[d]
				var w: Vector2i = Vector2i(v.x + o.x, v.y + o.y)
				if hex_set.has(w) and not comp.has(w):
					stack.append(w)
				d += 1
		for k in comp:
			unseen.erase(k)
		sizes.append(comp.size())
	sizes.sort()
	return sizes


func _init() -> void:
	var pmap = HexMapScript.make_prototype_play_map()
	var raw: Array[Vector2i] = PlainsForestScript.prototype_forest_decoration_hexes()
	_check(raw.size() >= 10, "non-empty prototype forest list")
	var as_set: Dictionary = PlainsForestScript.prototype_forest_cluster_set()
	_check(as_set.size() == raw.size(), "set size matches list (no duplicate coords)")
	for v in raw:
		_check(v != Vector2i.ZERO, "no forest on start hex (0,0)")
		var hc = HexCoordScript.new(v.x, v.y)
		_check(pmap.has(hc), "forest hex exists on prototype map")
		_check(
			int(pmap.terrain_at(hc)) == HexMapScript.Terrain.PLAINS,
			"forest hex %s must be PLAINS (if wrong terrain, change coord in plains_forest_decoration.gd, not terrain rules)" % v
		)
	var sizes: Array = _forest_component_sizes(as_set)
	# Typical shape after hand placement on R=7: one bulk region plus NW plateau + hill wedge; pure 1-hex
	# isolates are sparse without merging into pairs/patches.
	var n1: int = 0
	var n_small: int = 0
	var n_med: int = 0
	var n_large: int = 0
	for s in sizes:
		var sz: int = int(s)
		if sz == 1:
			n1 += 1
		elif sz >= 2 and sz <= 3:
			n_small += 1
		elif sz >= 5 and sz <= 9:
			n_med += 1
		elif sz >= 10:
			n_large += 1
	_check(n1 >= 1, "at least one isolated single-hex forest component")
	_check(n_small >= 1, "at least one 2–3 hex patch")
	_check(n_med >= 2, "at least two 5–9 hex clusters (includes NW plateau + hill mass bands)")
	_check(n_large >= 1, "at least one 10+ hex region")
	if _any_fail:
		call_deferred("quit", 1)
	else:
		print("PASS %d/%d component_sizes=%s" % [_total, _total, str(sizes)])
		call_deferred("quit", 0)


func _check(cond: bool, message: String) -> void:
	_total += 1
	if cond:
		return
	_any_fail = true
	var line = "FAIL: %s" % message
	print(line)
	push_error(line)
