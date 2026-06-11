extends Node

const RoadGraphScript := preload("res://scripts/traffic/road_graph.gd")
const TrafficCarScene := preload("res://scenes/traffic/traffic_car.tscn")

const MOVIE_WIDTH := 1920
const MOVIE_HEIGHT := 1080
const FADE_SECONDS := 0.4
const CAR_Y := 0.82
const EAST_YAW := -PI * 0.5
const BEATS := [
	{"name": "coastal", "duration": 4.8},
	{"name": "boulevard", "duration": 10.5},
	{"name": "converted", "duration": 8.7},
	{"name": "night_market", "duration": 9.6},
	{"name": "closing", "duration": 4.6},
]

var _elapsed := 0.0
var _beat_index := -1
var _beat_elapsed := 0.0
var _beat_started_at := 0.0
var _ending := false
var _vehicle_event_sent := false
var _wheel_spin := 0.0

var _city: Node3D
var _player_root: Node3D
var _player_body: Node3D
var _car: VehicleBody3D
var _streamer: Node
var _traffic_manager: Node
var _time_of_day: Node
var _cinematic_camera: Camera3D
var _fade_rect: ColorRect
var _demo_root: Node3D
var _demo_lights: Array[Light3D] = []
var _demo_traffic: Array[Node] = []


func _ready() -> void:
	process_priority = -1000
	_configure_movie_window()
	_resolve_nodes()
	_build_cinematic_camera()
	_build_fade()
	_prepare_city()
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
	_stop_driving_hud()


func _configure_movie_window() -> void:
	if DisplayServer.get_name() == "headless":
		return

	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(MOVIE_WIDTH, MOVIE_HEIGHT))
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_RESIZE_DISABLED, true)


func _resolve_nodes() -> void:
	_city = get_parent().get_node_or_null("City") as Node3D
	if _city == null:
		push_error("DemoCityDirector needs a City child.")
		return

	_player_root = _city.get_node_or_null("Player") as Node3D
	if _player_root != null:
		_player_body = _player_root.get_node_or_null("Body") as Node3D

	_car = _city.get_node_or_null("Car") as VehicleBody3D
	_streamer = _city.get_node_or_null("WorldStreamer")
	_traffic_manager = _city.get_node_or_null("TrafficManager")
	_time_of_day = _city.get_node_or_null("TimeOfDay")


func _build_cinematic_camera() -> void:
	_cinematic_camera = Camera3D.new()
	_cinematic_camera.name = "DemoCityCamera"
	_cinematic_camera.fov = 58.0
	_cinematic_camera.near = 0.08
	_cinematic_camera.far = 1200.0
	add_child(_cinematic_camera)
	_cinematic_camera.make_current()


func _build_fade() -> void:
	var layer := CanvasLayer.new()
	layer.name = "DemoCityFadeLayer"
	layer.layer = 100
	add_child(layer)

	_fade_rect = ColorRect.new()
	_fade_rect.name = "Fade"
	_fade_rect.color = Color.BLACK
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_fade_rect)


func _prepare_city() -> void:
	if _city == null:
		return

	_demo_root = Node3D.new()
	_demo_root.name = "DemoCityRuntimeSet"
	_city.add_child(_demo_root)

	if _time_of_day != null:
		_time_of_day.set("day_length_minutes", 0.0)
		_set_hour(10.4)

	if _streamer != null:
		_streamer.set("load_radius_tiles", 3)
		_streamer.set("unload_radius_tiles", 4)
		if _car != null and _streamer.has_method("set_target"):
			_streamer.call("set_target", _car)

	if _traffic_manager != null:
		_traffic_manager.set("max_cars", 6)
		_traffic_manager.set("min_car_speed", 9.5)
		_traffic_manager.set("max_car_speed", 12.5)

	if _player_root != null and _player_root.has_method("set_active"):
		_player_root.call("set_active", false)

	_build_demo_lights()
	_build_demo_district_markers()
	_build_demo_traffic()
	_place_car_at(Vector3(292.0, CAR_Y, 64.0), 17.0)
	_sync_player_shadow_target()
	_start_driving_hud()


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

	_beat_index = index
	_beat_started_at = _elapsed
	_beat_elapsed = 0.0

	match String(BEATS[index]["name"]):
		"coastal":
			_set_hour(10.6)
			_set_demo_lights_night(false)
			_start_driving_hud()
		"boulevard":
			_set_hour(15.8)
			_set_demo_lights_night(false)
			_start_driving_hud()
		"converted":
			_set_hour(17.45)
			_set_demo_lights_night(false)
			_start_driving_hud()
		"night_market":
			_set_hour(21.25)
			_set_demo_lights_night(true)
			_start_driving_hud()
		"closing":
			_set_hour(21.35)
			_set_demo_lights_night(true)
			_stop_driving_hud()


