class_name RoadGraph
extends RefCounted

const LANE_Y := 0.15
const LANE_OFFSET := 2.0

var graph_name: StringName = &""

var _loops: Array[PackedVector3Array] = []
var _loop_lengths: PackedFloat32Array = PackedFloat32Array()
var _segment_lengths: Array[PackedFloat32Array] = []


static func create_playground_ring() -> RefCounted:
	var graph := new()
	graph.graph_name = &"playground_ring"

	# Playground road centers are x +/-65 and z +/-50, with a 10 m road.
	# This clockwise lane is offset about 2 m to the right of each centerline.
	graph.add_loop(PackedVector3Array([
		Vector3(-65.0 + LANE_OFFSET, LANE_Y, -50.0 + LANE_OFFSET),
		Vector3(65.0 - LANE_OFFSET, LANE_Y, -50.0 + LANE_OFFSET),
		Vector3(65.0 - LANE_OFFSET, LANE_Y, 50.0 - LANE_OFFSET),
		Vector3(-65.0 + LANE_OFFSET, LANE_Y, 50.0 - LANE_OFFSET),
	]))

	return graph


static func create_district_grid() -> RefCounted:
	var graph := new()
	graph.graph_name = &"district_grid"

	# Tile district 2x2 world bounds: x 256..512, z 0..256.
	# Interior road centerlines land at x/z 320 and 448, with seam roads
	# at x/z 384 and 128. Loops are lane centers offset right by about 2 m.
	graph.add_loop(PackedVector3Array([
		Vector3(320.0 + LANE_OFFSET, LANE_Y, 64.0 + LANE_OFFSET),
		Vector3(448.0 - LANE_OFFSET, LANE_Y, 64.0 + LANE_OFFSET),
		Vector3(448.0 - LANE_OFFSET, LANE_Y, 192.0 - LANE_OFFSET),
		Vector3(320.0 + LANE_OFFSET, LANE_Y, 192.0 - LANE_OFFSET),
	]))

	graph.add_loop(PackedVector3Array([
		Vector3(384.0 + LANE_OFFSET, LANE_Y, 64.0 + LANE_OFFSET),
		Vector3(448.0 - LANE_OFFSET, LANE_Y, 64.0 + LANE_OFFSET),
		Vector3(448.0 - LANE_OFFSET, LANE_Y, 128.0 - LANE_OFFSET),
		Vector3(384.0 + LANE_OFFSET, LANE_Y, 128.0 - LANE_OFFSET),
	]))

	return graph


static func create_by_name(name: StringName) -> RefCounted:
	match name:
		&"city_grid", &"district_grid":
			return create_district_grid()
		&"playground_ring":
			return create_playground_ring()
		_:
			return create_playground_ring()


func add_loop(points: PackedVector3Array) -> int:
	var clean_points := PackedVector3Array()
	for point in points:
		clean_points.append(point)

	if clean_points.size() < 2:
		return -1

	_loops.append(clean_points)
	_rebuild_loop_lengths()
	return _loops.size() - 1


func get_loop_count() -> int:
	return _loops.size()


func get_loop_points(loop_index: int) -> PackedVector3Array:
	if not _is_valid_loop(loop_index):
		return PackedVector3Array()
	return _loops[loop_index]


func get_waypoint(loop_index: int, waypoint_index: int) -> Vector3:
	if not _is_valid_loop(loop_index):
		return Vector3.ZERO

	var loop := _loops[loop_index]
	if loop.is_empty():
		return Vector3.ZERO

	return loop[posmod(waypoint_index, loop.size())]


func get_next_waypoint_index(loop_index: int, waypoint_index: int) -> int:
	if not _is_valid_loop(loop_index):
		return -1

	var loop := _loops[loop_index]
	return posmod(waypoint_index + 1, loop.size())


func get_loop_length(loop_index: int) -> float:
	if loop_index < 0 or loop_index >= _loop_lengths.size():
		return 0.0
	return _loop_lengths[loop_index]


