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
#   from the visual transform. ModelRoot scale is 0.30 for terrain scale S=1.
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
#   analytic two-bone leg (knee) adjustment with whole-foot sole-to-normal
#   alignment — while walking and idling. Sole contact is CALIBRATED to
#   the post-alignment sole-plane invariant (dot(n, ankle - s) == d with
#   d = the rig-derived rest ankle height; the audited bind-pose soles sit
#   exactly on the plane) and STATIONARY units plant each foot in ground
#   space so
#   the remapped not-true-idle clips cannot hover, rock, or drift planted
#   feet; this view toggles the grounder's locomotion gate on glide
#   begin/arrival so plants release and replant smoothly. Transient glide
#   height and the foot targets sample ONLY the rendered top surface
#   through the injected WorldSurfaceSampler (never cliff walls, never
#   legality); without a sampler (or on a miss) the glide falls back to
#   interpolating the two anchor heights and the skeleton keeps the
#   animated pose.
# - N7g.3 combat presentation (presentation-only, never an outcome source):
#   present_combat(event, deferred_snapshot) plays ONE deterministic
#   presentation for an ACCEPTED server attack_unit: (1) presentation-only
#   melee approach — attacker Walks from its pre-combat authoritative
#   anchor to a melee staging point at MELEE_STANDOFF_DISTANCE in front of
#   the defender (terrain-following/grounding; never emits unit_arrived;
#   never mutates gameplay position); (2) impact-timed exchange — attacker
#   Left_Slash with the target's reaction starting after
#   COMBAT_IMPACT_DELAY_SEC (overlap; attack completion is NOT required);
#   (3) at impact a non-fatal hit plays Hit_Reaction_1, while a fatal hit
#   starts Dead directly (Dead already contains its own hit reaction —
#   never prepend Hit_Reaction_1); (4) retaliation only when the event says
#   retaliated==true (same impact overlap; never after defender death);
#   every semantic clip change crossfades via ANIM_BLEND_DEFAULT_SEC;
#   (5) living Left_Slash / Hit_Reaction_1 use combat-support grounding
#   (near-stance support contacts forced; clear authored swing feet free;
#   ModelRoot stays upright; mutually exclusive with Walking/Idle plants);
#   a bounded Spine02+Spine01 aim chain rotates the measured club-head
#   strike endpoint to the defender's head-region contact height at the
#   impact phase (above → downward strike; below → upward; equal surface
#   elevation → neutral authored slash; never whole-body tilt);
#   (6) continuous corpse terrain support WHILE Dead plays — authored fall
#   until animated body regions would contact/penetrate, then minimum
#   presentation lift + multi-point pitch/roll (Dead is the ONE full-body
#   pitch/roll exception; grounder fully paused on corpses);
#   (7) survivor traversal to the snapshot-authoritative final anchor;
#   ordinary facing (move, approach, face-opponent, return/occupation,
#   post-return) uses the centralized FACING_BLEND_SEC shortest-arc
#   controller. Every clip resolves through Warrior3DAnimationRemap.
#   combat_presentation_finished fires once after the full sequence.
#   Malformed events/snapshots/roots/clips refuse and return false for
#   immediate reconciliation; cancel/supersede clears presentation
#   offsets. Damage/survival/retaliation/elimination are never computed
#   here — the accepted event + deferred authoritative snapshot only.
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

## N7g.3 combat-presentation completion: emitted EXACTLY ONCE when a
## sequence started by present_combat finishes — approach, combat clips,
## death/corpse fit, and survivor traversal to the snapshot-authoritative
## final anchor all complete; survivors are on Idle_3 with grounders
## resumed. Never emitted for canceled sequences or failed present_combat
## calls. Presentation output only: the world-play scene applies the
## deferred authoritative snapshot and refetches legality on it —
## gameplay state was accepted by the server long before this fires.
signal combat_presentation_finished(attacker_id: int, defender_id: int)

# Reused for asset-path resolution and the audited GLB idle-clip remap only
# (RefCounted helpers; none of the legacy env-flag gating applies here).
const Warrior3DExperimentScript = preload("res://presentation/warrior_3d_unit_experiment.gd")
const Warrior3DAnimationRemapScript = preload("res://presentation/warrior_3d_animation_remap.gd")
const WorldUnitLegGrounderScript = preload("res://presentation/world/world_unit_leg_grounder.gd")

const MODEL_ROOT_NAME := "ModelRoot"
# Visual scale below the unit root, tuned for terrain scale S=1.
# City preview scale reference: 0.30.
const MODEL_ROOT_SCALE := 0.30
const SEMANTIC_IDLE_CLIP := "Idle_3"
const SEMANTIC_WALK_CLIP := "Walking"
# N7g.3 semantic combat clips (resolved through the audited remap — the raw
# Meshy GLB names are misleading; the mapping stays centralized in
# warrior_3d_animation_remap.gd and is never inferred from clip names here).
const SEMANTIC_ATTACK_CLIP := "Left_Slash"
const SEMANTIC_HIT_CLIP := "Hit_Reaction_1"
const SEMANTIC_DEAD_CLIP := "Dead"

# N7g.3 presentation tuning (never gameplay authority):
# Distance from the defender's authoritative anchor to the attacker's melee
# staging point along the pre-combat attacker→defender axis. Tuned for
# ModelRoot scale 0.5 so the remapped club swing reads as contact
# (second visual pass: 0.55 was too tight → 0.80).
const MELEE_STANDOFF_DISTANCE := 0.80
# Seconds after a Left_Slash begins before the target's reaction starts
# (non-fatal → Hit_Reaction_1; fatal → Dead directly). Overlap: attack
# completion is not required.
const COMBAT_IMPACT_DELAY_SEC := 0.5
# Centralized AnimationPlayer crossfade for every semantic clip change
# (Idle/Walking/combat/death/cancel). Reuses the legacy map-view
# Walking→Idle value from unit_3d_world_view / warrior_3d_unit_markers_view
# (`idle_end_blend_sec = 0.28`). Applied via player.play(clip, blend_sec).
# One-shot completion timing still uses the remapped clip length from
# play-start — blending must not delay impact or gate release.
const ANIM_BLEND_DEFAULT_SEC := 0.28
# Centralized shortest-arc yaw blend for ordinary gameplay-driven turns
# (move start, approach, face-opponent, return/occupation, post-return).
# Confirmed visual value; lifecycle snaps stay immediate (see _facing_snap).
const FACING_BLEND_SEC := ANIM_BLEND_DEFAULT_SEC
# Alias retained for existing combat diagnostics / tests.
const TRAVEL_FACING_BLEND_SEC := FACING_BLEND_SEC
# Corpse contact: treat a body region as contacting when within this many
# world units of the sampled top surface (prevents sub-surface flash).
const CORPSE_CONTACT_EPS := 0.02
# Once hips are this close to the surface (or Dead has finished), enable
# multi-point pitch/roll in addition to the penetration lift.
const CORPSE_PITCH_ENABLE_CLEARANCE := 0.22
# Footprint half-extents used only as a bone-less fallback fit.
const CORPSE_FOOTPRINT_HALF_LENGTH := 0.32
const CORPSE_FOOTPRINT_HALF_WIDTH := 0.12
# Localized melee elevation aim (radians) — never ModelRoot pitch. Per-bone
# bound; the correction spans the two authored lower-spine vertebrae
# (Spine02 + Spine01, half each), so the total world angle is bounded by
# ATTACK_PITCH_CHAIN_MAX_RAD. Eighth-pass measurement: reaching the strike
# contact on the reference 0.25-grade slope needs ~0.56 rad total — a single
# Spine02 DOF at 0.40 was geometrically unable to reach it.
const ATTACK_PITCH_MAX_RAD := 0.40
const ATTACK_PITCH_CHAIN_MAX_RAD := 2.0 * ATTACK_PITCH_MAX_RAD
const ATTACK_PITCH_BLEND_SEC := ANIM_BLEND_DEFAULT_SEC
# Left_Slash striking endpoint and unchanged Hit_Reaction_1 contact region.
const ATTACK_STRIKE_BONE := "LeftHand"
# Canonical defender contact (eighth-pass measurement): on the accepted
# equal-elevation authored exchange the club head passes the defender's
# HEAD height (dy +0.029 world at the impact instant; Spine01 was 0.15
# below the real contact) — the strike is an overhead downswing to the
# head/upper-chest region, so the Head bone anchors the contact point.
const ATTACK_TARGET_BONE := "Head"
# Fallback contact height above the sampled surface when bones are
# unavailable (flat idle Head height 0.7185 at ModelRoot scale 0.5).
const ATTACK_AIM_TORSO_HEIGHT := 1.437 * MODEL_ROOT_SCALE
# Authored warrior strike geometry (eighth pass, rig+clip derived — see
# docs/UNITS.md): the visible striking endpoint is the club head skinned to
# LeftHand (hand-local vertex-cluster offset in raw skeleton units). On the
# audited slash the strike's contact window is the overhead downswing at
# t ≈ 0.44–0.58 — bracketing the accepted COMBAT_IMPACT_DELAY_SEC — where
# the endpoint passes the defender's head height at equal elevation. The
# impact-phase (t = 0.5) endpoint and Spine02 pivot are captured in
# ModelRoot-local space so the per-swing aim solve is stable (never chases
# the live mid-swing hand pose, whose short pivot lever made the old
# correction move the hand only ~0.028 world units at full clamp).
const ATTACK_STRIKE_TIP_HAND_LOCAL := Vector3(0.384, 20.244, 0.385)
const ATTACK_IMPACT_PHASE_SEC := COMBAT_IMPACT_DELAY_SEC
const ATTACK_IMPACT_ENDPOINT_MODEL := Vector3(0.1056, 1.4953, -0.8955)
const ATTACK_IMPACT_PIVOT_MODEL := Vector3(-0.0260, 1.0966, -0.1320)

