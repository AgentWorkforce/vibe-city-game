# Integration test: grab a ladder by pushing into it, climb to the top,
# mantle onto the ledge. Usage: godot --headless -s tools/test_climb.gd
extends SceneTree

var _frames := 0
var _failures: Array[String] = []
var _body: CharacterBody3D
var _grab_height := 0.0


func _initialize() -> void:
	var scene: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene"))
	root.add_child(scene.instantiate())
	_body = root.get_node("Playground/Player/Body")


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures.append(msg)


func _process(_delta: float) -> bool:
	_frames += 1
	match _frames:
		20:
			# North of the 3m ledge wall's north face; ladder zone is there.
			_body.global_position = Vector3(26, 0.1, -4.6)
		30:
			# Default camera faces -Z; the wall is south (+Z): push move_back.
			Input.action_press("move_back")
		90:
			_grab_height = _body.global_position.y
			_check(_body.global_position.z > -4.4,
				"player did not walk toward the wall (z=%.2f)" % _body.global_position.z)
		300:
			_check(_body.global_position.y > _grab_height + 2.0,
				"player did not climb: y=%.2f (grab y=%.2f)" % [_body.global_position.y, _grab_height])
		420:
			Input.action_release("move_back")
			_check(_body.global_position.y > 2.7,
				"player not on top of 3m ledge: y=%.2f" % _body.global_position.y)
			_check(_body.is_on_floor() or _body.velocity.y != 0.0, "player in limbo at top")
		440:
			if _failures.is_empty():
				print("CLIMB TEST PASS (grabbed, climbed, mantled y=%.2f)" % _body.global_position.y)
				quit(0)
			else:
				for f in _failures:
					print("CLIMB TEST FAIL: ", f)
				quit(1)
	return false
