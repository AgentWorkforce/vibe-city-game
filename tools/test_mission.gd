# Integration test: mission framework contract and the first liberation mission.
# Usage: godot --headless -s tools/test_mission.gd
# Autoloads are absent in -s mode, so this installs Events and a manager manually.
extends SceneTree

const MissionManagerScript = preload("res://scripts/missions/mission_manager.gd")
const EventsScript = preload("res://scripts/core/events.gd")
const MISSION_SCENE := "res://scenes/missions/liberate_nw.tscn"
const MAX_FRAMES := 220

var _frames := 0
var _events: Node
var _manager: MissionManager
var _world: Node3D
var _zone_area: Area3D
var _player_body: CharacterBody3D
var _objectives_seen: Array[String] = []
var _started_count := 0
var _completed_count := 0
var _failed_count := 0
var _failure_reason := ""
var _second_mission_started := false
var _finished := false
var _failures: Array[String] = []


func _initialize() -> void:
	_install_events()
	_make_mock_world()
	current_scene = _world

	_manager = MissionManagerScript.new()
	_manager.name = "Missions"
	_manager.auto_start_delay = 0.0
	root.add_child(_manager)


func _process(_delta: float) -> bool:
	_frames += 1

	match _frames:
		10:
			_check_auto_start_flow()
		20:
			_zone_area.emit_signal(&"body_entered", _player_body)
		30:
			_events.emit_signal(&"district_control_changed", &"playground_nw", -1.0)
		50:
			_check_completion_flow()
			_start_mission()
			_second_mission_started = true
		60:
			_events.emit_signal(&"player_caught", null)
		80:
			_check_failure_flow()
			_finish(0)
			return true

	if _frames >= MAX_FRAMES:
		return _fail("timed out before mission flow completed")

	return false


func _install_events() -> void:
	_events = root.get_node_or_null("Events")
	if _events == null:
		_events = EventsScript.new()
		_events.name = "Events"
		root.add_child(_events)
	_events.connect(&"mission_started", Callable(self, "_on_mission_started"))
	_events.connect(&"mission_objective", Callable(self, "_on_mission_objective"))
	_events.connect(&"mission_completed", Callable(self, "_on_mission_completed"))
	_events.connect(&"mission_failed", Callable(self, "_on_mission_failed"))


func _make_mock_world() -> void:
	_world = Node3D.new()
	_world.name = "MissionMockWorld"
	root.add_child(_world)

	var zone_root := Node3D.new()
	zone_root.name = "ConversionZone"
	_world.add_child(zone_root)

	_zone_area = Area3D.new()
	_zone_area.name = "ZoneArea"
	_zone_area.add_to_group(&"conversion_zone")
	zone_root.add_child(_zone_area)

	_player_body = CharacterBody3D.new()
	_player_body.name = "Body"
	_player_body.add_to_group(&"player")
	_world.add_child(_player_body)


func _start_mission() -> void:
	var mission := _manager.start_mission(MISSION_SCENE)
	if mission == null:
		_record_failure("manager failed to start liberate_nw mission")


func _check_auto_start_flow() -> void:
	if _started_count != 1:
		_record_failure("manager did not auto-start initial mission once after scene load")
	if _manager.get_active_mission() == null:
		_record_failure("auto-start did not create an active mission")


func _check_completion_flow() -> void:
	var mission := _manager.get_active_mission()
	if mission == null:
		_fail("no active mission after completion path")
		return

	if _started_count < 1:
		_record_failure("mission_started did not forward through Events")
	if not _objectives_seen.has("Visit the converted zone"):
		_record_failure("initial objective did not forward through Events")
	if not _objectives_seen.has("Disconnect all conversion pylons"):
		_record_failure("second objective did not appear after zone entry")
	if _completed_count != 1:
		_record_failure("mission_completed did not fire after zone entry and control flip")
	if not bool(mission.call("is_completed")):
		_record_failure("mission did not mark itself completed")


func _check_failure_flow() -> void:
	if not _second_mission_started:
		_record_failure("second mission did not start for failure path")
	if _failed_count != 1:
		_record_failure("mission_failed did not fire on player_caught")
	if _failure_reason != "politely detained":
		_record_failure("wrong failure reason: %s" % _failure_reason)
	if not _manager.is_active_mission_failed():
		_record_failure("manager did not keep failed mission for retry")

	var retry_ok := _manager.retry_active_mission()
	if not retry_ok:
		_record_failure("retry_active_mission returned false after failure")
	if _started_count < 3:
		_record_failure("retry did not restart the failed mission")

	if not _failures.is_empty():
		for failure in _failures:
			print("MISSION TEST FAIL: ", failure)
		_finish(1)
		return
	print("MISSION TEST PASS (objectives advanced, completion fired, failure fired, retry restarted)")


func _on_mission_started(_mission: Node) -> void:
	_started_count += 1


func _on_mission_objective(text: String) -> void:
	_objectives_seen.append(text)


func _on_mission_completed(_mission: Node) -> void:
	_completed_count += 1


func _on_mission_failed(_mission: Node, reason: String) -> void:
	_failed_count += 1
	_failure_reason = reason


func _fail(msg: String) -> bool:
	_record_failure(msg)
	for failure in _failures:
		print("MISSION TEST FAIL: ", failure)
	_finish(1)
	return true


func _record_failure(msg: String) -> void:
	if not _failures.has(msg):
		_failures.append(msg)


func _finish(status: int) -> void:
	if _finished:
		return
	_finished = true
	current_scene = null

	if is_instance_valid(_manager):
		root.remove_child(_manager)
		_manager.free()
	if is_instance_valid(_world):
		root.remove_child(_world)
		_world.free()
	if is_instance_valid(_events):
		root.remove_child(_events)
		_events.free()

	quit(status)
