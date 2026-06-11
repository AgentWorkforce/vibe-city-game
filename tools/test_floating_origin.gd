# Integration test: verify streaming, save/load coordinate conversion, and
# cached local systems across multiple floating-origin shifts.
# Usage: godot --headless -s tools/test_floating_origin.gd
extends SceneTree

const EventsScript = preload("res://scripts/core/events.gd")
const SaveSystemScript = preload("res://scripts/core/save_system.gd")
const FloatingOriginScript = preload("res://scripts/world/floating_origin.gd")
const SaveSnapshot = preload("res://scripts/core/save_snapshot.gd")

const MAX_FRAMES := 2600
const START_TRUE := Vector3(320.0, 1.0, 64.0)
const FINAL_TRUE := Vector3(742.0, 1.0, 64.0)
const STEP_TRUE_DELTA := 211.0
const SHIFT_THRESHOLD := 180.0
const EXPECTED_FINAL_TILE := Vector2i(5, 0)
const SAVE_PATH := "user://floating_origin_test.json"

enum Phase {
	WAIT_INITIAL_SHIFT,
	WALK_STEPS,
	WAIT_STREAMING,
	ASSERT_SAVE,
}

var _frames := 0
var _phase := Phase.WAIT_INITIAL_SHIFT
var _phase_frames := 0
var _city: Node3D
var _origin
var _streamer: Node
var _player: Node3D
var _body: CharacterBody3D
var _saves: SaveSystem
var _true_target := START_TRUE
var _next_step_true_x := START_TRUE.x + STEP_TRUE_DELTA
var _step_start_shift_count := 0
var _shift_signal_count := 0
var _min_local_x_after_shift := INF
var _max_true_error := 0.0
var _max_velocity := 0.0
var _failures: Array[String] = []
var _cleanup_started := false
var _cleanup_frames := 0
var _cleanup_exit_code := 0


func _initialize() -> void:
	_install_events()
	_install_saves()

	var scene := load("res://scenes/city/city.tscn") as PackedScene
	_city = scene.instantiate() as Node3D
	_streamer = _city.get_node("WorldStreamer")
	_streamer.set("load_radius_tiles", 0)
	_streamer.set("unload_radius_tiles", 0)

	_origin = _city.get_node_or_null("FloatingOrigin")
	if _origin == null:
		_origin = FloatingOriginScript.new()
		_origin.name = "FloatingOrigin"
		_city.add_child(_origin)

	_origin.threshold_meters = SHIFT_THRESHOLD
	_origin.streamer_path = NodePath("../WorldStreamer")
	_origin.target_path = NodePath("../Player/Body")
	_origin.world_root_path = NodePath("..")

	root.add_child(_city)
	current_scene = _city

	_player = _city.get_node("Player") as Node3D
	_body = _player.get_node("Body") as CharacterBody3D


func _process(_delta: float) -> bool:
	_frames += 1
	_phase_frames += 1

	if _cleanup_started:
		_cleanup_frames += 1
		if _cleanup_frames >= 20:
			quit(_cleanup_exit_code)
			return true
		return false

	_record_velocity_bounds()
	_record_true_error()

	match _phase:
		Phase.WAIT_INITIAL_SHIFT:
			_wait_initial_shift()
		Phase.WALK_STEPS:
			_walk_steps()
		Phase.WAIT_STREAMING:
			_wait_streaming()
		Phase.ASSERT_SAVE:
			_assert_save()

	if _frames >= MAX_FRAMES:
		_begin_cleanup(["timed out in phase %s after %d frames" % [_phase_name(_phase), MAX_FRAMES]], 1)
		return true

	return false


func _install_events() -> void:
	var events := root.get_node_or_null("Events")
	if events == null:
		events = EventsScript.new()
		events.name = "Events"
		root.add_child(events)

	var shifted_callable := Callable(self, "_on_origin_shifted")
	if not events.is_connected(&"origin_shifted", shifted_callable):
		events.connect(&"origin_shifted", shifted_callable)


func _install_saves() -> void:
	_saves = root.get_node_or_null("Saves") as SaveSystem
	if _saves == null:
		_saves = SaveSystemScript.new()
		_saves.name = "Saves"
		root.add_child(_saves)
	_saves.save_path = SAVE_PATH


func _wait_initial_shift() -> void:
	_place_player_at_true(START_TRUE)
	if _origin.get_shift_count() <= 0:
		return

	_check(_origin.get_world_offset().distance_to(Vector3(320.0, 0.0, 64.0)) < 1.0, "initial true offset was not recorded correctly")
	_step_start_shift_count = int(_origin.get_shift_count())
	_next_step_true_x = START_TRUE.x + STEP_TRUE_DELTA
	_set_phase(Phase.WALK_STEPS)


func _walk_steps() -> void:
	if _next_step_true_x > FINAL_TRUE.x + 0.01:
		_true_target = FINAL_TRUE
		_place_player_at_true(_true_target)
		_set_phase(Phase.WAIT_STREAMING)
		return

	_true_target = Vector3(_next_step_true_x, START_TRUE.y, START_TRUE.z)
	_place_player_at_true(_true_target)

	if int(_origin.get_shift_count()) > _step_start_shift_count:
		_step_start_shift_count = int(_origin.get_shift_count())
		_next_step_true_x += STEP_TRUE_DELTA
		return

	if _phase_frames > 600 and _origin.get_shift_count() < 3:
		_begin_cleanup(["floating origin produced only %d shifts during logical travel" % _origin.get_shift_count()], 1)


