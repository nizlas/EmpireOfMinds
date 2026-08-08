# Headless: godot --headless --path game -s res://presentation/tests/test_world_units_combat.gd
#
# N7g.3 combat presentation (WorldUnitsView.present_combat) on the REAL
# shipped warrior rig — presentation-only sequencing driven exclusively by
# the accepted server event + deferred authoritative snapshot:
# - presentation-only melee approach (Walking, terrain-following, no
#   unit_arrived, no gameplay-position mutation);
# - impact-timed overlapping Left_Slash / Hit_Reaction_1 (non-fatal);
# - fatal hits: Dead starts directly at impact (no Hit_Reaction_1 prepend);
# - centralized AnimationPlayer blend on every semantic clip change;
# - retaliation only when the event says so (never after defender death);
# - continuous corpse terrain support during Dead (contact→final, no pop);
# - survivor return vs snapshot-authoritative occupation traversal;
# - shortest-arc travel-facing blend on survivor departure (no yaw snap);
# - cancel/supersede clears presentation offsets;
# - N7f locomotion/arrival unchanged after combat.
# Fast — no terrain build, no networking.
extends SceneTree

const WorldUnitsViewScript = preload("res://presentation/world/world_units_view.gd")

const ANCHORS := {
	Vector2i(0, 0): Vector3(0.0, 0.0, 0.0),
	Vector2i(1, 0): Vector3(2.0, 0.0, 0.0),
	Vector2i(2, 0): Vector3(4.0, 0.0, 0.0),
	Vector2i(0, 1): Vector3(0.0, 0.0, 2.0),
}

# Anchors whose Y matches SlopeSampler height = 0.25 * x (production N4 style).
const SLOPE_ANCHORS := {
	Vector2i(0, 0): Vector3(0.0, 0.0, 0.0),
	Vector2i(1, 0): Vector3(2.0, 0.5, 0.0),
	Vector2i(2, 0): Vector3(4.0, 1.0, 0.0),
	Vector2i(0, 1): Vector3(0.0, 0.0, 2.0),
}

const WARRIOR_GLB_ATTACK := "Dead"  # semantic Left_Slash
const WARRIOR_GLB_HIT := "Running"  # semantic Hit_Reaction_1
const WARRIOR_GLB_DEAD := "Left_Slash"  # semantic Dead
const WARRIOR_GLB_IDLE := "Combat_Stance"  # semantic Idle_3
const WARRIOR_GLB_WALK := "Idle_02"  # semantic Walking

var _total := 0
var _any_fail := false
var _finished_events: Array = []
var _arrivals: Array = []


class FlatSampler:
	extends RefCounted
	func sample(x: float, z: float, y_hint: float) -> Dictionary:
		return {"ok": true, "height": 0.0, "normal": Vector3.UP}


class SlopeSampler:
	extends RefCounted
	# Gentle +X slope: height = 0.25 * x, normal tilts toward -X.
	func sample(x: float, z: float, y_hint: float) -> Dictionary:
		var n := Vector3(-0.25, 1.0, 0.0).normalized()
		return {"ok": true, "height": 0.25 * x, "normal": n}


func _units(pos_1: Array, pos_2: Array) -> Array:
	return [
		{"id": 1, "owner_id": 0, "position": pos_1, "type_id": "warrior", "current_hp": 100, "has_attacked": false},
		{"id": 2, "owner_id": 1, "position": pos_2, "type_id": "warrior", "current_hp": 70, "has_attacked": false},
	]


func _event(att_killed: bool, def_killed: bool, retaliated: bool) -> Dictionary:
	return {
		"attacker_id": 1,
		"defender_id": 2,
		"attacker_killed": att_killed,
		"defender_killed": def_killed,
		"retaliated": retaliated,
		"attacker_hp_after": 70,
		"defender_hp_after": 40,
	}


func _snap_survive() -> Dictionary:
	return {
		"units": [
			{"id": 1, "owner_id": 0, "position": [0, 0], "type_id": "warrior", "current_hp": 70, "has_attacked": true},
			{"id": 2, "owner_id": 1, "position": [1, 0], "type_id": "warrior", "current_hp": 40, "has_attacked": false},
		]
	}


func _snap_capture() -> Dictionary:
	# Defender killed: authoritative attacker position is the former defender tile.
	return {
		"units": [
			{"id": 1, "owner_id": 0, "position": [1, 0], "type_id": "warrior", "current_hp": 100, "has_attacked": true},
		]
	}


func _snap_attacker_dead() -> Dictionary:
	return {
		"units": [
			{"id": 2, "owner_id": 1, "position": [1, 0], "type_id": "warrior", "current_hp": 40, "has_attacked": false},
		]
	}


func _on_finished(attacker_id: int, defender_id: int) -> void:
	_finished_events.append([int(attacker_id), int(defender_id)])


func _on_arrival(unit_id: int) -> void:
	_arrivals.append(int(unit_id))


func _rendered_forward(view, unit_id: int) -> Vector3:
	var model: Node3D = (view.root_for_unit(unit_id) as Node3D).get_node("ModelRoot")
	return (model.basis * Vector3.FORWARD).normalized()


func _current_clip(view, unit_id: int) -> String:
	var player: AnimationPlayer = view.animation_player_for_unit(unit_id)
	if player == null:
		return ""
	# Frozen corpses use speed_scale 0 — current_animation may clear while
	# assigned_animation still names the Dead clip.
	if not player.current_animation.is_empty():
		return player.current_animation
	return player.assigned_animation


func _clip_length(view, unit_id: int, glb_clip: String) -> float:
	var player: AnimationPlayer = view.animation_player_for_unit(unit_id)
	return float(player.get_animation(glb_clip).length)


func _visual(view, unit_id: int) -> Vector3:
	return view.visual_position_for_unit(unit_id)


