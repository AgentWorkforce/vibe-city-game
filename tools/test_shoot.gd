# Integration test: aim and fire the player blaster.
# Usage: godot --headless -s tools/test_shoot.gd
# Loads the real main scene, creates a Health target on the camera ray, and
# asserts that a tracer appears and the target takes hitscan damage.
extends SceneTree

const HealthScript = preload("res://scripts/combat/health.gd")

var _frames := 0
var _failures: Array[String] = []
var _player: Node3D
var _camera: Camera3D
var _target: StaticBody3D
var _target_health: Node
var _saw_tracer := false


func _initialize() -> void:
	var scene: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene"))
	root.add_child(scene.instantiate())
	_player = root.get_node("Playground/Player")
	_camera = _player.get_node("CameraRig/Pitch/SpringArm3D/Camera3D")


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures.append(msg)


func _process(_delta: float) -> bool:
	_frames += 1
	if not get_nodes_in_group("weapon_tracer").is_empty():
		_saw_tracer = true

	match _frames:
		20:
			_place_target_on_camera_ray()
		40:
			Input.action_press("aim")
			Input.action_press("fire")
		42:
			Input.action_release("fire")
		80:
			Input.action_release("aim")
			_check(_saw_tracer, "no weapon tracer appeared after firing")
			var current_health := _target_health_value()
			_check(current_health <= 75.0, "target health was not damaged: %.2f" % current_health)
		300:
			if _failures.is_empty():
				print("SHOOT TEST PASS (tracer spawned, target health %.2f)" % _target_health_value())
				quit(0)
			else:
				for failure in _failures:
					print("SHOOT TEST FAIL: ", failure)
				quit(1)
	return false


func _place_target_on_camera_ray() -> void:
	var origin := _camera.global_position
	var direction := -_camera.global_transform.basis.z.normalized()

	_target = StaticBody3D.new()
	_target.name = "ShootTestTarget"

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 2.0, 2.0)
	shape.shape = box
	_target.add_child(shape)

	_target_health = HealthScript.new()
	_target_health.name = "Health"
	_target_health.set("max_health", 100.0)
	_target.add_child(_target_health)

	var playground := root.get_node("Playground") as Node3D
	playground.add_child(_target)
	_target.global_position = origin + direction * 14.0


func _target_health_value() -> float:
	return float(_target_health.get("current"))
