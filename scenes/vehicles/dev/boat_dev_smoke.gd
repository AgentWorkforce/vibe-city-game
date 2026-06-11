extends Node3D

const START_FRAME := 45
const DRIVE_FRAMES := 180
const MIN_DISTANCE_METERS := 5.0

var _frame := 0
var _boat: Node3D
var _start_position := Vector3.ZERO
var _failures: Array[String] = []


func _ready() -> void:
	_boat = get_node_or_null("Boat") as Node3D
	if not is_instance_valid(_boat):
		_failures.append("Boat node missing")


func _physics_process(_delta: float) -> void:
	_frame += 1

	if _frame == START_FRAME:
		if is_instance_valid(_boat):
			_boat.set("driven", true)
			_start_position = _boat.global_position
			Input.action_press("move_forward")

	if _frame == START_FRAME + DRIVE_FRAMES:
		Input.action_release("move_forward")
		if is_instance_valid(_boat):
			var distance := _boat.global_position.distance_to(_start_position)
			if distance <= MIN_DISTANCE_METERS:
				_failures.append("boat moved %.2f m" % distance)
		_finish()


func _finish() -> void:
	Input.action_release("move_forward")
	if _failures.is_empty():
		print("BOAT DEV PASS (forward displacement > %.1f m)" % MIN_DISTANCE_METERS)
		get_tree().quit(0)
	else:
		for failure in _failures:
			print("BOAT DEV FAIL: ", failure)
		get_tree().quit(1)
