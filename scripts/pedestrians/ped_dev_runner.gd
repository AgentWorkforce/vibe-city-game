extends Node3D

@export var quit_when_complete: bool = true
@export var fake_impact_after_seconds: float = 0.9
@export var timeout_seconds: float = 6.0

var _elapsed := 0.0
var _impact_sent := false
var _seen_stroll := false
var _seen_flee := false
var _seen_resume := false

@onready var _fake_impact_emitter: Node3D = $FakeImpactEmitter


func _ready() -> void:
	print("PED DEV: ready")
	call_deferred("_bootstrap_demo")


func _bootstrap_demo() -> void:
	for child in get_children():
		if child.has_signal("state_changed"):
			child.connect("state_changed", Callable(self, "_on_pedestrian_state_changed").bind(child))
			if child.has_method("get_state_name"):
				print("PED DEV: %s starts %s" % [child.name, String(child.call("get_state_name"))])


func _process(delta: float) -> void:
	_elapsed += delta

	if not _impact_sent and _elapsed >= fake_impact_after_seconds:
		_emit_fake_impact()

	if _seen_stroll and _seen_flee and _seen_resume:
		print("PED DEV PASS: observed IDLE/STROLL -> FLEE -> RESUME")
		if quit_when_complete:
			get_tree().quit(0)
		return

	if _elapsed >= timeout_seconds:
		print("PED DEV FAIL: transitions missing; STROLL=%s FLEE=%s RESUME=%s" % [
			str(_seen_stroll),
			str(_seen_flee),
			str(_seen_resume),
		])
		if quit_when_complete:
			get_tree().quit(1)


func _emit_fake_impact() -> void:
	_impact_sent = true
	var events := get_node_or_null("/root/Events")
	if events != null and events.has_signal(&"weapon_impact"):
		events.emit_signal(&"weapon_impact", _fake_impact_emitter.global_position)
	print("PED DEV: fake weapon impact emitted at %s" % str(_fake_impact_emitter.global_position))


func _on_pedestrian_state_changed(previous: String, current: String, pedestrian: Node) -> void:
	print("PED DEV: %s %s -> %s" % [pedestrian.name, previous, current])
	if current == "STROLL":
		_seen_stroll = true
	elif current == "FLEE":
		_seen_flee = true
	elif previous == "FLEE" and current == "RESUME":
		_seen_resume = true
