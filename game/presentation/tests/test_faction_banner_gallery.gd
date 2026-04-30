# Headless: godot --headless --path game -s res://presentation/tests/test_faction_banner_gallery.gd
extends SceneTree

const FactionBannerGalleryScript = preload("res://presentation/faction_banner_gallery.gd")
const FactionDefinitionsScript = preload("res://domain/content/faction_definitions.gd")

var _total: int = 0
var _any_fail: bool = false


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var g = FactionBannerGalleryScript.new()
	root.add_child(g)
	call_deferred("_finish_tests", g)


func _finish_tests(g) -> void:
	_check(g.visible == false, "hidden by default")
	_check(g.banner_row != null, "banner_row set")
	_check(
		g.banner_row.get_child_count() == (FactionDefinitionsScript.ids() as Array).size(),
		"one column per faction id"
	)

	g.toggle_visible()
	_check(g.visible == true, "toggle show")
	g.toggle_visible()
	_check(g.visible == false, "toggle hide")

	_check(FactionBannerGalleryScript.resolve_banner_texture("") == null, "resolve empty path")
	_check(
		FactionBannerGalleryScript.resolve_banner_texture(
			"res://assets/prototype/factions/banners/__nonexistent__banner__.png"
		)
		== null,
		"resolve missing path"
	)

	if _any_fail:
		call_deferred("quit", 1)
	else:
		print("PASS %d/%d" % [_total, _total])
		call_deferred("quit", 0)


func _check(cond, message) -> void:
	_total = _total + 1
	if cond:
		return
	_any_fail = true
	var line = "FAIL: %s" % message
	print(line)
	push_error(line)