# Convention-level authoring correction (NOT a per-unit hack): both shipped
# rigs are authored facing +Z (the glTF forward convention; audited via the
# toe-vs-ankle rest direction, identical on settler and warrior). Mounting
# every character instance with this single 180° yaw makes the composed
# model's visual front the locked local -Z (Vector3.FORWARD).
const MODEL_FORWARD_CORRECTION_YAW := PI

# N7f base movement-speed tuning (Niclas review value): world units per
# second at terrain scale S=1 before the presentation translation scale.
const LOCOMOTION_SPEED_UNITS_PER_SEC := 1.6
# Presentation-only translation scale, derived from measured stride/root
# synchronization: with Walking playback fixed at 1.0, the authored stance
# feet sweep backward under the body at ~0.69–0.73 wu/s (warrior/settler)
# — root translation must match that or the planted soles slide. The
# eighth-pass 0.43 (0.688 wu/s) minimized the UNSIGNED slip but both rigs
# still drifted backward at a signed mean sole velocity of ~−0.024 wu/s
# (Niclas saw it live); the ninth pass raises the root by exactly that
# measured deficit: 0.445 × 1.6 = 0.712 wu/s centers the signed planted-
# sole velocity around zero (settler/warrior means within ±0.002 wu/s)
# without reintroducing the forward skating of the rejected 0.81 (~0.34 wu
# per stance). Scales root translation only; Walking playback stays 1.0.
const LOCOMOTION_TRANSLATION_SPEED_SCALE := 0.445
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
# unit id -> remaining seconds to keep locomotion grounding after exact
# arrival / Idle resume so the Walking→Idle crossfade never briefly shows
# ungrounded authored soles. Plants engage when the timer elapses.
var _ground_settle_by_unit_id: Dictionary = {}

# N7g.3 active combat sequence ({} = none). Stage machine — see
# present_combat / advance_combat. Presentation-only travel lives in
# _combat["travel"] and NEVER touches _loco_by_unit_id / unit_arrived.
var _combat: Dictionary = {}
# Centralized facing blends: unit_id -> {from, to, elapsed, duration}.
var _facing_by_unit_id: Dictionary = {}
# Diagnostics for the centralized blend path (last semantic play request).
var _last_play_unit_id := -1
var _last_play_semantic := ""
var _last_play_blend_sec := -1.0
var _last_play_one_shot := false


# Effective presentation translation speed (base × scale). Animation playback
# speed is independent and stays at 1.0.
static func locomotion_translation_speed() -> float:
	return LOCOMOTION_SPEED_UNITS_PER_SEC * LOCOMOTION_TRANSLATION_SPEED_SCALE


func _process(delta: float) -> void:
	# Public advance_* helpers also step facing for headless tests; the
	# engine path advances facing once here to avoid double-speed turns.
	_step_ground_settle(delta)
	_step_locomotion(delta)
	_step_combat(delta)
	advance_facing(delta)


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
# the existing roots; missing ids free their roots. A snapshot arriving
# while a combat sequence runs supersedes it: the presentation cancels
# safely FIRST (authority always wins; historical combat is never replayed
# — sequences only ever start from present_combat on an accepted response).
func apply_snapshot_units(units: Array) -> void:
	cancel_combat_presentation()
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
		_ground_settle_by_unit_id.erase(stale_id)
		_player_by_unit_id.erase(stale_id)
		_grounder_by_unit_id.erase(stale_id)
		_facing_clear(stale_id)


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


# Tells the unit's grounder whether locomotion-mode grounding is active
# (glide or post-arrival Walking→Idle settle). Stationary planting engages
# only when this becomes false after the settle window.
func _set_grounder_locomotion(unit_id: int, active: bool) -> void:
	var grounder = _grounder_by_unit_id.get(unit_id)
	if grounder != null:
		grounder.set_locomotion_active(active)


# Clears combat-only grounder state so Walking/Idle never inherit support
# mode, contact-weight combat selection, or Spine02 attack pitch.
func _clear_combat_grounding_state(unit_id: int) -> void:
	_set_combat_support_grounding(unit_id, false)
	_set_grounder_upper_body_pitch(unit_id, 0.0)


# Keep locomotion-mode sole grounding through the Idle crossfade; plant only
# after ANIM_BLEND_DEFAULT_SEC so authored soles cannot float mid-blend.
func _begin_arrival_ground_settle(unit_id: int) -> void:
	_clear_combat_grounding_state(unit_id)
	_set_grounder_locomotion(unit_id, true)
	_ground_settle_by_unit_id[unit_id] = ANIM_BLEND_DEFAULT_SEC


func _step_ground_settle(delta: float) -> void:
	if _ground_settle_by_unit_id.is_empty() or delta <= 0.0:
		return
	var done: Array = []
	for id_key in _ground_settle_by_unit_id.keys():
		var unit_id := int(id_key)
		var remaining := float(_ground_settle_by_unit_id[unit_id]) - delta
		if remaining <= 0.0:
			done.append(unit_id)
		else:
			_ground_settle_by_unit_id[unit_id] = remaining
	for unit_id in done:
		_ground_settle_by_unit_id.erase(unit_id)
		# Exact arrival already settled the visual; only plants engage now.
		_set_grounder_locomotion(unit_id, false)


# Advances every active glide by delta seconds (called from _process;
# headless tests drive it directly for determinism). Also advances the
# centralized facing controller so move-start turns stay in sync.
func advance_locomotion(delta: float) -> void:
	_step_ground_settle(delta)
	_step_locomotion(delta)
	advance_facing(delta)


func _step_locomotion(delta: float) -> void:
	for id_key in _loco_by_unit_id.keys():
		var unit_id := int(id_key)
		var root: Node3D = _root_by_unit_id.get(unit_id) as Node3D
		if root == null:
			_loco_by_unit_id.erase(unit_id)
			_ground_settle_by_unit_id.erase(unit_id)
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
		# Facing is owned by the centralized facing controller (not snapped
		# every locomotion step).


func _begin_locomotion(unit_id: int, from_pos: Vector3, to_anchor: Vector3) -> void:
	var root: Node3D = _root_by_unit_id.get(unit_id) as Node3D
	if root == null:
		return
	var model_root := _model_root_of(root)
	var flat := Vector3(to_anchor.x - from_pos.x, 0.0, to_anchor.z - from_pos.z)
	var dist := flat.length()
	_ground_settle_by_unit_id.erase(unit_id)
	if dist < 0.0001:
		# Degenerate segment: settle at the anchor pose immediately.
		model_root.position = Vector3.ZERO
		_loco_by_unit_id.erase(unit_id)
		_play_semantic_clip(unit_id, SEMANTIC_IDLE_CLIP)
		_begin_arrival_ground_settle(unit_id)
		return
	var dir := flat / dist
	_loco_by_unit_id[unit_id] = {
		"start": from_pos,
		"end": to_anchor,
		"dir": dir,
		"elapsed": 0.0,
		"duration": maxf(dist / locomotion_translation_speed(), LOCOMOTION_MIN_DURATION_SEC),
	}
	# Visual stays where it was: root moved to the anchor, offset compensates.
	model_root.position = from_pos - to_anchor
	_facing_request_dir(unit_id, dir, true)
	_play_semantic_clip(unit_id, SEMANTIC_WALK_CLIP)
	# Release the stationary foot plants smoothly: the grounder blends the
	# planted anchors out while the walking gait takes over. Also clears any
	# leftover combat-support / attack-pitch state.
	_clear_combat_grounding_state(unit_id)
	_set_grounder_locomotion(unit_id, true)


# Arrival: EXACT final-anchor pose (offset zero), facing retained (yaw
# toward the movement direction), idle clip resumes. Locomotion-mode
# grounding continues through the Walking→Idle crossfade; stationary
# planting engages only after that blend completes.
func _arrive(unit_id: int, seg: Dictionary, root: Node3D) -> void:
	var model_root := _model_root_of(root)
	model_root.position = Vector3.ZERO
	_facing_request_dir(unit_id, seg["dir"] as Vector3, true)
	_loco_by_unit_id.erase(unit_id)
	_play_semantic_clip(unit_id, SEMANTIC_IDLE_CLIP)
	_begin_arrival_ground_settle(unit_id)
	# Large headless advances can overshoot the arrival instant — consume
	# that overshoot against the settle window so planting still engages.
	var overshoot := maxf(float(seg["elapsed"]) - float(seg["duration"]), 0.0)
	if overshoot > 0.0 and _ground_settle_by_unit_id.has(unit_id):
		var remaining := float(_ground_settle_by_unit_id[unit_id]) - overshoot
		if remaining <= 0.0:
			_ground_settle_by_unit_id.erase(unit_id)
			_set_grounder_locomotion(unit_id, false)
		else:
			_ground_settle_by_unit_id[unit_id] = remaining
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


# Instant yaw write (lifecycle / internal). Ordinary gameplay turns must
# go through _facing_request_dir so they blend.
func _apply_visual_yaw(model_root: Node3D, dir: Vector3) -> void:
	model_root.basis = locomotion_yaw(dir) * Basis.from_scale(Vector3.ONE * MODEL_ROOT_SCALE)


# --- N7g.3 combat presentation (presentation-only) ---------------------------


# True while a combat sequence started by present_combat is running.
func combat_active() -> bool:
	return not _combat.is_empty()


# Current stage name for tests/diagnostics ("" = none).
func combat_stage() -> String:
	if _combat.is_empty():
		return ""
	return str(_combat.get("stage", ""))


# Melee staging world position derived for the active sequence (ZERO = none).
func combat_melee_staging() -> Vector3:
	if _combat.is_empty():
		return Vector3.ZERO
	return _combat.get("melee_staging", Vector3.ZERO) as Vector3


