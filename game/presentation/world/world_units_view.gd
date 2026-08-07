# N7c/N7f world-unit presentation: renders the authoritative snapshot-v3
# units as the existing 3D settler/warrior characters on the WorldMap
# terrain, with the N7f presentation-only locomotion layer.
#
# Contract (locked):
# - The server snapshot is the only gameplay truth: each unit row is exactly
#   {"id": int, "owner_id": int, "position": [q, r], "type_id": ...} and this
#   view reconciles ONE stable Node3D root per unit, keyed by exact unit id.
# - Placement uses the N4 anchors verbatim: every root sits exactly at
#   TerrainWorld.tile_anchors[Vector2i(q, r)] (derived presentation data,
#   never gameplay authority). Nothing is rendered until BOTH the snapshot
#   units and the terrain anchors are available — never an origin fallback,
#   never a recomputed anchor, never a raycast or mesh-derived placement.
#   A unit position without an anchor is a contract violation: explicit
#   error, unit skipped.
# - Visuals reuse the project's imported GLB scenes (settler/warrior) below
#   a ModelRoot child, so the gameplay position (unit root) stays separate
#   from the visual transform. ModelRoot scale is 0.5 for terrain scale S=1.
#   The locked EFFECTIVE model forward is local -Z (Vector3.FORWARD): both
#   shipped rigs are AUTHORED facing +Z (glTF convention; audited 2026-08
#   via the toe-vs-ankle rest direction), so the character instance is
#   mounted with one convention-level 180° yaw (MODEL_FORWARD_CORRECTION),
#   identical for every unit type — after it, ModelRoot's local -Z IS the
#   rendered facing. Never per-unit facing hacks beyond this shared
#   authoring-convention correction.
# - N7f locomotion (presentation-only, never gameplay state): the
#   authoritative unit root snaps to its new anchor IMMEDIATELY on every
#   snapshot apply — only the visual ModelRoot catches up, gliding one
#   straight segment from the previous visual position to the new anchor
#   at LOCOMOTION_SPEED_UNITS_PER_SEC. Initial spawn snaps (no glide);
#   identical snapshot reapplication never restarts a glide or a clip; a
#   newer accepted move mid-glide retargets from the current visual
#   position (no teleport, no duplicate); removal cancels cleanly. While
#   moving the semantic "Walking" clip plays; on arrival the ModelRoot
#   returns to EXACTLY the anchor pose, keeps its facing, and the semantic
#   "Idle_3" clip resumes. All world displacement comes from this layer —
#   the audited GLB clips carry no root-motion position tracks.
# - N7f facing + grounding (upright-humanoid contract): the ModelRoot stays
#   UPRIGHT in world +Y with YAW ONLY — it faces the horizontal movement
#   direction and retains that facing after arrival; terrain normals never
#   pitch or roll the whole character. Terrain contact is skeletal instead:
#   WorldUnitLegGrounder (a SkeletonModifier3D under each character's
#   skeleton) grounds the FEET every frame — independent left/right
#   rendered-top-surface samples, a vertical pelvis adjustment, and an
#   analytic two-bone leg (knee) adjustment — while walking and idling.
#   Transient glide height and the foot targets sample ONLY the rendered
#   top surface through the injected WorldSurfaceSampler (never cliff
#   walls, never legality); without a sampler (or on a miss) the glide
#   falls back to interpolating the two anchor heights and the skeleton
#   keeps the animated pose. Sole-to-normal rotation is a documented
#   deferred fine-tune (see UNITS.md).
# - No selection, markers, or action submission here (N7d); no legality
#   (server-only, N7a/N7b); no path smoothing across multiple moves. The
#   legacy 2D/unit_3d_world_view path (ray placement, ~75x scale) is NOT
#   reused.
class_name WorldUnitsView
extends Node3D

## N7f.1 arrival event: emitted EXACTLY ONCE when a real glide completes —
## the visual reached its exact final-anchor pose, the locomotion entry was
## removed, and Idle resumed. Never emitted for initial spawns, identical
## snapshot reapplies, ordinary idling, degenerate (no-glide) settlements,
## or units removed mid-glide. Presentation output only: consumers (the
## world-play arrival gate) pace INPUT with it — gameplay state is never
## delayed by animation completion.
signal unit_arrived(unit_id: int)

# Reused for asset-path resolution and the audited GLB idle-clip remap only
# (RefCounted helpers; none of the legacy env-flag gating applies here).
const Warrior3DExperimentScript = preload("res://presentation/warrior_3d_unit_experiment.gd")
const Warrior3DAnimationRemapScript = preload("res://presentation/warrior_3d_animation_remap.gd")
const WorldUnitLegGrounderScript = preload("res://presentation/world/world_unit_leg_grounder.gd")

