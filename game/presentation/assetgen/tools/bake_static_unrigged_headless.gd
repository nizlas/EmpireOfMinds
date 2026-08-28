# Headless adapter for the generic rest-pose static bake. Godot owns the
# deformation; the caller owns serialisation.
#
#   godot --headless --path game \
#       -s res://presentation/assetgen/tools/bake_static_unrigged_headless.gd \
#       -- --scene=res://assets/.../warrior_3d.glb --mode=bake \
#          --report=<native path>.json --arrays=<native path>.bin
#
# WHY THE ARRAYS LEAVE AS A RAW BLOB INSTEAD OF A GLB. Godot can write glTF, but
# it would re-encode the material and re-compress the embedded texture, so the
# output could no longer be proven to carry the SOURCE's texture bytes, and the
# byte layout would depend on the engine's exporter rather than on anything this
# repository controls. The engine therefore reports evaluated geometry and the
# Python side assembles the GLB deterministically, copying the source material,
# images and samplers verbatim.
#
# EXIT PROTOCOL
#   0  requested mode completed
#   2  classified asset failure (named error class; the asset is unusable)
#   1  infrastructure / invocation / IO failure
extends SceneTree

const Bake := preload("res://presentation/assetgen/rest_pose_static_bake.gd")

const EXIT_OK := 0
const EXIT_INFRA := 1
const EXIT_CLASSIFIED := 2

const MARKER := "STATIC_BAKE"

## Invocation and IO problems: the tool or its caller is wrong, not the asset.
const INFRA_ERROR_CLASSES: Array[String] = [
	"BAKE_ARGS_MISSING",
	"BAKE_SCENE_MISSING",
	"BAKE_SCENE_NOT_A_SCENE",
	"BAKE_INSTANTIATE_FAILED",
	"BAKE_REPORT_WRITE_FAILED",
	"BAKE_ARRAYS_WRITE_FAILED",
	"BAKE_ANIMATION_UNKNOWN",
]

var _report := {}


func _init() -> void:
	_run()


func _run() -> void:
	# One frame first: while the main-loop script is being constructed the
	# scene-tree root does not exist yet, and a node outside the tree reports
	# IDENTITY for `global_transform`. Baking then silently drops every ancestor
	# transform — for a Blender-exported armature that is a factor of 100.
	await process_frame

	var args: Dictionary = _parse_args()
	var scene_path: String = str(args.get("scene", ""))
	var mode: String = str(args.get("mode", "inspect"))
	var report_path: String = str(args.get("report", ""))
	var arrays_path: String = str(args.get("arrays", ""))

	_report = {
		"schema": Bake.SCHEMA,
		"mode": mode,
		"scene": scene_path,
		"godot_version": Engine.get_version_info(),
		"ok": false,
	}

	if scene_path.is_empty():
		_fail("BAKE_ARGS_MISSING", "--scene is required")
		return
	if mode == "bake" and arrays_path.is_empty():
		_fail("BAKE_ARGS_MISSING", "--arrays is required in bake mode")
		return
	if not ResourceLoader.exists(scene_path):
		_fail("BAKE_SCENE_MISSING", scene_path)
		return
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		_fail("BAKE_SCENE_NOT_A_SCENE", scene_path)
		return
	var instance: Node = packed.instantiate()
	if instance == null:
		_fail("BAKE_INSTANTIATE_FAILED", scene_path)
		return

	# The holder IS the output space. Tests place it deliberately: a bake that
	# leaked caller context would change when this transform changes.
	var holder := Node3D.new()
	holder.transform = _holder_transform(args)
	root.add_child(holder)
	holder.add_child(instance)

	_report["holder_transform"] = {
		"translation": _v(holder.transform.origin),
		"scale": _v(holder.transform.basis.get_scale()),
		"rotation_deg": _v(holder.transform.basis.get_euler() * 180.0 / PI),
	}
	_report["inspection"] = Bake.inspect(instance)

	# Deliberately hostile starting state on request: an animation left playing
	# must not be able to reach the baked geometry.
	var play: String = str(args.get("play-animation", ""))
	if not play.is_empty():
		var started: Dictionary = _start_animation(instance, play, float(str(args.get("play-seconds", "0.4"))))
		if not bool(started.get("ok", false)):
			_fail(str(started.get("error_class", "BAKE_ANIMATION_UNKNOWN")), str(started.get("detail", "")))
			return
		_report["played_animation"] = started

	if mode == "inspect":
		_report["ok"] = true
		_finish(report_path, EXIT_OK)
		return

	var baked: Dictionary = Bake.bake(instance, holder)
	if not bool(baked.get("ok", false)):
		_report["excluded_meshes"] = baked.get("excluded", [])
		_fail(str(baked.get("error_class", "BAKE_FAILED")), str(baked.get("detail", "")))
		return

	var surfaces: Array = baked["surfaces"]
	_report["excluded_meshes"] = baked.get("excluded", [])
	_report["measurement"] = Bake.measure(surfaces)
	_report["surfaces"] = _surface_metadata(surfaces)

	# Post-bake proof that the scene we measured is the scene we were given:
	# the restore path must have put every pose back.
	_report["post_bake_inspection_matches"] = _inspection_unchanged(instance)

	var wrote: Dictionary = _write_arrays(arrays_path, surfaces)
	if not bool(wrote.get("ok", false)):
		_fail("BAKE_ARRAYS_WRITE_FAILED", str(wrote.get("detail", "")))
		return
	_report["arrays"] = wrote["index"]
	_report["arrays_path"] = arrays_path
	_report["arrays_sha256"] = wrote["sha256"]
	_report["ok"] = true
	_finish(report_path, EXIT_OK)


