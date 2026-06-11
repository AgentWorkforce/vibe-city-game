# Integration test: destroy all conversion pylons in the real main scene
# and assert the district liberates (control flips, grid fades, walls gone).
# Usage: godot --headless -s tools/test_reclaim.gd
# Poll-based: under headless -s, frame time is uncapped, so time-based
# tweens cannot be asserted at fixed frame numbers. Autoloads are also
# absent in -s mode, so control is read from the zone API, not Events.
extends SceneTree

const Health = preload("res://scripts/combat/health.gd")
const MAX_FRAMES := 8000

var _frames := 0
var _zone: Node3D
var _sanity_done := false


func _initialize() -> void:
	var scene: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene"))
	root.add_child(scene.instantiate())
	_zone = root.get_node("Playground/ConversionZone")


func _fail(msg: String) -> bool:
	print("RECLAIM TEST FAIL: ", msg)
	quit(1)
	return true


func _process(_delta: float) -> bool:
	_frames += 1

	if _frames == 30:
		_sanity_done = true
		if _zone.call("get_control") != 1.0:
			return _fail("zone not fully agent-held at start")
		if int(_zone.call("get_total_pylon_count")) < 3:
			return _fail("expected at least 3 pylons")

	# Kill one alive pylon every 30 frames once sanity passed.
	if _sanity_done and _frames % 30 == 0 and int(_zone.call("get_alive_pylon_count")) > 0:
		for health in _zone.find_children("Health", "Health", true, false):
			var h := health as Health
			if h != null and not h.is_dead:
				h.apply_damage(999.0, null)
				break

	# Poll for full liberation.
	if _sanity_done and bool(_zone.call("is_liberated")) \
			and bool(_zone.call("is_grid_faded")) \
			and bool(_zone.call("are_boundary_walls_gone")):
		var control := float(_zone.call("get_control"))
		if absf(control + 1.0) > 0.001:
			return _fail("final control not -1.0 (human): %f" % control)
		print("RECLAIM TEST PASS (district liberated after %d frames, control %.1f)" % [_frames, control])
		quit(0)
		return true

	if _frames >= MAX_FRAMES:
		return _fail("liberation incomplete after %d frames (liberated=%s grid_faded=%s walls_gone=%s)" % [
			MAX_FRAMES, _zone.call("is_liberated"), _zone.call("is_grid_faded"),
			_zone.call("are_boundary_walls_gone")])
	return false
