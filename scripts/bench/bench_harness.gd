extends Node3D

const CITY_SCENE: PackedScene = preload("res://scenes/city/city.tscn")
const PEDESTRIAN_SCENE: PackedScene = preload("res://scenes/pedestrians/pedestrian.tscn")
const AGENT_SCENE: PackedScene = preload("res://scenes/agents/agent.tscn")
const POLICE_SCENE: PackedScene = preload("res://scenes/agents/police_agent.tscn")

const REPORT_DIR := "user://bench"
const DEFAULT_LABEL := "benchmark_city"
const GOLDEN_ANGLE := 2.399963229728653

@export_range(0, 500, 1) var pedestrians: int = 60
@export_range(0, 256, 1) var traffic_cars: int = 16
@export_range(0, 256, 1) var agents: int = 12
@export_range(0, 128, 1) var police: int = 4
@export_range(1, 20000, 1) var bench_frames: int = 1800
@export_range(0, 2000, 1) var warmup_frames: int = 120
@export var seed: int = 11011
@export var focus_position := Vector3(320.0, 1.0, 64.0)
@export var report_label := DEFAULT_LABEL

var _city: Node3D
var _headless := false
var _warmup_ticks := 0
var _measured_frames := 0
var _started := false
var _completed := false
var _settle_wait_frames := 0
var _cleanup_started := false
var _cleanup_frames := 0

var _process_ms: Array[float] = []
var _physics_ms: Array[float] = []
var _combined_ms: Array[float] = []
var _object_counts: Array[float] = []
var _node_counts: Array[float] = []
var _fps_values: Array[float] = []
var _samples: Array[Dictionary] = []


func _ready() -> void:
	_headless = DisplayServer.get_name() == "headless"
	_apply_user_args()
	_setup_city()
	_setup_benchmark_camera()
	_print_configuration()


func _physics_process(_delta: float) -> void:
	if _cleanup_started:
		_cleanup_frames += 1
		if _cleanup_frames >= 12:
			get_tree().quit(0)
		return

	if _completed:
		return

	if not _started:
		_warmup_ticks += 1
		if _warmup_ticks < warmup_frames or not _streaming_settled():
			_settle_wait_frames += 1
			return
		_started = true

	_sample_frame()
	_measured_frames += 1

	if _measured_frames >= bench_frames:
		_completed = true
		_write_reports()
		_begin_cleanup()


func _setup_city() -> void:
	_city = CITY_SCENE.instantiate() as Node3D
	if _city == null:
		push_error("Could not instantiate city scene for benchmark.")
		get_tree().quit(1)
		return

	_prepare_city_before_ready()
	add_child(_city)
	_place_player_at_focus()
	_spawn_population()
	_configure_traffic()
	_clear_wanted_level()


func _prepare_city_before_ready() -> void:
	_clear_container_children(_city.get_node_or_null("Agents"))
	_clear_container_children(_city.get_node_or_null("Pedestrians"))
	_remove_city_child("HUD")
	_remove_city_child("Minimap")
	_remove_city_child("FullMap")
	_remove_city_child("MissionBanner")
	_remove_city_child("StreamingDebugHUD")
	if _headless:
		_remove_city_child("WorldStreamer")

	var traffic_manager := _city.get_node_or_null("TrafficManager")
	if traffic_manager != null:
		traffic_manager.set("spawn_on_ready", false)
		traffic_manager.set("max_cars", traffic_cars)


func _clear_container_children(container: Node) -> void:
	if container == null:
		return

	for child in container.get_children():
		container.remove_child(child)
		child.free()


func _remove_city_child(path: NodePath) -> void:
	var child := _city.get_node_or_null(path)
	if child == null:
		return

	var parent := child.get_parent()
	if parent != null:
		parent.remove_child(child)
	child.free()


