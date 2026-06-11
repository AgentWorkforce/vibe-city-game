extends Node

@export var police_scene: PackedScene = preload("res://scenes/agents/police_agent.tscn")
@export var desired_police_by_wanted_level := PackedInt32Array([1, 2, 3, 4, 5, 7])
@export var spawn_min_distance: float = 25.0
@export var spawn_max_distance: float = 42.0
@export var despawn_distance: float = 60.0
@export var spawn_interval: float = 0.75
@export var debug_spawning: bool = false

var _wanted_level := 0
var _spawn_timer := 0.0
var _police: Array[Node3D] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_wanted_level = _read_wanted_level()

	var events := _events()
	var changed_callable := Callable(self, "_on_wanted_changed")
	if events != null and not events.is_connected(&"wanted_changed", changed_callable):
		events.connect(&"wanted_changed", changed_callable)


func _process(delta: float) -> void:
	_wanted_level = _read_wanted_level()
	_prune_invalid()

	var player := _find_player()
	if player == null:
		return

	var desired := _desired_count()
	_despawn_far_or_extra(player, desired)

	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	_spawn_timer = spawn_interval

	while _police.size() < desired:
		if not _spawn_police(player):
			return


func _on_wanted_changed(level: int) -> void:
	_wanted_level = clampi(level, 0, 5)
	_spawn_timer = 0.0


func _read_wanted_level() -> int:
	var wanted := get_node_or_null("/root/Wanted")
	if wanted != null and wanted.has_method("get_level"):
		return clampi(int(wanted.call("get_level")), 0, 5)
	return _wanted_level


func _desired_count() -> int:
	if desired_police_by_wanted_level.is_empty():
		return 0

	var index := clampi(_wanted_level, 0, desired_police_by_wanted_level.size() - 1)
	return max(0, desired_police_by_wanted_level[index])


func _spawn_police(player: Node3D) -> bool:
	if police_scene == null:
		return false

	var spawned := police_scene.instantiate() as Node3D
	if spawned == null:
		return false

	var parent := get_parent()
	if parent == null:
		parent = self
	parent.add_child(spawned)
	spawned.global_position = _pick_spawn_position(player)
	_police.append(spawned)

	if debug_spawning:
		print("PoliceSpawner: spawned police at %s for wanted %d" % [
			spawned.global_position,
			_wanted_level,
		])

	return true


func _pick_spawn_position(player: Node3D) -> Vector3:
	var min_distance := maxf(spawn_min_distance, 0.0)
	var max_distance := maxf(spawn_max_distance, min_distance)
	var angle := _rng.randf_range(0.0, TAU)
	var distance := _rng.randf_range(min_distance, max_distance)
	return player.global_position + Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)


func _despawn_far_or_extra(player: Node3D, desired: int) -> void:
	var far_distance_squared := despawn_distance * despawn_distance
	for police in _police.duplicate():
		if not is_instance_valid(police):
			_police.erase(police)
			continue
		if police.global_position.distance_squared_to(player.global_position) > far_distance_squared:
			_remove_police(police)

	while _police.size() > desired:
		var farthest := _find_farthest_police(player)
		if farthest == null:
			return
		_remove_police(farthest)


func _find_farthest_police(player: Node3D) -> Node3D:
	var farthest: Node3D
	var farthest_distance := -1.0
	for police in _police:
		if not is_instance_valid(police):
			continue

		var distance := police.global_position.distance_squared_to(player.global_position)
		if distance > farthest_distance:
			farthest_distance = distance
			farthest = police

	return farthest


func _remove_police(police: Node3D) -> void:
	_police.erase(police)
	if is_instance_valid(police):
		if debug_spawning:
			print("PoliceSpawner: despawned police at %s" % police.global_position)
		police.queue_free()


func _prune_invalid() -> void:
	for police in _police.duplicate():
		if not is_instance_valid(police):
			_police.erase(police)


func _find_player() -> Node3D:
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as Node3D
		if player != null:
			return player
	return null


func _events() -> Node:
	return get_node_or_null("/root/Events")
