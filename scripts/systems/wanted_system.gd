extends Node

const WantedLogic = preload("res://scripts/systems/wanted_logic.gd")

@export var severity_heat := PackedFloat32Array(WantedLogic.DEFAULT_SEVERITY_HEAT)
@export var level_thresholds := PackedFloat32Array(WantedLogic.DEFAULT_LEVEL_THRESHOLDS)
@export var decay_rate: float = 5.0
@export var unseen_decay_multiplier: float = 2.5
@export var decay_grace_seconds: float = 3.0
@export var far_from_agent_distance: float = 35.0

var _logic := WantedLogic.new()


func _ready() -> void:
	_configure_logic()
	var events := _events()
	var crime_callable := Callable(self, "_on_crime_committed")
	if events != null and not events.is_connected(&"crime_committed", crime_callable):
		events.connect(&"crime_committed", crime_callable)


func _process(delta: float) -> void:
	_configure_logic()
	var result := _logic.decay(delta, _player_is_far_from_agents())
	_emit_if_level_changed(result)


func get_level() -> int:
	return _logic.get_level()


func add_heat(amount: float) -> void:
	_configure_logic()
	var result := _logic.add_heat(amount)
	_emit_if_level_changed(result)


func clear() -> void:
	var result := _logic.clear()
	_emit_if_level_changed(result)


func get_heat() -> float:
	return _logic.heat


func restore_state(heat: float) -> void:
	_configure_logic()
	var previous_level := _logic.get_level()
	_logic.heat = maxf(heat, 0.0)
	_logic.time_since_crime = 0.0 if _logic.heat > 0.0 else INF
	_emit_if_level_changed({
		"previous_level": previous_level,
		"level": _logic.get_level(),
		"heat": _logic.heat,
	})


func _configure_logic() -> void:
	_logic.configure(
		severity_heat,
		level_thresholds,
		decay_rate,
		unseen_decay_multiplier,
		decay_grace_seconds
	)


func _on_crime_committed(severity: int, _position: Vector3) -> void:
	_configure_logic()
	var result := _logic.add_crime(severity)
	_emit_if_level_changed(result)


func _emit_if_level_changed(result: Dictionary) -> void:
	if int(result["previous_level"]) == int(result["level"]):
		return
	var events := _events()
	if events != null:
		events.emit_signal(&"wanted_changed", int(result["level"]))


func _events() -> Node:
	return get_node_or_null("/root/Events")


func _player_is_far_from_agents() -> bool:
	var player := _find_player()
	if player == null:
		return false

	var distance_squared := far_from_agent_distance * far_from_agent_distance
	for node in get_tree().get_nodes_in_group("agents"):
		var agent := node as Node3D
		if agent == null or agent == player:
			continue
		if agent.global_position.distance_squared_to(player.global_position) <= distance_squared:
			return false

	return true


func _find_player() -> Node3D:
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as Node3D
		if player != null:
			return player
	return null
