extends CharacterBody3D

const BarkSystem = preload("res://scripts/agents/bark_system.gd")

enum AgentState {
	WANDER,
	NOTICE,
	GREET,
	RESUME,
}

@export var wander_radius: float = 18.0
@export var wander_speed: float = 1.6
@export var notice_distance: float = 9.0
@export var notice_speed: float = 2.2
@export var approach_distance: float = 3.0
@export var greet_distance: float = 3.5
@export var greet_cooldown: float = 20.0
@export var idle_min_duration: float = 2.0
@export var idle_max_duration: float = 5.0
@export var greet_min_duration: float = 6.0
@export var greet_max_duration: float = 10.0
@export var idle_chatter_min_interval: float = 12.0
@export var idle_chatter_max_interval: float = 25.0
@export var bark_visible_time: float = 4.0
@export var blocked_give_up_time: float = 2.0
@export var turn_speed: float = 8.0
@export var stop_acceleration: float = 16.0
@export var debug_state_changes: bool = false
@export var ram_collision_speed_threshold: float = 4.0
@export var vehicle_ram_distance: float = 2.5
@export var vehicle_ram_speed_threshold: float = 8.0
@export var witnessed_crime_cooldown: float = 3.0

var _state := AgentState.WANDER
var _spawn_position := Vector3.ZERO
var _wander_target := Vector3.ZERO
var _has_wander_target := false
var _idle_timer := 0.0
var _greet_timer := 0.0
var _idle_chatter_timer := 0.0
var _blocked_timer := 0.0
var _gravity := 9.8
var _life_time := 0.0
var _current_player: CharacterBody3D
var _last_greet_times: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _barks := BarkSystem.new()
var _bark_tween: Tween
var _witnessed_crime_timer := 0.0
var _player_vehicle: Node3D

@onready var _bark_bubble: Label3D = get_node_or_null("BarkBubble") as Label3D


func _ready() -> void:
	add_to_group("agents")
	_rng.randomize()
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	_spawn_position = global_position
	_schedule_idle_chatter()
	_pick_wander_target()
	_connect_vehicle_events()

	if _bark_bubble != null:
		_bark_bubble.visible = false
		_bark_bubble.modulate.a = 0.0

	if debug_state_changes:
		print("Agent state: %s" % _state_name(_state))


func _physics_process(delta: float) -> void:
	_life_time += delta
	_witnessed_crime_timer = maxf(0.0, _witnessed_crime_timer - delta)

	match _state:
		AgentState.WANDER:
			var player := _find_notice_player()
			if player != null:
				_current_player = player
				_set_state(AgentState.NOTICE)
			else:
				_update_wander(delta)
		AgentState.NOTICE:
			_update_notice(delta)
		AgentState.GREET:
			_update_greet(delta)
		AgentState.RESUME:
			_enter_wander()

	_update_crime_witnessing()


func _update_wander(delta: float) -> void:
	_update_idle_chatter(delta)

	if _idle_timer > 0.0:
		_idle_timer -= delta
		_stop_horizontal(delta)
		return

	if not _has_wander_target:
		_pick_wander_target()

	var distance := _horizontal_distance(global_position, _wander_target)
	if distance <= 0.55:
		_begin_wander_idle()
		_stop_horizontal(delta)
		return

	var moved := _move_toward(_wander_target, wander_speed, delta)
	if moved < maxf(wander_speed * delta * 0.15, 0.005):
		_blocked_timer += delta
	else:
		_blocked_timer = 0.0

	if _blocked_timer >= blocked_give_up_time:
		_begin_wander_idle()


func _update_notice(delta: float) -> void:
	if not is_instance_valid(_current_player):
		_enter_wander()
		return

	var player_position := _current_player.global_position
	var distance := global_position.distance_to(player_position)
	if distance > notice_distance * 1.25:
		_enter_wander()
		return

	_turn_toward(player_position, delta)
	if distance <= greet_distance:
		_enter_greet()
		return

	if distance > approach_distance:
		_move_toward(player_position, notice_speed, delta)
	else:
		_stop_horizontal(delta)