func _place_player_at_focus() -> void:
	var player := _city.get_node_or_null("Player") as Node3D
	var body := _city.get_node_or_null("Player/Body") as CharacterBody3D
	if player != null:
		player.global_position = focus_position
	if body != null:
		body.global_position = focus_position
		body.velocity = Vector3.ZERO

	var spawn := _city.get_node_or_null("PlayerSpawn") as Node3D
	if spawn != null:
		spawn.global_position = focus_position

	var stream_target := _city.get_node_or_null("StreamTarget") as Node3D
	if stream_target != null:
		stream_target.global_position = focus_position


func _spawn_population() -> void:
	var pedestrian_parent := _city.get_node_or_null("Pedestrians") as Node3D
	var agent_parent := _city.get_node_or_null("Agents") as Node3D
	if pedestrian_parent == null or agent_parent == null:
		push_error("Benchmark city is missing Agents or Pedestrians container.")
		get_tree().quit(1)
		return

	if _headless:
		_add_headless_collision_block()

	for index in range(pedestrians):
		var ped := PEDESTRIAN_SCENE.instantiate() as Node3D
		_configure_pedestrian_before_ready(ped)
		ped.name = "BenchPedestrian%03d" % index
		ped.position = _pedestrian_position(index, pedestrians)
		ped.rotation.y = _spawn_yaw(index)
		pedestrian_parent.add_child(ped)
		_seed_and_reset_actor(ped, seed + 1000 + index, "_enter_idle")

	for index in range(agents):
		var agent := AGENT_SCENE.instantiate() as Node3D
		_configure_agent_before_ready(agent)
		agent.name = "BenchAgent%03d" % index
		agent.position = _agent_position(index, agents, 18.0, 46.0)
		agent.rotation.y = _spawn_yaw(index + 100)
		agent_parent.add_child(agent)
		_seed_and_reset_actor(agent, seed + 3000 + index, "_enter_wander")

	for index in range(police):
		var police_agent := POLICE_SCENE.instantiate() as Node3D
		_configure_agent_before_ready(police_agent)
		police_agent.name = "BenchPolice%03d" % index
		police_agent.position = _agent_position(index, police, 28.0, 54.0)
		police_agent.rotation.y = _spawn_yaw(index + 200)
		agent_parent.add_child(police_agent)
		_seed_and_reset_actor(police_agent, seed + 5000 + index, "_enter_wander")


func _configure_pedestrian_before_ready(pedestrian: Node) -> void:
	if pedestrian == null:
		return

	pedestrian.set("idle_min_duration", 0.35)
	pedestrian.set("idle_max_duration", 0.35)
	pedestrian.set("scale_min", 1.0)
	pedestrian.set("scale_max", 1.0)
	pedestrian.set("curious_lean_chance", 0.0)
	pedestrian.set("debug_state_changes", false)


func _configure_agent_before_ready(agent: Node) -> void:
	if agent == null:
		return

	_set_if_property(agent, "idle_min_duration", 0.45)
	_set_if_property(agent, "idle_max_duration", 0.45)
	_set_if_property(agent, "greet_min_duration", 4.0)
	_set_if_property(agent, "greet_max_duration", 4.0)
	_set_if_property(agent, "idle_chatter_min_interval", 999.0)
	_set_if_property(agent, "idle_chatter_max_interval", 999.0)
	_set_if_property(agent, "debug_state_changes", false)
	_set_if_property(agent, "debug_police_state_changes", false)


func _seed_and_reset_actor(actor: Node, actor_seed: int, reset_method: StringName) -> void:
	var actor_rng := actor.get("_rng") as RandomNumberGenerator
	if actor_rng != null:
		actor_rng.seed = actor_seed

	if actor.has_method(reset_method):
		actor.call(reset_method)


