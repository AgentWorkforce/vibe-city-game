extends Node3D

# Tile scenes are authored at root-local origin. The streamer owns world placement:
# tile_{X}_{Z}.tscn is placed at X * tile_size, 0, Z * tile_size.
const TILE_PATH_TEMPLATE := "res://scenes/city/tiles/tile_%d_%d.tscn"
const STREAM_INTERVAL_SECONDS := 0.25
const MAX_REQUESTS_PER_STREAM_TICK := 8

@export var tile_size: float = 128.0
@export var load_radius_tiles: int = 2
@export var unload_radius_tiles: int = 3
@export var target_path: NodePath

var _target: Node3D
var _stream_timer := 0.0
var _last_target_position := Vector3.ZERO
var _target_velocity := Vector3.ZERO
var _current_target_tile := Vector2i.ZERO

var _loaded_tiles: Dictionary = {}
var _in_flight_tiles: Dictionary = {}
var _ready_tiles: Array[Dictionary] = []
var _missing_tiles: Dictionary = {}
var _request_queue: Array[Vector2i] = []


func _ready() -> void:
	_resolve_target()
	if is_instance_valid(_target):
		_last_target_position = _target.global_position
		_current_target_tile = world_to_tile_coord(_last_target_position)
	_update_streaming()


func _process(delta: float) -> void:
	_resolve_target()
	_poll_threaded_loads()
	_instantiate_one_ready_tile()

	if not is_instance_valid(_target):
		return

	_stream_timer += delta
	if _stream_timer < STREAM_INTERVAL_SECONDS:
		return

	var elapsed := _stream_timer
	_stream_timer = 0.0
	var target_position := _target.global_position
	_target_velocity = (target_position - _last_target_position) / maxf(elapsed, 0.001)
	_last_target_position = target_position
	_current_target_tile = world_to_tile_coord(target_position)
	_update_streaming()


func world_to_tile_coord(world_position: Vector3) -> Vector2i:
	# TODO(M3 floating origin): account for origin shifts here and adjust
	# _last_target_position so shifts do not create phantom velocity spikes.
	return Vector2i(floori(world_position.x / tile_size), floori(world_position.z / tile_size))


func get_resident_tile_count() -> int:
	return _loaded_tiles.size()


func get_resident_tile_coords() -> Array[Vector2i]:
	var coords: Array[Vector2i] = []
	for coord in _loaded_tiles.keys():
		coords.append(coord)
	coords.sort_custom(Callable(self, "_compare_coords"))
	return coords


func get_loads_in_flight_count() -> int:
	return _in_flight_tiles.size()


func get_pending_load_count() -> int:
	return _request_queue.size()


func get_known_missing_count() -> int:
	return _missing_tiles.size()


func is_tile_resident(coord: Vector2i) -> bool:
	return _loaded_tiles.has(coord)


func has_known_missing_tile(coord: Vector2i) -> bool:
	return _missing_tiles.has(coord)


func _resolve_target() -> void:
	if is_instance_valid(_target):
		return
	if target_path.is_empty():
		return
	_target = get_node_or_null(target_path) as Node3D


func _update_streaming() -> void:
	if tile_size <= 0.0:
		return

	_unload_distant_tiles()
	var wanted_tiles := _get_tiles_within_radius(_current_target_tile, load_radius_tiles)
	_enqueue_missing_resident_tiles(wanted_tiles)
	_sort_request_queue()
	_start_queued_requests()


func _get_tiles_within_radius(center: Vector2i, radius: int) -> Array[Vector2i]:
	var coords: Array[Vector2i] = []
	for z in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			coords.append(Vector2i(x, z))
	return coords


func _enqueue_missing_resident_tiles(coords: Array[Vector2i]) -> void:
	for coord in coords:
		if _loaded_tiles.has(coord) or _in_flight_tiles.has(coord) or _missing_tiles.has(coord):
			continue
		if _request_queue.has(coord):
			continue

		var tile_path := _tile_path(coord)
		if not ResourceLoader.exists(tile_path, "PackedScene"):
			_missing_tiles[coord] = true
			continue

		_request_queue.append(coord)


func _sort_request_queue() -> void:
	_request_queue.sort_custom(Callable(self, "_compare_load_priority"))


