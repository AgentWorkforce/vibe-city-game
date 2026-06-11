extends Node

const MOVIE_WIDTH := 1920
const MOVIE_HEIGHT := 1080
const FADE_SECONDS := 0.35
const BEATS := [
	{"name": "establish", "duration": 5.5},
	{"name": "jump", "duration": 7.0},
	{"name": "greet", "duration": 6.0},
	{"name": "drive", "duration": 15.5},
	{"name": "shoot", "duration": 10.5},
	{"name": "closing", "duration": 5.5},
]
const ACTIONS := [
	"move_forward",
	"move_back",
	"move_left",
	"move_right",
	"jump",
	"sprint",
	"interact",
	"handbrake",
	"look_behind",
	"aim",
	"fire",
	"camera_left",
	"camera_right",
	"camera_up",
	"camera_down",
]
const JUMP_TIMES := [1.15, 2.25, 3.45, 4.65]

var _elapsed := 0.0
var _beat_index := -1
var _beat_elapsed := 0.0
var _beat_started_at := 0.0
var _ending := false
var _shot_times := [1.2, 1.75, 2.3, 4.1, 4.65, 5.2]
var _shots_fired: Dictionary = {}
var _fallback_damage_done := false
var _greet_demo_done := false

var _playground: Node3D
var _player_root: Node3D
var _player_body: CharacterBody3D
var _player_camera_rig: Node3D
var _player_camera_pitch: Node3D
var _player_camera: Camera3D
var _car: VehicleBody3D
var _car_camera: Camera3D
var _coupler: Node
var _zone: Node3D
var _agents: Node3D
var _cinematic_camera: Camera3D
var _fade_rect: ColorRect


func _ready() -> void:
	process_priority = -1000
	_configure_movie_window()
	_resolve_nodes()
	_build_cinematic_camera()
	_build_fade()
	_reset_actions()
	_prepare_world()
	_enter_beat(0)


func _process(delta: float) -> void:
	if _ending:
		return

	_elapsed += delta
	var next_index := _beat_index_for_time(_elapsed)
	if next_index != _beat_index:
		_enter_beat(next_index)

	_beat_elapsed = _elapsed - _beat_started_at
	_update_fade(_beat_elapsed, float(BEATS[_beat_index]["duration"]))
	_update_current_beat(delta)


func _exit_tree() -> void:
	_reset_actions()


func _configure_movie_window() -> void:
	if DisplayServer.get_name() == "headless":
		return

	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(MOVIE_WIDTH, MOVIE_HEIGHT))
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_RESIZE_DISABLED, true)


func _resolve_nodes() -> void:
	_playground = get_parent().get_node_or_null("Playground") as Node3D
	if _playground == null:
		push_error("DemoDirector needs a Playground child.")
		return

	_player_root = _playground.get_node_or_null("Player") as Node3D
	if _player_root != null:
		_player_body = _player_root.get_node_or_null("Body") as CharacterBody3D
		_player_camera_rig = _player_root.get_node_or_null("CameraRig") as Node3D
		_player_camera_pitch = _player_root.get_node_or_null("CameraRig/Pitch") as Node3D
		_player_camera = _player_root.get_node_or_null("CameraRig/Pitch/SpringArm3D/Camera3D") as Camera3D

	_car = _playground.get_node_or_null("Car") as VehicleBody3D
	if _car != null:
		_car_camera = _car.get_node_or_null("CameraRig/SpringArm3D/Camera3D") as Camera3D

	_coupler = _playground.get_node_or_null("VehicleCoupler")
	_zone = _playground.get_node_or_null("ConversionZone") as Node3D
	_agents = _playground.get_node_or_null("Agents") as Node3D


func _build_cinematic_camera() -> void:
	_cinematic_camera = Camera3D.new()
	_cinematic_camera.name = "DemoCinematicCamera"
	_cinematic_camera.fov = 58.0
	_cinematic_camera.near = 0.08
	_cinematic_camera.far = 800.0
	add_child(_cinematic_camera)


func _build_fade() -> void:
	var layer := CanvasLayer.new()
	layer.name = "DemoFadeLayer"
	layer.layer = 100
	add_child(layer)

	_fade_rect = ColorRect.new()
	_fade_rect.name = "Fade"
	_fade_rect.color = Color.BLACK
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_fade_rect)


func _prepare_world() -> void:
	if _zone != null and _zone.has_method("restore_control"):
		_zone.call("restore_control", 1.0)


