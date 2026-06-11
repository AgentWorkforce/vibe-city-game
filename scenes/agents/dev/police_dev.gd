extends Node3D

const WantedSystem = preload("res://scripts/systems/wanted_system.gd")

@export var quit_when_complete: bool = true
@export var timeout_seconds: float = 4.0

var _wanted: Node
var _elapsed := 0.0
var _crime_sent := false
var _pursuit_seen := false

@onready var _police: Node3D = $PoliceAgent
@onready var _player: CharacterBody3D = $DummyPlayer


func _ready() -> void:
	print("POLICE DEV: ready")
	call_deferred("_bootstrap_demo")


func _bootstrap_demo() -> void:
	_ensure_wanted()
	if _wanted.has_method("clear"):
		_wanted.call("clear")

	var events := _events()
	var wanted_callable := Callable(self, "_on_wanted_changed")
	if events != null and not events.is_connected(&"wanted_changed", wanted_callable):
		events.connect(&"wanted_changed", wanted_callable)

	var bark_callable := Callable(self, "_on_bark_emitted")
	if events != null and not events.is_connected(&"bark_emitted", bark_callable):
		events.connect(&"bark_emitted", bark_callable)

	if _police.has_signal("player_caught"):
		_police.connect("player_caught", Callable(self, "_on_player_caught"))

	_start_demo()


func _process(delta: float) -> void:
	_elapsed += delta

	if _crime_sent and not _pursuit_seen and _police.has_method("get_police_state_name"):
		var state := String(_police.call("get_police_state_name"))
		if state == "PURSUE" or state == "CATCH":
			_pursuit_seen = true
			print("POLICE DEV: police reached %s at wanted level %d" % [
				state,
				_wanted_level(),
			])
			print("POLICE DEV PASS: crime -> wanted level %d -> police %s" % [
				_wanted_level(),
				state,
			])
			if quit_when_complete:
				get_tree().quit(0)

	if _elapsed >= timeout_seconds:
		print("POLICE DEV FAIL: pursuit was not observed")
		if quit_when_complete:
			get_tree().quit(1)


func _ensure_wanted() -> void:
	_wanted = get_node_or_null("/root/Wanted")
	if _wanted != null:
		return

	_wanted = WantedSystem.new()
	_wanted.name = "Wanted"
	get_tree().root.add_child(_wanted)


func _start_demo() -> void:
	var events := _events()
	if events != null:
		events.emit_signal(&"crime_committed", 1, _player.global_position)
	_crime_sent = true
	print("POLICE DEV: emitted severity 1 crime")


func _wanted_level() -> int:
	if _wanted != null and _wanted.has_method("get_level"):
		return int(_wanted.call("get_level"))
	return -1


func _on_wanted_changed(level: int) -> void:
	print("POLICE DEV: wanted level changed to %d" % level)


func _on_bark_emitted(speaker: Node, category: StringName, text: String) -> void:
	if speaker == _police:
		print("POLICE DEV BARK [%s]: %s" % [String(category), text])


func _on_player_caught(player: Node) -> void:
	print("POLICE DEV: player caught by %s" % _police.name)


func _events() -> Node:
	return get_node_or_null("/root/Events")
