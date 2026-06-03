# Slice C14c: one-shot boot parameters from front door into main.tscn (no autoload).
extends RefCounted
class_name BootIntent

const CloudClientScript = preload("res://cloud/cloud_client.gd")

const MODE_NONE: String = ""
const MODE_LOCAL_HOTSEAT: String = "local_hotseat"
const MODE_CLOUD_CREATE: String = "cloud_create"
const MODE_CLOUD_RECONNECT: String = "cloud_reconnect"
## Front door already **POST /v1/matches**; **main** loads via **GET** (not a second create).
const MODE_CLOUD_ENTER_CREATED: String = "cloud_enter_created"
## Staging area for a match (C14d-3); may carry host and/or seat token.
const MODE_CLOUD_STAGING: String = "cloud_staging"

static var mode: String = MODE_NONE
static var server_url: String = ""
static var match_id: String = ""
static var seat_token: String = ""
static var host_token: String = ""
static var actor_id: int = -1
static var display_name: String = ""
static var scenario_id: String = "prototype_play"


static func clear() -> void:
	mode = MODE_NONE
	server_url = ""
	match_id = ""
	seat_token = ""
	host_token = ""
	actor_id = -1
	display_name = ""
	scenario_id = "prototype_play"


static func set_local_hotseat() -> void:
	clear()
	mode = MODE_LOCAL_HOTSEAT


static func set_cloud_create(url: String, host_token: String, scen: String = "prototype_play") -> void:
	clear()
	mode = MODE_CLOUD_CREATE
	server_url = str(url).rstrip("/")
	match_id = ""
	seat_token = str(host_token).strip_edges()
	actor_id = 0
	scenario_id = scen


static func set_cloud_reconnect(
	url: String,
	mid: String,
	token: String,
	act_id: int,
	scen: String = "prototype_play",
) -> void:
	clear()
	mode = MODE_CLOUD_RECONNECT
	server_url = str(url).rstrip("/")
	match_id = str(mid).strip_edges()
	seat_token = str(token).strip_edges()
	actor_id = int(act_id)
	scenario_id = scen


static func set_cloud_staging(
	url: String,
	mid: String,
	host_tok: String = "",
	seat_tok: String = "",
	act_id: int = -1,
	display: String = "",
	scen: String = "prototype_play",
) -> void:
	clear()
	mode = MODE_CLOUD_STAGING
	server_url = str(url).rstrip("/")
	match_id = str(mid).strip_edges()
	host_token = str(host_tok).strip_edges()
	seat_token = str(seat_tok).strip_edges()
	actor_id = int(act_id)
	display_name = str(display).strip_edges()
	scenario_id = scen


## After front-door **POST /v1/matches** — **GET** in **main**, not a second create.
static func set_cloud_play_from_create_response(
	url: String,
	resp: Dictionary,
	scen: String = "prototype_play",
) -> void:
	var mid: String = str(resp.get("match_id", "")).strip_edges()
	var tok: String = CloudClientScript.host_token_from_create_response(resp)
	clear()
	mode = MODE_CLOUD_ENTER_CREATED
	server_url = str(url).rstrip("/")
	match_id = mid
	seat_token = tok
	actor_id = 0
	scenario_id = scen


static func is_cloud_enter_created(boot_mode: String) -> bool:
	return str(boot_mode) == MODE_CLOUD_ENTER_CREATED


static func is_cloud_staging(boot_mode: String) -> bool:
	return str(boot_mode) == MODE_CLOUD_STAGING


static func cloud_load_status_message(boot_mode: String) -> String:
	if is_cloud_staging(boot_mode):
		return "Entering staging…"
	if is_cloud_enter_created(boot_mode):
		return "Connecting to new cloud match…"
	if str(boot_mode) == MODE_CLOUD_RECONNECT:
		return "Reconnecting to cloud match…"
	if str(boot_mode) == MODE_CLOUD_CREATE:
		return "Creating cloud match…"
	return "Connecting to cloud match…"


## Dev/test: skip front door when **EOM_CLOUD_CLIENT** is set (same as Main cloud gate).
static func should_skip_front_door_for_env() -> bool:
	var flg: String = OS.get_environment("EOM_CLOUD_CLIENT").strip_edges()
	return flg == "1" or flg.to_lower() == "true"


static func apply_env_cloud_to_boot_intent() -> void:
	var url: String = OS.get_environment("EOM_CLOUD_BASE_URL").strip_edges()
	if url.is_empty():
		url = "http://127.0.0.1:8000"
	var mid: String = OS.get_environment("EOM_CLOUD_MATCH_ID").strip_edges()
	var tok: String = OS.get_environment("EOM_CLOUD_SEAT_TOKEN").strip_edges()
	var scen: String = OS.get_environment("EOM_CLOUD_SCENARIO_ID").strip_edges()
	if scen.is_empty():
		scen = "prototype_play"
	if CloudClientScript.should_create_match(mid):
		set_cloud_create(url, tok, scen)
	else:
		set_cloud_reconnect(url, mid, tok, 0, scen)


static func consume_for_main() -> Dictionary:
	var snap := {
		"mode": mode,
		"server_url": server_url,
		"match_id": match_id,
		"seat_token": seat_token,
		"host_token": host_token,
		"actor_id": actor_id,
		"display_name": display_name,
		"scenario_id": scenario_id,
	}
	clear()
	return snap


static func has_pending() -> bool:
	return mode != MODE_NONE