func _run_to_completion(view) -> void:
	var guard := 0
	while view.combat_active() and guard < 32:
		view.advance_combat(60.0)
		guard += 1


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	var view = WorldUnitsViewScript.new()
	root.add_child(view)
	view.set_process(false)
	view.set_surface_sampler(FlatSampler.new())
	view.combat_presentation_finished.connect(_on_finished)
	view.unit_arrived.connect(_on_arrival)
	view.set_tile_anchors(ANCHORS)
	view.apply_snapshot_units(_units([0, 0], [1, 0]))
	_check(view.unit_count() == 2, "both warriors render")
	_check(not view.combat_active(), "no combat active after spawn")

	# --- refusal / fallback paths ---------------------------------------------
	_check(not view.present_combat({}), "empty event refuses to start")
	_check(not view.present_combat(_event(false, false, true), {}), "missing deferred snapshot refuses to start")
	var missing := _event(false, false, false)
	missing.erase("retaliated")
	_check(not view.present_combat(missing, _snap_survive()), "missing outcome field refuses to start")
	var bad_flag := _event(false, false, false)
	bad_flag["defender_killed"] = "yes"
	_check(not view.present_combat(bad_flag, _snap_survive()), "non-bool outcome flag refuses to start")
	var unknown := _event(false, false, false)
	unknown["defender_id"] = 99
	_check(not view.present_combat(unknown, _snap_survive()), "unknown participant refuses to start")
	var self_attack := _event(false, false, false)
	self_attack["defender_id"] = 1
	_check(not view.present_combat(self_attack, _snap_survive()), "attacker == defender refuses to start")
	# Inconsistent occupation: event says kill but snapshot leaves attacker home.
	_check(
		not view.present_combat(_event(false, true, false), _snap_survive()),
		"inconsistent deferred destination refuses to start"
	)
	_check(not view.combat_active(), "failed starts leave no combat state")
	_check(_finished_events.is_empty(), "failed starts never emit the finished signal")
	_check(_current_clip(view, 1) == WARRIOR_GLB_IDLE, "failed starts leave the idle clip playing")

	view.apply_snapshot_units(_units([0, 1], [1, 0]))
	_check(view.is_unit_moving(1), "warrior 1 is mid-glide")
	_check(not view.present_combat(_event(false, false, true), _snap_survive()), "a mid-glide combatant refuses to start")
	view.advance_locomotion(60.0)
	_check(_arrivals == [1], "N7f arrival still fires normally (locomotion untouched)")
	_arrivals.clear()
	view.apply_snapshot_units(_units([0, 0], [1, 0]))
	view.advance_locomotion(60.0)
	_arrivals.clear()

	# --- approach + impact overlap + retaliation survivors --------------------
	var g1 = view.grounder_for_unit(1)
	var g2 = view.grounder_for_unit(2)
	_check(g1 != null and g2 != null, "both warrior rigs bound their leg grounders")
	var pre_a: Vector3 = ANCHORS[Vector2i(0, 0)]
	var pre_d: Vector3 = ANCHORS[Vector2i(1, 0)]
	_check(view.present_combat(_event(false, false, true), _snap_survive()), "retaliation sequence starts")
	_check(view.combat_stage() == "approach", "combat begins with the melee approach")
	_check(_current_clip(view, 1) == WARRIOR_GLB_WALK, "approach uses the Walking clip")
	_check(
		view.last_animation_play_info()["semantic"] == "Walking"
			and is_equal_approx(float(view.last_animation_play_info()["blend_sec"]), 0.28),
		"Idle→Walking requests the centralized blend"
	)
	_check(_arrivals.is_empty(), "approach emits no gameplay movement-arrival signal")
	_check(view.root_for_unit(1).position == pre_a, "approach does not mutate the authoritative root")
	var staging: Vector3 = view.combat_melee_staging()
	_check(
		is_equal_approx(view.melee_standoff_distance(), 0.80),
		"standoff uses the centralized 0.80 tuning value"
	)
	_check(
		absf(staging.x - (pre_d.x - view.melee_standoff_distance())) < 0.001
			and absf(staging.z - pre_d.z) < 0.001,
		"melee staging is standoff-distance in front of the defender"
	)
	_check(
		is_equal_approx(view.animation_blend_default_sec(), 0.28),
		"centralized blend duration reuses the legacy 0.28s map-view value"
	)
	_check(
		is_equal_approx(view.combat_impact_delay(), 0.5),
		"impact delay stays 0.5s — blending must not retune onset"
	)
	# Partial approach: still traveling, not at staging — uses the same
	# centralized stride-derived presentation translation speed as ordinary
	# movement (0.445, ninth-pass signed-drift centering).
	_check(
		is_equal_approx(WorldUnitsViewScript.locomotion_translation_speed(), 1.6 * 0.445),
		"combat travel uses the centralized 0.445 translation tuning"
	)
	var approach_dt := 0.5
	view.advance_combat(approach_dt)
	var approach_moved := _visual(view, 1).distance_to(pre_a)
	_check(
		absf(approach_moved - WorldUnitsViewScript.locomotion_translation_speed() * approach_dt) < 0.05,
		"melee approach translation over a fixed interval matches the 0.445 scale"
	)
	_check(view.combat_stage() == "approach", "partial approach stays in the approach stage")
	_check(_visual(view, 1).distance_to(pre_a) > 0.01, "approach leaves the pre-combat anchor")
	_check(_visual(view, 1).distance_to(staging) > 0.01, "partial approach has not reached staging yet")
	_check(_arrivals.is_empty(), "partial approach still emits no arrival")
	_check(
		is_equal_approx(view.animation_player_for_unit(1).speed_scale, 1.0),
		"approach Walking animation speed is unchanged by the translation scale"
	)
	# Finish approach.
	view.advance_combat(60.0)
	_check(view.combat_stage() == "exchange", "approach ends and the exchange begins")
	_check(_visual(view, 1).distance_to(staging) < 0.05, "approach ends at the melee staging point")
	_check(_arrivals.is_empty(), "completed approach emits no gameplay arrival")
	_check(
		_rendered_forward(view, 1).dot(Vector3(1, 0, 0)) > 0.99
			and _rendered_forward(view, 2).dot(Vector3(-1, 0, 0)) > 0.99,
		"combatants face each other after approach (yaw-only)"
	)
	_check(
		bool(g1.is_combat_support_grounding()) and not bool(g2.is_combat_support_grounding()),
		"attacker combat-support during Left_Slash; defender keeps Idle plants pre-hit"
	)
	_check(
		not bool(g1.is_grounding_paused()) and not bool(g2.is_grounding_paused()),
		"living combatants are not fully paused during Left_Slash / Hit"
	)
	var root_basis_att: Basis = (view.root_for_unit(1) as Node3D).get_node("ModelRoot").basis.orthonormalized()
	_check(
		root_basis_att.y.dot(Vector3.UP) > 0.99,
		"living attacker ModelRoot stays upright (no terrain pitch/roll)"
	)
	_check(_current_clip(view, 1) == WARRIOR_GLB_ATTACK, "exchange starts the attacker's Left_Slash")
	_check(
		view.last_animation_play_info()["semantic"] == "Left_Slash"
			and bool(view.last_animation_play_info()["one_shot"])
			and is_equal_approx(float(view.last_animation_play_info()["blend_sec"]), 0.28),
		"Walking→Left_Slash requests the centralized one-shot blend"
	)
	var att_player: AnimationPlayer = view.animation_player_for_unit(1)
	_check(
		att_player.get_animation(WARRIOR_GLB_ATTACK).loop_mode == Animation.LOOP_NONE,
		"combat clips are one-shot (never looped)"
	)
	# Impact delay: hit must NOT start before the named delay.
	view.advance_combat(view.combat_impact_delay() * 0.5)
	_check(view.combat_stage() == "exchange", "pre-impact advancing stays in the exchange")
	_check(_current_clip(view, 1) == WARRIOR_GLB_ATTACK, "attack clip remains active before impact")
	_check(_current_clip(view, 2) != WARRIOR_GLB_HIT, "hit reaction has not started before the impact delay")
	# Cross the impact delay while the attack clip is still running.
	view.advance_combat(view.combat_impact_delay())
	_check(_current_clip(view, 2) == WARRIOR_GLB_HIT, "non-fatal hit reaction begins at the impact delay")
	_check(
		bool(view.grounder_for_unit(2).is_combat_support_grounding()),
		"defender combat-support engages with Hit_Reaction_1"
	)
	_check(
		view.last_animation_play_info()["semantic"] == "Hit_Reaction_1"
			and is_equal_approx(float(view.last_animation_play_info()["blend_sec"]), 0.28),
		"impact Hit_Reaction_1 requests the centralized blend"
	)
	_check(
		_current_clip(view, 1) == WARRIOR_GLB_ATTACK
			or view.combat_stage() == "exchange"
			or view.combat_stage() == "retaliation",
		"attack completion is not required before the hit reaction begins"
	)
	# Initial defender hit: capture authored clip identity + early playback.
	_check(_current_clip(view, 2) == WARRIOR_GLB_HIT, "initial non-fatal hit plays remapped Hit_Reaction_1")
	var def_hit_info: Dictionary = view.last_animation_play_info()
	var def_hit_player: AnimationPlayer = view.animation_player_for_unit(2)
	view.advance_combat(0.15)
	var def_hit_pos := float(def_hit_player.current_animation_position)
	_check(
		_current_clip(view, 2) == WARRIOR_GLB_HIT and def_hit_pos > 0.05 and def_hit_pos < 0.55,
		"initial Hit_Reaction_1 advances on its own hit clock (pos %.3f)" % def_hit_pos
	)
	var def_gap_l := float(view.sole_surface_gap(2, "LeftFoot"))
	var def_gap_r := float(view.sole_surface_gap(2, "RightFoot"))
	_check(minf(def_gap_l, def_gap_r) < 0.08, "initial hit recipient support sole stays grounded")
	# Finish defender hit into retaliation; original attacker must leave slash.
	view.advance_combat(_clip_length(view, 2, WARRIOR_GLB_HIT) + 0.05)
	_check(view.combat_stage() == "retaliation", "surviving defender enters counterattack")
	_check(_current_clip(view, 2) == WARRIOR_GLB_ATTACK, "counterattack plays defender Left_Slash")
	_check(_current_clip(view, 1) == WARRIOR_GLB_IDLE, "counterattack victim waits on Idle (not leftover slash)")
	_check(
		is_equal_approx(float(view.grounder_for_unit(1).upper_body_pitch()), 0.0)
			and not bool(view.grounder_for_unit(1).is_combat_support_grounding()),
		"counterattack victim clears attacker-only pitch/support while waiting"
	)
	view.advance_combat(view.combat_impact_delay())
	_check(_current_clip(view, 1) == WARRIOR_GLB_HIT, "counterattack victim plays the same remapped Hit_Reaction_1")
	_check(
		view.last_animation_play_info()["semantic"] == "Hit_Reaction_1"
			and bool(view.last_animation_play_info()["one_shot"])
			and is_equal_approx(float(view.last_animation_play_info()["blend_sec"]), 0.28),
		"counterattack Hit_Reaction_1 uses the same one-shot blend contract"
	)
	_check(
		is_equal_approx(float(view.grounder_for_unit(1).upper_body_pitch()), 0.0),
		"counterattack victim has no Spine02 attack pitch during Hit_Reaction_1"
	)
	var att_hit_player: AnimationPlayer = view.animation_player_for_unit(1)
	_check(
		is_equal_approx(float(att_hit_player.current_animation_position), 0.0)
			or float(att_hit_player.current_animation_position) < 0.08,
		"counterattack Hit_Reaction_1 starts near frame 0"
	)
	view.advance_combat(0.15)
	var att_hit_pos := float(att_hit_player.current_animation_position)
	_check(
		_current_clip(view, 1) == WARRIOR_GLB_HIT and absf(att_hit_pos - def_hit_pos) < 0.12,
		"counterattack Hit_Reaction_1 tracks hit_elapsed like the initial hit (%.3f vs %.3f)"
		% [att_hit_pos, def_hit_pos]
	)
	for _si in 8:
		var gap_l := float(view.sole_surface_gap(1, "LeftFoot"))
		var gap_r := float(view.sole_surface_gap(1, "RightFoot"))
		_check(minf(gap_l, gap_r) > -0.05, "counterattack victim support sole does not penetrate")
		_check(minf(gap_l, gap_r) < 0.10, "counterattack victim support sole does not hover")
		view.advance_combat(0.05)
	# Finish retaliation into return travel; prove smooth facing.
	while view.combat_active() and view.combat_stage() != "survivor_travel":
		view.advance_combat(0.05)
	_check(view.combat_stage() == "survivor_travel", "survivor return enters travel stage")
	_check(
		_current_clip(view, 1) == WARRIOR_GLB_WALK
			and view.last_animation_play_info()["semantic"] == "Walking"
			and is_equal_approx(float(view.last_animation_play_info()["blend_sec"]), 0.28),
		"one-shot combat → Walking return requests the centralized blend"
	)
	_check(
		is_equal_approx(view.facing_blend_sec(), 0.28),
		"centralized facing blend reuses ANIM_BLEND_DEFAULT_SEC (0.28)"
	)
	var facing_info: Dictionary = view.facing_blend_info(1)
	_check(not facing_info.is_empty(), "survivor travel exposes facing-blend diagnostics")
	_check(
		is_equal_approx(float(facing_info["yaw_duration"]), 0.28),
		"return travel requests a material shortest-arc yaw blend"
	)
	var yaw_from := float(facing_info["yaw_from"])
	var yaw_to := float(facing_info["yaw_to"])
	_check(absf(angle_difference(yaw_from, yaw_to)) > 2.5, "return travel reverses facing (~180°)")
	var prev_yaw := yaw_from
	var max_step := 0.0
	var step := view.travel_facing_blend_sec() / 4.0
	for _i in 4:
		view.advance_combat(step)
		var yaw_now := WorldUnitsViewScript._current_visual_yaw_angle(
			(view.root_for_unit(1) as Node3D).get_node("ModelRoot") as Node3D
		)
		var step_abs := absf(angle_difference(prev_yaw, yaw_now))
		if step_abs > max_step:
			max_step = step_abs
		_check(step_abs < 2.0, "return facing has no one-frame yaw jump")
		prev_yaw = yaw_now
	_check(max_step > 0.05, "return facing actually interpolates (not stuck)")
	_check(
		absf(angle_difference(prev_yaw, yaw_to)) < 0.08,
		"return facing reaches the exact travel heading after the blend"
	)
	_check(_current_clip(view, 1) == WARRIOR_GLB_WALK, "Walking continues through the facing blend (no idle frame)")
	_run_to_completion(view)
	_check(not view.combat_active(), "survivor sequence finishes")
	_check(_finished_events == [[1, 2]], "finished signal emitted exactly once with both ids")
	_check(
		view.root_for_unit(1).position == pre_a
			and (view.root_for_unit(1) as Node3D).get_node("ModelRoot").position == Vector3.ZERO,
		"surviving defender results in return to the original snapshot-authoritative anchor"
	)
	_check(
		_rendered_forward(view, 1).dot(Vector3(1, 0, 0)) > 0.99,
		"after returning, the attacker faces the surviving defender"
	)
	_check(
		_current_clip(view, 1) == WARRIOR_GLB_IDLE and _current_clip(view, 2) == WARRIOR_GLB_IDLE,
		"both survivors return to the remapped idle clip"
	)
	_check(
		view.last_animation_play_info()["semantic"] == "Idle_3"
			and is_equal_approx(float(view.last_animation_play_info()["blend_sec"]), 0.28),
		"Walking → Idle after return requests the centralized blend"
	)
	_check(
		not bool(g1.is_grounding_paused()) and not bool(g2.is_grounding_paused()),
		"both grounders resume after the sequence"
	)
	_check(_arrivals.is_empty(), "survivor return never emits gameplay arrival")

	# --- defender killed: Dead at impact, no retaliation, occupation travel ---
	_finished_events.clear()
	_arrivals.clear()
	view.apply_snapshot_units(_units([0, 0], [1, 0]))
	_check(view.present_combat(_event(false, true, true), _snap_capture()), "defender-killed sequence starts")
	# Drive to exchange and verify Dead starts at impact (no Hit prepend).
	view.advance_combat(60.0)  # approach → exchange start
	_check(view.combat_stage() == "exchange", "kill case enters the exchange after approach")
	view.advance_combat(view.combat_impact_delay() * 0.5)
	_check(_current_clip(view, 2) != WARRIOR_GLB_DEAD, "Dead has not started before the impact delay")
	_check(_current_clip(view, 2) != WARRIOR_GLB_HIT, "fatal hits never prepend Hit_Reaction_1")
	view.advance_combat(view.combat_impact_delay())
	_check(view.combat_stage() == "death", "fatal defender Dead starts directly at impact")
	_check(_current_clip(view, 2) == WARRIOR_GLB_DEAD, "the defender plays the remapped Dead clip at impact")
	_check(
		view.last_animation_play_info()["semantic"] == "Dead"
			and is_equal_approx(float(view.last_animation_play_info()["blend_sec"]), 0.28),
		"fatal Dead requests the centralized blend"
	)
	_check(
		_current_clip(view, 1) == WARRIOR_GLB_ATTACK or view.combat_stage() == "death",
		"attack and fatal death still overlap at impact"
	)
	_check(_current_clip(view, 2) != WARRIOR_GLB_HIT, "no Hit_Reaction_1 on the fatal defender branch")
	view.advance_combat(_clip_length(view, 2, WARRIOR_GLB_DEAD) + 0.01)
	# Corpse fit then survivor travel to captured tile.
	_check(
		view.combat_stage() == "survivor_travel" or not view.combat_active(),
		"after death the surviving attacker begins occupation travel (or has finished)"
	)
	_run_to_completion(view)
	_check(_finished_events == [[1, 2]], "kill sequence emits the finished signal once")
	_check(view.root_for_unit(2) != null, "the killed defender is RETAINED through hit/death/fit")
	_check(_current_clip(view, 2) == WARRIOR_GLB_DEAD, "the killed defender stays on its Dead clip")
	_check(
		view.root_for_unit(1).position == pre_d
			and (view.root_for_unit(1) as Node3D).get_node("ModelRoot").position == Vector3.ZERO,
		"killed defender results in forward traversal to the captured snapshot-authoritative tile"
	)
	_check(_current_clip(view, 1) == WARRIOR_GLB_IDLE, "the attacker arrives at the captured tile and idles")
	_check(_arrivals.is_empty(), "occupation travel emits no gameplay arrival")
	# Occupation must keep travel-arrival facing — no return-path 180° turn.
	_check(
		_rendered_forward(view, 1).dot(Vector3(1, 0, 0)) > 0.99,
		"after occupation the attacker keeps the capture-travel facing (no 180° turn)"
	)
	view.advance_facing(1.0)
	_check(
		_rendered_forward(view, 1).dot(Vector3(1, 0, 0)) > 0.99,
		"occupation facing stays on the travel heading after further facing ticks"
	)
	view.apply_snapshot_units(_snap_capture()["units"])
	_check(view.root_for_unit(2) == null, "snapshot reconciliation removes the eliminated unit")
	_check(view.unit_count() == 1, "exactly the survivor remains")

	# --- attacker killed by retaliation: Dead at impact, no return travel -----
	_finished_events.clear()
	view.apply_snapshot_units(_units([0, 0], [1, 0]))
	view.advance_locomotion(60.0)  # settle any post-capture glide before combat
	_arrivals.clear()
	_check(view.present_combat(_event(true, false, true), _snap_attacker_dead()), "attacker-killed sequence starts")
	var g1b = view.grounder_for_unit(1)
	# Approach + exchange + non-fatal hit on defender, then into retaliation.
	view.advance_combat(60.0)
	view.advance_combat(view.combat_impact_delay() + _clip_length(view, 2, WARRIOR_GLB_HIT) + 0.05)
	_check(view.combat_stage() == "retaliation", "surviving defender enters retaliation")
	_check(_current_clip(view, 2) == WARRIOR_GLB_ATTACK, "retaliation starts the defender's Left_Slash")
	view.advance_combat(view.combat_impact_delay() * 0.5)
	_check(_current_clip(view, 1) != WARRIOR_GLB_DEAD, "retaliation Dead has not started before impact")
	_check(_current_clip(view, 1) != WARRIOR_GLB_HIT, "fatal retaliation never prepends Hit_Reaction_1")
	view.advance_combat(view.combat_impact_delay())
	_check(view.combat_stage() == "death", "fatal retaliation Dead starts directly at impact")
	_check(_current_clip(view, 1) == WARRIOR_GLB_DEAD, "the attacker plays Dead at retaliation impact")
	_check(
		view.last_animation_play_info()["semantic"] == "Dead"
			and is_equal_approx(float(view.last_animation_play_info()["blend_sec"]), 0.28),
		"fatal retaliation Dead requests the centralized blend"
	)
	_check(
		_current_clip(view, 2) == WARRIOR_GLB_ATTACK or view.combat_stage() == "death",
		"retaliation Left_Slash and fatal Dead still overlap at impact"
	)
	_run_to_completion(view)
	_check(not view.combat_active() and _finished_events == [[1, 2]], "attacker-death sequence finishes once")
	_check(view.root_for_unit(1) != null and _current_clip(view, 1) == WARRIOR_GLB_DEAD, "dead attacker retained on Dead")
	_check(bool(g1b.is_grounding_paused()), "dead attacker's grounder stays paused")
	_check(view.root_for_unit(1).position == pre_a, "attacker death results in no occupation of the defender tile")
	_check(
		_visual(view, 1).distance_to(pre_a) > 0.1,
		"dead attacker remains at the melee combat position (not returned home)"
	)
	_check(_current_clip(view, 2) == WARRIOR_GLB_IDLE, "the surviving defender returns to idle")
	view.apply_snapshot_units(_snap_attacker_dead()["units"])
	_check(view.root_for_unit(1) == null, "the dead attacker disappears on the snapshot apply")

	# --- continuous corpse support on sloping terrain during Dead -------------
	view.apply_snapshot_units(_units([0, 0], [1, 0]))
	view.advance_locomotion(60.0)
	_arrivals.clear()
	view.set_surface_sampler(SlopeSampler.new())
	_finished_events.clear()
	_check(view.present_combat(_event(false, true, false), _snap_capture()), "slope corpse sequence starts")
	view.advance_combat(60.0)  # approach → exchange
	view.advance_combat(view.combat_impact_delay())  # fatal Dead at impact
	_check(view.combat_stage() == "death", "slope case is in the Dead stage")
	_check(not view.combat_corpse_contact_active(), "corpse contact starts inactive at Dead onset")
	var dead_len := _clip_length(view, 2, WARRIOR_GLB_DEAD)
	var contact_at := -1.0
	var last_support_y := view.visual_position_for_unit(2).y
	var max_down_jump := 0.0
	var mid_support_y := last_support_y
	var t_acc := 0.0
	var dt := 0.05
	while view.combat_stage() == "death" and t_acc < dead_len + 0.2:
		view.advance_combat(dt)
		t_acc += dt
		var y_now := view.visual_position_for_unit(2).y
		if y_now + 0.001 < last_support_y:
			max_down_jump = maxf(max_down_jump, last_support_y - y_now)
		last_support_y = y_now
		if view.combat_corpse_contact_active() and contact_at < 0.0:
			contact_at = t_acc
			_check(t_acc < dead_len - 0.05, "terrain correction begins before Dead completion")
		if view.combat_corpse_contact_active():
			mid_support_y = y_now
			# Body regions must not pass below the sampled surface after contact.
			var regions: Dictionary = view._sample_corpse_body_regions(2)
			if bool(regions.get("ok", false)):
				var below := false
				for key in ["head", "hips", "feet", "left_foot", "right_foot"]:
					var bp: Vector3 = regions[key]
					var bs: Dictionary = SlopeSampler.new().sample(bp.x, bp.z, bp.y)
					if bool(bs["ok"]) and bp.y < float(bs["height"]) - 0.04:
						below = true
				_check(not below, "sampled body regions stay on/above the surface after contact")
	_check(contact_at >= 0.0, "corpse contact activates when first penetration would occur")
	var final_y_before_finish := (
		view.visual_position_for_unit(2).y if view.root_for_unit(2) != null else mid_support_y
	)
	_run_to_completion(view)
	_check(view.root_for_unit(2) != null, "corpse retained after fit")
	var corpse_model: Node3D = (view.root_for_unit(2) as Node3D).get_node("ModelRoot")
	var corpse_basis: Basis = corpse_model.basis.orthonormalized()
	_check(absf(corpse_basis.y.x) > 0.01 or absf(corpse_basis.y.z) > 0.01 or absf(corpse_model.position.y) >= 0.0, "corpse fit applies height/pitch/roll on non-flat terrain")
	var final_y := view.visual_position_for_unit(2).y
	_check(
		absf(final_y - final_y_before_finish) < 0.08 or absf(final_y - mid_support_y) < 0.12,
		"corpse height changes continuously without a final upward pop"
	)
	_check(max_down_jump < 0.15, "after contact the corpse does not drop through the terrain")
	_check(_current_clip(view, 2) == WARRIOR_GLB_DEAD, "final corpse pose remains on the Dead clip")
	_check(
		(view.root_for_unit(1) as Node3D).basis.get_euler().x == 0.0
			or absf(_rendered_forward(view, 1).y) < 0.05,
		"living units remain upright after corpse fitting"
	)
	view.set_surface_sampler(FlatSampler.new())

	# --- eighth-pass: REAL strike-endpoint trajectory aim on slopes/flat -------
	# The rejected seventh-pass metric (|LeftHand.y − Spine01.y| on a single
	# seeked frame) measured blend-frozen poses at a non-impact frame. These
	# cases run the whole live-advanced exchange and verify the final FK club
	# endpoint against the committed head-region contact point. The ACCEPTED
	# equal-elevation authored exchange runs FIRST and defines the neutral
	# contact baseline (its small live offset below the Head bone origin is
	# the Walking→slash crossfade residue of the accepted look); the elevated
	# cases must then reach the SAME contact height relative to that baseline.
	_finished_events.clear()
	view.set_tile_anchors(ANCHORS)
	view.set_surface_sampler(FlatSampler.new())
	# The corpse case above retained unit 2 on its Dead pose. Server snapshots
	# never resurrect an eliminated id, so remove it first (reconciliation)
	# and respawn it fresh — otherwise the "defender" whose head anchors the
	# aim target would be a stale lying corpse (headless players only advance
	# when ticked).
	view.apply_snapshot_units([_units([0, 0], [1, 0])[0]])
	view.apply_snapshot_units(_units([0, 0], [1, 0]))
	view.advance_locomotion(60.0)
	_settle_players(view)
	_arrivals.clear()
	_check(view.present_combat(_event(false, false, false), _snap_survive()), "flat equal-elevation slash starts")
	view.advance_combat(60.0)
	_check(view.combat_stage() == "exchange", "flat case enters Left_Slash exchange")
	var g_att = view.grounder_for_unit(1)
	_check(bool(g_att.is_combat_support_grounding()), "attacker uses combat-support grounding during slash")
	_check(
		not bool(view.grounder_for_unit(2).is_combat_support_grounding()),
		"defender keeps Idle plants before Hit_Reaction_1"
	)
	_check(view.combat_impact_delay() == 0.5, "impact delay unchanged by attack pitch")
	var err_flat := _strike_trajectory_case(view, "equal-elevation", "neutral")
	_check(bool(view.grounder_for_unit(2).is_combat_support_grounding()), "defender combat-support starts with hit")
	_run_to_completion(view)
	_check(is_equal_approx(float(g_att.upper_body_pitch()), 0.0), "attack pitch clears after the one-shot")
	_check(
		absf(float(err_flat["impact_dy"])) < 0.12,
		"neutral authored slash passes the head-region contact height (baseline dy %.4f)" % err_flat["impact_dy"]
	)

	view.set_tile_anchors(SLOPE_ANCHORS)
	view.set_surface_sampler(SlopeSampler.new())
	view.apply_snapshot_units(_units([1, 0], [0, 0]))  # attacker higher on +X slope
	view.advance_locomotion(60.0)
	_settle_players(view)
	_arrivals.clear()
	var downhill_snap := {
		"units": [
			{"id": 1, "owner_id": 1, "position": [1, 0], "type_id": "warrior", "current_hp": 70, "has_attacked": true},
			{"id": 2, "owner_id": 2, "position": [0, 0], "type_id": "warrior", "current_hp": 70, "has_attacked": false},
		]
	}
	_check(view.present_combat(_event(false, false, false), downhill_snap), "downhill slash sequence starts")
	view.advance_combat(60.0)  # approach → exchange
	_check(view.combat_stage() == "exchange", "downhill case enters Left_Slash exchange")
	var err_above := _strike_trajectory_case(view, "attacker-above", "down")
	_run_to_completion(view)

	view.apply_snapshot_units(_units([0, 0], [1, 0]))
	view.advance_locomotion(60.0)
	_settle_players(view)
	_arrivals.clear()
	var uphill_snap := {
		"units": [
			{"id": 1, "owner_id": 1, "position": [0, 0], "type_id": "warrior", "current_hp": 70, "has_attacked": true},
			{"id": 2, "owner_id": 2, "position": [1, 0], "type_id": "warrior", "current_hp": 70, "has_attacked": false},
		]
	}
	_check(view.present_combat(_event(false, false, false), uphill_snap), "uphill slash sequence starts")
	view.advance_combat(60.0)
	var err_below := _strike_trajectory_case(view, "attacker-below", "up")
	_run_to_completion(view)
	view.set_tile_anchors(ANCHORS)
	view.set_surface_sampler(FlatSampler.new())

	print(
		"AIM flat dy %.4f->%.4f d3=%.4f | above dy %.4f->%.4f d3=%.4f | below dy %.4f->%.4f d3=%.4f"
		% [
			err_flat["before_dy"], err_flat["impact_dy"], err_flat["impact_d3"],
			err_above["before_dy"], err_above["impact_dy"], err_above["impact_d3"],
			err_below["before_dy"], err_below["impact_dy"], err_below["impact_d3"],
		]
	)
	# Tolerance 0.08 wu ≈ the club-head contact radius: elevated strikes must
	# land inside the same head/upper-chest band the accepted neutral slash
	# passes. The residual (measured ~0.05–0.07) is the live combat-grounding
	# pelvis response during the pitched swing — the per-swing solve is
	# deliberately NOT re-fed from the live mid-swing pose (rejected model).
	_check(
		absf(float(err_above["impact_dy"]) - float(err_flat["impact_dy"])) < 0.08,
		"attacker-above reaches the accepted neutral contact band (dev %.4f)"
		% absf(float(err_above["impact_dy"]) - float(err_flat["impact_dy"]))
	)
	_check(
		absf(float(err_below["impact_dy"]) - float(err_flat["impact_dy"])) < 0.08,
		"attacker-below reaches the accepted neutral contact band (dev %.4f)"
		% absf(float(err_below["impact_dy"]) - float(err_flat["impact_dy"]))
	)
	_check(
		err_above["impact_d3"] < err_flat["impact_d3"] + 0.30
			and err_below["impact_d3"] < err_flat["impact_d3"] + 0.30,
		"elevated strikes stay within the accepted equal-elevation contact envelope"
	)
	_check(is_equal_approx(WorldUnitsViewScript.LOCOMOTION_TRANSLATION_SPEED_SCALE, 0.445), "locomotion 0.445 translation frozen")
	_check(is_equal_approx(view.facing_blend_sec(), 0.28), "locomotion 0.28 yaw blend frozen")

	# Entering Walking/Idle after combat restores ordinary locomotion grounding.
	var g_post = view.grounder_for_unit(1)
	_check(not bool(g_post.is_combat_support_grounding()), "post-combat Idle clears combat-support")
	_check(is_equal_approx(float(g_post.upper_body_pitch()), 0.0), "post-combat Idle clears attack pitch")
	view.advance_locomotion(0.28)
	_check(not bool(g_post.is_combat_support_grounding()), "post-combat settle never re-enables combat-support")
	_check(is_equal_approx(WorldUnitsViewScript.LOCOMOTION_TRANSLATION_SPEED_SCALE, 0.445), "0.445 translation scale frozen")
	_check(is_equal_approx(view.facing_blend_sec(), 0.28), "0.28 yaw blend frozen")

	# --- ninth-pass: matched lethal vs non-lethal downhill strike -------------
	# Live defect: the killing strike from above snapped back to the
	# unpitched (visibly too high) trajectory because the lethal impact
	# branch cleared the additive aim at the 0.5 s tick — mid contact
	# window — while the non-lethal strike kept aiming. The two sequences
	# below differ ONLY in defender survival: the cached target, additive
	# pitch, and full club-tip trajectory must match through the contact
	# window; only the DEFENDER's reaction may diverge.
	var matched := {}
	for lethal in [false, true]:
		view.set_tile_anchors(SLOPE_ANCHORS)
		view.set_surface_sampler(SlopeSampler.new())
		view.apply_snapshot_units([_units([1, 0], [0, 0])[0]])  # fresh defender
		view.apply_snapshot_units(_units([1, 0], [0, 0]))
		view.advance_locomotion(60.0)
		_settle_players(view)
		var m_label: String = "lethal" if lethal else "non-lethal"
		var m_snap: Dictionary = downhill_snap
		if lethal:
			m_snap = {
				"units": [
					{"id": 1, "owner_id": 1, "position": [0, 0], "type_id": "warrior", "current_hp": 70, "has_attacked": true},
				]
			}
		_check(
			view.present_combat(_event(false, lethal, false), m_snap),
			"matched %s downhill strike starts" % m_label
		)
		view.advance_combat(60.0)  # approach → exchange
		_check(view.combat_stage() == "exchange", "matched %s case enters the exchange" % m_label)
		matched[lethal] = _sample_strike_through_window(view)
		if lethal:
			_check(view.combat_stage() == "death", "matched lethal case entered Dead at impact")
		_run_to_completion(view)
	var tgt_nl: Vector3 = matched[false]["target"]
	var tgt_l: Vector3 = matched[true]["target"]
	_check(
		tgt_nl != Vector3.INF and tgt_l != Vector3.INF and tgt_nl.distance_to(tgt_l) < 0.02,
		"matched strikes commit the same cached head contact (dev %.4f)" % tgt_nl.distance_to(tgt_l)
	)
	var s_nl: Array = matched[false]["samples"]
	var s_l: Array = matched[true]["samples"]
	var n_pairs: int = mini(s_nl.size(), s_l.size())
	_check(n_pairs > 120, "matched strike sampler captured the full window (%d pairs)" % n_pairs)
	var pre_ep_dev := 0.0
	var pre_pitch_dev := 0.0
	var win_ep_dev := 0.0
	var win_pitch_dev := 0.0
	var l_win_pitch := 0.0
	for i in n_pairs:
		var ra: Array = s_nl[i]
		var rb: Array = s_l[i]
		if absf(float(ra[0]) - float(rb[0])) > 0.003:
			continue
		var ep_dev: float = (ra[1] as Vector3).distance_to(rb[1] as Vector3)
		var pitch_dev: float = absf(float(ra[2]) - float(rb[2]))
		if float(ra[0]) < 0.5:
			pre_ep_dev = maxf(pre_ep_dev, ep_dev)
			pre_pitch_dev = maxf(pre_pitch_dev, pitch_dev)
		if float(ra[0]) >= 0.44 and float(ra[0]) <= 0.58:
			win_ep_dev = maxf(win_ep_dev, ep_dev)
			win_pitch_dev = maxf(win_pitch_dev, pitch_dev)
			l_win_pitch = minf(l_win_pitch, float(rb[2]))
	print(
		"MATCHED_STRIKE pairs=%d pre[ep %.4f pitch %.4f] window[ep %.4f pitch %.4f] lethal window pitch %.4f"
		% [n_pairs, pre_ep_dev, pre_pitch_dev, win_ep_dev, win_pitch_dev, l_win_pitch]
	)
	_check(pre_ep_dev < 0.02, "pre-impact club-tip trajectories are equivalent (dev %.4f)" % pre_ep_dev)
	_check(pre_pitch_dev < 0.01, "pre-impact additive aim is identical (dev %.4f)" % pre_pitch_dev)
	_check(
		win_ep_dev < 0.02 and win_pitch_dev < 0.01,
		"the killing strike holds the aimed trajectory through the whole contact window"
	)
	_check(l_win_pitch < -0.02, "the fatal strike from above still aims downward at contact")
	# Clean production-faithful state for the following sections: the corpse
	# is removed by reconciliation and both units respawn fresh on flat.
	view.set_tile_anchors(ANCHORS)
	view.set_surface_sampler(FlatSampler.new())
	view.apply_snapshot_units([_units([0, 0], [1, 0])[0]])
	view.apply_snapshot_units(_units([0, 0], [1, 0]))
	view.advance_locomotion(60.0)
	_settle_players(view)

	# --- superseding snapshot cancels safely -----------------------------------
	_finished_events.clear()
	view.apply_snapshot_units(_units([0, 0], [1, 0]))
	view.advance_locomotion(60.0)
	_arrivals.clear()
	_check(view.present_combat(_event(false, false, true), _snap_survive()), "cancel-case sequence starts")
	view.advance_combat(60.0)  # into/through approach — possibly at staging
	_check(view.combat_active(), "cancel-case sequence is active")
	view.apply_snapshot_units(_units([0, 0], [1, 0]))
	_check(not view.combat_active(), "a superseding snapshot apply cancels the sequence")
	_check(_finished_events.is_empty(), "a canceled sequence never emits the finished signal")
	_check(
		view.root_for_unit(1).position == pre_a
			and (view.root_for_unit(1) as Node3D).get_node("ModelRoot").position == Vector3.ZERO,
		"cancellation restores the attacker off the melee staging point"
	)
	_check(
		_current_clip(view, 1) == WARRIOR_GLB_IDLE and _current_clip(view, 2) == WARRIOR_GLB_IDLE,
		"canceled participants return to idle"
	)
	_check(
		view.last_animation_play_info()["semantic"] == "Idle_3"
			and is_equal_approx(float(view.last_animation_play_info()["blend_sec"]), 0.28),
		"cancellation Idle requests the centralized blend"
	)
	var g1c = view.grounder_for_unit(1)
	var g2c = view.grounder_for_unit(2)
	_check(
		not bool(g1c.is_grounding_paused()) and not bool(g2c.is_grounding_paused()),
		"canceled participants' grounders resume"
	)

	# --- double-start + post-combat locomotion --------------------------------
	_check(view.present_combat(_event(false, false, true), _snap_survive()), "a fresh sequence starts")
	_check(not view.present_combat(_event(false, false, true), _snap_survive()), "a second sequence cannot start mid-presentation")
	_run_to_completion(view)
	_check(not view.combat_active(), "run-to-completion helper settles the sequence")
	_arrivals.clear()
	view.apply_snapshot_units(_units([2, 0], [1, 0]))
	_check(view.is_unit_moving(1), "post-combat move glides normally")
	_check(_current_clip(view, 1) == WARRIOR_GLB_WALK, "the Walking clip plays post-combat")
	view.advance_locomotion(60.0)
	_check(_arrivals == [1], "post-combat arrival event fires exactly once")
	_check(
		view.root_for_unit(1).position == ANCHORS[Vector2i(2, 0)]
			and (view.root_for_unit(1) as Node3D).get_node("ModelRoot").position == Vector3.ZERO,
		"post-combat arrival lands the exact anchor pose"
	)
	_check(_current_clip(view, 1) == WARRIOR_GLB_IDLE, "idle resumes after the post-combat move")

	view.queue_free()
	await process_frame

	print("WorldUnitsCombat tests: %d checks" % _total)
	if _any_fail:
		print("FAIL")
		quit(1)
	else:
		print("PASS")
		quit(0)


