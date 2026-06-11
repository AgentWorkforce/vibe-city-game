extends Node3D

const BarkSystem = preload("res://scripts/agents/bark_system.gd")
const Health = preload("res://scripts/combat/health.gd")

const CYAN := Color(0.098, 0.89, 0.89, 1.0)
const WARM_TINT := Color(1.0, 0.48, 0.42, 0.08)
const CREAM := Color(1.0, 0.92, 0.78, 1.0)
const PINK := Color(1.0, 0.38, 0.58, 1.0)

@export var district_name: StringName = &"playground_nw"
@export var pylon_collapse_seconds: float = 0.5
@export var liberation_fade_seconds: float = 2.0
@export var wall_sink_depth: float = 3.6

var _barks := BarkSystem.new()
var _health_to_pylon: Dictionary = {}
var _dead_health: Dictionary = {}
var _pylon_health: Array[Health] = []
var _pylons: Array[Node3D] = []
var _boundary_walls: Array[MeshInstance3D] = []
var _total_pylons := 0
var _alive_pylons := 0
var _control := 1.0
var _grid_fade_alpha := 1.0
var _boundary_fade_alpha := 1.0
var _warm_tint_alpha := 0.0
var _liberated := false
var _boundaries_gone := false
var _grid_material: ShaderMaterial
var _boundary_material: ShaderMaterial
var _warm_tint_material: StandardMaterial3D

@onready var _ground_overlay: MeshInstance3D = $GroundOverlay
@onready var _boundaries: Node3D = $Boundaries
@onready var _warm_tint: MeshInstance3D = $WarmTint


func _ready() -> void:
	_prepare_materials()
	_collect_pylons()
	_refresh_control()
	_apply_control_visuals()


func get_control() -> float:
	return _control


func get_alive_pylon_count() -> int:
	return _alive_pylons


func get_total_pylon_count() -> int:
	return _total_pylons


func is_liberated() -> bool:
	return _liberated


func is_grid_faded() -> bool:
	return _grid_fade_alpha <= 0.01 and (not is_instance_valid(_ground_overlay) or not _ground_overlay.visible)


func are_boundary_walls_gone() -> bool:
	return _boundaries_gone


func get_distress() -> float:
	if _total_pylons <= 0:
		return 1.0
	return 1.0 - (float(_alive_pylons) / float(_total_pylons))


func _prepare_materials() -> void:
	_grid_material = _unique_shader_material(_ground_overlay)
	_set_grid_fade_alpha(1.0)

	_boundary_walls.clear()
	for node in _boundaries.find_children("*", "MeshInstance3D", true, false):
		var wall := node as MeshInstance3D
		if wall != null:
			_boundary_walls.append(wall)

	if not _boundary_walls.is_empty():
		var source_material := _boundary_walls[0].get_active_material(0) as ShaderMaterial
		if source_material != null:
			_boundary_material = source_material.duplicate() as ShaderMaterial
			_boundary_material.resource_local_to_scene = true
			for wall in _boundary_walls:
				wall.material_override = _boundary_material
	_set_boundary_fade_alpha(1.0)

	_prepare_warm_tint()


func _prepare_warm_tint() -> void:
	_warm_tint_material = StandardMaterial3D.new()
	_warm_tint_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_warm_tint_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_warm_tint_material.albedo_color = Color(WARM_TINT.r, WARM_TINT.g, WARM_TINT.b, 0.0)
	_warm_tint_material.emission_enabled = true
	_warm_tint_material.emission = Color(WARM_TINT.r, WARM_TINT.g, WARM_TINT.b, 1.0)
	_warm_tint_material.emission_energy_multiplier = 0.15
	_warm_tint.material_override = _warm_tint_material
	_warm_tint.visible = false


func _unique_shader_material(mesh: MeshInstance3D) -> ShaderMaterial:
	var material := mesh.get_active_material(0) as ShaderMaterial
	if material == null:
		return null

	var duplicate := material.duplicate() as ShaderMaterial
	duplicate.resource_local_to_scene = true
	mesh.material_override = duplicate
	return duplicate


func _collect_pylons() -> void:
	_health_to_pylon.clear()
	_dead_health.clear()
	_pylon_health.clear()
	_pylons.clear()

	for node in find_children("Health", "Health", true, false):
		var health := node as Health
		var pylon := health.get_parent() as Node3D
		if health == null or pylon == null:
			continue

		_health_to_pylon[health] = pylon
		_pylon_health.append(health)
		_pylons.append(pylon)

		var died_callable := Callable(self, "_on_pylon_died").bind(health)
		if not health.is_connected(&"died", died_callable):
			health.connect(&"died", died_callable)

	_total_pylons = _pylon_health.size()


func _refresh_control() -> void:
	_alive_pylons = 0
	for health in _pylon_health:
		if is_instance_valid(health) and not health.is_dead:
			_alive_pylons += 1

	if _total_pylons <= 0:
		_control = -1.0
	else:
		var alive_ratio := float(_alive_pylons) / float(_total_pylons)
		_control = alive_ratio * 2.0 - 1.0


func _apply_control_visuals() -> void:
	if _grid_material == null:
		return

	_grid_material.set_shader_parameter("distress", get_distress())


func _on_pylon_died(source: Node, health: Health) -> void:
	if _dead_health.has(health):
		return

	_dead_health[health] = true
	var pylon := _health_to_pylon.get(health) as Node3D
	if pylon != null:
		_disable_pylon_collision(pylon)
		_play_pylon_collapse(pylon)

	_refresh_control()
	_apply_control_visuals()
	_emit_control_changed()

	if _alive_pylons <= 0:
		_emit_bark(&"district_liberated")
		_start_liberation_visuals()
	else:
		_emit_bark(&"district_converting")


