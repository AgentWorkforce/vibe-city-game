# Integration test: spawn cheap traffic on a minimal playground graph,
# verify it moves, stops for a blocking body, and resumes when clear.
# Usage: godot --headless -s tools/test_traffic.gd
# Poll-based: under headless -s, frame time is uncapped, so assertions wait
# for observed positions/speeds instead of fixed tween or frame timing.
extends SceneTree

const TrafficManagerScript = preload("res://scripts/traffic/traffic_manager.gd")

const MAX_FRAMES := 1600

enum Phase {
	WAIT_SPAWN,
	WAIT_MOVE,
	PLACE_OBSTACLE,
	WAIT_STOP,
	REMOVE_OBSTACLE,
	WAIT_RESUME,
}

var _frames := 0
var _phase := Phase.WAIT_SPAWN
var _phase_frames := 0
var _world: Node3D
var _manager: Node
var _car: Node3D
var _obstacle: StaticBody3D
var _move_start := Vector3.ZERO
var _stop_start := Vector3.ZERO
var _resume_start := Vector3.ZERO
var _stationary_position := Vector3.ZERO
var _stationary_frames := 0
var _failures: Array[String] = []


func _initialize() -> void:
	_world = Node3D.new()
	_world.name = "TrafficTestWorld"
	root.add_child(_world)
	_add_floor()
	_add_manager()


func _process(_delta: float) -> bool:
	_frames += 1
	_phase_frames += 1

	match _phase:
		Phase.WAIT_SPAWN:
			_wait_spawn()
		Phase.WAIT_MOVE:
			_wait_move()
		Phase.PLACE_OBSTACLE:
			_place_obstacle()
			_set_phase(Phase.WAIT_STOP)
		Phase.WAIT_STOP:
			_wait_stop()
		Phase.REMOVE_OBSTACLE:
			_remove_obstacle()
			_set_phase(Phase.WAIT_RESUME)
		Phase.WAIT_RESUME:
			_wait_resume()

	if _frames >= MAX_FRAMES:
		_fail("timed out in phase %s after %d frames" % [_phase_name(_phase), MAX_FRAMES])
		return true

	return false


func _wait_spawn() -> void:
	var cars: Array[Node] = _manager.call("get_cars")
	if cars.size() < 3:
		return

	_car = cars[0] as Node3D
	if _car == null:
		_fail("spawned car did not use TrafficCar script")
		return

	_move_start = _car.global_position
	_set_phase(Phase.WAIT_MOVE)


func _wait_move() -> void:
	var moved: float = _car.global_position.distance_to(_move_start)
	if moved > 2.0 and float(_car.call("get_current_speed")) > 1.0:
		_set_phase(Phase.PLACE_OBSTACLE)
		return

	if _phase_frames > 240:
		_fail("traffic car did not advance along the loop")


func _place_obstacle() -> void:
	var forward: Vector3 = (_car.call("get_forward_direction") as Vector3).normalized()
	_obstacle = StaticBody3D.new()
	_obstacle.name = "TrafficStopObstacle"
	_obstacle.position = _car.global_position + forward * 5.0

	var shape := BoxShape3D.new()
	shape.size = Vector3(3.0, 2.0, 3.0)
	var collision := CollisionShape3D.new()
	collision.position = Vector3(0.0, 1.0, 0.0)
	collision.shape = shape
	_obstacle.add_child(collision)
	_world.add_child(_obstacle)
	_stop_start = _car.global_position
	_stationary_position = _stop_start
	_stationary_frames = 0


func _wait_stop() -> void:
	if float(_car.call("get_current_speed")) <= 0.25 and _phase_frames > 8:
		var drift: float = _car.global_position.distance_to(_stop_start)
		if drift > 8.0:
			_fail("traffic car drifted %.2f m while stopping for obstacle" % drift)
			return

		if _car.global_position.distance_to(_stationary_position) <= 0.05:
			_stationary_frames += 1
		else:
			_stationary_frames = 0
			_stationary_position = _car.global_position

		if _stationary_frames >= 12:
			_set_phase(Phase.REMOVE_OBSTACLE)
			return

	if _phase_frames > 260:
		_fail("traffic car did not stop for obstacle; speed %.2f" % float(_car.call("get_current_speed")))


func _remove_obstacle() -> void:
	_resume_start = _car.global_position
	if _obstacle != null and is_instance_valid(_obstacle):
		_obstacle.queue_free()


func _wait_resume() -> void:
	var resumed_distance: float = _car.global_position.distance_to(_resume_start)
	if float(_car.call("get_current_speed")) > 2.0 and resumed_distance > 1.5:
		print("TRAFFIC TEST PASS (spawned %d cars, moved %.2f m, stopped, resumed %.2f m)" % [
			(_manager.call("get_cars") as Array).size(),
			_resume_start.distance_to(_move_start),
			resumed_distance,
		])
		quit(0)
		return

	if _phase_frames > 260:
		_fail("traffic car did not resume after obstacle removal; speed %.2f moved %.2f" % [
			float(_car.call("get_current_speed")),
			resumed_distance,
		])


func _add_floor() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	floor_body.position = Vector3(0.0, -0.08, 0.0)

	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(220.0, 0.16, 220.0)
	var floor_collision := CollisionShape3D.new()
	floor_collision.shape = floor_shape
	floor_body.add_child(floor_collision)
	_world.add_child(floor_body)


func _add_manager() -> void:
	_manager = TrafficManagerScript.new()
	_manager.name = "TrafficManager"
	_manager.graph_name = &"playground_ring"
	_manager.max_cars = 3
	_manager.min_car_speed = 8.0
	_manager.max_car_speed = 8.0
	_world.add_child(_manager)


func _set_phase(phase: int) -> void:
	_phase = phase
	_phase_frames = 0


func _phase_name(phase: int) -> String:
	match phase:
		Phase.WAIT_SPAWN:
			return "WAIT_SPAWN"
		Phase.WAIT_MOVE:
			return "WAIT_MOVE"
		Phase.PLACE_OBSTACLE:
			return "PLACE_OBSTACLE"
		Phase.WAIT_STOP:
			return "WAIT_STOP"
		Phase.REMOVE_OBSTACLE:
			return "REMOVE_OBSTACLE"
		Phase.WAIT_RESUME:
			return "WAIT_RESUME"
		_:
			return "UNKNOWN"


func _fail(message: String) -> void:
	if not _failures.has(message):
		_failures.append(message)
	for failure in _failures:
		print("TRAFFIC TEST FAIL: ", failure)
	quit(1)
