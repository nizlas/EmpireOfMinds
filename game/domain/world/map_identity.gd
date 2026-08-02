# Canonical immutable map content identity. Domain-only; no rendering or networking.
# Spec: docs/MAP_CONTENT.md, docs/MAP_MODEL.md
class_name MapIdentity
extends RefCounted

const ScriptRef = preload("res://domain/world/map_identity.gd")

var map_id: String
var schema_version: int
var content_hash: String


func _init(p_map_id: String = "", p_schema_version: int = 0, p_content_hash: String = "") -> void:
	map_id = p_map_id
	schema_version = p_schema_version
	content_hash = p_content_hash


func equals(other) -> bool:
	if other == null or other.get_script() != ScriptRef:
		return false
	return (
		map_id == other.map_id
		and schema_version == other.schema_version
		and content_hash == other.content_hash
	)


func to_dict() -> Dictionary:
	return {
		"map_id": map_id,
		"schema_version": schema_version,
		"content_hash": content_hash,
	}


static func from_dict(data: Dictionary):
	return ScriptRef.new(
		str(data.get("map_id", "")),
		int(data.get("schema_version", 0)),
		str(data.get("content_hash", ""))
	)
