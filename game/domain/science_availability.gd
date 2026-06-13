# Phase 5.1.12b — derived science availability from ProgressDefinitions prerequisites + completed_progress_ids.
# available_for follows ProgressDefinitions.ids() tree order (auto-target uses first entry).
# locked_for / completed_for remain sorted alphabetically for stable display lists.
class_name ScienceAvailability
extends RefCounted

const ProgressDefinitionsScript = preload("res://domain/content/progress_definitions.gd")


static func _sort_ids(ids: Array) -> void:
	var a = 0
	while a < ids.size():
		var b = a + 1
		while b < ids.size():
			if str(ids[a]) > str(ids[b]):
				var tmp = ids[a]
				ids[a] = ids[b]
				ids[b] = tmp
			b = b + 1
		a = a + 1


static func _prerequisites_satisfied(progress_state, owner_id: int, science_id: String) -> bool:
	if progress_state == null:
		return false
	var req = ProgressDefinitionsScript.prerequisites(science_id)
	var i = 0
	while i < req.size():
		if not progress_state.has_completed_progress(owner_id, str(req[i])):
			return false
		i = i + 1
	return true


static func completed_for(progress_state, owner_id: int) -> Array[String]:
	var out: Array[String] = []
	if progress_state == null:
		return out
	var raw = progress_state.completed_progress_ids_for(owner_id)
	var i = 0
	while i < raw.size():
		var pid = str(raw[i])
		if ProgressDefinitionsScript.is_science(pid):
			out.append(pid)
		i = i + 1
	_sort_ids(out)
	return out


static func is_available(progress_state, owner_id: int, science_id: String) -> bool:
	if not ProgressDefinitionsScript.is_science(science_id):
		return false
	if progress_state == null:
		return false
	if progress_state.has_completed_progress(owner_id, science_id):
		return false
	return _prerequisites_satisfied(progress_state, owner_id, science_id)


static func available_for(progress_state, owner_id: int) -> Array[String]:
	var out: Array[String] = []
	if progress_state == null:
		return out
	var ids = ProgressDefinitionsScript.ids()
	var i = 0
	while i < ids.size():
		var sid = str(ids[i])
		if is_available(progress_state, owner_id, sid):
			out.append(sid)
		i = i + 1
	return out


static func locked_for(progress_state, owner_id: int) -> Array[String]:
	var out: Array[String] = []
	if progress_state == null:
		return out
	var ids = ProgressDefinitionsScript.ids()
	var i = 0
	while i < ids.size():
		var sid = str(ids[i])
		if not ProgressDefinitionsScript.is_science(sid):
			i = i + 1
			continue
		if progress_state.has_completed_progress(owner_id, sid):
			i = i + 1
			continue
		if not _prerequisites_satisfied(progress_state, owner_id, sid):
			out.append(sid)
		i = i + 1
	_sort_ids(out)
	return out