func _configure_traffic() -> void:
	var traffic_manager := _city.get_node_or_null("TrafficManager")
	if traffic_manager == null:
		return

	traffic_manager.set("max_cars", traffic_cars)
	traffic_manager.set("min_car_speed", 8.0)
	traffic_manager.set("max_car_speed", 10.0)

	var manager_rng := traffic_manager.get("_rng") as RandomNumberGenerator
	if manager_rng != null:
		manager_rng.seed = seed + 7000

	if traffic_manager.has_method("set_road_graph"):
		traffic_manager.call("set_road_graph", traffic_manager.get("road_graph"))


func _add_headless_collision_block() -> void:
	var existing := _city.get_node_or_null("BenchPhysicsBlock")
	if existing != null:
		return

	var block := Node3D.new()
	block.name = "BenchPhysicsBlock"
	_city.add_child(block)

	_add_collision_box(block, "Ground", Vector3(320.0, -0.08, 64.0), Vector3(144.0, 0.16, 144.0))
	_add_collision_box(block, "EastWestRoad", Vector3(320.0, 0.0, 64.0), Vector3(144.0, 0.18, 12.0))
	_add_collision_box(block, "NorthSouthRoad", Vector3(320.0, 0.0, 64.0), Vector3(12.0, 0.18, 144.0))
	_add_collision_box(block, "NorthSidewalk", Vector3(320.0, 0.04, 74.0), Vector3(144.0, 0.18, 6.0))
	_add_collision_box(block, "SouthSidewalk", Vector3(320.0, 0.04, 54.0), Vector3(144.0, 0.18, 6.0))
	_add_collision_box(block, "WestSidewalk", Vector3(310.0, 0.04, 64.0), Vector3(6.0, 0.18, 144.0))
	_add_collision_box(block, "EastSidewalk", Vector3(330.0, 0.04, 64.0), Vector3(6.0, 0.18, 144.0))


func _add_collision_box(parent: Node, name: String, center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = name
	body.position = center

	var shape := BoxShape3D.new()
	shape.size = size

	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)


func _clear_wanted_level() -> void:
	var wanted := get_node_or_null("/root/Wanted")
	if wanted != null and wanted.has_method("clear"):
		wanted.call("clear")


func _setup_benchmark_camera() -> void:
	var marker := Marker3D.new()
	marker.name = "BenchmarkFocus"
	marker.position = focus_position
	add_child(marker)

	var camera := Camera3D.new()
	camera.name = "BenchmarkCamera"
	camera.fov = 58.0
	camera.position = focus_position + Vector3(44.0, 34.0, 78.0)
	add_child(camera)
	camera.look_at(focus_position + Vector3(0.0, 1.1, 0.0), Vector3.UP)
	camera.make_current()


func _pedestrian_position(index: int, total: int) -> Vector3:
	var lane := index % 4
	var slot := index / 4
	var slots_per_lane := maxi(1, ceili(float(maxi(total, 1)) / 4.0))
	var t := (float((slot * 7) % slots_per_lane) + 0.5) / float(slots_per_lane)
	var jitter := _deterministic_jitter(index, 1.15)

	match lane:
		0:
			return Vector3(274.0 + 92.0 * t, 0.35, 55.5 + jitter.z)
		1:
			return Vector3(274.0 + 92.0 * t, 0.35, 72.5 + jitter.z)
		2:
			return Vector3(311.5 + jitter.x, 0.35, 24.0 + 92.0 * t)
		_:
			return Vector3(328.5 + jitter.x, 0.35, 24.0 + 92.0 * t)


func _agent_position(index: int, total: int, inner_radius: float, outer_radius: float) -> Vector3:
	var count := maxi(total, 1)
	var radius_t := sqrt((float(index) + 0.5) / float(count))
	var radius := lerpf(inner_radius, outer_radius, radius_t)
	var angle := float(index) * GOLDEN_ANGLE + float(seed % 360) * 0.01745329252
	var offset := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
	var jitter := _deterministic_jitter(index + 313, 0.75)
	return Vector3(focus_position.x + offset.x + jitter.x, 0.35, focus_position.z + offset.z + jitter.z)


