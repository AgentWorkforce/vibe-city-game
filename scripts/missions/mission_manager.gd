class_name MissionManager
extends Node

@export_file("*.tscn") var initial_mission_scene: String = "res://scenes/missions/liberate_nw.tscn"
@export var auto_start_delay: float = 5.0

var _active_mission: Mission
var _active_scene_path := ""
var _active_failed := false
var _auto_start_scheduled := false
var _auto_start_fired := false


func _ready() -> void:
	set_process(not initial_mission_scene.is_empty())


func _process(_delta: float) -> void:
	if initial_mission_scene.is_empty() or _auto_start_scheduled or _auto_start_fired:
		set_process(false)
		return
	if get_tree().current_scene == null or get_active_mission() != null:
		return

	_schedule_auto_start()
	set_process(false)


func start_mission(scene_path: String) -> Mission:
	if scene_path.is_empty():
		push_error("MissionManager.start_mission requires a scene path.")
		return null

	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_error("MissionManager could not load mission scene: %s" % scene_path)
		return null

	var mission_node := packed.instantiate()
	var mission := mission_node as Mission
	if mission == null:
		mission_node.queue_free()
		push_error("Mission scene does not extend Mission: %s" % scene_path)
		return null

	_clear_active_mission()
	_active_mission = mission
	_active_scene_path = scene_path
	_active_failed = false

	_connect_mission_signals(mission)
	add_child(mission)
	mission.start()
	return mission


func retry_active_mission() -> bool:
	if not is_instance_valid(_active_mission) or not _active_failed:
		return false

	_active_failed = false
	_active_mission.start()
	return true


func get_active_mission() -> Mission:
	if is_instance_valid(_active_mission):
		return _active_mission
	return null


func get_active_scene_path() -> String:
	return _active_scene_path


func is_active_mission_failed() -> bool:
	return _active_failed


func get_save_snapshot() -> Dictionary:
	var mission := get_active_mission()
	if mission == null:
		return {}

	return {
		"mission_id": String(mission.mission_id),
		"scene_path": _active_scene_path,
		"current_objective_index": mission.get_current_objective_index(),
		"objectives": mission.get_objective_states(),
	}


func restore_save_snapshot(snapshot: Dictionary) -> Mission:
	_auto_start_fired = true
	_auto_start_scheduled = false

	var scene_path := str(snapshot.get("scene_path", ""))
	if scene_path.is_empty():
		_clear_active_mission()
		return null

	var mission := start_mission(scene_path)
	if mission == null:
		return null

	var objective_states: Array = snapshot.get("objectives", [])
	mission.restore_objective_states(
		objective_states,
		int(snapshot.get("current_objective_index", -1))
	)
	_active_failed = false
	return mission


func _schedule_auto_start() -> void:
	if not is_inside_tree():
		return

	_auto_start_scheduled = true
	var timer := get_tree().create_timer(maxf(auto_start_delay, 0.0))
	timer.timeout.connect(_on_auto_start_timeout)


func _on_auto_start_timeout() -> void:
	_auto_start_scheduled = false

	if _auto_start_fired:
		return
	if get_tree().current_scene == null:
		set_process(not initial_mission_scene.is_empty())
		return

	_auto_start_fired = true
	if get_active_mission() == null and not initial_mission_scene.is_empty():
		start_mission(initial_mission_scene)


func _clear_active_mission() -> void:
	if not is_instance_valid(_active_mission):
		_active_mission = null
		_active_scene_path = ""
		_active_failed = false
		return

	remove_child(_active_mission)
	_active_mission.queue_free()
	_active_mission = null
	_active_scene_path = ""
	_active_failed = false


func _connect_mission_signals(mission: Mission) -> void:
	_connect_once(mission, &"mission_started", Callable(self, "_on_mission_started"))
	_connect_once(mission, &"objective_updated", Callable(self, "_on_objective_updated"))
	_connect_once(mission, &"mission_completed", Callable(self, "_on_mission_completed"))
	_connect_once(mission, &"mission_failed", Callable(self, "_on_mission_failed"))


func _connect_once(source: Object, signal_name: StringName, callback: Callable) -> void:
	if not source.is_connected(signal_name, callback):
		source.connect(signal_name, callback)


func _on_mission_started(mission: Mission) -> void:
	_active_failed = false
	_emit_events_signal(&"mission_started", [mission])


func _on_objective_updated(_mission: Mission, text: String) -> void:
	_emit_events_signal(&"mission_objective", [text])


func _on_mission_completed(mission: Mission) -> void:
	_active_failed = false
	_emit_events_signal(&"mission_completed", [mission])


func _on_mission_failed(mission: Mission, reason: String) -> void:
	_active_failed = true
	_emit_events_signal(&"mission_failed", [mission, reason])


func _emit_events_signal(signal_name: StringName, args: Array) -> void:
	var events := _events()
	if events == null or not events.has_signal(signal_name):
		return

	var call_args: Array = [signal_name]
	call_args.append_array(args)
	events.callv("emit_signal", call_args)


func _events() -> Node:
	return get_node_or_null("/root/Events")
