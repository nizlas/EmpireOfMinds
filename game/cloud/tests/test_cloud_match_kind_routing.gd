# Headless: godot --headless --path game -s res://cloud/tests/test_cloud_match_kind_routing.gd
#
# N6: match_kind must be preserved through every real client transition into
# gameplay — (1) env-created match, (2) create response into staging,
# (3) lobby join, (4) saved-match resume, (5) staging poll into gameplay —
# and legacy matches (absent kind) must keep the untouched main.tscn entry
# and the unchanged legacy create body.
extends SceneTree

const BootIntentScript = preload("res://cloud/boot_intent.gd")
const CloudClientScript = preload("res://cloud/cloud_client.gd")

const WORLD_SCENE := "res://cloud/world_play/cloud_world_play.tscn"
const LEGACY_SCENE := "res://main.tscn"

var _total := 0
var _any_fail := false


func _init() -> void:
	_run()


func _run() -> void:
	BootIntentScript.clear()
	_test_play_scene_routing()
	_test_create_body_contract()
	_test_kind_parsers()
	_test_env_create_transition()
	_test_create_response_into_staging_transition()
	_test_lobby_join_transition()
	_test_saved_resume_transition()
	await _test_staging_poll_into_gameplay_transition()
	_finish()


func _test_play_scene_routing() -> void:
	_check(
		BootIntentScript.play_scene_for_match_kind("world_map") == WORLD_SCENE,
		"world_map kind routes to cloud_world_play"
	)
	_check(
		BootIntentScript.play_scene_for_match_kind("") == LEGACY_SCENE,
		"absent kind keeps legacy main.tscn"
	)
	_check(
		BootIntentScript.play_scene_for_match_kind("  world_map  ") == WORLD_SCENE,
		"kind routing strips whitespace"
	)
	_check(BootIntentScript.is_world_map_kind("world_map"), "is_world_map_kind true")
	_check(not BootIntentScript.is_world_map_kind(""), "is_world_map_kind false for legacy")


func _test_create_body_contract() -> void:
	# Legacy body is byte-for-byte unchanged when kind is unset.
	var legacy: Dictionary = CloudClientScript.build_create_match_body("prototype_play", "My Match")
	_check(
		legacy == {"scenario_id": "prototype_play", "display_name": "My Match"},
		"legacy create body unchanged"
	)
	var legacy_plain: Dictionary = CloudClientScript.build_create_match_body("prototype_play")
	_check(legacy_plain == {"scenario_id": "prototype_play"}, "legacy body without display name")
	# World body: match_kind (+ optional map_id), no scenario_id.
	var world: Dictionary = CloudClientScript.build_create_match_body(
		"prototype_play", "World", "world_map", "handdrawn_test_map_full_01"
	)
	_check(
		world == {
			"match_kind": "world_map",
			"map_id": "handdrawn_test_map_full_01",
			"display_name": "World",
		},
		"world create body carries match_kind + map_id and no scenario_id"
	)
	var world_default_map: Dictionary = CloudClientScript.build_create_match_body(
		"prototype_play", "", "world_map"
	)
	_check(
		world_default_map == {"match_kind": "world_map"},
		"world body omits map_id when unset (server default)"
	)


func _test_kind_parsers() -> void:
	_check(
		CloudClientScript.match_kind_from_lobby_row({"match_kind": "world_map"}) == "world_map",
		"lobby row kind parsed"
	)
	_check(
		CloudClientScript.match_kind_from_lobby_row({"match_id": "m_x"}) == "",
		"legacy lobby row (absent key) parses to empty kind"
	)
	_check(
		CloudClientScript.match_kind_from_create_response(
			{"snapshot": {"match_kind": "world_map"}}
		) == "world_map",
		"create response kind parsed from snapshot"
	)
	_check(
		CloudClientScript.match_kind_from_create_response({"snapshot": {"schema_version": 2}}) == "",
		"legacy create response parses to empty kind"
	)


# Transition 1: env-created match (EOM_CLOUD_MATCH_KIND opt-in).
func _test_env_create_transition() -> void:
	OS.set_environment("EOM_CLOUD_BASE_URL", "http://127.0.0.1:8000")
	OS.set_environment("EOM_CLOUD_MATCH_ID", "")
	OS.set_environment("EOM_CLOUD_SEAT_TOKEN", "ht_env")
	OS.set_environment("EOM_CLOUD_MATCH_KIND", "world_map")
	BootIntentScript.apply_env_cloud_to_boot_intent()
	_check(BootIntentScript.mode == BootIntentScript.MODE_CLOUD_CREATE, "env create mode")
	_check(BootIntentScript.match_kind == "world_map", "env create carries world_map kind")
	_check(
		BootIntentScript.play_scene_for_match_kind(BootIntentScript.match_kind) == WORLD_SCENE,
		"env create routes to the world play scene"
	)
	var snap: Dictionary = BootIntentScript.consume_for_main()
	_check(str(snap.get("match_kind", "")) == "world_map", "env create consume keeps kind")
	# Env reconnect keeps the kind as well.
	OS.set_environment("EOM_CLOUD_MATCH_ID", "m_env")
	BootIntentScript.apply_env_cloud_to_boot_intent()
	_check(
		BootIntentScript.mode == BootIntentScript.MODE_CLOUD_RECONNECT
			and BootIntentScript.match_kind == "world_map",
		"env reconnect carries world_map kind"
	)
	BootIntentScript.clear()
	# Legacy env boot stays legacy.
	OS.set_environment("EOM_CLOUD_MATCH_KIND", "")
	OS.set_environment("EOM_CLOUD_MATCH_ID", "")
	BootIntentScript.apply_env_cloud_to_boot_intent()
	_check(BootIntentScript.match_kind == "", "legacy env boot has empty kind")
	_check(
		BootIntentScript.play_scene_for_match_kind(BootIntentScript.match_kind) == LEGACY_SCENE,
		"legacy env boot routes to main.tscn"
	)
	BootIntentScript.clear()
	OS.set_environment("EOM_CLOUD_BASE_URL", "")
	OS.set_environment("EOM_CLOUD_SEAT_TOKEN", "")


