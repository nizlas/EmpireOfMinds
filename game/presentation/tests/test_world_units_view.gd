# Headless: godot --headless --path game -s res://presentation/tests/test_world_units_view.gd
#
# N7c world-unit projection: WorldUnitsView reconciles one stable Node3D
# root per snapshot unit (keyed by exact unit id), places every root exactly
# at the supplied tile anchor, reuses the existing settler/warrior GLB
# characters below a 0.5-scaled ModelRoot with the audited idle clip, waits
# until BOTH snapshot units and anchors are available (either order), never
# duplicates on reapplied snapshots, and never falls back to the origin.
extends SceneTree

const WorldUnitsViewScript = preload("res://presentation/world/world_units_view.gd")

# Deliberately irregular anchor values (non-zero Y) so exact placement is
# distinguishable from any recomputed or origin-fallback position.
const ANCHORS := {
	Vector2i(1, 1): Vector3(1.5, 2.0, -1.25),
	Vector2i(2, 1): Vector3(3.25, 1.6, -0.75),
	Vector2i(2, 14): Vector3(2.75, 0.4, 12.5),
	Vector2i(2, 13): Vector3(2.5, 0.8, 11.25),
	# Extra tile for newly appearing unit-id reconciliation (N8c spawn).
	Vector2i(3, 1): Vector3(4.0, 1.2, -0.5),
}
# Audited GLB idle clips (warrior_3d_animation_remap.gd): semantic Idle_3.
const SETTLER_IDLE_CLIP := "Hit_Reaction_1"
const WARRIOR_IDLE_CLIP := "Combat_Stance"
# Albedo texture imports actually used by the settler/warrior animated GLBs.
const ALBEDO_IMPORTS := [
	"res://assets/prototype/3d/units/settler/settler_animations_texture_0.png.import",
	"res://assets/prototype/3d/units/settler/settler_animations_texture_0_1.png.import",
	"res://assets/prototype/3d/units/warrior/warrior_3d_animations_texture_0.png.import",
]

var _total := 0
var _any_fail := false


