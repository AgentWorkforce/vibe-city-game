class_name FloatingOrigin
extends Node3D
## Keeps active world scenes near the engine origin while preserving true
## world-space coordinates through a cumulative offset.
##
## The default threshold is intentionally low enough for M3 automated coverage.
## Production city wiring should raise it to roughly 8192 m once test scenes no
## longer need frequent shifts.
## By default, only direct Node3D children of world_root_path are shifted; put
## world-space Node3D descendants under a shifted Node3D root or list them in
## shifted_node_paths.

@export var threshold_meters: float = 2048.0
@export var streamer_path: NodePath = NodePath("../WorldStreamer")
@export var target_path: NodePath
@export var world_root_path: NodePath = NodePath("..")
@export var shifted_node_paths: Array[NodePath] = []
@export var excluded_node_paths: Array[NodePath] = []
@export var excluded_node_names := PackedStringArray([
	"FloatingOrigin",
	"WorldEnvironment",
	"Sun",
	"HUD",
	"Minimap",
	"FullMap",
	"MissionBanner",
	"StreamingDebugHUD",
])

var _world_offset := Vector3.ZERO
var _shift_count := 0
var _streamer: Node
var _target: Node3D
var _world_root: Node


func _ready() -> void:
	_warn_if_duplicate_origin()
	add_to_group(&"floating_origin")
	_resolve_world_root()
	_resolve_streamer()
	_resolve_target()


func _physics_process(_delta: float) -> void:
	_resolve_target()
	if not is_instance_valid(_target):
		return

	var offset := Vector3(_target.global_position.x, 0.0, _target.global_position.z)
	if offset.length() <= maxf(threshold_meters, 1.0):
		return

	_shift_origin(offset)


func to_world(local_world_position: Vector3) -> Vector3:
	return local_world_position + _world_offset


func to_local_world(true_world_position: Vector3) -> Vector3:
	return true_world_position - _world_offset


func get_world_offset() -> Vector3:
	return _world_offset


func get_shift_count() -> int:
	return _shift_count


func get_current_target() -> Node3D:
	return _target


func _shift_origin(offset: Vector3) -> void:
	if offset.length_squared() <= 0.0001:
		return

	for node in _collect_shift_nodes():
		if not is_instance_valid(node):
			continue
		node.global_position -= offset
		_reset_physics_interpolation_recursive(node)

	_world_offset += offset
	_shift_count += 1
	_emit_origin_shifted(offset)


func _collect_shift_nodes() -> Array[Node3D]:
	var result: Array[Node3D] = []
	if not shifted_node_paths.is_empty():
		for path in shifted_node_paths:
			var explicit_node := get_node_or_null(path) as Node3D
			if explicit_node != null and _is_shift_candidate(explicit_node):
				result.append(explicit_node)
		return result

	_resolve_world_root()
	if _world_root == null:
		return result

	for child in _world_root.get_children():
		var node3d := child as Node3D
		if node3d != null and _is_shift_candidate(node3d):
			result.append(node3d)
	return result


func _is_shift_candidate(node: Node3D) -> bool:
	if node == null or node == self:
		return false
	if excluded_node_names.has(String(node.name)):
		return false
	for path in excluded_node_paths:
		var excluded := get_node_or_null(path)
		if excluded == node:
			return false
	return true


func _resolve_world_root() -> void:
	if is_instance_valid(_world_root):
		return
	if not world_root_path.is_empty():
		_world_root = get_node_or_null(world_root_path)
	if _world_root == null:
		_world_root = get_parent()


func _resolve_streamer() -> void:
	if is_instance_valid(_streamer):
		return
	if not streamer_path.is_empty():
		_streamer = get_node_or_null(streamer_path)
	if _streamer == null and is_instance_valid(_world_root):
		_streamer = _world_root.find_child("WorldStreamer", false, false)


func _resolve_target() -> void:
	_resolve_streamer()
	if is_instance_valid(_streamer) and _streamer.has_method("get_current_target"):
		var streamer_target := _streamer.call("get_current_target") as Node3D
		if is_instance_valid(streamer_target):
			_target = streamer_target
			return

	if not target_path.is_empty():
		var explicit_target := get_node_or_null(target_path) as Node3D
		if explicit_target != null:
			_target = explicit_target
			return

	for node in get_tree().get_nodes_in_group(&"player"):
		var player := node as Node3D
		if player != null:
			_target = player
			return


func _emit_origin_shifted(offset: Vector3) -> void:
	var events := get_node_or_null("/root/Events")
	if events != null and events.has_signal(&"origin_shifted"):
		events.emit_signal(&"origin_shifted", offset)


func _warn_if_duplicate_origin() -> void:
	if not is_inside_tree():
		return

	for node in get_tree().get_nodes_in_group(&"floating_origin"):
		if node == self:
			continue
		push_warning(
			"FloatingOrigin detected another active origin at %s; consumers use the first group member, so duplicates are order-dependent." %
			node.get_path()
		)
		return


func _reset_physics_interpolation_recursive(node: Node) -> void:
	if node.has_method("reset_physics_interpolation"):
		node.call("reset_physics_interpolation")
	for child in node.get_children():
		_reset_physics_interpolation_recursive(child)
