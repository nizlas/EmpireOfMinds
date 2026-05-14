# Headless: godot --headless --path game -s res://presentation/tests/test_prototype_forest_clusters.gd
# Authoritative acceptance for `PlainsForestScript.PROTOTYPE_FOREST_DECORATION_HEXES`:
# every entry must be Terrain.PLAINS on `HexMap.make_prototype_play_map()`, not (0,0), and connected-component
# sizes show deliberate fragmentation (many components, max size capped — no single 10+ hex decoration carpet).
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
	sizes.sort()
	var max_sz: int = int(sizes[sizes.size() - 1])
	# **5.1.16g.2 polish:** intentionally fragmented woods (no single decoration carpet); structural mix only.
	var n1: int = 0
	var n_small: int = 0
	var n_med: int = 0
	for s in sizes:
		var sz: int = int(s)
		if sz == 1:
			n1 += 1
		elif sz >= 2 and sz <= 3:
			n_small += 1
		elif sz >= 4 and sz <= 9:
			n_med += 1
	_check(max_sz <= 9, "largest forest patch stays ≤9 hexes (anti–mega-blob)")
	_check(sizes.size() >= 8, "many separable forest components")
	_check(n1 >= 2, "at least two single-hex groves")
	_check(n_small >= 2, "at least two 2–3 hex patches")
	_check(n_med >= 2, "at least two medium patches (4–9 hex)")
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
