extends Node3D

const Health = preload("res://scripts/combat/health.gd")

@export var auto_start := true
@export var quit_when_complete := true
@export var start_delay_seconds := 0.35
@export var damage_interval_seconds := 0.45
@export var settle_seconds := 2.35

var _complete := false
var _failed := false
var _running := false
var _control_events: Array[float] = []

@onready var _zone: Node = $ConversionZone


func _ready() -> void:
	print("RECLAIM DEV: ready")
	_connect_events()
	if auto_start:
		call_deferred("run_reclaim_sequence")


func run_reclaim_sequence() -> void:
	if _running:
		return

	_running = true
	_complete = false
	_failed = false
	_control_events.clear()

	await get_tree().create_timer(start_delay_seconds).timeout

	var pylon_health := _collect_pylon_health()
	print("RECLAIM DEV: pylons=%d initial_control=%.2f" % [pylon_health.size(), _zone.call("get_control")])
	if pylon_health.is_empty():
		_fail("no pylon Health children found")
		return

	for health in pylon_health:
		if not is_instance_valid(health):
			continue
		var pylon := health.get_parent()
		print("RECLAIM DEV: applying 75 damage to %s" % pylon.name)
		health.apply_damage(75.0, self)
		await get_tree().create_timer(damage_interval_seconds).timeout

	await get_tree().create_timer(settle_seconds).timeout
	_assert_final_state()


func is_complete() -> bool:
	return _complete


func has_failed() -> bool:
	return _failed


func _connect_events() -> void:
	var events := _events()
	if events == null:
		return

	var control_callable := Callable(self, "_on_district_control_changed")
	if not events.is_connected(&"district_control_changed", control_callable):
		events.connect(&"district_control_changed", control_callable)

	var bark_callable := Callable(self, "_on_bark_emitted")
	if not events.is_connected(&"bark_emitted", bark_callable):
		events.connect(&"bark_emitted", bark_callable)


func _collect_pylon_health() -> Array[Health]:
	var result: Array[Health] = []
	for node in _zone.find_children("Health", "Health", true, false):
		var health := node as Health
		if health != null:
			result.append(health)
	return result


func _assert_final_state() -> void:
	var final_control := float(_zone.call("get_control"))
	var liberated := bool(_zone.call("is_liberated"))
	var grid_faded := bool(_zone.call("is_grid_faded"))
	var walls_gone := bool(_zone.call("are_boundary_walls_gone"))

	if absf(final_control - -1.0) > 0.001:
		_fail("final control expected -1.00, got %.2f" % final_control)
		return
	if not liberated:
		_fail("zone did not enter liberated state")
		return
	if not grid_faded:
		_fail("grid did not fade out")
		return
	if not walls_gone:
		_fail("boundary walls did not disappear")
		return
	if _control_events.size() != 4:
		_fail("expected 4 control events, got %d" % _control_events.size())
		return

	print("RECLAIM DEV PASS: final_control=%.2f grid_faded=%s walls_gone=%s events=%s" % [
		final_control,
		str(grid_faded),
		str(walls_gone),
		str(_control_events),
	])
	_complete = true
	_running = false
	if quit_when_complete:
		get_tree().quit(0)


func _fail(message: String) -> void:
	_failed = true
	_complete = true
	_running = false
	push_error("RECLAIM DEV FAIL: %s" % message)
	print("RECLAIM DEV FAIL: %s" % message)
	if quit_when_complete:
		get_tree().quit(1)


func _on_district_control_changed(district: StringName, control: float) -> void:
	print("RECLAIM DEV: control %s = %.2f" % [String(district), control])
	_control_events.append(control)


func _on_bark_emitted(_speaker: Node, category: StringName, text: String) -> void:
	if category == &"district_converting" or category == &"district_liberated":
		print("RECLAIM DEV BARK [%s]: %s" % [String(category), text])


func _events() -> Node:
	return get_node_or_null("/root/Events")
