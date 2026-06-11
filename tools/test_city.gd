# Integration test: load the streaming city, land the player on tile_2_0,
# enter the car, drive across a tile boundary, and verify streaming follows.
# Usage: godot --headless -s tools/test_city.gd
# Poll-based: under headless -s, frame time is uncapped and threaded loads
# complete asynchronously, so assertions wait for observable streamer state.
extends SceneTree

const MAX_FRAMES := 3200
const START_TILE := Vector2i(2, 0)

enum Phase {
	WAIT_START_TILE,
	WAIT_PLAYER_FLOOR,
	TELEPORT_TO_CAR,
	ENTER_CAR,
	DRIVE_TO_NEXT_TILE,
	WAIT_STREAMING_AFTER_DRIVE,
}

var _frames := 0
var _phase := Phase.WAIT_START_TILE
var _phase_frames := 0
var _city: Node3D
var _streamer: Node
var _player: Node3D
var _body: CharacterBody3D
var _spawn: Node3D
var _car_spawn: Node3D
var _car: VehicleBody3D
var _car_start := Vector3.ZERO
var _crossed_tile := Vector2i.ZERO
var _failures: Array[String] = []
var _cleanup_started := false
var _cleanup_frames := 0
var _cleanup_exit_code := 0


func _initialize() -> void:
	_ensure_events_bus()
	var scene: PackedScene = load("res://scenes/city/city.tscn")
	_city = scene.instantiate() as Node3D
	_streamer = _city.get_node("WorldStreamer")
	_streamer.set("load_radius_tiles", 0)
	_streamer.set("unload_radius_tiles", 0)
	root.add_child(_city)

	_player = _city.get_node("Player") as Node3D
	_body = _player.get_node("Body") as CharacterBody3D
	_spawn = _city.get_node("PlayerSpawn") as Node3D
	_car_spawn = _city.get_node("CarSpawn") as Node3D
	_car = _city.get_node("Car") as VehicleBody3D


func _process(_delta: float) -> bool:
	_frames += 1
	_phase_frames += 1

	if _cleanup_started:
		_cleanup_frames += 1
		if _cleanup_frames >= 20:
			quit(_cleanup_exit_code)
			return true
		return false

	match _phase:
		Phase.WAIT_START_TILE:
			_wait_for_start_tile()
		Phase.WAIT_PLAYER_FLOOR:
			_wait_for_player_floor()
		Phase.TELEPORT_TO_CAR:
			_place_player_near_car()
			_set_phase(Phase.ENTER_CAR)
		Phase.ENTER_CAR:
			_enter_car()
		Phase.DRIVE_TO_NEXT_TILE:
			_drive_to_next_tile()
		Phase.WAIT_STREAMING_AFTER_DRIVE:
			_wait_for_streaming_after_drive()

	if _frames >= MAX_FRAMES:
		_begin_cleanup(["timed out in phase %s after %d frames" % [_phase_name(_phase), MAX_FRAMES]], 1)
		return true

	return false


func _wait_for_start_tile() -> void:
	if not _is_tile_resident(START_TILE):
		return

	_place_player_at_spawn()
	_set_phase(Phase.WAIT_PLAYER_FLOOR)


func _wait_for_player_floor() -> void:
	if not _body.is_on_floor():
		return

	var player_tile := _tile_of(_body.global_position)
	_check(player_tile == START_TILE, "player landed on %s instead of tile_2_0" % player_tile)
	if not _failures.is_empty():
		_begin_cleanup(_failures, 1)
		return

	_set_phase(Phase.TELEPORT_TO_CAR)


func _enter_car() -> void:
	if _phase_frames == 12:
		Input.action_press("interact")
	elif _phase_frames == 14:
		Input.action_release("interact")

	if _phase_frames > 20 and bool(_car.get("driven")):
		_check(
			bool(_streamer.call("is_following_target", _car)),
			"streamer did not retarget to car through vehicle_entered event"
		)
		if not _failures.is_empty():
			_begin_cleanup(_failures, 1)
			return

		_car_start = _car.global_position
		Input.action_press("move_forward")
		_set_phase(Phase.DRIVE_TO_NEXT_TILE)
		return

	if _phase_frames > 140:
		_begin_cleanup(["car did not enter driven state after interact"], 1)


