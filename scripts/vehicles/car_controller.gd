extends VehicleBody3D

@export var driven: bool = false
@export var max_engine_force: float = 900.0
@export var max_reverse_force: float = 520.0
@export var max_forward_speed_mps: float = 42.0
@export var max_reverse_speed_mps: float = 12.0
@export var engine_taper_floor: float = 0.12
@export var brake_force: float = 28.0
@export var handbrake_force: float = 70.0
@export var idle_brake_force: float = 2.0
@export var brake_before_reverse_speed: float = 1.2
@export var steering_standstill_degrees: float = 35.0
@export var steering_top_speed_degrees: float = 12.0
@export var steering_lerp_speed: float = 8.0
@export var top_speed_for_steering_mps: float = 34.0
@export var rear_friction_slip: float = 4.6
@export var front_friction_slip: float = 5.0
@export var handbrake_rear_friction_scale: float = 0.42
@export var custom_center_of_mass: Vector3 = Vector3(0.0, -0.45, -0.22)

@onready var _front_left: VehicleWheel3D = get_node_or_null("WheelFrontLeft") as VehicleWheel3D
@onready var _front_right: VehicleWheel3D = get_node_or_null("WheelFrontRight") as VehicleWheel3D
@onready var _rear_left: VehicleWheel3D = get_node_or_null("WheelRearLeft") as VehicleWheel3D
@onready var _rear_right: VehicleWheel3D = get_node_or_null("WheelRearRight") as VehicleWheel3D
@onready var _chase_camera: Node = get_node_or_null("CameraRig")

var _front_wheels: Array[VehicleWheel3D] = []
var _rear_wheels: Array[VehicleWheel3D] = []
var _all_wheels: Array[VehicleWheel3D] = []
var _current_steering: float = 0.0


func _ready() -> void:
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = custom_center_of_mass
	_collect_wheels()
	_apply_normal_friction()


func _physics_process(delta: float) -> void:
	if driven:
		sleeping = false
		_apply_driver_input(delta)
	else:
		release_controls(delta)


func set_camera_active(active: bool) -> void:
	if not is_instance_valid(_chase_camera) or not _chase_camera.has_method("set_camera_active"):
		return

	_chase_camera.call("set_camera_active", active)


func release_controls(delta: float = 0.0) -> void:
	_current_steering = _lerp_scalar(_current_steering, 0.0, steering_lerp_speed, delta)
	_set_front_steering(_current_steering)
	_set_rear_engine_force(0.0)
	_set_wheel_brakes(idle_brake_force, idle_brake_force)
	_apply_normal_friction()


func _collect_wheels() -> void:
	_front_wheels.clear()
	_rear_wheels.clear()
	_all_wheels.clear()

	for wheel in [_front_left, _front_right]:
		if is_instance_valid(wheel):
			_front_wheels.append(wheel)
			_all_wheels.append(wheel)

	for wheel in [_rear_left, _rear_right]:
		if is_instance_valid(wheel):
			_rear_wheels.append(wheel)
			_all_wheels.append(wheel)


func _apply_driver_input(delta: float) -> void:
	var throttle := Input.get_action_strength("move_forward")
	var brake_reverse := Input.get_action_strength("move_back")
	var steering_input := (
		Input.get_action_strength("move_left")
		- Input.get_action_strength("move_right")
	)
	var signed_speed := _get_forward_speed()
	var absolute_speed := absf(signed_speed)

	var steering_ratio := clampf(absolute_speed / top_speed_for_steering_mps, 0.0, 1.0)
	var steering_limit := deg_to_rad(lerpf(
		steering_standstill_degrees,
		steering_top_speed_degrees,
		steering_ratio
	))
	var target_steering := steering_input * steering_limit
	_current_steering = _lerp_scalar(_current_steering, target_steering, steering_lerp_speed, delta)
	_set_front_steering(_current_steering)

	var engine := 0.0
	var brake := 0.0
	if throttle > brake_reverse and throttle > 0.01:
		if signed_speed < -brake_before_reverse_speed:
			brake = throttle * brake_force
		else:
			engine = -throttle * max_engine_force * _speed_taper(maxf(signed_speed, 0.0), max_forward_speed_mps)
	elif brake_reverse > 0.01:
		if signed_speed > brake_before_reverse_speed:
			brake = brake_reverse * brake_force
		else:
			engine = brake_reverse * max_reverse_force * _speed_taper(absf(minf(signed_speed, 0.0)), max_reverse_speed_mps)

	var handbrake := Input.is_action_pressed("handbrake")
	var rear_brake := brake
	if handbrake:
		rear_brake = maxf(rear_brake, handbrake_force)
		_apply_handbrake_friction()
	else:
		_apply_normal_friction()

	_set_rear_engine_force(engine)
	_set_wheel_brakes(brake, rear_brake)


func _set_front_steering(value: float) -> void:
	for wheel in _front_wheels:
		wheel.steering = value


func _set_rear_engine_force(value: float) -> void:
	for wheel in _front_wheels:
		wheel.engine_force = 0.0
	for wheel in _rear_wheels:
		wheel.engine_force = value


func _set_wheel_brakes(front_brake: float, rear_brake: float) -> void:
	for wheel in _front_wheels:
		wheel.brake = front_brake
	for wheel in _rear_wheels:
		wheel.brake = rear_brake


func _apply_normal_friction() -> void:
	for wheel in _front_wheels:
		wheel.wheel_friction_slip = front_friction_slip
	for wheel in _rear_wheels:
		wheel.wheel_friction_slip = rear_friction_slip


func _apply_handbrake_friction() -> void:
	for wheel in _rear_wheels:
		wheel.wheel_friction_slip = rear_friction_slip * handbrake_rear_friction_scale


func _speed_taper(speed: float, max_speed: float) -> float:
	if max_speed <= 0.01:
		return 1.0
	return clampf(1.0 - (speed / max_speed), engine_taper_floor, 1.0)


func _get_forward_speed() -> float:
	return -global_transform.basis.z.dot(linear_velocity)


func _lerp_scalar(from: float, to: float, rate: float, delta: float) -> float:
	if delta <= 0.0:
		return to
	return lerpf(from, to, clampf(1.0 - exp(-rate * delta), 0.0, 1.0))
