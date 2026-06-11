extends AudioStreamPlayer3D
## Plays stride-timed footsteps and landing thuds for the parent CharacterBody3D.
## Surface type is classified from the floor collider's name (blockout-era
## heuristic; districts will use physics layers/groups later).

const CONCRETE_STREAMS: Array[AudioStream] = [
	preload("res://assets/audio/sfx/footstep_concrete_1.wav"),
	preload("res://assets/audio/sfx/footstep_concrete_2.wav"),
	preload("res://assets/audio/sfx/footstep_concrete_3.wav"),
	preload("res://assets/audio/sfx/footstep_concrete_4.wav"),
]
const SAND_STREAMS: Array[AudioStream] = [
	preload("res://assets/audio/sfx/footstep_sand_1.wav"),
	preload("res://assets/audio/sfx/footstep_sand_2.wav"),
	preload("res://assets/audio/sfx/footstep_sand_4.wav"),
	preload("res://assets/audio/sfx/footstep_sand_3.wav"),
]
const LAND_STREAM: AudioStream = preload("res://assets/audio/sfx/land_thud.wav")

const CONCRETE_NAME_HINTS := [
	"road", "curb", "ramp", "step", "stair", "platform", "slope", "ledge",
	"building", "block",
]

@export var stride_length: float = 1.7
@export var min_interval: float = 0.28
@export var max_interval: float = 0.75
@export var min_speed: float = 0.8
@export var land_velocity_threshold: float = 2.5

var _body: CharacterBody3D
var _step_timer: float = 0.0
var _was_on_floor: bool = true
var _last_fall_speed: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_body = get_parent() as CharacterBody3D


func _physics_process(delta: float) -> void:
	if _body == null:
		return

	var on_floor := _body.is_on_floor()
	if not on_floor:
		_last_fall_speed = maxf(_last_fall_speed, -_body.velocity.y)
	if on_floor and not _was_on_floor and _last_fall_speed > land_velocity_threshold:
		_play_stream(LAND_STREAM)
	if on_floor:
		_last_fall_speed = 0.0
	_was_on_floor = on_floor

	var speed := Vector2(_body.velocity.x, _body.velocity.z).length()
	if not on_floor or speed < min_speed:
		_step_timer = 0.1
		return

	_step_timer -= delta
	if _step_timer <= 0.0:
		_play_footstep()
		_step_timer = clampf(stride_length / speed, min_interval, max_interval)


func _play_footstep() -> void:
	var streams := SAND_STREAMS
	if _floor_is_concrete():
		streams = CONCRETE_STREAMS
	_play_stream(streams[_rng.randi_range(0, streams.size() - 1)])


func _play_stream(audio: AudioStream) -> void:
	stream = audio
	pitch_scale = _rng.randf_range(0.92, 1.08)
	play()


func _floor_is_concrete() -> bool:
	var space := _body.get_world_3d().direct_space_state
	var from := _body.global_position + Vector3.UP * 0.1
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 0.6)
	query.exclude = [_body.get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return false
	var collider: Object = hit.get("collider")
	if collider == null or not (collider is Node):
		return false
	var node := collider as Node
	# Check the collider and one ancestor (obstacles are grouped under
	# container nodes like "Staircase"/"Slopes").
	for candidate in [node, node.get_parent()]:
		if candidate == null:
			continue
		var lower := String(candidate.name).to_lower()
		for hint in CONCRETE_NAME_HINTS:
			if lower.contains(hint):
				return true
	return false
