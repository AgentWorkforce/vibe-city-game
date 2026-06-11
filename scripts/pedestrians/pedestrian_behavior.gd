class_name PedestrianBehavior
extends CharacterBody3D

signal state_changed(previous: String, current: String)

const HealthScript = preload("res://scripts/combat/health.gd")

enum PedestrianState {
	IDLE,
	STROLL,
	GAWK,
	FLEE,
	RESUME,
}

@export var stroll_radius: float = 12.0
@export var stroll_speed: float = 1.1
@export var gawk_distance: float = 6.0
@export var gawk_release_distance: float = 7.5
@export var flee_crime_distance: float = 25.0
@export var flee_shot_distance: float = 12.0
@export var flee_speed: float = 5.0
@export var flee_min_duration: float = 4.0
@export var flee_max_duration: float = 7.0
@export var idle_min_duration: float = 2.0
@export var idle_max_duration: float = 6.0
@export var resume_duration: float = 0.45
@export var blocked_give_up_time: float = 1.5
@export var turn_speed: float = 8.0
@export var stop_acceleration: float = 16.0
@export var curious_lean_chance: float = 0.22
@export var curious_lean_degrees: float = 7.0
@export var scale_min: float = 0.92
@export var scale_max: float = 1.05
@export var district_name: StringName = &""
@export var district_center_path: NodePath = NodePath("")
@export var district_radius: float = 32.0
@export var celebrate_jump_velocity: float = 4.2
@export var celebrate_duration: float = 1.0
@export var corpse_seconds: float = 3.0
@export var debug_state_changes: bool = false
@export var body_palette: Array[Color] = [
	Color(0.95, 0.36, 0.28, 1.0),
	Color(0.82, 0.58, 0.38, 1.0),
	Color(0.48, 0.56, 0.34, 1.0),
	Color(0.23, 0.42, 0.68, 1.0),
	Color(0.93, 0.68, 0.46, 1.0),
]
@export var head_palette: Array[Color] = [
	Color(0.95, 0.74, 0.55, 1.0),
	Color(0.72, 0.50, 0.36, 1.0),
	Color(0.54, 0.36, 0.24, 1.0),
	Color(0.98, 0.82, 0.64, 1.0),
]

var _state := PedestrianState.IDLE
var _spawn_position := Vector3.ZERO
var _stroll_target := Vector3.ZERO
var _has_stroll_target := false
var _idle_timer := 0.0
var _flee_timer := 0.0
var _resume_timer := 0.0
var _blocked_timer := 0.0
var _gravity := 9.8
var _rng := RandomNumberGenerator.new()
var _current_player: Node3D
var _flee_source := Vector3.ZERO
var _health: Health
var _dead := false
var _crumpling := false
var _lean_timer := 0.0
var _lean_direction := 1.0
var _celebrate_timer := 0.0
var _celebrate_player: Node3D

@onready var _visuals: Node3D = get_node_or_null("Visuals") as Node3D
@onready var _body_mesh: MeshInstance3D = get_node_or_null("Visuals/BodyMesh") as MeshInstance3D
@onready var _head_mesh: MeshInstance3D = get_node_or_null("Visuals/Head") as MeshInstance3D


func _ready() -> void:
	add_to_group("pedestrians")
	_rng.randomize()
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	_spawn_position = global_position
	_connect_health()
	_connect_events()
	_apply_random_appearance()
	_enter_idle()

	if debug_state_changes:
		print("Pedestrian state: %s" % _state_name(_state))


func _physics_process(delta: float) -> void:
	if _dead:
		_stop_dead_body(delta)
		return

	_update_celebration(delta)

	match _state:
		PedestrianState.IDLE:
			_update_idle(delta)
		PedestrianState.STROLL:
			_update_stroll(delta)
		PedestrianState.GAWK:
			_update_gawk(delta)
		PedestrianState.FLEE:
			_update_flee(delta)
		PedestrianState.RESUME:
			_update_resume(delta)


func get_state_name() -> String:
	return _state_name(_state)


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