# Transition 2: create response into staging (kind from response snapshot).
func _test_create_response_into_staging_transition() -> void:
	var resp := {
		"match_id": "m_created",
		"host_token": "ht_created",
		"snapshot": {"schema_version": 3, "match_kind": "world_map"},
	}
	var kind: String = CloudClientScript.match_kind_from_create_response(resp)
	BootIntentScript.set_cloud_staging(
		"http://127.0.0.1:8000", "m_created", "ht_created", "", -1, "World", "prototype_play", kind
	)
	_check(BootIntentScript.mode == BootIntentScript.MODE_CLOUD_STAGING, "create->staging mode")
	var snap: Dictionary = BootIntentScript.consume_for_main()
	_check(
		str(snap.get("match_kind", "")) == "world_map",
		"create->staging preserves world_map kind"
	)
	# Legacy create response leaves the kind empty.
	var legacy_kind: String = CloudClientScript.match_kind_from_create_response(
		{"match_id": "m_l", "snapshot": {"schema_version": 2}}
	)
	BootIntentScript.set_cloud_staging(
		"http://127.0.0.1:8000", "m_l", "ht_l", "", -1, "L", "prototype_play", legacy_kind
	)
	var snap2: Dictionary = BootIntentScript.consume_for_main()
	_check(str(snap2.get("match_kind", "")) == "", "legacy create->staging keeps empty kind")


# Transition 3: lobby join (kind from the token-free lobby row).
func _test_lobby_join_transition() -> void:
	var lobby_row := {"match_id": "m_join", "status": "staging", "match_kind": "world_map"}
	BootIntentScript.set_cloud_staging(
		"http://127.0.0.1:8000",
		"m_join",
		"",
		"",
		-1,
		"Join",
		"prototype_play",
		CloudClientScript.match_kind_from_lobby_row(lobby_row),
	)
	var snap: Dictionary = BootIntentScript.consume_for_main()
	_check(str(snap.get("match_kind", "")) == "world_map", "lobby join preserves world_map kind")


# Transition 4: saved-match resume (kind rides on the resume row view).
func _test_saved_resume_transition() -> void:
	var server_row := {
		"match_id": "m_saved",
		"display_name": "Saved World",
		"status": "ongoing",
		"revision": 4,
		"match_kind": "world_map",
	}
	var cred := {"actor_id": 1, "seat_token": "st_saved", "is_host": false}
	var view: Dictionary = CloudClientScript.build_resume_row_view(
		server_row, cred, "http://127.0.0.1:8000"
	)
	_check(str(view.get("match_kind", "")) == "world_map", "resume row view carries kind")
	BootIntentScript.set_cloud_reconnect(
		"http://127.0.0.1:8000",
		"m_saved",
		"st_saved",
		1,
		"prototype_play",
		str(view.get("match_kind", "")),
	)
	_check(
		BootIntentScript.play_scene_for_match_kind(BootIntentScript.match_kind) == WORLD_SCENE,
		"world resume routes to the world play scene"
	)
	var snap: Dictionary = BootIntentScript.consume_for_main()
	_check(str(snap.get("match_kind", "")) == "world_map", "resume preserves world_map kind")
	# Legacy resume rows (absent key) keep the legacy route.
	var legacy_view: Dictionary = CloudClientScript.build_resume_row_view(
		{"match_id": "m_old", "status": "ongoing"}, cred, "http://127.0.0.1:8000"
	)
	_check(str(legacy_view.get("match_kind", "")) == "", "legacy resume row has empty kind")
	_check(
		BootIntentScript.play_scene_for_match_kind(str(legacy_view.get("match_kind", "")))
			== LEGACY_SCENE,
		"legacy resume routes to main.tscn"
	)


# Transition 5: staging poll into ongoing gameplay (staging scene consumes
# the kind from its boot intent and routes gameplay entry by kind).
func _test_staging_poll_into_gameplay_transition() -> void:
	BootIntentScript.set_cloud_staging(
		"http://127.0.0.1:8000",
		"m_stage",
		"ht_stage",
		"st_stage",
		0,
		"Stage",
		"prototype_play",
		"world_map",
	)
	var packed: PackedScene = load("res://cloud/cloud_staging.tscn") as PackedScene
	_check(packed != null, "staging scene loads")
	if packed == null:
		return
	var node: Node = packed.instantiate()
	root.add_child(node)
	await node.ready
	_check(str(node._match_kind) == "world_map", "staging consumes world_map kind from intent")
	# The staging row refresh keeps a server-provided kind current.
	var lobby_row := {"match_id": "m_stage", "match_kind": "world_map"}
	_check(
		CloudClientScript.match_kind_from_lobby_row(lobby_row) == "world_map",
		"staging poll reads the row kind"
	)
	_check(
		BootIntentScript.play_scene_for_match_kind(str(node._match_kind)) == WORLD_SCENE,
		"staging gameplay entry routes world_map to the world play scene"
	)
	node.queue_free()
	await process_frame
	BootIntentScript.clear()


func _check(condition: bool, label: String) -> void:
	_total += 1
	if condition:
		print("PASS ", label)
	else:
		_any_fail = true
		print("FAIL ", label)


func _finish() -> void:
	print("CloudMatchKindRouting tests: %d checks" % _total)
	if _any_fail:
		print("FAIL")
		quit(1)
	else:
		print("PASS")
		quit(0)
