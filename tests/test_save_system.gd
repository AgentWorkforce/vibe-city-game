extends RefCounted

const SaveSnapshot = preload("res://scripts/core/save_snapshot.gd")

var failures: Array = []


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func test_dictionary_restore_normalizes_saved_state() -> void:
	var saved := SaveSnapshot.create(
		{
			"global_position": Vector3(12.5, 3.0, -8.25),
			"velocity": Vector3(1.0, -2.0, 3.5),
			"rotation": Vector3(0.0, 1.25, 0.0),
		},
		{
			"heat": 135.0,
			"level": 3,
		},
		[
			{"district_name": "playground_nw", "control": -1.0},
			{"district_name": "beachfront", "control": 0.5},
		],
		{
			"mission_id": "liberate_nw",
			"scene_path": "res://scenes/missions/liberate_nw.tscn",
			"current_objective_index": 1,
			"objectives": [
				{"id": "visit_converted_zone", "text": "Visit the converted zone", "done": true},
				{"id": "disconnect_pylons", "text": "Disconnect all conversion pylons", "done": false},
			],
			}
		)

	var restored := SaveSnapshot.restore(saved)
	var player: Dictionary = restored["player"]
	var wanted: Dictionary = restored["wanted"]
	var districts: Array = restored["districts"]
	var mission: Dictionary = restored["mission"]
	var objectives: Array = mission["objectives"]

	check(_vector_close(player["global_position"], Vector3(12.5, 3.0, -8.25)), "player position did not round-trip")
	check(_vector_close(player["velocity"], Vector3(1.0, -2.0, 3.5)), "player velocity did not round-trip")
	check(_vector_close(player["rotation"], Vector3(0.0, 1.25, 0.0)), "player rotation did not round-trip")
	check(absf(float(wanted["heat"]) - 135.0) < 0.001, "wanted heat did not round-trip")
	check(int(wanted["level"]) == 3, "wanted level did not round-trip")
	check(districts.size() == 2, "district count changed during round-trip")
	check(_district_control(districts, "playground_nw") == -1.0, "liberated district control did not round-trip")
	check(_district_control(districts, "beachfront") == 0.5, "partial district control did not round-trip")
	check(str(mission["mission_id"]) == "liberate_nw", "mission id did not round-trip")
	check(int(mission["current_objective_index"]) == 1, "mission objective index did not round-trip")
	check(objectives.size() == 2 and bool(objectives[0]["done"]) and not bool(objectives[1]["done"]), "mission objective states did not round-trip")


func test_json_snapshot_normalizes_arrays_and_guards_corruption() -> void:
	var saved := SaveSnapshot.create(
		{
			"global_position": Vector3(1.0, 2.0, 3.0),
			"velocity": Vector3(4.0, 5.0, 6.0),
			"rotation": Vector3(0.0, 0.25, 0.0),
		},
		{"heat": 45.0, "level": 1},
		[{"district_name": "playground_nw", "control": -2.0}],
		{"mission_id": "liberate_nw", "current_objective_index": 4}
	)
	var parsed: Variant = JSON.parse_string(JSON.stringify(saved))
	var normalized := SaveSnapshot.normalize(parsed)
	var districts: Array = normalized["districts"]

	check(SaveSnapshot.is_valid_snapshot(parsed), "serialized snapshot should be valid")
	check(not SaveSnapshot.is_valid_snapshot({}), "empty dictionary should be treated as corrupt")
	check(not SaveSnapshot.is_valid_snapshot({"version": 999}), "unsupported version should be treated as corrupt")
	check(_vector_close(normalized["player"]["global_position"], Vector3(1.0, 2.0, 3.0)), "JSON vector array did not normalize")
	check(float(districts[0]["control"]) == -1.0, "district control was not clamped during normalization")
	check(int(normalized["mission"]["current_objective_index"]) == 0, "empty mission objective index should clamp to zero")


func _vector_close(data: Variant, expected: Vector3) -> bool:
	var vector := SaveSnapshot.vector3_from_data(data)
	return vector.distance_to(expected) < 0.001


func _district_control(districts: Array, district_name: String) -> float:
	for district in districts:
		if typeof(district) != TYPE_DICTIONARY:
			continue
		if str(district.get("district_name", "")) == district_name:
			return float(district.get("control", 0.0))
	return INF