func _connect_events() -> void:
	var events := _events()
	if events == null:
		return

	var crime_callable := Callable(self, "_on_crime_committed")
	if events.has_signal(&"crime_committed") and not events.is_connected(&"crime_committed", crime_callable):
		events.connect(&"crime_committed", crime_callable)

	var impact_callable := Callable(self, "_on_weapon_impact")
	if events.has_signal(&"weapon_impact") and not events.is_connected(&"weapon_impact", impact_callable):
		events.connect(&"weapon_impact", impact_callable)

	var district_callable := Callable(self, "_on_district_control_changed")
	if events.has_signal(&"district_control_changed") and not events.is_connected(&"district_control_changed", district_callable):
		events.connect(&"district_control_changed", district_callable)

	var shifted_callable := Callable(self, "_on_origin_shifted")
	if events.has_signal(&"origin_shifted") and not events.is_connected(&"origin_shifted", shifted_callable):
		events.connect(&"origin_shifted", shifted_callable)


func _apply_random_appearance() -> void:
	var varied_scale := _rng.randf_range(scale_min, scale_max)
	scale = Vector3(scale.x * varied_scale, scale.y * varied_scale, scale.z * varied_scale)

	_apply_mesh_color(_body_mesh, _pick_color(body_palette, Color(0.95, 0.36, 0.28, 1.0)), 0.08)
	_apply_mesh_color(_head_mesh, _pick_color(head_palette, Color(0.95, 0.74, 0.55, 1.0)), 0.02)


func _pick_color(palette: Array[Color], fallback: Color) -> Color:
	if palette.is_empty():
		return fallback
	return palette[_rng.randi_range(0, palette.size() - 1)]


func _apply_mesh_color(mesh: MeshInstance3D, color: Color, emission_energy: float) -> void:
	if mesh == null:
		return

	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = emission_energy > 0.0
	material.emission = color
	material.emission_energy_multiplier = emission_energy
	material.roughness = 0.72
	mesh.material_override = material


func _update_idle(delta: float) -> void:
	if _enter_gawk_if_player_near():
		_stop_horizontal(delta)
		return

	_idle_timer -= delta
	_stop_horizontal(delta)
	if _idle_timer <= 0.0:
		_enter_stroll()


func _update_stroll(delta: float) -> void:
	if _enter_gawk_if_player_near():
		_stop_horizontal(delta)
		return

	if not _has_stroll_target:
		_pick_stroll_target()

	var distance := _horizontal_distance(global_position, _stroll_target)
	if distance <= 0.55:
		_enter_idle()
		_stop_horizontal(delta)
		return

	var moved := _move_toward(_stroll_target, stroll_speed, delta)
	if moved < maxf(stroll_speed * delta * 0.15, 0.005):
		_blocked_timer += delta
	else:
		_blocked_timer = 0.0

	if _blocked_timer >= blocked_give_up_time:
		_enter_idle()


func _update_gawk(delta: float) -> void:
	if not is_instance_valid(_current_player):
		_enter_resume()
		_stop_horizontal(delta)
		return

	var player_position := _current_player.global_position
	if global_position.distance_to(player_position) > gawk_release_distance:
		_enter_resume()
		_stop_horizontal(delta)
		return

	_turn_toward(player_position, delta)
	_update_curious_lean(delta)
	_stop_horizontal(delta)


func _update_flee(delta: float) -> void:
	_flee_timer -= delta

	var direction := global_position - _flee_source
	direction.y = 0.0
	if direction.length_squared() <= 0.0001:
		var angle := _rng.randf_range(0.0, TAU)
		direction = Vector3(cos(angle), 0.0, sin(angle))
	else:
		direction = direction.normalized()

	velocity.x = direction.x * flee_speed
	velocity.z = direction.z * flee_speed
	_turn_toward(global_position + direction, delta)
	_apply_gravity(delta)
	move_and_slide()

	if _flee_timer <= 0.0:
		_enter_resume()


func _update_resume(delta: float) -> void:
	_resume_timer -= delta
	_stop_horizontal(delta)
	if _resume_timer <= 0.0:
		_enter_idle()