func _update_current_beat(delta: float) -> void:
	match String(BEATS[_beat_index]["name"]):
		"coastal":
			_update_coastal(delta)
		"boulevard":
			_update_boulevard(delta)
		"converted":
			_update_converted(delta)
		"night_market":
			_update_night_market(delta)
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


func _update_coastal(delta: float) -> void:
	var t := _normalized_beat_time()
	var car_position := _drive_between(Vector3(292.0, CAR_Y, 64.0), Vector3(338.0, CAR_Y, 64.0), t, delta)
	var camera_position := car_position + Vector3(-30.0, 34.0, -48.0).lerp(Vector3(-22.0, 24.0, -34.0), t)
	var target := car_position + Vector3(30.0, 1.8, 8.0)
	_set_camera_transform(_cinematic_camera, camera_position, target)
	_cinematic_camera.fov = lerpf(62.0, 52.0, t)


func _update_boulevard(delta: float) -> void:
	var t := _normalized_beat_time()
	var car_position := _drive_between(Vector3(338.0, CAR_Y, 64.0), Vector3(520.0, CAR_Y, 64.0), t, delta)
	var forward := _car_forward()
	var right := _car_right()
	var side := lerpf(9.5, 13.5, sin(t * PI))
	var rear := lerpf(13.0, 9.0, t)
	var camera_position := car_position - forward * rear + right * side + Vector3.UP * lerpf(8.2, 9.4, t)
	var target := car_position + forward * 7.0 + right * 1.0 + Vector3.UP * 1.35
	_set_camera_transform(_cinematic_camera, camera_position, target)
	_cinematic_camera.fov = lerpf(54.0, 58.0, t)


func _update_converted(delta: float) -> void:
	var t := _normalized_beat_time()
	var car_position := _drive_between(Vector3(520.0, CAR_Y, 64.0), Vector3(636.0, CAR_Y, 64.0), t, delta)
	var forward := _car_forward()
	var right := _car_right()
	var camera_position := car_position - forward * 8.0 + right * lerpf(8.5, 11.0, t) + Vector3.UP * 4.2
	var target := Vector3(606.0, 8.0, 96.0).lerp(car_position + forward * 20.0 + Vector3.UP * 1.4, t * 0.45)
	_set_camera_transform(_cinematic_camera, camera_position, target)
	_cinematic_camera.fov = 55.0


func _update_night_market(delta: float) -> void:
	var t := _normalized_beat_time()
	var car_position := _drive_between(Vector3(636.0, CAR_Y, 64.0), Vector3(724.0, CAR_Y, 64.0), t, delta)
	var forward := _car_forward()
	var right := _car_right()
	var camera_position := car_position - forward * 7.0 + right * lerpf(-8.0, -11.0, t) + Vector3.UP * 3.4
	var target := car_position + forward * 15.0 + right * 4.5 + Vector3.UP * 1.7
	_set_camera_transform(_cinematic_camera, camera_position, target)
	_cinematic_camera.fov = lerpf(56.0, 50.0, t)


