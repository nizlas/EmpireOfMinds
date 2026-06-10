# Headless: godot --headless --path game -s res://presentation/tests/test_units_view_draw.gd
extends SceneTree
const UnitsViewScript = preload("res://presentation/units_view.gd")
const Warrior3DUnitExperimentScript = preload("res://presentation/warrior_3d_unit_experiment.gd")
const ScenarioScript = preload("res://domain/scenario.gd")
const HexLayoutScript = preload("res://presentation/hex_layout.gd")
const HexCoordScript = preload("res://domain/hex_coord.gd")

var _total = 0
var _any_fail = false

func _init() -> void:
	var sc = ScenarioScript.make_tiny_test_scenario()
	var layout = HexLayoutScript.new()
	var items = UnitsViewScript.compute_marker_items(sc, layout)
	_check(
		items.size() == sc.units().size(),
		"marker items should match number of domain units"
	)
	var id_seen = {}
	var i = 0
	while i < items.size():
		var it = items[i]
		var uid = it["unit_id"]
		if not id_seen.has(uid):
			id_seen[uid] = 0
		id_seen[uid] = id_seen[uid] + 1
		_check(
			sc.map.has(it["coord"]),
			"each marker coord should be on the map"
		)
		_check(
			not it["coord"].equals(HexCoordScript.new(-1, 0)),
			"WATER cell should have no unit marker in canonical scenario"
		)
		var exp_w = layout.hex_to_world(it["coord"].q, it["coord"].r)
		_check(
			(it["world"] as Vector2).is_equal_approx(exp_w),
			"world position should match layout.hex_to_world for coord"
		)
		i = i + 1
	var ulist = sc.units()
	var k = 0
	while k < ulist.size():
		var uu = ulist[k]
		_check(
			id_seen.get(uu.id, 0) == 1,
			"each unit id from domain should appear exactly once in items"
		)
		k = k + 1
	var c0: Color
	var c0_set = false
	var c1: Color
	var c1_set = false
	var m = 0
	while m < items.size():
		var it2 = items[m]
		if it2["owner_id"] == 0:
			if not c0_set:
				c0 = it2["color"]
				c0_set = true
			_check(
				(it2["color"] as Color).is_equal_approx(c0),
				"owner 0 items should share the same color"
			)
		if it2["owner_id"] == 1:
			if not c1_set:
				c1 = it2["color"]
				c1_set = true
		m = m + 1
	_check(c0_set, "should have at least one owner-0 item")
	_check(c1_set, "should have at least one owner-1 item")
	_check(
		not c1.is_equal_approx(c0),
		"owner-1 color should differ from owner-0 color"
	)
	_check(
		UnitsViewScript.compute_marker_items(null, layout).size() == 0,
		"null scenario should produce no items"
	)
	_check(
		UnitsViewScript.compute_marker_items(sc, null).size() == 0,
		"null layout should produce no items"
	)
	var rr = Rect2(100.0, 50.0, 40.0, 48.0)
	const TamScript = preload("res://presentation/texture_alpha_metrics.gd")
	var msett: Dictionary = TamScript.metrics_for_res_path(
		UnitsViewScript.marker_texture_res_path("settler")
	)
	_check(msett.get("ok", false), "alpha metrics should load for settler marker PNG")
	if msett.get("ok", false):
		_check(int(msett["bottom_padding_px"]) >= 0, "bottom_padding_px should be non-negative")
	var uv_align: UnitsViewScript = UnitsViewScript.new()
	uv_align._ready()
	var anch: Vector2 = Vector2(512.0, 384.0)
	var psc: float = 1.0
	var urect: Rect2 = uv_align.unit_marker_texture_rect_presentation(anch, psc, "settler")
	if urect.size.x > 0.0:
		var raw_b: Vector2 = UnitsViewScript.unit_png_bottom_center_from_rect(urect)
		var pad_s: float = TamScript.scaled_bottom_padding_y(msett, urect.size.y)
		var eff_pt: Vector2 = raw_b - Vector2(0.0, pad_s)
		_check(
			eff_pt.distance_to(anch) < 0.02,
			"textured unit effective bottom (opaque) should match anchor_pres"
		)
	var urect_w: Rect2 = uv_align.unit_marker_texture_rect_presentation(anch, psc, "warrior")
	if urect_w.size.x > 0.0:
		var mwarr: Dictionary = TamScript.metrics_for_res_path(
			UnitsViewScript.marker_texture_res_path("warrior")
		)
		var raw_w: Vector2 = UnitsViewScript.unit_png_bottom_center_from_rect(urect_w)
		var pad_w: float = TamScript.scaled_bottom_padding_y(mwarr, urect_w.size.y)
		var eff_w: Vector2 = raw_w - Vector2(0.0, pad_w)
		_check(
			eff_w.distance_to(anch) < 0.02,
			"warrior textured effective bottom should match anchor_pres"
		)
	uv_align.queue_free()
	OS.set_environment(Warrior3DUnitExperimentScript.ENV_FLAG, "")
	OS.unset_environment(Warrior3DUnitExperimentScript.ENV_FLAG_LEGACY)
	_check(not Warrior3DUnitExperimentScript.is_enabled(), "3d models experiment off by default")
	OS.set_environment(Warrior3DUnitExperimentScript.ENV_FLAG, "1")
	_check(Warrior3DUnitExperimentScript.is_enabled(), "EMPIRE_USE_3D_MODELS flag on")
	OS.unset_environment(Warrior3DUnitExperimentScript.ENV_FLAG)
	OS.set_environment(Warrior3DUnitExperimentScript.ENV_FLAG_LEGACY, "1")
	_check(Warrior3DUnitExperimentScript.is_enabled(), "EMPIRE_USE_3D_WARRIOR legacy alias on")
	_check(
		Warrior3DUnitExperimentScript.should_render_unit_as_3d("warrior"),
		"legacy warrior flag enables warrior 3d only",
	)
	_check(
		not Warrior3DUnitExperimentScript.should_render_unit_as_3d("settler"),
		"legacy warrior flag does not enable settler 3d",
	)
	OS.unset_environment(Warrior3DUnitExperimentScript.ENV_FLAG_LEGACY)
	OS.set_environment(Warrior3DUnitExperimentScript.ENV_FLAG, "1")
	_check(
		Warrior3DUnitExperimentScript.should_render_unit_as_3d("warrior"),
		"warrior uses 3d path when flag on and glb exists",
	)
	_check(
		Warrior3DUnitExperimentScript.should_render_unit_as_3d("settler"),
		"settler uses 3d path when flag on and glb exists",
	)
	_check(
		ResourceLoader.exists(Warrior3DUnitExperimentScript.WARRIOR_ANIMATED_GLB_PATH),
		"warrior animated glb exists for idle experiment",
	)
	_check(
		ResourceLoader.exists(Warrior3DUnitExperimentScript.SETTLER_ANIMATED_GLB_PATH),
		"settler animated glb exists for idle experiment",
	)
	_check(
		Warrior3DUnitExperimentScript.WARRIOR_ANIMATED_GLB_PATH.find(
			"prototype/3d/units/warrior/"
		) >= 0,
		"warrior animated glb under prototype/3d/units/warrior",
	)
	_check(
		Warrior3DUnitExperimentScript.SETTLER_ANIMATED_GLB_PATH.find(
			"prototype/3d/units/settler/"
		) >= 0,
		"settler animated glb under prototype/3d/units/settler",
	)
	_check(
		ResourceLoader.exists(Warrior3DUnitExperimentScript.ANCIENT_VILLAGE_GLB_PATH),
		"ancient_village glb exists for city 3d experiment",
	)
	_check(
		Warrior3DUnitExperimentScript.should_render_city_as_3d(),
		"city uses 3d path when EMPIRE_USE_3D_MODELS=1 and glb exists",
	)
	_check(
		Warrior3DUnitExperimentScript.warrior_scene_path().ends_with(
			"prototype/3d/units/warrior/warrior_3d_animations.glb"
		),
		"warrior scene prefers animated glb when present",
	)
	var anim_scene: PackedScene = load(
		Warrior3DUnitExperimentScript.WARRIOR_ANIMATED_GLB_PATH
	) as PackedScene
	var anim_root: Node = anim_scene.instantiate()
	var anim_player: AnimationPlayer = _find_warrior_anim_player(anim_root)
	_check(anim_player != null, "animated warrior glb has AnimationPlayer")
	if anim_player != null:
		_check(
			anim_player.has_animation(Warrior3DUnitExperimentScript.map_animation_name()),
			"animated warrior glb has configured map animation",
		)
		_check(anim_player.has_animation("Dead"), "animated warrior glb has Dead clip for anim switch test")
	var WViewScript = preload("res://presentation/warrior_3d_unit_markers_view.gd")
	var RemapScript = preload("res://presentation/warrior_3d_animation_remap.gd")
	OS.unset_environment(Warrior3DUnitExperimentScript.ANIM_AUDIT_ENV)
	OS.set_environment(Warrior3DUnitExperimentScript.ENV_FLAG, "1")
	var wview = WViewScript.new()
	wview.map_animation_name = "Idle_3"
	wview.use_glb_animation_name_remap = true
	root.add_child(wview)
	wview._load_warrior_scene()
	var slot: Node2D = wview._create_slot()
	root.add_child(slot)
	call_deferred("_finish_warrior_3d_slot_checks", wview, slot, RemapScript, anim_root, rr)
	return


