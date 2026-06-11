extends Node3D
## Shared chase camera rig for drivable vehicles.
## Attach to a vehicle's CameraRig node with SpringArm3D/Camera3D children.

@export var target_path: NodePath
@export var spring_arm_path: NodePath = NodePath("SpringArm3D")
@export var camera_path: NodePath = NodePath("SpringArm3D/Camera3D")
@export var max_speed_property: StringName = &"max_forward_speed_mps"
@export var look_behind_action: StringName = &"look_behind"
@export var follow_speed: float = 9.0
@export var yaw_lerp_speed: float = 7.0
@export var base_fov: float = 70.0
@export var fast_fov: float = 85.0
@export var fov_lerp_speed: float = 7.0
@export var look_height: float = 0.85
@export var fov_full_speed: float = 0.0

var _target: Node3D
var _body: RigidBody3D
var _spring_arm: SpringArm3D
var _camera: Camera3D
var _camera_yaw: float = 0.0


func _ready() -> void:
	_resolve_nodes()
	if not is_instance_valid(_target):
		return

	top_level = true
	_camera_yaw = _target.global_rotation.y
	global_position = _target.global_position
	global_rotation = Vector3(0.0, _camera_yaw, 0.0)

	var collision_target := _target as CollisionObject3D
	if is_instance_valid(_spring_arm) and is_instance_valid(collision_target):
		_spring_arm.add_excluded_object(collision_target.get_rid())

	if is_instance_valid(_camera):
		_camera.fov = base_fov
		if _is_target_driven():
			_camera.make_current()


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_target):
		_resolve_nodes()
	if not is_instance_valid(_target):
		return

	var follow_blend := _blend(follow_speed, delta)
	global_position = global_position.lerp(_target.global_position, follow_blend)

	var target_yaw := _target.global_rotation.y
	if _is_target_driven() and Input.is_action_pressed(look_behind_action):
		target_yaw += PI

	var yaw_blend := _blend(yaw_lerp_speed, delta)
	_camera_yaw = lerp_angle(_camera_yaw, target_yaw, yaw_blend)
	global_rotation = Vector3(0.0, _camera_yaw, 0.0)

	if not is_instance_valid(_camera):
		return

	var speed_ratio := clampf(_target_speed() / _fov_speed(), 0.0, 1.0)
	var target_fov := lerpf(base_fov, fast_fov, speed_ratio)
	_camera.fov = lerpf(_camera.fov, target_fov, _blend(fov_lerp_speed, delta))

	var look_target := _target.global_position + Vector3.UP * look_height
	var look_direction := look_target - _camera.global_position
	if look_direction.length_squared() > 0.0001 and absf(look_direction.normalized().dot(Vector3.UP)) < 0.98:
		_camera.look_at(look_target, Vector3.UP)


func set_camera_active(active: bool) -> void:
	if not is_instance_valid(_camera):
		_resolve_nodes()
	if not is_instance_valid(_camera):
		return

	if active:
		_camera.make_current()
	else:
		_camera.current = false


func _resolve_nodes() -> void:
	if not is_instance_valid(_target):
		if not target_path.is_empty():
			_target = get_node_or_null(target_path) as Node3D
		else:
			_target = get_parent() as Node3D
		_body = _target as RigidBody3D

	if not is_instance_valid(_spring_arm):
		_spring_arm = get_node_or_null(spring_arm_path) as SpringArm3D

	if not is_instance_valid(_camera):
		_camera = get_node_or_null(camera_path) as Camera3D


func _is_target_driven() -> bool:
	if not is_instance_valid(_target):
		return false
	return bool(_target.get("driven"))


func _target_speed() -> float:
	if is_instance_valid(_body):
		return _body.linear_velocity.length()
	return 0.0


func _fov_speed() -> float:
	if fov_full_speed > 0.01:
		return fov_full_speed

	if is_instance_valid(_target):
		var value: Variant = _target.get(max_speed_property)
		if value is float or value is int:
			return maxf(float(value), 0.01)

	return 30.0


func _blend(rate: float, delta: float) -> float:
	if delta <= 0.0:
		return 1.0
	return clampf(1.0 - exp(-rate * delta), 0.0, 1.0)