# Snapshot-authoritative final attacker anchor for the active sequence
# (absent when the attacker dies). Null Variant when none.
func combat_final_attacker_anchor():
	if _combat.is_empty() or not _combat.has("final_attacker_anchor"):
		return null
	return _combat["final_attacker_anchor"]


# Locked presentation impact delay (seconds).
# Locked melee standoff (tests / diagnostics).
func melee_standoff_distance() -> float:
	return MELEE_STANDOFF_DISTANCE


func combat_impact_delay() -> float:
	return COMBAT_IMPACT_DELAY_SEC


# Locked ordinary facing-blend duration (tests / diagnostics).
func facing_blend_sec() -> float:
	return FACING_BLEND_SEC


# Alias for older combat diagnostics.
func travel_facing_blend_sec() -> float:
	return FACING_BLEND_SEC


# True after continuous corpse support has engaged contact during Dead.
func combat_corpse_contact_active() -> bool:
	return bool(_combat.get("corpse_contact", false))


# Active facing-blend diagnostics for one unit (empty when none / snapped).
func facing_blend_info(unit_id: int) -> Dictionary:
	if not _facing_by_unit_id.has(unit_id):
		return {}
	var st: Dictionary = _facing_by_unit_id[unit_id]
	return {
		"yaw_from": float(st["from"]),
		"yaw_to": float(st["to"]),
		"yaw_elapsed": float(st["elapsed"]),
		"yaw_duration": float(st["duration"]),
	}


# Backward-compatible alias used by combat return-travel tests.
func combat_travel_facing_info() -> Dictionary:
	if _combat.is_empty():
		return {}
	return facing_blend_info(int(_combat.get("attacker_id", -1)))


# Locked per-vertebra attack-pitch clamp (radians).
func attack_pitch_max_rad() -> float:
	return ATTACK_PITCH_MAX_RAD


# Total bounded aim-chain clamp (Spine02 + Spine01, half each).
func attack_pitch_chain_max_rad() -> float:
	return ATTACK_PITCH_CHAIN_MAX_RAD


# Starts the deterministic combat presentation for one ACCEPTED
# authoritative attack_unit event + its deferred response snapshot.
# Outcomes come ONLY from the event flags; the attacker's final
# presentation destination comes ONLY from the deferred snapshot unit
# position (never inferred from defender_killed alone). Returns false —
# presenting NOTHING — on any validation failure so the caller falls back
# to immediate authoritative reconciliation.
func present_combat(event: Dictionary, deferred_snapshot: Dictionary = {}) -> bool:
	if combat_active():
		return false
	var plan := _combat_plan_from_event(event, deferred_snapshot)
	if plan.is_empty():
		return false
	_combat = plan
	_start_combat_approach()
	return true


# Advances the active combat sequence by delta seconds (called from
# _process; headless tests drive it directly for determinism).
func advance_combat(delta: float) -> void:
	# Combat-only headless drivers never call advance_locomotion; still step
	# the post-Idle settle so planting engages after survivor restore.
	_step_ground_settle(delta)
	_step_combat(delta)
	advance_facing(delta)


func _step_combat(delta: float) -> void:
	if _combat.is_empty() or delta <= 0.0:
		return
	var stage := str(_combat["stage"])
	match stage:
		"approach":
			_advance_combat_approach(delta)
		"exchange":
			_advance_combat_exchange(delta)
		"retaliation":
			_advance_combat_retaliation(delta)
		"death":
			_advance_combat_death(delta)
		"survivor_travel":
			_advance_combat_survivor_travel(delta)
		_:
			_finish_combat_presentation()


# Cancels an active sequence WITHOUT emitting the finished signal (used by
# superseding snapshot applies and teardown): presentation travel/offsets/
# pitch/roll are cleared, participants snap back to their pre-combat
# authoritative anchors with idle + resumed grounders. The authoritative
# reconcile that follows owns all further state, including removals.
func cancel_combat_presentation() -> void:
	if _combat.is_empty():
		return
	var attacker_id := int(_combat["attacker_id"])
	var defender_id := int(_combat["defender_id"])
	var pre_a: Vector3 = _combat["pre_attacker_anchor"]
	var pre_d: Vector3 = _combat["pre_defender_anchor"]
	_combat = {}
	_facing_clear(attacker_id)
	_facing_clear(defender_id)
	_snap_combatant_to_anchor(attacker_id, pre_a)
	_snap_combatant_to_anchor(defender_id, pre_d)
	_restore_combatant_to_idle(attacker_id)
	_restore_combatant_to_idle(defender_id)


# Validates the accepted event + deferred snapshot + participants and
# builds the combat plan ({} when anything is unusable). Retaliation is
# honored ONLY when the defender survived. The attacker's final
# destination is read from the deferred snapshot and checked for
# consistency with the occupation rule — never invented locally.
func _combat_plan_from_event(event: Dictionary, deferred_snapshot: Dictionary) -> Dictionary:
	for key in ["attacker_id", "defender_id", "attacker_killed", "defender_killed", "retaliated"]:
		if not event.has(key):
			return {}
	for key in ["attacker_id", "defender_id"]:
		var t := typeof(event[key])
		if t != TYPE_INT and t != TYPE_FLOAT:
			return {}
	for key in ["attacker_killed", "defender_killed", "retaliated"]:
		if typeof(event[key]) != TYPE_BOOL:
			return {}
	var attacker_id := int(event["attacker_id"])
	var defender_id := int(event["defender_id"])
	if attacker_id == defender_id:
		return {}
	for uid in [attacker_id, defender_id]:
		if _root_by_unit_id.get(uid) == null or _player_by_unit_id.get(uid) == null:
			return {}
		if is_unit_moving(uid):
			return {}
	var attacker_killed := bool(event["attacker_killed"])
	var defender_killed := bool(event["defender_killed"])
	# Never animate retaliation after defender death even if a malformed
	# event claims it.
	var retaliated := bool(event["retaliated"]) and not defender_killed
	if attacker_killed and defender_killed:
		return {}
	for semantic in [SEMANTIC_ATTACK_CLIP, SEMANTIC_HIT_CLIP, SEMANTIC_DEAD_CLIP, SEMANTIC_WALK_CLIP, SEMANTIC_IDLE_CLIP]:
		if not _semantic_clip_available(attacker_id, semantic):
			return {}
	for semantic in [SEMANTIC_ATTACK_CLIP, SEMANTIC_HIT_CLIP, SEMANTIC_DEAD_CLIP, SEMANTIC_IDLE_CLIP]:
		if not _semantic_clip_available(defender_id, semantic):
			return {}
	var att_root: Node3D = _root_by_unit_id[attacker_id] as Node3D
	var def_root: Node3D = _root_by_unit_id[defender_id] as Node3D
	var pre_a: Vector3 = att_root.position
	var pre_d: Vector3 = def_root.position
	var face := Vector3(pre_d.x - pre_a.x, 0.0, pre_d.z - pre_a.z)
	if face.length_squared() < 0.000001:
		return {}
	face = face.normalized()
	var staging := pre_d - face * MELEE_STANDOFF_DISTANCE
	var sampled_staging := _sample_surface(staging)
	if bool(sampled_staging["ok"]):
		staging.y = float(sampled_staging["height"])
	else:
		staging.y = lerpf(pre_a.y, pre_d.y, 1.0 - MELEE_STANDOFF_DISTANCE / maxf(pre_a.distance_to(pre_d), 0.001))
	var resolved: Dictionary = _resolve_final_attacker_anchor(
		deferred_snapshot, attacker_id, attacker_killed, defender_killed, pre_a, pre_d
	)
	if not bool(resolved.get("ok", false)):
		return {}
	return {
		"attacker_id": attacker_id,
		"defender_id": defender_id,
		"attacker_killed": attacker_killed,
		"defender_killed": defender_killed,
		"retaliated": retaliated,
		"pre_attacker_anchor": pre_a,
		"pre_defender_anchor": pre_d,
		"melee_staging": staging,
		"face_dir": face,
		"final_attacker_anchor": resolved.get("anchor", null),
		"stage": "approach",
		"travel": {},
		"attack_elapsed": 0.0,
		"attack_duration": 0.0,
		"hit_started": false,
		"hit_elapsed": 0.0,
		"hit_duration": 0.0,
		"death_unit_id": -1,
		"death_elapsed": 0.0,
		"death_duration": 0.0,
		"finished_emitted": false,
	}


# Reads the attacker's resulting authoritative tile from the deferred
# snapshot. Returns {"ok": bool, "anchor": Vector3|null}. Client never
# invents occupation — inconsistent/malformed results fail closed.
func _resolve_final_attacker_anchor(
	snap: Dictionary,
	attacker_id: int,
	attacker_killed: bool,
	defender_killed: bool,
	pre_a: Vector3,
	pre_d: Vector3
) -> Dictionary:
	var fail := {"ok": false, "anchor": null}
	if typeof(snap) != TYPE_DICTIONARY:
		return fail
	var units = snap.get("units", null)
	if typeof(units) != TYPE_ARRAY:
		return fail
	var found = null
	var count := 0
	for row_variant in units:
		if typeof(row_variant) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_variant
		if int(row.get("id", -1)) != attacker_id:
			continue
		count += 1
		found = row
	if attacker_killed:
		return {"ok": count == 0, "anchor": null}
	if count != 1 or found == null:
		return fail
	var pos = found.get("position", null)
	if typeof(pos) != TYPE_ARRAY or (pos as Array).size() != 2:
		return fail
	var key := Vector2i(int(pos[0]), int(pos[1]))
	if not _tile_anchors.has(key):
		return fail
	var anchor: Vector3 = _tile_anchors[key]
	# Consistency with the locked occupation rule (positions are authoritative;
	# refuse an inconsistent pair so presentation cannot disagree).
	var want_capture := defender_killed and not attacker_killed
	var at_original := anchor.distance_to(pre_a) < 0.001
	var at_defender := anchor.distance_to(pre_d) < 0.001
	if want_capture and not at_defender:
		return fail
	if not want_capture and not at_original:
		return fail
	return {"ok": true, "anchor": anchor}


