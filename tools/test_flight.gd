# Integration test: spawn the plane on a flat dev strip, take off,
# sustain flight, and verify throttle release descends without instability.
# Usage: godot --headless -s tools/test_flight.gd
extends SceneTree

const MAX_FRAMES := 1800
const TAKEOFF_TIMEOUT_FRAMES := 720
const SUSTAIN_FRAMES := 300
const DESCENT_FRAMES := 360
const MIN_TAKEOFF_ALTITUDE := 8.0
const MAX_POSITION_COMPONENT := 10000.0

enum Phase {
	WAIT_SETTLE,
	TAKEOFF,
	SUSTAIN,
	DESCEND,
}

var _frames := 0
var _phase := Phase.WAIT_SETTLE
var _phase_frames := 0
var _scene: Node3D
var _plane: RigidBody3D
var _start_y := 0.0
var _takeoff_y := 0.0
var _sustain_min_y := INF
var _sustain_start_y := 0.0
var _descent_start_y := 0.0
var _failures: Array[String] = []


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/vehicles/dev/plane_dev.tscn")
	_scene = scene.instantiate() as Node3D
	root.add_child(_scene)
	_plane = _scene.get_node("Plane") as RigidBody3D
	_plane.set("driven", true)


func _process(_delta: float) -> bool:
	_frames += 1
	_phase_frames += 1

	if not _position_is_finite(_plane.global_position):
		_fail("plane position became invalid: %s" % _plane.global_position)
		return true

	match _phase:
		Phase.WAIT_SETTLE:
			_wait_settle()
		Phase.TAKEOFF:
			_takeoff()
		Phase.SUSTAIN:
			_sustain()
		Phase.DESCEND:
			_descend()

	if _frames >= MAX_FRAMES:
		_fail("timed out in phase %s" % _phase_name(_phase))
		return true

	return false


func _wait_settle() -> void:
	if _phase_frames == 1:
		_start_y = _plane.global_position.y

	if _phase_frames >= 20:
		Input.action_press("move_forward")
		_set_phase(Phase.TAKEOFF)


func _takeoff() -> void:
	if _plane.global_position.y - _start_y > MIN_TAKEOFF_ALTITUDE:
		_takeoff_y = _plane.global_position.y
		_sustain_start_y = _plane.global_position.y
		_sustain_min_y = _plane.global_position.y
		_set_phase(Phase.SUSTAIN)
		return

	if _phase_frames > TAKEOFF_TIMEOUT_FRAMES:
		_fail("plane did not take off: gained %.2f m, moved %.2f m, speed %.2f m/s, driven=%s" % [
			_plane.global_position.y - _start_y,
			Vector2(_plane.global_position.x, _plane.global_position.z).length(),
			_plane.linear_velocity.length(),
			bool(_plane.get("driven")),
		])


func _sustain() -> void:
	_sustain_min_y = minf(_sustain_min_y, _plane.global_position.y)
	if _phase_frames < SUSTAIN_FRAMES:
		return

	var altitude_loss := _sustain_start_y - _sustain_min_y
	if altitude_loss > 5.0:
		_fail("plane failed sustained flight: lost %.2f m while throttled" % altitude_loss)
		return

	_descent_start_y = _plane.global_position.y
	Input.action_release("move_forward")
	Input.action_press("handbrake")
	_set_phase(Phase.DESCEND)


func _descend() -> void:
	if _phase_frames < DESCENT_FRAMES:
		return

	Input.action_release("handbrake")
	var descent := _descent_start_y - _plane.global_position.y
	if descent <= 1.0:
		_fail("plane did not descend after throttle release: descent %.2f m" % descent)
		return

	print("FLIGHT TEST PASS (takeoff %.2f m, sustained min %.2f m, descent %.2f m)" % [
		_takeoff_y - _start_y,
		_sustain_min_y - _start_y,
		descent,
	])
	quit(0)


func _position_is_finite(value: Vector3) -> bool:
	return (
		is_finite(value.x)
		and is_finite(value.y)
		and is_finite(value.z)
		and absf(value.x) < MAX_POSITION_COMPONENT
		and absf(value.y) < MAX_POSITION_COMPONENT
		and absf(value.z) < MAX_POSITION_COMPONENT
	)


func _set_phase(phase: int) -> void:
	_phase = phase
	_phase_frames = 0


func _phase_name(phase: int) -> String:
	match phase:
		Phase.WAIT_SETTLE:
			return "WAIT_SETTLE"
		Phase.TAKEOFF:
			return "TAKEOFF"
		Phase.SUSTAIN:
			return "SUSTAIN"
		Phase.DESCEND:
			return "DESCEND"
		_:
			return "UNKNOWN"


func _fail(message: String) -> void:
	Input.action_release("move_forward")
	Input.action_release("handbrake")
	_failures.append(message)
	for failure in _failures:
		print("FLIGHT TEST FAIL: ", failure)
	quit(1)