func _enter_idle() -> void:
	_has_stroll_target = false
	_blocked_timer = 0.0
	_idle_timer = _rng.randf_range(idle_min_duration, idle_max_duration)
	_reset_lean()
	_set_state(PedestrianState.IDLE)


func _enter_stroll() -> void:
	_pick_stroll_target()
	_reset_lean()
	_set_state(PedestrianState.STROLL)


func _enter_gawk(player: Node3D) -> void:
	_current_player = player
	_has_stroll_target = false
	_blocked_timer = 0.0
	_begin_possible_lean()
	_set_state(PedestrianState.GAWK)


func _enter_flee(source_position: Vector3) -> void:
	_current_player = null
	_flee_source = source_position
	_flee_timer = _rng.randf_range(flee_min_duration, flee_max_duration)
	_has_stroll_target = false
	_blocked_timer = 0.0
	_reset_lean()
	_set_state(PedestrianState.FLEE)


func _enter_resume() -> void:
	_current_player = null
	_has_stroll_target = false
	_blocked_timer = 0.0
	_resume_timer = maxf(_resume_timer, resume_duration)
	_reset_lean()
	_set_state(PedestrianState.RESUME)


func _enter_gawk_if_player_near() -> bool:
	var player := _find_nearby_player(gawk_distance)
	if player == null:
		return false

	_enter_gawk(player)
	return true


func _pick_stroll_target() -> void:
	var angle := _rng.randf_range(0.0, TAU)
	var distance := sqrt(_rng.randf()) * maxf(stroll_radius, 0.0)
	_stroll_target = _spawn_position + Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
	_has_stroll_target = true
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


func _stop_dead_body(delta: float) -> void:
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


func _find_nearby_player(max_distance: float) -> Node3D:
	var best_player: Node3D
	var best_distance_squared := max_distance * max_distance

	for node in get_tree().get_nodes_in_group("player"):
		var player := node as Node3D
		if player == null:
			continue

		var distance_squared := global_position.distance_squared_to(player.global_position)
		if distance_squared <= best_distance_squared:
			best_distance_squared = distance_squared
			best_player = player

	return best_player


func _find_any_player() -> Node3D:
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as Node3D
		if player != null:
			return player
	return null


func _on_crime_committed(_severity: int, position: Vector3) -> void:
	if _dead:
		return
	if global_position.distance_squared_to(position) > flee_crime_distance * flee_crime_distance:
		return

	_enter_flee(position)


func _on_weapon_impact(position: Vector3) -> void:
	if _dead or flee_shot_distance <= 0.0:
		return
	if global_position.distance_squared_to(position) > flee_shot_distance * flee_shot_distance:
		return

	_enter_flee(position)


func _on_district_control_changed(district: StringName, control: float) -> void:
	if _dead or control > -0.999:
		return
	if not _is_in_liberated_district(district):
		return

	_start_celebration()


func _on_origin_shifted(offset: Vector3) -> void:
	# Stroll/flee anchors are local world-space caches and must move with the
	# shifted scene to preserve behavior after a floating-origin snap.
	_spawn_position -= offset
	_stroll_target -= offset
	_flee_source -= offset


func _is_in_liberated_district(district: StringName) -> bool:
	var assigned_district := _assigned_district_name()
	if assigned_district == &"" or assigned_district != district:
		return false

	var center := _district_center()
	if center == null:
		return true

	return global_position.distance_squared_to(center.global_position) <= district_radius * district_radius


func _assigned_district_name() -> StringName:
	if district_name != &"":
		return district_name

	var cursor := get_parent()
	while cursor != null:
		var value: Variant = cursor.get("district_name")
		if typeof(value) == TYPE_STRING_NAME or typeof(value) == TYPE_STRING:
			var as_text := String(value)
			if not as_text.is_empty():
				return StringName(as_text)
		cursor = cursor.get_parent()

	return &""


func _district_center() -> Node3D:
	if not district_center_path.is_empty():
		var explicit_center := get_node_or_null(district_center_path) as Node3D
		if explicit_center != null:
			return explicit_center

	var cursor := get_parent()
	var assigned_district := _assigned_district_name()
	while cursor != null:
		var value: Variant = cursor.get("district_name")
		if String(value) == String(assigned_district):
			var center := cursor as Node3D
			if center != null:
				return center
		cursor = cursor.get_parent()

	return null


