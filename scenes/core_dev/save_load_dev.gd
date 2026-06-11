extends Node3D

const SaveSystemScript = preload("res://scripts/core/save_system.gd")
const MISSION_SCENE := "res://scenes/missions/liberate_nw.tscn"
const DEV_SAVE_PATH := "user://vibe_city_save_dev.json"

@export var quit_when_complete := true

var _failures: Array[String] = []

@onready var _player_body: CharacterBody3D = $Player/Body
@onready var _zone: Node = $ConversionZone


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame
	_player_body.set_physics_process(false)
	var saves := _ensure_saves()
	saves.save_path = DEV_SAVE_PATH

	var missions := get_node_or_null("/root/Missions")
	if missions != null:
		missions.initial_mission_scene = ""
		if missions.has_method("restore_save_snapshot"):
			missions.call("restore_save_snapshot", {})

	_set_saved_state()
	if not saves.save():
		_fail("save() returned false")
		return

	_mutate_state()
	if not saves.load_save():
		_fail("load_save() returned false")
		return

	_assert_restored_state()


func _ensure_saves() -> Node:
	var saves := get_node_or_null("/root/Saves")
	if saves != null:
		return saves

	saves = SaveSystemScript.new()
	saves.name = "Saves"
	get_tree().root.add_child(saves)
	return saves


func _set_saved_state() -> void:
	_player_body.global_position = Vector3(6.0, 1.25, -4.0)
	_player_body.velocity = Vector3(1.5, -0.5, 3.25)
	_player_body.global_rotation = Vector3(0.0, 1.1, 0.0)

	var wanted := get_node_or_null("/root/Wanted")
	if wanted != null and wanted.has_method("restore_state"):
		wanted.call("restore_state", 145.0)

	var mission := _start_mission()
	if mission != null:
		mission.call("complete_objective", &"visit_converted_zone")

	_zone.call("restore_control", -1.0)


func _mutate_state() -> void:
	_player_body.global_position = Vector3(-20.0, 8.0, 9.0)
	_player_body.velocity = Vector3.ZERO
	_player_body.global_rotation = Vector3.ZERO

	var wanted := get_node_or_null("/root/Wanted")
	if wanted != null and wanted.has_method("clear"):
		wanted.call("clear")

	_zone.call("restore_control", 1.0)

	var missions := get_node_or_null("/root/Missions")
	if missions != null and missions.has_method("restore_save_snapshot"):
		missions.call("restore_save_snapshot", {})


func _start_mission() -> Node:
	var missions := get_node_or_null("/root/Missions")
	if missions == null or not missions.has_method("start_mission"):
		return null
	return missions.call("start_mission", MISSION_SCENE)


func _assert_restored_state() -> void:
	_expect(_player_body.global_position.distance_to(Vector3(6.0, 1.25, -4.0)) < 0.001, "player position not restored")
	_expect(_player_body.velocity.distance_to(Vector3(1.5, -0.5, 3.25)) < 0.001, "player velocity not restored")
	_expect(absf(_player_body.global_rotation.y - 1.1) < 0.001, "player rotation not restored")

	var wanted := get_node_or_null("/root/Wanted")
	_expect(wanted != null and absf(float(wanted.call("get_heat")) - 145.0) < 0.001, "wanted heat not restored")
	_expect(wanted != null and int(wanted.call("get_level")) > 0, "wanted level not restored")

	_expect(absf(float(_zone.call("get_control")) - -1.0) < 0.001, "district control not restored")
	_expect(bool(_zone.call("is_liberated")), "district liberation state not restored")
	_expect(bool(_zone.call("is_grid_faded")), "district grid fade not restored")
	_expect(bool(_zone.call("are_boundary_walls_gone")), "district boundary state not restored")

	var missions := get_node_or_null("/root/Missions")
	var snapshot: Dictionary = missions.call("get_save_snapshot") if missions != null else {}
	var objectives: Array = snapshot.get("objectives", [])
	_expect(str(snapshot.get("mission_id", "")) == "liberate_nw", "mission id not restored")
	_expect(int(snapshot.get("current_objective_index", -1)) == 2, "mission objective index not restored")
	_expect(objectives.size() == 2 and bool(objectives[0].get("done", false)) and bool(objectives[1].get("done", false)), "mission objectives not restored")

	if _failures.is_empty():
		print("SAVE LOAD DEV PASS: player, wanted, district, and mission restored")
		if quit_when_complete:
			get_tree().quit(0)
	else:
		for failure in _failures:
			print("SAVE LOAD DEV FAIL: %s" % failure)
		if quit_when_complete:
			get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition and not _failures.has(message):
		_failures.append(message)


func _fail(message: String) -> void:
	push_error("SAVE LOAD DEV FAIL: %s" % message)
	print("SAVE LOAD DEV FAIL: %s" % message)
	if quit_when_complete:
		get_tree().quit(1)
