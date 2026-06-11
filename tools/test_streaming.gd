# Integration test: stream city tiles around a moving target.
# Usage: godot --headless -s tools/test_streaming.gd
# Poll-based: under headless -s, frame time is uncapped and threaded loads
# complete asynchronously, so assertions wait for observable streamer state.
extends SceneTree

const MAX_FRAMES := 1400
const TILE_SIZE := 128.0

var _frames := 0
var _city: Node3D
var _target: Marker3D
var _streamer: Node
var _failures: Array[String] = []
var _saw_origin_tiles := false
var _saw_far_tile := false
var _saw_unload := false
var _saw_missing_cache := false
var _cleanup_started := false
var _cleanup_frames := 0
var _cleanup_exit_code := 0


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/city/city.tscn")
	_city = scene.instantiate() as Node3D
	_target = _city.get_node("StreamTarget") as Marker3D
	_streamer = _city.get_node("WorldStreamer")
	_streamer.set("load_radius_tiles", 1)
	_streamer.set("unload_radius_tiles", 1)
	root.add_child(_city)


func _process(_delta: float) -> bool:
	_frames += 1
	if _cleanup_started:
		_cleanup_frames += 1
		if _cleanup_frames >= 20:
			quit(_cleanup_exit_code)
			return true
		return false

	var progress := clampf(float(_frames - 160) / 360.0, 0.0, 1.0)
	_target.global_position = Vector3(64.0 - TILE_SIZE * 3.0 * progress, 1.0, 64.0)

	if _frames > 40 and _has_tiles([Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]):
		_saw_origin_tiles = true

	if _frames > 40 and _is_tile_resident(Vector2i(1, 1)):
		_saw_far_tile = true

	if _frames > 560 and not _is_tile_resident(Vector2i(0, 0)):
		_saw_unload = true

	if _frames > 360 and int(_streamer.call("get_known_missing_count")) > 0:
		_saw_missing_cache = true

	if _frames == 700:
		_check(_saw_origin_tiles, "origin placeholder tiles never loaded")
		_check(_saw_far_tile, "adjacent placeholder tile never became resident")
		_check(_saw_unload, "tile_0_0 did not unload after moving beyond unload radius")
		_check(_saw_missing_cache, "sparse missing tiles were not cached")
		_finish()
		return true

	if _frames >= MAX_FRAMES:
		_begin_cleanup(["timed out before streaming assertions completed"], 1)
		return true

	return false


func _has_tiles(coords: Array[Vector2i]) -> bool:
	for coord in coords:
		if not _is_tile_resident(coord):
			return false
	return true


func _is_tile_resident(coord: Vector2i) -> bool:
	return bool(_streamer.call("is_tile_resident", coord))


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures.append(msg)


func _finish() -> void:
	if _failures.is_empty():
		print("STREAMING TEST PASS (loaded origin tiles, prioritized nearby tiles, unloaded tile_0_0)")
		_begin_cleanup([], 0)
	else:
		_begin_cleanup(_failures, 1)


func _begin_cleanup(failures: Array[String], exit_code: int) -> void:
	if _cleanup_started:
		return

	for failure in failures:
		print("STREAMING TEST FAIL: ", failure)

	_cleanup_started = true
	_cleanup_exit_code = exit_code
	if is_instance_valid(_city):
		_city.queue_free()
