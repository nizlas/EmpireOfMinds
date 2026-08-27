# A2.13b: the two F6 preview paths are real, and they are the SAME path.
#
# The visual acceptance itself is the user's, and nothing here claims it. What
# this does claim is that both previews reach a certified grip through the
# generic certification authority and the generic assembler, with no authored
# oracle fixture anywhere in the scene — so if the user does not like what they
# see, the thing they are looking at is what the pipeline produces, and if they
# do, the pipeline is what earned it.
extends SceneTree

const Preview = preload(
	"res://assets/prototype/3d/units/generated_warrior/uthana_a2"
	+ "/uthana_a2_dual_certified_grip_preview.gd"
)
const PREVIEW_SCENE := (
	"res://assets/prototype/3d/units/generated_warrior/uthana_a2"
	+ "/uthana_a2_dual_certified_grip_preview.tscn"
)
const ORACLE_SCRIPT := "uthana_warrior_hand_fixture"

var _total := 0
var _any_fail := false


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	_test_scene_loads_no_authored_oracle()
	_test_the_hud_reads_closest_patch_and_cannot_invent_one()
	await _test_both_deliveries_reach_a_certified_grip()
	print("test_dual_certified_grip_preview: %d checks, %s" % [
		_total, "FAIL" if _any_fail else "OK"
	])
	quit(1 if _any_fail else 0)


## The HUD's `closest patch` reads the achieved-geometry step out of the report
## and nothing else. Driven with doctored reports so the reader's behaviour is
## proven rather than inferred from the one run where the answer happens to be
## the expected one: it must echo whatever the producer recorded, including a
## value the gate would have refused, and it must go EMPTY when the step is
## absent so an unmeasured run cannot be dressed up as a passing one.
func _test_the_hud_reads_closest_patch_and_cannot_invent_one() -> void:
	_check(
		Preview.achieved_closest_patch({}).is_empty(),
		"a report with no achieved-geometry step yields no patch name"
	)
	_check(
		Preview.achieved_closest_patch({"diagnostics": {}}).is_empty(),
		"a report with empty diagnostics yields no patch name"
	)
	_check(
		Preview.achieved_closest_patch(
			{"diagnostics": {"grip_ground_truth": {"closest_patch": "nail"}}}
		) == "nail",
		"the reader echoes the recorded reading even when it is the refused one"
	)
	_check(
		not str(Preview.NO_ACHIEVED_READING).contains("pad"),
		"the absent-reading marker cannot be misread as the pad"
	)
	# The assembler's own result carries no `surface` block; reading it there was
	# what produced the `?` the A2.13b visual check reported.
	_check(
		Preview.achieved_closest_patch(
			{"assembler_result": {"surface": {"closest_patch": "pad"}}}
		).is_empty(),
		"the reader does not take the value from the assembler result shape"
	)


## The preview may not reach for the hand-authored A2.7 fixture, because a scene
## that can fall back to an oracle proves nothing about the compiler.
func _test_scene_loads_no_authored_oracle() -> void:
	var f := FileAccess.open(
		"res://assets/prototype/3d/units/generated_warrior/uthana_a2"
		+ "/uthana_a2_dual_certified_grip_preview.gd",
		FileAccess.READ
	)
	_check(f != null, "the preview script is readable")
	if f == null:
		return
	var code_only := ""
	for line in f.get_as_text().split("\n"):
		var s := str(line).strip_edges()
		if s.begins_with("#"):
			continue
		code_only += s + "\n"
	_check(
		not code_only.contains(ORACLE_SCRIPT),
		"the preview never loads the hand-authored oracle fixture"
	)
	_check(
		not code_only.contains("reference_fixture_mode"),
		"the preview never enables reference-fixture mode"
	)
	_check(ResourceLoader.exists(PREVIEW_SCENE), "the preview scene exists for F6")