func _deterministic_jitter(index: int, amplitude: float) -> Vector3:
	var local_rng := RandomNumberGenerator.new()
	local_rng.seed = seed + index * 7919
	return Vector3(
		local_rng.randf_range(-amplitude, amplitude),
		0.0,
		local_rng.randf_range(-amplitude, amplitude)
	)


func _spawn_yaw(index: int) -> float:
	return fposmod(float(seed + index * 37), 360.0) * 0.01745329252


func _streaming_settled() -> bool:
	var streamer := _city.get_node_or_null("WorldStreamer")
	if streamer == null:
		return true

	if streamer.has_method("get_loads_in_flight_count") and int(streamer.call("get_loads_in_flight_count")) > 0:
		return false
	if streamer.has_method("get_pending_load_count") and int(streamer.call("get_pending_load_count")) > 0:
		return false
	return true


func _sample_frame() -> void:
	var process_value := float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0
	var physics_value := float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
	var combined_value := process_value + physics_value
	var object_count := float(Performance.get_monitor(Performance.OBJECT_COUNT))
	var node_count := float(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))

	_process_ms.append(process_value)
	_physics_ms.append(physics_value)
	_combined_ms.append(combined_value)
	_object_counts.append(object_count)
	_node_counts.append(node_count)

	var sample := {
		"frame": _measured_frames + 1,
		"process_ms": process_value,
		"physics_ms": physics_value,
		"combined_ms": combined_value,
		"object_count": int(object_count),
		"node_count": int(node_count),
	}

	if not _headless:
		var fps_value := float(Performance.get_monitor(Performance.TIME_FPS))
		_fps_values.append(fps_value)
		sample["fps"] = fps_value

	_samples.append(sample)


func _write_reports() -> void:
	var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(REPORT_DIR))
	if err != OK:
		push_error("Could not create benchmark report directory: %s" % REPORT_DIR)
		get_tree().quit(1)
		return

	var run_id := _run_id()
	var json_user_path := "%s/%s.json" % [REPORT_DIR, run_id]
	var text_user_path := "%s/%s.txt" % [REPORT_DIR, run_id]
	var json_abs_path := ProjectSettings.globalize_path(json_user_path)
	var text_abs_path := ProjectSettings.globalize_path(text_user_path)
	var data := _build_report_data(run_id, json_user_path, text_user_path)

	_write_text_file(json_user_path, JSON.stringify(data, "\t"))
	_write_text_file(text_user_path, _format_human_report(data))
	_write_text_file("%s/latest.json" % REPORT_DIR, JSON.stringify(data, "\t"))
	_write_text_file("%s/latest.txt" % REPORT_DIR, _format_human_report(data))

	_print_summary_table(data)
	print("BENCH_JSON_USER=%s" % json_user_path)
	print("BENCH_JSON_ABS=%s" % json_abs_path)
	print("BENCH_REPORT_USER=%s" % text_user_path)
	print("BENCH_REPORT_ABS=%s" % text_abs_path)


func _begin_cleanup() -> void:
	if _cleanup_started:
		return

	_cleanup_started = true
	_cleanup_frames = 0
	if is_instance_valid(_city):
		_city.queue_free()


func _build_report_data(run_id: String, json_user_path: String, text_user_path: String) -> Dictionary:
	return {
		"run_id": run_id,
		"label": report_label,
		"timestamp_unix": Time.get_unix_time_from_system(),
		"godot_version": Engine.get_version_info().get("string", "unknown"),
		"display_server": DisplayServer.get_name(),
		"headless": _headless,
		"scene": "res://scenes/bench/benchmark_city.tscn",
		"city_scene": "res://scenes/city/city.tscn",
		"seed": seed,
		"counts": {
			"pedestrians": pedestrians,
			"traffic_cars": traffic_cars,
			"agents": agents,
			"police": police,
		},
		"frames": {
			"requested_measured": bench_frames,
			"measured": _measured_frames,
			"warmup_requested": warmup_frames,
			"warmup_and_settle": _settle_wait_frames,
		},
		"focus_position": {
			"x": focus_position.x,
			"y": focus_position.y,
			"z": focus_position.z,
		},
		"paths": {
			"json_user": json_user_path,
			"json_abs": ProjectSettings.globalize_path(json_user_path),
			"report_user": text_user_path,
			"report_abs": ProjectSettings.globalize_path(text_user_path),
		},
		"metrics": {
			"process_ms": _summarize(_process_ms),
			"physics_ms": _summarize(_physics_ms),
			"combined_ms": _summarize(_combined_ms),
			"object_count": _summarize(_object_counts),
			"node_count": _summarize(_node_counts),
			"fps": _summarize(_fps_values) if not _headless else {},
		},
		"samples": _samples,
	}


