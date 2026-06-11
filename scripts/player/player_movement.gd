extends CharacterBody3D

const MovementLogic = preload("res://scripts/player/movement_logic.gd")

@export var walk_speed: float = 4.5
@export var sprint_speed: float = 7.5
@export var ground_acceleration: float = 30.0
@export var ground_deceleration: float = 40.0
@export var air_control_factor: float = 0.3
@export var jump_height: float = 1.5
@export var coyote_time: float = 0.12
@export var jump_buffer_time: float = 0.12
@export var visual_rotation_speed: float = 10.0
@export var climb_speed: float = 3.0
@export var climb_strafe_speed: float = 1.5
@export var mantle_up_velocity: float = 3.2
@export var mantle_forward_velocity: float = 2.4

var _camera_yaw_source: Node3D
var _gravity: float = 9.8
var _logic := MovementLogic.new()
var _climbing: bool = false
var _climb_facing: Vector3 = Vector3.FORWARD
var _mantle_timer: float = 0.0

@onready var _ladder_sensor: Area3D = get_node_or_null("LadderSensor") as Area3D


func _ready() -> void:
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity"))


func set_camera_yaw_source(source: Node3D) -> void:
	_camera_yaw_source = source


func get_horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func _physics_process(delta: float) -> void:
	var move_input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var desired_direction := _get_camera_relative_direction(move_input)
	if _update_climbing(desired_direction, delta):
		return
	var movement := _logic.step_velocity(
		velocity,
		desired_direction,
		Input.is_action_pressed("sprint"),
		is_on_floor(),
		Input.is_action_just_pressed("jump"),
		delta,
		walk_speed,
		sprint_speed,
		ground_acceleration,
		ground_deceleration,
		air_control_factor,
		jump_height,
		_gravity,
		coyote_time,
		jump_buffer_time
	)

	velocity = movement["velocity"]
	move_and_slide()
	_rotate_toward_horizontal_velocity(delta)


func _in_ladder_zone() -> bool:
	if _ladder_sensor == null:
		return false
	for area in _ladder_sensor.get_overlapping_areas():
		if area.is_in_group("ladder"):
			return true
	return false


func _update_climbing(desired_direction: Vector3, delta: float) -> bool:
	var in_zone := _in_ladder_zone()
	var input_strength := desired_direction.length()

	# Mantle mode: carry up and over the ledge after topping out.
	if _mantle_timer > 0.0:
		_mantle_timer -= delta
		velocity = Vector3.UP * mantle_up_velocity + _climb_facing * mantle_forward_velocity
		move_and_slide()
		if is_on_floor():
			_mantle_timer = 0.0
		return true

	if not _climbing:
		# Grab when pushing into the ladder wall: there is input, but the
		# wall has stopped us (works from any approach/camera angle, and
		# also catches falling past a ladder while steering into it).
		var blocked := get_horizontal_speed() < 0.6
		if in_zone and input_strength > 0.3 and blocked:
			_climbing = true
			_climb_facing = desired_direction.normalized()
			_climb_facing.y = 0.0
			_climb_facing = _climb_facing.normalized()
		else:
			return false

	# Jump releases the ladder with a push away from the wall.
	if Input.is_action_just_pressed("jump"):
		_climbing = false
		velocity = -_climb_facing * 3.0 + Vector3.UP * MovementLogic.calculate_jump_velocity(jump_height, _gravity) * 0.8
		move_and_slide()
		return true

	# Pushing toward the wall climbs up; pushing away climbs down.
	var climb_axis := 0.0
	if input_strength > 0.1:
		climb_axis = desired_direction.normalized().dot(_climb_facing)

	# Climbed out the top of the zone while ascending: mantle onto the ledge.
	if not in_zone:
		_climbing = false
		if climb_axis > 0.2:
			_mantle_timer = 0.45
			velocity = Vector3.UP * mantle_up_velocity + _climb_facing * mantle_forward_velocity
			move_and_slide()
			return true
		return false

	# Reached the ground while descending or steering away: let go.
	if is_on_floor() and climb_axis < -0.2:
		_climbing = false
		return false

	var vertical := climb_axis * climb_speed
	var strafe := desired_direction - _climb_facing * desired_direction.dot(_climb_facing)
	velocity = strafe * climb_strafe_speed + Vector3(0, vertical, 0)
	move_and_slide()
	return true


func _get_camera_relative_direction(move_input: Vector2) -> Vector3:
	if move_input.length_squared() <= 0.0001:
		return Vector3.ZERO

	var camera_yaw := 0.0
	if is_instance_valid(_camera_yaw_source):
		camera_yaw = _camera_yaw_source.global_rotation.y

	var local_direction := Vector3(move_input.x, 0.0, move_input.y)
	return Basis(Vector3.UP, camera_yaw) * local_direction


func _rotate_toward_horizontal_velocity(delta: float) -> void:
	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	if horizontal_velocity.length_squared() <= 0.01:
		return

	var target_yaw := atan2(-horizontal_velocity.x, -horizontal_velocity.z)
	rotation.y = lerp_angle(
		rotation.y,
		target_yaw,
		clampf(visual_rotation_speed * delta, 0.0, 1.0)
	)