func _update_greet(delta: float) -> void:
	if is_instance_valid(_current_player):
		_turn_toward(_current_player.global_position, delta)

	_stop_horizontal(delta)
	_greet_timer -= delta
	if _greet_timer <= 0.0:
		_set_state(AgentState.RESUME)


func _enter_greet() -> void:
	if is_instance_valid(_current_player):
		_last_greet_times[_current_player.get_instance_id()] = _life_time

	_greet_timer = _rng.randf_range(greet_min_duration, greet_max_duration)
	_show_bark(_barks.get_bark("greeting"))
	_set_state(AgentState.GREET)


func _enter_wander() -> void:
	_current_player = null
	_has_wander_target = false
	_idle_timer = 0.0
	_blocked_timer = 0.0
	_schedule_idle_chatter()
	_pick_wander_target()
	_set_state(AgentState.WANDER)


func _begin_wander_idle() -> void:
	_has_wander_target = false
	_blocked_timer = 0.0
	_idle_timer = _rng.randf_range(idle_min_duration, idle_max_duration)


func _pick_wander_target() -> void:
	var angle := _rng.randf_range(0.0, TAU)
	var distance := sqrt(_rng.randf()) * maxf(wander_radius, 0.0)
	_wander_target = _spawn_position + Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
	_has_wander_target = true
	_blocked_timer = 0.0


func _move_toward(target: Vector3, speed: float, delta: float) -> float:
	var before := global_position
	var direction := target - global_position
	direction.y = 0.0

	if direction.length_squared() > 0.0001:
		direction = direction.normalized()
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		_turn_toward(global_position + direction, delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, stop_acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, stop_acceleration * delta)

	_apply_gravity(delta)
	move_and_slide()
	return _horizontal_distance(before, global_position)


func _stop_horizontal(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, stop_acceleration * delta)
	velocity.z = move_toward(velocity.z, 0.0, stop_acceleration * delta)
	_apply_gravity(delta)
	move_and_slide()


func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		if velocity.y < 0.0:
			velocity.y = -0.1
	else:
		velocity.y -= _gravity * delta


func _find_notice_player() -> CharacterBody3D:
	var best_player: CharacterBody3D
	var best_distance_squared := notice_distance * notice_distance

	for node in get_tree().get_nodes_in_group("player"):
		var player := node as CharacterBody3D
		if player == null:
			continue
		if not _can_greet(player):
			continue

		var distance_squared := global_position.distance_squared_to(player.global_position)
		if distance_squared <= best_distance_squared:
			best_distance_squared = distance_squared
			best_player = player

	return best_player


func _can_greet(player: CharacterBody3D) -> bool:
	var player_id := player.get_instance_id()
	if not _last_greet_times.has(player_id):
		return true

	return _life_time - float(_last_greet_times[player_id]) >= greet_cooldown


func _update_idle_chatter(delta: float) -> void:
	_idle_chatter_timer -= delta
	if _idle_chatter_timer > 0.0:
		return

	_show_bark(_barks.get_bark("idle_chatter"))
	_schedule_idle_chatter()


func _schedule_idle_chatter() -> void:
	_idle_chatter_timer = _rng.randf_range(idle_chatter_min_interval, idle_chatter_max_interval)


func _connect_vehicle_events() -> void:
	var events := _events()
	if events == null:
		return

	var entered_callable := Callable(self, "_on_player_vehicle_entered")
	if not events.is_connected(&"vehicle_entered", entered_callable):
		events.connect(&"vehicle_entered", entered_callable)

	var exited_callable := Callable(self, "_on_player_vehicle_exited")
	if not events.is_connected(&"vehicle_exited", exited_callable):
		events.connect(&"vehicle_exited", exited_callable)


func _on_player_vehicle_entered(vehicle: Node) -> void:
	_player_vehicle = vehicle as Node3D


func _on_player_vehicle_exited(vehicle: Node) -> void:
	if vehicle == _player_vehicle:
		_player_vehicle = null


func _update_crime_witnessing() -> void:
	if _witnessed_crime_timer > 0.0:
		return

	if _witnessed_fast_collision() or _witnessed_nearby_vehicle_ram():
		_report_witnessed_ram()