func _start_combat_approach() -> void:
	var attacker_id := int(_combat["attacker_id"])
	var staging: Vector3 = _combat["melee_staging"]
	var from_pos := visual_position_for_unit(attacker_id)
	_ground_settle_by_unit_id.erase(attacker_id)
	_set_combat_grounder_paused(attacker_id, false)
	_set_combat_grounder_paused(int(_combat["defender_id"]), false)
	_set_combat_support_grounding(attacker_id, false)
	_set_combat_support_grounding(int(_combat["defender_id"]), false)
	_set_grounder_locomotion(attacker_id, true)
	_play_semantic_clip(attacker_id, SEMANTIC_WALK_CLIP)
	_combat["travel"] = _make_combat_travel(attacker_id, from_pos, staging)
	var travel_dir: Vector3 = _combat["travel"].get("dir", Vector3.ZERO)
	if travel_dir.length_squared() > 0.000001:
		_facing_request_dir(attacker_id, travel_dir, true)
	_combat["stage"] = "approach"


func _advance_combat_approach(delta: float) -> void:
	if not _step_combat_travel(delta):
		return
	# Arrived at melee staging: blend face-each-other; enable support-foot
	# grounding for living one-shots (not full pause — Dead still pauses).
	var attacker_id := int(_combat["attacker_id"])
	var defender_id := int(_combat["defender_id"])
	var face: Vector3 = _combat["face_dir"]
	_place_visual_at(attacker_id, _combat["melee_staging"] as Vector3)
	_facing_request_dir(attacker_id, face, true)
	_facing_request_dir(defender_id, -face, true)
	_set_grounder_locomotion(attacker_id, false)
	_set_grounder_locomotion(defender_id, false)
	# Attacker enters Left_Slash under combat-support. Defender stays on
	# ordinary Idle plants until Hit_Reaction_1 starts — enabling support
	# early suppressed plants and left the waiting defender hovering.
	_set_combat_support_grounding(attacker_id, true)
	_set_combat_support_grounding(defender_id, false)
	_start_combat_exchange()


func _start_combat_exchange() -> void:
	var attacker_id := int(_combat["attacker_id"])
	var length := _play_semantic_clip_one_shot(attacker_id, SEMANTIC_ATTACK_CLIP)
	if length <= 0.0:
		_finish_combat_presentation()
		return
	_combat["stage"] = "exchange"
	_combat["attack_elapsed"] = 0.0
	_combat["attack_duration"] = length
	_combat["hit_started"] = false
	_combat["hit_elapsed"] = 0.0
	_combat["hit_duration"] = 0.0
	_combat["attack_pitch_unit_id"] = attacker_id
	# Commit the strike: canonical contact captured once per swing.
	_combat["aim_target_w"] = _combat_aim_target_world(int(_combat["defender_id"]))
	_combat["aim_pivot_shift_y"] = _combat_aim_pivot_shift_y(attacker_id)


func _advance_combat_exchange(delta: float) -> void:
	_combat["attack_elapsed"] = float(_combat["attack_elapsed"]) + delta
	_tick_living_combat_presentation(delta)
	if not bool(_combat["hit_started"]) and float(_combat["attack_elapsed"]) >= COMBAT_IMPACT_DELAY_SEC:
		var defender_id := int(_combat["defender_id"])
		# Fatal: Dead starts at impact (it already contains the hit reaction).
		# Non-fatal: Hit_Reaction_1 at the same delay. Attack may continue.
		# The swing's additive aim is NOT cleared here: killing the defender
		# changes the DEFENDER's reaction, never the incoming strike —
		# clearing at this tick snapped the club back to the unpitched
		# (visibly too high) trajectory in the middle of the contact window.
		# The death stage rides the aim out for the rest of the swing.
		if bool(_combat["defender_killed"]):
			_combat["hit_started"] = true
			_start_combat_death(defender_id)
			return
		var hit_len := _play_semantic_clip_one_shot(defender_id, SEMANTIC_HIT_CLIP)
		if hit_len <= 0.0:
			_finish_combat_presentation()
			return
		_set_combat_support_grounding(defender_id, true)
		_combat["hit_started"] = true
		_combat["hit_elapsed"] = 0.0
		_combat["hit_duration"] = hit_len
	if not bool(_combat["hit_started"]):
		return
	# Fatal branch already left this stage for "death".
	if bool(_combat["defender_killed"]):
		return
	_combat["hit_elapsed"] = float(_combat["hit_elapsed"]) + delta
	if float(_combat["hit_elapsed"]) < float(_combat["hit_duration"]):
		return
	_clear_attack_pitch()
	if bool(_combat["retaliated"]):
		_start_combat_retaliation()
	else:
		_start_combat_survivor_travel()


func _start_combat_retaliation() -> void:
	var attacker_id := int(_combat["attacker_id"])
	var defender_id := int(_combat["defender_id"])
	var length := _play_semantic_clip_one_shot(defender_id, SEMANTIC_ATTACK_CLIP)
	if length <= 0.0:
		_finish_combat_presentation()
		return
	_set_combat_support_grounding(defender_id, true)
	# Original attacker leaves its outgoing Left_Slash / aim state and waits
	# on ordinary Idle plants until the counterattack hit — same role as the
	# defender's Idle wait before the initial Hit_Reaction_1.
	_set_combat_support_grounding(attacker_id, false)
	_set_grounder_locomotion(attacker_id, false)
	_set_grounder_upper_body_pitch(attacker_id, 0.0)
	_play_semantic_clip(attacker_id, SEMANTIC_IDLE_CLIP)
	_combat["stage"] = "retaliation"
	_combat["attack_elapsed"] = 0.0
	_combat["attack_duration"] = length
	_combat["hit_started"] = false
	_combat["hit_elapsed"] = 0.0
	_combat["hit_duration"] = 0.0
	_combat["attack_pitch_unit_id"] = defender_id
	# The counter-swing commits to ITS victim's contact (the original
	# attacker), replacing the initial swing's cached target.
	_combat["aim_target_w"] = _combat_aim_target_world(attacker_id)
	_combat["aim_pivot_shift_y"] = _combat_aim_pivot_shift_y(defender_id)


func _advance_combat_retaliation(delta: float) -> void:
	_combat["attack_elapsed"] = float(_combat["attack_elapsed"]) + delta
	_tick_living_combat_presentation(delta)
	if not bool(_combat["hit_started"]) and float(_combat["attack_elapsed"]) >= COMBAT_IMPACT_DELAY_SEC:
		var attacker_id := int(_combat["attacker_id"])
		# Same fatal/non-fatal impact rule as the initial exchange — the
		# counter-swing's aim also rides out through the death stage.
		if bool(_combat["attacker_killed"]):
			_combat["hit_started"] = true
			_start_combat_death(attacker_id)
			return
		var hit_len := _play_semantic_clip_one_shot(attacker_id, SEMANTIC_HIT_CLIP)
		if hit_len <= 0.0:
			_finish_combat_presentation()
			return
		# Victim receives authored Hit_Reaction_1 with no leftover slash pitch.
		_set_grounder_upper_body_pitch(attacker_id, 0.0)
		_set_combat_support_grounding(attacker_id, true)
		_combat["hit_started"] = true
		_combat["hit_elapsed"] = 0.0
		_combat["hit_duration"] = hit_len
	if not bool(_combat["hit_started"]):
		return
	if bool(_combat["attacker_killed"]):
		return
	_combat["hit_elapsed"] = float(_combat["hit_elapsed"]) + delta
	if float(_combat["hit_elapsed"]) < float(_combat["hit_duration"]):
		return
	_clear_attack_pitch()
	_start_combat_survivor_travel()


func _start_combat_death(unit_id: int) -> void:
	var length := _play_semantic_clip_one_shot(unit_id, SEMANTIC_DEAD_CLIP)
	if length <= 0.0:
		_finish_combat_presentation()
		return
	# Dead: full grounder pause + no facing blends / attack pitch on corpse.
	_set_combat_support_grounding(unit_id, false)
	_set_combat_grounder_paused(unit_id, true)
	_set_grounder_upper_body_pitch(unit_id, 0.0)
	_facing_clear(unit_id)
	_combat["stage"] = "death"
	_combat["death_unit_id"] = unit_id
	_combat["death_elapsed"] = 0.0
	_combat["death_duration"] = length
	_combat["corpse_contact"] = false
	_combat["corpse_last_support_y"] = visual_position_for_unit(unit_id).y
	_sync_death_animation_pose(unit_id, 0.0)


func _advance_combat_death(delta: float) -> void:
	_tick_lethal_swing_aim(delta)
	_combat["death_elapsed"] = float(_combat["death_elapsed"]) + delta
	var dead_id := int(_combat["death_unit_id"])
	var elapsed := float(_combat["death_elapsed"])
	var duration := float(_combat["death_duration"])
	var t := minf(elapsed, duration)
	# Keep the authored Dead pose in sync even when tests drive advance_combat
	# with process disabled — continuous support reads animated bones.
	_sync_death_animation_pose(dead_id, t)
	var final_pass := elapsed >= duration
	# Continuous multi-point support from first contact through final freeze.
	if not _update_corpse_terrain_support(dead_id, final_pass):
		_finish_combat_presentation()
		return
	if not final_pass:
		return
	_freeze_death_animation(dead_id)
	if bool(_combat["attacker_killed"]):
		# No return/occupation traversal for a dead attacker.
		_finish_combat_presentation()
	else:
		_start_combat_survivor_travel()


