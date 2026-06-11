class_name TrafficCar
extends CharacterBody3D

const SimLODManagerScript = preload("res://scripts/sim_lod/sim_lod_manager.gd")

@export var cruise_speed: float = 9.0
@export var acceleration: float = 9.0
@export var braking: float = 24.0
@export var obstacle_ray_length: float = 8.0
@export var obstacle_ray_start: float = 1.2
@export var turn_rate: float = 8.0
@export var wheel_radius: float = 0.34
@export var color_palette: Array[Color] = [
	Color(0.95, 0.22, 0.18, 1.0),
	Color(0.1, 0.44, 0.88, 1.0),
	Color(0.98, 0.82, 0.22, 1.0),
	Color(0.15, 0.72, 0.42, 1.0),
	Color(0.9, 0.92, 0.96, 1.0),
	Color(0.08, 0.09, 0.13, 1.0),
]

var road_graph: RefCounted
var loop_index := 0
var path_distance := 0.0

var _current_speed := 0.0
var _stopped_for_obstacle := false
var _rng := RandomNumberGenerator.new()
var _forward := Vector3.FORWARD
var _sim_lod_manager: Node
var _sim_lod_tier := SimLODManagerScript.TIER_NEAR
var _sim_lod_mid_interval := 1
var _sim_lod_tick_counter := 0
var _sim_lod_accumulated_delta := 0.0
var _sim_lod_step_delta := 0.0
var _sim_lod_collision_saved := false
var _sim_lod_collision_layer := 0
var _sim_lod_collision_mask := 0

@onready var _body_mesh: MeshInstance3D = get_node_or_null("Visuals/Body") as MeshInstance3D
@onready var _wheels: Array[Node3D] = [
	get_node_or_null("Visuals/WheelFrontLeft") as Node3D,
	get_node_or_null("Visuals/WheelFrontRight") as Node3D,
	get_node_or_null("Visuals/WheelRearLeft") as Node3D,
	get_node_or_null("Visuals/WheelRearRight") as Node3D,
]


func _ready() -> void:
	add_to_group("traffic_cars")
	_rng.randomize()
	_apply_random_color()
	if road_graph != null:
		_sync_to_graph(true, 0.0)
	_register_sim_lod()


func _physics_process(delta: float) -> void:
	if _sim_lod_tier != SimLODManagerScript.TIER_NEAR and not _begin_sim_lod_step(delta):
		return

	if _sim_lod_tier != SimLODManagerScript.TIER_NEAR:
		delta = _sim_lod_step_delta

	if road_graph == null or road_graph.get_loop_count() == 0:
		velocity = Vector3.ZERO
		return

	if _sim_lod_tier == SimLODManagerScript.TIER_FAR:
		_update_far_traffic(delta)
		return

	var extra_lookahead := _obstacle_lookahead_extra(delta)
	_stopped_for_obstacle = _is_forward_blocked(extra_lookahead)
	var target_speed := 0.0 if _stopped_for_obstacle else cruise_speed
	var rate := braking if target_speed < _current_speed else acceleration
	_current_speed = move_toward(_current_speed, target_speed, rate * delta)

	path_distance = road_graph.wrap_distance(loop_index, path_distance + _current_speed * delta)
	_sync_to_graph(false, delta)
	_spin_wheels(delta)


func _exit_tree() -> void:
	if is_instance_valid(_sim_lod_manager):
		_sim_lod_manager.unregister_npc(self)


func configure(graph: RefCounted, assigned_loop_index: int, initial_distance: float, target_speed: float = -1.0) -> void:
	road_graph = graph
	if road_graph == null or road_graph.get_loop_count() == 0:
		return

	loop_index = clampi(assigned_loop_index, 0, road_graph.get_loop_count() - 1)
	path_distance = road_graph.wrap_distance(loop_index, initial_distance)
	if target_speed > 0.0:
		cruise_speed = target_speed
	_current_speed = cruise_speed
	_sync_to_graph(true, 0.0)


func get_current_speed() -> float:
	return _current_speed


func is_stopped_for_obstacle() -> bool:
	return _stopped_for_obstacle and _current_speed <= 0.25


func get_forward_direction() -> Vector3:
	return _forward


func set_sim_tier(tier: int) -> void:
	set_sim_lod(tier, _sim_lod_mid_interval)


func set_sim_lod(tier: int, mid_interval: int = 1) -> void:
	var previous_tier: int = _sim_lod_tier
	var previous_interval: int = _sim_lod_mid_interval
	_sim_lod_tier = tier
	_sim_lod_mid_interval = maxi(1, mid_interval)
	if tier != previous_tier or _sim_lod_mid_interval != previous_interval:
		_reset_sim_lod_tick_state()
	_apply_sim_lod_collision_mode()


