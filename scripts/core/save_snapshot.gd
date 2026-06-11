class_name SaveSnapshot
extends RefCounted

const VERSION := 1


static func create(
		player_state: Dictionary = {},
		wanted_state: Dictionary = {},
		district_states: Array = [],
		mission_state: Dictionary = {}) -> Dictionary:
	return {
		"version": VERSION,
		"player": _normalize_player(player_state),
		"wanted": _normalize_wanted(wanted_state),
		"districts": _normalize_districts(district_states),
		"mission": _normalize_mission(mission_state),
	}


static func is_valid_snapshot(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false

	var raw: Dictionary = value
	return int(raw.get("version", -1)) == VERSION \
			and raw.has("player") \
			and raw.has("wanted") \
			and raw.has("districts") \
			and raw.has("mission")


static func normalize(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return create()

	var raw: Dictionary = value
	return create(
		_to_dictionary(raw.get("player", {})),
		_to_dictionary(raw.get("wanted", {})),
		_to_array(raw.get("districts", [])),
		_to_dictionary(raw.get("mission", {}))
	)


static func restore(saved_snapshot: Dictionary) -> Dictionary:
	var saved := normalize(saved_snapshot)
	return saved.duplicate(true)


static func vector3_to_data(value: Variant) -> Array:
	var vector := vector3_from_data(value)
	return [vector.x, vector.y, vector.z]


static func vector3_from_data(value: Variant) -> Vector3:
	match typeof(value):
		TYPE_VECTOR3:
			return value
		TYPE_ARRAY:
			var values: Array = value
			return Vector3(
				_to_float(values[0] if values.size() > 0 else 0.0),
				_to_float(values[1] if values.size() > 1 else 0.0),
				_to_float(values[2] if values.size() > 2 else 0.0)
			)
		TYPE_DICTIONARY:
			var values: Dictionary = value
			return Vector3(
				_to_float(values.get("x", 0.0)),
				_to_float(values.get("y", 0.0)),
				_to_float(values.get("z", 0.0))
			)
	return Vector3.ZERO


static func _normalize_player(raw: Dictionary) -> Dictionary:
	var rotation_value: Variant = raw.get("rotation", raw.get("global_rotation", Vector3.ZERO))
	return {
		"global_position": vector3_to_data(raw.get("global_position", raw.get("position", Vector3.ZERO))),
		"velocity": vector3_to_data(raw.get("velocity", Vector3.ZERO)),
		"rotation": vector3_to_data(rotation_value),
	}


static func _normalize_wanted(raw: Dictionary) -> Dictionary:
	return {
		"heat": maxf(_to_float(raw.get("heat", 0.0)), 0.0),
		"level": clampi(_to_int(raw.get("level", 0)), 0, 5),
	}


static func _normalize_districts(raw: Array) -> Array:
	var result: Array = []
	var seen := {}
	for entry in raw:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var district: Dictionary = entry
		var district_name := str(district.get("district_name", district.get("id", "")))
		if district_name.is_empty():
			continue
		seen[district_name] = {
			"district_name": district_name,
			"control": clampf(_to_float(district.get("control", 0.0)), -1.0, 1.0),
		}

	var names := seen.keys()
	names.sort()
	for name in names:
		result.append(seen[name])
	return result


static func _normalize_mission(raw: Dictionary) -> Dictionary:
	var objectives := _normalize_objectives(_to_array(raw.get("objectives", [])))
	var current_index := _to_int(raw.get("current_objective_index", _derive_current_objective_index(objectives)))
	current_index = clampi(current_index, 0, objectives.size())
	return {
		"mission_id": str(raw.get("mission_id", raw.get("id", ""))),
		"scene_path": str(raw.get("scene_path", "")),
		"current_objective_index": current_index,
		"objectives": objectives,
	}


static func _normalize_objectives(raw: Array) -> Array:
	var result: Array = []
	for entry in raw:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var objective: Dictionary = entry
		var objective_id := str(objective.get("id", ""))
		if objective_id.is_empty():
			continue
		result.append({
			"id": objective_id,
			"text": str(objective.get("text", "")),
			"done": bool(objective.get("done", false)),
		})
	return result


static func _derive_current_objective_index(objectives: Array) -> int:
	for index in range(objectives.size()):
		var objective: Dictionary = objectives[index]
		if not bool(objective.get("done", false)):
			return index
	return objectives.size()


static func _to_dictionary(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


static func _to_array(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


static func _to_float(value: Variant, default_value: float = 0.0) -> float:
	match typeof(value):
		TYPE_FLOAT, TYPE_INT:
			return float(value)
		TYPE_BOOL:
			return 1.0 if bool(value) else 0.0
		TYPE_STRING, TYPE_STRING_NAME:
			return float(str(value))
	return default_value


static func _to_int(value: Variant, default_value: int = 0) -> int:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return int(value)
		TYPE_BOOL:
			return 1 if bool(value) else 0
		TYPE_STRING, TYPE_STRING_NAME:
			return int(str(value))
	return default_value