func _start_combat_survivor_travel() -> void:
	var attacker_id := int(_combat["attacker_id"])
	if bool(_combat["attacker_killed"]):
		_finish_combat_presentation()
		return
	var dest = _combat.get("final_attacker_anchor", null)
	if typeof(dest) != TYPE_VECTOR3:
		_finish_combat_presentation()
		return
	var to_anchor: Vector3 = dest
	var from_pos := visual_position_for_unit(attacker_id)
	_ground_settle_by_unit_id.erase(attacker_id)
	_clear_attack_pitch()
	_set_combat_support_grounding(attacker_id, false)
	_set_combat_grounder_paused(attacker_id, false)
	_set_grounder_locomotion(attacker_id, true)
	# Walking crossfade + centralized facing blend start together.
	_play_semantic_clip(attacker_id, SEMANTIC_WALK_CLIP)
	_combat["travel"] = _make_combat_travel(attacker_id, from_pos, to_anchor)
	var travel_dir: Vector3 = _combat["travel"].get("dir", Vector3.ZERO)
	if travel_dir.length_squared() > 0.000001:
		_facing_request_dir(attacker_id, travel_dir, true)
	_combat["stage"] = "survivor_travel"


func _advance_combat_survivor_travel(delta: float) -> void:
	if not _step_combat_travel(delta):
		return
	var attacker_id := int(_combat["attacker_id"])
	var defender_id := int(_combat["defender_id"])
	var dest: Vector3 = _combat["final_attacker_anchor"]
	var occupied := bool(_combat["defender_killed"])
	# Settle the authoritative root on the snapshot-final anchor so the
	# deferred apply is idempotent (no second glide / teleport).
	_settle_combatant_at_anchor(attacker_id, dest)
	_set_grounder_locomotion(attacker_id, false)
	if occupied:
		# Occupation: keep the travel-arrival facing. Never reuse the
		# return-path 180° restoration (face_back toward the defender).
		var travel: Dictionary = _combat.get("travel", {})
		var travel_dir: Vector3 = travel.get("dir", Vector3.ZERO) as Vector3
		if travel_dir.length_squared() > 0.000001:
			_facing_request_dir(attacker_id, travel_dir, false)
	elif _root_by_unit_id.get(defender_id) != null:
		# Return home: turn ~180° from return travel to face the defender
		# again (restore the post-approach / pre-return facing).
		var face_back := Vector3(
			(_combat["pre_defender_anchor"] as Vector3).x - dest.x,
			0.0,
			(_combat["pre_defender_anchor"] as Vector3).z - dest.z
		)
		if face_back.length_squared() > 0.000001:
			_facing_request_dir(attacker_id, face_back, true)
	_restore_combatant_to_idle(attacker_id)
	if not occupied:
		_restore_combatant_to_idle(defender_id)
	_finish_combat_presentation()


func _finish_combat_presentation() -> void:
	if _combat.is_empty() or bool(_combat.get("finished_emitted", false)):
		return
	var attacker_id := int(_combat["attacker_id"])
	var defender_id := int(_combat["defender_id"])
	var attacker_killed := bool(_combat["attacker_killed"])
	var defender_killed := bool(_combat["defender_killed"])
	_combat["finished_emitted"] = true
	# Survivors that never took the survivor_travel path (edge failure) still
	# get idle/grounder restoration; killed units stay on their Dead/corpse pose.
	if not attacker_killed and str(_combat.get("stage", "")) != "survivor_travel":
		_restore_combatant_to_idle(attacker_id)
	if not defender_killed:
		_restore_combatant_to_idle(defender_id)
	_combat = {}
	combat_presentation_finished.emit(attacker_id, defender_id)


func _make_combat_travel(unit_id: int, from_pos: Vector3, to_pos: Vector3) -> Dictionary:
	var flat := Vector3(to_pos.x - from_pos.x, 0.0, to_pos.z - from_pos.z)
	var dist := flat.length()
	var dir := flat / dist if dist > 0.0001 else Vector3.ZERO
	return {
		"unit_id": unit_id,
		"start": from_pos,
		"end": to_pos,
		"dir": dir,
		"elapsed": 0.0,
		"duration": maxf(dist / locomotion_translation_speed(), LOCOMOTION_MIN_DURATION_SEC) if dist > 0.0001 else 0.0,
	}


# Steps presentation-only combat travel. Returns true when the segment has
# settled. Facing is owned by the centralized facing controller. Never
# touches _loco_by_unit_id and never emits unit_arrived.
func _step_combat_travel(delta: float) -> bool:
	var travel: Dictionary = _combat.get("travel", {})
	if travel.is_empty():
		return true
	var unit_id := int(travel["unit_id"])
	var root: Node3D = _root_by_unit_id.get(unit_id) as Node3D
	if root == null:
		_combat["travel"] = {}
		return true
	var duration := float(travel["duration"])
	if duration <= 0.0:
		_place_visual_at(unit_id, travel["end"] as Vector3)
		_combat["travel"] = {}
		return true
	travel["elapsed"] = float(travel["elapsed"]) + delta
	var s: float = clampf(float(travel["elapsed"]) / duration, 0.0, 1.0)
	var pos: Vector3 = (travel["start"] as Vector3).lerp(travel["end"] as Vector3, s)
	var sampled := _sample_surface(pos)
	if bool(sampled["ok"]):
		pos.y = float(sampled["height"])
	_place_visual_at(unit_id, pos)
	_combat["travel"] = travel
	if s < 1.0:
		return false
	_place_visual_at(unit_id, travel["end"] as Vector3)
	_combat["travel"] = {}
	return true


static func _yaw_angle_for_dir(dir: Vector3) -> float:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.000001:
		return 0.0
	flat = flat.normalized()
	return atan2(-flat.x, -flat.z)


static func _current_visual_yaw_angle(model_root: Node3D) -> float:
	# ModelRoot local −Z is the locked effective forward (see locomotion_yaw).
	var forward := -model_root.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.000001:
		return 0.0
	forward = forward.normalized()
	return atan2(-forward.x, -forward.z)


func _apply_visual_yaw_angle(model_root: Node3D, yaw: float) -> void:
	model_root.basis = Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3.ONE * MODEL_ROOT_SCALE)


# --- centralized facing controller (ordinary gameplay turns) ---------------


# Shortest-arc yaw request. smooth=false snaps (lifecycle / already aligned).
func _facing_request_dir(unit_id: int, dir: Vector3, smooth: bool = true) -> void:
	if _facing_blocked(unit_id):
		return
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.000001:
		return
	var root: Node3D = _root_by_unit_id.get(unit_id) as Node3D
	if root == null:
		return
	var model_root := _model_root_of(root)
	var yaw_to := _yaw_angle_for_dir(flat)
	var yaw_from := _current_visual_yaw_angle(model_root)
	if not smooth or absf(angle_difference(yaw_from, yaw_to)) <= 0.05:
		_facing_snap_yaw(unit_id, yaw_to)
		return
	var existing: Dictionary = _facing_by_unit_id.get(unit_id, {})
	if not existing.is_empty() and absf(angle_difference(float(existing.get("to", yaw_to)), yaw_to)) < 0.02:
		# Same target — keep progress (never restart a converging blend).
		existing["to"] = yaw_to
		_facing_by_unit_id[unit_id] = existing
		return
	_facing_by_unit_id[unit_id] = {
		"from": yaw_from,
		"to": yaw_to,
		"elapsed": 0.0,
		"duration": FACING_BLEND_SEC,
	}


func _facing_snap_yaw(unit_id: int, yaw: float) -> void:
	_facing_by_unit_id.erase(unit_id)
	if _facing_blocked(unit_id):
		return
	var root: Node3D = _root_by_unit_id.get(unit_id) as Node3D
	if root == null:
		return
	_apply_visual_yaw_angle(_model_root_of(root), yaw)


func _facing_clear(unit_id: int) -> void:
	_facing_by_unit_id.erase(unit_id)


# Frozen / pitched corpses must not be rotated by ordinary facing blends.
func _facing_blocked(unit_id: int) -> bool:
	if not _combat.is_empty() and int(_combat.get("death_unit_id", -1)) == unit_id:
		return true
	var root: Node3D = _root_by_unit_id.get(unit_id) as Node3D
	if root == null:
		return true
	var up := _model_root_of(root).basis.y.normalized()
	return up.dot(Vector3.UP) < 0.98


func advance_facing(delta: float) -> void:
	if delta <= 0.0 or _facing_by_unit_id.is_empty():
		return
	var done: Array = []
	for id_key in _facing_by_unit_id.keys():
		var unit_id := int(id_key)
		if _facing_blocked(unit_id):
			done.append(unit_id)
			continue
		var root: Node3D = _root_by_unit_id.get(unit_id) as Node3D
		if root == null:
			done.append(unit_id)
			continue
		var st: Dictionary = _facing_by_unit_id[unit_id]
		st["elapsed"] = float(st["elapsed"]) + delta
		var duration := float(st["duration"])
		var t := 1.0 if duration <= 0.0 else clampf(float(st["elapsed"]) / duration, 0.0, 1.0)
		var yaw := lerp_angle(float(st["from"]), float(st["to"]), t)
		_apply_visual_yaw_angle(_model_root_of(root), yaw)
		if t >= 1.0:
			done.append(unit_id)
		else:
			_facing_by_unit_id[unit_id] = st
	for unit_id in done:
		_facing_by_unit_id.erase(unit_id)


# --- living combat one-shot support (grounding + localized attack pitch) ---


func _set_combat_support_grounding(unit_id: int, active: bool) -> void:
	var grounder = _grounder_by_unit_id.get(unit_id)
	if grounder != null:
		grounder.set_combat_support_grounding(active)


func _set_grounder_upper_body_pitch(
	unit_id: int, pitch: float, right_w: Vector3 = Vector3.ZERO
) -> void:
	var grounder = _grounder_by_unit_id.get(unit_id)
	if grounder != null:
		grounder.set_upper_body_pitch(pitch, right_w)


