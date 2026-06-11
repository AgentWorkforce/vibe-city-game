extends Node3D
## Engine, tire, and impact audio for the parent VehicleBody3D.
## Engine pitch/volume track speed; tire screech plays while handbraking
## at speed; impacts trigger on hard contacts (requires contact_monitor).

const ENGINE_LOOP: AudioStream = preload("res://assets/audio/sfx/engine_loop.wav")
const TIRE_LOOP: AudioStream = preload("res://assets/audio/sfx/tire_screech_loop.wav")
const IMPACT: AudioStream = preload("res://assets/audio/sfx/impact_crunch.wav")

@export var idle_pitch: float = 0.7
@export var max_pitch: float = 2.1
@export var pitch_full_speed: float = 30.0
@export var idle_volume_db: float = -18.0
@export var driving_volume_db: float = -8.0
@export var screech_min_speed: float = 4.0
@export var impact_min_velocity: float = 4.0
@export var impact_cooldown: float = 0.4

var _car: VehicleBody3D
var _engine: AudioStreamPlayer3D
var _tires: AudioStreamPlayer3D
var _impact: AudioStreamPlayer3D
var _impact_timer: float = 0.0
var _last_velocity: Vector3 = Vector3.ZERO


func _ready() -> void:
	_car = get_parent() as VehicleBody3D
	_engine = _make_player(ENGINE_LOOP, idle_volume_db)
	_tires = _make_player(TIRE_LOOP, -10.0)
	_impact = _make_player(IMPACT, -4.0)
	_engine.play()


func _make_player(audio: AudioStream, volume_db: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = audio
	p.volume_db = volume_db
	p.max_distance = 60.0
	add_child(p)
	return p


func _physics_process(delta: float) -> void:
	if _car == null:
		return

	var speed := _car.linear_velocity.length()
	var driven: bool = bool(_car.get("driven"))

	var speed_ratio := clampf(speed / pitch_full_speed, 0.0, 1.0)
	_engine.pitch_scale = lerpf(idle_pitch, max_pitch, speed_ratio)
	var target_db := driving_volume_db if driven else idle_volume_db
	_engine.volume_db = lerpf(_engine.volume_db, target_db + speed_ratio * 4.0, 1.0 - exp(-6.0 * delta))

	var screeching := driven and Input.is_action_pressed("handbrake") and speed > screech_min_speed
	if screeching and not _tires.playing:
		_tires.play()
	elif not screeching and _tires.playing:
		_tires.stop()

	_impact_timer = maxf(_impact_timer - delta, 0.0)
	var dv := (_car.linear_velocity - _last_velocity).length()
	if dv > impact_min_velocity and _impact_timer <= 0.0 and _car.get_contact_count() > 0:
		_impact.volume_db = lerpf(-10.0, 0.0, clampf(dv / 15.0, 0.0, 1.0))
		_impact.play()
		_impact_timer = impact_cooldown
	_last_velocity = _car.linear_velocity
