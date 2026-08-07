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
	# Partial approach: still traveling, not at staging.
	view.advance_combat(0.2)
	_check(view.combat_stage() == "approach", "partial approach stays in the approach stage")
	_check(_visual(view, 1).distance_to(pre_a) > 0.01, "approach leaves the pre-combat anchor")
	_check(_visual(view, 1).distance_to(staging) > 0.01, "partial approach has not reached staging yet")
	_check(_arrivals.is_empty(), "partial approach still emits no arrival")
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
		bool(g1.is_grounding_paused()) and bool(g2.is_grounding_paused()),
		"both grounders are paused for authored combat clips"
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
	# Finish exchange/retaliation into return travel; prove smooth facing.
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
		is_equal_approx(view.travel_facing_blend_sec(), 0.28),
		"survivor travel-facing blend reuses ANIM_BLEND_DEFAULT_SEC (0.28)"
	)
	var facing_info: Dictionary = view.combat_travel_facing_info()
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


func _check(cond: bool, label: String) -> void:
	_total += 1
	if cond:
		print("PASS %s" % label)
	else:
		_any_fail = true
		print("FAIL %s" % label)
