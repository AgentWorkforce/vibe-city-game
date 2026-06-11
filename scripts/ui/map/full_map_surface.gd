extends Control

const CYAN := Color(0.098, 0.89, 0.89, 1.0)
const SOFT_WHITE := Color(0.94, 0.98, 1.0, 1.0)
const GRID_COLOR := Color(0.94, 0.98, 1.0, 0.07)
const GRID_MAJOR_COLOR := Color(0.098, 0.89, 0.89, 0.18)
const HUMAN_WARM := Color(1.0, 0.48, 0.35, 1.0)
const OBJECTIVE_COLOR := Color(1.0, 0.38, 0.58, 1.0)
const WORLD_GRID_METERS := 64.0
const WORLD_MAJOR_GRID_METERS := 128.0
const DEFAULT_ZONE_SIZE := Vector2(30.0, 30.0)
const FALLBACK_DISTRICT_RECTS := {
	&"playground_nw": Rect2(Vector2(-57.0, -47.0), Vector2(30.0, 30.0)),
	&"city_east_a": Rect2(Vector2(593.0, 81.0), Vector2(30.0, 30.0)),
	&"city_east_b": Rect2(Vector2(589.0, 209.0), Vector2(30.0, 30.0)),
}

@export var world_min := Vector2(-128.0, -128.0)
@export var world_max := Vector2(768.0, 256.0)
@export var update_interval := 0.18

var _player: Node3D
var _agents: Array[Node3D] = []
var _vehicles: Array[Node3D] = []
var _districts: Array[Dictionary] = []
var _known_controls := {}
var _active_mission: Node
var _objective_position: Variant = null
var _refresh_seconds := 0.0
var _pulse_seconds := 0.0
var _car_style: StyleBoxFlat
var _events: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_car_style = _make_car_style()
	_connect_events()
	_refresh_state()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return

	_pulse_seconds += delta
	_refresh_seconds += delta
	if _refresh_seconds >= update_interval:
		_refresh_seconds = 0.0
		_refresh_state()
	queue_redraw()


func _draw() -> void:
	if size.x <= 4.0 or size.y <= 4.0:
		return

	var full_rect := Rect2(Vector2.ZERO, size)
	draw_rect(full_rect, Color(0.025, 0.065, 0.072, 0.88), true)

	var map_rect := _fit_world_rect(full_rect.grow(-8.0))
	draw_rect(map_rect, Color(0.03, 0.08, 0.09, 0.72), true)
	_draw_grid(map_rect)
	_draw_districts(map_rect)
	_draw_vehicles(map_rect)
	_draw_agents(map_rect)
	_draw_objective(map_rect)
	_draw_player(map_rect)
	draw_rect(map_rect.grow(-0.5), Color(CYAN.r, CYAN.g, CYAN.b, 0.48), false, 1.5, true)


func _connect_events() -> void:
	_events = get_node_or_null("/root/Events")
	if _events == null:
		return

	_connect_event(&"district_control_changed", Callable(self, "_on_district_control_changed"))
	_connect_event(&"mission_started", Callable(self, "_on_mission_event"))
	_connect_event(&"mission_completed", Callable(self, "_on_mission_event"))
	_connect_event(&"mission_failed", Callable(self, "_on_mission_failed"))


func _connect_event(signal_name: StringName, callback: Callable) -> void:
	if _events.has_signal(signal_name) and not _events.is_connected(signal_name, callback):
		_events.connect(signal_name, callback)


func _on_district_control_changed(district: StringName, control: float) -> void:
	_known_controls[district] = control
	_refresh_state()
	queue_redraw()


func _on_mission_event(_mission: Node) -> void:
	_refresh_state()
	queue_redraw()


func _on_mission_failed(_mission: Node, _reason: String) -> void:
	_refresh_state()
	queue_redraw()


func _refresh_state() -> void:
	_player = _find_player()
	_agents = _collect_group_node3d(&"agents")
	_vehicles = _collect_vehicles()
	_refresh_districts()
	_refresh_active_objective()


