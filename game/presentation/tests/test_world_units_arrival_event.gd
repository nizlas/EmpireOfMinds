# Headless: godot --headless --path game -s res://presentation/tests/test_world_units_arrival_event.gd
#
# N7f.1 arrival event (WorldUnitsView.unit_arrived): emitted EXACTLY ONCE
# per completed glide — after the visual settled at its exact final-anchor
# pose, the locomotion entry was removed, and Idle resumed. Never emitted
# for initial spawns, identical snapshot reapplies, ordinary idling,
# degenerate settlements, or units removed mid-glide; a mid-glide retarget
# emits nothing until the retargeted glide's own final settlement; with
# several units the event carries the correct unit id. Locomotion,
# grounding, clips, and the exact-anchor arrival pose stay untouched.
# Fast — no terrain build, no networking.
extends SceneTree

const WorldUnitsViewScript = preload("res://presentation/world/world_units_view.gd")

const ANCHORS := {
	Vector2i(0, 0): Vector3(0.0, 0.0, 0.0),
	Vector2i(1, 0): Vector3(2.0, 0.4, 0.0),
	Vector2i(2, 0): Vector3(4.0, 0.8, 0.0),
	Vector2i(0, 1): Vector3(0.0, 0.2, 2.0),
	Vector2i(1, 1): Vector3(2.0, 0.6, 2.0),
}
const SETTLER_IDLE_CLIP := "Hit_Reaction_1"
const SPEED: float = WorldUnitsViewScript.LOCOMOTION_SPEED_UNITS_PER_SEC

var _total := 0
var _any_fail := false
var _arrivals: Array = []


func _units(settler_pos: Array, warrior_pos: Array) -> Array:
	return [
		{"id": 1, "owner_id": 11, "position": settler_pos, "type_id": "settler"},
		{"id": 2, "owner_id": 22, "position": warrior_pos, "type_id": "warrior"},
	]


func _on_arrival(unit_id: int) -> void:
	_arrivals.append(int(unit_id))


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	var view = WorldUnitsViewScript.new()
	root.add_child(view)
	view.set_process(false)  # tests drive advance_locomotion deterministically
	view.unit_arrived.connect(_on_arrival)
	view.set_tile_anchors(ANCHORS)

	# --- spawn emits nothing -------------------------------------------------
	view.apply_snapshot_units(_units([0, 0], [0, 1]))
	_check(_arrivals.is_empty(), "initial spawn emits no arrival")
	view.advance_locomotion(1.0)
	_check(_arrivals.is_empty(), "ordinary idle advancing emits no arrival")

	# --- identical reapply emits nothing --------------------------------------
	view.apply_snapshot_units(_units([0, 0], [0, 1]))
	_check(_arrivals.is_empty(), "identical snapshot reapply emits no arrival")

	# --- one real glide: exactly one arrival at exact settlement -------------
	view.apply_snapshot_units(_units([1, 0], [0, 1]))
	_check(view.is_unit_moving(1), "glide is active after the move")
	var duration: float = 2.0 / SPEED
	view.advance_locomotion(duration * 0.5)
	_check(_arrivals.is_empty(), "mid-glide advancing emits no arrival")
	view.advance_locomotion(duration)  # crosses the completion point
	_check(_arrivals == [1], "exactly one arrival, carrying the moved unit's id")
	_check(not view.is_unit_moving(1), "locomotion entry removed at arrival")
	var settler_root: Node3D = view.root_for_unit(1)
	var settler_model: Node3D = settler_root.get_node("ModelRoot")
	_check(
		settler_model.position == Vector3.ZERO
			and settler_root.position == ANCHORS[Vector2i(1, 0)],
		"arrival fires only after the EXACT final-anchor pose"
	)
	var player: AnimationPlayer = view.animation_player_for_unit(1)
	_check(player.current_animation == SETTLER_IDLE_CLIP, "Idle resumed when the event fired")
	view.advance_locomotion(5.0)
	_check(_arrivals == [1], "no further events after settlement (exactly once)")
	view.apply_snapshot_units(_units([1, 0], [0, 1]))
	_check(_arrivals == [1], "post-arrival identical reapply emits nothing")

	# --- mid-glide retarget: one arrival at the FINAL settlement only --------
	_arrivals.clear()
	view.apply_snapshot_units(_units([2, 0], [0, 1]))
	view.advance_locomotion(duration * 0.4)
	_check(_arrivals.is_empty(), "in-flight glide emits nothing before retarget")
	view.apply_snapshot_units(_units([1, 0], [0, 1]))  # retarget mid-glide
	_check(_arrivals.is_empty(), "the retarget itself emits no arrival")
	_check(view.is_unit_moving(1), "retargeted glide continues")
	view.advance_locomotion(60.0)
	_check(_arrivals == [1], "retargeted glide emits exactly one arrival at final settlement")
	_check(
		view.root_for_unit(1).position == ANCHORS[Vector2i(1, 0)]
			and (view.root_for_unit(1) as Node3D).get_node("ModelRoot").position == Vector3.ZERO,
		"retargeted arrival is the exact newest-anchor pose"
	)

	# --- multiple units: the id belongs to the arriving unit ------------------
	_arrivals.clear()
	view.apply_snapshot_units(_units([1, 0], [1, 1]))  # warrior moves, settler idle
	_check(view.is_unit_moving(2) and not view.is_unit_moving(1), "only the warrior glides")
	view.advance_locomotion(60.0)
	_check(_arrivals == [2], "the arrival event carries the ARRIVING unit's id")

	# --- removal mid-glide emits nothing ---------------------------------------
	_arrivals.clear()
	view.apply_snapshot_units(_units([2, 0], [1, 1]))
	view.advance_locomotion(duration * 0.3)
	view.apply_snapshot_units([_units([2, 0], [1, 1])[1]])  # settler removed mid-glide
	await process_frame
	view.advance_locomotion(60.0)
	_check(
		not _arrivals.has(1),
		"a unit removed mid-glide never emits an arrival"
	)

	view.queue_free()
	await process_frame

	print("WorldUnitsArrivalEvent tests: %d checks" % _total)
	if _any_fail:
		print("FAIL")
		quit(1)
	else:
		print("PASS")
		quit(0)


func _check(cond: bool, label: String) -> void:
	_total += 1
	if cond:
		print("PASS %s" % label)
	else:
		_any_fail = true
		print("FAIL %s" % label)
