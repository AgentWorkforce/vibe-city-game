extends Node

@export var player_root_path: NodePath
@export var car_path: NodePath
@export var player_body_name: StringName = &"Body"
@export var enter_zone_name: StringName = &"EnterZone"
@export var exit_left_offset: Vector3 = Vector3(-2.8, 0.4, 0.0)
@export var exit_raise: float = 0.15

var _player_root: Node3D
var _player_body: CollisionObject3D
var _car: Node3D
var _enter_zone: Area3D
var _driving: bool = false


func _ready() -> void:
	_resolve_nodes()


func _process(_delta: float) -> void:
	if not Input.is_action_just_pressed("interact"):
		return

	_resolve_nodes()
	if not _has_required_nodes():
		return

	if _driving:
		_exit_vehicle()
	elif _player_is_in_enter_zone():
		_enter_vehicle()


func _resolve_nodes() -> void:
	if not is_instance_valid(_player_root) and not player_root_path.is_empty():
		_player_root = get_node_or_null(player_root_path) as Node3D

	if is_instance_valid(_player_root) and not is_instance_valid(_player_body):
		_player_body = _player_root.get_node_or_null(NodePath(player_body_name)) as CollisionObject3D

	if not is_instance_valid(_car) and not car_path.is_empty():
		_car = get_node_or_null(car_path) as Node3D

	if is_instance_valid(_car) and not is_instance_valid(_enter_zone):
		_enter_zone = _car.get_node_or_null(NodePath(enter_zone_name)) as Area3D


func _has_required_nodes() -> bool:
	return (
		is_instance_valid(_player_root)
		and is_instance_valid(_player_body)
		and is_instance_valid(_car)
		and is_instance_valid(_enter_zone)
	)


func _player_is_in_enter_zone() -> bool:
	if not is_instance_valid(_enter_zone) or not is_instance_valid(_player_body):
		return false
	return _enter_zone.get_overlapping_bodies().has(_player_body)


func _enter_vehicle() -> void:
	_driving = true
	if _player_root.has_method("set_active"):
		_player_root.call("set_active", false)

	_car.set("driven", true)
	if _car.has_method("set_camera_active"):
		_car.call("set_camera_active", true)


func _exit_vehicle() -> void:
	_driving = false
	_car.set("driven", false)
	if _car.has_method("release_controls"):
		_car.call("release_controls")

	var exit_position := _get_exit_position()
	_player_root.global_position = exit_position
	if is_instance_valid(_player_body):
		_player_body.global_position = exit_position
		_player_body.set("velocity", Vector3.ZERO)

	if _player_root.has_method("set_active"):
		_player_root.call("set_active", true)


func _get_exit_position() -> Vector3:
	var local_offset := exit_left_offset
	var exit_position := _car.global_transform * local_offset
	exit_position.y = maxf(exit_position.y, _car.global_position.y + exit_raise)
	return exit_position
