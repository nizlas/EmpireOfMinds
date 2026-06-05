# C14d-visual: front door centered narrow menu in lower half + background.
extends SceneTree

const CloudFrontDoorScript = preload("res://cloud/cloud_front_door.gd")
const FRONT_DOOR_SCENE: String = "res://cloud/cloud_front_door.tscn"

var _total = 0
var _any_fail = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_front_door_layout()
	if _any_fail:
		call_deferred("quit", 1)
	else:
		print("PASS %d/%d" % [_total, _total])
		call_deferred("quit", 0)


func _check(cond: bool, message: String) -> void:
	_total += 1
	if cond:
		return
	_any_fail = true
	var line := "FAIL: %s" % message
	print(line)
	push_error(line)


func _test_front_door_layout() -> void:
	_check(
		CloudFrontDoorScript.FRONT_DOOR_BACKGROUND_TEXTURE_PATH
			== "res://assets/prototype/ui/backgrounds/empire_of_minds_title_page.png",
		"front door title page texture path",
	)
	_check(
		ResourceLoader.exists(CloudFrontDoorScript.FRONT_DOOR_BACKGROUND_TEXTURE_PATH),
		"title page texture resource exists",
	)
	var packed: PackedScene = load(FRONT_DOOR_SCENE) as PackedScene
	_check(packed != null, "load cloud_front_door.tscn")
	if packed == null:
		return
	var door: Control = packed.instantiate() as Control
	get_root().add_child(door)
	for _i in 3:
		await process_frame
	var bg: TextureRect = door.get_node_or_null(
		CloudFrontDoorScript.FRONT_DOOR_BACKGROUND_NODE_NAME
	) as TextureRect
	_check(bg != null, "FrontDoorBackground exists")
	if bg != null:
		if bg.texture != null:
			_check(
				str(bg.texture.resource_path).ends_with("empire_of_minds_title_page.png"),
				"front door uses title page background",
			)
		_check(
			bg.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_COVERED,
			"background keep-aspect-covered",
		)
		_check(bg.mouse_filter == Control.MOUSE_FILTER_IGNORE, "background ignores mouse")
	var ui: Control = door.get_node_or_null(CloudFrontDoorScript.FRONT_DOOR_UI_ROOT_NODE_NAME) as Control
	_check(ui != null, "FrontDoorUiRoot exists")
	if ui != null:
		var w: float = CloudFrontDoorScript.FRONT_DOOR_UI_WIDTH_FRACTION
		var col_left: float = (1.0 - w) * 0.5
		var col_right: float = col_left + w
		_check(absf(ui.anchor_left - col_left) < 0.001, "ui column one-quarter width centered")
		_check(absf(ui.anchor_right - col_right) < 0.001, "ui column right edge")
		_check(
			absf(ui.anchor_top - CloudFrontDoorScript.FRONT_DOOR_UI_TOP_ANCHOR) < 0.001,
			"menu starts at vertical midpoint",
		)
	if bg != null and ui != null:
		_check(bg.get_index() < ui.get_index(), "background behind ui")
	_check(_find_button_named(door, "Local Hotseat") != null, "Local Hotseat button")
	_check(_find_button_named(door, "Create Cloud Match") != null, "Create Cloud Match button")
	var saved_list: ItemList = _find_item_list_after_label(door, "Your matches on this server")
	_check(saved_list != null, "saved matches ItemList exists")
	if saved_list != null:
		_check(
			saved_list.custom_minimum_size.y
				>= CloudFrontDoorScript.FRONT_DOOR_SAVED_LIST_MIN_HEIGHT_PX,
			"saved list at least two rows tall",
		)
		_check(
			saved_list.custom_minimum_size.y
				<= CloudFrontDoorScript.FRONT_DOOR_SAVED_LIST_MAX_HEIGHT_PX,
			"saved list at most seven rows tall",
		)
	var lobby_list: ItemList = _find_item_list_after_label(door, "Open staging matches")
	_check(lobby_list != null, "open staging ItemList exists")
	if lobby_list != null:
		_check(
			(lobby_list.size_flags_vertical & Control.SIZE_EXPAND) == 0,
			"lobby list does not expand vertically",
		)
		_check(
			lobby_list.custom_minimum_size.y
				>= CloudFrontDoorScript.FRONT_DOOR_LOBBY_LIST_MIN_HEIGHT_PX,
			"lobby list at least three rows tall",
		)
		_check(
			lobby_list.custom_minimum_size.y <= CloudFrontDoorScript.FRONT_DOOR_LOBBY_LIST_MAX_HEIGHT_PX,
			"lobby list height capped",
		)
	door.queue_free()


func _find_item_list_after_label(root: Node, label_text: String) -> ItemList:
	var labels: Array = []
	_collect_labels(root, labels)
	var i: int = 0
	while i < labels.size():
		var lbl: Label = labels[i] as Label
		if lbl.text == label_text:
			var parent: Node = lbl.get_parent()
			if parent != null:
				var j: int = lbl.get_index() + 1
				if j < parent.get_child_count() and parent.get_child(j) is ItemList:
					return parent.get_child(j) as ItemList
		i += 1
	return null


func _collect_labels(root: Node, out: Array) -> void:
	if root is Label:
		out.append(root)
	var c: int = 0
	while c < root.get_child_count():
		_collect_labels(root.get_child(c), out)
		c += 1


func _find_button_named(root: Node, text: String) -> Button:
	if root is Button and (root as Button).text == text:
		return root as Button
	var i: int = 0
	while i < root.get_child_count():
		var found: Button = _find_button_named(root.get_child(i), text)
		if found != null:
			return found
		i += 1
	return null
