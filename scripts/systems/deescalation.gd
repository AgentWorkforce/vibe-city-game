extends Node

const BarkSystem = preload("res://scripts/agents/bark_system.gd")

@export var player_root_path: NodePath
@export var respawn_marker_path: NodePath
@export var police_grace_seconds: float = 5.0

var _barks := BarkSystem.new()
var _player_root: Node3D
var _respawn_marker: Node3D
var _player_vehicle: Node
var _grace_until_msec := 0


func _ready() -> void:
	_resolve_nodes()
	_connect_events()


func _process(_delta: float) -> void:
	_resolve_nodes()
	if _in_grace_window():
		_apply_police_grace()


func handle_player_caught(by: Node = null) -> void:
	_resolve_nodes()
	if _is_player_driving():
		return

	_emit_player_down_bark(by)
	_clear_wanted()
	_start_grace()
	_apply_police_grace()
	_set_player_active(false)
	_teleport_player_to_respawn()
	_set_player_active(true)


func _connect_events() -> void:
	var events := _events()
	if events == null:
		return

	var caught_callable := Callable(self, "_on_player_caught")
	if events.has_signal(&"player_caught") and not events.is_connected(&"player_caught", caught_callable):
		events.connect(&"player_caught", caught_callable)

	var entered_callable := Callable(self, "_on_vehicle_entered")
	if events.has_signal(&"vehicle_entered") and not events.is_connected(&"vehicle_entered", entered_callable):
		events.connect(&"vehicle_entered", entered_callable)

	var exited_callable := Callable(self, "_on_vehicle_exited")
	if events.has_signal(&"vehicle_exited") and not events.is_connected(&"vehicle_exited", exited_callable):
		events.connect(&"vehicle_exited", exited_callable)


func _on_player_caught(by: Node) -> void:
	handle_player_caught(by)


func _on_vehicle_entered(vehicle: Node) -> void:
	_player_vehicle = vehicle


func _on_vehicle_exited(vehicle: Node) -> void:
	if vehicle == _player_vehicle:
		_player_vehicle = null


func _resolve_nodes() -> void:
	if not is_instance_valid(_player_root) and not player_root_path.is_empty():
		_player_root = get_node_or_null(player_root_path) as Node3D

	if not is_instance_valid(_respawn_marker) and not respawn_marker_path.is_empty():
		_respawn_marker = get_node_or_null(respawn_marker_path) as Node3D


func _is_player_driving() -> bool:
	if is_instance_valid(_player_vehicle) and _is_driven_vehicle(_player_vehicle):
		return true

	var root := get_tree().current_scene
	if root == null:
		root = get_tree().root
	return _has_driven_vehicle_under(root)


func _has_driven_vehicle_under(node: Node) -> bool:
	if _is_driven_vehicle(node):
		return true

	for child in node.get_children():
		if _has_driven_vehicle_under(child):
			return true

	return false


func _is_driven_vehicle(node: Node) -> bool:
	if node == null or not (node is VehicleBody3D):
		return false
	return bool(node.get("driven"))


func _emit_player_down_bark(by: Node) -> void:
	var line := _barks.get_bark("player_down")
	if line.is_empty():
		line = "You've been temporarily de-escalated. See you soon, friend!"

	var events := _events()
	if events != null:
		events.emit_signal(&"bark_emitted", by if is_instance_valid(by) else self, &"player_down", line)


func _clear_wanted() -> void:
	var wanted := get_node_or_null("/root/Wanted")
	if wanted != null and wanted.has_method("clear"):
		wanted.call("clear")


func _set_player_active(active: bool) -> void:
	if is_instance_valid(_player_root) and _player_root.has_method("set_active"):
		_player_root.call("set_active", active)


func _teleport_player_to_respawn() -> void:
	if not is_instance_valid(_respawn_marker):
		return

	var target_position := _respawn_marker.global_position
	if is_instance_valid(_player_root):
		_player_root.global_position = target_position

	var body := _player_body()
	if is_instance_valid(body):
		body.global_position = target_position
		body.set("velocity", Vector3.ZERO)


func _player_body() -> Node3D:
	if not is_instance_valid(_player_root):
		return null

	var body := _player_root.get_node_or_null("Body") as Node3D
	if body != null:
		return body

	return _player_root


func _start_grace() -> void:
	_grace_until_msec = max(_grace_until_msec, Time.get_ticks_msec() + int(maxf(police_grace_seconds, 0.0) * 1000.0))


func _apply_police_grace() -> void:
	var remaining := maxf(float(_grace_until_msec - Time.get_ticks_msec()) / 1000.0, 0.0)
	if remaining <= 0.0:
		return

	for node in get_tree().get_nodes_in_group("police"):
		if node != null and node.has_method("ignore_player_for"):
			node.call("ignore_player_for", remaining)


func _in_grace_window() -> bool:
	return Time.get_ticks_msec() < _grace_until_msec


func _events() -> Node:
	return get_node_or_null("/root/Events")
