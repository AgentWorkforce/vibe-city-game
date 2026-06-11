# Integration test: close the combat/de-escalation loop.
# Usage: godot --headless -s tools/test_deescalation.gd
# Autoloads can be absent in -s mode, so this installs Events and Wanted if needed.
extends SceneTree

const MAX_FRAMES := 1200

var _frames := 0
var _failures: Array[String] = []
var _playground: Node3D
var _player_root: Node3D
var _player_body: CharacterBody3D
var _camera: Camera3D
var _respawn_marker: Node3D
var _events: Node
var _wanted: Node
var _agent: CharacterBody3D
var _agent_health: Node
var _police: Node3D
var _deescalation: Node
var _shot_fired := false
var _crime_verified := false
var _catch_started := false
var _saw_player_down_bark := false
var _wanted_before_catch := 0
var _saw_caught_event := false
var _saw_local_caught_signal := false
var _created_events := false
var _created_wanted := false
var _pending_status := -1
var _finish_frame := -1


func _initialize() -> void:
	_install_autoloads()

	var scene: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene"))
	_playground = scene.instantiate() as Node3D
	root.add_child(_playground)
	current_scene = _playground

	_player_root = root.get_node("Playground/Player") as Node3D
	_player_body = _player_root.get_node("Body") as CharacterBody3D
	_camera = _player_root.get_node("CameraRig/Pitch/SpringArm3D/Camera3D") as Camera3D
	_respawn_marker = root.get_node("Playground/PlayerSpawn") as Node3D

	_add_deescalation()


func _process(_delta: float) -> bool:
	_frames += 1
	if _pending_status >= 0:
		if _frames >= _finish_frame:
			_finish(_pending_status)
			return true
		return false

	match _frames:
		20:
			_place_agent_on_camera_ray()
		60:
			Input.action_press("fire")
			_shot_fired = true
		62:
			Input.action_release("fire")

	if _shot_fired and not _crime_verified and _wanted_level() >= 1:
		_verify_shot_crime()
		if _failures.is_empty():
			_wanted_before_catch = _wanted_level()
			_crime_verified = true
			_start_police_catch()

	if _catch_started and _player_is_respawned() and _wanted_level() == 0:
		_check(_saw_player_down_bark, "player_down bark was not emitted")
		if is_instance_valid(_police) and _police.has_method("is_ignoring_player"):
			_check(bool(_police.call("is_ignoring_player")), "police grace was not active after catch")
		if _failures.is_empty():
			print("DEESCALATION TEST PASS (shot agent -> wanted %d before catch, respawned at %s, wanted cleared)" % [
				_wanted_before_catch,
				_respawn_marker.global_position,
			])
			_schedule_finish(0)
		else:
			_print_failures()
			_schedule_finish(1)
		return false

	if _frames >= MAX_FRAMES:
		_check(_crime_verified, "shooting the agent did not raise wanted")
		_check(_catch_started, "police catch did not start")
		_check(_player_is_respawned(), "player was not teleported to respawn")
		_check(_wanted_level() == 0, "wanted was not cleared after catch")
		_print_failures()
		_schedule_finish(1)
		return false

	return false


func _install_autoloads() -> void:
	_events = root.get_node_or_null("Events")
	if _events == null:
		var events_script := load("res://scripts/core/events.gd") as Script
		_events = events_script.new()
		_events.name = "Events"
		root.add_child(_events)
		_created_events = true

	_wanted = root.get_node_or_null("Wanted")
	if _wanted == null:
		var wanted_script := load("res://scripts/systems/wanted_system.gd") as Script
		_wanted = wanted_script.new()
		_wanted.name = "Wanted"
		root.add_child(_wanted)
		_created_wanted = true
	_wanted.call("clear")

	_events.connect(&"bark_emitted", Callable(self, "_on_bark_emitted"))
	_events.connect(&"player_caught", Callable(self, "_on_player_caught_event"))


func _add_deescalation() -> void:
	var deescalation_script := load("res://scripts/systems/deescalation.gd") as Script
	_deescalation = deescalation_script.new()
	_deescalation.name = "Deescalation"
	_deescalation.set("player_root_path", NodePath("/root/Playground/Player"))
	_deescalation.set("respawn_marker_path", NodePath("/root/Playground/PlayerSpawn"))
	_deescalation.set("police_grace_seconds", 5.0)
	root.add_child(_deescalation)