func _beat_index_for_time(time: float) -> int:
	var cursor := 0.0
	for index in range(BEATS.size()):
		cursor += float(BEATS[index]["duration"])
		if time < cursor:
			return index
	return BEATS.size()


func _enter_beat(index: int) -> void:
	if index >= BEATS.size():
		_finish_demo()
		return

	_reset_actions()
	_beat_index = index
	_beat_started_at = _elapsed
	_beat_elapsed = 0.0
	_shots_fired.clear()

	match String(BEATS[index]["name"]):
		"establish":
			_enter_establishing()
		"jump":
			_enter_jump()
		"greet":
			_enter_greet()
		"drive":
			_enter_drive()
		"shoot":
			_enter_shoot()
		"closing":
			_enter_closing()


func _update_current_beat(delta: float) -> void:
	match String(BEATS[_beat_index]["name"]):
		"establish":
			_update_establishing()
		"jump":
			_update_jump()
		"greet":
			_update_greet()
		"drive":
			_update_drive()
		"shoot":
			_update_shoot()
		"closing":
			_update_closing()


func _update_fade(local_time: float, duration: float) -> void:
	if _fade_rect == null:
		return

	var alpha := 0.0
	if local_time < FADE_SECONDS:
		alpha = 1.0 - local_time / FADE_SECONDS
	elif duration - local_time < FADE_SECONDS:
		alpha = 1.0 - maxf(duration - local_time, 0.0) / FADE_SECONDS

	var color := _fade_rect.color
	color.a = clampf(alpha, 0.0, 1.0)
	_fade_rect.color = color


func _enter_establishing() -> void:
	_force_on_foot()
	_set_cinematic_current(true)


func _update_establishing() -> void:
	var t := _normalized_beat_time()
	var angle := lerpf(-0.95, 0.25, t)
	var center := Vector3(-34.0, 4.0, -38.0)
	var target := Vector3(-30.0, 9.0, -58.0)
	var position := center + Vector3(cos(angle) * 88.0, 42.0 + sin(t * PI) * 5.0, sin(angle) * 64.0)
	_set_camera_transform(_cinematic_camera, position, target)
	_cinematic_camera.fov = lerpf(60.0, 50.0, t)


func _enter_jump() -> void:
	_force_on_foot()
	_place_player(Vector3(-37.4, 1.2, 18.0), deg_to_rad(-90.0))
	_set_player_view(-90.0, -7.0)
	_make_player_camera_current()


func _update_jump() -> void:
	_press_between("sprint", 0.55, 5.7)
	_press_between("move_forward", 0.55, 5.9)
	_tap_sequence("jump", JUMP_TIMES, 0.16)
	_set_player_view(-90.0, lerpf(-5.0, -11.0, _normalized_beat_time()))


func _enter_greet() -> void:
	_force_on_foot()
	_place_player(Vector3(5.7, 0.7, 2.0), deg_to_rad(-90.0))
	_greet_demo_done = false
	_look_at_agent()
	_make_player_camera_current()


func _update_greet() -> void:
	_look_at_agent()
	if _beat_elapsed > 0.9 and not _greet_demo_done:
		_show_agent_greeting()
		_greet_demo_done = true


func _enter_drive() -> void:
	_force_on_foot()
	_place_car(Vector3(65.0, 0.65, -20.0), 0.0)
	_place_player(_car.global_position + Vector3(2.8, 0.2, 0.0), 0.0)
	_set_player_view(35.0, -8.0)
	_make_player_camera_current()


func _update_drive() -> void:
	_tap_at("interact", 0.75, 0.14)
	_press_between("move_forward", 1.15, 14.5)
	_press_between("move_left", 3.0, 7.1)
	_press_between("handbrake", 5.05, 7.2)
	_press_between("move_right", 8.7, 11.8)
	_press_between("look_behind", 12.0, 13.3)


func _enter_shoot() -> void:
	_force_on_foot()
	if _zone != null and _zone.has_method("restore_control"):
		_zone.call("restore_control", 1.0)
	_fallback_damage_done = false
	_place_player(Vector3(-42.0, 0.7, -18.5), deg_to_rad(180.0))
	_make_player_camera_current()


func _update_shoot() -> void:
	var target := _current_pylon_target()
	if target != null:
		_aim_player_camera_at(target.global_position + Vector3(0.0, 0.4, 0.0))

	_press_between("aim", 0.55, 8.6)
	_tap_sequence("fire", _shot_times, 0.09)
	for shot_time in _shot_times:
		if _beat_elapsed >= shot_time and not _shots_fired.has(shot_time):
			_spawn_demo_shot()
			_shots_fired[shot_time] = true

	if _beat_elapsed > 3.0 and not _fallback_damage_done:
		_ensure_zone_distress()
		_fallback_damage_done = true


