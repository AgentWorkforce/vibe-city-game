extends RigidBody3D
## RigidBody3D boat controller with local buoyancy probes.
## Keeps the vehicle_coupler contract used by the car: driven,
## set_camera_active, release_controls, and an EnterZone child in the scene.

@export var driven: bool = false
# TODO(M3 floating origin): derive this from the active water surface or update
# it from the origin-shift signal instead of treating world Y as permanent.
@export var water_level: float = 0.0
@export var buoyancy_force_per_probe: float = 2600.0
@export var buoyancy_probe_depth: float = 0.85
@export var buoyancy_damping: float = 420.0
@export var water_linear_damp: float = 1.65
@export var water_angular_damp: float = 3.4
@export var air_linear_damp: float = 0.05
@export var air_angular_damp: float = 0.05
@export var max_thrust_force: float = 2850.0
@export var max_reverse_force: float = 720.0
@export var max_forward_speed_mps: float = 24.0
@export var max_reverse_speed_mps: float = 7.0
@export var engine_taper_floor: float = 0.18
@export var brake_before_reverse_speed: float = 1.0
@export var steering_torque: float = 780.0
@export var steering_speed_for_full_torque_mps: float = 13.0
@export var stern_force_local_offset: Vector3 = Vector3(0.0, -0.05, 1.45)
@export var wake_min_speed: float = 1.3

@onready var _probe_root: Node3D = get_node_or_null("BuoyancyProbes") as Node3D
@onready var _chase_camera: Node = get_node_or_null("CameraRig")
@onready var _wake: CPUParticles3D = get_node_or_null("WakeParticles") as CPUParticles3D

var _probe_points: Array[Vector3] = []
var _in_water: bool = false


func _ready() -> void:
	_collect_probe_points()
	linear_damp = air_linear_damp
	angular_damp = air_angular_damp


func _physics_process(delta: float) -> void:
	sleeping = false if driven else sleeping
	_apply_buoyancy()
	if driven:
		_apply_driver_input()
	else:
		release_controls()

	_update_damping()
	_update_wake()


func set_camera_active(active: bool) -> void:
	if not is_instance_valid(_chase_camera) or not _chase_camera.has_method("set_camera_active"):
		return

	_chase_camera.call("set_camera_active", active)


func release_controls(_delta: float = 0.0) -> void:
	pass


func _collect_probe_points() -> void:
	_probe_points.clear()
	if is_instance_valid(_probe_root):
		for child in _probe_root.get_children():
			var probe := child as Node3D
			if is_instance_valid(probe):
				_probe_points.append(probe.position)

	if _probe_points.is_empty():
		_probe_points = [
			Vector3(-0.75, -0.35, -1.5),
			Vector3(0.75, -0.35, -1.5),
			Vector3(-0.75, -0.35, 1.5),
			Vector3(0.75, -0.35, 1.5),
		]


func _apply_buoyancy() -> void:
	_in_water = false
	for local_point in _probe_points:
		var world_point := global_transform * local_point
		var submersion := water_level - world_point.y
		if submersion <= 0.0:
			continue

		_in_water = true
		var depth_ratio := clampf(submersion / buoyancy_probe_depth, 0.0, 1.0)
		var point_offset := world_point - global_position
		var point_velocity := linear_velocity + angular_velocity.cross(point_offset)
		var damping_force := -point_velocity.y * buoyancy_damping
		var upward_force := maxf((depth_ratio * buoyancy_force_per_probe) + damping_force, 0.0)
		apply_force(Vector3.UP * upward_force, point_offset)


func _apply_driver_input() -> void:
	var throttle := Input.get_action_strength("move_forward")
	var brake_reverse := Input.get_action_strength("move_back")
	var steering_input := (
		Input.get_action_strength("move_left")
		- Input.get_action_strength("move_right")
	)
	var signed_speed := _get_forward_speed()
	var forward := -global_transform.basis.z.normalized()
	var stern_offset := global_transform.basis * stern_force_local_offset

	if throttle > brake_reverse and throttle > 0.01:
		var thrust := max_thrust_force
		if signed_speed < -brake_before_reverse_speed:
			thrust *= 0.45
		else:
			thrust *= _speed_taper(maxf(signed_speed, 0.0), max_forward_speed_mps)
		apply_force(forward * throttle * thrust, stern_offset)
	elif brake_reverse > 0.01:
		var reverse_force := max_reverse_force
		if signed_speed > brake_before_reverse_speed:
			reverse_force *= 0.6
		else:
			reverse_force *= _speed_taper(absf(minf(signed_speed, 0.0)), max_reverse_speed_mps)
		apply_force(-forward * brake_reverse * reverse_force, stern_offset)

	if absf(steering_input) > 0.01:
		var speed_ratio := clampf(absf(signed_speed) / steering_speed_for_full_torque_mps, 0.0, 1.0)
		var torque_scale := lerpf(0.25, 1.0, speed_ratio)
		apply_torque(Vector3.UP * steering_input * steering_torque * torque_scale)


func _update_damping() -> void:
	if _in_water:
		linear_damp = water_linear_damp
		angular_damp = water_angular_damp
	else:
		linear_damp = air_linear_damp
		angular_damp = air_angular_damp


func _update_wake() -> void:
	if not is_instance_valid(_wake):
		return
	_wake.emitting = _in_water and linear_velocity.length() > wake_min_speed


func _speed_taper(speed: float, max_speed: float) -> float:
	if max_speed <= 0.01:
		return 1.0
	return clampf(1.0 - (speed / max_speed), engine_taper_floor, 1.0)


func _get_forward_speed() -> float:
	return -global_transform.basis.z.dot(linear_velocity)