func _clear_attack_pitch() -> void:
	if _combat.is_empty():
		return
	var uid := int(_combat.get("attack_pitch_unit_id", -1))
	if uid >= 0:
		_set_grounder_upper_body_pitch(uid, 0.0)
	_combat.erase("attack_pitch_unit_id")
	_combat.erase("attack_pitch_right_w")


# Sync one-shot poses to combat elapsed time, ground support feet, then aim
# the swinging unit's striking hand at the defender's fixed Spine01 contact.
func _tick_living_combat_presentation(_delta: float) -> void:
	var attacker_id := int(_combat["attacker_id"])
	var defender_id := int(_combat["defender_id"])
	var pitch_uid := int(_combat.get("attack_pitch_unit_id", -1))
	var death_uid := int(_combat.get("death_unit_id", -1))
	var stage := str(_combat.get("stage", ""))
	# Role-owned clocks: attack_elapsed drives the current Left_Slash only.
	# Seeking the original attacker to attack_elapsed during retaliation was
	# scrubbing its Hit_Reaction_1 (and leftover slash) onto the counter
	# swing timeline — the counterattack-only hit corruption.
	var swing_id := defender_id if stage == "retaliation" else attacker_id
	var hit_id := attacker_id if stage == "retaliation" else defender_id
	if swing_id != death_uid:
		_seek_combat_clip(swing_id, float(_combat.get("attack_elapsed", 0.0)))
	if (
		hit_id != death_uid
		and bool(_combat.get("hit_started", false))
		and not (stage != "retaliation" and bool(_combat.get("defender_killed", false)))
		and not (stage == "retaliation" and bool(_combat.get("attacker_killed", false)))
	):
		_seek_combat_clip(hit_id, float(_combat.get("hit_elapsed", 0.0)))
	# Clear pitch before measuring the geometric hand→target angle so the
	# correction is computed from the authored slash pose, not a prior lean.
	if pitch_uid >= 0 and pitch_uid != death_uid:
		_set_grounder_upper_body_pitch(pitch_uid, 0.0)
	for uid in [attacker_id, defender_id]:
		if uid == death_uid:
			continue
		var grounder = _grounder_by_unit_id.get(uid)
		if grounder == null:
			continue
		# Idle-waiting defender uses ordinary plants; combat-support units
		# get an explicit support pass (engine modifier also runs on tick).
		if grounder.is_combat_support_grounding() or not grounder.is_locomotion_active():
			grounder.apply_grounding_now(-1.0)
	if pitch_uid < 0 or pitch_uid == death_uid:
		return
	var other := defender_id if pitch_uid == attacker_id else attacker_id
	var aim: Dictionary = _combat_aim_pitch(pitch_uid, other)
	var target: float = float(aim.get("pitch", 0.0))
	var right_w: Vector3 = aim.get("right_w", Vector3.ZERO) as Vector3
	var elapsed := float(_combat["attack_elapsed"])
	var duration := float(_combat["attack_duration"])
	var w_in := clampf(elapsed / ATTACK_PITCH_BLEND_SEC, 0.0, 1.0)
	var w_out := clampf((duration - elapsed) / ATTACK_PITCH_BLEND_SEC, 0.0, 1.0)
	_combat["attack_pitch_right_w"] = right_w
	_set_grounder_upper_body_pitch(pitch_uid, target * minf(w_in, w_out), right_w)
	var grounder_p = _grounder_by_unit_id.get(pitch_uid)
	if grounder_p != null and grounder_p.is_combat_support_grounding():
		grounder_p.apply_grounding_now(-1.0)


# The killing swing continues while its victim's Dead plays. Keep the
# committed per-swing aim (cached target — never resampled from the
# falling body) through the remainder of the swing, exactly like the
# matched non-fatal strike, then clear it once the one-shot completes.
func _tick_lethal_swing_aim(delta: float) -> void:
	var pitch_uid := int(_combat.get("attack_pitch_unit_id", -1))
	var death_uid := int(_combat.get("death_unit_id", -1))
	if pitch_uid < 0 or pitch_uid == death_uid:
		return
	_combat["attack_elapsed"] = float(_combat["attack_elapsed"]) + delta
	var elapsed := float(_combat["attack_elapsed"])
	var duration := float(_combat["attack_duration"])
	if elapsed >= duration:
		_clear_attack_pitch()
		return
	_seek_combat_clip(pitch_uid, elapsed)
	_set_grounder_upper_body_pitch(pitch_uid, 0.0)
	var attacker_id := int(_combat["attacker_id"])
	var defender_id := int(_combat["defender_id"])
	var other := defender_id if pitch_uid == attacker_id else attacker_id
	var aim: Dictionary = _combat_aim_pitch(pitch_uid, other)
	var right_w: Vector3 = aim.get("right_w", Vector3.ZERO) as Vector3
	var w_in := clampf(elapsed / ATTACK_PITCH_BLEND_SEC, 0.0, 1.0)
	var w_out := clampf((duration - elapsed) / ATTACK_PITCH_BLEND_SEC, 0.0, 1.0)
	_combat["attack_pitch_right_w"] = right_w
	_set_grounder_upper_body_pitch(
		pitch_uid, float(aim.get("pitch", 0.0)) * minf(w_in, w_out), right_w
	)
	var grounder_p = _grounder_by_unit_id.get(pitch_uid)
	if grounder_p != null and grounder_p.is_combat_support_grounding():
		grounder_p.apply_grounding_now(-1.0)


func _seek_combat_clip(unit_id: int, elapsed: float) -> void:
	var player: AnimationPlayer = _player_by_unit_id.get(unit_id) as AnimationPlayer
	if player == null or not player.is_playing():
		return
	var anim := player.current_animation
	if anim == "" or not player.has_animation(anim):
		return
	var length := maxf(float(player.get_animation(anim).length), 0.0)
	player.seek(clampf(elapsed, 0.0, length), true)


# Total world angle + axis that rotate the authored impact-phase strike
# endpoint (club head) to the cached defender contact HEIGHT about a
# horizontal axis. Solved from per-swing-stable quantities only — the
# ModelRoot transform, the model-local authored impact endpoint/pivot, and
# the contact point cached at swing start — never from the live mid-swing
# hand pose (chasing the swinging hand made both magnitude and trial sign
# chatter frame to frame). Hit_Reaction_1 is never retargeted.
func _combat_aim_pitch(attacker_id: int, defender_id: int) -> Dictionary:
	_refresh_unit_transforms(attacker_id)
	var root: Node3D = _root_by_unit_id.get(attacker_id) as Node3D
	if root == null:
		return {"pitch": 0.0, "right_w": Vector3.RIGHT}
	# Equal supported elevation: keep the authored neutral Left_Slash (the
	# measured baseline — the neutral endpoint passes the contact height).
	var origin := visual_position_for_unit(attacker_id)
	var def_pos := visual_position_for_unit(defender_id)
	if absf(_combat_aim_contact_y(origin) - _combat_aim_contact_y(def_pos)) < 0.06:
		return {"pitch": 0.0, "right_w": Vector3.RIGHT}
	var target: Vector3 = _combat.get("aim_target_w", Vector3.INF) as Vector3
	if target == Vector3.INF:
		target = _combat_aim_target_world(defender_id)
	if target == Vector3.INF:
		return {"pitch": 0.0, "right_w": Vector3.RIGHT}
	var xf: Transform3D = _model_root_of(root).global_transform
	var endpoint: Vector3 = xf * ATTACK_IMPACT_ENDPOINT_MODEL
	var pivot: Vector3 = xf * ATTACK_IMPACT_PIVOT_MODEL
	# Per-swing grounding calibration: on slopes the pelvis solve lowers the
	# whole upper body, shifting the real chain relative to the flat-derived
	# model constants (measured ~0.1 world on the reference slope).
	var shift_y := float(_combat.get("aim_pivot_shift_y", 0.0))
	endpoint.y += shift_y
	pivot.y += shift_y
	var los_xz := Vector3(target.x - pivot.x, 0.0, target.z - pivot.z)
	if los_xz.length_squared() < 0.000001:
		return {"pitch": 0.0, "right_w": Vector3.RIGHT}
	var fwd := los_xz.normalized()
	# Axis convention: with axis = fwd × UP, rotating by +θ RAISES the
	# endpoint's elevation in the fwd/up plane (d/dθ = axis × v; on the
	# forward direction (axis × fwd)·UP = +1), so θ = e_target − e_endpoint
	# needs no trial sign.
	var right_w := fwd.cross(Vector3.UP).normalized()
	var v: Vector3 = endpoint - pivot
	var v_p: Vector3 = v - right_w * v.dot(right_w)
	var r := v_p.length()
	if r < 0.0001:
		return {"pitch": 0.0, "right_w": right_w}
	var e0 := atan2(v_p.dot(Vector3.UP), v_p.dot(fwd))
	# Solve the endpoint HEIGHT at the impact phase: pivot_y + r·sin(e) must
	# equal the contact height. Contacts beyond the arc's vertical reach
	# saturate at the extreme elevation before the chain clamp applies.
	var sin_new := clampf((target.y - pivot.y) / r, -1.0, 1.0)
	var theta := clampf(asin(sin_new) - e0, -ATTACK_PITCH_CHAIN_MAX_RAD, ATTACK_PITCH_CHAIN_MAX_RAD)
	if absf(theta) < 0.000001:
		return {"pitch": 0.0, "right_w": right_w}
	return {"pitch": theta, "right_w": right_w}


func _combat_aim_pitch_rad(attacker_id: int, defender_id: int) -> float:
	return float(_combat_aim_pitch(attacker_id, defender_id).get("pitch", 0.0))