func _start_queued_requests() -> void:
	var requests_started := 0
	while not _request_queue.is_empty() and requests_started < MAX_REQUESTS_PER_STREAM_TICK:
		var coord: Vector2i = _request_queue.pop_front()
		if _loaded_tiles.has(coord) or _in_flight_tiles.has(coord):
			continue
		if not _is_within_unload_radius(coord):
			continue

		var tile_path := _tile_path(coord)
		var err := ResourceLoader.load_threaded_request(tile_path, "PackedScene")
		if err != OK:
			_missing_tiles[coord] = true
			continue

		_in_flight_tiles[coord] = tile_path
		requests_started += 1


func _poll_threaded_loads() -> void:
	if _in_flight_tiles.is_empty():
		return

	var completed: Array[Vector2i] = []
	for coord in _in_flight_tiles.keys():
		var tile_path := String(_in_flight_tiles[coord])
		var status := ResourceLoader.load_threaded_get_status(tile_path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue

		completed.append(coord)
		if status != ResourceLoader.THREAD_LOAD_LOADED:
			_missing_tiles[coord] = true
			continue

		var scene := ResourceLoader.load_threaded_get(tile_path) as PackedScene
		if scene != null:
			_ready_tiles.append({"coord": coord, "scene": scene})

	for coord in completed:
		_in_flight_tiles.erase(coord)

	_ready_tiles.sort_custom(Callable(self, "_compare_ready_priority"))


func _instantiate_one_ready_tile() -> void:
	if _ready_tiles.is_empty():
		return

	var entry: Dictionary = _ready_tiles.pop_front()
	var coord := entry["coord"] as Vector2i
	if _loaded_tiles.has(coord):
		return
	if not _is_within_unload_radius(coord):
		return

	var scene := entry["scene"] as PackedScene
	if scene == null:
		_missing_tiles[coord] = true
		return

	var tile := scene.instantiate() as Node3D
	if tile == null:
		_missing_tiles[coord] = true
		return

	tile.position = Vector3(coord.x * tile_size, 0.0, coord.y * tile_size)
	add_child(tile)
	_loaded_tiles[coord] = tile


func _unload_distant_tiles() -> void:
	var unload_coords: Array[Vector2i] = []
	for coord in _loaded_tiles.keys():
		if not _is_within_unload_radius(coord):
			unload_coords.append(coord)

	for coord in unload_coords:
		var tile := _loaded_tiles[coord] as Node
		_loaded_tiles.erase(coord)
		if is_instance_valid(tile):
			tile.queue_free()


func _is_within_unload_radius(coord: Vector2i) -> bool:
	var delta := coord - _current_target_tile
	return maxi(abs(delta.x), abs(delta.y)) <= unload_radius_tiles


func _tile_path(coord: Vector2i) -> String:
	return TILE_PATH_TEMPLATE % [coord.x, coord.y]


func _tile_center(coord: Vector2i) -> Vector3:
	return Vector3((float(coord.x) + 0.5) * tile_size, 0.0, (float(coord.y) + 0.5) * tile_size)


func _tile_priority(coord: Vector2i) -> float:
	if coord == _current_target_tile:
		return -100000.0

	var target_position := _last_target_position
	var to_tile := _tile_center(coord) - target_position
	to_tile.y = 0.0
	var distance := to_tile.length()
	if _target_velocity.length_squared() <= 0.01 or distance <= 0.001:
		return distance

	var velocity := _target_velocity
	velocity.y = 0.0
	var directional_bias := to_tile.normalized().dot(velocity.normalized())
	return distance - directional_bias * tile_size * 2.0


func _compare_load_priority(a: Vector2i, b: Vector2i) -> bool:
	var a_priority := _tile_priority(a)
	var b_priority := _tile_priority(b)
	if is_equal_approx(a_priority, b_priority):
		return _compare_coords(a, b)
	return a_priority < b_priority


func _compare_ready_priority(a: Dictionary, b: Dictionary) -> bool:
	return _compare_load_priority(a["coord"] as Vector2i, b["coord"] as Vector2i)


func _compare_coords(a: Vector2i, b: Vector2i) -> bool:
	if a.x == b.x:
		return a.y < b.y
	return a.x < b.x