func _place_agent_on_camera_ray() -> void:
	var agent_scene := load("res://scenes/agents/agent.tscn") as PackedScene
	_agent = agent_scene.instantiate() as CharacterBody3D
	_agent.set("wander_radius", 0.0)
	_agent.set("notice_distance", 0.0)
	_agent.set("idle_chatter_min_interval", 999.0)
	_agent.set("idle_chatter_max_interval", 999.0)
	_playground.add_child(_agent)

	var origin := _camera.global_position
	var direction := -_camera.global_transform.basis.z.normalized()
	_agent.global_position = origin + direction * 14.0 - Vector3(0.0, 0.95, 0.0)
	_agent.set_physics_process(false)
	_agent_health = _agent.get_node("Health")


func _verify_shot_crime() -> void:
	_check(float(_agent_health.get("current")) <= 35.0, "agent health was not reduced by the blaster")
	_check(_wanted_level() >= 1, "weapon damage did not raise wanted")


func _start_police_catch() -> void:
	_catch_started = true
	var catch_position := Vector3(12.0, 1.0, 12.0)
	_player_root.global_position = catch_position
	_player_body.global_position = catch_position
	_player_body.velocity = Vector3.ZERO

	var police_scene := load("res://scenes/agents/police_agent.tscn") as PackedScene
	_police = police_scene.instantiate() as Node3D
	_police.set("activation_radius", 30.0)
	_police.set("catch_distance", 2.5)
	_police.set("idle_chatter_min_interval", 999.0)
	_police.set("idle_chatter_max_interval", 999.0)
	_playground.add_child(_police)
	_police.global_position = catch_position + Vector3(0.0, 0.0, 0.8)
	if _police.has_signal("player_caught"):
		_police.connect("player_caught", Callable(self, "_on_local_player_caught"))


func _player_is_respawned() -> bool:
	if not is_instance_valid(_player_body) or not is_instance_valid(_respawn_marker):
		return false
	return _player_body.global_position.distance_to(_respawn_marker.global_position) <= 0.25


func _wanted_level() -> int:
	if _wanted != null and _wanted.has_method("get_level"):
		return int(_wanted.call("get_level"))
	return -1


func _on_bark_emitted(_speaker: Node, category: StringName, _text: String) -> void:
	if category == &"player_down":
		_saw_player_down_bark = true


func _on_player_caught_event(_by: Node) -> void:
	_saw_caught_event = true


func _on_local_player_caught(_player: Node) -> void:
	_saw_local_caught_signal = true


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures.append(msg)


func _print_failures() -> void:
	if _failures.is_empty():
		_failures.append("test timed out before pass condition")
	print("DEESCALATION TEST DEBUG: frame=%d wanted=%d caught_event=%s local_caught=%s player=%s respawn=%s police_state=%s" % [
		_frames,
		_wanted_level(),
		_saw_caught_event,
		_saw_local_caught_signal,
		_player_body.global_position if is_instance_valid(_player_body) else Vector3.ZERO,
		_respawn_marker.global_position if is_instance_valid(_respawn_marker) else Vector3.ZERO,
		_police.call("get_police_state_name") if is_instance_valid(_police) and _police.has_method("get_police_state_name") else "none",
	])
	for failure in _failures:
		print("DEESCALATION TEST FAIL: ", failure)


func _schedule_finish(status: int) -> void:
	Input.action_release("fire")
	_pending_status = status
	_finish_frame = _frames + 240


func _finish(status: int) -> void:
	Input.action_release("fire")
	current_scene = null
	_stop_audio_under(root)

	if is_instance_valid(_deescalation):
		root.remove_child(_deescalation)
		_deescalation.free()

	if is_instance_valid(_playground):
		root.remove_child(_playground)
		_playground.free()

	if _created_wanted and is_instance_valid(_wanted):
		root.remove_child(_wanted)
		_wanted.free()

	if _created_events and is_instance_valid(_events):
		root.remove_child(_events)
		_events.free()

	quit(status)


func _stop_audio_under(node: Node) -> void:
	for child in node.get_children():
		_stop_audio_under(child)

	var audio_3d := node as AudioStreamPlayer3D
	if audio_3d != null:
		audio_3d.stop()
		audio_3d.stream = null
		return

	var audio := node as AudioStreamPlayer
	if audio != null:
		audio.stop()
		audio.stream = null