func _finish_warrior_3d_slot_checks(wview, slot: Node2D, RemapScript, anim_root: Node, rr: Rect2) -> void:
	wview._ensure_slot_animation(slot, RemapScript.glb_clip_for_visual("Idle_3", true))
	var slot_player: AnimationPlayer = _find_warrior_anim_player(slot)
	if slot_player != null:
		var glb_clip: String = RemapScript.glb_clip_for_visual("Idle_3", true)
		_check(glb_clip == "Combat_Stance", "Idle_3 visual remaps to Combat_Stance GLB key")
		_check(
			slot_player.is_playing() and slot_player.assigned_animation == glb_clip,
			"Warrior3DUnitMarkersView plays remapped GLB clip for Idle_3 visual",
		)
	slot.free()
	wview.free()
	anim_root.free()
	OS.unset_environment(Warrior3DUnitExperimentScript.ENV_FLAG)
	OS.unset_environment(Warrior3DUnitExperimentScript.ANIM_AUDIT_ENV)
	var bc = UnitsViewScript.unit_png_bottom_center_from_rect(rr)
	_check(
		bc.is_equal_approx(Vector2(120.0, 98.0)),
		"PNG bottom-center is rect mid-x and position.y+size.y"
	)
	if _any_fail:
		quit(1)
	else:
		print("PASS %d/%d" % [_total, _total])
		quit(0)

func _check(cond, message) -> void:
	_total = _total + 1
	if cond:
		return
	_any_fail = true
	var line = "FAIL: %s" % message
	print(line)
	push_error(line)


func _find_warrior_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	var ci: int = 0
	while ci < node.get_child_count():
		var found: AnimationPlayer = _find_warrior_anim_player(node.get_child(ci))
		if found != null:
			return found
		ci += 1
	return null
