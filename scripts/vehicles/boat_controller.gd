extends RigidBody3D
## RigidBody3D boat controller with local buoyancy probes.
## Keeps the vehicle_coupler contract used by the car: driven,
## set_camera_active, release_controls, and an EnterZone child in the scene.

const ENGINE_LOOP: AudioStream = preload("res://assets/audio/sfx/engine_loop.wav")
const IMPACT: AudioStream = preload("res://assets/audio/sfx/impact_crunch.wav")

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
@export var camera_follow_speed: float = 7.0
@export var camera_yaw_lerp_speed: float = 6.0
@export var camera_base_fov: float = 70.0
@export var camera_fast_fov: float = 82.0
@export var camera_fov_lerp_speed: float = 6.0
@export var camera_look_height: float = 0.8
@export var wake_min_speed: float = 1.3
@export var idle_pitch: float = 0.64
@export var max_pitch: float = 1.55
@export var pitch_full_speed: float = 22.0
@export var idle_volume_db: float = -19.0
@export var driving_volume_db: float = -8.5
@export var impact_min_velocity: float = 4.0
@export var impact_cooldown: float = 0.4

@onready var _probe_root: Node3D = get_node_or_null("BuoyancyProbes") as Node3D
@onready var _camera_rig: Node3D = get_node_or_null("CameraRig") as Node3D
@onready var _spring_arm: SpringArm3D = get_node_or_null("CameraRig/SpringArm3D") as SpringArm3D
@onready var _camera: Camera3D = get_node_or_null("CameraRig/SpringArm3D/Camera3D") as Camera3D
@onready var _wake: CPUParticles3D = get_node_or_null("WakeParticles") as CPUParticles3D

var _probe_points: Array[Vector3] = []
var _camera_yaw: float = 0.0
var _in_water: bool = false
var _engine: AudioStreamPlayer3D
var _impact: AudioStreamPlayer3D
var _impact_timer: float = 0.0
var _last_velocity: Vector3 = Vector3.ZERO


func _ready() -> void:
	_collect_probe_points()
	linear_damp = air_linear_damp
	angular_damp = air_angular_damp
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

	_engine = _make_audio_player(ENGINE_LOOP, idle_volume_db)
	_impact = _make_audio_player(IMPACT, -4.0)
	_engine.play()


func _physics_process(delta: float) -> void:
	sleeping = false if driven else sleeping
	_apply_buoyancy()
	if driven:
		_apply_driver_input()
	else:
		release_controls()

	_update_damping()
	_update_wake()
	_update_audio(delta)
	_update_chase_camera(delta)


func set_camera_active(active: bool) -> void:
	if not is_instance_valid(_camera):
		return

	if active:
		_camera.make_current()
	else:
		_camera.current = false


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


func _make_audio_player(audio: AudioStream, volume_db: float) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.stream = audio
	player.volume_db = volume_db
	player.max_distance = 65.0
	add_child(player)
	return player


func _update_audio(delta: float) -> void:
	if not is_instance_valid(_engine):
		return

	var speed := linear_velocity.length()
	var speed_ratio := clampf(speed / pitch_full_speed, 0.0, 1.0)
	_engine.pitch_scale = lerpf(idle_pitch, max_pitch, speed_ratio)
	var target_db := driving_volume_db if driven else idle_volume_db
	_engine.volume_db = lerpf(_engine.volume_db, target_db + speed_ratio * 3.0, 1.0 - exp(-6.0 * delta))

	_impact_timer = maxf(_impact_timer - delta, 0.0)
	var dv := (linear_velocity - _last_velocity).length()
	if is_instance_valid(_impact) and dv > impact_min_velocity and _impact_timer <= 0.0 and get_contact_count() > 0:
		_impact.volume_db = lerpf(-10.0, 0.0, clampf(dv / 15.0, 0.0, 1.0))
		_impact.play()
		_impact_timer = impact_cooldown
	_last_velocity = linear_velocity


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