func _wait_streaming() -> void:
	_place_player_at_true(FINAL_TRUE)
	var true_position: Vector3 = _origin.call("to_world", _body.global_position) as Vector3
	var expected_tile := _streamer.call("true_world_to_tile_coord", true_position) as Vector2i
	var expected_loaded := bool(_streamer.call("is_tile_resident", EXPECTED_FINAL_TILE))
	var only_expected := _resident_tiles_are_current(EXPECTED_FINAL_TILE)
	if expected_tile == EXPECTED_FINAL_TILE and expected_loaded and only_expected:
		_set_phase(Phase.ASSERT_SAVE)
		return

	if _phase_frames > 900:
		_begin_cleanup([
			"streaming did not settle at true tile %s (expected_loaded=%s only_expected=%s resident=%s)" % [
				EXPECTED_FINAL_TILE,
				expected_loaded,
				only_expected,
				_streamer.call("get_resident_tile_coords"),
			],
		], 1)


func _assert_save() -> void:
	_place_player_at_true(FINAL_TRUE)

	_check(_shift_signal_count >= 3, "origin_shifted signal fired only %d times" % _shift_signal_count)
	_check(_origin.get_shift_count() >= 3, "origin shifted only %d times" % _origin.get_shift_count())
	_check(_min_local_x_after_shift < SHIFT_THRESHOLD * 0.35, "player local position never snapped back after shift (min local x %.2f)" % _min_local_x_after_shift)
	_check(_max_true_error < 1.0, "true world position drifted from logical travel by %.2f m" % _max_true_error)
	_check(_max_velocity < 120.0, "physics velocity exceeded bound after shifts (%.2f m/s)" % _max_velocity)
	_check((_streamer.call("true_world_to_tile_coord", FINAL_TRUE) as Vector2i) == EXPECTED_FINAL_TILE, "expected final true tile math is wrong")

	if not _saves.save():
		_record_failure("save() returned false")
	else:
		var snapshot := _saves.read_snapshot()
		var player_state := snapshot.get("player", {}) as Dictionary
		var saved_position := SaveSnapshot.vector3_from_data(player_state.get("global_position", Vector3.ZERO))
		_check(saved_position.distance_to(FINAL_TRUE) < 1.0, "save captured %s instead of true world position %s" % [saved_position, FINAL_TRUE])

	if _failures.is_empty():
		print("FLOATING ORIGIN TEST PASS (%d shifts, true %.1f, local %.1f, tile %s, max_velocity %.2f)" % [
			_origin.get_shift_count(),
		(_origin.call("to_world", _body.global_position) as Vector3).x,
			_body.global_position.x,
			EXPECTED_FINAL_TILE,
			_max_velocity,
		])
		_begin_cleanup([], 0)
	else:
		_begin_cleanup(_failures, 1)


func _place_player_at_true(true_position: Vector3) -> void:
	var local_position: Vector3 = _origin.call("to_local_world", true_position) as Vector3
	_player.global_position = local_position
	_body.global_position = local_position
	_body.velocity = Vector3.ZERO
	if _body.has_method("reset_physics_interpolation"):
		_body.call("reset_physics_interpolation")


func _record_true_error() -> void:
	if _origin == null or _body == null:
		return
	var true_position: Vector3 = _origin.call("to_world", _body.global_position) as Vector3
	_max_true_error = maxf(_max_true_error, true_position.distance_to(_true_target))


func _record_velocity_bounds() -> void:
	for node in root.find_children("*", "Node", true, false):
		var character := node as CharacterBody3D
		if character != null:
			_max_velocity = maxf(_max_velocity, character.velocity.length())
			continue

		var rigid := node as RigidBody3D
		if rigid != null:
			_max_velocity = maxf(_max_velocity, rigid.linear_velocity.length())


func _on_origin_shifted(_offset: Vector3) -> void:
	_shift_signal_count += 1
	if is_instance_valid(_body):
		_min_local_x_after_shift = minf(_min_local_x_after_shift, absf(_body.global_position.x))


func _resident_tiles_are_current(expected: Vector2i) -> bool:
	var coords := _streamer.call("get_resident_tile_coords") as Array
	if coords.size() != 1:
		return false
	return (coords[0] as Vector2i) == expected


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_record_failure(msg)


func _record_failure(msg: String) -> void:
	if not _failures.has(msg):
		_failures.append(msg)


func _set_phase(phase: int) -> void:
	_phase = phase
	_phase_frames = 0


func _phase_name(phase: int) -> String:
	match phase:
		Phase.WAIT_INITIAL_SHIFT:
			return "WAIT_INITIAL_SHIFT"
		Phase.WALK_STEPS:
			return "WALK_STEPS"
		Phase.WAIT_STREAMING:
			return "WAIT_STREAMING"
		Phase.ASSERT_SAVE:
			return "ASSERT_SAVE"
		_:
			return "UNKNOWN"


func _begin_cleanup(failures: Array[String], exit_code: int) -> void:
	if _cleanup_started:
		return

	for failure in failures:
		print("FLOATING ORIGIN TEST FAIL: ", failure)

	_cleanup_started = true
	_cleanup_exit_code = exit_code
	current_scene = null
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	if is_instance_valid(_city):
		_city.queue_free()