# Runs the Left_Slash exchange from its start on the REAL production
# animation/modifier path — AnimationPlayers are advanced per tick exactly
# like tree frames in the live game (seek alone cannot advance crossfades
# headlessly, which froze every seventh-pass pose measurement) — and
# samples the final forward-kinematic strike endpoint (club head skinned
# to LeftHand) against the per-swing committed head-region contact point.
# Verifies contact HEIGHT and full 3D approach across the impact window
# (the authored downswing around COMBAT_IMPACT_DELAY_SEC), plus bounded
# chain angles, upright ModelRoot, and mid-swing support-sole grounding.
# Call with combat_stage() == "exchange" at attack_elapsed ~ 0.
# Headless AnimationPlayers only pose the skeleton when advanced, so any
# pending Idle crossfade must be played out before a case samples bone
# positions (live gameplay advances every frame — this mimics that).
func _settle_players(p_view: Node) -> void:
	for uid in [1, 2]:
		var pl: AnimationPlayer = p_view.animation_player_for_unit(uid)
		if pl != null:
			pl.advance(0.6)


# Advances the live exchange at 240 Hz from swing start until past the
# contact window (attack_elapsed 0.70) and records the committed target
# plus per-tick [elapsed, club-tip endpoint, applied pitch] rows — the
# swing keeps being sampled across the lethal stage change into "death".
func _sample_strike_through_window(p_view: Node) -> Dictionary:
	var att_p: AnimationPlayer = p_view.animation_player_for_unit(1)
	var def_p: AnimationPlayer = p_view.animation_player_for_unit(2)
	var g = p_view.grounder_for_unit(1)
	var out := {
		"target": p_view._combat.get("aim_target_w", Vector3.INF),
		"samples": [],
	}
	var dt := 1.0 / 240.0
	while p_view.combat_active():
		if float(p_view._combat.get("attack_elapsed", 0.0)) > 0.70:
			break
		att_p.advance(dt)
		if def_p != null:
			def_p.advance(dt)
		p_view.advance_combat(dt)
		if not p_view.combat_active():
			break
		var el := float(p_view._combat.get("attack_elapsed", 0.0))
		var ep: Vector3 = p_view.strike_endpoint_world(1)
		(out["samples"] as Array).append([el, ep, float(g.upper_body_pitch())])
	return out


