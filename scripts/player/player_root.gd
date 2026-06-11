extends Node3D

@export var camera_follow_speed: float = 12.0

@onready var body: CharacterBody3D = $Body
@onready var camera_rig: Node3D = $CameraRig


func _ready() -> void:
	camera_rig.global_position = body.global_position
	if body.has_method("set_camera_yaw_source"):
		body.call("set_camera_yaw_source", camera_rig)
	if camera_rig.has_method("set_speed_source"):
		camera_rig.call("set_speed_source", body)
	if camera_rig.has_method("exclude_collision"):
		camera_rig.call("exclude_collision", body.get_rid())


func _process(delta: float) -> void:
	var blend := clampf(1.0 - exp(-camera_follow_speed * delta), 0.0, 1.0)
	camera_rig.global_position = camera_rig.global_position.lerp(body.global_position, blend)