func _start_celebration() -> void:
	_celebrate_timer = maxf(_celebrate_timer, celebrate_duration)
	_celebrate_player = _find_any_player()
	if is_on_floor():
		velocity.y = maxf(velocity.y, celebrate_jump_velocity)
	if _state != PedestrianState.FLEE:
		_resume_timer = maxf(_resume_timer, celebrate_duration)
		_enter_resume()


func _update_celebration(delta: float) -> void:
	if _celebrate_timer <= 0.0:
		return

	_celebrate_timer = maxf(0.0, _celebrate_timer - delta)
	if is_instance_valid(_celebrate_player):
		_turn_toward(_celebrate_player.global_position, delta)


func _on_damaged(_amount: float, _source: Node) -> void:
	if _dead:
		return
	_emit_severe_human_crime()


func _on_died(_source: Node) -> void:
	if _dead:
		return

	_dead = true
	_crumpling = true
	velocity = Vector3.ZERO
	_emit_severe_human_crime()
	_disable_collision()
	_play_crumple()


func _emit_severe_human_crime() -> void:
	var events := _events()
	if events != null:
		events.emit_signal(&"crime_committed", 5, global_position)


func _disable_collision() -> void:
	collision_layer = 0
	collision_mask = 0

	for node in find_children("*", "CollisionShape3D", true, false):
		var shape := node as CollisionShape3D
		if shape != null:
			shape.set_deferred("disabled", true)


func _play_crumple() -> void:
	if _crumpling:
		var target_scale := Vector3(scale.x * 1.12, maxf(scale.y * 0.08, 0.02), scale.z * 1.12)
		var target_y := position.y - 0.62 * maxf(scale.y, 0.1)
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(self, "scale", target_scale, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tween.tween_property(self, "position:y", target_y, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	var timer := get_tree().create_timer(corpse_seconds)
	timer.timeout.connect(queue_free)


func _begin_possible_lean() -> void:
	_lean_timer = 0.0
	_lean_direction = 1.0
	if _rng.randf() > curious_lean_chance:
		_reset_lean()
		return

	_lean_timer = _rng.randf_range(0.55, 1.1)
	_lean_direction = -1.0 if _rng.randf() < 0.5 else 1.0


func _update_curious_lean(delta: float) -> void:
	if _visuals == null:
		return

	if _lean_timer > 0.0:
		_lean_timer = maxf(0.0, _lean_timer - delta)
		var target_roll := deg_to_rad(curious_lean_degrees) * _lean_direction
		_visuals.rotation.z = lerp_angle(_visuals.rotation.z, target_roll, clampf(8.0 * delta, 0.0, 1.0))
	else:
		_visuals.rotation.z = lerp_angle(_visuals.rotation.z, 0.0, clampf(8.0 * delta, 0.0, 1.0))


func _reset_lean() -> void:
	_lean_timer = 0.0
	if _visuals != null:
		_visuals.rotation.z = 0.0


func _turn_toward(target: Vector3, delta: float) -> void:
	var direction := target - global_position
	direction.y = 0.0
	if direction.length_squared() <= 0.0001:
		return

	var target_yaw := atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(turn_speed * delta, 0.0, 1.0))


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _events() -> Node:
	return get_node_or_null("/root/Events")


func _set_state(next_state: int) -> void:
	if _state == next_state:
		return

	var previous_name := _state_name(_state)
	var next_name := _state_name(next_state)
	if debug_state_changes:
		print("Pedestrian state: %s -> %s" % [previous_name, next_name])

	_state = next_state
	state_changed.emit(previous_name, next_name)


func _state_name(state: int) -> String:
	match state:
		PedestrianState.IDLE:
			return "IDLE"
		PedestrianState.STROLL:
			return "STROLL"
		PedestrianState.GAWK:
			return "GAWK"
		PedestrianState.FLEE:
			return "FLEE"
		PedestrianState.RESUME:
			return "RESUME"
		_:
			return "UNKNOWN"
