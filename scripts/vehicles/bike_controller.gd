extends VehicleBody3D
## Copy-adapted from car_controller.gd for a two-wheel prototype.
## The same coupler contract is kept: driven, set_camera_active,
## release_controls, and an EnterZone child in the scene.
## TODO(pre-plane): extract the chase-camera block shared by car/bike/boat.

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
@export var camera_follow_speed: float = 9.0
@export var camera_yaw_lerp_speed: float = 7.0
@export var camera_base_fov: float = 70.0
@export var camera_fast_fov: float = 84.0
@export var camera_fov_lerp_speed: float = 7.0
@export var camera_look_height: float = 0.9

@onready var _front_wheel: VehicleWheel3D = get_node_or_null("WheelFront") as VehicleWheel3D
@onready var _rear_wheel: VehicleWheel3D = get_node_or_null("WheelRear") as VehicleWheel3D
@onready var _visual_root: Node3D = get_node_or_null("VisualRoot") as Node3D
@onready var _camera_rig: Node3D = get_node_or_null("CameraRig") as Node3D
@onready var _spring_arm: SpringArm3D = get_node_or_null("CameraRig/SpringArm3D") as SpringArm3D
@onready var _camera: Camera3D = get_node_or_null("CameraRig/SpringArm3D/Camera3D") as Camera3D

var _current_steering: float = 0.0
var _camera_yaw: float = 0.0
var _visual_roll: float = 0.0


func _ready() -> void:
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = custom_center_of_mass
	_apply_normal_friction()
	_camera_yaw = global_rotation.y

	if is_instance_valid(_camera_rig):
		_camera_rig.top_level = true
		_camera_rig.global_position = global_position
		_camera_rig.global_rotation = Vector3(0.0, _camera_yaw, 0.0)

	if is_instance_valid(_spring_arm):
		_spring_arm.add_excluded_object(get_rid())

	if is_instance_valid(_camera):
		_camera.fov = camera_base_fov
		if driven:
			_camera.make_current()


func _physics_process(delta: float) -> void:
	if driven:
		sleeping = false
		_apply_driver_input(delta)
	else:
		release_controls(delta)

	_update_visual_lean(delta)
	_update_chase_camera(delta)


func set_camera_active(active: bool) -> void:
	if not is_instance_valid(_camera):
		return

	if active:
		_camera.make_current()
	else:
		_camera.current = false


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


func _update_chase_camera(delta: float) -> void:
	if not is_instance_valid(_camera_rig):
		return

	var follow_blend := clampf(1.0 - exp(-camera_follow_speed * delta), 0.0, 1.0)
	_camera_rig.global_position = _camera_rig.global_position.lerp(global_position, follow_blend)

	var target_yaw := global_rotation.y
	if driven and Input.is_action_pressed("look_behind"):
		target_yaw += PI

	var yaw_blend := clampf(1.0 - exp(-camera_yaw_lerp_speed * delta), 0.0, 1.0)
	_camera_yaw = lerp_angle(_camera_yaw, target_yaw, yaw_blend)
	_camera_rig.global_rotation = Vector3(0.0, _camera_yaw, 0.0)

	if is_instance_valid(_camera):
		var speed_ratio := clampf(linear_velocity.length() / max_forward_speed_mps, 0.0, 1.0)
		var target_fov := lerpf(camera_base_fov, camera_fast_fov, speed_ratio)
		var fov_blend := clampf(1.0 - exp(-camera_fov_lerp_speed * delta), 0.0, 1.0)
		_camera.fov = lerpf(_camera.fov, target_fov, fov_blend)
		var look_target := global_position + Vector3.UP * camera_look_height
		var look_direction := look_target - _camera.global_position
		if look_direction.length_squared() > 0.0001 and absf(look_direction.normalized().dot(Vector3.UP)) < 0.98:
			_camera.look_at(look_target, Vector3.UP)


func _lerp_scalar(from: float, to: float, rate: float, delta: float) -> float:
	if delta <= 0.0:
		return to
	return lerpf(from, to, clampf(1.0 - exp(-rate * delta), 0.0, 1.0))
