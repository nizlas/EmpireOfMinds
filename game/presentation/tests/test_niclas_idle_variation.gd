# Headless: Niclas weighted idle variation (presentation-only; seeded RNG for tests).
extends SceneTree

const Experiment = preload("res://presentation/warrior_3d_unit_experiment.gd")
const IdleVariationScript = preload("res://presentation/unit_3d_idle_variation.gd")
const UnitWorldScript = preload("res://presentation/unit_3d_world_view.gd")
const MapLayerScript = preload("res://presentation/map_presentation_3d_layer.gd")
const CityWorldScript = preload("res://presentation/city_3d_world_view.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const MapCameraScript = preload("res://presentation/map_camera.gd")
const MapPlaneProjectionScript = preload("res://presentation/map_plane_projection.gd")

const MAP_LAYER_ORIGIN: Vector2 = Vector2(400.0, 428.0)
const NICLAS_UNIT_ID: int = ScenarioScript.DEBUG_NICLAS_UNIT_ID
const FEET_DELTA_TOL_PX: float = 12.0

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	OS.set_environment(Experiment.ENV_FLAG, "1")
	OS.set_environment(Experiment.ENV_REAL_3D_UNITS, "1")
	call_deferred("_run")


func _run() -> void:
	_test_config_and_weights()
	_test_seeded_rng_branches()
	_test_state_machine_rules()
	_test_arrival_chooser_flow()
	_test_stale_generation_guard()
	await _test_integration_with_unit_world()
	if _failures > 0:
		push_error("test_niclas_idle_variation: %d failures / %d checks" % [_failures, _checks])
		quit(1)
	print("test_niclas_idle_variation: %d checks, all ok" % _checks)
	quit(0)


func _test_config_and_weights() -> void:
	_check(IdleVariationScript.has_variation("niclas"), "niclas has idle variation config")
	_check(not IdleVariationScript.has_variation("warrior"), "warrior has no idle variation")
	_check(not IdleVariationScript.has_variation("settler"), "settler has no idle variation")
	var variants: Array = IdleVariationScript.niclas_weighted_variants()
	_check(variants.size() == 2, "niclas has two weighted variants")
	var idle_weight: float = 0.0
	var kick_weight: float = 0.0
	var i: int = 0
	while i < variants.size():
		var clip: String = str(variants[i].get("clip", ""))
		var weight: float = float(variants[i].get("weight", 0.0))
		if clip == IdleVariationScript.CLIP_IDLE_3:
			idle_weight = weight
		elif clip == IdleVariationScript.CLIP_FLYING_FIST_KICK:
			kick_weight = weight
		i += 1
	_check(is_equal_approx(idle_weight, 1.0), "Idle_3 weight is 1.0")
	_check(is_equal_approx(kick_weight, 1.0), "Flying_Fist_Kick weight is 1.0")
	_check(is_equal_approx(idle_weight, kick_weight), "explicit 50/50 equal weights")
	var cfg: Dictionary = IdleVariationScript.config_for_type("niclas")
	_check(
		is_equal_approx(float(cfg.get("blend_to_flourish_sec", -1.0)), 0.15),
		"blend Idle_3 to kick is 0.15s",
	)
	_check(
		is_equal_approx(float(cfg.get("blend_to_recovery_sec", -1.0)), 0.30),
		"blend kick to Idle_3 is 0.30s",
	)
	_check(
		is_equal_approx(IdleVariationScript.NICLAS_RECOVERY_IDLE_CAP_SEC, 1.5),
		"post-kick recovery cap is 1.5s",
	)
	_check(
		is_equal_approx(
			IdleVariationScript.logical_length_for_phase(
				IdleVariationScript.PHASE_RECOVERY_IDLE,
				IdleVariationScript.CLIP_IDLE_3,
				9.966666,
			),
			1.5,
		),
		"recovery_idle uses capped stabilization duration",
	)
	_check(
		is_equal_approx(
			IdleVariationScript.logical_length_for_phase(
				IdleVariationScript.PHASE_NORMAL_IDLE,
				IdleVariationScript.CLIP_IDLE_3,
				9.966666,
			),
			9.966666,
		),
		"normal_idle uses full imported clip duration",
	)


func _test_arrival_chooser_flow() -> void:
	var cfg: Dictionary = IdleVariationScript.config_for_type("niclas")
	IdleVariationScript.test_rng_seed_base = 5000
	var state: Dictionary = IdleVariationScript.make_state(ScenarioScript.DEBUG_NICLAS_UNIT_ID)
	state["phase"] = IdleVariationScript.PHASE_FLOURISH
	state["current_clip"] = IdleVariationScript.CLIP_FLYING_FIST_KICK
	IdleVariationScript.interrupt_for_movement(state)
	_check(
		str(state.get("phase", "")) == IdleVariationScript.PHASE_MOVING,
		"walk interrupt leaves moving phase until arrival",
	)
	IdleVariationScript.restart_after_arrival(state)
	_check(
		str(state.get("phase", "")) == IdleVariationScript.PHASE_CHOOSING,
		"arrival enters chooser phase (not recovery_idle)",
	)
	var first_after_arrival: Dictionary = IdleVariationScript.choose_from_chooser(state, cfg)
	_check(not first_after_arrival.is_empty(), "arrival chooser returns a clip")
	_check(
		str(state.get("phase", "")) != IdleVariationScript.PHASE_RECOVERY_IDLE,
		"first post-walk clip is not forced recovery_idle",
	)
	_check(
		str(first_after_arrival.get("clip", ""))
			in [IdleVariationScript.CLIP_IDLE_3, IdleVariationScript.CLIP_FLYING_FIST_KICK],
		"arrival chooser picks Idle_3 or kick",
	)
	var kick_unit_id: int = -1
	var sweep: int = 0
	while sweep < 256:
		var st: Dictionary = IdleVariationScript.make_state(sweep)
		IdleVariationScript.interrupt_for_movement(st)
		IdleVariationScript.restart_after_arrival(st)
		var spec: Dictionary = IdleVariationScript.choose_from_chooser(st, cfg)
		if str(spec.get("clip", "")) == IdleVariationScript.CLIP_FLYING_FIST_KICK:
			kick_unit_id = sweep
			break
		sweep += 1
	_check(kick_unit_id >= 0, "seeded RNG can select kick as first post-walk animation")
	var not_always_idle: bool = false
	sweep = 0
	while sweep < 64:
		var st2: Dictionary = IdleVariationScript.make_state(200 + sweep)
		IdleVariationScript.restart_after_arrival(st2)
		var spec2: Dictionary = IdleVariationScript.choose_from_chooser(st2, cfg)
		if str(spec2.get("clip", "")) == IdleVariationScript.CLIP_FLYING_FIST_KICK:
			not_always_idle = true
			break
		sweep += 1
	_check(not_always_idle, "arrival does not always start Idle_3")
	IdleVariationScript.test_rng_seed_base = -1


func _test_seeded_rng_branches() -> void:
	IdleVariationScript.test_rng_seed_base = 1000
	var variants: Array = IdleVariationScript.niclas_weighted_variants()
	var found_idle: bool = false
	var found_kick: bool = false
	var trial: int = 0
	while trial < 32:
		var st: Dictionary = IdleVariationScript.make_state(trial)
		var pick: Dictionary = IdleVariationScript.pick_weighted_variant(
			st["rng"] as RandomNumberGenerator,
			variants,
		)
		var clip: String = str(pick.get("clip", ""))
		if clip == IdleVariationScript.CLIP_IDLE_3:
			found_idle = true
		elif clip == IdleVariationScript.CLIP_FLYING_FIST_KICK:
			found_kick = true
		trial += 1
	_check(found_idle, "seeded RNG can pick Idle_3")
	_check(found_kick, "seeded RNG can pick Flying_Fist_Kick")
	var idle_count: int = 0
	var kick_count: int = 0
	var sweep_i: int = 0
	while sweep_i < 200:
		var st: Dictionary = IdleVariationScript.make_state(100 + sweep_i)
		var pick: Dictionary = IdleVariationScript.pick_weighted_variant(
			st["rng"] as RandomNumberGenerator,
			variants,
		)
		var clip: String = str(pick.get("clip", ""))
		if clip == IdleVariationScript.CLIP_IDLE_3:
			idle_count += 1
		elif clip == IdleVariationScript.CLIP_FLYING_FIST_KICK:
			kick_count += 1
		sweep_i += 1
	_check(idle_count > 40 and kick_count > 40, "seed sweep exercises both branches")
	IdleVariationScript.test_rng_seed_base = -1


func _test_state_machine_rules() -> void:
	var cfg: Dictionary = IdleVariationScript.config_for_type("niclas")
	var state: Dictionary = IdleVariationScript.make_state(0)
	state["phase"] = IdleVariationScript.PHASE_FLOURISH
	state["current_clip"] = IdleVariationScript.CLIP_FLYING_FIST_KICK
	var recovery: Dictionary = IdleVariationScript.next_after_complete(state, cfg)
	_check(
		str(recovery.get("clip", "")) == IdleVariationScript.CLIP_IDLE_3,
		"flourish always recovers through Idle_3",
	)
	_check(
		str(state.get("phase", "")) == IdleVariationScript.PHASE_RECOVERY_IDLE,
		"recovery_idle phase after kick",
	)
	_check(
		is_equal_approx(float(recovery.get("blend_sec", 0.0)), 0.30),
		"kick recovery blend is 0.30s",
	)
	IdleVariationScript.mark_clip_started(state, IdleVariationScript.CLIP_IDLE_3, 1.0)
	state["clip_elapsed_sec"] = 1.0
	var after_recovery: Dictionary = IdleVariationScript.next_after_complete(state, cfg)
	_check(not after_recovery.is_empty(), "recovery_idle completes into new choose")
	_check(
		str(after_recovery.get("clip", "")) != ""
			or str(state.get("phase", "")) in [
				IdleVariationScript.PHASE_NORMAL_IDLE,
				IdleVariationScript.PHASE_FLOURISH,
			],
		"post-recovery re-chooses idle variant",
	)
	if str(after_recovery.get("clip", "")) == IdleVariationScript.CLIP_FLYING_FIST_KICK:
		_check(
			str(state.get("phase", "")) == IdleVariationScript.PHASE_FLOURISH,
			"kick only after explicit choose (never kick-to-kick)",
		)
	# Simulate kick->recovery->choose kick path: must pass through recovery Idle_3 first.
	state = IdleVariationScript.make_state(1)
	state["phase"] = IdleVariationScript.PHASE_FLOURISH
	var step_recovery: Dictionary = IdleVariationScript.next_after_complete(state, cfg)
	_check(str(step_recovery.get("clip", "")) == IdleVariationScript.CLIP_IDLE_3, "no kick chain skip")


func _test_stale_generation_guard() -> void:
	var state: Dictionary = IdleVariationScript.make_state(9)
	var gen_before: int = int(state.get("generation", 0))
	IdleVariationScript.mark_clip_started(state, IdleVariationScript.CLIP_IDLE_3, 1.0)
	state["clip_elapsed_sec"] = 1.0
	IdleVariationScript.interrupt_for_movement(state)
	_check(int(state.get("generation", 0)) == gen_before + 1, "movement bumps generation")
	_check(str(state.get("phase", "")) == IdleVariationScript.PHASE_MOVING, "movement sets moving phase")
	_check(not IdleVariationScript.is_clip_logically_complete(state), "interrupted clip cleared")
	var cfg: Dictionary = IdleVariationScript.config_for_type("niclas")
	var stale_next: Dictionary = IdleVariationScript.next_after_complete(state, cfg)
	_check(stale_next.is_empty() or str(state.get("phase", "")) == IdleVariationScript.PHASE_MOVING, "moving phase blocks flourish recovery")


func _test_integration_with_unit_world() -> void:
	IdleVariationScript.test_rng_seed_base = 5000
	var root := Node.new()
	get_root().add_child(root)
	var layout = HexLayoutScript.new()
	var scenario = ScenarioScript.with_debug_character_units(
		ScenarioScript.make_tiny_test_scenario()
	)
	var layer = MapLayerScript.new()
	root.add_child(layer)
	layer.real_3d_units_enabled = true
	layer.layout = layout
	layer.scenario = scenario
	layer.map_layer_origin = MAP_LAYER_ORIGIN
	var projection = MapPlaneProjectionScript.new()
	projection.vanishing_pres = (get_root().get_visible_rect().size * 0.5) - MAP_LAYER_ORIGIN
	var map_camera = MapCameraScript.new()
	map_camera.projection = projection
	layer.map_camera = map_camera
	await process_frame
	layer.sync_from_scenario()
	layer.prepare_for_draw()
	await process_frame
	var unit_world: Unit3DWorldView = layer._unit_world_view
	_check(unit_world != null, "Unit3DWorldView present for integration")
	_check(unit_world.has_ready_unit_instance(NICLAS_UNIT_ID), "Niclas instance ready")
	var niclas_inst: Node3D = unit_world._instance_by_unit_id[NICLAS_UNIT_ID] as Node3D
	_check(niclas_inst != null, "Niclas instance node")
	_check(unit_world._idle_variation_by_unit_id.has(NICLAS_UNIT_ID), "Niclas idle variation state exists")
	var state_a: Dictionary = unit_world._idle_variation_state(NICLAS_UNIT_ID)
	var state_other: Dictionary = IdleVariationScript.make_state(NICLAS_UNIT_ID + 100)
	_check(
		(state_other["rng"] as RandomNumberGenerator).seed
			!= (state_a["rng"] as RandomNumberGenerator).seed,
		"distinct unit ids get distinct RNG seeds under test base",
	)
	var anchor_before: Vector2 = CityWorldScript.compute_anchor_2d(
		layout.hex_to_world(0, 1),
		map_camera,
		MAP_LAYER_ORIGIN,
	)
	var global_before: Vector3 = niclas_inst.global_position
	# prepare_for_draw must advance idle without relying on _process alone.
	unit_world.set_process(false)
	layer.prepare_for_draw()
	await process_frame
	var player: AnimationPlayer = unit_world._animation_player_for_root(niclas_inst)
	_check(player != null, "Niclas AnimationPlayer present")
	if player != null:
		_check(player.is_playing(), "Niclas plays idle immediately after prepare_for_draw")
		var playing_clip: String = str(player.current_animation)
		_check(
			playing_clip == IdleVariationScript.CLIP_IDLE_3
				or playing_clip == IdleVariationScript.CLIP_FLYING_FIST_KICK,
			"idle variation plays Idle_3 or kick clip on startup",
		)
		var idle_anim: Animation = player.get_animation(IdleVariationScript.CLIP_IDLE_3)
		if idle_anim != null:
			_check(
				IdleVariationScript.is_import_loop_linear(idle_anim)
					or idle_anim.length > 0.0,
				"Idle_3 import loop metadata readable",
			)
	for _frame in range(8):
		layer.prepare_for_draw()
		await process_frame
	if player != null:
		_check(player.is_playing(), "no stationary gap: AnimationPlayer still playing")
	var feet_before_move: Vector2 = UnitWorldScript.projected_mesh_feet_2d(
		layer._world_camera,
		niclas_inst,
	)
	_check(
		feet_before_move.distance_to(anchor_before) < FEET_DELTA_TOL_PX,
		"idle tick keeps feet near anchor",
	)
	_check(
		niclas_inst.global_position.is_equal_approx(global_before),
		"idle animation does not drift unit root before movement",
	)
	var gen_before_move: int = int(unit_world._idle_variation_state(NICLAS_UNIT_ID).get("generation", 0))
	unit_world.begin_hex_move(NICLAS_UNIT_ID, "niclas", 0, 1, -1, 1)
	_check(unit_world.is_unit_hex_move_active(NICLAS_UNIT_ID), "movement cancels idle and starts walk")
	var gen_after_move: int = int(unit_world._idle_variation_state(NICLAS_UNIT_ID).get("generation", 0))
	_check(gen_after_move > gen_before_move, "movement bumps idle generation")
	_check(
		str(unit_world._idle_variation_state(NICLAS_UNIT_ID).get("phase", ""))
			== IdleVariationScript.PHASE_MOVING,
		"idle phase is moving during hex move",
	)
	if player != null:
		_check(
			str(player.current_animation) == "Walking",
			"movement plays Walking clip",
		)
	var stride_sec: float = unit_world._hex_move_stride_anim_sec("niclas")
	var move: Dictionary = unit_world._active_hex_moves[NICLAS_UNIT_ID]
	move["progress"] = 1.0
	move["anim_elapsed_sec"] = stride_sec
	unit_world._active_hex_moves[NICLAS_UNIT_ID] = move
	unit_world._tick_hex_moves(0.0)
	layer.prepare_for_draw()
	await process_frame
	_check(not unit_world.is_unit_hex_move_active(NICLAS_UNIT_ID), "move completes")
	var post_arrival_phase: String = str(
		unit_world._idle_variation_state(NICLAS_UNIT_ID).get("phase", "")
	)
	_check(
		post_arrival_phase != IdleVariationScript.PHASE_RECOVERY_IDLE,
		"arrival does not enter recovery_idle before first random choice",
	)
	_check(
		post_arrival_phase
			in [
				IdleVariationScript.PHASE_NORMAL_IDLE,
				IdleVariationScript.PHASE_FLOURISH,
			],
		"arrival immediately plays chosen idle or kick (not chooser stall)",
	)
	_check(gen_after_move < int(unit_world._idle_variation_state(NICLAS_UNIT_ID).get("generation", 0)), "arrival bumps generation again")
	layer.prepare_for_draw()
	await process_frame
	_check(
		bool(unit_world._idle_variation_state(NICLAS_UNIT_ID).get("clip_started", false)),
		"arrival schedules visible idle clip",
	)
	_check(
		str(unit_world._idle_variation_state(NICLAS_UNIT_ID).get("current_clip", ""))
			in [IdleVariationScript.CLIP_IDLE_3, IdleVariationScript.CLIP_FLYING_FIST_KICK],
		"arrival idle current_clip is Idle_3 or kick",
	)
	if player != null:
		var idle_anim: Animation = player.get_animation(IdleVariationScript.CLIP_IDLE_3)
		if idle_anim != null:
			var iv_state: Dictionary = unit_world._idle_variation_state(NICLAS_UNIT_ID)
			var logical_len: float = float(iv_state.get("clip_logical_length_sec", 0.0))
			var phase_now: String = str(iv_state.get("phase", ""))
			if phase_now == IdleVariationScript.PHASE_NORMAL_IDLE:
				_check(
					absf(logical_len - idle_anim.length) < 0.01,
					"normal Idle_3 logical cycle uses real animation duration",
				)
			elif phase_now == IdleVariationScript.PHASE_RECOVERY_IDLE:
				_check(
					absf(
						logical_len
							- minf(idle_anim.length, IdleVariationScript.NICLAS_RECOVERY_IDLE_CAP_SEC)
					)
					< 0.01,
					"recovery Idle_3 uses capped stabilization duration",
				)
	_check(not unit_world._idle_variation_by_unit_id.has(2), "warrior has no idle variation state")
	_test_looped_idle_logical_cycle()
	IdleVariationScript.test_rng_seed_base = -1
	root.free()


func _test_looped_idle_logical_cycle() -> void:
	var state: Dictionary = IdleVariationScript.make_state(77)
	IdleVariationScript.mark_clip_started(state, IdleVariationScript.CLIP_IDLE_3, 2.0)
	state["phase"] = IdleVariationScript.PHASE_NORMAL_IDLE
	IdleVariationScript.advance_elapsed(state, 2.0, 1.0)
	_check(IdleVariationScript.is_clip_logically_complete(state), "looped Idle_3 logical cycle completes by timer")
	var cfg: Dictionary = IdleVariationScript.config_for_type("niclas")
	var next: Dictionary = IdleVariationScript.next_after_complete(state, cfg)
	_check(not next.is_empty(), "logical completion schedules next idle choice")


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("ok: %s" % msg)
	else:
		_failures += 1
		push_error("FAIL: %s" % msg)
