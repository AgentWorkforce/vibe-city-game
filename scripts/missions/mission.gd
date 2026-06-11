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


func get_objective_done(id: StringName) -> bool:
	for objective in objectives:
		if StringName(objective.get("id", &"")) == id:
			return bool(objective.get("done", false))
	return false


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
