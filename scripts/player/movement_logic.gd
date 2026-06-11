class_name PlayerMovementLogic
extends RefCounted

const HORIZONTAL_EPSILON := 0.001

var coyote_timer: float = 0.0
var jump_buffer_timer: float = 0.0


func step_velocity(
	current_velocity: Vector3,
	desired_direction: Vector3,
	sprinting: bool,
	on_floor: bool,
	jump_pressed: bool,
	delta: float,
	walk_speed: float,
	sprint_speed: float,
	ground_acceleration: float,
	ground_deceleration: float,
	air_control_factor: float,
	jump_height: float,
	gravity: float,
	coyote_time: float,
	jump_buffer_time: float
) -> Dictionary:
	var jump_state := update_jump_timers(
		delta,
		on_floor,
		jump_pressed,
		coyote_time,
		jump_buffer_time
	)
	var target_speed := sprint_speed if sprinting else walk_speed
	var next_velocity := calculate_horizontal_velocity(
		current_velocity,
		desired_direction,
		target_speed,
		ground_acceleration,
		ground_deceleration,
		air_control_factor,
		on_floor,
		delta
	)

	next_velocity.y = calculate_vertical_velocity(
		current_velocity.y,
		on_floor,
		jump_state["should_jump"],
		jump_height,
		gravity,
		delta
	)

	return {
		"velocity": next_velocity,
		"jumped": jump_state["should_jump"],
		"coyote_timer": coyote_timer,
		"jump_buffer_timer": jump_buffer_timer,
	}


func update_jump_timers(
	delta: float,
	on_floor: bool,
	jump_pressed: bool,
	coyote_time: float,
	jump_buffer_time: float
) -> Dictionary:
	if on_floor:
		coyote_timer = coyote_time
	else:
		coyote_timer = maxf(coyote_timer - delta, 0.0)

	if jump_pressed:
		jump_buffer_timer = jump_buffer_time
	else:
		jump_buffer_timer = maxf(jump_buffer_timer - delta, 0.0)

	var should_jump := coyote_timer > 0.0 and jump_buffer_timer > 0.0
	if should_jump:
		coyote_timer = 0.0
		jump_buffer_timer = 0.0

	return {
		"should_jump": should_jump,
		"coyote_timer": coyote_timer,
		"jump_buffer_timer": jump_buffer_timer,
	}


static func calculate_horizontal_velocity(
	current_velocity: Vector3,
	desired_direction: Vector3,
	target_speed: float,
	ground_acceleration: float,
	ground_deceleration: float,
	air_control_factor: float,
	on_floor: bool,
	delta: float
) -> Vector3:
	var current_horizontal := Vector3(current_velocity.x, 0.0, current_velocity.z)
	var normalized_direction := normalized_horizontal_direction(desired_direction)
	var desired_velocity := normalized_direction * target_speed
	var next_horizontal := current_horizontal

	if on_floor:
		if normalized_direction.length_squared() > HORIZONTAL_EPSILON:
			next_horizontal = current_horizontal.move_toward(
				desired_velocity,
				ground_acceleration * delta
			)
		else:
			next_horizontal = current_horizontal.move_toward(
				Vector3.ZERO,
				ground_deceleration * delta
			)
	elif normalized_direction.length_squared() > HORIZONTAL_EPSILON:
		next_horizontal = current_horizontal.move_toward(
			desired_velocity,
			ground_acceleration * air_control_factor * delta
		)

	return Vector3(next_horizontal.x, current_velocity.y, next_horizontal.z)


static func calculate_vertical_velocity(
	current_y_velocity: float,
	on_floor: bool,
	should_jump: bool,
	jump_height: float,
	gravity: float,
	delta: float
) -> float:
	if should_jump:
		return calculate_jump_velocity(jump_height, gravity)

	if on_floor and current_y_velocity < 0.0:
		return 0.0

	if not on_floor:
		return current_y_velocity - gravity * delta

	return current_y_velocity


static func calculate_jump_velocity(jump_height: float, gravity: float) -> float:
	return sqrt(2.0 * gravity * jump_height)


static func normalized_horizontal_direction(direction: Vector3) -> Vector3:
	var horizontal := Vector3(direction.x, 0.0, direction.z)
	var length_squared := horizontal.length_squared()
	if length_squared <= HORIZONTAL_EPSILON:
		return Vector3.ZERO
	if length_squared > 1.0:
		return horizontal / sqrt(length_squared)
	return horizontal
