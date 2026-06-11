extends Mission

const OBJECTIVE_LIBERATE := &"liberate_city_east_a"
const TARGET_DISTRICT := &"city_east_a"

@export var district_name: StringName = TARGET_DISTRICT
@export var fallback_objective_position := Vector3(608.0, 0.12, 96.0)

var _events: Node
var _zone: Node3D


func _init() -> void:
	mission_id = &"block_party"
	title = "A Block Party"


func _ready() -> void:
	_configure_objectives()


func start() -> void:
	if objectives.is_empty():
		_configure_objectives()

	super.start()
	set_process(true)
	_connect_events()
	_refresh_zone()
	_check_existing_control()


func get_objective_position():
	_refresh_zone()
	if _zone != null:
		return _to_true_world_position(_zone.global_position)
	return fallback_objective_position


func _process(_delta: float) -> void:
	if not is_active():
		set_process(false)
		return

	_refresh_zone()
	_check_existing_control()


func _configure_objectives() -> void:
	set_objectives([
		{"id": OBJECTIVE_LIBERATE, "text": "Liberate city_east_a"},
	])


func _connect_events() -> void:
	_events = get_node_or_null("/root/Events")
	if _events == null:
		return

	var callback := Callable(self, "_on_district_control_changed")
	if _events.has_signal(&"district_control_changed") and not _events.is_connected(&"district_control_changed", callback):
		_events.connect(&"district_control_changed", callback)


func _on_district_control_changed(district: StringName, control: float) -> void:
	if not is_active() or district != district_name:
		return
	if control <= -1.0:
		complete_objective(OBJECTIVE_LIBERATE)
		set_process(false)


func _refresh_zone() -> void:
	if is_instance_valid(_zone):
		return

	for node in get_tree().get_nodes_in_group(&"conversion_zone"):
		var zone := _zone_root_from_node(node)
		if zone != null and _district_name_for(zone) == district_name:
			_zone = zone
			return


func _check_existing_control() -> void:
	if not is_instance_valid(_zone):
		return
	if _zone.has_method("get_control") and float(_zone.call("get_control")) <= -1.0:
		complete_objective(OBJECTIVE_LIBERATE)
		set_process(false)


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


func _to_true_world_position(local_world_position: Vector3) -> Vector3:
	var origin := _floating_origin()
	if origin != null and origin.has_method("to_world"):
		return origin.call("to_world", local_world_position) as Vector3
	return local_world_position


func _floating_origin() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group(&"floating_origin")