# Vertical delta between the swinging unit's LIVE Spine02 (final grounded
# pose) and the flat-derived model-constant pivot, captured once per swing.
func _combat_aim_pivot_shift_y(unit_id: int) -> float:
	var root: Node3D = _root_by_unit_id.get(unit_id) as Node3D
	if root == null:
		return 0.0
	var live := _bone_world_position(unit_id, "Spine02")
	if live == Vector3.INF:
		return 0.0
	var modeled: Vector3 = _model_root_of(root).global_transform * ATTACK_IMPACT_PIVOT_MODEL
	return live.y - modeled.y


# Canonical defender contact: the authored Head-region world position when
# the swing starts (cached per swing — a committed strike must not chase a
# falling/reacting body). Fallback: sampled surface + contact height.
func _combat_aim_target_world(defender_id: int) -> Vector3:
	var bone := _bone_world_position(defender_id, ATTACK_TARGET_BONE)
	if bone != Vector3.INF:
		return bone
	var root: Node3D = _root_by_unit_id.get(defender_id) as Node3D
	if root == null:
		return Vector3.INF
	var pos := visual_position_for_unit(defender_id)
	return Vector3(pos.x, _combat_aim_contact_y(pos), pos.z)


func _combat_aim_contact_y(visual_pos: Vector3) -> float:
	var sample := _sample_surface(visual_pos)
	var surface_y := float(sample["height"]) if bool(sample["ok"]) else visual_pos.y
	return surface_y + ATTACK_AIM_TORSO_HEIGHT


# Final post-transform world position of the visible striking endpoint:
# the club head rigidly skinned to LeftHand (hand-local cluster offset),
# pushed through the CURRENT forward-kinematic hand pose — including any
# applied upper-body aim chain rotation.
func strike_endpoint_world(unit_id: int) -> Vector3:
	var root: Node3D = _root_by_unit_id.get(unit_id) as Node3D
	if root == null:
		return Vector3.INF
	_refresh_unit_transforms(unit_id)
	var skel := _find_skeleton(root)
	if skel == null:
		return Vector3.INF
	var hand_i := skel.find_bone(ATTACK_STRIKE_BONE)
	if hand_i < 0:
		return Vector3.INF
	skel.force_update_all_bone_transforms()
	return skel.to_global(skel.get_bone_global_pose(hand_i) * ATTACK_STRIKE_TIP_HAND_LOCAL)


# Fixed anatomical contact on the defender (Head region — the measured
# body location the accepted neutral slash passes). Never moved to meet
# the strike — Hit_Reaction_1 stays authored.
func defender_aim_target_world(unit_id: int) -> Vector3:
	return _bone_world_position(unit_id, ATTACK_TARGET_BONE)


# Vertical aiming error of the strike endpoint vs the defender target.
func strike_aim_vertical_error(attacker_id: int, defender_id: int) -> float:
	var hand := strike_endpoint_world(attacker_id)
	var target := defender_aim_target_world(defender_id)
	if hand == Vector3.INF or target == Vector3.INF:
		return INF
	return hand.y - target.y


# Final post-transform sole-to-surface gap (ankle proxy) for one foot bone.
func sole_surface_gap(unit_id: int, foot_bone: String) -> float:
	var foot := _bone_world_position(unit_id, foot_bone)
	if foot == Vector3.INF:
		return INF
	var sample := _sample_surface(foot)
	if not bool(sample.get("ok", false)):
		return INF
	return foot.y - float(sample["height"])


func _refresh_unit_transforms(unit_id: int) -> void:
	var root: Node3D = _root_by_unit_id.get(unit_id) as Node3D
	if root == null:
		return
	root.force_update_transform()
	var model := _model_root_of(root)
	model.force_update_transform()
	for n in root.find_children("*", "Node3D", true, false):
		(n as Node3D).force_update_transform()


func _bone_world_position(unit_id: int, bone_name: String) -> Vector3:
	var root: Node3D = _root_by_unit_id.get(unit_id) as Node3D
	if root == null:
		return Vector3.INF
	_refresh_unit_transforms(unit_id)
	var skel := _find_skeleton(root)
	if skel == null:
		return Vector3.INF
	var bone_i := skel.find_bone(bone_name)
	if bone_i < 0:
		return Vector3.INF
	skel.force_update_all_bone_transforms()
	return skel.to_global(skel.get_bone_global_pose(bone_i).origin)


# Places the visual at a world position WITHOUT moving the authoritative
# root (ModelRoot offset compensates). Used during approach / mid-combat.
func _place_visual_at(unit_id: int, world_pos: Vector3) -> void:
	var root: Node3D = _root_by_unit_id.get(unit_id) as Node3D
	if root == null:
		return
	var model_root := _model_root_of(root)
	model_root.position = world_pos - root.position


# Settles a unit onto an authoritative anchor for the deferred apply:
# root + target mirror the snapshot position, ModelRoot offset cleared,
# upright yaw retained.
func _settle_combatant_at_anchor(unit_id: int, anchor: Vector3) -> void:
	var root: Node3D = _root_by_unit_id.get(unit_id) as Node3D
	if root == null:
		return
	var model_root := _model_root_of(root)
	var yaw_basis := model_root.basis
	# Preserve current yaw (drop pitch/roll/scale), then re-apply scale.
	var forward := -yaw_basis.z
	forward.y = 0.0
	root.position = anchor
	_target_anchor_by_unit_id[unit_id] = anchor
	model_root.position = Vector3.ZERO
	if forward.length_squared() > 0.000001:
		_apply_visual_yaw(model_root, forward)
	else:
		model_root.basis = Basis.from_scale(Vector3.ONE * MODEL_ROOT_SCALE)


func _snap_combatant_to_anchor(unit_id: int, anchor: Vector3) -> void:
	var root: Node3D = _root_by_unit_id.get(unit_id) as Node3D
	if root == null:
		return
	root.position = anchor
	_target_anchor_by_unit_id[unit_id] = anchor
	var model_root := _model_root_of(root)
	model_root.position = Vector3.ZERO
	model_root.basis = Basis.from_scale(Vector3.ONE * MODEL_ROOT_SCALE)


func _set_combat_grounder_paused(unit_id: int, paused: bool) -> void:
	var grounder = _grounder_by_unit_id.get(unit_id)
	if grounder != null:
		grounder.set_grounding_paused(paused)


func _restore_combatant_to_idle(unit_id: int) -> void:
	if _root_by_unit_id.get(unit_id) == null:
		return
	_set_combat_grounder_paused(unit_id, false)
	_play_semantic_clip(unit_id, SEMANTIC_IDLE_CLIP)
	# Deterministic return to ordinary Idle grounding: clear combat-only
	# state and keep locomotion grounding through the Idle crossfade.
	_begin_arrival_ground_settle(unit_id)


func _sync_death_animation_pose(unit_id: int, t: float) -> void:
	var player: AnimationPlayer = _player_by_unit_id.get(unit_id) as AnimationPlayer
	if player == null:
		return
	# update=true applies the pose immediately (needed when process is off).
	player.seek(maxf(t, 0.0), true)


func _freeze_death_animation(unit_id: int) -> void:
	var player: AnimationPlayer = _player_by_unit_id.get(unit_id) as AnimationPlayer
	if player == null:
		return
	var duration := float(_combat.get("death_duration", 0.0))
	# Pin the final Dead pose and freeze further advancement. Keep the
	# original play()'s current_animation assigned (pause/stop/re-play can
	# clear the clip name in headless and break corpse retention checks).
	player.seek(maxf(duration, 0.0), true)
	player.speed_scale = 0.0


# Continuous corpse support while Dead plays. Authored fall proceeds above
# ground; from first contact/penetration of animated body regions, apply
# the minimum ModelRoot lift (and later pitch/roll) via the same top-surface
# sampler as living travel. Returns false only when a final pass cannot
# query terrain (fail closed into finish — no gate deadlock).
func _update_corpse_terrain_support(unit_id: int, final_pass: bool) -> bool:
	if _surface_sampler == null:
		return not final_pass
	var root: Node3D = _root_by_unit_id.get(unit_id) as Node3D
	if root == null:
		return false
	var regions := _sample_corpse_body_regions(unit_id)
	if not bool(regions.get("ok", false)):
		return _fit_corpse_footprint_fallback(unit_id) if final_pass else true
	var pts: Array = [
		regions["head"],
		regions["hips"],
		regions["feet"],
		regions["left_foot"],
		regions["right_foot"],
	]
	var terrain_ys: Array = []
	for p_variant in pts:
		var p: Vector3 = p_variant
		var s := _sample_surface(p)
		if not bool(s["ok"]):
			return not final_pass
		terrain_ys.append(float(s["height"]))
	var max_pen := 0.0
	for i in pts.size():
		var pen: float = float(terrain_ys[i]) - (pts[i] as Vector3).y + CORPSE_CONTACT_EPS
		if pen > max_pen:
			max_pen = pen
	if max_pen <= 0.0 and not final_pass:
		# Still above the surface — let the authored Dead fall continue.
		return true
	_combat["corpse_contact"] = true
	var model_root := _model_root_of(root)
	if max_pen > 0.0:
		model_root.position.y += max_pen
		for i in pts.size():
			var lifted: Vector3 = pts[i]
			lifted.y += max_pen
			pts[i] = lifted
	var hips: Vector3 = pts[1]
	var hips_clearance: float = hips.y - float(terrain_ys[1])
	var enable_tilt := final_pass or hips_clearance <= CORPSE_PITCH_ENABLE_CLEARANCE
	var face := _corpse_face_dir(unit_id)
	if not enable_tilt:
		# Height-only correction while the body is still high — keep authored yaw.
		var upright := locomotion_yaw(face) * Basis.from_scale(Vector3.ONE * MODEL_ROOT_SCALE)
		model_root.basis = upright
		_combat["corpse_last_support_y"] = root.position.y + model_root.position.y
		return true
	return _apply_corpse_support_plane(unit_id, pts, terrain_ys, face)


