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

var _camera_yaw_source: Node3D
var _gravity: float = 9.8
var _logic := MovementLogic.new()


func _ready() -> void:
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity"))


func set_camera_yaw_source(source: Node3D) -> void:
	_camera_yaw_source = source


func get_horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func _physics_process(delta: float) -> void:
	var move_input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var desired_direction := _get_camera_relative_direction(move_input)
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