func _enter_closing() -> void:
	_force_on_foot()
	_set_cinematic_current(true)


func _update_closing() -> void:
	var t := _normalized_beat_time()
	var center := _zone.global_position if _zone != null else Vector3(-42.0, 0.0, -32.0)
	var start := center + Vector3(-20.0, 17.0, 24.0)
	var finish := center + Vector3(16.0, 39.0, 88.0)
	var position := start.lerp(finish, t)
	var target := center + Vector3(0.0, 3.4, -8.0)
	_set_camera_transform(_cinematic_camera, position, target)
	_cinematic_camera.fov = lerpf(50.0, 64.0, t)


func _normalized_beat_time() -> float:
	var duration := float(BEATS[_beat_index]["duration"])
	return clampf(_beat_elapsed / maxf(duration, 0.001), 0.0, 1.0)


func _force_on_foot() -> void:
	if _coupler != null and _car != null and bool(_car.get("driven")) and _coupler.has_method("_exit_vehicle"):
		_coupler.call("_exit_vehicle")
	elif _car != null:
		_car.set("driven", false)
		if _car.has_method("release_controls"):
			_car.call("release_controls")
		if _car.has_method("set_camera_active"):
			_car.call("set_camera_active", false)

	if _player_root != null and _player_root.has_method("set_active"):
		_player_root.call("set_active", true)


func _place_player(position: Vector3, yaw: float) -> void:
	if _player_root != null:
		_player_root.global_position = position
	if _player_body != null:
		_player_body.global_position = position
		_player_body.rotation.y = yaw
		_player_body.velocity = Vector3.ZERO
	if _player_camera_rig != null:
		_player_camera_rig.global_position = position


func _place_car(position: Vector3, yaw: float) -> void:
	if _car == null:
		return

	_car.global_position = position
	_car.global_rotation = Vector3(0.0, yaw, 0.0)
	_car.linear_velocity = Vector3.ZERO
	_car.angular_velocity = Vector3.ZERO
	_car.sleeping = false
	_car.set("driven", false)
	if _car.has_method("release_controls"):
		_car.call("release_controls")
	if _car.has_method("set_camera_active"):
		_car.call("set_camera_active", false)


func _set_player_view(yaw_degrees: float, pitch_degrees: float) -> void:
	if _player_camera_rig == null:
		return

	_player_camera_rig.rotation_degrees.y = yaw_degrees
	_player_camera_rig.set("_yaw_degrees", yaw_degrees)
	if _player_camera_pitch != null:
		_player_camera_pitch.rotation_degrees.x = pitch_degrees
	_player_camera_rig.set("_pitch_degrees", pitch_degrees)


func _aim_player_camera_at(target: Vector3) -> void:
	if _player_camera == null:
		return

	var direction := target - _player_camera.global_position
	if direction.length_squared() <= 0.001:
		return
	direction = direction.normalized()
	var yaw := rad_to_deg(atan2(-direction.x, -direction.z))
	var pitch := rad_to_deg(asin(clampf(direction.y, -0.95, 0.95)))
	_set_player_view(yaw, pitch)


func _look_at_agent() -> void:
	var agent := _demo_agent()
	if agent == null:
		_set_player_view(90.0, -7.5)
		return
	_aim_player_camera_at(agent.global_position + Vector3(0.0, 1.35, 0.0))


func _demo_agent() -> Node3D:
	if _agents == null:
		return null
	return _agents.get_node_or_null("Agent1") as Node3D


func _show_agent_greeting() -> void:
	var agent := _demo_agent()
	if agent == null:
		return

	var line := "We're upgrading this street's vibe. The old vibe has been archived."
	if agent.has_method("_show_bark"):
		agent.call("_show_bark", line)

	var events := get_node_or_null("/root/Events")
	if events != null and events.has_signal(&"bark_emitted"):
		events.emit_signal(&"bark_emitted", agent, &"greeting", line)


func _make_player_camera_current() -> void:
	_set_cinematic_current(false)
	if _player_camera != null:
		_player_camera.make_current()


func _set_cinematic_current(active: bool) -> void:
	if _cinematic_camera == null:
		return
	if active:
		_cinematic_camera.make_current()
	else:
		_cinematic_camera.current = false