func _refresh_districts() -> void:
	_districts.clear()
	var seen := {}

	for node in get_tree().get_nodes_in_group(&"conversion_zone"):
		var zone := _zone_root_from_node(node)
		if zone == null:
			continue

		var district_name := _district_name_for(zone)
		if district_name == &"":
			continue

		var district_key := String(district_name)
		if seen.has(district_key):
			continue
		seen[district_key] = true

		var zone_rect := _zone_footprint_rect(zone)
		if zone_rect.size.x <= 0.0 or zone_rect.size.y <= 0.0:
			continue

		_districts.append({
			"district": district_name,
			"rect": zone_rect,
			"control": _control_for_zone(zone, district_name),
		})

	for district_name in FALLBACK_DISTRICT_RECTS.keys():
		var district_key := String(district_name)
		if seen.has(district_key):
			continue

		_districts.append({
			"district": district_name,
			"rect": FALLBACK_DISTRICT_RECTS[district_name],
			"control": float(_known_controls.get(district_name, 1.0)),
		})


func _refresh_active_objective() -> void:
	_active_mission = null
	_objective_position = null

	var missions := get_node_or_null("/root/Missions")
	if missions == null or not missions.has_method("get_active_mission"):
		return

	_active_mission = missions.call("get_active_mission") as Node
	if _active_mission == null or not _active_mission.has_method("get_objective_position"):
		return

	var position_value: Variant = _active_mission.call("get_objective_position")
	if position_value is Vector3:
		var position := position_value as Vector3
		if _is_valid_world_position(position):
			_objective_position = position


func _draw_grid(map_rect: Rect2) -> void:
	var x := floorf(world_min.x / WORLD_GRID_METERS) * WORLD_GRID_METERS
	while x <= world_max.x + 0.01:
		var point := _world_to_map(Vector2(x, world_min.y), map_rect)
		var color := GRID_MAJOR_COLOR if _is_major_grid_line(x) else GRID_COLOR
		draw_line(Vector2(point.x, map_rect.position.y), Vector2(point.x, map_rect.end.y), color, 1.0, true)
		x += WORLD_GRID_METERS

	var z := floorf(world_min.y / WORLD_GRID_METERS) * WORLD_GRID_METERS
	while z <= world_max.y + 0.01:
		var point := _world_to_map(Vector2(world_min.x, z), map_rect)
		var color := GRID_MAJOR_COLOR if _is_major_grid_line(z) else GRID_COLOR
		draw_line(Vector2(map_rect.position.x, point.y), Vector2(map_rect.end.x, point.y), color, 1.0, true)
		z += WORLD_GRID_METERS


func _draw_districts(map_rect: Rect2) -> void:
	for entry in _districts:
		var world_rect: Rect2 = entry.get("rect", Rect2())
		var clipped_world_rect := world_rect.intersection(Rect2(world_min, world_max - world_min))
		if clipped_world_rect.size.x <= 0.0 or clipped_world_rect.size.y <= 0.0:
			continue

		var screen_rect := _world_rect_to_map(clipped_world_rect, map_rect)
		var control := clampf(float(entry.get("control", 1.0)), -1.0, 1.0)
		var zone_color := _district_color(control)
		draw_rect(screen_rect, Color(zone_color.r, zone_color.g, zone_color.b, 0.16 + absf(control) * 0.09), true)
		draw_rect(screen_rect, Color(zone_color.r, zone_color.g, zone_color.b, 0.70), false, 2.0, true)


func _draw_agents(map_rect: Rect2) -> void:
	for agent in _agents:
		if not is_instance_valid(agent):
			continue

		var point := _world_to_map(_true_xz(agent.global_position), map_rect)
		if not map_rect.has_point(point):
			continue

		if _is_police_agent(agent):
			draw_circle(point, 6.0, Color(CYAN.r, CYAN.g, CYAN.b, 0.18))
			draw_arc(point, 6.0, 0.0, TAU, 24, Color(CYAN.r, CYAN.g, CYAN.b, 0.78), 1.3, true)

		draw_circle(point, 3.0, SOFT_WHITE)
		draw_circle(point, 1.35, Color(CYAN.r, CYAN.g, CYAN.b, 0.88))


func _draw_vehicles(map_rect: Rect2) -> void:
	for vehicle in _vehicles:
		if not is_instance_valid(vehicle):
			continue

		var point := _world_to_map(_true_xz(vehicle.global_position), map_rect)
		if not map_rect.has_point(point):
			continue

		draw_style_box(_car_style, Rect2(point - Vector2(7.0, 4.5), Vector2(14.0, 9.0)))
		var forward := _forward_xz(vehicle)
		if forward.length_squared() > 0.01:
			draw_line(point, point + forward.normalized() * 10.0, Color(CYAN.r, CYAN.g, CYAN.b, 0.78), 1.4, true)


