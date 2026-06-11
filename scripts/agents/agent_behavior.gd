extends CharacterBody3D

const BarkSystem = preload("res://scripts/agents/bark_system.gd")
const HealthScript = preload("res://scripts/combat/health.gd")
const HITSCAN_WEAPON_PATH := "res://scripts/combat/hitscan_weapon.gd"
const DEREZ_CYAN := Color(0.098, 0.89, 0.89, 1.0)

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
@export var damage_stagger_seconds: float = 0.4
@export var derez_seconds: float = 0.6

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
var _health: Health
var _stagger_timer := 0.0
var _derezzing := false
var _derez_materials: Array[StandardMaterial3D] = []

@onready var _bark_bubble: Label3D = get_node_or_null("BarkBubble") as Label3D


func _ready() -> void:
	add_to_group("agents")
	_connect_health()
	_rng.randomize()
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	_spawn_position = global_position
	_schedule_idle_chatter()
	_pick_wander_target()
	_connect_vehicle_events()
	_connect_origin_events()

	if _bark_bubble != null:
		_bark_bubble.visible = false
		_bark_bubble.modulate.a = 0.0

	if debug_state_changes:
		print("Agent state: %s" % _state_name(_state))


func _physics_process(delta: float) -> void:
	_tick_reaction_timers(delta)
	if _derezzing:
		return
	if _process_stagger(delta):
		_update_crime_witnessing()
		return

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


func _tick_reaction_timers(delta: float) -> void:
	_life_time += delta
	_witnessed_crime_timer = maxf(0.0, _witnessed_crime_timer - delta)


func _process_stagger(delta: float) -> bool:
	if _stagger_timer <= 0.0:
		return false

	_stagger_timer = maxf(0.0, _stagger_timer - delta)
	_stop_horizontal(delta)
	return true


func _connect_health() -> void:
	_health = get_node_or_null("Health") as Health
	if _health == null:
		return

	var damaged_callable := Callable(self, "_on_damaged")
	if not _health.is_connected(&"damaged", damaged_callable):
		_health.connect(&"damaged", damaged_callable)

	var died_callable := Callable(self, "_on_died")
	if not _health.is_connected(&"died", died_callable):
		_health.connect(&"died", died_callable)


func _on_damaged(_amount: float, source: Node) -> void:
	if _derezzing:
		return

	_stagger_timer = maxf(_stagger_timer, damage_stagger_seconds)
	_emit_bark(&"taking_damage")
	if _is_weapon_damage_source(source):
		_report_weapon_damage_crime()


func _on_died(_source: Node) -> void:
	if _derezzing:
		return

	_derezzing = true
	velocity = Vector3.ZERO
	_emit_bark(&"taking_damage", "Thank you for the feedback. De-rezzing now.")
	_disable_collision()
	_play_derez()


func _report_weapon_damage_crime() -> void:
	if _witnessed_crime_timer > 0.0:
		return

	_witnessed_crime_timer = witnessed_crime_cooldown
	var events := _events()
	if events != null:
		events.emit_signal(&"crime_committed", 3, global_position)


func _is_weapon_damage_source(source: Node) -> bool:
	if source == null:
		return false

	var script := source.get_script() as Script
	return script != null and String(script.resource_path) == HITSCAN_WEAPON_PATH


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


func _connect_origin_events() -> void:
	var events := _events()
	if events == null:
		return

	var shifted_callable := Callable(self, "_on_origin_shifted")
	if events.has_signal(&"origin_shifted") and not events.is_connected(&"origin_shifted", shifted_callable):
		events.connect(&"origin_shifted", shifted_callable)


func _on_player_vehicle_entered(vehicle: Node) -> void:
	_player_vehicle = vehicle as Node3D


func _on_player_vehicle_exited(vehicle: Node) -> void:
	if vehicle == _player_vehicle:
		_player_vehicle = null


func _on_origin_shifted(offset: Vector3) -> void:
	# Wander anchors are cached local world-space positions, so they shift with
	# the agent and the rest of the active scene.
	_spawn_position -= offset
	_wander_target -= offset


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
	_emit_bark(&"taking_damage")
	var events := _events()
	if events != null:
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


func _emit_bark(category: StringName, fallback: String = "") -> void:
	var line := _barks.get_bark(String(category))
	if line.is_empty():
		line = fallback
	if line.is_empty():
		return

	_show_bark(line)
	var events := _events()
	if events != null:
		events.emit_signal(&"bark_emitted", self, category, line)


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


func _disable_collision() -> void:
	collision_layer = 0
	collision_mask = 0

	for node in find_children("*", "CollisionShape3D", true, false):
		var shape := node as CollisionShape3D
		if shape != null:
			shape.set_deferred("disabled", true)


func _play_derez() -> void:
	_derez_materials.clear()
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh != null:
			var material := _make_derez_material()
			mesh.material_override = material
			_derez_materials.append(material)

	var flash := OmniLight3D.new()
	flash.name = "DerezFlash"
	flash.light_color = DEREZ_CYAN
	flash.light_energy = 3.0
	flash.omni_range = 4.0
	add_child(flash)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector3(1.12, 0.04, 1.12), derez_seconds).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "position:y", position.y - 1.25, derez_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_method(_set_derez_alpha, 0.92, 0.0, derez_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(flash, "light_energy", 0.0, derez_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.finished.connect(func() -> void:
		if is_instance_valid(flash):
			flash.queue_free()
		queue_free()
	)


func _make_derez_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(DEREZ_CYAN.r, DEREZ_CYAN.g, DEREZ_CYAN.b, 0.92)
	material.emission_enabled = true
	material.emission = DEREZ_CYAN
	material.emission_energy_multiplier = 4.5
	material.roughness = 0.18
	return material


func _set_derez_alpha(value: float) -> void:
	for material in _derez_materials:
		if material == null:
			continue
		var color := material.albedo_color
		color.a = clampf(value, 0.0, 1.0)
		material.albedo_color = color


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
