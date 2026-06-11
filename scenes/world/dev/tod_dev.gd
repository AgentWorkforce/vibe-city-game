# Dev tool: render the time-of-day dev scene at sunrise, noon, and night.
# Usage: godot --resolution 1280x720 -s scenes/world/dev/tod_dev.gd
extends SceneTree

const SCENE_PATH := "res://scenes/world/dev/tod_dev.tscn"

var _hours := [7.0, 12.0, 22.0]
var _labels := ["07_sunrise", "12_noon", "22_night"]
var _out_prefix := "/tmp/tod"
var _settle_frames := 45
var _index := 0
var _frames := 0
var _scene: Node
var _time_of_day: Node


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_out_prefix = args[0]
	if args.size() >= 2:
		_settle_frames = int(args[1])

	var packed_scene: PackedScene = load(SCENE_PATH)
	_scene = packed_scene.instantiate()
	root.add_child(_scene)
	_time_of_day = _scene.get_node("TimeOfDay")
	_time_of_day.set_process(false)
	_set_hour_for_current_shot()


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < _settle_frames:
		return false

	if DisplayServer.get_name() == "headless":
		print("tod screenshot failed: display renderer unavailable; run without --headless for rendered captures")
		quit(1)
		return true

	var out_path := "%s_%s.png" % [_out_prefix, _labels[_index]]
	var viewport_texture := root.get_texture()
	if viewport_texture == null:
		print("tod screenshot failed: viewport texture unavailable; run without --headless for rendered captures")
		quit(1)
		return true
	var img := viewport_texture.get_image()
	if img == null:
		print("tod screenshot failed: viewport image unavailable; run without --headless for rendered captures")
		quit(1)
		return true
	img.save_png(out_path)
	print("screenshot saved: ", out_path)

	_index += 1
	if _index >= _hours.size():
		return true

	_set_hour_for_current_shot()
	return false


func _set_hour_for_current_shot() -> void:
	_frames = 0
	_time_of_day.call("set_hour", _hours[_index])
