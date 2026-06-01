# Pure URL / payload helpers for tests and documentation parity (Slice C8).
extends RefCounted
class_name CloudClient


static func matches_base(base_url: String, path: String) -> String:
	return str(base_url).rstrip("/") + path


## Slice **C9**: empty match id → create; non-empty → reconnect via **GET /v1/matches/{id}**.
static func should_create_match(match_id: String) -> bool:
	return str(match_id).strip_edges().is_empty()


static func get_match_path(match_id: String) -> String:
	return "/v1/matches/%s" % str(match_id).strip_edges()


## Stable key for **cloud_move_action_by_hex** / server **move_unit** destination (axial q,r).
static func hex_action_key(q: int, r: int) -> String:
	return "%d,%d" % [q, r]


## Slice C8: **Space** means cloud **end_turn** when cloud mode is on (used with **Main._input** early routing).
static func is_cloud_space_end_turn_shortcut(cloud_mode: bool, event: InputEvent) -> bool:
	if not cloud_mode or event == null or not (event is InputEventKey):
		return false
	var ek = event as InputEventKey
	return ek.pressed and not ek.echo and ek.keycode == KEY_SPACE


static func legal_actions_path(
	match_id: String,
	actor_id: int,
	selected_unit_id: int = -1,
	selected_city_id: int = -1,
) -> String:
	var q = "?actor_id=%d" % actor_id
	if selected_unit_id >= 0:
		q += "&selected_unit_id=%d" % selected_unit_id
	if selected_city_id >= 0:
		q += "&selected_city_id=%d" % selected_city_id
	return "/v1/matches/%s/legal-actions%s" % [match_id, q]


## True only when the client should replace local presentation from `snapshot` (Slice C8 gate).
static func should_apply_snapshot(response: Dictionary) -> bool:
	if response == null or typeof(response) != TYPE_DICTIONARY:
		return false
	if response.has("_error"):
		return false
	if not bool(response.get("accepted", false)):
		return false
	return typeof(response.get("snapshot")) == TYPE_DICTIONARY


## Godot **JSON.parse** maps JSON numbers to **float**; FastAPI+Pydantic expects **int** for **actor_id** / **unit_id**
## and **move_unit** **from**/**to** (see **server/app/domain/actions/move_unit.py**). Normalize before **POST /actions**.
static func _normalize_qr_array(v) -> Array:
	if typeof(v) != TYPE_ARRAY:
		return []
	var a: Array = v
	if a.size() < 2:
		return []
	return [int(a[0]), int(a[1])]


static func normalize_api_action_for_post(action: Dictionary) -> Dictionary:
	var out: Dictionary = action.duplicate(true)
	if out.has("schema_version"):
		out["schema_version"] = int(out["schema_version"])
	if out.has("actor_id"):
		out["actor_id"] = int(out["actor_id"])
	var at: String = str(out.get("action_type", ""))
	match at:
		"move_unit":
			if out.has("unit_id"):
				out["unit_id"] = int(out["unit_id"])
			var fmq = _normalize_qr_array(out.get("from"))
			var tmq = _normalize_qr_array(out.get("to"))
			if fmq.size() == 2:
				out["from"] = fmq
			if tmq.size() == 2:
				out["to"] = tmq
		"found_city":
			if out.has("unit_id"):
				out["unit_id"] = int(out["unit_id"])
			var pos = _normalize_qr_array(out.get("position"))
			if pos.size() == 2:
				out["position"] = pos
		"set_city_production":
			if out.has("city_id"):
				out["city_id"] = int(out["city_id"])
			if out.has("project_id"):
				out["project_id"] = str(out["project_id"])
		_:
			pass
	return out


## Slice C8: show turn-start banner only on player change (or initial cloud bootstrap when **previous** is **null**).
static func should_show_turn_start_banner(previous_player_id, new_player_id: int) -> bool:
	if new_player_id < 0:
		return false
	if previous_player_id == null:
		return true
	return int(previous_player_id) != new_player_id
