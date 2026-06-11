extends VehicleBody3D
## Copy-adapted from car_controller.gd for a two-wheel prototype.
## The same coupler contract is kept: driven, set_camera_active,
## release_controls, and an EnterZone child in the scene.

@export var driven: bool = false
@export var max_engine_force: float = 1250.0
@export var max_reverse_force: float = 430.0
@export var max_forward_speed_mps: float = 32.0
@export var max_reverse_speed_mps: float = 8.0
@export var engine_taper_floor: float = 0.14
@export var brake_force: float = 24.0
@export var handbrake_force: float = 46.0
@export var idle_brake_force: float = 1.0
@export var brake_before_reverse_speed: float = 1.2
@export var steering_standstill_degrees: float = 30.0
@export var steering_top_speed_degrees: float = 8.0
@export var steering_lerp_speed: float = 10.0
@export var top_speed_for_steering_mps: float = 28.0
@export var rear_friction_slip: float = 3.35
@export var front_friction_slip: float = 3.7
@export var handbrake_rear_friction_scale: float = 0.5
@export var custom_center_of_mass: Vector3 = Vector3(0.0, -0.6, -0.05)
@export var visual_lean_max_degrees: float = 25.0
@export var lean_speed_for_full_tilt_mps: float = 18.0
@export var lean_lerp_speed: float = 9.0

@onready var _front_wheel: VehicleWheel3D = get_node_or_null("WheelFront") as VehicleWheel3D
@onready var _rear_wheel: VehicleWheel3D = get_node_or_null("WheelRear") as VehicleWheel3D
@onready var _visual_root: Node3D = get_node_or_null("VisualRoot") as Node3D
@onready var _chase_camera: Node = get_node_or_null("CameraRig")

var _current_steering: float = 0.0
var _visual_roll: float = 0.0


func _ready() -> void:
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = custom_center_of_mass
	_apply_normal_friction()


func _physics_process(delta: float) -> void:
	if driven:
		sleeping = false
		_apply_driver_input(delta)
	else:
		release_controls(delta)

	_update_visual_lean(delta)


func set_camera_active(active: bool) -> void:
	if not is_instance_valid(_chase_camera) or not _chase_camera.has_method("set_camera_active"):
		return

	_chase_camera.call("set_camera_active", active)


func release_controls(delta: float = 0.0) -> void:
	_current_steering = _lerp_scalar(_current_steering, 0.0, steering_lerp_speed, delta)
	if is_instance_valid(_front_wheel):
		_front_wheel.steering = _current_steering
	if is_instance_valid(_rear_wheel):
		_rear_wheel.engine_force = 0.0
		_rear_wheel.brake = idle_brake_force
	if is_instance_valid(_front_wheel):
		_front_wheel.engine_force = 0.0
		_front_wheel.brake = idle_brake_force
	_apply_normal_friction()


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
	if is_instance_valid(_front_wheel):
		_front_wheel.steering = _current_steering

	var engine := 0.0
	var front_brake := 0.0
	var rear_brake := 0.0
	if throttle > brake_reverse and throttle > 0.01:
		if signed_speed < -brake_before_reverse_speed:
			front_brake = throttle * brake_force
			rear_brake = front_brake
		else:
			# Vehicle forward is -Z, and positive engine_force pushes +Z.
			engine = -throttle * max_engine_force * _speed_taper(maxf(signed_speed, 0.0), max_forward_speed_mps)
	elif brake_reverse > 0.01:
		if signed_speed > brake_before_reverse_speed:
			front_brake = brake_reverse * brake_force
			rear_brake = front_brake
		else:
			engine = brake_reverse * max_reverse_force * _speed_taper(absf(minf(signed_speed, 0.0)), max_reverse_speed_mps)

	if Input.is_action_pressed("handbrake"):
		rear_brake = maxf(rear_brake, handbrake_force)
		_apply_handbrake_friction()
	else:
		_apply_normal_friction()

	if is_instance_valid(_front_wheel):
		_front_wheel.engine_force = 0.0
		_front_wheel.brake = front_brake
	if is_instance_valid(_rear_wheel):
		_rear_wheel.engine_force = engine
		_rear_wheel.brake = rear_brake


func _apply_normal_friction() -> void:
	if is_instance_valid(_front_wheel):
		_front_wheel.wheel_friction_slip = front_friction_slip
	if is_instance_valid(_rear_wheel):
		_rear_wheel.wheel_friction_slip = rear_friction_slip


func _apply_handbrake_friction() -> void:
	if is_instance_valid(_rear_wheel):
		_rear_wheel.wheel_friction_slip = rear_friction_slip * handbrake_rear_friction_scale


func _speed_taper(speed: float, max_speed: float) -> float:
	if max_speed <= 0.01:
		return 1.0
	return clampf(1.0 - (speed / max_speed), engine_taper_floor, 1.0)


func _get_forward_speed() -> float:
	return -global_transform.basis.z.dot(linear_velocity)


func _update_visual_lean(delta: float) -> void:
	if not is_instance_valid(_visual_root):
		return

	var steering_denominator := maxf(deg_to_rad(steering_standstill_degrees), 0.001)
	var steering_ratio := clampf(_current_steering / steering_denominator, -1.0, 1.0)
	var speed_ratio := clampf(absf(_get_forward_speed()) / lean_speed_for_full_tilt_mps, 0.0, 1.0)
	var target_roll := -steering_ratio * speed_ratio * deg_to_rad(visual_lean_max_degrees)
	_visual_roll = _lerp_scalar(_visual_roll, target_roll, lean_lerp_speed, delta)
	_visual_root.rotation.z = _visual_roll


func _lerp_scalar(from: float, to: float, rate: float, delta: float) -> float:
	if delta <= 0.0:
		return to
	return lerpf(from, to, clampf(1.0 - exp(-rate * delta), 0.0, 1.0))