func _disable_pylon_collision(pylon: Node3D) -> void:
	var collision_object := pylon as CollisionObject3D
	if collision_object != null:
		collision_object.collision_layer = 0
		collision_object.collision_mask = 0

	for node in pylon.find_children("*", "CollisionShape3D", true, false):
		var shape := node as CollisionShape3D
		if shape != null:
			shape.disabled = true


func _play_pylon_collapse(pylon: Node3D) -> void:
	if not is_instance_valid(pylon):
		return

	for node in pylon.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh != null:
			mesh.material_override = _make_pylon_flash_material()

	var flash := OmniLight3D.new()
	flash.name = "CollapseFlash"
	flash.light_color = CYAN
	flash.light_energy = 3.4
	flash.omni_range = 5.0
	pylon.add_child(flash)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(pylon, "scale", Vector3(1.22, 0.04, 1.22), pylon_collapse_seconds).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(pylon, "position:y", pylon.position.y - 2.25, pylon_collapse_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(flash, "light_energy", 0.0, pylon_collapse_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.finished.connect(func() -> void:
		if is_instance_valid(pylon):
			pylon.visible = false
		if is_instance_valid(flash):
			flash.queue_free()
	)


func _make_pylon_flash_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(CYAN.r, CYAN.g, CYAN.b, 0.92)
	material.emission_enabled = true
	material.emission = CYAN
	material.emission_energy_multiplier = 5.0
	material.roughness = 0.18
	return material


func _emit_control_changed() -> void:
	var events := _events()
	if events != null:
		events.emit_signal(&"district_control_changed", district_name, _control)


func _emit_bark(category: StringName) -> void:
	var line := _barks.get_bark(String(category))
	if line.is_empty():
		if category == &"district_liberated":
			line = "Liberation logged. We'll be back with an even better offer."
		else:
			line = "Conversion in progress. Please enjoy the soothing cyan."

	var events := _events()
	if events != null:
		events.emit_signal(&"bark_emitted", self, category, line)


func _start_liberation_visuals() -> void:
	if _liberated:
		return

	_liberated = true
	_warm_tint.visible = true
	_spawn_liberation_sparks()

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_method(_set_grid_fade_alpha, _grid_fade_alpha, 0.0, liberation_fade_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_method(_set_boundary_fade_alpha, _boundary_fade_alpha, 0.0, liberation_fade_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_method(_set_warm_tint_alpha, _warm_tint_alpha, WARM_TINT.a, liberation_fade_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	for wall in _boundary_walls:
		if is_instance_valid(wall):
			tween.tween_property(wall, "position:y", wall.position.y - wall_sink_depth, liberation_fade_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	tween.finished.connect(_finish_liberation_visuals)


func _set_grid_fade_alpha(value: float) -> void:
	_grid_fade_alpha = clampf(value, 0.0, 1.0)
	if _grid_material != null:
		_grid_material.set_shader_parameter("fade_alpha", _grid_fade_alpha)
	if _grid_fade_alpha <= 0.01 and is_instance_valid(_ground_overlay):
		_ground_overlay.visible = false


func _set_boundary_fade_alpha(value: float) -> void:
	_boundary_fade_alpha = clampf(value, 0.0, 1.0)
	if _boundary_material != null:
		_boundary_material.set_shader_parameter("fade_alpha", _boundary_fade_alpha)


func _set_warm_tint_alpha(value: float) -> void:
	_warm_tint_alpha = clampf(value, 0.0, WARM_TINT.a)
	if _warm_tint_material == null:
		return
	var color := _warm_tint_material.albedo_color
	color.a = _warm_tint_alpha
	_warm_tint_material.albedo_color = color


func _finish_liberation_visuals() -> void:
	if is_instance_valid(_ground_overlay):
		_ground_overlay.visible = false

	for wall in _boundary_walls:
		if is_instance_valid(wall):
			wall.visible = false

	if is_instance_valid(_boundaries):
		_boundaries.visible = false

	_boundaries_gone = true


func _spawn_liberation_sparks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(district_name)) + 101

	for index in range(14):
		var spark := MeshInstance3D.new()
		spark.name = "LiberationSpark"
		var mesh := SphereMesh.new()
		mesh.radius = rng.randf_range(0.08, 0.15)
		mesh.height = mesh.radius * 2.0
		spark.mesh = mesh
		spark.material_override = _make_spark_material(CREAM if index % 2 == 0 else PINK)
		spark.position = Vector3(
			rng.randf_range(-10.5, 10.5),
			rng.randf_range(0.18, 0.75),
			rng.randf_range(-10.5, 10.5)
		)
		add_child(spark)

		var target_position := spark.position + Vector3(
			rng.randf_range(-0.55, 0.55),
			rng.randf_range(1.35, 2.45),
			rng.randf_range(-0.55, 0.55)
		)
		var duration := rng.randf_range(0.9, 1.35)
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(spark, "position", target_position, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_property(spark, "scale", Vector3.ZERO, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tween.finished.connect(func() -> void:
			if is_instance_valid(spark):
				spark.queue_free()
		)


func _make_spark_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(color.r, color.g, color.b, 0.88)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 2.3
	return material


func _events() -> Node:
	return get_node_or_null("/root/Events")
