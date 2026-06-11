extends RefCounted

const TimeOfDay = preload("res://scripts/world/time_of_day.gd")

var failures: Array = []


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func test_hour_wrapping() -> void:
	check(absf(TimeOfDay.wrap_hour(25.5) - 1.5) < 0.001, "25.5 should wrap to 1.5")
	check(absf(TimeOfDay.wrap_hour(-1.0) - 23.0) < 0.001, "-1 should wrap to 23")
	check(absf(TimeOfDay.wrap_hour(48.0)) < 0.001, "48 should wrap to 0")


func test_minute_of_day_wraps() -> void:
	check(TimeOfDay.minute_of_day(1.5) == 90, "1.5h should be minute 90")
	check(TimeOfDay.minute_of_day(23.999) == 1439, "23.999h should be final day minute")
	check(TimeOfDay.minute_of_day(-0.001) == 1439, "-0.001h should wrap to final day minute")


func test_noon_elevation_is_higher_than_sunrise() -> void:
	var sunrise_elevation := TimeOfDay.sun_elevation_degrees(7.0)
	var noon_elevation := TimeOfDay.sun_elevation_degrees(12.0)
	check(noon_elevation > sunrise_elevation,
		"noon elevation %f should be above sunrise %f" % [noon_elevation, sunrise_elevation])


func test_night_sun_energy_is_zero() -> void:
	check(TimeOfDay.sun_energy(22.0) == 0.0, "sun energy should be zero at 22:00")
	check(TimeOfDay.sun_elevation_degrees(22.0) < 0.0, "sun should be below horizon at 22:00")


func test_sunset_color_is_warmer_than_noon() -> void:
	var sunset := TimeOfDay.sun_color(17.0)
	var noon := TimeOfDay.sun_color(12.0)
	var sunset_warmth := sunset.r - sunset.b
	var noon_warmth := noon.r - noon.b
	check(sunset_warmth > noon_warmth,
		"sunset warmth %f should be greater than noon warmth %f" % [sunset_warmth, noon_warmth])


func test_night_detection_wraps() -> void:
	check(TimeOfDay.is_night_hour(23.5), "23:30 should be night")
	check(TimeOfDay.is_night_hour(-1.0), "-1 should wrap to 23:00 night")
	check(not TimeOfDay.is_night_hour(12.0), "noon should not be night")
