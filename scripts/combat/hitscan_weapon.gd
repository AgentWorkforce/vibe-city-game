extends Node3D
## Player hitscan blaster. The rig is parented under Body so the weapon visual
## follows the character, but all shots raycast from the active camera center.

const HealthScript = preload("res://scripts/combat/health.gd")
const SHOT_STREAM_PATH := "res://assets/audio/sfx/blaster_shot.wav"

@export var camera_path: NodePath = NodePath("../../CameraRig/Pitch/SpringArm3D/Camera3D")
@export var camera_rig_path: NodePath = NodePath("../../CameraRig")
@export var player_body_path: NodePath = NodePath("..")
@export var muzzle_path: NodePath = NodePath("Muzzle")
@export var shot_range: float = 60.0
@export var damage: float = 25.0
@export var shots_per_second: float = 5.0
@export var recoil_pitch_degrees: float = 0.4
@export var tracer_lifetime: float = 0.07
@export var impact_lifetime: float = 0.14

var _camera: Camera3D
var _camera_rig: Node
var _player_body: CollisionObject3D
var _muzzle: Node3D
var _crosshair: Node
var _shot_audio: AudioStreamPlayer3D
var _cooldown: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_camera = get_node_or_null(camera_path) as Camera3D
	_camera_rig = get_node_or_null(camera_rig_path)
	_player_body = get_node_or_null(player_body_path) as CollisionObject3D
	_muzzle = get_node_or_null(muzzle_path) as Node3D
	_crosshair = get_node_or_null("Crosshair")
	_shot_audio = get_node_or_null("ShotAudio") as AudioStreamPlayer3D
	if _shot_audio != null and _shot_audio.stream == null:
		_shot_audio.stream = load(SHOT_STREAM_PATH) as AudioStream
	_rng.randomize()


func _process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if Input.is_action_pressed("fire") and _cooldown <= 0.0:
		_fire()
		_cooldown = 1.0 / maxf(shots_per_second, 0.01)


func _fire() -> void:
	if _camera == null:
		return

	var origin := _camera.global_position
	var direction := -_camera.global_transform.basis.z.normalized()
	var max_point := origin + direction * shot_range
	var hit_point := max_point
	var hit_normal := -direction

	var query := PhysicsRayQueryParameters3D.create(origin, max_point)
	if _player_body != null:
		query.exclude = [_player_body.get_rid()]
	var hit := _camera.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		hit_point = hit["position"]
		hit_normal = hit.get("normal", hit_normal)
		_apply_hit_damage(hit.get("collider"))
		_spawn_impact(hit_point, hit_normal)

	_emit_weapon_impact(hit_point)
	_spawn_tracer(_get_muzzle_position(), hit_point)
	_play_shot_audio()
	_apply_recoil()
	if _crosshair != null and _crosshair.has_method("show_after_fire"):
		_crosshair.call("show_after_fire")


func _apply_hit_damage(collider: Variant) -> void:
	if not (collider is Node):
		return

	var health: Node = HealthScript.find_in(collider as Node)
	if health != null:
		health.call("apply_damage", damage, self)


func _get_muzzle_position() -> Vector3:
	if is_instance_valid(_muzzle):
		return _muzzle.global_position
	return global_position


func _spawn_tracer(start: Vector3, end: Vector3) -> void:
	var delta := end - start
	var length := delta.length()
	if length <= 0.01:
		return

	var tracer := MeshInstance3D.new()
	tracer.name = "WeaponTracer"
	tracer.add_to_group("weapon_tracer")
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.035, 0.035, length)
	tracer.mesh = mesh
	tracer.material_override = _make_emissive_material(Color(0.45, 1.0, 1.0, 0.9), 2.6)
	_add_world_effect(tracer)
	tracer.global_position = start.lerp(end, 0.5)
	tracer.look_at(end, Vector3.UP)

	var timer := get_tree().create_timer(tracer_lifetime)
	timer.timeout.connect(tracer.queue_free)


func _spawn_impact(position: Vector3, normal: Vector3) -> void:
	var impact := MeshInstance3D.new()
	impact.name = "WeaponImpact"
	var mesh := SphereMesh.new()
	mesh.radius = 0.08
	mesh.height = 0.16
	impact.mesh = mesh
	impact.material_override = _make_emissive_material(Color(0.35, 1.0, 1.0, 0.85), 3.0)
	_add_world_effect(impact)
	impact.global_position = position + normal.normalized() * 0.035
	impact.scale = Vector3.ONE * 0.12

	var tween := impact.create_tween()
	tween.tween_property(impact, "scale", Vector3.ONE * 0.55, impact_lifetime)
	tween.tween_callback(impact.queue_free)


func _emit_weapon_impact(position: Vector3) -> void:
	var events := get_node_or_null("/root/Events")
	if events != null and events.has_signal(&"weapon_impact"):
		events.emit_signal(&"weapon_impact", position)


func _add_world_effect(effect: Node3D) -> void:
	var parent := get_tree().current_scene
	if parent == null:
		parent = get_tree().root
	parent.add_child(effect)


func _make_emissive_material(color: Color, emission_energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = Color(color.r, color.g, color.b)
	material.emission_energy_multiplier = emission_energy
	return material


func _play_shot_audio() -> void:
	if _shot_audio == null:
		return
	_shot_audio.pitch_scale = _rng.randf_range(0.94, 1.06)
	_shot_audio.play()


func _apply_recoil() -> void:
	if _camera_rig != null and _camera_rig.has_method("add_recoil"):
		_camera_rig.call("add_recoil", recoil_pitch_degrees)
