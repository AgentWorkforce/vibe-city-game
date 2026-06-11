extends Node

@onready var _player: Node3D = $Playground/Body
@onready var _agent_a: Node3D = $Playground/Agents/AgentA
@onready var _agent_b: Node3D = $Playground/Agents/AgentB
@onready var _police: Node3D = $Playground/Agents/PoliceAgent
@onready var _car: Node3D = $Playground/Car
@onready var _zone: Node3D = $Playground/ConversionZone

var _elapsed := 0.0
var _tick: Timer


func _ready() -> void:
	_tick = Timer.new()
	_tick.wait_time = 0.1
	_tick.timeout.connect(_on_tick)
	add_child(_tick)
	_tick.start()
	_on_tick()
	call_deferred("_run_liberation_demo")


func _on_tick() -> void:
	_elapsed += _tick.wait_time
	_player.position = Vector3(sin(_elapsed * 0.55) * 28.0, 0.0, cos(_elapsed * 0.42) * 24.0)
	_player.rotation.y = _elapsed * 0.72

	_agent_a.position = Vector3(-18.0 + sin(_elapsed * 1.2) * 8.0, 0.0, -8.0 + cos(_elapsed) * 5.0)
	_agent_b.position = Vector3(22.0 + cos(_elapsed * 0.7) * 10.0, 0.0, 20.0 + sin(_elapsed * 0.9) * 8.0)
	_police.position = Vector3(-4.0 + cos(_elapsed * 1.1) * 18.0, 0.0, 16.0 + sin(_elapsed * 1.1) * 18.0)

	_car.position = Vector3(30.0 + sin(_elapsed * 0.45) * 14.0, 0.0, -28.0 + cos(_elapsed * 0.5) * 10.0)
	_car.rotation.y = _elapsed * 0.45

	_zone.position = Vector3(-42.0 + sin(_elapsed * 0.35) * 2.5, 0.0, -32.0 + cos(_elapsed * 0.35) * 2.5)


func _run_liberation_demo() -> void:
	await get_tree().create_timer(1.6).timeout
	_zone.set("control", -1.0)
	var events := get_node_or_null("/root/Events")
	if events != null and events.has_signal(&"district_control_changed"):
		events.emit_signal(&"district_control_changed", StringName(str(_zone.get("district_name"))), -1.0)
