extends Mission

const OBJECTIVE_REACH := &"reach_city_east"
const TARGET_DISTRICT := &"city_east_a"

@export var target_district: StringName = TARGET_DISTRICT
@export var fallback_objective_position := Vector3(608.0, 0.12, 96.0)

var _zone_area: Area3D
var _current_vehicle: Node


func _init() -> void:
	mission_id = &"eastward"
	title = "Eastward"


func _ready() -> void:
	_configure_objectives()


func start() -> void:
	if objectives.is_empty():
		_configure_objectives()

	super.start()
	set_process(true)
	_connect_target_zone()
	_connect_events()


func get_objective_position():
	var zone := _zone_root_from_area(_zone_area)
	if zone != null:
		return zone.global_position
	return fallback_objective_position


func _process(_delta: float) -> void:
	if not is_active():
		set_process(false)
		return

	_connect_target_zone()


func _configure_objectives() -> void:
	set_objectives([
		{"id": OBJECTIVE_REACH, "text": "Drive east to the converted district"},
	])


func _connect_target_zone() -> void:
	var area := _find_target_zone_area()
	if area == null:
		return

	_zone_area = area
	var entered_callable := Callable(self, "_on_zone_body_entered")
	if not _zone_area.is_connected(&"body_entered", entered_callable):
		_zone_area.connect(&"body_entered", entered_callable)

	for body in _zone_area.get_overlapping_bodies():
		_on_zone_body_entered(body)


func _connect_events() -> void:
	var events := get_node_or_null("/root/Events")
	if events == null:
		return

	_connect_event(events, &"vehicle_entered", Callable(self, "_on_vehicle_entered"))
	_connect_event(events, &"vehicle_exited", Callable(self, "_on_vehicle_exited"))


func _connect_event(events: Node, signal_name: StringName, callback: Callable) -> void:
	if events.has_signal(signal_name) and not events.is_connected(signal_name, callback):
		events.connect(signal_name, callback)


func _find_target_zone_area() -> Area3D:
	for node in get_tree().get_nodes_in_group(&"conversion_zone"):
		var area := node as Area3D
		if area == null:
			continue

		var zone := _zone_root_from_area(area)
		if zone != null and _district_name_for(zone) == target_district:
			return area

	return null


func _on_zone_body_entered(body: Node3D) -> void:
	if not _is_player_body(body):
		return

	complete_objective(OBJECTIVE_REACH)
	set_process(false)


func _zone_root_from_area(area: Area3D) -> Node3D:
	var cursor := area as Node
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


func _is_player_body(body: Node3D) -> bool:
	if body == null:
		return false
	if body.is_in_group(&"player"):
		return true
	if _current_vehicle != null and body == _current_vehicle:
		return true
	return body.name == &"Body" and body.get_parent() != null and body.get_parent().name == &"Player"


func _on_vehicle_entered(vehicle: Node) -> void:
	_current_vehicle = vehicle


func _on_vehicle_exited(vehicle: Node) -> void:
	if vehicle == _current_vehicle:
		_current_vehicle = null
