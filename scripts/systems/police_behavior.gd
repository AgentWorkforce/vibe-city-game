extends "res://scripts/agents/agent_behavior.gd"

signal player_caught(player: Node)

enum PoliceState {
	PATROL,
	PURSUE,
	CATCH,
}

@export var activation_radius: float = 45.0
@export var pursue_speed: float = 4.5
@export var catch_distance: float = 1.2
@export var caught_bark: String = "Thank you for stopping. You are being helped with maximum courtesy."
@export var debug_police_state_changes: bool = false

var _police_state := PoliceState.PATROL
var _wanted_level := 0
var _pursuit_start_barked := false
var _caught_player_ids: Dictionary = {}


func _ready() -> void:
	super._ready()
	add_to_group("police")
	_wanted_level = _read_wanted_level()

	var events := _events()
	var changed_callable := Callable(self, "_on_wanted_changed")
	if events != null and not events.is_connected(&"wanted_changed", changed_callable):
		events.connect(&"wanted_changed", changed_callable)

	if debug_police_state_changes:
		print("Police state: %s" % _police_state_name(_police_state))


func _physics_process(delta: float) -> void:
	_sync_wanted_level()

	if _wanted_level <= 0:
		if _police_state != PoliceState.PATROL:
			_end_pursuit()
		super._physics_process(delta)
		return

	var target := _find_pursuit_target()
	if target == null:
		super._physics_process(delta)
		return

	if _police_state == PoliceState.PATROL:
		if global_position.distance_to(target.global_position) <= activation_radius:
			_enter_pursuit()
		else:
			super._physics_process(delta)
			return

	_life_time += delta
	_witnessed_crime_timer = maxf(0.0, _witnessed_crime_timer - delta)

	var player := _find_on_foot_player()
	if player != null and global_position.distance_to(player.global_position) <= catch_distance:
		_catch_player(player, delta)
	else:
		_set_police_state(PoliceState.PURSUE)
		_move_toward(target.global_position, pursue_speed, delta)

	_update_crime_witnessing()


func get_police_state_name() -> String:
	return _police_state_name(_police_state)


func _sync_wanted_level() -> void:
	var level := _read_wanted_level()
	if level != _wanted_level:
		_on_wanted_changed(level)


func _read_wanted_level() -> int:
	var wanted := get_node_or_null("/root/Wanted")
	if wanted != null and wanted.has_method("get_level"):
		return clampi(int(wanted.call("get_level")), 0, 5)
	return _wanted_level


func _on_wanted_changed(level: int) -> void:
	var previous_level := _wanted_level
	_wanted_level = clampi(level, 0, 5)

	if _wanted_level > previous_level and _police_state == PoliceState.PURSUE:
		_say_bark(&"pursuit_escalation")
	elif _wanted_level <= 0 and previous_level > 0 and _police_state != PoliceState.PATROL:
		_end_pursuit()


func _enter_pursuit() -> void:
	_set_police_state(PoliceState.PURSUE)
	if not _pursuit_start_barked:
		_say_bark(&"pursuit_start")
		_pursuit_start_barked = true


func _end_pursuit() -> void:
	_say_bark(&"pursuit_lost")
	_pursuit_start_barked = false
	_caught_player_ids.clear()
	_set_police_state(PoliceState.PATROL)
	_enter_wander()


func _catch_player(player: Node, delta: float) -> void:
	_stop_horizontal(delta)
	_set_police_state(PoliceState.CATCH)

	var player_id := player.get_instance_id()
	if _caught_player_ids.has(player_id):
		return

	_caught_player_ids[player_id] = true
	_show_bark(caught_bark)
	var events := _events()
	if events != null:
		events.emit_signal(&"bark_emitted", self, &"caught", caught_bark)
	player_caught.emit(player)


func _find_pursuit_target() -> Node3D:
	var vehicle := _find_player_vehicle()
	if vehicle != null:
		return vehicle
	return _find_any_player()


func _find_on_foot_player() -> CharacterBody3D:
	if _find_player_vehicle() != null:
		return null

	for node in get_tree().get_nodes_in_group("player"):
		var player := node as CharacterBody3D
		if player != null:
			return player

	return null


func _find_any_player() -> Node3D:
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as Node3D
		if player != null:
			return player
	return null


func _say_bark(category: StringName) -> void:
	var line := _barks.get_bark(String(category))
	if line.is_empty():
		return

	_show_bark(line)
	var events := _events()
	if events != null:
		events.emit_signal(&"bark_emitted", self, category, line)


func _set_police_state(next_state: int) -> void:
	if _police_state == next_state:
		return

	if debug_police_state_changes:
		print("Police state: %s -> %s" % [
			_police_state_name(_police_state),
			_police_state_name(next_state),
		])

	_police_state = next_state


func _police_state_name(state: int) -> String:
	match state:
		PoliceState.PATROL:
			return "PATROL"
		PoliceState.PURSUE:
			return "PURSUE"
		PoliceState.CATCH:
			return "CATCH"
		_:
			return "UNKNOWN"
