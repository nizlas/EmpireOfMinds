# C14d-4b: cloud ongoing match — local seat vs server current player (client UX only).
extends RefCounted

const WAITING_STATUS_TEXT: String = "Other player's turn"


static func current_actor_id_from_turn_state(turn_state) -> int:
	if turn_state == null:
		return -1
	return int(turn_state.current_player_id())


static func is_my_cloud_turn(local_actor_id: int, turn_state) -> bool:
	if int(local_actor_id) < 0 or turn_state == null:
		return false
	return int(local_actor_id) == current_actor_id_from_turn_state(turn_state)


static func is_cloud_waiting_readonly(cloud_mode: bool, local_actor_id: int, turn_state) -> bool:
	if not cloud_mode:
		return false
	return not is_my_cloud_turn(local_actor_id, turn_state)


static func waiting_status_text(cloud_mode: bool, local_actor_id: int, turn_state) -> String:
	if is_cloud_waiting_readonly(cloud_mode, local_actor_id, turn_state):
		return WAITING_STATUS_TEXT
	return ""


static func gameplay_actor_id_from_boot(boot: Dictionary) -> int:
	var tok: String = str(boot.get("seat_token", "")).strip_edges()
	if not tok.begins_with("st_"):
		return -1
	var aid: int = int(boot.get("actor_id", -1))
	if aid < 0:
		return -1
	return aid


static func gameplay_actor_id_from_credential(entry: Dictionary) -> int:
	if typeof(entry) != TYPE_DICTIONARY or entry.is_empty():
		return -1
	const StoreScript = preload("res://cloud/cloud_credential_store.gd")
	var seat_tok: String = StoreScript.gameplay_token_from_entry(entry)
	if seat_tok.is_empty() or not seat_tok.begins_with("st_"):
		return -1
	var aid: int = int(entry.get("actor_id", -1))
	if aid < 0:
		return -1
	return aid


static func is_seat_not_allowed_response(response: Dictionary) -> bool:
	if typeof(response) != TYPE_DICTIONARY:
		return false
	if bool(response.get("accepted", false)):
		return false
	return str(response.get("reason", "")).strip_edges() == "seat_not_allowed"