const MODEL_ROOT_NAME := "ModelRoot"
# Visual scale below the unit root, tuned for terrain scale S=1.
const MODEL_ROOT_SCALE := 0.5
const SEMANTIC_IDLE_CLIP := "Idle_3"
const SEMANTIC_WALK_CLIP := "Walking"

# Convention-level authoring correction (NOT a per-unit hack): both shipped
# rigs are authored facing +Z (the glTF forward convention; audited via the
# toe-vs-ankle rest direction, identical on settler and warrior). Mounting
# every character instance with this single 180° yaw makes the composed
# model's visual front the locked local -Z (Vector3.FORWARD).
const MODEL_FORWARD_CORRECTION_YAW := PI

# N7f movement-speed tuning constant (Niclas review value): world units per
# second at terrain scale S=1. Adjacent tile anchors are ~1.7 world units
# apart, so one tile move reads as ~1.1 s of walking.
const LOCOMOTION_SPEED_UNITS_PER_SEC := 1.6
# Degenerate-distance guard only (a real tile move is far longer).
const LOCOMOTION_MIN_DURATION_SEC := 0.05

# Locked matte unit-material treatment (permanent WorldMap unit-render
# profile; same values the previously approved real-3D path used). The GLBs
# import fully metallic (metallic=1.0, roughness=0.41, specular=0.5), which
# renders yellow/golden under the warm N3c.7 key sun — every rendered
# surface gets a per-instance duplicated StandardMaterial3D with these
# values instead. Albedo texture/color, transparency/culling, and all other
# imported properties are preserved; the imported resources themselves are
# never mutated. Filter stays linear+mipmaps (anisotropic was tried on the
# prior path and rejected — no gain).
const UNIT_MAT_METALLIC := 0.0
const UNIT_MAT_ROUGHNESS := 0.85
const UNIT_MAT_SPECULAR := 0.3

# Latest inputs (view state only; both must be present before anything
# renders — arrival order does not matter).
var _tile_anchors: Dictionary = {}
var _units: Array = []
var _anchors_ready := false
var _units_ready := false

var _root_by_unit_id: Dictionary = {}
var _type_by_unit_id: Dictionary = {}
var _scene_by_type: Dictionary = {}
var _warned_types: Dictionary = {}

# N7f locomotion state (presentation-only; never read by gameplay).
# unit id -> current authoritative target anchor (root position).
var _target_anchor_by_unit_id: Dictionary = {}
# unit id -> active glide segment {start, end, dir, elapsed, duration}.
var _loco_by_unit_id: Dictionary = {}
# unit id -> the character's AnimationPlayer (clip transitions).
var _player_by_unit_id: Dictionary = {}
# unit id -> WorldUnitLegGrounder (skeletal foot grounding; may be absent
# when a rig cannot bind — the unit then simply keeps its animated pose).
var _grounder_by_unit_id: Dictionary = {}
# Injected top-surface sampler (WorldSurfaceSampler-shaped; may stay null).
var _surface_sampler = null


func _process(delta: float) -> void:
	advance_locomotion(delta)


# Injects the presentation-only rendered-top-surface sampler (production:
# WorldSurfaceSampler over the built TerrainCollision body; tests may pass
# any object exposing sample(x, z, y_hint) -> {ok, height, normal}) and
# propagates it to every existing leg grounder.
func set_surface_sampler(sampler) -> void:
	_surface_sampler = sampler
	for grounder in _grounder_by_unit_id.values():
		grounder.set_surface_sampler(sampler)


func has_surface_sampler() -> bool:
	return _surface_sampler != null


# Supplies the terrain anchors (TerrainWorld.tile_anchors: Vector2i -> Vector3).
func set_tile_anchors(anchors: Dictionary) -> void:
	_tile_anchors = anchors
	_anchors_ready = not anchors.is_empty()
	_reconcile()


# Applies the authoritative snapshot "units" array. Reapplying the same
# array is idempotent (stable roots, no duplicates); changed positions move
# the existing roots; missing ids free their roots.
func apply_snapshot_units(units: Array) -> void:
	_units = units.duplicate(true)
	_units_ready = true
	_reconcile()


func unit_count() -> int:
	return _root_by_unit_id.size()


# Ascending unit ids currently rendered.
func unit_ids() -> Array:
	var ids: Array = _root_by_unit_id.keys()
	ids.sort()
	return ids


