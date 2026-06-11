extends Mission

const OBJECTIVE_VISIT := &"visit_converted_zone"
const OBJECTIVE_DISCONNECT := &"disconnect_pylons"
const FAILURE_CAUGHT := "politely detained"

@export var district_name: StringName = &"playground_nw"

var _zone_area: Area3D
var _events: Node


func _init() -> void:
	mission_id = &"liberate_nw"
	title = "A Gentle Unwelcome"


func _ready() -> void:
	_configure_objectives()


func start() -> void:
	if objectives.is_empty():
		_configure_objectives()

	super.start()
	_connect_zone()
	_connect_events()
	_check_existing_control()


func _configure_objectives() -> void:
	set_objectives([
		{"id": OBJECTIVE_VISIT, "text": "Visit the converted zone"},
		{"id": OBJECTIVE_DISCONNECT, "text": "Disconnect all conversion pylons"},
	])


func _connect_zone() -> void:
	_zone_area = _find_conversion_zone()
	if _zone_area == null:
		return

	var entered_callable := Callable(self, "_on_zone_body_entered")
	if not _zone_area.is_connected(&"body_entered", entered_callable):
		_zone_area.connect(&"body_entered", entered_callable)

	for body in _zone_area.get_overlapping_bodies():
		_on_zone_body_entered(body)


func _connect_events() -> void:
	_events = get_node_or_null("/root/Events")
	if _events == null:
		return

	_connect_event(&"district_control_changed", Callable(self, "_on_district_control_changed"))
	_connect_event(&"player_caught", Callable(self, "_on_player_caught"))


func _connect_event(signal_name: StringName, callback: Callable) -> void:
	if _events.has_signal(signal_name) and not _events.is_connected(signal_name, callback):
		_events.connect(signal_name, callback)


func _find_conversion_zone() -> Area3D:
	for node in get_tree().get_nodes_in_group(&"conversion_zone"):
		var area := node as Area3D
		if area != null:
			return area
	return null


func _on_zone_body_entered(body: Node3D) -> void:
	if not _is_player_body(body):
		return
	complete_objective(OBJECTIVE_VISIT)


func _on_district_control_changed(district: StringName, control: float) -> void:
	if not is_active() or district != district_name:
		return
	if control <= -1.0:
		complete_objective(OBJECTIVE_DISCONNECT)


func _on_player_caught(_by: Node) -> void:
	fail_mission(FAILURE_CAUGHT)


func _check_existing_control() -> void:
	if _zone_area == null:
		return

	var zone_root := _zone_area.get_parent()
	if zone_root != null and zone_root.has_method("get_control") and float(zone_root.call("get_control")) <= -1.0:
		complete_objective(OBJECTIVE_DISCONNECT)


func _is_player_body(body: Node3D) -> bool:
	if body == null:
		return false
	if body.is_in_group(&"player"):
		return true
	return body.name == &"Body" and body.get_parent() != null and body.get_parent().name == &"Player"