func _witnessed_fast_collision() -> bool:
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		if collision == null:
			continue

		var collider := collision.get_collider() as Node
		if collider == null:
			continue
		if not _is_player_or_driven_vehicle(collider):
			continue
		if _get_body_speed(collider) > ram_collision_speed_threshold:
			return true

	return false


func _witnessed_nearby_vehicle_ram() -> bool:
	var vehicle := _find_player_vehicle()
	if vehicle == null:
		return false
	if global_position.distance_to(vehicle.global_position) > vehicle_ram_distance:
		return false
	return _get_body_speed(vehicle) > vehicle_ram_speed_threshold


func _report_witnessed_ram() -> void:
	_witnessed_crime_timer = witnessed_crime_cooldown
	var line := _barks.get_bark("taking_damage")
	_show_bark(line)
	var events := _events()
	if events == null:
		return
	if not line.is_empty():
		events.emit_signal(&"bark_emitted", self, &"taking_damage", line)
	events.emit_signal(&"crime_committed", 2, global_position)


func _is_player_or_driven_vehicle(node: Node) -> bool:
	if node.is_in_group("player"):
		return true
	if node == _player_vehicle:
		return true
	return node is VehicleBody3D and _is_driven_vehicle(node)


func _find_player_vehicle() -> VehicleBody3D:
	if is_instance_valid(_player_vehicle) and _is_driven_vehicle(_player_vehicle):
		return _player_vehicle as VehicleBody3D

	var scene := get_tree().current_scene
	if scene == null:
		return null
	return _find_driven_vehicle_under(scene)


func _find_driven_vehicle_under(node: Node) -> VehicleBody3D:
	var vehicle := node as VehicleBody3D
	if vehicle != null and _is_driven_vehicle(vehicle):
		return vehicle

	for child in node.get_children():
		var found := _find_driven_vehicle_under(child)
		if found != null:
			return found

	return null


func _is_driven_vehicle(node: Node) -> bool:
	if node == null:
		return false
	return bool(node.get("driven"))


func _get_body_speed(node: Object) -> float:
	var rigid_body := node as RigidBody3D
	if rigid_body != null:
		return rigid_body.linear_velocity.length()

	var character_body := node as CharacterBody3D
	if character_body != null:
		return character_body.velocity.length()

	var linear_velocity: Variant = node.get("linear_velocity")
	if typeof(linear_velocity) == TYPE_VECTOR3:
		return (linear_velocity as Vector3).length()

	var velocity_value: Variant = node.get("velocity")
	if typeof(velocity_value) == TYPE_VECTOR3:
		return (velocity_value as Vector3).length()

	return 0.0


func _events() -> Node:
	return get_node_or_null("/root/Events")


func _show_bark(line: String) -> void:
	if _bark_bubble == null or line.is_empty():
		return

	if _bark_tween != null and _bark_tween.is_running():
		_bark_tween.kill()

	_bark_bubble.text = line
	_bark_bubble.visible = true
	_bark_bubble.modulate = Color(1.0, 1.0, 1.0, 1.0)

	_bark_tween = create_tween()
	_bark_tween.tween_interval(bark_visible_time)
	_bark_tween.tween_property(_bark_bubble, "modulate", Color(1.0, 1.0, 1.0, 0.0), 0.35)
	_bark_tween.tween_callback(_bark_bubble.hide)


func _turn_toward(target: Vector3, delta: float) -> void:
	var direction := target - global_position
	direction.y = 0.0
	if direction.length_squared() <= 0.0001:
		return

	var target_yaw := atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(turn_speed * delta, 0.0, 1.0))


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _set_state(next_state: int) -> void:
	if _state == next_state:
		return

	if debug_state_changes:
		print("Agent state: %s -> %s" % [_state_name(_state), _state_name(next_state)])

	_state = next_state


func _state_name(state: int) -> String:
	match state:
		AgentState.WANDER:
			return "WANDER"
		AgentState.NOTICE:
			return "NOTICE"
		AgentState.GREET:
			return "GREET"
		AgentState.RESUME:
			return "RESUME"
		_:
			return "UNKNOWN"
