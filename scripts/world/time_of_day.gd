class_name TimeOfDay
extends Node
## Drives the shared sun, sky, fog, glow, and lightweight streetlights from an
## in-game 24-hour clock.
##
## The sun DirectionalLight3D stays on the sun arc and turns off below the
## horizon. A runtime child DirectionalLight3D provides the low-energy cyan moon
## pass at night so the sun math remains physically readable and testable.
## Streetlights are runtime OmniLight3D nodes capped by max_streetlights; this
## keeps the first district comfortably inside the M4 traffic/crowd/render budget.

signal hour_changed(hour: int)

const SUNRISE_HOUR := 6.0
const SUNSET_HOUR := 18.0
const NOON_HOUR := 12.0
const MAX_SUN_ENERGY := 2.6
const MAX_MOON_ENERGY := 0.18
const MOON_COLOR := Color(0.62, 0.82, 1.0, 1.0)
const STREETLIGHT_COLOR := Color(1.0, 0.76, 0.42, 1.0)
const NIGHT_GLOW_INTENSITY := 1.05

@export_range(0.1, 120.0, 0.1) var day_length_minutes := 10.0
@export_range(0.0, 24.0, 0.01) var start_hour := 10.0
@export_node_path("DirectionalLight3D") var sun_path: NodePath
@export_node_path("WorldEnvironment") var world_environment_path: NodePath

## Optional exact world positions for streetlights.
@export var streetlight_positions := PackedVector3Array()
## Optional paired world-space segment endpoints. Each pair is sampled into
## streetlights at streetlight_spacing_meters, then capped by max_streetlights.
@export var streetlight_segment_points := PackedVector3Array()
@export_range(8.0, 80.0, 1.0) var streetlight_spacing_meters := 28.0
@export_range(0, 24, 1) var max_streetlights := 24
@export_range(0.0, 8.0, 0.1) var streetlight_energy := 1.25
@export_range(2.0, 20.0, 0.5) var streetlight_range := 10.0

var _hour := 10.0
var _last_whole_hour := -1
var _last_minute_of_day := -1
var _sun: DirectionalLight3D
var _moon: DirectionalLight3D
var _world_environment: WorldEnvironment
var _environment: Environment
var _base_ambient_energy := 0.85
var _base_glow_intensity := 0.6
var _base_fog_density := 0.0005
var _base_sky_energy := 1.0
var _base_ground_energy := 1.0
var _streetlight_root: Node3D
var _streetlights: Array[OmniLight3D] = []


func _ready() -> void:
	_hour = wrap_hour(start_hour)
	_last_whole_hour = int(floor(_hour))
	_sun = get_node_or_null(sun_path) as DirectionalLight3D
	_world_environment = get_node_or_null(world_environment_path) as WorldEnvironment
	if _world_environment != null:
		_environment = _world_environment.environment
		_cache_environment_defaults()
	_ensure_moon_light()
	_ensure_streetlights()
	_apply_time(true)


func _process(delta: float) -> void:
	if day_length_minutes <= 0.0:
		return
	set_hour(_hour + (delta / (day_length_minutes * 60.0)) * 24.0)


func get_hour() -> float:
	return _hour


func set_hour(hour: float) -> void:
	_hour = wrap_hour(hour)
	_apply_time(false)


func is_night() -> bool:
	return is_night_hour(_hour)


static func wrap_hour(hour: float) -> float:
	return fposmod(hour, 24.0)


static func minute_of_day(hour: float) -> int:
	return int(floor(wrap_hour(hour) * 60.0)) % 1440


static func is_night_hour(hour: float) -> bool:
	return daylight_factor(hour) <= 0.001


static func daylight_factor(hour: float) -> float:
	var wrapped := wrap_hour(hour)
	if wrapped < SUNRISE_HOUR or wrapped > SUNSET_HOUR:
		return 0.0
	var day_progress := (wrapped - SUNRISE_HOUR) / (SUNSET_HOUR - SUNRISE_HOUR)
	return clampf(sin(day_progress * PI), 0.0, 1.0)


static func night_factor(hour: float) -> float:
	if not is_night_hour(hour):
		return 0.0
	var wrapped := wrap_hour(hour)
	var night_progress := 0.0
	if wrapped >= SUNSET_HOUR:
		night_progress = (wrapped - SUNSET_HOUR) / (24.0 - SUNSET_HOUR + SUNRISE_HOUR)
	else:
		night_progress = (wrapped + (24.0 - SUNSET_HOUR)) / (24.0 - SUNSET_HOUR + SUNRISE_HOUR)
	return clampf(sin(night_progress * PI), 0.0, 1.0)