func _update_closing() -> void:
	var t := _normalized_beat_time()
	_place_car_at(Vector3(728.0, CAR_Y, 64.0), 0.0)
	var start := Vector3(705.0, 18.0, 118.0)
	var finish := Vector3(560.0, 48.0, 176.0)
	var position := start.lerp(finish, t)
	var target := Vector3(635.0, 5.0, 92.0).lerp(Vector3(604.0, 9.0, 96.0), t)
	_set_camera_transform(_cinematic_camera, position, target)
	_cinematic_camera.fov = lerpf(54.0, 64.0, t)


func _normalized_beat_time() -> float:
	var duration := float(BEATS[_beat_index]["duration"])
	return clampf(_beat_elapsed / maxf(duration, 0.001), 0.0, 1.0)


func _drive_between(start: Vector3, finish: Vector3, t: float, delta: float) -> Vector3:
	var eased := smoothstep(0.0, 1.0, t)
	var position := start.lerp(finish, eased)
	var duration := float(BEATS[_beat_index]["duration"])
	var speed := start.distance_to(finish) / maxf(duration, 0.001)
	_place_car_at(position, speed)
	_spin_car_wheels(speed, delta)
	_sync_player_shadow_target()
	return position


func _place_car_at(position: Vector3, speed_mps: float) -> void:
	if _car == null:
		return

	_car.global_position = position
	_car.global_rotation = Vector3(0.0, EAST_YAW, 0.0)
	_car.linear_velocity = _car_forward() * speed_mps
	_car.angular_velocity = Vector3.ZERO
	_car.sleeping = false
	_car.set("driven", speed_mps > 0.1)


func _spin_car_wheels(speed_mps: float, delta: float) -> void:
	if _car == null:
		return
	_wheel_spin += (speed_mps / 0.36) * delta
	for wheel_name in ["WheelFrontLeft", "WheelFrontRight", "WheelRearLeft", "WheelRearRight"]:
		var visual := _car.get_node_or_null(NodePath("%s/Visual" % wheel_name)) as Node3D
		if visual != null:
			visual.rotation.x = _wheel_spin


func _sync_player_shadow_target() -> void:
	if _player_root != null and _car != null:
		_player_root.global_position = _car.global_position + Vector3(0.0, 0.2, 0.0)
	if _player_body != null and _car != null:
		_player_body.global_position = _car.global_position + Vector3(0.0, 0.2, 0.0)


func _start_driving_hud() -> void:
	if _car == null or _vehicle_event_sent:
		return
	var events := get_node_or_null("/root/Events")
	if events != null and events.has_signal(&"vehicle_entered"):
		events.emit_signal(&"vehicle_entered", _car)
	_vehicle_event_sent = true


func _stop_driving_hud() -> void:
	if _car == null:
		return
	_car.linear_velocity = Vector3.ZERO
	_car.set("driven", false)
	if not _vehicle_event_sent:
		return
	var events := get_node_or_null("/root/Events")
	if events != null and events.has_signal(&"vehicle_exited"):
		events.emit_signal(&"vehicle_exited", _car)
	_vehicle_event_sent = false


func _set_hour(hour: float) -> void:
	if _time_of_day != null and _time_of_day.has_method("set_hour"):
		_time_of_day.call("set_hour", hour)


func _build_demo_traffic() -> void:
	if _demo_root == null:
		return

	var graph := RoadGraphScript.new()
	graph.graph_name = &"demo_boulevard"
	graph.add_loop(PackedVector3Array([
		Vector3(298.0, 0.15, 66.0),
		Vector3(730.0, 0.15, 66.0),
		Vector3(730.0, 0.15, 126.0),
		Vector3(298.0, 0.15, 126.0),
	]))

	for index in range(7):
		var traffic := TrafficCarScene.instantiate()
		if traffic == null:
			continue
		_demo_root.add_child(traffic)
		traffic.set("collision_layer", 0)
		traffic.set("collision_mask", 0)
		var distance := 48.0 + float(index) * 70.0
		var speed := 8.5 + float(index % 3) * 1.3
		traffic.call("configure", graph, 0, distance, speed)
		_demo_traffic.append(traffic)


