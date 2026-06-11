# Dev tool: render the main scene for a few frames and save a screenshot.
# Usage: godot -s tools/screenshot.gd [-- <output_path> <frames>]
extends SceneTree

var _frames := 0
var _target_frames := 30
var _out_path := "/tmp/vibe_city_screenshot.png"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_out_path = args[0]
	if args.size() >= 2:
		_target_frames = int(args[1])
	var scene: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene"))
	root.add_child(scene.instantiate())


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames >= _target_frames:
		var img := root.get_texture().get_image()
		img.save_png(_out_path)
		print("screenshot saved: ", _out_path)
		return true
	return false