static func sun_elevation_degrees(hour: float) -> float:
	var wrapped := wrap_hour(hour)
	if is_night_hour(wrapped):
		var night_dip := night_factor(wrapped)
		return -8.0 - (38.0 * night_dip)
	return 4.0 + (68.0 * daylight_factor(wrapped))


static func sun_azimuth_degrees(hour: float) -> float:
	var wrapped := wrap_hour(hour)
	return lerpf(120.0, -120.0, wrapped / 24.0)


static func sun_angles(hour: float) -> Vector2:
	return Vector2(sun_azimuth_degrees(hour), sun_elevation_degrees(hour))


static func sun_energy(hour: float) -> float:
	var light := daylight_factor(hour)
	if light <= 0.001:
		return 0.0
	return MAX_SUN_ENERGY * _smoothstep(0.05, 0.72, light)


static func moon_energy(hour: float) -> float:
	return MAX_MOON_ENERGY * night_factor(hour)


static func sun_color(hour: float) -> Color:
	var day := daylight_factor(hour)
	var edge_warmth := 1.0 - _smoothstep(0.18, 0.82, day)
	var kelvin := lerpf(6500.0, 2500.0, edge_warmth)
	return color_temperature(kelvin)


static func color_temperature(kelvin: float) -> Color:
	var temperature := clampf(kelvin, 1000.0, 40000.0) / 100.0
	var red := 255.0
	var green := 255.0
	var blue := 255.0

	if temperature > 66.0:
		red = 329.698727446 * pow(temperature - 60.0, -0.1332047592)

	if temperature <= 66.0:
		green = 99.4708025861 * log(temperature) - 161.1195681661
	else:
		green = 288.1221695283 * pow(temperature - 60.0, -0.0755148492)

	if temperature >= 66.0:
		blue = 255.0
	elif temperature <= 19.0:
		blue = 0.0
	else:
		blue = 138.5177312231 * log(temperature - 10.0) - 305.0447927307

	return Color(
		clampf(red / 255.0, 0.0, 1.0),
		clampf(green / 255.0, 0.0, 1.0),
		clampf(blue / 255.0, 0.0, 1.0),
		1.0
	)


static func ambient_energy(hour: float) -> float:
	var day := daylight_factor(hour)
	var night := night_factor(hour)
	return 0.18 + (0.72 * _smoothstep(0.0, 1.0, day)) + (0.08 * night)


static func sky_energy_multiplier(hour: float) -> float:
	var day := daylight_factor(hour)
	var night := night_factor(hour)
	return 0.14 + (0.94 * day) + (0.05 * night)


static func glow_intensity(hour: float) -> float:
	var night := night_factor(hour)
	return lerpf(0.45, NIGHT_GLOW_INTENSITY, night)


static func fog_density_multiplier(hour: float) -> float:
	var wrapped := wrap_hour(hour)
	var dawn_bump := 1.0 - clampf(absf(wrapped - SUNRISE_HOUR) / 2.0, 0.0, 1.0)
	var dusk_bump := 1.0 - clampf(absf(wrapped - SUNSET_HOUR) / 2.5, 0.0, 1.0)
	return 1.0 + (0.9 * dawn_bump) + (0.35 * dusk_bump)


static func moon_elevation_degrees(hour: float) -> float:
	return 18.0 + (28.0 * night_factor(hour))


static func moon_azimuth_degrees(hour: float) -> float:
	return sun_azimuth_degrees(hour) + 180.0


static func _smoothstep(edge0: float, edge1: float, value: float) -> float:
	if is_equal_approx(edge0, edge1):
		return 0.0
	var x := clampf((value - edge0) / (edge1 - edge0), 0.0, 1.0)
	return x * x * (3.0 - (2.0 * x))


func _apply_time(force_hour_signal: bool) -> void:
	_apply_sun()
	_apply_moon()
	_apply_environment()
	_apply_streetlights()
	_emit_time_signals(force_hour_signal)


func _apply_sun() -> void:
	if _sun == null:
		return
	var elevation := sun_elevation_degrees(_hour)
	_sun.rotation_degrees = Vector3(-elevation, sun_azimuth_degrees(_hour), 0.0)
	_sun.light_energy = sun_energy(_hour)
	_sun.light_color = sun_color(_hour)
	_sun.visible = _sun.light_energy > 0.001


func _apply_moon() -> void:
	if _moon == null:
		return
	var energy := moon_energy(_hour)
	_moon.rotation_degrees = Vector3(-moon_elevation_degrees(_hour), moon_azimuth_degrees(_hour), 0.0)
	_moon.light_color = MOON_COLOR
	_moon.light_energy = energy
	_moon.visible = energy > 0.001