func _spawn_units() -> Array:
	return [
		{"id": 1, "owner_id": 11, "position": [1, 1], "type_id": "settler"},
		{"id": 2, "owner_id": 11, "position": [2, 1], "type_id": "warrior"},
		{"id": 3, "owner_id": 22, "position": [2, 14], "type_id": "settler"},
		{"id": 4, "owner_id": 22, "position": [2, 13], "type_id": "warrior"},
	]


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame

	# Anchors first, snapshot second.
	var view = WorldUnitsViewScript.new()
	root.add_child(view)
	view.set_tile_anchors(ANCHORS)
	_check(view.unit_count() == 0, "anchors alone render nothing (snapshot not yet available)")
	view.apply_snapshot_units(_spawn_units())
	_check(view.unit_count() == 4, "all four snapshot units are instantiated")
	_check(view.unit_ids() == [1, 2, 3, 4], "unit ids are exact")
	var expected_types := {1: "settler", 2: "warrior", 3: "settler", 4: "warrior"}
	for row in _spawn_units():
		var unit_id: int = int(row["id"])
		var node = view.root_for_unit(unit_id)
		_check(node != null, "unit %d has a root" % unit_id)
		if node == null:
			continue
		var anchor: Vector3 = ANCHORS[Vector2i(int(row["position"][0]), int(row["position"][1]))]
		_check(node.position == anchor, "unit %d root sits exactly at its tile anchor" % unit_id)
		_check(node.rotation == Vector3.ZERO, "unit %d keeps the -Z forward identity rotation" % unit_id)
		var model_root: Node3D = node.get_node_or_null("ModelRoot") as Node3D
		_check(model_root != null, "unit %d has a ModelRoot child" % unit_id)
		if model_root != null:
			_check(
				model_root.scale == Vector3.ONE * 0.5,
				"unit %d ModelRoot scale is 0.5" % unit_id
			)
			_check(
				model_root.get_child_count() == 1,
				"unit %d ModelRoot holds exactly the instantiated character" % unit_id
			)
		_check(
			view.type_id_for_unit(unit_id) == str(expected_types[unit_id]),
			"unit %d renders the %s character" % [unit_id, str(expected_types[unit_id])]
		)

	# Existing idle animation is started (audited remapped clips).
	_check_idle(view, 1, SETTLER_IDLE_CLIP, "settler")
	_check_idle(view, 2, WARRIOR_IDLE_CLIP, "warrior")

	# Locked matte material treatment on every rendered surface (both types).
	_check_materials(view, 1, "settler")
	_check_materials(view, 2, "warrior")
	# Per-instance duplication: the two settlers never share material objects.
	var settler_a: Array = _standard_materials(view.root_for_unit(1))
	var settler_b: Array = _standard_materials(view.root_for_unit(3))
	_check(
		not settler_a.is_empty() and not settler_b.is_empty()
			and settler_a[0] != settler_b[0],
		"material treatment is duplicated per instance (settlers share nothing)"
	)
	# The imported source materials stay untouched (still fully metallic).
	var imports_untouched := true
	for source_mat in _imported_source_materials(view.root_for_unit(1)):
		if (source_mat as StandardMaterial3D).metallic < 0.5:
			imports_untouched = false
	_check(imports_untouched, "imported GLB materials are never mutated")
	# Small-unit quality profile: albedo imports keep generated mipmaps.
	for import_path in ALBEDO_IMPORTS:
		var import_text := FileAccess.get_file_as_string(str(import_path))
		_check(
			import_text.contains("mipmaps/generate=true"),
			"albedo import keeps mipmaps: %s" % str(import_path).get_file()
		)

	# Reapplying the identical snapshot keeps the same instances (no duplicates).
	var ids_before := {}
	for unit_id in view.unit_ids():
		ids_before[unit_id] = view.root_for_unit(int(unit_id)).get_instance_id()
	view.apply_snapshot_units(_spawn_units())
	await process_frame
	_check(view.unit_count() == 4, "reapplied snapshot keeps four units")
	_check(view.get_child_count() == 4, "reapplied snapshot creates no duplicate roots")
	var stable := true
	for unit_id in view.unit_ids():
		if view.root_for_unit(int(unit_id)).get_instance_id() != int(ids_before[unit_id]):
			stable = false
	_check(stable, "reapplied snapshot reuses the same root instances")

	# A newly appearing unit id (production spawn) is placed at its supplied anchor.
	var with_spawned := _spawn_units().duplicate(true)
	with_spawned.append(
		{"id": 5, "owner_id": 11, "position": [3, 1], "type_id": "warrior"}
	)
	view.apply_snapshot_units(with_spawned)
	_check(view.unit_ids() == [1, 2, 3, 4, 5], "new unit id appears in reconciliation")
	_check(
		view.root_for_unit(5) != null
			and view.root_for_unit(5).position == ANCHORS[Vector2i(3, 1)],
		"newly appearing unit id sits exactly at its supplied tile anchor"
	)
	_check(
		view.root_for_unit(1).get_instance_id() == int(ids_before[1]),
		"existing roots stay stable when a new unit id appears"
	)

	# A moved unit keeps its instance and lands exactly on the new anchor.
	var moved := _spawn_units()
	(moved[1] as Dictionary)["position"] = [2, 13]
	(moved[3] as Dictionary)["position"] = [2, 1]
	view.apply_snapshot_units(moved)
	_check(
		view.root_for_unit(2).position == ANCHORS[Vector2i(2, 13)]
			and view.root_for_unit(4).position == ANCHORS[Vector2i(2, 1)],
		"moved units sit exactly at their new tile anchors"
	)
	_check(
		view.root_for_unit(2).get_instance_id() == int(ids_before[2])
			and view.root_for_unit(4).get_instance_id() == int(ids_before[4]),
		"moved units keep their stable root instances"
	)

	# Units missing from the snapshot are removed.
	view.apply_snapshot_units([_spawn_units()[0], _spawn_units()[2]])
	await process_frame
	_check(view.unit_ids() == [1, 3], "stale units are removed on reconciliation")
	_check(view.get_child_count() == 2, "removed units free their roots")
	view.queue_free()
	await process_frame

	# Snapshot first, anchors second: nothing renders until both exist.
	var late_view = WorldUnitsViewScript.new()
	root.add_child(late_view)
	late_view.apply_snapshot_units(_spawn_units())
	_check(
		late_view.unit_count() == 0 and late_view.get_child_count() == 0,
		"snapshot alone renders nothing (no origin fallback)"
	)
	late_view.set_tile_anchors(ANCHORS)
	_check(late_view.unit_count() == 4, "units render once anchors arrive after the snapshot")
	_check(
		late_view.root_for_unit(1).position == ANCHORS[Vector2i(1, 1)],
		"late-anchor placement is still the exact tile anchor"
	)
	late_view.queue_free()
	await process_frame

	# A unit position without an anchor is skipped (explicit error, no guess).
	var partial_anchors := ANCHORS.duplicate()
	partial_anchors.erase(Vector2i(2, 14))
	var partial_view = WorldUnitsViewScript.new()
	root.add_child(partial_view)
	partial_view.set_tile_anchors(partial_anchors)
	partial_view.apply_snapshot_units(_spawn_units())
	_check(
		partial_view.unit_ids() == [1, 2, 4],
		"a unit without a tile anchor is not rendered (no fallback position)"
	)
	partial_view.queue_free()
	await process_frame

	_finish()


