extends Control

@onready var _vehicle: Node3D = $DummyVehicle

var _elapsed := 0.0
var _events: Node


func _ready() -> void:
	_events = get_node_or_null("/root/Events")
	call_deferred("_run_demo")


func _process(delta: float) -> void:
	_elapsed += delta
	var speed_mps := 17.0 + sin(_elapsed * 1.7) * 7.0
	_vehicle.set("linear_velocity", Vector3(speed_mps, 0.0, 0.0))


func _run_demo() -> void:
	_emit_wanted(0)
	await get_tree().create_timer(0.35).timeout
	_emit_wanted(1)
	await get_tree().create_timer(0.5).timeout
	_emit_bark(&"police", "Please remain still while assistance converges.")
	await get_tree().create_timer(0.55).timeout
	_emit_wanted(2)
	await get_tree().create_timer(0.55).timeout
	_emit_bark(&"civilian", "That was impressively inadvisable.")
	await get_tree().create_timer(0.55).timeout
	_emit_wanted(3)
	await get_tree().create_timer(0.35).timeout
	_emit_vehicle_entered()


func _emit_wanted(level: int) -> void:
	if is_instance_valid(_events) and _events.has_signal(&"wanted_changed"):
		_events.emit_signal(&"wanted_changed", level)


func _emit_bark(category: StringName, text: String) -> void:
	if is_instance_valid(_events) and _events.has_signal(&"bark_emitted"):
		_events.emit_signal(&"bark_emitted", self, category, text)


func _emit_vehicle_entered() -> void:
	if is_instance_valid(_events) and _events.has_signal(&"vehicle_entered"):
		_events.emit_signal(&"vehicle_entered", _vehicle)
