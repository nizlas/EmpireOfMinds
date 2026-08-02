# Loads canonical map envelopes from res://content/maps into WorldMap. Domain-only.
# Spec: docs/MAP_CONTENT.md, docs/WORLD_COORDINATES.md
class_name MapContentLoader
extends RefCounted

const SCHEMA_VERSION_V1 := 1
const VALID_ORIGINS := ["reference", "authored", "generated"]
const DEFAULT_ELEVATION_BASE := 1
const DEFAULT_ELEVATION_STEP := 0.4
const DEFAULT_CLIFF_THRESHOLD := 1

const WorldMapScript = preload("res://domain/world/world_map.gd")
const MapIdentityScript = preload("res://domain/world/map_identity.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")


static func sha256_hex_lower(raw_bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(raw_bytes)
	return ctx.finish().hex_encode()


static func load_world_map_from_res_path(res_path: String):
	var result := try_load_world_map_from_res_path(res_path)
	if not result["ok"]:
		push_error(str(result["error"]))
		return null
	return result["world_map"]


static func try_load_world_map_from_res_path(res_path: String) -> Dictionary:
	if not FileAccess.file_exists(res_path):
		return {"ok": false, "error": "Map file not found: %s" % res_path, "world_map": null}
	var raw_bytes := FileAccess.get_file_as_bytes(res_path)
	var raw_text := raw_bytes.get_string_from_utf8()
	var content_hash := sha256_hex_lower(raw_bytes)

	var parsed: Variant = JSON.parse_string(raw_text)
	if parsed == null:
		return {"ok": false, "error": "Invalid JSON in map file: %s" % res_path, "world_map": null}
	if not parsed is Dictionary:
		return {"ok": false, "error": "Map file must contain a JSON object: %s" % res_path, "world_map": null}

	var envelope: Dictionary = parsed
	var envelope_err := _validate_envelope(envelope, res_path)
	if envelope_err != "":
		return {"ok": false, "error": envelope_err, "world_map": null}

	var logical_map: Dictionary = envelope["logical_map"]
	var logical_err := _validate_logical_map(logical_map, res_path)
	if logical_err != "":
		return {"ok": false, "error": logical_err, "world_map": null}

	var map_id := str(logical_map["id"])
	var identity := MapIdentityScript.new(map_id, SCHEMA_VERSION_V1, content_hash)

	var elevation_step := float(logical_map.get("elevation_step", DEFAULT_ELEVATION_STEP))
	var elevation_base := int(logical_map.get("elevation_base", DEFAULT_ELEVATION_BASE))
	if elevation_step <= 0.0:
		return {"ok": false, "error": "elevation_step must be > 0 in %s" % res_path, "world_map": null}

	var edge_rule: Dictionary = logical_map.get("edge_rule", {})
	var cliff_threshold := int(
		edge_rule.get("cliff_if_abs_delta_greater_than", DEFAULT_CLIFF_THRESHOLD)
	)

	var tiles_dict: Dictionary = {}
	for tile_entry in logical_map["tiles"]:
		if not tile_entry is Dictionary:
			return {"ok": false, "error": "Each tile must be an object in %s" % res_path, "world_map": null}
		if not tile_entry.has("q") or not tile_entry.has("r") or not tile_entry.has("elevation"):
			return {"ok": false, "error": "Tile missing q/r/elevation in %s" % res_path, "world_map": null}
		var q := int(tile_entry["q"])
		var r := int(tile_entry["r"])
		var elevation := int(tile_entry["elevation"])
		var coord := Vector2i(q, r)
		if tiles_dict.has(coord):
			return {
				"ok": false,
				"error": "Duplicate tile (%d,%d) in %s" % [q, r, res_path],
				"world_map": null,
			}
		tiles_dict[coord] = WorldMapScript.WorldTile.new(q, r, elevation)

	var override_result := _parse_edge_overrides(logical_map.get("edge_overrides", []), res_path)
	if not override_result["ok"]:
		return {"ok": false, "error": override_result["error"], "world_map": null}
	var overrides: Dictionary = override_result["overrides"]

	var edges_dict := _derive_edges(tiles_dict, cliff_threshold, overrides)
	var world_map := WorldMapScript.new(
		identity, elevation_step, elevation_base, cliff_threshold, tiles_dict, edges_dict
	)
	return {"ok": true, "error": "", "world_map": world_map}


static func load_reference_world_map():
	return load_world_map_from_res_path("res://content/maps/reference/handdrawn_test_map_full_01.json")


static func _validate_envelope(envelope: Dictionary, source: String) -> String:
	if not envelope.has("schema_version"):
		return "Missing schema_version in %s" % source
	if int(envelope["schema_version"]) != SCHEMA_VERSION_V1:
		return "Unsupported schema_version in %s" % source
	if not envelope.has("origin"):
		return "Missing origin in %s" % source
	var origin := str(envelope["origin"])
	if not VALID_ORIGINS.has(origin):
		return "Invalid origin %s in %s" % [origin, source]
	if not envelope.has("provenance"):
		return "Missing provenance in %s" % source
	if not envelope["provenance"] is String or str(envelope["provenance"]).strip_edges() == "":
		return "Invalid provenance in %s" % source
	if not envelope.has("logical_map") or not envelope["logical_map"] is Dictionary:
		return "Missing or invalid logical_map in %s" % source
	return ""


static func _validate_logical_map(logical_map: Dictionary, source: String) -> String:
	if not logical_map.has("id") or str(logical_map["id"]).strip_edges() == "":
		return "Missing logical_map.id in %s" % source
	if not logical_map.has("tiles") or not logical_map["tiles"] is Array:
		return "Missing logical_map.tiles array in %s" % source
	if logical_map["tiles"].is_empty():
		return "logical_map.tiles must not be empty in %s" % source
	if logical_map.has("edge_rule") and not logical_map["edge_rule"] is Dictionary:
		return "logical_map.edge_rule must be an object in %s" % source
	if logical_map.has("edge_overrides") and not (
		logical_map["edge_overrides"] is Array or logical_map["edge_overrides"] is Dictionary
	):
		return "logical_map.edge_overrides must be array or object in %s" % source
	return ""


static func _parse_tile_coord(raw: Variant, source: String) -> Dictionary:
	if raw is Dictionary:
		if not raw.has("q") or not raw.has("r"):
			return {"ok": false, "error": "Invalid tile coordinate object in %s" % source}
		return {"ok": true, "error": "", "coord": Vector2i(int(raw["q"]), int(raw["r"]))}
	if raw is Array and raw.size() == 2:
		return {"ok": true, "error": "", "coord": Vector2i(int(raw[0]), int(raw[1]))}
	return {"ok": false, "error": "Invalid tile coordinate in %s" % source}


static func _parse_edge_overrides(raw: Variant, source: String) -> Dictionary:
	var overrides: Dictionary = {}
	if raw == null:
		return {"ok": true, "error": "", "overrides": overrides}
	if raw is Dictionary:
		for key in raw.keys():
			var key_str := str(key)
			var parts := key_str.split(",")
			if parts.size() != 4:
				return {"ok": false, "error": "Invalid edge override key %s in %s" % [key_str, source], "overrides": {}}
			var a := Vector2i(int(parts[0]), int(parts[1]))
			var b := Vector2i(int(parts[2]), int(parts[3]))
			var transition_result := _normalize_transition(str(raw[key]), source)
			if not transition_result["ok"]:
				return {"ok": false, "error": transition_result["error"], "overrides": {}}
			overrides[WorldMapScript.normalized_edge_key(a, b)] = transition_result["transition"]
		return {"ok": true, "error": "", "overrides": overrides}
	if raw is Array:
		for entry in raw:
			if not entry is Dictionary:
				return {"ok": false, "error": "Invalid edge override entry in %s" % source, "overrides": {}}
			if not entry.has("edge") or not entry.has("transition"):
				return {"ok": false, "error": "Edge override missing edge/transition in %s" % source, "overrides": {}}
			var edge_raw = entry["edge"]
			if not edge_raw is Array or edge_raw.size() != 2:
				return {"ok": false, "error": "Invalid edge override edge pair in %s" % source, "overrides": {}}
			var a_result := _parse_tile_coord(edge_raw[0], source)
			if not a_result["ok"]:
				return {"ok": false, "error": a_result["error"], "overrides": {}}
			var b_result := _parse_tile_coord(edge_raw[1], source)
			if not b_result["ok"]:
				return {"ok": false, "error": b_result["error"], "overrides": {}}
			var transition_result := _normalize_transition(str(entry["transition"]), source)
			if not transition_result["ok"]:
				return {"ok": false, "error": transition_result["error"], "overrides": {}}
			var a: Vector2i = a_result["coord"]
			var b: Vector2i = b_result["coord"]
			overrides[WorldMapScript.normalized_edge_key(a, b)] = transition_result["transition"]
		return {"ok": true, "error": "", "overrides": overrides}
	return {"ok": false, "error": "Unsupported edge_overrides format in %s" % source, "overrides": {}}


static func _normalize_transition(raw: String, source: String) -> Dictionary:
	var value := raw.to_lower()
	if value == WorldMapScript.EDGE_SMOOTH or value == WorldMapScript.EDGE_CLIFF:
		return {"ok": true, "error": "", "transition": value}
	return {"ok": false, "error": "Unsupported edge transition %s in %s" % [raw, source], "transition": ""}


static func _derive_edges(
	tiles_dict: Dictionary,
	cliff_threshold: int,
	overrides: Dictionary
) -> Dictionary:
	var edges: Dictionary = {}
	for coord: Vector2i in tiles_dict.keys():
		var tile = tiles_dict[coord]
		for d in range(6):
			var offset: Vector2i = HexCoordScript.DIRECTIONS[d]
			var neighbor := Vector2i(coord.x + offset.x, coord.y + offset.y)
			if not tiles_dict.has(neighbor):
				continue
			var edge_key := WorldMapScript.normalized_edge_key(coord, neighbor)
			if edges.has(edge_key):
				continue
			var neighbor_tile = tiles_dict[neighbor]
			var transition := WorldMapScript.EDGE_SMOOTH
			if overrides.has(edge_key):
				transition = str(overrides[edge_key])
			elif abs(tile.elevation - neighbor_tile.elevation) > cliff_threshold:
				transition = WorldMapScript.EDGE_CLIFF
			var edge_tiles: Array = WorldMapScript.parse_edge_key(edge_key)
			edges[edge_key] = WorldMapScript.WorldEdge.new(edge_tiles[0], edge_tiles[1], transition)
	return edges