func _set_camera_transform(camera: Camera3D, position: Vector3, target: Vector3) -> void:
	if camera == null:
		return
	camera.global_position = position
	var direction := target - position
	if direction.length_squared() > 0.001 and absf(direction.normalized().dot(Vector3.UP)) < 0.98:
		camera.look_at(target, Vector3.UP)


func _current_pylon_target() -> Node3D:
	if _zone == null:
		return null

	var first := _zone.get_node_or_null("Pylons/PylonNorthWest") as Node3D
	var second := _zone.get_node_or_null("Pylons/PylonNorthEast") as Node3D
	if _beat_elapsed < 3.3 and _pylon_is_alive(first):
		return first
	if _pylon_is_alive(second):
		return second
	if _pylon_is_alive(first):
		return first
	return second if second != null else first


func _spawn_demo_shot() -> void:
	var target := _current_pylon_target()
	if target == null or _player_camera == null:
		return

	var start := _player_camera.global_position + -_player_camera.global_transform.basis.z.normalized() * 1.5
	var end := target.global_position + Vector3(0.0, 0.55, 0.0)
	_spawn_demo_tracer(start, end)
	_spawn_demo_impact(end)
	_damage_pylon(target, 25.0)


func _spawn_demo_tracer(start: Vector3, end: Vector3) -> void:
	var delta := end - start
	var length := delta.length()
	if length <= 0.01:
		return

	var tracer := MeshInstance3D.new()
	tracer.name = "DemoWeaponTracer"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.065, 0.065, length)
	tracer.mesh = mesh
	tracer.material_override = _make_emissive_material(Color(0.35, 1.0, 1.0, 0.95), 4.5)
	get_tree().current_scene.add_child(tracer)
	tracer.global_position = start.lerp(end, 0.5)
	tracer.look_at(end, Vector3.UP)

	var tween := tracer.create_tween()
	tween.tween_property(tracer, "scale", Vector3(1.0, 1.0, 0.2), 0.28).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_callback(tracer.queue_free)


func _spawn_demo_impact(position: Vector3) -> void:
	var impact := MeshInstance3D.new()
	impact.name = "DemoWeaponImpact"
	var mesh := SphereMesh.new()
	mesh.radius = 0.12
	mesh.height = 0.24
	impact.mesh = mesh
	impact.material_override = _make_emissive_material(Color(0.35, 1.0, 1.0, 0.9), 5.0)
	get_tree().current_scene.add_child(impact)
	impact.global_position = position

	var tween := impact.create_tween()
	tween.tween_property(impact, "scale", Vector3.ONE * 0.85, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_callback(impact.queue_free)


func _damage_pylon(pylon: Node3D, amount: float) -> void:
	var health := pylon.get_node_or_null("Health")
	if health != null and health.has_method("apply_damage"):
		health.call("apply_damage", amount, self)


func _make_emissive_material(color: Color, emission_energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = Color(color.r, color.g, color.b)
	material.emission_energy_multiplier = emission_energy
	return material


func _pylon_is_alive(pylon: Node3D) -> bool:
	if pylon == null:
		return false
	var health := pylon.get_node_or_null("Health")
	return health != null and not bool(health.get("is_dead"))


func _ensure_zone_distress() -> void:
	if _zone == null or _zone.has_method("get_distress") and float(_zone.call("get_distress")) > 0.0:
		return

	var pylon := _zone.get_node_or_null("Pylons/PylonNorthWest")
	var health := pylon.get_node_or_null("Health") if pylon != null else null
	if health != null and health.has_method("apply_damage"):
		health.call("apply_damage", 999.0, self)


func _press_between(action: StringName, start: float, end: float) -> void:
	if _beat_elapsed >= start and _beat_elapsed < end:
		Input.action_press(action)
	else:
		Input.action_release(action)


func _tap_at(action: StringName, start: float, length: float) -> void:
	_press_between(action, start, start + length)


func _tap_sequence(action: StringName, times: Array, length: float) -> void:
	var pressed := false
	for start in times:
		var start_time := float(start)
		if _beat_elapsed >= start_time and _beat_elapsed < start_time + length:
			pressed = true
			break

	if pressed:
		Input.action_press(action)
	else:
		Input.action_release(action)


func _reset_actions() -> void:
	for action in ACTIONS:
		Input.action_release(action)


func _finish_demo() -> void:
	_ending = true
	_reset_actions()
	get_tree().quit()
