extends Node3D

@export var mouse_sensitivity_degrees: float = 0.08
@export var gamepad_look_degrees_per_second: float = 180.0
@export var min_pitch_degrees: float = -75.0
@export var max_pitch_degrees: float = 70.0
@export var base_fov: float = 75.0
@export var sprint_fov: float = 82.0
@export var fov_lerp_speed: float = 8.0
@export var fov_walk_speed: float = 4.5
@export var fov_sprint_speed: float = 7.5

@onready var pitch: Node3D = $Pitch
@onready var spring_arm: SpringArm3D = $Pitch/SpringArm3D
@onready var camera: Camera3D = $Pitch/SpringArm3D/Camera3D

var _yaw_degrees: float = 0.0
var _pitch_degrees: float = 0.0
var _speed_source: CharacterBody3D


func _ready() -> void:
	_yaw_degrees = rotation_degrees.y
	_pitch_degrees = pitch.rotation_degrees.x
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	camera.fov = base_fov
	_apply_rotation()


func set_speed_source(source: CharacterBody3D) -> void:
	_speed_source = source


func exclude_collision(rid: RID) -> void:
	spring_arm.add_excluded_object(rid)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE:
			_toggle_mouse_capture()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mouse_event := event as InputEventMouseMotion
		_yaw_degrees -= mouse_event.relative.x * mouse_sensitivity_degrees
		_pitch_degrees = clampf(
			_pitch_degrees - mouse_event.relative.y * mouse_sensitivity_degrees,
			min_pitch_degrees,
			max_pitch_degrees
		)
		_apply_rotation()


func _process(delta: float) -> void:
	_apply_gamepad_look(delta)
	_update_sprint_fov(delta)


func _apply_gamepad_look(delta: float) -> void:
	var look_x := Input.get_action_strength("camera_right") - Input.get_action_strength("camera_left")
	var look_y := Input.get_action_strength("camera_down") - Input.get_action_strength("camera_up")
	if absf(look_x) <= 0.001 and absf(look_y) <= 0.001:
		return

	_yaw_degrees -= look_x * gamepad_look_degrees_per_second * delta
	_pitch_degrees = clampf(
		_pitch_degrees - look_y * gamepad_look_degrees_per_second * delta,
		min_pitch_degrees,
		max_pitch_degrees
	)
	_apply_rotation()


func _update_sprint_fov(delta: float) -> void:
	var horizontal_speed := 0.0
	if is_instance_valid(_speed_source):
		horizontal_speed = Vector2(_speed_source.velocity.x, _speed_source.velocity.z).length()

	var sprint_amount := 0.0
	if fov_sprint_speed > fov_walk_speed:
		sprint_amount = clampf(
			(horizontal_speed - fov_walk_speed) / (fov_sprint_speed - fov_walk_speed),
			0.0,
			1.0
		)

	var target_fov := lerpf(base_fov, sprint_fov, sprint_amount)
	var blend := clampf(1.0 - exp(-fov_lerp_speed * delta), 0.0, 1.0)
	camera.fov = lerpf(camera.fov, target_fov, blend)


func _toggle_mouse_capture() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _apply_rotation() -> void:
	rotation_degrees.y = _yaw_degrees
	pitch.rotation_degrees.x = _pitch_degrees
