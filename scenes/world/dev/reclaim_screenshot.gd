# Dev tool: save before/after screenshots of the reclaim loop.
# Usage: godot --headless --resolution 1280x720 -s scenes/world/dev/reclaim_screenshot.gd -- /tmp/reclaim_before.png /tmp/reclaim_after.png
extends SceneTree

var _before_path := "/tmp/reclaim_before.png"
var _after_path := "/tmp/reclaim_after.png"
var _scene_path := "res://scenes/world/dev/reclaim_dev.tscn"
var _before_frames := 30
var _timeout_msec := 15000
var _frames := 0
var _state := "before"
var _after_started_msec := 0
var _scene: Node


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_before_path = args[0]
	if args.size() >= 2:
		_after_path = args[1]
	if args.size() >= 3:
		_scene_path = args[2]

	var packed_scene: PackedScene = load(_scene_path)
	_scene = packed_scene.instantiate()
	_scene.set("auto_start", false)
	_scene.set("quit_when_complete", false)
	root.add_child(_scene)


func _process(_delta: float) -> bool:
	_frames += 1

	if _state == "before" and _frames >= _before_frames:
		_save_screenshot(_before_path)
		_scene.call("run_reclaim_sequence")
		_state = "after"
		_after_started_msec = Time.get_ticks_msec()
		_frames = 0
		return false

	if _state == "after":
		if bool(_scene.call("has_failed")):
			quit(1)
			return true
		if bool(_scene.call("is_complete")):
			_save_screenshot(_after_path)
			return true
		if Time.get_ticks_msec() - _after_started_msec >= _timeout_msec:
			print("reclaim screenshot failed: timed out waiting for after state")
			quit(1)
			return true

	return false


func _save_screenshot(path: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("screenshot saved: ", path)
