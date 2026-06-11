# Integration test: enter the car, drive forward, exit.
# Usage: godot --headless -s tools/test_drive.gd
# Simulates input actions against the real main scene and asserts the
# player->car->player handoff plus actual car movement.
extends SceneTree

var _frames := 0
var _failures: Array[String] = []
var _player: Node3D
var _body: CharacterBody3D
var _car: Node3D
var _car_start: Vector3


func _initialize() -> void:
	var scene: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene"))
	root.add_child(scene.instantiate())
	_player = root.get_node("Playground/Player")
	_body = _player.get_node("Body")
	_car = root.get_node("Playground/Car")


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures.append(msg)


func _process(_delta: float) -> bool:
	_frames += 1
	match _frames:
		20:
			# Walk-up shortcut: teleport next to the car.
			_body.global_position = _car.global_position + Vector3(3.0, 0.5, 0)
		40:
			Input.action_press("interact")
		42:
			Input.action_release("interact")
		60:
			_check(not _player.visible, "player still visible after entering car")
			_check(_car.get("driven") == true, "car not driven after interact")
			_car_start = _car.global_position
			Input.action_press("move_forward")
		240:
			Input.action_release("move_forward")
			var dist: float = (_car.global_position - _car_start).length()
			_check(dist > 5.0, "car barely moved while driving: %.2f m" % dist)
		260:
			Input.action_press("interact")
		262:
			Input.action_release("interact")
		290:
			_check(_player.visible, "player not visible after exiting car")
			_check(_car.get("driven") == false, "car still driven after exit")
			_check(_body.global_position.distance_to(_car.global_position) < 8.0,
				"player exited too far from car")
		300:
			if _failures.is_empty():
				print("DRIVE TEST PASS (car moved, handoff both ways)")
				quit(0)
			else:
				for f in _failures:
					print("DRIVE TEST FAIL: ", f)
				quit(1)
	return false