func _check_materials(view, unit_id: int, label: String) -> void:
	var mats: Array = _standard_materials(view.root_for_unit(unit_id))
	_check(not mats.is_empty(), "%s has treated StandardMaterial3D surfaces" % label)
	var values_ok := true
	var albedo_ok := true
	var filter_ok := true
	for mat in mats:
		var sm: StandardMaterial3D = mat as StandardMaterial3D
		if (
			absf(sm.metallic - 0.0) >= 0.001
			or absf(sm.roughness - 0.85) >= 0.001
			or absf(sm.metallic_specular - 0.3) >= 0.001
		):
			values_ok = false
		if sm.albedo_texture == null:
			albedo_ok = false
		if sm.texture_filter != BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS:
			filter_ok = false
	_check(values_ok, "%s surfaces: metallic 0.0, roughness 0.85, specular 0.3" % label)
	_check(albedo_ok, "%s surfaces keep the real albedo texture" % label)
	_check(filter_ok, "%s surfaces keep linear+mipmap filtering" % label)


# Treated per-surface override materials below one unit root.
static func _standard_materials(root: Node) -> Array:
	var out: Array = []
	if root == null:
		return out
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_inst: MeshInstance3D = node as MeshInstance3D
		if mesh_inst.mesh == null:
			continue
		for si in mesh_inst.mesh.get_surface_count():
			var mat: Material = mesh_inst.get_surface_override_material(si)
			if mat is StandardMaterial3D:
				out.append(mat)
	return out


# The untouched imported materials still attached to the shared mesh.
static func _imported_source_materials(root: Node) -> Array:
	var out: Array = []
	if root == null:
		return out
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_inst: MeshInstance3D = node as MeshInstance3D
		if mesh_inst.mesh == null:
			continue
		for si in mesh_inst.mesh.get_surface_count():
			var mat: Material = mesh_inst.mesh.surface_get_material(si)
			if mat is StandardMaterial3D:
				out.append(mat)
	return out


func _check_idle(view, unit_id: int, expected_clip: String, label: String) -> void:
	var node = view.root_for_unit(unit_id)
	var player := _find_animation_player(node)
	_check(player != null, "%s has an AnimationPlayer" % label)
	if player == null:
		return
	_check(player.has_animation(expected_clip), "%s idle clip '%s' exists" % [label, expected_clip])
	_check(
		str(player.current_animation) == expected_clip,
		"%s plays the audited idle clip '%s'" % [label, expected_clip]
	)


static func _find_animation_player(node: Node) -> AnimationPlayer:
	if node == null:
		return null
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child as Node)
		if found != null:
			return found
	return null


func _check(condition: bool, label: String) -> void:
	_total += 1
	if condition:
		print("PASS ", label)
	else:
		_any_fail = true
		print("FAIL ", label)


func _finish() -> void:
	print("WorldUnitsView tests: %d checks" % _total)
	if _any_fail:
		print("FAIL")
		quit(1)
	else:
		print("PASS")
		quit(0)