func _draw_player(map_rect: Rect2) -> void:
	if not is_instance_valid(_player):
		return

	var point := _world_to_map(_true_xz(_player.global_position), map_rect)
	if not map_rect.has_point(point):
		return

	var forward := _forward_xz(_player)
	if forward.length_squared() <= 0.01:
		forward = Vector2(0.0, -1.0)

	var direction := forward.normalized()
	var side := Vector2(-direction.y, direction.x)
	var points := PackedVector2Array([
		point + direction * 11.0,
		point - direction * 7.0 + side * 5.8,
		point - direction * 7.0 - side * 5.8,
	])
	draw_polygon(points, PackedColorArray([CYAN, CYAN, CYAN]))
	draw_polyline(PackedVector2Array([points[0], points[1], points[2], points[0]]), SOFT_WHITE, 1.25, true)


func _draw_objective(map_rect: Rect2) -> void:
	if not (_objective_position is Vector3):
		return

	var objective := _objective_position as Vector3
	var point := _world_to_map(_xz(objective), map_rect)
	if not map_rect.has_point(point):
		return

	var pulse := (sin(_pulse_seconds * TAU * 1.35) + 1.0) * 0.5
	var radius := 8.0 + pulse * 5.0
	draw_circle(point, radius, Color(OBJECTIVE_COLOR.r, OBJECTIVE_COLOR.g, OBJECTIVE_COLOR.b, 0.16))
	draw_arc(point, radius, 0.0, TAU, 36, Color(OBJECTIVE_COLOR.r, OBJECTIVE_COLOR.g, OBJECTIVE_COLOR.b, 0.86), 2.0, true)
	draw_line(point + Vector2(-5.0, 0.0), point + Vector2(5.0, 0.0), SOFT_WHITE, 1.4, true)
	draw_line(point + Vector2(0.0, -5.0), point + Vector2(0.0, 5.0), SOFT_WHITE, 1.4, true)


func _fit_world_rect(rect: Rect2) -> Rect2:
	var world_size := world_max - world_min
	if world_size.x <= 0.0 or world_size.y <= 0.0:
		return rect

	var world_aspect := world_size.x / world_size.y
	var rect_aspect := rect.size.x / maxf(rect.size.y, 1.0)
	if rect_aspect > world_aspect:
		var width := rect.size.y * world_aspect
		return Rect2(Vector2(rect.position.x + (rect.size.x - width) * 0.5, rect.position.y), Vector2(width, rect.size.y))

	var height := rect.size.x / world_aspect
	return Rect2(Vector2(rect.position.x, rect.position.y + (rect.size.y - height) * 0.5), Vector2(rect.size.x, height))


func _world_to_map(world_xz: Vector2, map_rect: Rect2) -> Vector2:
	var world_size := world_max - world_min
	var normalized := Vector2(
		(world_xz.x - world_min.x) / maxf(world_size.x, 1.0),
		(world_xz.y - world_min.y) / maxf(world_size.y, 1.0)
	)
	return map_rect.position + normalized * map_rect.size


func _world_rect_to_map(world_rect: Rect2, map_rect: Rect2) -> Rect2:
	var map_a := _world_to_map(world_rect.position, map_rect)
	var map_b := _world_to_map(world_rect.position + world_rect.size, map_rect)
	var draw_position := Vector2(minf(map_a.x, map_b.x), minf(map_a.y, map_b.y))
	var draw_size := Vector2(absf(map_b.x - map_a.x), absf(map_b.y - map_a.y))
	return Rect2(draw_position, draw_size)


func _is_major_grid_line(value: float) -> bool:
	return absf(roundf(value / WORLD_MAJOR_GRID_METERS) * WORLD_MAJOR_GRID_METERS - value) < 0.01


func _district_color(control: float) -> Color:
	var t := clampf((control + 1.0) * 0.5, 0.0, 1.0)
	return HUMAN_WARM.lerp(CYAN, t)


