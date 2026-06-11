extends Node3D

@export var camera_follow_speed: float = 12.0

@onready var body: CharacterBody3D = $Body
@onready var camera_rig: Node3D = $CameraRig

var _body_collision_layer: int = 0
var _body_collision_mask: int = 0
var _body_collision_saved: bool = false


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


func set_active(active: bool) -> void:
	if active:
		process_mode = Node.PROCESS_MODE_INHERIT
		if _body_collision_saved:
			body.collision_layer = _body_collision_layer
			body.collision_mask = _body_collision_mask
			_body_collision_saved = false
		visible = true
		camera_rig.global_position = body.global_position
		var player_camera := get_node_or_null("CameraRig/Pitch/SpringArm3D/Camera3D") as Camera3D
		if is_instance_valid(player_camera):
			player_camera.make_current()
	else:
		if not _body_collision_saved:
			_body_collision_layer = body.collision_layer
			_body_collision_mask = body.collision_mask
			_body_collision_saved = true
		body.collision_layer = 0
		body.collision_mask = 0
		visible = false
		process_mode = Node.PROCESS_MODE_DISABLED
