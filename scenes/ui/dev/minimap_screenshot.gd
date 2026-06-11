# Dev tool: render the minimap dev scene for a few frames and save a screenshot.
# Usage: godot --resolution 1920x1080 -s scenes/ui/dev/minimap_screenshot.gd -- /tmp/minimap_dev.png 240
extends SceneTree

var _frames := 0
var _target_frames := 240
var _out_path := "/tmp/minimap_dev.png"
var _scene_path := "res://scenes/ui/dev/minimap_dev.tscn"


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
	if _frames < _target_frames:
		return false

	if DisplayServer.get_name() == "headless":
		print("screenshot skipped: viewport texture is unavailable with the headless display driver")
		return true

	var texture := root.get_texture()
	if texture == null:
		print("screenshot skipped: viewport texture is unavailable")
		return true

	var img := texture.get_image()
	if img == null:
		print("screenshot skipped: viewport image is unavailable")
		return true

	img.save_png(_out_path)
	print("screenshot saved: ", _out_path)
	return true
