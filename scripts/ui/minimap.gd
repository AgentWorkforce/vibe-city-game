extends Control

const CYAN := Color(0.098, 0.89, 0.89, 1.0)
const SOFT_WHITE := Color(0.94, 0.98, 1.0, 1.0)
const GLASS := Color(0.055, 0.11, 0.13, 0.58)
const GRID_COLOR := Color(0.94, 0.98, 1.0, 0.08)
const GRID_MAJOR_COLOR := Color(0.098, 0.89, 0.89, 0.16)
const WARM_PINK := Color(1.0, 0.38, 0.58, 1.0)
const WORLD_GRID_METERS := 20.0
const WORLD_MAJOR_GRID_METERS := 40.0
const DEFAULT_ZONE_SIZE := Vector2(30.0, 30.0)

@export var conversion_zone_path: NodePath
@export var world_min := Vector2(-100.0, -100.0)
@export var world_max := Vector2(100.0, 100.0)
@export var view_size_meters := 160.0
@export var update_interval := 0.1

var _player: Node3D
var _car: Node3D
var _conversion_zone: Node3D
var _zone_district := &""
var _liberated_districts := {}
var _map_center := Vector2.ZERO
var _events: Node
var _car_style: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_car_style = _make_car_style()
	_apply_panel_style()
	_connect_events()
	_start_update_timer()
	_on_update_tick()


func _draw() -> void:
	if size.x <= 2.0 or size.y <= 2.0:
		return

	var map_rect := Rect2(Vector2.ZERO, size)
	draw_rect(map_rect, Color(0.035, 0.08, 0.09, 0.36), true)
	_draw_grid(map_rect)
	_draw_conversion_zone(map_rect)
	_draw_agents(map_rect)
	_draw_car(map_rect)
	_draw_player(map_rect)
	draw_rect(map_rect.grow(-0.5), Color(CYAN.r, CYAN.g, CYAN.b, 0.34), false, 1.0, true)


func _start_update_timer() -> void:
	var timer := Timer.new()
	timer.wait_time = maxf(update_interval, 0.05)
	timer.one_shot = false
	timer.autostart = false
	timer.timeout.connect(_on_update_tick)
	add_child(timer)
	timer.start()


func _on_update_tick() -> void:
	_player = _find_first_node3d_in_group(&"player")
	_car = _find_car()
	_conversion_zone = _resolve_conversion_zone()
	_refresh_zone_state()
	_refresh_map_center()
	queue_redraw()


func _connect_events() -> void:
	_events = get_node_or_null("/root/Events")
	if not is_instance_valid(_events) or not _events.has_signal(&"district_control_changed"):
		return

	var callback := Callable(self, "_on_district_control_changed")
	if not _events.is_connected(&"district_control_changed", callback):
		_events.connect(&"district_control_changed", callback)


func _on_district_control_changed(district: StringName, control: float) -> void:
	if control <= -1.0:
		_liberated_districts[district] = true
	else:
		_liberated_districts.erase(district)
	queue_redraw()


func _refresh_map_center() -> void:
	if is_instance_valid(_player):
		_map_center = _clamp_center_to_bounds(_true_xz(_player.global_position))
	else:
		_map_center = (world_min + world_max) * 0.5


func _clamp_center_to_bounds(center: Vector2) -> Vector2:
	var half := view_size_meters * 0.5
	var clamped := center

	if world_max.x - world_min.x > view_size_meters:
		clamped.x = clampf(center.x, world_min.x + half, world_max.x - half)
	else:
		clamped.x = (world_min.x + world_max.x) * 0.5

	if world_max.y - world_min.y > view_size_meters:
		clamped.y = clampf(center.y, world_min.y + half, world_max.y - half)
	else:
		clamped.y = (world_min.y + world_max.y) * 0.5

	return clamped


