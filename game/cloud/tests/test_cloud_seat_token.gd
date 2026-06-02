# Headless: godot --headless --path game -s res://cloud/tests/test_cloud_seat_token.gd
extends SceneTree

const CloudClientScript = preload("res://cloud/cloud_client.gd")
const CloudSessionScript = preload("res://cloud/cloud_session.gd")

var _total = 0
var _any_fail = false


func _init() -> void:
	var resp: Dictionary = {
		"match_id": "m_t",
		"host_token": "ht_abc",
		"seats": [
			{"actor_id": 0, "token": "st_p0"},
			{"actor_id": 1, "token": "st_p1"},
		],
	}
	_check(CloudClientScript.host_token_from_create_response(resp) == "ht_abc", "host_token extract")
	_check(CloudClientScript.seat_token_for_actor(resp, 1) == "st_p1", "seat token for actor 1")
	_check(CloudClientScript.SEAT_TOKEN_HEADER == "X-Empire-Seat-Token", "header constant")
	var sess = CloudSessionScript.new()
	sess.seat_token = "ht_test"
	var tok: String = sess.seat_token.strip_edges()
	var hdr_line := ""
	if tok.length() > 0:
		hdr_line = "%s: %s" % [CloudClientScript.SEAT_TOKEN_HEADER, tok]
	_check(hdr_line.find("ht_test") >= 0, "header line would include token")
	sess.free()
	if _any_fail:
		call_deferred("quit", 1)
	else:
		print("PASS %d/%d" % [_total, _total])
		call_deferred("quit", 0)


func _check(cond, message) -> void:
	_total = _total + 1
	if cond:
		return
	_any_fail = true
	var line = "FAIL: %s" % message
	print(line)
	push_error(line)
