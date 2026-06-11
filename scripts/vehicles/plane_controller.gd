extends RigidBody3D
## Arcade flight prototype. Keeps the shared vehicle coupler contract:
## driven, set_camera_active, release_controls, and an EnterZone scene child.

@export var driven: bool = false
@export var max_forward_speed_mps: float = 52.0
@export var min_flight_speed_mps: float = 10.0
@export var takeoff_speed_mps: float = 15.0
@export var thrust_acceleration: float = 65.0
@export var reverse_acceleration: float = 4.0
@export var ground_drag: float = 0.04
@export var air_drag: float = 0.12
@export var airbrake_drag: float = 2.6
@export var airbrake_down_acceleration: float = 7.0
@export var lift_acceleration: float = 11.8
@export var max_lift_acceleration: float = 15.0
@export var idle_lift_scale: float = 0.16
@export var ground_turn_rate_degrees: float = 50.0
@export var pitch_rate_degrees: float = 42.0
@export var roll_rate_degrees: float = 88.0
@export var yaw_rate_degrees: float = 26.0
@export var control_response: float = 5.5
@export var auto_level_rate: float = 1.7
@export var low_altitude_auto_level_m: float = 7.0
@export var stall_nose_drop_degrees: float = 18.0
@export var propeller_idle_rps: float = 7.0
@export var propeller_full_rps: float = 34.0

@onready var _chase_camera: Node = get_node_or_null("CameraRig")
@onready var _propeller: Node3D = get_node_or_null("VisualRoot/PropellerRoot") as Node3D

var _control_angular_velocity := Vector3.ZERO
var _last_throttle := 0.0


func _ready() -> void:
	linear_damp = 0.0
	angular_damp = 1.2


func _physics_process(delta: float) -> void:
	if driven:
		sleeping = false
		_apply_driver_input(delta)
	else:
		release_controls(delta)

	_update_propeller(delta)


func set_camera_active(active: bool) -> void:
	if not is_instance_valid(_chase_camera) or not _chase_camera.has_method("set_camera_active"):
		return

	_chase_camera.call("set_camera_active", active)


func release_controls(delta: float = 0.0) -> void:
	_last_throttle = 0.0
	_control_angular_velocity = _control_angular_velocity.lerp(Vector3.ZERO, _blend(control_response, delta))
	angular_velocity = angular_velocity.lerp(_control_angular_velocity, _blend(control_response, delta))
	_apply_passive_drag(delta, false)
	_apply_auto_level(delta, _should_auto_level())


func get_airspeed() -> float:
	return maxf(_get_forward_speed(), 0.0)


func is_airborne() -> bool:
	return not _is_grounded()


func _apply_driver_input(delta: float) -> void:
	var throttle := Input.get_action_strength("move_forward")
	var brake_reverse := Input.get_action_strength("move_back")
	var steer := Input.get_action_strength("move_left") - Input.get_action_strength("move_right")
	var pitch_input := Input.get_action_strength("camera_up") - Input.get_action_strength("camera_down")
	var airbrake := Input.is_action_pressed("handbrake")
	_last_throttle = throttle

	var forward := -global_transform.basis.z.normalized()
	var forward_speed := _get_forward_speed()
	var speed_ratio := clampf(maxf(forward_speed, 0.0) / max_forward_speed_mps, 0.0, 1.0)
	var thrust_ratio := 1.0 - speed_ratio

	if throttle > 0.01:
		apply_central_force(forward * throttle * thrust_acceleration * maxf(thrust_ratio, 0.12) * mass)

	if brake_reverse > 0.01 and _is_grounded():
		apply_central_force(-forward * brake_reverse * reverse_acceleration * mass)

	_apply_passive_drag(delta, airbrake)
	_apply_lift(delta, forward_speed)
	_apply_flight_controls(delta, steer, pitch_input, forward_speed)
	_apply_stall_recovery(delta, forward_speed)
	_apply_auto_level(delta, _should_auto_level())