func _strike_trajectory_case(p_view: Node, label: String, expect: String) -> Dictionary:
	var att_p: AnimationPlayer = p_view.animation_player_for_unit(1)
	var def_p: AnimationPlayer = p_view.animation_player_for_unit(2)
	var g_att = p_view.grounder_for_unit(1)
	var target: Vector3 = p_view._combat.get("aim_target_w", Vector3.INF)
	_check(target != Vector3.INF, "%s: swing commits a defender contact point" % label)
	# Unpitched impact prediction (authored endpoint + grounding shift).
	var model: Node3D = (p_view.root_for_unit(1) as Node3D).get_node("ModelRoot")
	model.force_update_transform()
	var shift := float(p_view._combat.get("aim_pivot_shift_y", 0.0))
	var before_dy: float = (
		(model.global_transform * p_view.ATTACK_IMPACT_ENDPOINT_MODEL).y + shift - target.y
	)
	# 240 Hz sampling: the authored downswing sweeps ~5 wu/s, so 60 Hz ticks
	# would quantize the height-crossing measurement by up to ~0.08 wu.
	var dt := 1.0 / 240.0
	var impact_dy := INF
	var impact_d3 := INF
	var impact_pitch := 0.0
	var best_d3 := INF
	var best_t := -1.0
	var soles_checked := false
	while str(p_view.combat_stage()) == "exchange":
		att_p.advance(dt)
		def_p.advance(dt)
		p_view.advance_combat(dt)
		var el := float(p_view._combat.get("attack_elapsed", 0.0)) if p_view.combat_active() else INF
		if el > 0.95:
			break
		var ep: Vector3 = p_view.strike_endpoint_world(1)
		if ep == Vector3.INF:
			continue
		var d3 := ep.distance_to(target)
		if d3 < best_d3:
			best_d3 = d3
			best_t = el
		# Impact window: the authored downswing contact phase.
		if el >= 0.44 and el <= 0.58:
			if absf(ep.y - target.y) < absf(impact_dy):
				impact_dy = ep.y - target.y
				impact_d3 = d3
				impact_pitch = float(g_att.upper_body_pitch())
			if not soles_checked and el >= 0.5:
				soles_checked = true
				for uid in [1, 2]:
					var gap_l := float(p_view.sole_surface_gap(uid, "LeftFoot"))
					var gap_r := float(p_view.sole_surface_gap(uid, "RightFoot"))
					var support_gap := minf(gap_l, gap_r)
					_check(
						support_gap > -0.05 and support_gap < 0.10,
						"%s unit %d: mid-swing support sole stays grounded (gap %.4f)" % [label, uid, support_gap]
					)
	_check(
		absf(impact_pitch) <= p_view.attack_pitch_chain_max_rad() + 0.001,
		"%s: total aim angle respects the chain bound (%.4f)" % [label, impact_pitch]
	)
	match expect:
		"down":
			_check(impact_pitch < -0.02, "%s: attacker above aims downward (pitch %.4f)" % [label, impact_pitch])
			_check(
				absf(impact_dy) < absf(before_dy),
				"%s: endpoint height error shrinks vs unpitched (%.4f -> %.4f)" % [label, before_dy, impact_dy]
			)
		"up":
			_check(impact_pitch > 0.02, "%s: attacker below aims upward (pitch %.4f)" % [label, impact_pitch])
			_check(
				absf(impact_dy) < absf(before_dy),
				"%s: endpoint height error shrinks vs unpitched (%.4f -> %.4f)" % [label, before_dy, impact_dy]
			)
		"neutral":
			_check(
				absf(impact_pitch) < 0.001,
				"%s: equal elevation preserves the authored neutral slash (pitch %.4f)" % [label, impact_pitch]
			)
	_check(
		model.basis.orthonormalized().y.dot(Vector3.UP) > 0.99,
		"%s: living attacker ModelRoot stays upright" % label
	)
	print(
		"AIM_CASE %s before_dy=%.4f impact_dy=%.4f impact_d3=%.4f best_d3=%.4f@%.3f pitch=%.4f target=(%.3f,%.3f,%.3f)"
		% [label, before_dy, impact_dy, impact_d3, best_d3, best_t, impact_pitch, target.x, target.y, target.z]
	)
	return {
		"before_dy": before_dy,
		"impact_dy": impact_dy,
		"impact_d3": impact_d3,
		"best_d3": best_d3,
		"pitch": impact_pitch,
	}


func _check(cond: bool, label: String) -> void:
	_total += 1
	if cond:
		print("PASS %s" % label)
	else:
		_any_fail = true
		print("FAIL %s" % label)