func _draw_grid(map_rect: Rect2) -> void:
	var half := view_size_meters * 0.5
	var min_x := _map_center.x - half
	var max_x := _map_center.x + half
	var min_z := _map_center.y - half
	var max_z := _map_center.y + half

	var x := floorf(min_x / WORLD_GRID_METERS) * WORLD_GRID_METERS
	while x <= max_x + 0.01:
		var point := _world_to_map(Vector2(x, _map_center.y), map_rect)
		var color := GRID_MAJOR_COLOR if _is_major_grid_line(x) else GRID_COLOR
		draw_line(Vector2(point.x, map_rect.position.y), Vector2(point.x, map_rect.end.y), color, 1.0, true)
		x += WORLD_GRID_METERS

	var z := floorf(min_z / WORLD_GRID_METERS) * WORLD_GRID_METERS
	while z <= max_z + 0.01:
		var point := _world_to_map(Vector2(_map_center.x, z), map_rect)
		var color := GRID_MAJOR_COLOR if _is_major_grid_line(z) else GRID_COLOR
		draw_line(Vector2(map_rect.position.x, point.y), Vector2(map_rect.end.x, point.y), color, 1.0, true)
		z += WORLD_GRID_METERS


func _is_major_grid_line(value: float) -> bool:
	return absf(roundf(value / WORLD_MAJOR_GRID_METERS) * WORLD_MAJOR_GRID_METERS - value) < 0.01


func _draw_conversion_zone(map_rect: Rect2) -> void:
	if not is_instance_valid(_conversion_zone):
		return

	var zone_rect := _zone_footprint_rect()
	if zone_rect.size.x <= 0.0 or zone_rect.size.y <= 0.0:
		return

	var map_a := _world_to_map(zone_rect.position, map_rect)
	var map_b := _world_to_map(zone_rect.position + zone_rect.size, map_rect)
	var draw_position := Vector2(minf(map_a.x, map_b.x), minf(map_a.y, map_b.y))
	var draw_size := Vector2(absf(map_b.x - map_a.x), absf(map_b.y - map_a.y))
	var map_zone_rect := Rect2(draw_position, draw_size)
	var clipped_rect := map_zone_rect.intersection(map_rect)
	if clipped_rect.size.x <= 0.0 or clipped_rect.size.y <= 0.0:
		return

	var zone_color := WARM_PINK if _is_zone_liberated() else CYAN
	draw_rect(clipped_rect, Color(zone_color.r, zone_color.g, zone_color.b, 0.20), true)
	draw_rect(clipped_rect, Color(zone_color.r, zone_color.g, zone_color.b, 0.72), false, 2.0, true)


func _draw_agents(map_rect: Rect2) -> void:
	for node in get_tree().get_nodes_in_group(&"agents"):
		var agent := node as Node3D
		if agent == null:
			continue

		var point := _world_to_map(_true_xz(agent.global_position), map_rect)
		if not map_rect.has_point(point):
			continue

		# Police agents expose the player_caught signal, and existing scenes also
		# add them to the police group. Either marker keeps this UI read-only.
		if _is_police_agent(agent):
			draw_circle(point, 7.0, Color(CYAN.r, CYAN.g, CYAN.b, 0.18))
			draw_arc(point, 7.0, 0.0, TAU, 24, Color(CYAN.r, CYAN.g, CYAN.b, 0.78), 1.4, true)

		draw_circle(point, 3.4, SOFT_WHITE)
		draw_circle(point, 1.6, Color(CYAN.r, CYAN.g, CYAN.b, 0.82))


func _draw_car(map_rect: Rect2) -> void:
	if not is_instance_valid(_car):
		return

	var point := _world_to_map(_true_xz(_car.global_position), map_rect)
	if not map_rect.has_point(point):
		return

	var icon_rect := Rect2(point - Vector2(7.0, 4.5), Vector2(14.0, 9.0))
	draw_style_box(_car_style, icon_rect)

	var forward := _forward_xz(_car)
	if forward.length_squared() > 0.01:
		draw_line(point, point + forward.normalized() * 9.0, Color(CYAN.r, CYAN.g, CYAN.b, 0.78), 1.4, true)


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
		point + direction * 10.5,
		point - direction * 7.0 + side * 5.7,
		point - direction * 7.0 - side * 5.7,
	])
	draw_polygon(points, PackedColorArray([CYAN, CYAN, CYAN]))
	draw_polyline(PackedVector2Array([points[0], points[1], points[2], points[0]]), SOFT_WHITE, 1.25, true)


