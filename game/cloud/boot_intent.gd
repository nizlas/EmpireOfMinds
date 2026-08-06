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

## N6 match kinds: "" (legacy HexMap path, default) or "world_map" (snapshot
## v3 + server-fed WorldMap bootstrap). Routing must preserve the kind across
## every transition into gameplay (env-create, create->staging, lobby join,
## saved resume, staging poll->gameplay).
const MATCH_KIND_WORLD_MAP: String = "world_map"
const WORLD_PLAY_SCENE: String = "res://cloud/world_play/cloud_world_play.tscn"
const LEGACY_PLAY_SCENE: String = "res://main.tscn"

## C14d UI: neutral player-facing overlay while cloud session starts (create/reconnect/enter-created).
const CLOUD_CONNECTING_STATUS: String = "Connecting to cloud game…"
const CLOUD_LOADING_STATUS: String = "Loading cloud game…"

static var mode: String = MODE_NONE
static var server_url: String = ""
static var match_id: String = ""
static var seat_token: String = ""
static var host_token: String = ""
static var actor_id: int = -1
static var display_name: String = ""
static var scenario_id: String = "prototype_play"
## N6: "" = legacy; MATCH_KIND_WORLD_MAP = world_map match (snapshot v3).
static var match_kind: String = ""


static func clear() -> void:
	mode = MODE_NONE
	server_url = ""
	match_id = ""
	seat_token = ""
	host_token = ""
	actor_id = -1
	display_name = ""
	scenario_id = "prototype_play"
	match_kind = ""


static func set_local_hotseat() -> void:
	clear()
	mode = MODE_LOCAL_HOTSEAT


static func set_cloud_create(
	url: String,
	host_token: String,
	scen: String = "prototype_play",
	kind: String = "",
) -> void:
	clear()
	mode = MODE_CLOUD_CREATE
	server_url = str(url).rstrip("/")
	match_id = ""
	seat_token = str(host_token).strip_edges()
	actor_id = 0
	scenario_id = scen
	match_kind = str(kind).strip_edges()


static func set_cloud_reconnect(
	url: String,
	mid: String,
	token: String,
	act_id: int,
	scen: String = "prototype_play",
	kind: String = "",
) -> void:
	clear()
	mode = MODE_CLOUD_RECONNECT
	server_url = str(url).rstrip("/")
	match_id = str(mid).strip_edges()
	seat_token = str(token).strip_edges()
	actor_id = int(act_id)
	scenario_id = scen
	match_kind = str(kind).strip_edges()


