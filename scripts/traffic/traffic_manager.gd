class_name TrafficManager
extends Node3D

const RoadGraphScript := preload("res://scripts/traffic/road_graph.gd")
const TrafficCarScene := preload("res://scenes/traffic/traffic_car.tscn")
const RESPAWN_CHECK_INTERVAL := 0.5

@export var graph_name: StringName = &"playground_ring"
@export_range(0, 32, 1) var max_cars: int = 6
@export var respawn_distance_from_player: float = 150.0
@export var min_car_speed: float = 8.0
@export var max_car_speed: float = 10.0
@export var spawn_on_ready: bool = true
@export var car_scene: PackedScene = TrafficCarScene

var road_graph: RefCounted

var _cars: Array[Node] = []
var _rng := RandomNumberGenerator.new()
var _respawn_timer := 0.0


func _ready() -> void:
	_rng.randomize()
	if road_graph == null:
		road_graph = RoadGraphScript.create_by_name(graph_name)
	if spawn_on_ready:
		_ensure_car_count()


func _physics_process(delta: float) -> void:
	_prune_invalid_cars()
	_ensure_car_count()

	_respawn_timer += delta
	if _respawn_timer < RESPAWN_CHECK_INTERVAL:
		return
	_respawn_timer = 0.0

	_respawn_far_cars()


func set_road_graph(graph: RefCounted) -> void:
	road_graph = graph
	for car in _cars:
		if car == null or not is_instance_valid(car):
			continue
		car.queue_free()
	_cars.clear()
	_ensure_car_count()


func get_cars() -> Array[Node]:
	_prune_invalid_cars()
	return _cars.duplicate()


func _ensure_car_count() -> void:
	if road_graph == null or road_graph.get_loop_count() == 0:
		return

	while _cars.size() < max_cars:
		_spawn_car(_cars.size())

	while _cars.size() > max_cars:
		var car: Node = _cars.pop_back() as Node
		if car != null and is_instance_valid(car):
			car.queue_free()


func _spawn_car(slot_index: int, near_position: Vector3 = Vector3(INF, INF, INF)) -> void:
	if car_scene == null or road_graph == null or road_graph.get_loop_count() == 0:
		return

	var loop_index: int = slot_index % road_graph.get_loop_count()
	var distance: float = _distance_for_slot(slot_index, loop_index)
	if near_position.x != INF:
		# RoadGraph nearest-loop queries are authored in true world coordinates.
		var nearest: Dictionary = road_graph.find_nearest_loop_distance(near_position)
		if int(nearest["loop_index"]) >= 0:
			loop_index = int(nearest["loop_index"])
			var offset := _rng.randf_range(-35.0, 35.0)
			distance = road_graph.wrap_distance(loop_index, float(nearest["distance"]) + offset)

	var car := car_scene.instantiate() as Node
	if car == null:
		return

	add_child(car)
	car.call(
		"configure",
		road_graph,
		loop_index,
		distance,
		_rng.randf_range(min_car_speed, max_car_speed)
	)
	_cars.append(car)


func _distance_for_slot(slot_index: int, loop_index: int) -> float:
	var loop_length: float = road_graph.get_loop_length(loop_index)
	if loop_length <= 0.001:
		return 0.0

	var cars_on_loop := maxi(1, ceili(float(max_cars) / float(road_graph.get_loop_count())))
	var index_on_loop := floori(float(slot_index) / float(road_graph.get_loop_count()))
	var spacing: float = loop_length / float(cars_on_loop)
	var jitter := _rng.randf_range(0.0, minf(6.0, spacing * 0.2))
	return road_graph.wrap_distance(loop_index, spacing * float(index_on_loop) + jitter)


func _respawn_far_cars() -> void:
	var players := _get_valid_players()
	if players.is_empty():
		return

	for index in range(_cars.size() - 1, -1, -1):
		var car := _cars[index] as Node3D
		if car == null or not is_instance_valid(car):
			_cars.remove_at(index)
			continue

		if _is_near_any_player(car.global_position, players):
			continue

		var nearest_player := _to_true_world_position(_nearest_player_position(car.global_position, players))
		_cars.remove_at(index)
		car.queue_free()
		_spawn_car(index, nearest_player)


func _get_valid_players() -> Array[Node3D]:
	var players: Array[Node3D] = []
	for player_node in get_tree().get_nodes_in_group("player"):
		var player := player_node as Node3D
		if player != null and is_instance_valid(player):
			players.append(player)
	return players


func _is_near_any_player(position: Vector3, players: Array[Node3D]) -> bool:
	var max_distance_sq := respawn_distance_from_player * respawn_distance_from_player
	for player in players:
		if player.global_position.distance_squared_to(position) <= max_distance_sq:
			return true
	return false


func _nearest_player_position(position: Vector3, players: Array[Node3D]) -> Vector3:
	var best_position := position
	var best_distance_sq := INF
	for player in players:
		var dist_sq := player.global_position.distance_squared_to(position)
		if dist_sq < best_distance_sq:
			best_distance_sq = dist_sq
			best_position = player.global_position
	return best_position


func _prune_invalid_cars() -> void:
	for index in range(_cars.size() - 1, -1, -1):
		var car := _cars[index]
		if car == null or not is_instance_valid(car):
			_cars.remove_at(index)


func _to_true_world_position(local_world_position: Vector3) -> Vector3:
	var origin := _floating_origin()
	if origin != null and origin.has_method("to_world"):
		return origin.call("to_world", local_world_position) as Vector3
	return local_world_position


func _floating_origin() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group(&"floating_origin")
