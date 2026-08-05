# N6 server-fed WorldMap bootstrap (pure parse/verify helper; no networking,
# no scene work). Consumes a snapshot v3 (match_kind "world_map"): the server
# sends only the canonical MapIdentity (map_id, schema_version, content_hash)
# plus revision/turn_state — never tiles, edges, terrain, or geometry. The
# client loads the canonical content by map_id through the derived-package
# manifest and verifies the schema version and the raw-byte content hash
# against the server identity. Any missing content or identity mismatch is an
# explicit failure — there is deliberately NO fallback map (a silent
# mismatch would desync gameplay authority; docs/MAP_CONTENT.md).
class_name WorldSnapshotBootstrap
extends RefCounted

const MapContentLoaderScript = preload("res://domain/world/map_content_loader.gd")

const MATCH_KIND_WORLD_MAP := "world_map"
const SNAPSHOT_SCHEMA_V3 := 3


# Validates the snapshot v3 envelope and extracts the server MapIdentity.
# Returns {ok, error, map_id, schema_version, content_hash, revision,
# turn_state}. Pure; no content loading here.
static func parse_world_snapshot(snap) -> Dictionary:
	var fail := func(msg: String) -> Dictionary:
		return {"ok": false, "error": msg}
	if typeof(snap) != TYPE_DICTIONARY:
		return fail.call("snapshot must be a JSON object")
	var d: Dictionary = snap
	var schema := int(d.get("schema_version", -1))
	if schema != SNAPSHOT_SCHEMA_V3:
		return fail.call("unsupported snapshot schema_version %d (expected %d)" % [schema, SNAPSHOT_SCHEMA_V3])
	if str(d.get("match_kind", "")) != MATCH_KIND_WORLD_MAP:
		return fail.call("snapshot match_kind %s is not %s" % [str(d.get("match_kind", "")), MATCH_KIND_WORLD_MAP])
	var map_ident = d.get("map", null)
	if typeof(map_ident) != TYPE_DICTIONARY:
		return fail.call("snapshot map identity missing or not an object")
	var mi: Dictionary = map_ident
	var map_id := str(mi.get("map_id", "")).strip_edges()
	if map_id.is_empty():
		return fail.call("snapshot map identity has empty map_id")
	var content_hash := str(mi.get("content_hash", "")).strip_edges()
	if content_hash.is_empty():
		return fail.call("snapshot map identity has empty content_hash")
	var turn_state = d.get("turn_state", null)
	if typeof(turn_state) != TYPE_DICTIONARY:
		return fail.call("snapshot turn_state missing or not an object")
	return {
		"ok": true,
		"error": "",
		"map_id": map_id,
		"schema_version": int(mi.get("schema_version", -1)),
		"content_hash": content_hash,
		"revision": int(d.get("revision", -1)),
		"turn_state": (turn_state as Dictionary).duplicate(true),
	}


# Compares the locally loaded identity against the server identity from the
# parsed snapshot. Explicit per-field errors; never a partial match.
static func verify_identity(parsed: Dictionary, loaded_identity) -> Dictionary:
	if loaded_identity == null:
		return {"ok": false, "error": "loaded map identity is null"}
	if loaded_identity.map_id != str(parsed.get("map_id", "")):
		return {
			"ok": false,
			"error": (
				"map_id mismatch: server sent %s, local content is %s"
				% [str(parsed.get("map_id", "")), loaded_identity.map_id]
			),
		}
	if int(loaded_identity.schema_version) != int(parsed.get("schema_version", -1)):
		return {
			"ok": false,
			"error": (
				"map schema_version mismatch for %s: server %d, local %d"
				% [
					loaded_identity.map_id,
					int(parsed.get("schema_version", -1)),
					int(loaded_identity.schema_version),
				]
			),
		}
	if loaded_identity.content_hash != str(parsed.get("content_hash", "")):
		return {
			"ok": false,
			"error": (
				"content_hash mismatch for %s: server %s, local %s (canonical content out of sync)"
				% [
					loaded_identity.map_id,
					str(parsed.get("content_hash", "")),
					loaded_identity.content_hash,
				]
			),
		}
	return {"ok": true, "error": ""}


# Full bootstrap: parse v3 envelope -> load canonical content by map_id via
# the manifest -> verify identity. Returns {ok, error, world_map, parsed}.
# Every failure is explicit; the world_map is null unless everything passed.
static func load_and_verify_world_map(snap) -> Dictionary:
	var parsed := parse_world_snapshot(snap)
	if not parsed["ok"]:
		return {"ok": false, "error": parsed["error"], "world_map": null, "parsed": parsed}
	var load_result: Dictionary = MapContentLoaderScript.try_load_world_map_by_id(
		str(parsed["map_id"])
	)
	if not load_result["ok"]:
		return {"ok": false, "error": load_result["error"], "world_map": null, "parsed": parsed}
	var world_map = load_result["world_map"]
	var verify := verify_identity(parsed, world_map.identity)
	if not verify["ok"]:
		return {"ok": false, "error": verify["error"], "world_map": null, "parsed": parsed}
	return {"ok": true, "error": "", "world_map": world_map, "parsed": parsed}