func _holder_transform(args: Dictionary) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var scale: Vector3 = _parse_vector(str(args.get("holder-scale", "")), Vector3.ONE)
	var rotation: Vector3 = _parse_vector(str(args.get("holder-rotation-deg", "")), Vector3.ZERO)
	var translation: Vector3 = _parse_vector(str(args.get("holder-translation", "")), Vector3.ZERO)
	var basis := Basis.from_euler(rotation * PI / 180.0)
	basis = basis.scaled(scale)
	xf.basis = basis
	xf.origin = translation
	return xf


func _parse_vector(text: String, fallback: Vector3) -> Vector3:
	if text.is_empty():
		return fallback
	var parts: PackedStringArray = text.split(",")
	if parts.size() != 3:
		return fallback
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))


func _start_animation(instance: Node, name: String, seconds: float) -> Dictionary:
	var players: Array = instance.find_children("*", "AnimationPlayer", true, false)
	for p in players:
		var ap: AnimationPlayer = p as AnimationPlayer
		var available: PackedStringArray = ap.get_animation_list()
		var chosen := ""
		if name == "*" and available.size() > 0:
			chosen = available[0]
		elif available.has(name):
			chosen = name
		if chosen.is_empty():
			continue
		ap.play(chosen)
		ap.seek(seconds, true)
		return {
			"ok": true,
			"player": str(instance.get_path_to(ap)),
			"animation": chosen,
			"position": ap.current_animation_position,
			"playing": ap.is_playing(),
		}
	return {
		"ok": false,
		"error_class": "BAKE_ANIMATION_UNKNOWN",
		"detail": "no AnimationPlayer offers %s" % name,
	}


## Every skeleton back at the pose it arrived with, and every player restored.
## Reported, not assumed: the restore is part of the contract.
func _inspection_unchanged(instance: Node) -> bool:
	var now: Dictionary = Bake.inspect(instance)
	var before: Dictionary = _report.get("inspection", {})
	return JSON.stringify(now) == JSON.stringify(before)


func _surface_metadata(surfaces: Array) -> Array:
	var rows: Array = []
	for entry in surfaces:
		var surface: Dictionary = entry
		var indices: PackedInt32Array = surface["indices"]
		var positions: PackedVector3Array = surface["positions"]
		rows.append(
			{
				"source_node_path": surface["source_node_path"],
				"source_mesh_name": surface["source_mesh_name"],
				"source_surface": surface["source_surface"],
				"was_skinned": surface["was_skinned"],
				"bones_per_vertex": surface["bones_per_vertex"],
				"material_name": surface["material_name"],
				"material_class": surface["material_class"],
				"reflected_vertices": surface["reflected_vertices"],
				"vertex_count": positions.size(),
				"index_count": indices.size(),
				"triangle_count": int((indices.size() if indices.size() > 0 else positions.size()) / 3),
				"has_normals": (surface["normals"] as PackedVector3Array).size() > 0,
				"has_tangents": (surface["tangents"] as PackedFloat32Array).size() > 0,
				"has_uv": (surface["uv"] as PackedVector2Array).size() > 0,
				"has_uv2": (surface["uv2"] as PackedVector2Array).size() > 0,
				"has_colors": (surface["colors"] as PackedColorArray).size() > 0,
			}
		)
	return rows