func root_for_unit(unit_id: int) -> Node3D:
	return _root_by_unit_id.get(unit_id) as Node3D


func type_id_for_unit(unit_id: int) -> String:
	return str(_type_by_unit_id.get(unit_id, ""))


func _reconcile() -> void:
	if not _anchors_ready or not _units_ready:
		return
	var active_ids: Dictionary = {}
	for row_variant in _units:
		if typeof(row_variant) != TYPE_DICTIONARY:
			push_error("world_units_view: snapshot unit row is not an object")
			continue
		var row: Dictionary = row_variant
		var unit_id := int(row.get("id", -1))
		var type_id := str(row.get("type_id", ""))
		var pos_variant = row.get("position", null)
		if unit_id < 0 or typeof(pos_variant) != TYPE_ARRAY or (pos_variant as Array).size() != 2:
			push_error("world_units_view: malformed snapshot unit row (id=%d)" % unit_id)
			continue
		var pos: Array = pos_variant
		var key := Vector2i(int(pos[0]), int(pos[1]))
		if not _tile_anchors.has(key):
			push_error(
				"world_units_view: no tile anchor for unit %d at (%d, %d) — snapshot/anchor contract violation, unit not rendered"
				% [unit_id, key.x, key.y]
			)
			continue
		var anchor: Vector3 = _tile_anchors[key]
		var root: Node3D = _root_by_unit_id.get(unit_id) as Node3D
		if root == null:
			root = _create_unit_root(unit_id, type_id)
			if root == null:
				continue
			# Initial spawn (and reconnect rebuild) snaps directly.
			root.position = anchor
			_target_anchor_by_unit_id[unit_id] = anchor
			active_ids[unit_id] = true
			continue
		active_ids[unit_id] = true
		var prev_anchor: Vector3 = _target_anchor_by_unit_id.get(unit_id, root.position)
		if anchor == prev_anchor:
			# Idempotent reapply: never restarts a glide or an animation.
			root.position = anchor
			continue
		# Authoritative move: the root snaps to the new anchor IMMEDIATELY;
		# only the visual glides there from its current visual position
		# (mid-glide retarget starts from the in-flight pose — no teleport).
		var visual_start: Vector3 = root.position + _model_root_of(root).position
		root.position = anchor
		_target_anchor_by_unit_id[unit_id] = anchor
		_begin_locomotion(unit_id, visual_start, anchor)
	for stale_key in _root_by_unit_id.keys():
		var stale_id := int(stale_key)
		if active_ids.has(stale_id):
			continue
		var stale_root: Node = _root_by_unit_id[stale_id] as Node
		if stale_root != null:
			stale_root.queue_free()
		_root_by_unit_id.erase(stale_id)
		_type_by_unit_id.erase(stale_id)
		# Removal cancels any in-flight locomotion cleanly.
		_target_anchor_by_unit_id.erase(stale_id)
		_loco_by_unit_id.erase(stale_id)
		_player_by_unit_id.erase(stale_id)
		_grounder_by_unit_id.erase(stale_id)


func _create_unit_root(unit_id: int, type_id: String) -> Node3D:
	var scene := _scene_for_type(type_id)
	if scene == null:
		return null
	var model: Node = scene.instantiate()
	if model == null:
		push_error("world_units_view: instantiate failed for unit %d type %s" % [unit_id, type_id])
		return null
	apply_material_treatment(model)
	var root := Node3D.new()
	root.name = "WorldUnit_%d" % unit_id
	var model_root := Node3D.new()
	model_root.name = MODEL_ROOT_NAME
	model_root.scale = Vector3.ONE * MODEL_ROOT_SCALE
	# glTF-authored +Z front -> locked -Z effective forward (see constant).
	if model is Node3D:
		(model as Node3D).rotation = Vector3(0.0, MODEL_FORWARD_CORRECTION_YAW, 0.0)
	model_root.add_child(model)
	root.add_child(model_root)
	add_child(root)
	_root_by_unit_id[unit_id] = root
	_type_by_unit_id[unit_id] = type_id
	var player := _find_animation_player(model)
	if player == null:
		_warn_type_once(type_id, "no AnimationPlayer for unit animation")
	else:
		_player_by_unit_id[unit_id] = player
	_attach_leg_grounder(unit_id, model, model_root, type_id)
	_play_semantic_clip(unit_id, SEMANTIC_IDLE_CLIP)
	return root