## Both entries of the preview's delivery list run the whole chain and end up
## with a certificate and an assembled club. Driven through the preview's own
## public surface, so this is the path F6 takes.
func _test_both_deliveries_reach_a_certified_grip() -> void:
	var scene: PackedScene = load(PREVIEW_SCENE) as PackedScene
	_check(scene != null, "the preview scene loads")
	if scene == null:
		return
	var node: Node3D = scene.instantiate() as Node3D
	root.add_child(node)
	# `_ready` starts the first delivery's chain; it is not awaitable from here,
	# so the deliveries are driven explicitly instead.
	for i in (Preview.DELIVERIES as Array).size():
		await node._show(i)
		var label: String = str((Preview.DELIVERIES[i] as Dictionary).get("id", "?"))
		var report: Dictionary = node.last_report()
		_check(
			bool(report.get("ok", false)),
			"%s reaches a certificate through the real authority (%s at %s)"
				% [label, str(report.get("error_class", "")), str(report.get("stage", ""))]
		)
		if not bool(report.get("ok", false)):
			continue
		_check(
			not (report.get("certification", {}) as Dictionary).is_empty(),
			"%s minted a certification envelope" % label
		)
		var asm = report.get("assembler", null)
		_check(asm != null and asm.has_method("has_club") and bool(asm.has_club()),
			"%s has the club attached by the generic assembler" % label)
		if asm == null:
			continue
		# The fixture the assembler bound is a real certificate, not a reference.
		_check(
			str((asm.mesh_binding() as Dictionary).get("binding", "")) == "certified_bound",
			"%s assembled a CERTIFIED fixture (%s)"
				% [label, str((asm.mesh_binding() as Dictionary).get("binding", ""))]
		)
		var diag: Dictionary = report.get("diagnostics", {})
		var side: Dictionary = (diag.get("sides", {}) as Dictionary).get("right", {})
		_check(
			int(side.get("nail_tris", -1)) == 4 and int(side.get("pad_tris", -1)) == 10,
			"%s compiled 4 nail / 10 pad triangles (%s / %s)"
				% [label, str(side.get("nail_tris", "?")), str(side.get("pad_tris", "?"))]
		)
		# PRODUCER -> REPORT -> HUD, checked as a chain. The producer is the grip
		# engine that posed the hand; the expected value is read from IT, not
		# written here, so the HUD cannot pass by agreeing with a local constant.
		var produced := ""
		var grip = asm.grip_modifier() if asm.has_method("grip_modifier") else null
		_check(
			grip != null and grip.has_method("last_surface"),
			"%s the grip engine that measured the achieved pose is reachable" % label
		)
		if grip != null and grip.has_method("last_surface"):
			produced = str((grip.last_surface() as Dictionary).get("closest_patch", ""))
		_check(
			not produced.is_empty(),
			"%s the engine produced an achieved closest-patch reading" % label
		)
		_check(
			Preview.achieved_closest_patch(report) == produced,
			"%s the report carries the engine's own reading (%s vs %s)"
				% [label, Preview.achieved_closest_patch(report), produced]
		)
		_check(
			produced == "pad",
			"%s the achieved contact is the volar pad (%s)" % [label, produced]
		)
		# The HUD must be able to answer the questions the visual check asks.
		var hud: String = str(node.hud_text())
		for token in [
			"certified", "fixture owner", "gate verdict", "nail / pad",
			"approach", "closest patch", "view", "club",
		]:
			_check(hud.contains(token), "%s HUD reports '%s'" % [label, token])
		_check(hud.contains("certified     : YES"), "%s HUD shows it certified" % label)
		_check(hud.contains("gate verdict  : ACCEPTED"), "%s HUD shows ACCEPTED" % label)
		_check(
			hud.contains("nail / pad    : 4 / 10 triangles"),
			"%s HUD shows the 4/10 patch result" % label
		)
		_check(
			hud.contains("closest patch : %s" % produced),
			"%s HUD displays the engine's reading verbatim" % label
		)
		_check(
			not hud.contains(str(Preview.NO_ACHIEVED_READING)),
			"%s HUD is not showing the absent-reading marker" % label
		)
		_check_views(node, label)
	node.queue_free()
	await process_frame


## Both framings do what they declare. Neither view hides the weapon, so in both
## of them the club must be attached, its meshes visible and its centre inside
## the frustum: an empty frame is a defect and there is no view mode that could
## excuse one. The overview additionally has to stand on the club's side of the
## body, which is the bug the A2.13b visual check found - the club was in frustum
## but behind the torso, and an occluded club looks exactly like a missing one.
func _check_views(node: Node3D, label: String) -> void:
	_check(
		(Preview.VIEWS as Array).size() == 2,
		"%s the preview declares both F6 views" % label
	)
	for v in (Preview.VIEWS as Array).size():
		node.select_view(v)
		var d: Dictionary = node.view_diagnostics()
		var name: String = str(d.get("view", "?"))
		_check(
			bool(d.get("declares_weapon_shown", false)),
			"%s view '%s' declares that it shows the weapon" % [label, name]
		)
		_check(
			bool(d.get("attached", false)),
			"%s view '%s' has the club attached" % [label, name]
		)
		_check(
			bool(d.get("visible_meshes", false)),
			"%s view '%s' has the club's meshes visible" % [label, name]
		)
		_check(
			bool(d.get("in_frame", false)),
			"%s view '%s' has the club inside the frustum" % [label, name]
		)
		_check(
			str(node.hud_text()).contains("view          : %s" % name),
			"%s HUD names the active view '%s'" % [label, name]
		)
		_check(
			str(node.hud_text()).contains("club          : attached and in frame"),
			"%s view '%s' reports the club as shown, not hidden" % [label, name]
		)
		if v == 1:
			_check(
				bool(d.get("nearer_than_body_axis", false)),
				("%s the overview camera stands on the club's side of the body"
					+ " (club %.4f m vs body axis %.4f m)") % [
					label,
					float(d.get("camera_distance", 0.0)),
					float(d.get("body_axis_distance", 0.0)),
				]
			)
	node.select_view(0)


func _check(ok: bool, label: String) -> void:
	_total += 1
	if ok:
		print("PASS: %s" % label)
	else:
		_any_fail = true
		print("FAIL: %s" % label)