func _world_to_map(world_xz: Vector2, map_rect: Rect2) -> Vector2:
	var pixels_per_meter := minf(map_rect.size.x, map_rect.size.y) / maxf(view_size_meters, 1.0)
	return map_rect.position + map_rect.size * 0.5 + (world_xz - _map_center) * pixels_per_meter


func _zone_footprint_rect() -> Rect2:
	var shape_rect := _box_shape_footprint(_conversion_zone)
	if shape_rect.size.x > 0.0 and shape_rect.size.y > 0.0:
		return shape_rect

	var plane_rect := _plane_mesh_footprint(_conversion_zone)
	if plane_rect.size.x > 0.0 and plane_rect.size.y > 0.0:
		return plane_rect

	var center := _true_xz(_conversion_zone.global_position)
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
		elif shape_node.get_parent() != null and shape_node.get_parent().name == &"ZoneArea":
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


func _resolve_conversion_zone() -> Node3D:
	var explicit_node: Node = null
	if not String(conversion_zone_path).is_empty():
		explicit_node = get_node_or_null(conversion_zone_path)
	var explicit_zone := _zone_root_from_node(explicit_node)
	if explicit_zone != null:
		return explicit_zone

	for node in get_tree().get_nodes_in_group(&"conversion_zone"):
		var grouped_zone := _zone_root_from_node(node)
		if grouped_zone != null:
			return grouped_zone

	var current_scene := get_tree().current_scene
	if current_scene != null:
		var playground_zone := _zone_root_from_node(current_scene.get_node_or_null("Playground/ConversionZone"))
		if playground_zone != null:
			return playground_zone

	return _zone_root_from_node(get_tree().root.find_child("ConversionZone", true, false))


func _zone_root_from_node(node: Node) -> Node3D:
	var current := node
	while current != null:
		var node3d := current as Node3D
		if node3d == null:
			return null
		if node3d.name == &"ConversionZone":
			return node3d
		current = current.get_parent()

	return node as Node3D


func _refresh_zone_state() -> void:
	_zone_district = &""
	if not is_instance_valid(_conversion_zone):
		return

	var district_value: Variant = _conversion_zone.get("district_name")
	if district_value != null:
		_zone_district = StringName(str(district_value))

	if _zone_district == &"":
		return

	if _conversion_zone.has_method("get_control") and float(_conversion_zone.call("get_control")) <= -1.0:
		_liberated_districts[_zone_district] = true
	elif _conversion_zone.has_method("is_liberated") and bool(_conversion_zone.call("is_liberated")):
		_liberated_districts[_zone_district] = true


func _is_zone_liberated() -> bool:
	return _zone_district != &"" and bool(_liberated_districts.get(_zone_district, false))


func _find_first_node3d_in_group(group_name: StringName) -> Node3D:
	for node in get_tree().get_nodes_in_group(group_name):
		var node3d := node as Node3D
		if node3d != null:
			return node3d
	return null


func _find_car() -> Node3D:
	if is_instance_valid(_car):
		return _car

	var current_scene := get_tree().current_scene
	if current_scene != null:
		var scene_car := current_scene.find_child("Car", true, false) as Node3D
		if scene_car != null:
			return scene_car

	return get_tree().root.find_child("Car", true, false) as Node3D


func _is_police_agent(agent: Node) -> bool:
	return agent.is_in_group(&"police") or agent.has_signal(&"player_caught")


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


func _apply_panel_style() -> void:
	var current := get_parent()
	while current != null:
		var panel := current as PanelContainer
		if panel != null:
			panel.add_theme_stylebox_override("panel", _make_panel_style())
			return
		current = current.get_parent()


func _make_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = GLASS
	style.border_color = Color(CYAN.r, CYAN.g, CYAN.b, 0.46)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.shadow_color = Color(0.0, 0.08, 0.09, 0.30)
	style.shadow_size = 10
	style.shadow_offset = Vector2(0.0, 2.0)
	return style


func _make_car_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.94, 0.98, 1.0, 0.76)
	style.border_color = Color(CYAN.r, CYAN.g, CYAN.b, 0.88)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	return style
