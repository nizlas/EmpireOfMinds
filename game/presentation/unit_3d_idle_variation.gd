# Presentation-only weighted idle variation for real-3D units (no GameState / replay impact).
class_name Unit3DIdleVariation
extends RefCounted

const PHASE_CHOOSING: String = "choosing"
const PHASE_NORMAL_IDLE: String = "normal_idle"
const PHASE_FLOURISH: String = "flourish"
const PHASE_RECOVERY_IDLE: String = "recovery_idle"
const PHASE_MOVING: String = "moving"

const CLIP_IDLE_3: String = "Idle_3"
const CLIP_FLYING_FIST_KICK: String = "Flying_Fist_Kick"

const NICLAS_BLEND_TO_FLOURISH_SEC: float = 0.15
const NICLAS_BLEND_TO_RECOVERY_SEC: float = 0.30
## Post-kick neutral Idle_3 stabilization (not a full 9.97s import cycle).
const NICLAS_RECOVERY_IDLE_CAP_SEC: float = 1.5

const COMPLETE_EPS_SEC: float = 0.02

## Headless/tests: when >= 0, each unit seeds RNG as base + unit_id.
static var test_rng_seed_base: int = -1


static func has_variation(type_id: String) -> bool:
	return not config_for_type(type_id).is_empty()


static func config_for_type(type_id: String) -> Dictionary:
	if str(type_id) == "niclas":
		return {
			"recovery_clip": CLIP_IDLE_3,
			"blend_to_flourish_sec": NICLAS_BLEND_TO_FLOURISH_SEC,
			"blend_to_recovery_sec": NICLAS_BLEND_TO_RECOVERY_SEC,
			"variants": niclas_weighted_variants(),
		}
	return {}


static func niclas_weighted_variants() -> Array:
	return [
		{
			"clip": CLIP_IDLE_3,
			"weight": 1.0,
			"phase_after_pick": PHASE_NORMAL_IDLE,
		},
		{
			"clip": CLIP_FLYING_FIST_KICK,
			"weight": 1.0,
			"phase_after_pick": PHASE_FLOURISH,
		},
	]


static func total_weight(variants: Array) -> float:
	var total: float = 0.0
	var i: int = 0
	while i < variants.size():
		total += maxf(float(variants[i].get("weight", 0.0)), 0.0)
		i += 1
	return total


static func pick_weighted_variant(rng: RandomNumberGenerator, variants: Array) -> Dictionary:
	if variants.is_empty() or rng == null:
		return {}
	var total: float = total_weight(variants)
	if total <= 0.0:
		return {}
	var roll: float = rng.randf() * total
	var acc: float = 0.0
	var i: int = 0
	while i < variants.size():
		var entry: Dictionary = variants[i]
		acc += maxf(float(entry.get("weight", 0.0)), 0.0)
		if roll < acc:
			return entry
		i += 1
	return variants[variants.size() - 1]


static func make_state(unit_id: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	if test_rng_seed_base >= 0:
		rng.seed = test_rng_seed_base + unit_id
	else:
		rng.randomize()
	return {
		"generation": 0,
		"phase": PHASE_CHOOSING,
		"current_clip": "",
		"clip_started": false,
		"clip_elapsed_sec": 0.0,
		"clip_logical_length_sec": 0.0,
		"rng": rng,
	}


static func bump_generation(state: Dictionary) -> int:
	var next_gen: int = int(state.get("generation", 0)) + 1
	state["generation"] = next_gen
	return next_gen


static func interrupt_for_movement(state: Dictionary) -> int:
	bump_generation(state)
	state["phase"] = PHASE_MOVING
	state["current_clip"] = ""
	state["clip_started"] = false
	state["clip_elapsed_sec"] = 0.0
	state["clip_logical_length_sec"] = 0.0
	return int(state["generation"])


static func restart_after_arrival(state: Dictionary) -> int:
	bump_generation(state)
	begin_choose_phase(state)
	return int(state["generation"])


static func choose_from_chooser(state: Dictionary, config: Dictionary) -> Dictionary:
	if str(state.get("phase", "")) != PHASE_CHOOSING:
		begin_choose_phase(state)
	return choose_and_start(state, config)


static func begin_choose_phase(state: Dictionary) -> void:
	state["phase"] = PHASE_CHOOSING
	state["current_clip"] = ""
	state["clip_started"] = false
	state["clip_elapsed_sec"] = 0.0
	state["clip_logical_length_sec"] = 0.0


static func choose_and_start(state: Dictionary, config: Dictionary) -> Dictionary:
	var variants: Array = config.get("variants", [])
	var pick: Dictionary = pick_weighted_variant(state["rng"] as RandomNumberGenerator, variants)
	if pick.is_empty():
		return {}
	var clip: String = str(pick.get("clip", ""))
	var next_phase: String = str(pick.get("phase_after_pick", PHASE_NORMAL_IDLE))
	state["phase"] = next_phase
	var blend_sec: float = 0.0
	if clip == CLIP_FLYING_FIST_KICK:
		blend_sec = float(config.get("blend_to_flourish_sec", NICLAS_BLEND_TO_FLOURISH_SEC))
	return {
		"clip": clip,
		"blend_sec": blend_sec,
		"phase": next_phase,
		"reason": "choose",
	}


static func next_after_complete(state: Dictionary, config: Dictionary) -> Dictionary:
	var phase: String = str(state.get("phase", ""))
	match phase:
		PHASE_NORMAL_IDLE:
			begin_choose_phase(state)
			return choose_and_start(state, config)
		PHASE_FLOURISH:
			state["phase"] = PHASE_RECOVERY_IDLE
			return {
				"clip": str(config.get("recovery_clip", CLIP_IDLE_3)),
				"blend_sec": float(config.get("blend_to_recovery_sec", NICLAS_BLEND_TO_RECOVERY_SEC)),
				"phase": PHASE_RECOVERY_IDLE,
				"reason": "flourish_to_recovery",
			}
		PHASE_RECOVERY_IDLE:
			begin_choose_phase(state)
			return choose_and_start(state, config)
		_:
			return {}


static func is_clip_logically_complete(state: Dictionary) -> bool:
	var length_sec: float = float(state.get("clip_logical_length_sec", 0.0))
	if length_sec <= 0.0:
		return false
	return float(state.get("clip_elapsed_sec", 0.0)) >= length_sec - COMPLETE_EPS_SEC


static func advance_elapsed(state: Dictionary, delta: float, speed_scale: float = 1.0) -> void:
	state["clip_elapsed_sec"] = float(state.get("clip_elapsed_sec", 0.0)) + delta * speed_scale


static func logical_clip_length_sec(anim: Animation) -> float:
	if anim == null:
		return 0.0
	return maxf(anim.length, 0.001)


static func logical_length_for_phase(phase: String, clip: String, anim_length: float) -> float:
	var length: float = maxf(anim_length, 0.001)
	if str(phase) == PHASE_RECOVERY_IDLE and str(clip) == CLIP_IDLE_3:
		return minf(length, NICLAS_RECOVERY_IDLE_CAP_SEC)
	return length


static func is_import_loop_linear(anim: Animation) -> bool:
	return anim != null and anim.loop_mode == Animation.LOOP_LINEAR


static func mark_clip_started(state: Dictionary, clip: String, logical_length_sec: float) -> void:
	state["current_clip"] = clip
	state["clip_started"] = true
	state["clip_elapsed_sec"] = 0.0
	state["clip_logical_length_sec"] = maxf(logical_length_sec, 0.001)
