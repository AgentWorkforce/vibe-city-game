extends RefCounted

const WantedLogic = preload("res://scripts/systems/wanted_logic.gd")

var failures: Array = []


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func test_heat_thresholds_map_to_levels() -> void:
	var thresholds := PackedFloat32Array([0.0, 10.0, 25.0, 50.0, 90.0, 140.0])
	check(WantedLogic.calculate_level(0.0, thresholds) == 0, "zero heat should be clear")
	check(WantedLogic.calculate_level(9.9, thresholds) == 0, "heat below level 1 threshold escalated")
	check(WantedLogic.calculate_level(10.0, thresholds) == 1, "level 1 threshold not reached")
	check(WantedLogic.calculate_level(74.0, thresholds) == 3, "level 3 threshold mapping wrong")
	check(WantedLogic.calculate_level(200.0, thresholds) == 5, "max threshold should clamp to level 5")


func test_severity_values_add_expected_heat() -> void:
	var heat_values := PackedFloat32Array([0.0, 12.0, 24.0, 48.0])
	check(WantedLogic.heat_for_severity(0, heat_values) == 0.0, "severity 0 should add no heat")
	check(WantedLogic.heat_for_severity(2, heat_values) == 24.0, "severity 2 heat wrong")
	check(WantedLogic.heat_for_severity(9, heat_values) == 48.0, "severity should clamp high")


func test_add_heat_transitions_levels() -> void:
	var logic := WantedLogic.new()
	logic.configure(
		PackedFloat32Array([0.0, 12.0, 25.0]),
		PackedFloat32Array([0.0, 10.0, 30.0, 60.0, 100.0, 150.0]),
		5.0,
		2.0,
		0.0
	)

	var result := logic.add_heat(9.0)
	check(result["previous_level"] == 0 and result["level"] == 0, "heat below threshold changed level")
	result = logic.add_heat(1.0)
	check(result["previous_level"] == 0 and result["level"] == 1, "crossing threshold did not enter level 1")
	result = logic.add_crime(2)
	check(result["previous_level"] == 1 and result["level"] == 2, "crime severity did not transition to level 2")


func test_decay_waits_for_grace_window() -> void:
	var logic := WantedLogic.new()
	logic.configure(
		PackedFloat32Array(WantedLogic.DEFAULT_SEVERITY_HEAT),
		PackedFloat32Array([0.0, 10.0, 30.0, 60.0, 100.0, 150.0]),
		10.0,
		3.0,
		2.0
	)
	logic.add_heat(40.0)

	logic.decay(1.0, false)
	check(absf(logic.heat - 40.0) < 0.001, "heat decayed before grace window elapsed")
	logic.decay(1.1, false)
	check(logic.heat < 40.0, "heat did not decay after grace window")


func test_unseen_decay_is_faster() -> void:
	var seen := WantedLogic.new()
	var unseen := WantedLogic.new()
	for logic in [seen, unseen]:
		logic.configure(
			PackedFloat32Array(WantedLogic.DEFAULT_SEVERITY_HEAT),
			PackedFloat32Array(WantedLogic.DEFAULT_LEVEL_THRESHOLDS),
			5.0,
			4.0,
			0.0
		)
		logic.add_heat(100.0)

	seen.decay(2.0, false)
	unseen.decay(2.0, true)
	check(unseen.heat < seen.heat, "far-from-agent decay was not faster")


func test_decay_reports_level_drop() -> void:
	var logic := WantedLogic.new()
	logic.configure(
		PackedFloat32Array(WantedLogic.DEFAULT_SEVERITY_HEAT),
		PackedFloat32Array([0.0, 10.0, 30.0, 60.0, 100.0, 150.0]),
		15.0,
		1.0,
		0.0
	)
	logic.add_heat(35.0)

	var result := logic.decay(1.0, false)
	check(result["previous_level"] == 2 and result["level"] == 1, "decay did not report level drop")


func test_clear_resets_heat_and_level() -> void:
	var logic := WantedLogic.new()
	logic.add_heat(200.0)
	var result := logic.clear()
	check(result["previous_level"] == 4 and result["level"] == 0, "clear did not report level reset")
	check(logic.heat == 0.0 and logic.get_level() == 0, "clear did not reset logic")
