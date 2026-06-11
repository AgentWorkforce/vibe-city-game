class_name Mission
extends Node

signal mission_started(mission: Mission)
signal objective_updated(mission: Mission, text: String)
signal mission_completed(mission: Mission)
signal mission_failed(mission: Mission, reason: String)

@export var mission_id: StringName = &""
@export var title: String = ""

var objectives: Array[Dictionary] = []

var _active := false
var _completed := false
var _failed := false


func start() -> void:
	_active = true
	_completed = false
	_failed = false
	_reset_objectives()
	mission_started.emit(self)
	_emit_current_objective()


func complete_objective(id: StringName) -> bool:
	if not _active or _completed or _failed:
		return false

	for index in range(objectives.size()):
		var objective := objectives[index]
		if StringName(objective.get("id", &"")) != id:
			continue
		if bool(objective.get("done", false)):
			return false

		objective["done"] = true
		objectives[index] = objective
		_on_objective_changed()

		if _all_objectives_done():
			complete_mission()
		else:
			_emit_current_objective()
		return true

	return false


func complete_mission() -> void:
	if not _active or _completed or _failed:
		return

	_active = false
	_completed = true
	mission_completed.emit(self)


func fail_mission(reason: String) -> void:
	if not _active or _completed or _failed:
		return

	_active = false
	_failed = true
	mission_failed.emit(self, reason)


func set_objectives(definitions: Array[Dictionary]) -> void:
	objectives.clear()
	for definition in definitions:
		objectives.append({
			"id": StringName(definition.get("id", &"")),
			"text": str(definition.get("text", "")),
			"done": bool(definition.get("done", false)),
		})


func get_current_objective_text() -> String:
	for objective in objectives:
		if not bool(objective.get("done", false)):
			return str(objective.get("text", ""))
	return ""


func get_objective_position():
	return null


func get_objective_done(id: StringName) -> bool:
	for objective in objectives:
		if StringName(objective.get("id", &"")) == id:
			return bool(objective.get("done", false))
	return false


func get_current_objective_index() -> int:
	for index in range(objectives.size()):
		if not bool(objectives[index].get("done", false)):
			return index
	return objectives.size()


func get_objective_states() -> Array:
	var states: Array = []
	for objective in objectives:
		states.append({
			"id": String(objective.get("id", &"")),
			"text": str(objective.get("text", "")),
			"done": bool(objective.get("done", false)),
		})
	return states


func restore_objective_states(states: Array, current_objective_index: int = -1) -> void:
	var done_by_id := {}
	for state in states:
		if typeof(state) != TYPE_DICTIONARY:
			continue
		var objective_state: Dictionary = state
		var objective_id := StringName(str(objective_state.get("id", "")))
		if objective_id == &"":
			continue
		done_by_id[objective_id] = bool(objective_state.get("done", false))

	for index in range(objectives.size()):
		var objective := objectives[index]
		var objective_id := StringName(objective.get("id", &""))
		if done_by_id.has(objective_id):
			objective["done"] = bool(done_by_id[objective_id])
		elif current_objective_index >= 0:
			objective["done"] = index < current_objective_index
		objectives[index] = objective

	_failed = false
	_completed = _all_objectives_done()
	_active = not _completed
	if _active:
		_emit_current_objective()
	elif _completed:
		mission_completed.emit(self)


func is_active() -> bool:
	return _active


func is_completed() -> bool:
	return _completed


func is_failed() -> bool:
	return _failed


func _on_objective_changed() -> void:
	pass


func _emit_current_objective() -> void:
	var text := get_current_objective_text()
	if text.is_empty():
		return
	objective_updated.emit(self, text)


func _reset_objectives() -> void:
	for index in range(objectives.size()):
		var objective := objectives[index]
		objective["done"] = false
		objectives[index] = objective


func _all_objectives_done() -> bool:
	if objectives.is_empty():
		return false

	for objective in objectives:
		if not bool(objective.get("done", false)):
			return false
	return true