func _apply_environment() -> void:
	if _environment == null:
		return

	_environment.ambient_light_energy = _base_ambient_energy * ambient_energy(_hour)
	_environment.glow_enabled = true
	_environment.glow_intensity = maxf(_base_glow_intensity, glow_intensity(_hour))
	_environment.fog_enabled = true
	_environment.fog_density = _base_fog_density * fog_density_multiplier(_hour)
	_environment.fog_light_color = sun_color(_hour).lerp(MOON_COLOR, night_factor(_hour) * 0.8)

	var sky := _environment.sky
	if sky == null or sky.sky_material == null:
		return
	var sky_material := sky.sky_material as ProceduralSkyMaterial
	if sky_material == null:
		return
	var sky_energy := sky_energy_multiplier(_hour)
	sky_material.sky_energy_multiplier = _base_sky_energy * sky_energy
	sky_material.ground_energy_multiplier = _base_ground_energy * maxf(0.12, sky_energy * 0.8)


func _apply_streetlights() -> void:
	var night := is_night()
	for light in _streetlights:
		light.visible = night
		light.light_energy = streetlight_energy if night else 0.0


func _emit_time_signals(force_hour_signal: bool) -> void:
	var whole_hour := int(floor(_hour))
	if force_hour_signal or whole_hour != _last_whole_hour:
		_last_whole_hour = whole_hour
		hour_changed.emit(whole_hour)

	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null or tree.root == null:
		return
	var events := tree.root.get_node_or_null("Events")
	var minute := minute_of_day(_hour)
	if minute != _last_minute_of_day and events != null and events.has_signal("time_tick"):
		_last_minute_of_day = minute
		events.emit_signal("time_tick", _hour)


func _cache_environment_defaults() -> void:
	if _environment == null:
		return
	_base_ambient_energy = maxf(0.001, _environment.ambient_light_energy)
	_base_glow_intensity = maxf(0.001, _environment.glow_intensity)
	_base_fog_density = maxf(0.000001, _environment.fog_density)
	var sky := _environment.sky
	if sky == null or sky.sky_material == null:
		return
	var sky_material := sky.sky_material as ProceduralSkyMaterial
	if sky_material == null:
		return
	_base_sky_energy = maxf(0.001, sky_material.sky_energy_multiplier)
	_base_ground_energy = maxf(0.001, sky_material.ground_energy_multiplier)


func _ensure_moon_light() -> void:
	if _moon != null:
		return
	_moon = DirectionalLight3D.new()
	_moon.name = "Moon"
	_moon.light_color = MOON_COLOR
	_moon.light_energy = 0.0
	_moon.shadow_enabled = true
	_moon.visible = false
	add_child(_moon)


func _ensure_streetlights() -> void:
	if _streetlight_root != null:
		return
	_streetlight_root = Node3D.new()
	_streetlight_root.name = "RuntimeStreetlights"
	add_child(_streetlight_root)

	var positions := _build_streetlight_positions()
	var count = mini(positions.size(), max_streetlights)
	for i in count:
		_spawn_streetlight(positions[i])


func _build_streetlight_positions() -> Array[Vector3]:
	var positions: Array[Vector3] = []
	for position in streetlight_positions:
		positions.append(position)
		if positions.size() >= max_streetlights:
			return positions

	var pair_count := int(floor(streetlight_segment_points.size() / 2.0))
	for pair_index in pair_count:
		var start := streetlight_segment_points[pair_index * 2]
		var end := streetlight_segment_points[(pair_index * 2) + 1]
		var segment_length := start.distance_to(end)
		var samples = maxi(2, int(floor(segment_length / streetlight_spacing_meters)) + 1)
		for sample_index in samples:
			var t := 0.0 if samples <= 1 else float(sample_index) / float(samples - 1)
			positions.append(start.lerp(end, t))
			if positions.size() >= max_streetlights:
				return positions
	return positions


func _spawn_streetlight(base_position: Vector3) -> void:
	var pole_height := 4.4
	var pole := MeshInstance3D.new()
	pole.name = "StreetlightPole"
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.08
	pole_mesh.bottom_radius = 0.1
	pole_mesh.height = pole_height
	pole.mesh = pole_mesh
	pole.position = base_position + Vector3(0.0, pole_height * 0.5, 0.0)
	_streetlight_root.add_child(pole)

	var head := MeshInstance3D.new()
	head.name = "StreetlightHead"
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.7, 0.16, 0.28)
	head.mesh = head_mesh
	head.position = base_position + Vector3(0.0, pole_height + 0.1, 0.0)
	_streetlight_root.add_child(head)

	var light := OmniLight3D.new()
	light.name = "Streetlight"
	light.position = base_position + Vector3(0.0, pole_height, 0.0)
	light.light_color = STREETLIGHT_COLOR
	light.light_energy = 0.0
	light.omni_range = streetlight_range
	light.omni_attenuation = 1.6
	light.shadow_enabled = false
	light.visible = false
	_streetlight_root.add_child(light)
	_streetlights.append(light)