# Attaches the N7f skeletal foot grounding to the character's Skeleton3D
# (post-animation pose override; upright body, grounded feet). A rig that
# cannot bind only warns — the unit stays valid with its animated pose.
func _attach_leg_grounder(unit_id: int, model: Node, model_root: Node3D, type_id: String) -> void:
	var skeleton := _find_skeleton(model)
	if skeleton == null:
		_warn_type_once(type_id, "no Skeleton3D for leg grounding")
		return
	var grounder := WorldUnitLegGrounderScript.new()
	grounder.name = "LegGrounder"
	skeleton.add_child(grounder)
	if not grounder.setup(_surface_sampler, model_root):
		_warn_type_once(type_id, "leg-grounding bones not found; skeletal grounding disabled")
		grounder.queue_free()
		return
	_grounder_by_unit_id[unit_id] = grounder


func _scene_for_type(type_id: String) -> PackedScene:
	if _scene_by_type.has(type_id):
		return _scene_by_type[type_id] as PackedScene
	var scene_path: String = Warrior3DExperimentScript.animated_scene_path_for_type(type_id)
	var scene: PackedScene = null
	if scene_path.is_empty():
		_warn_type_once(type_id, "no character scene registered")
	else:
		scene = load(scene_path) as PackedScene
		if scene == null:
			_warn_type_once(type_id, "failed to load %s" % scene_path)
	_scene_by_type[type_id] = scene
	return scene


# Applies the locked matte treatment to every StandardMaterial3D surface of
# one instantiated character: duplicate per instance (imports untouched),
# set the three locked values, and pin linear+mipmap filtering. Everything
# else on the material is preserved.
static func apply_material_treatment(model: Node) -> void:
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_inst: MeshInstance3D = node as MeshInstance3D
		var mesh: Mesh = mesh_inst.mesh
		if mesh == null:
			continue
		for si in mesh.get_surface_count():
			var src_mat: Material = mesh_inst.get_surface_override_material(si)
			if src_mat == null:
				src_mat = mesh.surface_get_material(si)
			if src_mat is StandardMaterial3D:
				var treated: StandardMaterial3D = src_mat.duplicate() as StandardMaterial3D
				treated.metallic = UNIT_MAT_METALLIC
				treated.roughness = UNIT_MAT_ROUGHNESS
				treated.metallic_specular = UNIT_MAT_SPECULAR
				treated.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
				mesh_inst.set_surface_override_material(si, treated)


# --- N7f locomotion layer (presentation-only) -------------------------------


# True while the unit's visual is still gliding toward its anchor.
func is_unit_moving(unit_id: int) -> bool:
	return _loco_by_unit_id.has(unit_id)


# Current visual world position (root anchor + transient ModelRoot offset).
func visual_position_for_unit(unit_id: int) -> Vector3:
	var root: Node3D = _root_by_unit_id.get(unit_id) as Node3D
	if root == null:
		return Vector3.ZERO
	return root.position + _model_root_of(root).position


func animation_player_for_unit(unit_id: int) -> AnimationPlayer:
	return _player_by_unit_id.get(unit_id) as AnimationPlayer


# The unit's skeletal foot grounder (null when the rig could not bind).
func grounder_for_unit(unit_id: int):
	return _grounder_by_unit_id.get(unit_id)


# Advances every active glide by delta seconds (called from _process;
# headless tests drive it directly for determinism).
func advance_locomotion(delta: float) -> void:
	for id_key in _loco_by_unit_id.keys():
		var unit_id := int(id_key)
		var root: Node3D = _root_by_unit_id.get(unit_id) as Node3D
		if root == null:
			_loco_by_unit_id.erase(unit_id)
			continue
		var seg: Dictionary = _loco_by_unit_id[unit_id]
		seg["elapsed"] = float(seg["elapsed"]) + delta
		var s: float = clampf(float(seg["elapsed"]) / float(seg["duration"]), 0.0, 1.0)
		if s >= 1.0:
			_arrive(unit_id, seg, root)
			continue
		var pos: Vector3 = (seg["start"] as Vector3).lerp(seg["end"] as Vector3, s)
		var sampled := _sample_surface(pos)
		if bool(sampled["ok"]):
			pos.y = float(sampled["height"])
		var model_root := _model_root_of(root)
		model_root.position = pos - root.position
		_apply_visual_yaw(model_root, seg["dir"] as Vector3)