static func set_cloud_staging(
	url: String,
	mid: String,
	host_tok: String = "",
	seat_tok: String = "",
	act_id: int = -1,
	display: String = "",
	scen: String = "prototype_play",
	kind: String = "",
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
	match_kind = str(kind).strip_edges()


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


## N6 routing: world_map matches enter the dedicated production world scene;
## everything else (legacy / absent kind) keeps the untouched default entry.
static func play_scene_for_match_kind(kind: String) -> String:
	if str(kind).strip_edges() == MATCH_KIND_WORLD_MAP:
		return WORLD_PLAY_SCENE
	return LEGACY_PLAY_SCENE


static func is_world_map_kind(kind: String) -> bool:
	return str(kind).strip_edges() == MATCH_KIND_WORLD_MAP


static func is_cloud_enter_created(boot_mode: String) -> bool:
	return str(boot_mode) == MODE_CLOUD_ENTER_CREATED


static func is_cloud_staging(boot_mode: String) -> bool:
	return str(boot_mode) == MODE_CLOUD_STAGING


static func cloud_load_status_message(boot_mode: String) -> String:
	if is_cloud_staging(boot_mode):
		return "Entering staging…"
	return CLOUD_CONNECTING_STATUS


## Dev/test: skip front door when **EOM_CLOUD_CLIENT** is set (same as Main cloud gate).
static func should_skip_front_door_for_env() -> bool:
	var flg: String = OS.get_environment("EOM_CLOUD_CLIENT").strip_edges()
	return flg == "1" or flg.to_lower() == "true"


## N7d one-PC debug (locked dual-entry direction): dev-only opt-in that lets
## ONE Godot client control both players in turn against a LOCAL
## authoritative FastAPI server, through the same client-server API/action
## path as remote multiplayer. Explicit env flag only — EOM_CLOUD_DEBUG
## stays logging-only and normal seat-token/profile multiplayer is
## untouched when this flag is absent.
static func one_pc_debug_env_requested() -> bool:
	return OS.get_environment("EOM_CLOUD_ONE_PC_DEBUG").strip_edges() == "1"


## Loopback hosts only — the one-PC debug mode runs against a LOCALLY
## running authoritative server, never a remote one.
static func is_loopback_url(url: String) -> bool:
	var normalized := str(url).strip_edges().to_lower()
	var scheme_split := normalized.find("://")
	if scheme_split < 0:
		return false
	var scheme := normalized.substr(0, scheme_split)
	if scheme != "http" and scheme != "https":
		return false
	var rest := normalized.substr(scheme_split + 3)
	var authority_end := rest.length()
	for sep in ["/", "?", "#"]:
		var idx := rest.find(sep)
		if idx >= 0:
			authority_end = mini(authority_end, idx)
	var authority := rest.substr(0, authority_end)
	# User-info can make a loopback-looking prefix resolve to a remote host.
	if authority.is_empty() or authority.contains("@"):
		return false
	var host := authority
	var port_separator := authority.rfind(":")
	if port_separator >= 0:
		host = authority.substr(0, port_separator)
		var port := authority.substr(port_separator + 1)
		if not port.is_valid_int():
			return false
		var port_number := port.to_int()
		if port_number < 1 or port_number > 65535:
			return false
	return host == "127.0.0.1" or host == "localhost"


## The one-PC debug mode is valid ONLY for world_map matches against a
## loopback server; anything else ignores the flag (normal behavior).
static func one_pc_debug_allowed(kind: String, url: String) -> bool:
	return is_world_map_kind(kind) and is_loopback_url(url)


## N6 env opt-in: EOM_CLOUD_MATCH_KIND=world_map selects the world_map match
## kind for env-driven create/reconnect. Unset/empty stays legacy. Optional
## EOM_CLOUD_MAP_ID picks the canonical map for env-created world matches.
static func env_match_kind() -> String:
	return OS.get_environment("EOM_CLOUD_MATCH_KIND").strip_edges()


static func env_map_id() -> String:
	return OS.get_environment("EOM_CLOUD_MAP_ID").strip_edges()


static func apply_env_cloud_to_boot_intent() -> void:
	var url: String = OS.get_environment("EOM_CLOUD_BASE_URL").strip_edges()
	if url.is_empty():
		url = "http://127.0.0.1:8000"
	var mid: String = OS.get_environment("EOM_CLOUD_MATCH_ID").strip_edges()
	var tok: String = OS.get_environment("EOM_CLOUD_SEAT_TOKEN").strip_edges()
	var scen: String = OS.get_environment("EOM_CLOUD_SCENARIO_ID").strip_edges()
	if scen.is_empty():
		scen = "prototype_play"
	var kind: String = env_match_kind()
	if CloudClientScript.should_create_match(mid):
		set_cloud_create(url, tok, scen, kind)
	else:
		set_cloud_reconnect(url, mid, tok, 0, scen, kind)


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
		"match_kind": match_kind,
	}
	debug_log_consume(snap)
	clear()
	return snap


static func debug_log_consume(snap: Dictionary) -> void:
	if OS.get_environment("EOM_CLOUD_DEBUG").strip_edges() != "1":
		return
	var st: String = str(snap.get("seat_token", "")).strip_edges()
	var ht: String = str(snap.get("host_token", "")).strip_edges()
	print(
		(
			"SliceC14dReconnect boot_intent_consume mode=%s match_id=%s actor_id=%d "
			+ "has_seat_token=%s has_host_token=%s"
		)
		% [
			str(snap.get("mode", "")),
			str(snap.get("match_id", "")),
			int(snap.get("actor_id", -1)),
			str(st.begins_with("st_")),
			str(ht.begins_with("ht_")),
		]
	)


static func has_pending() -> bool:
	return mode != MODE_NONE