## Fixed-order little-endian blob plus a JSON index. Deterministic by
## construction: no dictionary iteration, no timestamps, no resource ids.
func _write_arrays(path: String, surfaces: Array) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "detail": "cannot open %s (error %d)" % [path, FileAccess.get_open_error()]}
	var index: Array = []
	var offset := 0
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	for entry in surfaces:
		var surface: Dictionary = entry
		var row := {"sections": {}}
		var blocks: Array = [
			["positions", _vec3_bytes(surface["positions"])],
			["normals", _vec3_bytes(surface["normals"])],
			["tangents", (surface["tangents"] as PackedFloat32Array).to_byte_array()],
			["uv", _vec2_bytes(surface["uv"])],
			["uv2", _vec2_bytes(surface["uv2"])],
			["colors", _color_bytes(surface["colors"])],
			["indices", _index_bytes(surface["indices"])],
		]
		for block in blocks:
			var name: String = block[0]
			var bytes: PackedByteArray = block[1]
			if bytes.size() == 0:
				continue
			file.store_buffer(bytes)
			context.update(bytes)
			row["sections"][name] = {"offset": offset, "length": bytes.size()}
			offset += bytes.size()
		row["vertex_count"] = (surface["positions"] as PackedVector3Array).size()
		row["index_count"] = (surface["indices"] as PackedInt32Array).size()
		index.append(row)
	file.close()
	return {"ok": true, "index": index, "sha256": context.finish().hex_encode()}


func _vec3_bytes(values: PackedVector3Array) -> PackedByteArray:
	var flat := PackedFloat32Array()
	flat.resize(values.size() * 3)
	for i in values.size():
		flat[i * 3] = values[i].x
		flat[i * 3 + 1] = values[i].y
		flat[i * 3 + 2] = values[i].z
	return flat.to_byte_array()


func _vec2_bytes(values: PackedVector2Array) -> PackedByteArray:
	var flat := PackedFloat32Array()
	flat.resize(values.size() * 2)
	for i in values.size():
		flat[i * 2] = values[i].x
		flat[i * 2 + 1] = values[i].y
	return flat.to_byte_array()


func _color_bytes(values: PackedColorArray) -> PackedByteArray:
	var flat := PackedFloat32Array()
	flat.resize(values.size() * 4)
	for i in values.size():
		flat[i * 4] = values[i].r
		flat[i * 4 + 1] = values[i].g
		flat[i * 4 + 2] = values[i].b
		flat[i * 4 + 3] = values[i].a
	return flat.to_byte_array()


func _index_bytes(values: PackedInt32Array) -> PackedByteArray:
	return values.to_byte_array()


func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if not s.begins_with("--"):
			continue
		var body := s.substr(2)
		var eq := body.find("=")
		if eq < 0:
			out[body] = "1"
		else:
			out[body.substr(0, eq)] = body.substr(eq + 1)
	return out


func _fail(error_class: String, detail: String) -> void:
	_report["ok"] = false
	_report["error_class"] = error_class
	_report["detail"] = detail
	var infra: bool = error_class in INFRA_ERROR_CLASSES
	_report["failure_kind"] = "infrastructure" if infra else "classified_asset_failure"
	_finish(str(_report.get("report_path", "")), EXIT_INFRA if infra else EXIT_CLASSIFIED)


func _finish(report_path: String, code: int) -> void:
	var payload: String = JSON.stringify(_jsonable(_report))
	if not report_path.is_empty():
		var file := FileAccess.open(report_path, FileAccess.WRITE)
		if file != null:
			file.store_string(payload)
			file.close()
	print("%s %s" % [MARKER, payload])
	quit(code)


func _v(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


func _jsonable(v):
	match typeof(v):
		TYPE_DICTIONARY:
			var o := {}
			for k in (v as Dictionary).keys():
				o[str(k)] = _jsonable((v as Dictionary)[k])
			return o
		TYPE_ARRAY:
			var a := []
			for it in (v as Array):
				a.append(_jsonable(it))
			return a
		TYPE_VECTOR3, TYPE_VECTOR2:
			return [v.x, v.y] if typeof(v) == TYPE_VECTOR2 else [v.x, v.y, v.z]
		TYPE_QUATERNION:
			return [v.x, v.y, v.z, v.w]
		TYPE_PACKED_STRING_ARRAY:
			var s := []
			for it in v:
				s.append(str(it))
			return s
		_:
			return v