func _corpse_face_dir(unit_id: int) -> Vector3:
	var face: Vector3 = _combat.get("face_dir", Vector3(0, 0, -1))
	if unit_id != int(_combat["attacker_id"]):
		face = -face
	if face.length_squared() < 0.000001:
		return Vector3(0, 0, -1)
	return face.normalized()


# World positions of animated upper/torso/leg regions used for death grounding.
func _sample_corpse_body_regions(unit_id: int) -> Dictionary:
	var root: Node3D = _root_by_unit_id.get(unit_id) as Node3D
	if root == null:
		return {"ok": false}
	var skeleton := _find_skeleton(root)
	if skeleton == null:
		return {"ok": false}
	var hips_i := skeleton.find_bone("Hips")
	var left_i := skeleton.find_bone("LeftFoot")
	var right_i := skeleton.find_bone("RightFoot")
	var head_i := skeleton.find_bone("Head")
	if head_i < 0:
		head_i = skeleton.find_bone("Spine2")
	if head_i < 0:
		head_i = skeleton.find_bone("Neck")
	if hips_i < 0 or left_i < 0 or right_i < 0 or head_i < 0:
		return {"ok": false}
	# AnimationPlayer.seek(update) leaves bone poses dirty until the skeleton
	# evaluates — force the pose before reading world positions.
	skeleton.force_update_all_bone_transforms()
	var head := skeleton.to_global(skeleton.get_bone_global_pose(head_i).origin)
	var hips := skeleton.to_global(skeleton.get_bone_global_pose(hips_i).origin)
	var left_foot := skeleton.to_global(skeleton.get_bone_global_pose(left_i).origin)
	var right_foot := skeleton.to_global(skeleton.get_bone_global_pose(right_i).origin)
	var feet: Vector3 = (left_foot + right_foot) * 0.5
	return {
		"ok": true,
		"head": head,
		"hips": hips,
		"feet": feet,
		"left_foot": left_foot,
		"right_foot": right_foot,
	}


func _apply_corpse_support_plane(
	unit_id: int, pts: Array, terrain_ys: Array, face: Vector3
) -> bool:
	var root: Node3D = _root_by_unit_id.get(unit_id) as Node3D
	if root == null:
		return false
	var model_root := _model_root_of(root)
	var head_p: Vector3 = pts[0]
	var feet_p: Vector3 = pts[2]
	var left_p: Vector3 = pts[3]
	var right_p: Vector3 = pts[4]
	var head_y: float = terrain_ys[0]
	var feet_y: float = terrain_ys[2]
	var left_y: float = terrain_ys[3]
	var right_y: float = terrain_ys[4]
	var span := maxf(head_p.distance_to(feet_p), 0.08)
	var lateral := maxf(left_p.distance_to(right_p), 0.06)
	var pitch := clampf(atan2(head_y - feet_y, span), -0.55, 0.55)
	var roll := clampf(atan2(left_y - right_y, lateral), -0.45, 0.45)
	# Pitch/roll only — XZ stays at the combat visual (no corpse slide).
	var yaw_basis := locomotion_yaw(face)
	var pitched := Basis(yaw_basis.x, pitch) * yaw_basis
	var rolled := Basis(pitched.z, roll) * pitched
	model_root.basis = rolled * Basis.from_scale(Vector3.ONE * MODEL_ROOT_SCALE)
	# Re-measure after tilt: add any residual penetration lift.
	var regions := _sample_corpse_body_regions(unit_id)
	if bool(regions.get("ok", false)):
		var check_pts: Array = [
			regions["head"], regions["hips"], regions["feet"],
			regions["left_foot"], regions["right_foot"],
		]
		var extra := 0.0
		for p_variant in check_pts:
			var p: Vector3 = p_variant
			var s := _sample_surface(p)
			if bool(s["ok"]):
				extra = maxf(extra, float(s["height"]) - p.y + CORPSE_CONTACT_EPS)
		if extra > 0.0:
			model_root.position.y += extra
	_combat["corpse_last_support_y"] = root.position.y + model_root.position.y
	return true


# Bone-less fallback (final pass only): fixed footprint around ModelRoot.
func _fit_corpse_footprint_fallback(unit_id: int) -> bool:
	var root: Node3D = _root_by_unit_id.get(unit_id) as Node3D
	if root == null or _surface_sampler == null:
		return false
	var model_root := _model_root_of(root)
	var visual := root.position + model_root.position
	var face := _corpse_face_dir(unit_id)
	var right := Vector3.UP.cross(face)
	if right.length_squared() < 0.000001:
		right = Vector3.RIGHT
	else:
		right = right.normalized()
	var offsets: Array = [
		Vector3.ZERO,
		face * CORPSE_FOOTPRINT_HALF_LENGTH,
		-face * CORPSE_FOOTPRINT_HALF_LENGTH,
		right * CORPSE_FOOTPRINT_HALF_WIDTH,
		-right * CORPSE_FOOTPRINT_HALF_WIDTH,
	]
	var samples: Array = []
	for off_variant in offsets:
		var off: Vector3 = off_variant
		var p := visual + off
		var s := _sample_surface(p)
		if not bool(s["ok"]):
			return false
		samples.append(float(s["height"]))
	var hips_y: float = samples[0]
	var head_y: float = samples[1]
	var feet_y: float = samples[2]
	var left_y: float = samples[3]
	var right_y: float = samples[4]
	var pitch := clampf(atan2(head_y - feet_y, CORPSE_FOOTPRINT_HALF_LENGTH * 2.0), -0.55, 0.55)
	var roll := clampf(atan2(left_y - right_y, CORPSE_FOOTPRINT_HALF_WIDTH * 2.0), -0.45, 0.45)
	var support_y := maxf(hips_y, (head_y + feet_y) * 0.5)
	var prev_y := float(_combat.get("corpse_last_support_y", support_y))
	support_y = maxf(support_y, prev_y)
	_combat["corpse_last_support_y"] = support_y
	model_root.position = Vector3(visual.x - root.position.x, support_y - root.position.y, visual.z - root.position.z)
	var yaw_basis := locomotion_yaw(face)
	var pitched := Basis(yaw_basis.x, pitch) * yaw_basis
	var rolled := Basis(pitched.z, roll) * pitched
	model_root.basis = rolled * Basis.from_scale(Vector3.ONE * MODEL_ROOT_SCALE)
	return true


func _semantic_clip_available(unit_id: int, semantic: String) -> bool:
	var player: AnimationPlayer = _player_by_unit_id.get(unit_id) as AnimationPlayer
	if player == null:
		return false
	var clip: String = Warrior3DAnimationRemapScript.glb_clip_for_visual(
		semantic, true, str(_type_by_unit_id.get(unit_id, ""))
	)
	return player.has_animation(clip)


# Plays one remapped clip as a ONE-SHOT (never looped) through the
# centralized blend path. Returns clip length in seconds (<= 0.0 when
# unavailable). Completion timing is measured from play-start against
# this length — the crossfade must not alter impact or one-shot duration.
# Combat vs idle/walk semantics resolve to DISJOINT GLB clips per rig, so
# flipping loop mode on the shared Animation resource never fights a
# concurrently looping unit of the same type.
func _play_semantic_clip_one_shot(unit_id: int, semantic: String) -> float:
	return _play_remapped_semantic(unit_id, semantic, true)


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


# Plays the remapped GLB clip for one looping semantic ("Idle_3" / "Walking")
# through the centralized blend path. Already-playing clips are never
# restarted (idempotent reapply, mid-glide retarget). Missing player/clip
# only warns — placement stays valid.
func _play_semantic_clip(unit_id: int, semantic: String) -> void:
	_play_remapped_semantic(unit_id, semantic, false)


# Locked default blend duration (tests / diagnostics).
func animation_blend_default_sec() -> float:
	return ANIM_BLEND_DEFAULT_SEC


# Last semantic play request through the centralized path (diagnostics).
func last_animation_play_info() -> Dictionary:
	return {
		"unit_id": _last_play_unit_id,
		"semantic": _last_play_semantic,
		"blend_sec": _last_play_blend_sec,
		"one_shot": _last_play_one_shot,
	}


# Central semantic→GLB playback: every Idle/Walking/combat/death/cancel
# transition crossfades with ANIM_BLEND_DEFAULT_SEC via AnimationPlayer.play
# (same API the legacy map-view used). Never stop() before play — that
# would snap away the outgoing clip and defeat the blend. Returns the
# remapped clip length when one_shot (else 0.0); negative when unavailable.
func _play_remapped_semantic(unit_id: int, semantic: String, one_shot: bool) -> float:
	var player: AnimationPlayer = _player_by_unit_id.get(unit_id) as AnimationPlayer
	if player == null:
		return -1.0
	var type_id := str(_type_by_unit_id.get(unit_id, ""))
	var clip: String = Warrior3DAnimationRemapScript.glb_clip_for_visual(semantic, true, type_id)
	if not player.has_animation(clip):
		_warn_type_once(type_id, "clip '%s' (semantic %s) not found" % [clip, semantic])
		return -1.0
	if not one_shot and player.current_animation == clip and player.is_playing():
		return 0.0
	var anim: Animation = player.get_animation(clip)
	anim.loop_mode = Animation.LOOP_NONE if one_shot else Animation.LOOP_LINEAR
	var blend_sec := ANIM_BLEND_DEFAULT_SEC
	# Crossfade from the current pose; custom_speed 1.0, from_end false so
	# one-shots still begin at frame 0. Completion = clip.length from now.
	# Reset speed_scale in case a prior Dead freeze left custom_speed 0.
	player.speed_scale = 1.0
	player.play(clip, blend_sec, 1.0, false)
	_last_play_unit_id = unit_id
	_last_play_semantic = semantic
	_last_play_blend_sec = blend_sec
	_last_play_one_shot = one_shot
	return maxf(float(anim.length), 0.0) if one_shot else 0.0


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
