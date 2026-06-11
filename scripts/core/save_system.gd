class_name SaveSystem
extends Node

const SaveSnapshot = preload("res://scripts/core/save_snapshot.gd")

const DEFAULT_SAVE_PATH := "user://vibe_city_save.json"

@export var save_path := DEFAULT_SAVE_PATH


func _ready() -> void:
	set_process_unhandled_input(true)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return

	if key.keycode == KEY_F5:
		save()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_F9:
		load_save()
		get_viewport().set_input_as_handled()


func save() -> bool:
	var snapshot := gather_snapshot()
	return write_snapshot(snapshot)


func load_save() -> bool:
	var snapshot := read_snapshot()
	if snapshot.is_empty():
		return false

	apply_snapshot(snapshot)
	return true


func gather_snapshot() -> Dictionary:
	return SaveSnapshot.create(
		_gather_player_state(),
		_gather_wanted_state(),
		_gather_district_states(),
		_gather_mission_state()
	)


func apply_snapshot(snapshot: Dictionary) -> void:
	var normalized := SaveSnapshot.normalize(snapshot)
	_apply_player_state(normalized.get("player", {}))
	_apply_wanted_state(normalized.get("wanted", {}))
	_apply_district_states(normalized.get("districts", []))
	_apply_mission_state(normalized.get("mission", {}))


func write_snapshot(snapshot: Dictionary) -> bool:
	var normalized := SaveSnapshot.normalize(snapshot)
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_warning("SaveSystem could not write %s: %s" % [save_path, error_string(FileAccess.get_open_error())])
		return false

	file.store_string(JSON.stringify(normalized, "\t"))
	return true


func read_snapshot() -> Dictionary:
	if not FileAccess.file_exists(save_path):
		push_warning("SaveSystem found no save file at %s." % save_path)
		return {}

	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		push_warning("SaveSystem could not read %s: %s" % [save_path, error_string(FileAccess.get_open_error())])
		return {}

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not SaveSnapshot.is_valid_snapshot(parsed):
		push_warning("SaveSystem ignored corrupt or unsupported save file at %s." % save_path)
		return {}

	return SaveSnapshot.normalize(parsed)


func _gather_player_state() -> Dictionary:
	var body := _find_player_body()
	if body == null:
		push_warning("SaveSystem could not find a player body in group 'player'.")
		return {}

	return {
		"global_position": body.global_position,
		"velocity": body.velocity,
		"rotation": body.global_rotation,
	}


func _apply_player_state(player_state: Dictionary) -> void:
	var body := _find_player_body()
	if body == null:
		push_warning("SaveSystem could not restore player state because no player body was found.")
		return

	body.global_position = SaveSnapshot.vector3_from_data(player_state.get("global_position", Vector3.ZERO))
	body.velocity = SaveSnapshot.vector3_from_data(player_state.get("velocity", Vector3.ZERO))
	body.global_rotation = SaveSnapshot.vector3_from_data(player_state.get("rotation", Vector3.ZERO))
	if body.has_method("reset_physics_interpolation"):
		body.call("reset_physics_interpolation")


func _gather_wanted_state() -> Dictionary:
	var wanted := get_node_or_null("/root/Wanted")
	if wanted == null:
		return {}

	var heat := 0.0
	if wanted.has_method("get_heat"):
		heat = float(wanted.call("get_heat"))

	var level := 0
	if wanted.has_method("get_level"):
		level = int(wanted.call("get_level"))

	return {
		"heat": heat,
		"level": level,
	}


func _apply_wanted_state(wanted_state: Dictionary) -> void:
	var wanted := get_node_or_null("/root/Wanted")
	if wanted == null:
		return

	var heat := float(wanted_state.get("heat", 0.0))
	if wanted.has_method("restore_state"):
		wanted.call("restore_state", heat)
	elif wanted.has_method("clear") and heat <= 0.0:
		wanted.call("clear")
	else:
		push_warning("SaveSystem could not restore Wanted state; restore_state(heat) is unavailable.")


func _gather_district_states() -> Array:
	var result: Array = []
	for district in _collect_conversion_zone_roots():
		var district_name := _district_name_for(district)
		if district_name == &"" or not district.has_method("get_control"):
			continue
		result.append({
			"district_name": String(district_name),
			"control": float(district.call("get_control")),
		})
	return result


func _apply_district_states(district_states: Array) -> void:
	var districts_by_name := {}
	for district in _collect_conversion_zone_roots():
		var district_name := _district_name_for(district)
		if district_name != &"":
			districts_by_name[String(district_name)] = district

	for entry in district_states:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var district_state: Dictionary = entry
		var district_name := str(district_state.get("district_name", ""))
		var district: Node = districts_by_name.get(district_name)
		if district == null:
			push_warning("SaveSystem could not find district '%s' while loading." % district_name)
			continue
		if not district.has_method("restore_control"):
			push_warning("SaveSystem could not restore district '%s'; restore_control(value) is unavailable." % district_name)
			continue
		district.call("restore_control", float(district_state.get("control", 0.0)))


func _gather_mission_state() -> Dictionary:
	var missions := get_node_or_null("/root/Missions")
	if missions == null or not missions.has_method("get_save_snapshot"):
		return {}
	return missions.call("get_save_snapshot")


func _apply_mission_state(mission_state: Dictionary) -> void:
	var missions := get_node_or_null("/root/Missions")
	if missions == null:
		return
	if not missions.has_method("restore_save_snapshot"):
		push_warning("SaveSystem could not restore Missions state; restore_save_snapshot(snapshot) is unavailable.")
		return
	missions.call("restore_save_snapshot", mission_state)


func _find_player_body() -> CharacterBody3D:
	for node in get_tree().get_nodes_in_group(&"player"):
		var body := node as CharacterBody3D
		if body != null:
			return body

		var child_body := node.get_node_or_null("Body") as CharacterBody3D
		if child_body != null:
			return child_body
	return null


func _collect_conversion_zone_roots() -> Array:
	var result: Array = []
	var seen := {}
	for node in get_tree().get_nodes_in_group(&"conversion_zone"):
		var district := _resolve_district_node(node)
		if district == null:
			continue
		var id := district.get_instance_id()
		if seen.has(id):
			continue
		seen[id] = true
		result.append(district)
	return result


func _resolve_district_node(node: Node) -> Node:
	var cursor := node
	while cursor != null:
		if cursor.has_method("get_control") and _district_name_for(cursor) != &"":
			return cursor
		cursor = cursor.get_parent()
	return null


func _district_name_for(node: Node) -> StringName:
	if node == null:
		return &""
	var value: Variant = node.get("district_name")
	if value == null:
		return &""
	return StringName(str(value))