func _begin_locomotion(unit_id: int, from_pos: Vector3, to_anchor: Vector3) -> void:
	var root: Node3D = _root_by_unit_id.get(unit_id) as Node3D
	if root == null:
		return
	var model_root := _model_root_of(root)
	var flat := Vector3(to_anchor.x - from_pos.x, 0.0, to_anchor.z - from_pos.z)
	var dist := flat.length()
	if dist < 0.0001:
		# Degenerate segment: settle at the anchor pose immediately.
		model_root.position = Vector3.ZERO
		_loco_by_unit_id.erase(unit_id)
		_play_semantic_clip(unit_id, SEMANTIC_IDLE_CLIP)
		return
	var dir := flat / dist
	_loco_by_unit_id[unit_id] = {
		"start": from_pos,
		"end": to_anchor,
		"dir": dir,
		"elapsed": 0.0,
		"duration": maxf(dist / LOCOMOTION_SPEED_UNITS_PER_SEC, LOCOMOTION_MIN_DURATION_SEC),
	}
	# Visual stays where it was: root moved to the anchor, offset compensates.
	model_root.position = from_pos - to_anchor
	_apply_visual_yaw(model_root, dir)
	_play_semantic_clip(unit_id, SEMANTIC_WALK_CLIP)


# Arrival: EXACT final-anchor pose (offset zero), facing retained (yaw
# toward the movement direction), idle clip resumes; the leg grounder
# keeps grounding the idle pose from here on.
func _arrive(unit_id: int, seg: Dictionary, root: Node3D) -> void:
	var model_root := _model_root_of(root)
	model_root.position = Vector3.ZERO
	_apply_visual_yaw(model_root, seg["dir"] as Vector3)
	_loco_by_unit_id.erase(unit_id)
	_play_semantic_clip(unit_id, SEMANTIC_IDLE_CLIP)
	# N7f.1: the one real-arrival point — pose finalized, entry removed,
	# Idle resumed. advance_locomotion reaches this branch exactly once per
	# completed glide (removed units erase their entry without arriving).
	unit_arrived.emit(unit_id)


# Deterministic YAW-ONLY facing (upright-humanoid contract): the ModelRoot
# stays upright in world +Y and rotates about it so the locked local -Z
# forward points along the horizontal movement direction. Terrain never
# tilts the body — grounding is skeletal (WorldUnitLegGrounder). Returns
# identity when the direction degenerates.
static func locomotion_yaw(move_dir: Vector3) -> Basis:
	var flat := Vector3(move_dir.x, 0.0, move_dir.z)
	if flat.length_squared() < 0.000001:
		return Basis.IDENTITY
	flat = flat.normalized()
	# -Z forward: yaw angle measured from -Z toward +X.
	return Basis(Vector3.UP, atan2(-flat.x, -flat.z))


func _apply_visual_yaw(model_root: Node3D, dir: Vector3) -> void:
	model_root.basis = locomotion_yaw(dir) * Basis.from_scale(Vector3.ONE * MODEL_ROOT_SCALE)


# One transient visual sample of the rendered top surface (fallback: keep
# the interpolated anchor height, upright normal). Never gameplay data.
func _sample_surface(pos: Vector3) -> Dictionary:
	if _surface_sampler == null:
		return {"ok": false, "height": pos.y, "normal": Vector3.UP}
	var res: Dictionary = _surface_sampler.sample(pos.x, pos.z, pos.y)
	if typeof(res) != TYPE_DICTIONARY or not bool(res.get("ok", false)):
		return {"ok": false, "height": pos.y, "normal": Vector3.UP}
	return res


func _model_root_of(root: Node3D) -> Node3D:
	return root.get_node(MODEL_ROOT_NAME) as Node3D


# Plays the remapped GLB clip for one semantic name ("Idle_3" / "Walking").
# Already-playing clips are never restarted (idempotent reapply, mid-glide
# retarget). Missing player/clip only warns — placement stays valid.
func _play_semantic_clip(unit_id: int, semantic: String) -> void:
	var player: AnimationPlayer = _player_by_unit_id.get(unit_id) as AnimationPlayer
	if player == null:
		return
	var type_id := str(_type_by_unit_id.get(unit_id, ""))
	var clip: String = Warrior3DAnimationRemapScript.glb_clip_for_visual(semantic, true, type_id)
	if not player.has_animation(clip):
		_warn_type_once(type_id, "clip '%s' (semantic %s) not found" % [clip, semantic])
		return
	if player.current_animation == clip and player.is_playing():
		return
	var anim: Animation = player.get_animation(clip)
	anim.loop_mode = Animation.LOOP_LINEAR
	player.play(clip)


static func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child as Node)
		if found != null:
			return found
	return null


static func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child as Node)
		if found != null:
			return found
	return null


func _warn_type_once(type_id: String, message: String) -> void:
	if _warned_types.has(type_id + "|" + message):
		return
	_warned_types[type_id + "|" + message] = true
	push_warning("world_units_view: type %s: %s" % [type_id, message])