func _control_for_zone(zone: Node, district_name: StringName) -> float:
	if zone != null and zone.has_method("get_control"):
		var control := float(zone.call("get_control"))
		_known_controls[district_name] = control
		return control
	return float(_known_controls.get(district_name, 1.0))


func _zone_footprint_rect(zone: Node3D) -> Rect2:
	var shape_rect := _box_shape_footprint(zone)
	if shape_rect.size.x > 0.0 and shape_rect.size.y > 0.0:
		return shape_rect

	var plane_rect := _plane_mesh_footprint(zone)
	if plane_rect.size.x > 0.0 and plane_rect.size.y > 0.0:
		return plane_rect

	var center := _true_xz(zone.global_position)
	return Rect2(center - DEFAULT_ZONE_SIZE * 0.5, DEFAULT_ZONE_SIZE)


func _box_shape_footprint(root: Node) -> Rect2:
	if root == null:
		return Rect2()

	var best_rect := Rect2()
	var best_score := 0.0
	for node in root.find_children("*", "CollisionShape3D", true, false):
		var shape_node := node as CollisionShape3D
		if shape_node == null:
			continue

		var box := shape_node.shape as BoxShape3D
		if box == null:
			continue

		var scale := shape_node.global_transform.basis.get_scale()
		var footprint := Vector2(absf(box.size.x * scale.x), absf(box.size.z * scale.z))
		var rect := Rect2(_true_xz(shape_node.global_position) - footprint * 0.5, footprint)
		var score := footprint.x * footprint.y
		if shape_node.get_parent() != null and shape_node.get_parent().is_in_group(&"conversion_zone"):
			score += 1000000.0

		if score > best_score:
			best_score = score
			best_rect = rect

	return best_rect


func _plane_mesh_footprint(root: Node) -> Rect2:
	if root == null:
		return Rect2()

	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node == null:
			continue

		var plane := mesh_node.mesh as PlaneMesh
		if plane == null:
			continue

		var scale := mesh_node.global_transform.basis.get_scale()
		var footprint := Vector2(absf(plane.size.x * scale.x), absf(plane.size.y * scale.z))
		return Rect2(_true_xz(mesh_node.global_position) - footprint * 0.5, footprint)

	return Rect2()


func _zone_root_from_node(node: Node) -> Node3D:
	var cursor := node
	while cursor != null:
		var node3d := cursor as Node3D
		if node3d != null and node3d.has_method("get_control") and _district_name_for(node3d) != &"":
			return node3d
		cursor = cursor.get_parent()
	return null


func _district_name_for(node: Node) -> StringName:
	if node == null:
		return &""

	var value: Variant = node.get("district_name")
	if value == null:
		return &""
	return StringName(str(value))


func _find_player() -> Node3D:
	for node in get_tree().get_nodes_in_group(&"player"):
		var node3d := node as Node3D
		if node3d != null:
			return node3d
	return null


func _collect_group_node3d(group_name: StringName) -> Array[Node3D]:
	var result: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group(group_name):
		var node3d := node as Node3D
		if node3d != null:
			result.append(node3d)
	return result


func _collect_vehicles() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for node in get_tree().root.find_children("*", "VehicleBody3D", true, false):
		var vehicle := node as Node3D
		if vehicle != null:
			result.append(vehicle)
	return result


func _is_police_agent(agent: Node) -> bool:
	return agent.is_in_group(&"police") or agent.has_signal(&"player_caught")


func _is_valid_world_position(position: Vector3) -> bool:
	return absf(position.x) < 999999.0 and absf(position.y) < 999999.0 and absf(position.z) < 999999.0


func _forward_xz(node: Node3D) -> Vector2:
	var forward := -node.global_transform.basis.z
	return Vector2(forward.x, forward.z)


func _xz(position: Vector3) -> Vector2:
	return Vector2(position.x, position.z)


func _true_xz(local_world_position: Vector3) -> Vector2:
	return _xz(_to_true_world_position(local_world_position))


func _to_true_world_position(local_world_position: Vector3) -> Vector3:
	var origin := _floating_origin()
	if origin != null and origin.has_method("to_world"):
		return origin.call("to_world", local_world_position) as Vector3
	return local_world_position


func _floating_origin() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group(&"floating_origin")


func _make_car_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.94, 0.98, 1.0, 0.76)
	style.border_color = Color(CYAN.r, CYAN.g, CYAN.b, 0.88)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	return style