func wrap_distance(loop_index: int, distance: float) -> float:
	var length := get_loop_length(loop_index)
	if length <= 0.001:
		return 0.0
	return fposmod(distance, length)


func sample_position(loop_index: int, distance: float) -> Vector3:
	var segment := _sample_segment(loop_index, distance)
	if segment.is_empty():
		return Vector3.ZERO
	return segment["position"] as Vector3


func sample_forward(loop_index: int, distance: float) -> Vector3:
	var segment := _sample_segment(loop_index, distance)
	if segment.is_empty():
		return Vector3.FORWARD
	return segment["forward"] as Vector3


func find_nearest_loop_distance(world_position: Vector3) -> Dictionary:
	var best := {
		"loop_index": -1,
		"distance": 0.0,
		"position": Vector3.ZERO,
		"distance_squared": INF,
	}

	for loop_index in range(_loops.size()):
		var loop := _loops[loop_index]
		var segment_lengths := _segment_lengths[loop_index]
		var distance_at_segment_start := 0.0
		for point_index in range(loop.size()):
			var start := loop[point_index]
			var end := loop[(point_index + 1) % loop.size()]
			var closest_info := _closest_point_on_segment_xz(world_position, start, end)
			var dist_sq := float(closest_info["distance_squared"])
			if dist_sq < float(best["distance_squared"]):
				var t := float(closest_info["t"])
				best["loop_index"] = loop_index
				best["distance"] = distance_at_segment_start + segment_lengths[point_index] * t
				best["position"] = closest_info["position"] as Vector3
				best["distance_squared"] = dist_sq

			distance_at_segment_start += segment_lengths[point_index]

	return best


func _sample_segment(loop_index: int, distance: float) -> Dictionary:
	if not _is_valid_loop(loop_index):
		return {}

	var length := get_loop_length(loop_index)
	if length <= 0.001:
		return {}

	var remaining := wrap_distance(loop_index, distance)
	var loop := _loops[loop_index]
	var segment_lengths := _segment_lengths[loop_index]

	for point_index in range(loop.size()):
		var segment_length := segment_lengths[point_index]
		if segment_length <= 0.001:
			continue

		if remaining <= segment_length or point_index == loop.size() - 1:
			var start := loop[point_index]
			var end := loop[(point_index + 1) % loop.size()]
			var t := clampf(remaining / segment_length, 0.0, 1.0)
			var forward := (end - start).normalized()
			return {
				"position": start.lerp(end, t),
				"forward": forward,
				"waypoint_index": point_index,
			}

		remaining -= segment_length

	return {}


func _rebuild_loop_lengths() -> void:
	_loop_lengths = PackedFloat32Array()
	_segment_lengths.clear()

	for loop in _loops:
		var lengths := PackedFloat32Array()
		var total := 0.0
		for point_index in range(loop.size()):
			var segment_length := loop[point_index].distance_to(loop[(point_index + 1) % loop.size()])
			lengths.append(segment_length)
			total += segment_length

		_segment_lengths.append(lengths)
		_loop_lengths.append(total)


func _closest_point_on_segment_xz(point: Vector3, start: Vector3, end: Vector3) -> Dictionary:
	var flat_point := Vector3(point.x, 0.0, point.z)
	var flat_start := Vector3(start.x, 0.0, start.z)
	var flat_end := Vector3(end.x, 0.0, end.z)
	var segment := flat_end - flat_start
	var segment_length_sq := segment.length_squared()
	var t := 0.0
	if segment_length_sq > 0.001:
		t = clampf((flat_point - flat_start).dot(segment) / segment_length_sq, 0.0, 1.0)

	var closest := start.lerp(end, t)
	var flat_closest := Vector3(closest.x, 0.0, closest.z)
	return {
		"position": closest,
		"t": t,
		"distance_squared": flat_point.distance_squared_to(flat_closest),
	}


func _is_valid_loop(loop_index: int) -> bool:
	return loop_index >= 0 and loop_index < _loops.size()