func _drive_to_next_tile() -> void:
	var car_tile := _tile_of(_car.global_position)
	if car_tile != START_TILE:
		_crossed_tile = car_tile
		Input.action_release("move_forward")
		Input.action_press("handbrake")
		_car.linear_velocity = Vector3.ZERO
		_car.angular_velocity = Vector3.ZERO
		_car.sleeping = true
		_set_phase(Phase.WAIT_STREAMING_AFTER_DRIVE)
		return

	if _phase_frames > 1600:
		var distance := (_car.global_position - _car_start).length()
		_begin_cleanup(["car did not cross a tile boundary after driving %.2f m" % distance], 1)


func _wait_for_streaming_after_drive() -> void:
	var crossed_loaded := _is_tile_resident(_crossed_tile)
	var start_unloaded := not _is_tile_resident(START_TILE)
	if crossed_loaded and start_unloaded:
		Input.action_release("handbrake")
		print("CITY TEST PASS (player landed on tile_2_0, car crossed into %s, old tile unloaded)" % _crossed_tile)
		_begin_cleanup([], 0)
		return

	if _phase_frames > 900:
		_begin_cleanup([
			"streaming did not settle after car crossed into %s (loaded=%s start_unloaded=%s)" % [
				_crossed_tile,
				crossed_loaded,
				start_unloaded,
			],
		], 1)


func _place_player_at_spawn() -> void:
	_player.global_position = _spawn.global_position
	_body.global_position = _spawn.global_position
	_body.velocity = Vector3.ZERO


func _place_player_near_car() -> void:
	_car.global_position = _car_spawn.global_position
	_car.global_rotation = _car_spawn.global_rotation
	_car.linear_velocity = Vector3.ZERO
	_car.angular_velocity = Vector3.ZERO
	_car.sleeping = false

	var side_offset := _car.global_transform.basis.x.normalized() * 2.4
	var target_position := _car.global_position + side_offset + Vector3.UP * 0.4
	_player.global_position = target_position
	_body.global_position = target_position
	_body.velocity = Vector3.ZERO


func _ensure_events_bus() -> void:
	if root.get_node_or_null("Events") != null:
		return

	# Some -s runs do not instantiate autoloads; install the same event bus so
	# vehicle enter still verifies the signal-driven streamer retarget path.
	var events_script := load("res://scripts/core/events.gd") as Script
	var events := Node.new()
	events.name = "Events"
	events.set_script(events_script)
	root.add_child(events)


func _tile_of(world_position: Vector3) -> Vector2i:
	return _streamer.call("world_to_tile_coord", world_position) as Vector2i


func _is_tile_resident(coord: Vector2i) -> bool:
	return bool(_streamer.call("is_tile_resident", coord))


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures.append(msg)


func _set_phase(phase: int) -> void:
	_phase = phase
	_phase_frames = 0


func _phase_name(phase: int) -> String:
	match phase:
		Phase.WAIT_START_TILE:
			return "WAIT_START_TILE"
		Phase.WAIT_PLAYER_FLOOR:
			return "WAIT_PLAYER_FLOOR"
		Phase.TELEPORT_TO_CAR:
			return "TELEPORT_TO_CAR"
		Phase.ENTER_CAR:
			return "ENTER_CAR"
		Phase.DRIVE_TO_NEXT_TILE:
			return "DRIVE_TO_NEXT_TILE"
		Phase.WAIT_STREAMING_AFTER_DRIVE:
			return "WAIT_STREAMING_AFTER_DRIVE"
		_:
			return "UNKNOWN"


func _begin_cleanup(failures: Array[String], exit_code: int) -> void:
	if _cleanup_started:
		return

	Input.action_release("interact")
	Input.action_release("move_forward")
	Input.action_release("handbrake")

	for failure in failures:
		print("CITY TEST FAIL: ", failure)

	_cleanup_started = true
	_cleanup_exit_code = exit_code
	if is_instance_valid(_city):
		_city.queue_free()
