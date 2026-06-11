# Dev tool: render the conversion-zone dev scene for a few frames and save a screenshot.
# Usage: godot --resolution 1280x720 -s scenes/world/dev/conversion_screenshot.gd -- /tmp/conversion_zone.png 90
extends SceneTree

var _frames := 0
var _target_frames := 90
var _out_path := "/tmp/conversion_zone.png"
var _scene_path := "res://scenes/world/dev/conversion_dev.tscn"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_out_path = args[0]
	if args.size() >= 2:
		_target_frames = int(args[1])
	if args.size() >= 3:
		_scene_path = args[2]

	var scene: PackedScene = load(_scene_path)
	root.add_child(scene.instantiate())


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames >= _target_frames:
		var img := root.get_texture().get_image()
		img.save_png(_out_path)
		print("screenshot saved: ", _out_path)
		return true
	return false
