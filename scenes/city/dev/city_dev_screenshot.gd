extends Node3D

@export var camera_path: NodePath = NodePath("Camera3D")
@export var look_at_position := Vector3(320, 1, 64)


func _ready() -> void:
	var camera := get_node_or_null(camera_path) as Camera3D
	if camera == null:
		return

	camera.look_at(look_at_position, Vector3.UP)
	camera.make_current()
