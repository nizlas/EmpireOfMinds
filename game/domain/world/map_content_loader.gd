# Loads canonical map envelopes from res://content/maps into WorldMap. Domain-only.
# Spec: docs/MAP_CONTENT.md, docs/WORLD_COORDINATES.md
class_name MapContentLoader
extends RefCounted

const SCHEMA_VERSION_V1 := 1
const VALID_ORIGINS := ["reference", "authored", "generated"]
const SUPPORTED_ORIENTATION := "pointy_top_custom_axes"
const EDGE_RULE_DEFAULT := "smooth"
const DEFAULT_ELEVATION_BASE := 1
const DEFAULT_ELEVATION_STEP := 0.4
const DEFAULT_CLIFF_THRESHOLD := 1

const WorldMapScript = preload("res://domain/world/world_map.gd")
const MapIdentityScript = preload("res://domain/world/map_identity.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")

const _CANONICAL_NEIGHBOR_DELTAS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(1, -1),
	Vector2i(0, -1),
	Vector2i(-1, 0),
	Vector2i(-1, 1),
	Vector2i(0, 1),
]


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
	var parsed_logical := _parse_logical_map(logical_map, res_path)
	if not parsed_logical["ok"]:
		return {"ok": false, "error": parsed_logical["error"], "world_map": null}

	var map_id: String = parsed_logical["map_id"]
	var identity := MapIdentityScript.new(map_id, SCHEMA_VERSION_V1, content_hash)
	var elevation_step: float = parsed_logical["elevation_step"]
	var elevation_base: int = parsed_logical["elevation_base"]
	var cliff_threshold: int = parsed_logical["cliff_threshold"]
	var tiles_dict: Dictionary = parsed_logical["tiles_dict"]
	var overrides: Dictionary = parsed_logical["overrides"]

	var edges_dict := _derive_edges(tiles_dict, cliff_threshold, overrides)
	var world_map := WorldMapScript.new(
		identity, elevation_step, elevation_base, cliff_threshold, tiles_dict, edges_dict
	)
	return {"ok": true, "error": "", "world_map": world_map}


static func load_reference_world_map():
	return load_world_map_from_res_path("res://content/maps/reference/handdrawn_test_map_full_01.json")


static func _require_json_int(value: Variant, field_path: String) -> Dictionary:
	if typeof(value) == TYPE_BOOL:
		return {"ok": false, "error": "%s must be an integer, got boolean" % field_path, "value": 0}
	if typeof(value) == TYPE_STRING:
		return {"ok": false, "error": "%s must be an integer, got string" % field_path, "value": 0}
	if typeof(value) == TYPE_INT:
		return {"ok": true, "error": "", "value": value}
	if typeof(value) == TYPE_FLOAT:
		if not is_finite(value):
			return {
				"ok": false,
				"error": "%s must be an integer, got non-finite number" % field_path,
				"value": 0,
			}
		var floored: float = floor(value)
		if value != floored:
			return {
				"ok": false,
				"error": "%s must be an integer, got fractional number" % field_path,
				"value": 0,
			}
		return {"ok": true, "error": "", "value": int(value)}
	return {"ok": false, "error": "%s must be an integer" % field_path, "value": 0}


static func _require_json_finite_number(value: Variant, field_path: String) -> Dictionary:
	if typeof(value) == TYPE_BOOL:
		return {"ok": false, "error": "%s must be a number, got boolean" % field_path, "value": 0.0}
	if typeof(value) == TYPE_STRING:
		return {"ok": false, "error": "%s must be a number, got string" % field_path, "value": 0.0}
	if typeof(value) == TYPE_INT:
		return {"ok": true, "error": "", "value": float(value)}
	if typeof(value) == TYPE_FLOAT:
		if not is_finite(value):
			return {"ok": false, "error": "%s must be a finite number" % field_path, "value": 0.0}
		return {"ok": true, "error": "", "value": value}
	return {"ok": false, "error": "%s must be a number" % field_path, "value": 0.0}


static func _require_json_string(value: Variant, field_path: String, allow_empty: bool = false) -> Dictionary:
	if typeof(value) != TYPE_STRING:
		return {"ok": false, "error": "%s must be a string" % field_path, "value": ""}
	if not allow_empty and value.strip_edges() == "":
		return {"ok": false, "error": "%s must be a non-empty string" % field_path, "value": ""}
	return {"ok": true, "error": "", "value": value}


