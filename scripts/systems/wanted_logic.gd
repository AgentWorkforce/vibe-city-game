extends RefCounted

const DEFAULT_SEVERITY_HEAT := [0.0, 35.0, 55.0, 85.0, 125.0, 180.0]
const DEFAULT_LEVEL_THRESHOLDS := [0.0, 30.0, 75.0, 130.0, 200.0, 290.0]

var heat: float = 0.0
var time_since_crime: float = INF
var severity_heat := PackedFloat32Array(DEFAULT_SEVERITY_HEAT)
var level_thresholds := PackedFloat32Array(DEFAULT_LEVEL_THRESHOLDS)
var decay_rate: float = 5.0
var unseen_decay_multiplier: float = 2.5
var decay_grace_seconds: float = 3.0


static func calculate_level(value: float, thresholds: PackedFloat32Array) -> int:
	var level := 0
	for i in thresholds.size():
		if value >= thresholds[i]:
			level = i
	return clampi(level, 0, 5)


static func heat_for_severity(severity: int, heat_values: PackedFloat32Array) -> float:
	if heat_values.is_empty():
		return 0.0

	var index := clampi(severity, 0, heat_values.size() - 1)
	return maxf(0.0, heat_values[index])


static func calculate_decay(
		current_heat: float,
		delta: float,
		base_rate: float,
		multiplier: float,
		time_without_crime: float,
		grace_seconds: float) -> float:
	var clamped_heat := maxf(current_heat, 0.0)
	if clamped_heat <= 0.0 or delta <= 0.0:
		return clamped_heat
	if time_without_crime < maxf(grace_seconds, 0.0):
		return clamped_heat

	var effective_rate := maxf(base_rate, 0.0) * maxf(multiplier, 0.0)
	return maxf(0.0, clamped_heat - effective_rate * delta)


func configure(
		new_severity_heat: PackedFloat32Array,
		new_level_thresholds: PackedFloat32Array,
		new_decay_rate: float,
		new_unseen_decay_multiplier: float,
		new_decay_grace_seconds: float) -> void:
	if not new_severity_heat.is_empty():
		severity_heat = new_severity_heat
	if not new_level_thresholds.is_empty():
		level_thresholds = new_level_thresholds
	decay_rate = new_decay_rate
	unseen_decay_multiplier = new_unseen_decay_multiplier
	decay_grace_seconds = new_decay_grace_seconds


func get_level() -> int:
	return calculate_level(heat, level_thresholds)


func add_heat(amount: float) -> Dictionary:
	var previous_level := get_level()
	heat = maxf(0.0, heat + maxf(amount, 0.0))
	if amount > 0.0:
		time_since_crime = 0.0

	return {
		"previous_level": previous_level,
		"level": get_level(),
		"heat": heat,
	}


func add_crime(severity: int) -> Dictionary:
	return add_heat(heat_for_severity(severity, severity_heat))


func decay(delta: float, far_from_agents: bool) -> Dictionary:
	var previous_level := get_level()
	var safe_delta := maxf(delta, 0.0)
	time_since_crime += safe_delta

	var multiplier := unseen_decay_multiplier if far_from_agents else 1.0
	heat = calculate_decay(
		heat,
		safe_delta,
		decay_rate,
		multiplier,
		time_since_crime,
		decay_grace_seconds
	)

	return {
		"previous_level": previous_level,
		"level": get_level(),
		"heat": heat,
	}


func clear() -> Dictionary:
	var previous_level := get_level()
	heat = 0.0
	time_since_crime = INF
	return {
		"previous_level": previous_level,
		"level": 0,
		"heat": heat,
	}
