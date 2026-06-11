# Dev tool: render the HUD dev scene for a few frames and save a screenshot.
# Usage: godot --resolution 1920x1080 -s scenes/ui/dev/hud_screenshot.gd -- /tmp/hud_dev.png 420
extends SceneTree

var _frames := 0
var _target_frames := 420
var _out_path := "/tmp/hud_dev.png"
var _scene_path := "res://scenes/ui/dev/hud_dev.tscn"


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
	return false
