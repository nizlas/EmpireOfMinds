# Headless: godot --headless --path game -s res://cloud/tests/test_cloud_world_play_smoke.gd
#
# N6/N7c production world-play scene smoke test: cloud_world_play builds the
# shared TerrainWorld + N4 anchor UI from a verified snapshot v3, renders the
# snapshot's units at the tile anchors (N7c WorldUnitsView), and fails
# explicitly (visible error, no fallback map) on identity mismatch. The
# network fetch is exercised by the end-to-end flow; this test feeds the
# snapshot directly through the same bootstrap entry the scene uses.
#
# Requires the built GDExtension (from repo root): .\scripts\build-native.ps1
extends SceneTree

const REFERENCE_MAP_ID := "handdrawn_test_map_full_01"
const REFERENCE_HASH := "16cc82c3392c66f1e47273e7da94cf8a804ae9885a051fc81c4b0a9a4261d8c6"

var _total := 0
var _any_fail := false


func _good_snapshot() -> Dictionary:
	return {
		"match_id": "m_smoke",
		"schema_version": 3,
		"match_kind": "world_map",
		"map": {
			"map_id": REFERENCE_MAP_ID,
			"schema_version": 1,
			"content_hash": REFERENCE_HASH,
		},
		"revision": 0,
		"turn_state": {"players": [0, 1], "current_index": 0, "turn_number": 1},
		# N7a spawn table for the reference map (live snapshot v3 shape).
		"units": [
			{"id": 1, "owner_id": 0, "position": [1, 1], "type_id": "settler"},
			{"id": 2, "owner_id": 0, "position": [2, 1], "type_id": "warrior"},
			{"id": 3, "owner_id": 1, "position": [2, 14], "type_id": "settler"},
			{"id": 4, "owner_id": 1, "position": [2, 13], "type_id": "warrior"},
		],
	}


func _init() -> void:
	_check(
		String(ProjectSettings.get_setting("application/run/main_scene")) ==
			"res://cloud/cloud_front_door.tscn",
		"cloud front door stays the project main scene (no default-entry cutover)"
	)
	var packed: PackedScene = load("res://cloud/world_play/cloud_world_play.tscn") as PackedScene
	_check(packed != null, "cloud_world_play scene loads")
	if packed == null:
		_finish()
		return
	var scene = packed.instantiate()
	_check(scene != null, "cloud_world_play instantiates")

	# Identity mismatch: explicit failure, no fallback, no world built.
	var bad := _good_snapshot()
	(bad["map"] as Dictionary)["content_hash"] = "0".repeat(64)
	_check(not scene.bootstrap_from_snapshot(bad), "hash mismatch bootstrap returns false")
	_check(scene.world == null, "hash mismatch builds no world (no fallback)")
	_check(scene.units_view == null, "hash mismatch renders no units")
	_check(
		str(scene.bootstrap_error).contains("content_hash mismatch"),
		"hash mismatch error is explicit and visible"
	)

	# Verified snapshot: shared TerrainWorld + N4 anchor UI.
	_check(scene.bootstrap_from_snapshot(_good_snapshot()), "verified snapshot bootstraps")
	_check(str(scene.bootstrap_error) == "", "bootstrap error cleared on success")
	var world = scene.world
	_check(
		world != null and world == scene.get_node_or_null("TerrainWorld")
			and world.get_script() == load("res://presentation/world/terrain_world.gd"),
		"scene builds the exact shared runtime-world component"
	)
	var anchor_ui = scene.anchor_ui
	_check(
		anchor_ui != null and anchor_ui == scene.get_node_or_null("WorldAnchorUi")
			and anchor_ui.get_script() == load("res://presentation/world/world_anchor_ui.gd"),
		"scene attaches the shared N4 projected anchor UI"
	)
	if world != null:
		_check(
			world.world_map != null and world.world_map.identity.map_id == REFERENCE_MAP_ID
				and world.world_map.identity.content_hash == REFERENCE_HASH,
			"world built from the verified canonical map"
		)
		_check(
			world.tile_anchors.size() == world.world_map.tile_count(),
			"one anchor per canonical tile"
		)

	# N7c: the live snapshot's units render at the exact tile anchors.
	var units_view = scene.units_view
	_check(
		units_view != null and units_view == scene.get_node_or_null("WorldUnitsView")
			and units_view.get_script() == load("res://presentation/world/world_units_view.gd"),
		"scene attaches the shared N7c world units view"
	)
	if units_view != null and world != null:
		_check(units_view.unit_ids() == [1, 2, 3, 4], "all snapshot units render with exact ids")
		var placed := true
		for row in (_good_snapshot()["units"] as Array):
			var key := Vector2i(int(row["position"][0]), int(row["position"][1]))
			var unit_root = units_view.root_for_unit(int(row["id"]))
			if unit_root == null or unit_root.position != world.tile_anchors[key]:
				placed = false
		_check(placed, "every unit root sits exactly at TerrainWorld.tile_anchors[(q, r)]")
		var ids_before := {}
		for unit_id in units_view.unit_ids():
			ids_before[unit_id] = units_view.root_for_unit(int(unit_id)).get_instance_id()
		scene._render_units()
		var stable: bool = units_view.unit_count() == 4
		for unit_id in units_view.unit_ids():
			if units_view.root_for_unit(int(unit_id)).get_instance_id() != int(ids_before[unit_id]):
				stable = false
		_check(stable, "re-rendering the held snapshot duplicates no units")

		# N7c render profile on the production path: matte material treatment
		# on every rendered surface of every unit.
		var mats_ok := true
		var mat_count := 0
		for unit_id in units_view.unit_ids():
			for mat in _standard_materials(units_view.root_for_unit(int(unit_id))):
				mat_count += 1
				var sm: StandardMaterial3D = mat as StandardMaterial3D
				if (
					absf(sm.metallic - 0.0) >= 0.001
					or absf(sm.roughness - 0.85) >= 0.001
					or absf(sm.metallic_specular - 0.3) >= 0.001
					or sm.albedo_texture == null
					or sm.texture_filter != BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
				):
					mats_ok = false
		_check(
			mat_count > 0 and mats_ok,
			"production units carry the locked matte material treatment"
		)

	# N7c small-unit quality profile: MSAA 2x + FXAA on the world viewport.
	var vp := SubViewport.new()
	scene.configure_world_viewport_aa(vp)
	_check(vp.msaa_3d == Viewport.MSAA_2X, "world viewport AA profile sets MSAA_2X")
	_check(
		vp.screen_space_aa == Viewport.SCREEN_SPACE_AA_FXAA,
		"world viewport AA profile sets FXAA"
	)
	vp.free()
	_check(
		FileAccess.get_file_as_string("res://cloud/world_play/cloud_world_play.gd")
			.contains("configure_world_viewport_aa(get_viewport())"),
		"scene _ready configures AA on the existing WorldMap viewport"
	)
	scene.free()
	_finish()


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


func _check(condition: bool, label: String) -> void:
	_total += 1
	if condition:
		print("PASS ", label)
	else:
		_any_fail = true
		print("FAIL ", label)


func _finish() -> void:
	print("CloudWorldPlaySmoke tests: %d checks" % _total)
	if _any_fail:
		print("FAIL")
		quit(1)
	else:
		print("PASS")
		quit(0)