static func _validate_envelope(envelope: Dictionary, source: String) -> String:
	if not envelope.has("schema_version"):
		return "Missing schema_version in %s" % source
	var schema_result := _require_json_int(envelope["schema_version"], "schema_version")
	if not schema_result["ok"]:
		return "%s in %s" % [schema_result["error"], source]
	if schema_result["value"] != SCHEMA_VERSION_V1:
		return "Unsupported schema_version %d in %s" % [schema_result["value"], source]

	if not envelope.has("origin"):
		return "Missing origin in %s" % source
	var origin_result := _require_json_string(envelope["origin"], "origin")
	if not origin_result["ok"]:
		return "%s in %s" % [origin_result["error"], source]
	if not VALID_ORIGINS.has(origin_result["value"]):
		return "Invalid origin %s in %s" % [origin_result["value"], source]

	if not envelope.has("provenance"):
		return "Missing provenance in %s" % source
	var provenance_result := _require_json_string(envelope["provenance"], "provenance")
	if not provenance_result["ok"]:
		return "%s in %s" % [provenance_result["error"], source]

	if not envelope.has("logical_map") or not envelope["logical_map"] is Dictionary:
		return "Missing or invalid logical_map in %s" % source
	return ""


static func _parse_logical_map(logical_map: Dictionary, source: String) -> Dictionary:
	if not logical_map.has("id"):
		return {"ok": false, "error": "Missing logical_map.id in %s" % source}
	var id_result := _require_json_string(logical_map["id"], "logical_map.id")
	if not id_result["ok"]:
		return {"ok": false, "error": "%s in %s" % [id_result["error"], source]}

	if not logical_map.has("orientation"):
		return {"ok": false, "error": "Missing logical_map.orientation in %s" % source}
	var orientation_result := _require_json_string(logical_map["orientation"], "logical_map.orientation")
	if not orientation_result["ok"]:
		return {"ok": false, "error": "%s in %s" % [orientation_result["error"], source]}
	if orientation_result["value"] != SUPPORTED_ORIENTATION:
		return {
			"ok": false,
			"error": "Unsupported logical_map.orientation %s in %s"
			% [orientation_result["value"], source],
		}

	if not logical_map.has("tiles") or not logical_map["tiles"] is Array:
		return {"ok": false, "error": "Missing logical_map.tiles array in %s" % source}
	if logical_map["tiles"].is_empty():
		return {"ok": false, "error": "logical_map.tiles must not be empty in %s" % source}

	var elevation_step := DEFAULT_ELEVATION_STEP
	if logical_map.has("elevation_step"):
		var step_result := _require_json_finite_number(
			logical_map["elevation_step"], "logical_map.elevation_step"
		)
		if not step_result["ok"]:
			return {"ok": false, "error": "%s in %s" % [step_result["error"], source]}
		elevation_step = step_result["value"]
	if elevation_step <= 0.0:
		return {"ok": false, "error": "logical_map.elevation_step must be > 0 in %s" % source}

	var elevation_base := DEFAULT_ELEVATION_BASE
	if logical_map.has("elevation_base"):
		var base_result := _require_json_int(logical_map["elevation_base"], "logical_map.elevation_base")
		if not base_result["ok"]:
			return {"ok": false, "error": "%s in %s" % [base_result["error"], source]}
		elevation_base = base_result["value"]

	if not logical_map.has("edge_rule") or not logical_map["edge_rule"] is Dictionary:
		return {"ok": false, "error": "Missing logical_map.edge_rule object in %s" % source}
	var edge_rule: Dictionary = logical_map["edge_rule"]
	if not edge_rule.has("default"):
		return {
			"ok": false,
			"error": "Missing logical_map.edge_rule.default in %s" % source,
		}
	var default_result := _require_json_string(edge_rule["default"], "logical_map.edge_rule.default")
	if not default_result["ok"]:
		return {"ok": false, "error": "%s in %s" % [default_result["error"], source]}
	if default_result["value"] != EDGE_RULE_DEFAULT:
		return {
			"ok": false,
			"error": "Unsupported logical_map.edge_rule.default %s in %s"
			% [default_result["value"], source],
		}
	if not edge_rule.has("cliff_if_abs_delta_greater_than"):
		return {
			"ok": false,
			"error": "Missing logical_map.edge_rule.cliff_if_abs_delta_greater_than in %s" % source,
		}
	var threshold_result := _require_json_int(
		edge_rule["cliff_if_abs_delta_greater_than"],
		"logical_map.edge_rule.cliff_if_abs_delta_greater_than",
	)
	if not threshold_result["ok"]:
		return {"ok": false, "error": "%s in %s" % [threshold_result["error"], source]}
	var cliff_threshold: int = threshold_result["value"]
	if cliff_threshold < 0:
		return {
			"ok": false,
			"error": "logical_map.edge_rule.cliff_if_abs_delta_greater_than must be >= 0 in %s" % source,
		}

	var tiles_dict: Dictionary = {}
	var tiles_array: Array = logical_map["tiles"]
	for tile_index in tiles_array.size():
		var tile_entry = tiles_array[tile_index]
		var tile_path := "logical_map.tiles[%d]" % tile_index
		if not tile_entry is Dictionary:
			return {"ok": false, "error": "%s must be an object in %s" % [tile_path, source]}
		if not tile_entry.has("q"):
			return {"ok": false, "error": "Missing %s.q in %s" % [tile_path, source]}
		if not tile_entry.has("r"):
			return {"ok": false, "error": "Missing %s.r in %s" % [tile_path, source]}
		if not tile_entry.has("elevation"):
			return {"ok": false, "error": "Missing %s.elevation in %s" % [tile_path, source]}
		var q_result := _require_json_int(tile_entry["q"], "%s.q" % tile_path)
		if not q_result["ok"]:
			return {"ok": false, "error": "%s in %s" % [q_result["error"], source]}
		var r_result := _require_json_int(tile_entry["r"], "%s.r" % tile_path)
		if not r_result["ok"]:
			return {"ok": false, "error": "%s in %s" % [r_result["error"], source]}
		var elevation_result := _require_json_int(tile_entry["elevation"], "%s.elevation" % tile_path)
		if not elevation_result["ok"]:
			return {"ok": false, "error": "%s in %s" % [elevation_result["error"], source]}
		var q: int = q_result["value"]
		var r: int = r_result["value"]
		var elevation: int = elevation_result["value"]
		var coord := Vector2i(q, r)
		if tiles_dict.has(coord):
			return {
				"ok": false,
				"error": "Duplicate tile (%d,%d) in %s" % [q, r, source],
			}
		tiles_dict[coord] = WorldMapScript.WorldTile.new(q, r, elevation)

	var overrides: Dictionary = {}
	if logical_map.has("edge_overrides"):
		var raw_overrides = logical_map["edge_overrides"]
		if raw_overrides == null:
			return {
				"ok": false,
				"error": "logical_map.edge_overrides must be an array, got null in %s" % source,
			}
		if not raw_overrides is Array:
			return {
				"ok": false,
				"error": "logical_map.edge_overrides must be an array in %s" % source,
			}
		var override_result := _parse_edge_overrides(raw_overrides, source, tiles_dict)
		if not override_result["ok"]:
			return {"ok": false, "error": override_result["error"]}
		overrides = override_result["overrides"]

	return {
		"ok": true,
		"error": "",
		"map_id": id_result["value"],
		"elevation_step": elevation_step,
		"elevation_base": elevation_base,
		"cliff_threshold": cliff_threshold,
		"tiles_dict": tiles_dict,
		"overrides": overrides,
	}