func _summarize(values: Array[float]) -> Dictionary:
	if values.is_empty():
		return {
			"p50": 0.0,
			"p95": 0.0,
			"max": 0.0,
			"samples": 0,
		}

	var sorted_values := values.duplicate()
	sorted_values.sort()
	return {
		"p50": _percentile(sorted_values, 0.50),
		"p95": _percentile(sorted_values, 0.95),
		"max": sorted_values[sorted_values.size() - 1],
		"samples": sorted_values.size(),
	}


func _percentile(sorted_values: Array[float], percentile: float) -> float:
	if sorted_values.is_empty():
		return 0.0

	var index := clampi(ceili(float(sorted_values.size()) * percentile) - 1, 0, sorted_values.size() - 1)
	return sorted_values[index]


func _format_human_report(data: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append("VIBE CITY benchmark report")
	lines.append("==========================")
	lines.append("")
	lines.append("Run: %s" % String(data["run_id"]))
	lines.append("Label: %s" % String(data["label"]))
	lines.append("Godot: %s" % String(data["godot_version"]))
	lines.append("Display: %s%s" % [String(data["display_server"]), " (headless)" if bool(data["headless"]) else ""])
	lines.append("Seed: %d" % int(data["seed"]))
	lines.append("Counts: pedestrians=%d traffic_cars=%d agents=%d police=%d" % [
		int(data["counts"]["pedestrians"]),
		int(data["counts"]["traffic_cars"]),
		int(data["counts"]["agents"]),
		int(data["counts"]["police"]),
	])
	lines.append("Frames: measured=%d warmup_and_settle=%d" % [
		int(data["frames"]["measured"]),
		int(data["frames"]["warmup_and_settle"]),
	])
	lines.append("")
	lines.append(_summary_table_text(data))
	lines.append("")
	lines.append("JSON: %s" % String(data["paths"]["json_abs"]))
	lines.append("Report: %s" % String(data["paths"]["report_abs"]))
	lines.append("")
	return "\n".join(lines)


func _print_summary_table(data: Dictionary) -> void:
	print("")
	print("BENCH SUMMARY %s" % String(data["run_id"]))
	print("counts: pedestrians=%d traffic_cars=%d agents=%d police=%d frames=%d seed=%d display=%s" % [
		int(data["counts"]["pedestrians"]),
		int(data["counts"]["traffic_cars"]),
		int(data["counts"]["agents"]),
		int(data["counts"]["police"]),
		int(data["frames"]["measured"]),
		int(data["seed"]),
		String(data["display_server"]),
	])
	print(_summary_table_text(data))


func _summary_table_text(data: Dictionary) -> String:
	var metrics := data["metrics"] as Dictionary
	var rows: Array[String] = []
	rows.append("| metric | p50 | p95 | max |")
	rows.append("|---|---:|---:|---:|")
	rows.append(_metric_row("process_ms", metrics["process_ms"] as Dictionary, "ms"))
	rows.append(_metric_row("physics_ms", metrics["physics_ms"] as Dictionary, "ms"))
	rows.append(_metric_row("combined_ms", metrics["combined_ms"] as Dictionary, "ms"))
	rows.append(_metric_row("object_count", metrics["object_count"] as Dictionary, ""))
	rows.append(_metric_row("node_count", metrics["node_count"] as Dictionary, ""))
	if metrics.has("fps") and not (metrics["fps"] as Dictionary).is_empty():
		rows.append(_metric_row("fps", metrics["fps"] as Dictionary, ""))
	return "\n".join(rows)


func _metric_row(name: String, metric: Dictionary, suffix: String) -> String:
	return "| %s | %s | %s | %s |" % [
		name,
		_format_metric_value(float(metric["p50"]), suffix),
		_format_metric_value(float(metric["p95"]), suffix),
		_format_metric_value(float(metric["max"]), suffix),
	]


func _format_metric_value(value: float, suffix: String) -> String:
	if suffix.is_empty():
		return "%.0f" % value
	return "%.3f %s" % [value, suffix]


func _write_text_file(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Could not write benchmark file: %s" % path)
		return
	file.store_string(text)
	file.close()


func _run_id() -> String:
	return "%s_p%d_c%d_a%d_pol%d_f%d_seed%d_%d" % [
		_sanitize_label(report_label),
		pedestrians,
		traffic_cars,
		agents,
		police,
		bench_frames,
		seed,
		int(Time.get_unix_time_from_system()),
	]


func _sanitize_label(value: String) -> String:
	var clean := value.strip_edges().to_lower()
	if clean.is_empty():
		clean = DEFAULT_LABEL

	var result := ""
	for character in clean:
		if character.is_valid_identifier() or character.is_valid_int():
			result += character
		elif character in ["-", "_"]:
			result += character
		else:
			result += "_"
	return result


func _print_configuration() -> void:
	print("BENCH CONFIG label=%s pedestrians=%d traffic_cars=%d agents=%d police=%d frames=%d warmup=%d seed=%d display=%s" % [
		report_label,
		pedestrians,
		traffic_cars,
		agents,
		police,
		bench_frames,
		warmup_frames,
		seed,
		DisplayServer.get_name(),
	])


func _set_if_property(object: Object, property_name: String, value: Variant) -> void:
	for property in object.get_property_list():
		if String(property["name"]) == property_name:
			object.set(property_name, value)
			return


func _apply_user_args() -> void:
	var args := OS.get_cmdline_user_args()
	var index := 0
	while index < args.size():
		var arg := String(args[index])
		var name := _arg_name(arg)
		var value := _arg_value(args, index)
		var consumed_value := not arg.contains("=") and not value.is_empty()

		match name:
			"--pedestrians", "--peds":
				pedestrians = maxi(0, int(value))
			"--traffic-cars", "--cars":
				traffic_cars = maxi(0, int(value))
			"--agents":
				agents = maxi(0, int(value))
			"--police":
				police = maxi(0, int(value))
			"--bench-frames", "--frames":
				bench_frames = maxi(1, int(value))
			"--warmup-frames", "--warmup":
				warmup_frames = maxi(0, int(value))
			"--seed":
				seed = int(value)
			"--bench-label", "--label":
				report_label = value

		index += 2 if consumed_value and _is_known_option(name) else 1


func _arg_name(arg: String) -> String:
	if not arg.contains("="):
		return arg
	return arg.split("=", false, 1)[0]


func _arg_value(args: PackedStringArray, index: int) -> String:
	var arg := String(args[index])
	if arg.contains("="):
		var parts := arg.split("=", true, 1)
		return parts[1] if parts.size() > 1 else ""

	if index + 1 < args.size():
		return String(args[index + 1])
	return ""


func _is_known_option(name: String) -> bool:
	return name in [
		"--pedestrians",
		"--peds",
		"--traffic-cars",
		"--cars",
		"--agents",
		"--police",
		"--bench-frames",
		"--frames",
		"--warmup-frames",
		"--warmup",
		"--seed",
		"--bench-label",
		"--label",
	]
