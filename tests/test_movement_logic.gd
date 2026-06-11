extends RefCounted

const MovementLogic = preload("res://scripts/player/movement_logic.gd")

var failures: Array = []


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _step(logic: MovementLogic, velocity: Vector3, direction: Vector3, sprinting: bool,
		on_floor: bool, jump_pressed: bool, delta := 1.0 / 60.0) -> Dictionary:
	return logic.step_velocity(
		velocity, direction, sprinting, on_floor, jump_pressed, delta,
		4.5, 7.5, 30.0, 40.0, 0.3, 1.5, 9.8, 0.12, 0.12
	)


func test_jump_velocity_reaches_height() -> void:
	var v := MovementLogic.calculate_jump_velocity(1.5, 9.8)
	var apex := v * v / (2.0 * 9.8)
	check(absf(apex - 1.5) < 0.001, "apex %f != 1.5" % apex)


func test_accelerates_toward_walk_speed() -> void:
	var logic := MovementLogic.new()
	var velocity := Vector3.ZERO
	for i in 120:
		velocity = _step(logic, velocity, Vector3.FORWARD, false, true, false)["velocity"]
	var speed := Vector2(velocity.x, velocity.z).length()
	check(absf(speed - 4.5) < 0.01, "walk speed %f != 4.5" % speed)


func test_sprint_reaches_sprint_speed() -> void:
	var logic := MovementLogic.new()
	var velocity := Vector3.ZERO
	for i in 180:
		velocity = _step(logic, velocity, Vector3.FORWARD, true, true, false)["velocity"]
	var speed := Vector2(velocity.x, velocity.z).length()
	check(absf(speed - 7.5) < 0.01, "sprint speed %f != 7.5" % speed)


func test_decelerates_to_zero_without_input() -> void:
	var logic := MovementLogic.new()
	var velocity := Vector3(0, 0, -4.5)
	for i in 30:
		velocity = _step(logic, velocity, Vector3.ZERO, false, true, false)["velocity"]
	check(Vector2(velocity.x, velocity.z).length() < 0.01,
		"velocity not zeroed: %s" % velocity)


func test_coyote_jump_within_window() -> void:
	var logic := MovementLogic.new()
	# One grounded frame primes the coyote timer.
	_step(logic, Vector3.ZERO, Vector3.ZERO, false, true, false)
	# Airborne for 4 frames (~0.067s) — still inside the 0.12s window.
	for i in 4:
		_step(logic, Vector3.ZERO, Vector3.ZERO, false, false, false)
	var result := _step(logic, Vector3.ZERO, Vector3.ZERO, false, false, true)
	check(result["jumped"], "coyote jump did not fire inside window")


func test_no_coyote_jump_after_window() -> void:
	var logic := MovementLogic.new()
	_step(logic, Vector3.ZERO, Vector3.ZERO, false, true, false)
	# Airborne for 10 frames (~0.167s) — past the 0.12s window.
	for i in 10:
		_step(logic, Vector3.ZERO, Vector3.ZERO, false, false, false)
	var result := _step(logic, Vector3.ZERO, Vector3.ZERO, false, false, true)
	check(not result["jumped"], "coyote jump fired after window expired")


func test_jump_buffer_fires_on_landing() -> void:
	var logic := MovementLogic.new()
	# Press jump while airborne; land 3 frames later — buffer should fire.
	_step(logic, Vector3(0, -3, 0), Vector3.ZERO, false, false, true)
	var result: Dictionary
	for i in 3:
		result = _step(logic, Vector3(0, -3, 0), Vector3.ZERO, false, false, false)
	result = _step(logic, Vector3(0, -3, 0), Vector3.ZERO, false, true, false)
	check(result["jumped"], "buffered jump did not fire on landing")


func test_gravity_applies_in_air() -> void:
	var logic := MovementLogic.new()
	var delta := 1.0 / 60.0
	var result := _step(logic, Vector3.ZERO, Vector3.ZERO, false, false, false, delta)
	var vy: float = result["velocity"].y
	check(absf(vy - (-9.8 * delta)) < 0.0001, "gravity not applied: vy=%f" % vy)


func test_air_control_is_reduced() -> void:
	var ground := MovementLogic.calculate_horizontal_velocity(
		Vector3.ZERO, Vector3.FORWARD, 4.5, 30.0, 40.0, 0.3, true, 1.0 / 60.0)
	var air := MovementLogic.calculate_horizontal_velocity(
		Vector3.ZERO, Vector3.FORWARD, 4.5, 30.0, 40.0, 0.3, false, 1.0 / 60.0)
	check(air.length() < ground.length(), "air accel not reduced")
	check(air.length() > 0.0, "no air control at all")