static func _parse_tile_coord(raw: Variant, field_path: String, source: String) -> Dictionary:
	if raw is Dictionary:
		if not raw.has("q"):
			return {"ok": false, "error": "Missing %s.q in %s" % [field_path, source]}
		if not raw.has("r"):
			return {"ok": false, "error": "Missing %s.r in %s" % [field_path, source]}
		var q_result := _require_json_int(raw["q"], "%s.q" % field_path)
		if not q_result["ok"]:
			return {"ok": false, "error": "%s in %s" % [q_result["error"], source]}
		var r_result := _require_json_int(raw["r"], "%s.r" % field_path)
		if not r_result["ok"]:
			return {"ok": false, "error": "%s in %s" % [r_result["error"], source]}
		return {"ok": true, "error": "", "coord": Vector2i(q_result["value"], r_result["value"])}
	if raw is Array and raw.size() == 2:
		var q_result := _require_json_int(raw[0], "%s[0]" % field_path)
		if not q_result["ok"]:
			return {"ok": false, "error": "%s in %s" % [q_result["error"], source]}
		var r_result := _require_json_int(raw[1], "%s[1]" % field_path)
		if not r_result["ok"]:
			return {"ok": false, "error": "%s in %s" % [r_result["error"], source]}
		return {"ok": true, "error": "", "coord": Vector2i(q_result["value"], r_result["value"])}
	return {"ok": false, "error": "Invalid tile coordinate at %s in %s" % [field_path, source]}