func _build_demo_lights() -> void:
	if _demo_root == null:
		return

	for x in [642.0, 674.0, 706.0, 736.0]:
		_spawn_demo_streetlight(Vector3(x, 0.0, 58.0))
		_spawn_demo_streetlight(Vector3(x + 12.0, 0.0, 122.0))


func _spawn_demo_streetlight(base_position: Vector3) -> void:
	var pole := MeshInstance3D.new()
	pole.name = "DemoStreetlightPole"
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.07
	pole_mesh.bottom_radius = 0.09
	pole_mesh.height = 4.8
	pole.mesh = pole_mesh
	pole.material_override = _make_standard_material(Color(0.12, 0.11, 0.1, 1.0), 0.0)
	pole.position = base_position + Vector3(0.0, 2.4, 0.0)
	_demo_root.add_child(pole)

	var bulb := MeshInstance3D.new()
	bulb.name = "DemoStreetlightBulb"
	var bulb_mesh := SphereMesh.new()
	bulb_mesh.radius = 0.28
	bulb_mesh.height = 0.56
	bulb.mesh = bulb_mesh
	bulb.material_override = _make_emissive_material(Color(1.0, 0.72, 0.34, 1.0), 1.8)
	bulb.position = base_position + Vector3(0.0, 4.9, 0.0)
	_demo_root.add_child(bulb)

	var light := OmniLight3D.new()
	light.name = "DemoStreetlight"
	light.light_color = Color(1.0, 0.72, 0.36, 1.0)
	light.light_energy = 0.0
	light.omni_range = 13.0
	light.omni_attenuation = 1.45
	light.shadow_enabled = false
	light.position = base_position + Vector3(0.0, 4.6, 0.0)
	_demo_root.add_child(light)
	_demo_lights.append(light)


func _build_demo_district_markers() -> void:
	if _demo_root == null:
		return

	for z in [52.0, 76.0, 100.0]:
		var strip := MeshInstance3D.new()
		strip.name = "DemoConversionCyanStrip"
		var mesh := BoxMesh.new()
		mesh.size = Vector3(84.0, 0.08, 0.42)
		strip.mesh = mesh
		strip.material_override = _make_emissive_material(Color(0.1, 0.95, 1.0, 0.85), 2.4)
		strip.position = Vector3(588.0, 0.14, z)
		_demo_root.add_child(strip)

	var warm_pool := OmniLight3D.new()
	warm_pool.name = "DemoMarketWarmPool"
	warm_pool.light_color = Color(1.0, 0.54, 0.24, 1.0)
	warm_pool.light_energy = 1.8
	warm_pool.omni_range = 28.0
	warm_pool.omni_attenuation = 1.4
	warm_pool.position = Vector3(688.0, 7.0, 96.0)
	_demo_root.add_child(warm_pool)
	_demo_lights.append(warm_pool)


func _set_demo_lights_night(night: bool) -> void:
	for light in _demo_lights:
		if light == null or not is_instance_valid(light):
			continue
		if light.name == "DemoMarketWarmPool":
			light.light_energy = 1.8 if night else 0.35
		else:
			light.light_energy = 1.65 if night else 0.0


func _car_forward() -> Vector3:
	if _car == null:
		return Vector3.RIGHT
	return -_car.global_transform.basis.z.normalized()


func _car_right() -> Vector3:
	if _car == null:
		return Vector3.FORWARD
	return _car.global_transform.basis.x.normalized()


func _set_camera_transform(camera: Camera3D, position: Vector3, target: Vector3) -> void:
	if camera == null:
		return
	camera.global_position = position
	var direction := target - position
	if direction.length_squared() > 0.001 and absf(direction.normalized().dot(Vector3.UP)) < 0.98:
		camera.look_at(target, Vector3.UP)


func _make_standard_material(color: Color, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = 0.66
	return material


func _make_emissive_material(color: Color, emission_energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = Color(color.r, color.g, color.b)
	material.emission_energy_multiplier = emission_energy
	material.roughness = 0.38
	return material


func _finish_demo() -> void:
	_ending = true
	_stop_driving_hud()
	get_tree().quit()