func _apply_passive_drag(delta: float, airbrake: bool) -> void:
	var drag := ground_drag if _is_grounded() else air_drag
	if airbrake:
		drag += airbrake_drag

	var horizontal := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	apply_central_force(-horizontal * drag * mass)
	if airbrake and not _is_grounded():
		apply_central_force(Vector3.DOWN * airbrake_down_acceleration * mass)


func _apply_lift(delta: float, forward_speed: float) -> void:
	if forward_speed <= min_flight_speed_mps:
		return

	var lift_ratio := clampf((forward_speed - min_flight_speed_mps) / maxf(takeoff_speed_mps - min_flight_speed_mps, 0.01), 0.0, 1.0)
	var high_speed_ratio := clampf((forward_speed - takeoff_speed_mps) / maxf(max_forward_speed_mps - takeoff_speed_mps, 0.01), 0.0, 1.0)
	var throttle_lift := lerpf(idle_lift_scale, 1.0, _last_throttle)
	var lift := lerpf(lift_acceleration, max_lift_acceleration, high_speed_ratio) * lift_ratio * throttle_lift
	apply_central_force(Vector3.UP * lift * mass)


func _apply_flight_controls(delta: float, steer: float, pitch_input: float, forward_speed: float) -> void:
	if _is_grounded():
		var target_ground_yaw := Vector3.UP * steer * deg_to_rad(ground_turn_rate_degrees)
		_control_angular_velocity = _control_angular_velocity.lerp(target_ground_yaw, _blend(control_response, delta))
		angular_velocity = angular_velocity.lerp(_control_angular_velocity, _blend(control_response, delta))
		return

	var speed_authority := clampf(forward_speed / takeoff_speed_mps, 0.35, 1.0)
	var right := global_transform.basis.x.normalized()
	var forward_axis := -global_transform.basis.z.normalized()
	var pitch_velocity := right * pitch_input * deg_to_rad(pitch_rate_degrees) * speed_authority
	var roll_velocity := forward_axis * steer * deg_to_rad(roll_rate_degrees) * speed_authority
	var yaw_velocity := Vector3.UP * -steer * deg_to_rad(yaw_rate_degrees) * speed_authority
	var target_angular := pitch_velocity + roll_velocity + yaw_velocity
	_control_angular_velocity = _control_angular_velocity.lerp(target_angular, _blend(control_response, delta))
	angular_velocity = angular_velocity.lerp(_control_angular_velocity, _blend(control_response, delta))


func _apply_stall_recovery(delta: float, forward_speed: float) -> void:
	if _is_grounded() or forward_speed >= min_flight_speed_mps:
		return

	var right := global_transform.basis.x.normalized()
	var stall_ratio := clampf(1.0 - (forward_speed / min_flight_speed_mps), 0.0, 1.0)
	angular_velocity += right * -deg_to_rad(stall_nose_drop_degrees) * stall_ratio * delta
	apply_central_force(Vector3.DOWN * 2.5 * stall_ratio * mass)


func _apply_auto_level(delta: float, active: bool) -> void:
	if not active:
		return

	var current := global_rotation
	var blend := _blend(auto_level_rate, delta)
	current.x = lerp_angle(current.x, 0.0, blend)
	current.z = lerp_angle(current.z, 0.0, blend)
	global_rotation = current


func _should_auto_level() -> bool:
	return _is_grounded() or global_position.y < low_altitude_auto_level_m


func _is_grounded() -> bool:
	return get_contact_count() > 0 and global_position.y < 1.8


func _get_forward_speed() -> float:
	return -global_transform.basis.z.dot(linear_velocity)


func _update_propeller(delta: float) -> void:
	if not is_instance_valid(_propeller):
		return

	var speed_ratio := clampf(get_airspeed() / max_forward_speed_mps, 0.0, 1.0)
	var rps := lerpf(propeller_idle_rps, propeller_full_rps, maxf(speed_ratio, _last_throttle))
	_propeller.rotation.z += TAU * rps * delta


func _blend(rate: float, delta: float) -> float:
	if delta <= 0.0:
		return 1.0
	return clampf(1.0 - exp(-rate * delta), 0.0, 1.0)