static func _are_adjacent(a: Vector2i, b: Vector2i) -> bool:
	var dq := b.x - a.x
	var dr := b.y - a.y
	for offset: Vector2i in _CANONICAL_NEIGHBOR_DELTAS:
		if offset.x == dq and offset.y == dr:
			return true
	return false


static func _parse_edge_overrides(
	raw: Variant,
	source: String,
	tiles_dict: Dictionary
) -> Dictionary:
	var overrides: Dictionary = {}
	if raw is Array:
		for entry_index in raw.size():
			var entry = raw[entry_index]
			var entry_path := "logical_map.edge_overrides[%d]" % entry_index
			if not entry is Dictionary:
				return {
					"ok": false,
					"error": "%s must be an object in %s" % [entry_path, source],
					"overrides": {},
				}
			if not entry.has("edge") or not entry.has("transition"):
				return {
					"ok": false,
					"error": "%s missing edge/transition in %s" % [entry_path, source],
					"overrides": {},
				}
			var edge_raw = entry["edge"]
			if not edge_raw is Array or edge_raw.size() != 2:
				return {
					"ok": false,
					"error": "%s.edge must be a pair of coordinates in %s" % [entry_path, source],
					"overrides": {},
				}
			var a_result := _parse_tile_coord(edge_raw[0], "%s.edge[0]" % entry_path, source)
			if not a_result["ok"]:
				return {"ok": false, "error": a_result["error"], "overrides": {}}
			var b_result := _parse_tile_coord(edge_raw[1], "%s.edge[1]" % entry_path, source)
			if not b_result["ok"]:
				return {"ok": false, "error": b_result["error"], "overrides": {}}
			var transition_result := _normalize_transition(
				entry["transition"], "%s.transition" % entry_path, source
			)
			if not transition_result["ok"]:
				return {"ok": false, "error": transition_result["error"], "overrides": {}}
			var a: Vector2i = a_result["coord"]
			var b: Vector2i = b_result["coord"]
			var store_result := _store_override(
				overrides,
				a,
				b,
				transition_result["transition"],
				entry_path,
				source,
				tiles_dict,
			)
			if not store_result["ok"]:
				return {"ok": false, "error": store_result["error"], "overrides": {}}
		return {"ok": true, "error": "", "overrides": overrides}
	return {"ok": false, "error": "logical_map.edge_overrides must be an array in %s" % source, "overrides": {}}


static func _store_override(
	overrides: Dictionary,
	a: Vector2i,
	b: Vector2i,
	transition: String,
	field_path: String,
	source: String,
	tiles_dict: Dictionary
) -> Dictionary:
	if a == b:
		return {
			"ok": false,
			"error": "%s endpoints must be distinct in %s" % [field_path, source],
		}
	if not tiles_dict.has(a):
		return {
			"ok": false,
			"error": "%s references missing tile (%d,%d) in %s" % [field_path, a.x, a.y, source],
		}
	if not tiles_dict.has(b):
		return {
			"ok": false,
			"error": "%s references missing tile (%d,%d) in %s" % [field_path, b.x, b.y, source],
		}
	if not _are_adjacent(a, b):
		return {
			"ok": false,
			"error": "%s references non-adjacent tiles (%d,%d)-(%d,%d) in %s"
			% [field_path, a.x, a.y, b.x, b.y, source],
		}
	var edge_key := WorldMapScript.normalized_edge_key(a, b)
	if overrides.has(edge_key):
		return {
			"ok": false,
			"error": "%s duplicates override for edge %s in %s" % [field_path, edge_key, source],
		}
	overrides[edge_key] = transition
	return {"ok": true, "error": ""}


static func _normalize_transition(raw: Variant, field_path: String, source: String) -> Dictionary:
	var string_result := _require_json_string(raw, field_path)
	if not string_result["ok"]:
		return {"ok": false, "error": "%s in %s" % [string_result["error"], source], "transition": ""}
	var value: String = string_result["value"]
	if value != WorldMapScript.EDGE_SMOOTH and value != WorldMapScript.EDGE_CLIFF:
		return {
			"ok": false,
			"error": "Unsupported edge transition %s at %s in %s" % [value, field_path, source],
			"transition": "",
		}
	return {"ok": true, "error": "", "transition": value}


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
