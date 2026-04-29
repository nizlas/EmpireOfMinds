# Immutable unit type definitions. Read-only static lookups. See docs/CONTENT_MODEL.md, docs/UNITS.md.
# Use get_definition(id) for a deep copy of a row; cannot name this "get" — conflicts with Object.get on RefCounted.
class_name UnitDefinitions
extends RefCounted

const _ORDERED_IDS: Array = ["settler", "warrior"]

# Primitive / JSON-equivalent rows only. No mutation at runtime.
const _DEFINITIONS: Dictionary = {
	"settler":
	{
		"id": "settler",
		"display_name": "Settler",
		"can_found_city": true,
		"production_cost": 2,
		"role": "founder",
	},
	"warrior":
	{
		"id": "warrior",
		"display_name": "Warrior",
		"can_found_city": false,
		"production_cost": 2,
		"role": "basic_melee",
	},
}


static func has(id: String) -> bool:
	return _DEFINITIONS.has(id)


static func get_definition(id: String):
	if not _DEFINITIONS.has(id):
		return null
	var src = _DEFINITIONS[id] as Dictionary
	return src.duplicate(true)


static func ids() -> Array:
	return _ORDERED_IDS.duplicate()


static func can_found_city(id: String) -> bool:
	var d = get_definition(id)
	return d != null and bool(d.get("can_found_city", false))
