# N7c world-unit presentation: renders the authoritative snapshot-v3 units
# as the existing 3D settler/warrior characters on the WorldMap terrain.
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
#   The locked -Z forward convention is preserved (identity rotation) and
#   the audited idle clip plays where available.
# - No selection, movement animation, facing-on-move, markers, or action
#   submission here (N7d); no legality (server-only, N7a/N7b). The legacy
#   2D/unit_3d_world_view path (ray placement, ~75x scale) is NOT reused.
class_name WorldUnitsView
extends Node3D

# Reused for asset-path resolution and the audited GLB idle-clip remap only
# (RefCounted helpers; none of the legacy env-flag gating applies here).
const Warrior3DExperimentScript = preload("res://presentation/warrior_3d_unit_experiment.gd")
const Warrior3DAnimationRemapScript = preload("res://presentation/warrior_3d_animation_remap.gd")

const MODEL_ROOT_NAME := "ModelRoot"
# Visual scale below the unit root, tuned for terrain scale S=1.
const MODEL_ROOT_SCALE := 0.5
const SEMANTIC_IDLE_CLIP := "Idle_3"

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
		var root: Node3D = _root_by_unit_id.get(unit_id) as Node3D
		if root == null:
			root = _create_unit_root(unit_id, type_id)
			if root == null:
				continue
		active_ids[unit_id] = true
		root.position = _tile_anchors[key]
	for stale_key in _root_by_unit_id.keys():
		var stale_id := int(stale_key)
		if active_ids.has(stale_id):
			continue
		var stale_root: Node = _root_by_unit_id[stale_id] as Node
		if stale_root != null:
			stale_root.queue_free()
		_root_by_unit_id.erase(stale_id)
		_type_by_unit_id.erase(stale_id)


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
	model_root.add_child(model)
	root.add_child(model_root)
	add_child(root)
	_root_by_unit_id[unit_id] = root
	_type_by_unit_id[unit_id] = type_id
	_start_idle_animation(model, type_id)
	return root


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


# Starts the audited idle clip where available (no new clips, no movement
# animation). Missing player/clip only warns — placement stays valid.
func _start_idle_animation(model: Node, type_id: String) -> void:
	var player := _find_animation_player(model)
	if player == null:
		_warn_type_once(type_id, "no AnimationPlayer for idle animation")
		return
	var idle_clip: String = Warrior3DAnimationRemapScript.glb_clip_for_visual(
		SEMANTIC_IDLE_CLIP, true, type_id
	)
	if not player.has_animation(idle_clip):
		_warn_type_once(type_id, "idle clip '%s' not found" % idle_clip)
		return
	var anim: Animation = player.get_animation(idle_clip)
	anim.loop_mode = Animation.LOOP_LINEAR
	player.play(idle_clip)


static func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child as Node)
		if found != null:
			return found
	return null


func _warn_type_once(type_id: String, message: String) -> void:
	if _warned_types.has(type_id + "|" + message):
		return
	_warned_types[type_id + "|" + message] = true
	push_warning("world_units_view: type %s: %s" % [type_id, message])