func get_sim_tier() -> int:
	return _sim_lod_tier


func _sync_to_graph(snap_rotation: bool, delta: float) -> void:
	# RoadGraph waypoints remain in true world coordinates. Traffic cars are
	# shifted with the scene, so graph samples are converted back to local world.
	var next_position: Vector3 = _to_local_world_position(road_graph.sample_position(loop_index, path_distance))
	var next_forward: Vector3 = road_graph.sample_forward(loop_index, path_distance)
	if next_forward.length_squared() <= 0.001:
		next_forward = _forward

	_forward = next_forward.normalized()
	global_position = next_position
	velocity = _forward * _current_speed

	var desired_basis := Basis.looking_at(_forward, Vector3.UP)
	if snap_rotation:
		global_transform = Transform3D(desired_basis, global_position)
	else:
		var blend := clampf(turn_rate * delta, 0.0, 1.0)
		global_transform = Transform3D(global_transform.basis.slerp(desired_basis, blend).orthonormalized(), global_position)


func _is_forward_blocked(extra_lookahead: float = 0.0) -> bool:
	var world := get_world_3d()
	if world == null:
		return false

	var ray_from := global_position + Vector3.UP * 0.65 + _forward * obstacle_ray_start
	var ray_to := ray_from + _forward * (obstacle_ray_length + maxf(extra_lookahead, 0.0))
	var query := PhysicsRayQueryParameters3D.create(ray_from, ray_to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [get_rid()]

	return not world.direct_space_state.intersect_ray(query).is_empty()


func _spin_wheels(delta: float) -> void:
	if wheel_radius <= 0.001:
		return

	var spin := (_current_speed / wheel_radius) * delta
	for wheel in _wheels:
		if wheel == null:
			continue
		wheel.rotate_y(spin)


func _apply_random_color() -> void:
	if _body_mesh == null:
		return

	var material := StandardMaterial3D.new()
	material.albedo_color = _pick_color()
	material.roughness = 0.58
	material.metallic = 0.05
	_body_mesh.material_override = material


func _pick_color() -> Color:
	if color_palette.is_empty():
		return Color(0.95, 0.22, 0.18, 1.0)
	return color_palette[_rng.randi_range(0, color_palette.size() - 1)]


func _to_local_world_position(true_world_position: Vector3) -> Vector3:
	var origin := _floating_origin()
	if origin != null and origin.has_method("to_local_world"):
		return origin.call("to_local_world", true_world_position) as Vector3
	return true_world_position


func _floating_origin() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group(&"floating_origin")


func _register_sim_lod() -> void:
	_sim_lod_manager = SimLODManagerScript.get_or_create(self)
	if is_instance_valid(_sim_lod_manager):
		_sim_lod_manager.register_npc(self, &"traffic")


func _begin_sim_lod_step(delta: float) -> bool:
	_sim_lod_step_delta = delta
	if _sim_lod_tier == SimLODManagerScript.TIER_MID:
		_sim_lod_accumulated_delta += delta
		_sim_lod_tick_counter += 1
		if _sim_lod_tick_counter % _sim_lod_mid_interval != 0:
			return false

		_sim_lod_step_delta = _sim_lod_accumulated_delta
		_sim_lod_accumulated_delta = 0.0
		return true

	_sim_lod_accumulated_delta = 0.0
	return true


func _update_far_traffic(delta: float) -> void:
	_stopped_for_obstacle = false
	_current_speed = move_toward(_current_speed, cruise_speed, acceleration * delta)
	path_distance = road_graph.wrap_distance(loop_index, path_distance + _current_speed * delta)
	_sync_to_graph(true, 0.0)


func _obstacle_lookahead_extra(delta: float) -> float:
	if _sim_lod_tier != SimLODManagerScript.TIER_MID:
		return 0.0
	return _current_speed * maxf(delta, 0.0)


func _reset_sim_lod_tick_state() -> void:
	_sim_lod_tick_counter = 0
	_sim_lod_accumulated_delta = 0.0


func _apply_sim_lod_collision_mode() -> void:
	if _sim_lod_tier == SimLODManagerScript.TIER_FAR:
		if _sim_lod_collision_saved:
			return
		_sim_lod_collision_layer = collision_layer
		_sim_lod_collision_mask = collision_mask
		_sim_lod_collision_saved = true
		collision_layer = 0
		collision_mask = 0
		return

	if not _sim_lod_collision_saved:
		return

	collision_layer = _sim_lod_collision_layer
	collision_mask = _sim_lod_collision_mask
	_sim_lod_collision_saved = false
