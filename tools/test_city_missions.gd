# Integration test: run the M5 city mission chain against the real city scene.
# Usage: godot --headless -s tools/test_city_missions.gd
# Poll-based: under headless -s, threaded tile loads and time-based mission
# timers are asynchronous. Autoloads are absent in -s mode, so Events and
# Missions are installed manually before the city scene is added.
extends SceneTree

const Health = preload("res://scripts/combat/health.gd")
const EventsScript = preload("res://scripts/core/events.gd")
const MissionManagerScript = preload("res://scripts/missions/mission_manager.gd")

const LIBERATE_NW_SCENE := "res://scenes/missions/liberate_nw.tscn"
const EASTWARD_SCENE := "res://scenes/missions/eastward.tscn"
const BLOCK_PARTY_SCENE := "res://scenes/missions/block_party.tscn"
const CITY_EAST_A_TILE := "res://scenes/city/tiles/tile_4_0.tscn"
const MAX_FRAMES := 4200
const TILE_SIZE := 128.0

enum Phase {
	START_LIBERATE_NW,
	COMPLETE_LIBERATE_NW_VISIT,
	COMPLETE_LIBERATE_NW_CONTROL,
	WAIT_EASTWARD,
	WAIT_CITY_ZONE,
	COMPLETE_EASTWARD,
	WAIT_BLOCK_PARTY,
	KILL_CITY_PYLONS,
	WAIT_BLOCK_PARTY_COMPLETE,
}

var _frames := 0
var _phase := Phase.START_LIBERATE_NW
var _phase_frames := 0
var _events: Node
var _manager: MissionManager
var _city: Node3D
var _body: CharacterBody3D
var _mock_zone_area: Area3D
var _city_zone: Node3D
var _city_zone_area: Area3D
var _started_ids: Array[String] = []
var _completed_ids: Array[String] = []
var _objectives_seen: Array[String] = []
var _failures: Array[String] = []
var _cleanup_started := false
var _cleanup_frames := 0
var _cleanup_exit_code := 0


func _initialize() -> void:
	_install_events()
	_install_missions()
	_make_mock_playground_world()


func _process(_delta: float) -> bool:
	_frames += 1
	_phase_frames += 1

	if _cleanup_started:
		_cleanup_frames += 1
		if _cleanup_frames >= 20:
			quit(_cleanup_exit_code)
			return true
		return false

	match _phase:
		Phase.START_LIBERATE_NW:
			_start_liberate_nw()
		Phase.COMPLETE_LIBERATE_NW_VISIT:
			_complete_liberate_nw_visit()
		Phase.COMPLETE_LIBERATE_NW_CONTROL:
			_complete_liberate_nw_control()
		Phase.WAIT_EASTWARD:
			_wait_for_mission(&"eastward", Phase.WAIT_CITY_ZONE)
		Phase.WAIT_CITY_ZONE:
			_wait_for_city_zone()
		Phase.COMPLETE_EASTWARD:
			_complete_eastward()
		Phase.WAIT_BLOCK_PARTY:
			_wait_for_mission(&"block_party", Phase.KILL_CITY_PYLONS)
		Phase.KILL_CITY_PYLONS:
			_kill_city_pylons()
		Phase.WAIT_BLOCK_PARTY_COMPLETE:
			_wait_for_block_party_complete()

	if _frames >= MAX_FRAMES:
		_begin_cleanup(["timed out in phase %s after %d frames" % [_phase_name(_phase), MAX_FRAMES]], 1)
		return false

	return false


func _install_events() -> void:
	_events = root.get_node_or_null("Events")
	if _events == null:
		_events = EventsScript.new()
		_events.name = "Events"
		root.add_child(_events)
	_connect_once(_events, &"mission_started", Callable(self, "_on_mission_started"))
	_connect_once(_events, &"mission_objective", Callable(self, "_on_mission_objective"))
	_connect_once(_events, &"mission_completed", Callable(self, "_on_mission_completed"))


func _install_missions() -> void:
	_manager = MissionManagerScript.new()
	_manager.name = "Missions"
	_manager.initial_mission_scene = ""
	_manager.eastward_mission_scene = EASTWARD_SCENE
	_manager.block_party_mission_scene = BLOCK_PARTY_SCENE
	_manager.liberate_nw_chain_delay = 0.0
	_manager.eastward_chain_delay = 0.0
	root.add_child(_manager)


func _load_city() -> void:
	if is_instance_valid(_city):
		return

	var scene: PackedScene = load("res://scenes/city/city.tscn")
	_city = scene.instantiate() as Node3D
	var streamer := _city.get_node_or_null("WorldStreamer")
	if streamer != null:
		streamer.set("load_radius_tiles", -1)
	root.add_child(_city)
	_add_city_east_a_tile()
	current_scene = _city
	_body = _city.get_node("Player/Body") as CharacterBody3D


func _add_city_east_a_tile() -> void:
	var packed := load(CITY_EAST_A_TILE) as PackedScene
	if packed == null:
		_record_failure("could not load city_east_a tile")
		_begin_cleanup(_failures, 1)
		return

	var tile := packed.instantiate() as Node3D
	if tile == null:
		_record_failure("city_east_a tile did not instantiate as Node3D")
		_begin_cleanup(_failures, 1)
		return

	tile.name = "TestTile_4_0"
	tile.position = Vector3(TILE_SIZE * 4.0, 0.0, 0.0)
	var streamer := _city.get_node_or_null("WorldStreamer")
	if streamer != null:
		streamer.add_child(tile)
	else:
		_city.add_child(tile)


func _make_mock_playground_world() -> void:
	_city = Node3D.new()
	_city.name = "MissionChainMockWorld"
	root.add_child(_city)
	current_scene = _city

	_body = CharacterBody3D.new()
	_body.name = "Body"
	_body.add_to_group(&"player")
	_city.add_child(_body)

	var zone_root := Node3D.new()
	zone_root.name = "MockPlaygroundConversionZone"
	_city.add_child(zone_root)

	_mock_zone_area = Area3D.new()
	_mock_zone_area.name = "ZoneArea"
	_mock_zone_area.add_to_group(&"conversion_zone")
	zone_root.add_child(_mock_zone_area)


func _start_liberate_nw() -> void:
	var mission := _manager.start_mission(LIBERATE_NW_SCENE)
	if mission == null:
		_record_failure("failed to start liberate_nw")
		_begin_cleanup(_failures, 1)
		return

	_set_phase(Phase.COMPLETE_LIBERATE_NW_VISIT)


func _complete_liberate_nw_visit() -> void:
	var mission := _manager.get_active_mission()
	if mission == null or not mission.is_active() or mission.mission_id != &"liberate_nw":
		return
	if mission.get_current_objective_text() != "Visit the converted zone":
		return

	_mock_zone_area.emit_signal(&"body_entered", _body)
	_set_phase(Phase.COMPLETE_LIBERATE_NW_CONTROL)


func _complete_liberate_nw_control() -> void:
	var mission := _manager.get_active_mission()
	if mission == null or mission.get_current_objective_text() != "Disconnect all conversion pylons":
		return

	_events.emit_signal(&"district_control_changed", &"playground_nw", -1.0)
	_set_phase(Phase.WAIT_EASTWARD)


func _wait_for_mission(mission_id: StringName, next_phase: int) -> void:
	var mission := _manager.get_active_mission()
	if mission != null and mission.mission_id == mission_id and mission.is_active():
		if mission_id == &"eastward":
			_replace_mock_with_city()
		_set_phase(next_phase)
		return

	if _phase_frames > 240:
		var active_id := "<none>"
		var active_active := false
		var active_completed := false
		if mission != null:
			active_id = String(mission.mission_id)
			active_active = mission.is_active()
			active_completed = mission.is_completed()
		_record_failure("mission %s did not start from chain (active=%s active_state=%s completed_state=%s started=%s completed=%s objectives=%s)" % [
			String(mission_id),
			active_id,
			active_active,
			active_completed,
			_started_ids,
			_completed_ids,
			_objectives_seen,
		])
		_begin_cleanup(_failures, 1)


func _replace_mock_with_city() -> void:
	if is_instance_valid(_city) and _city.name == "MissionChainMockWorld":
		root.remove_child(_city)
		_city.free()
		_city = null
	_load_city()
	_verify_map_pause_cycle()


func _verify_map_pause_cycle() -> void:
	var full_map := _city.get_node_or_null("FullMap")
	if full_map == null:
		_record_failure("city scene does not instance FullMap")
		_begin_cleanup(_failures, 1)
		return
	if not full_map.has_method("open_map") or not full_map.has_method("close_map"):
		_record_failure("FullMap does not expose open_map/close_map")
		_begin_cleanup(_failures, 1)
		return

	var previous_pause := paused
	full_map.call("open_map")
	_check(paused, "FullMap did not pause the tree when opened")
	if full_map.has_method("is_map_open"):
		_check(bool(full_map.call("is_map_open")), "FullMap did not report open state")

	full_map.call("close_map")
	_check(paused == previous_pause, "FullMap did not restore previous pause state")
	if full_map.has_method("is_map_open"):
		_check(not bool(full_map.call("is_map_open")), "FullMap did not report closed state")

	if not _failures.is_empty():
		_begin_cleanup(_failures, 1)


func _wait_for_city_zone() -> void:
	_city_zone = _find_district_zone(&"city_east_a")
	if _city_zone == null:
		return

	_city_zone_area = _zone_area_for(_city_zone)
	if _city_zone_area == null:
		return

	_set_phase(Phase.COMPLETE_EASTWARD)


func _complete_eastward() -> void:
	_body.global_position = _city_zone.global_position + Vector3.UP
	_body.velocity = Vector3.ZERO
	_city_zone_area.emit_signal(&"body_entered", _body)
	_set_phase(Phase.WAIT_BLOCK_PARTY)


func _kill_city_pylons() -> void:
	if _city_zone == null:
		_city_zone = _find_district_zone(&"city_east_a")
	if _city_zone == null:
		_record_failure("city_east_a zone disappeared before pylon kill")
		_begin_cleanup(_failures, 1)
		return

	var killed := 0
	for node in _city_zone.find_children("Health", "Health", true, false):
		var health := node as Health
		if health != null and not health.is_dead:
			health.apply_damage(999.0, null)
			killed += 1

	if killed <= 0:
		_record_failure("no live pylons found for city_east_a")
		_begin_cleanup(_failures, 1)
		return

	_set_phase(Phase.WAIT_BLOCK_PARTY_COMPLETE)


func _wait_for_block_party_complete() -> void:
	if not _completed_ids.has("block_party"):
		return

	_check(_started_ids.has("liberate_nw"), "liberate_nw did not start")
	_check(_completed_ids.has("liberate_nw"), "liberate_nw did not complete")
	_check(_started_ids.has("eastward"), "eastward did not start")
	_check(_completed_ids.has("eastward"), "eastward did not complete")
	_check(_started_ids.has("block_party"), "block_party did not start")
	_check(_objectives_seen.has("Drive east to the converted district"), "eastward objective was not emitted")
	_check(_objectives_seen.has("Liberate city_east_a"), "block party objective was not emitted")
	_check(float(_city_zone.call("get_control")) <= -1.0, "city_east_a control did not reach -1")

	if _failures.is_empty():
		print("CITY MISSIONS TEST PASS (liberate_nw -> eastward -> block_party completed, city_east_a control %.1f)" % float(_city_zone.call("get_control")))
		_begin_cleanup([], 0)
	else:
		_begin_cleanup(_failures, 1)


func _find_district_zone(district_name: StringName) -> Node3D:
	for node in root.get_tree().get_nodes_in_group(&"conversion_zone"):
		var zone := _zone_root_from_node(node)
		if zone != null and _district_name_for(zone) == district_name:
			return zone
	return null


func _zone_area_for(zone: Node) -> Area3D:
	for node in zone.find_children("*", "Area3D", true, false):
		var area := node as Area3D
		if area != null and area.is_in_group(&"conversion_zone"):
			return area
	return null


func _zone_root_from_node(node: Node) -> Node3D:
	var cursor := node
	while cursor != null:
		var node3d := cursor as Node3D
		if node3d != null and node3d.has_method("get_control") and _district_name_for(node3d) != &"":
			return node3d
		cursor = cursor.get_parent()
	return null


func _district_name_for(node: Node) -> StringName:
	if node == null:
		return &""

	var value: Variant = node.get("district_name")
	if value == null:
		return &""
	return StringName(str(value))


func _on_mission_started(mission: Node) -> void:
	_started_ids.append(String(mission.get("mission_id")))


func _on_mission_objective(text: String) -> void:
	_objectives_seen.append(text)


func _on_mission_completed(mission: Node) -> void:
	_completed_ids.append(String(mission.get("mission_id")))


func _set_phase(phase: int) -> void:
	_phase = phase
	_phase_frames = 0


func _connect_once(source: Object, signal_name: StringName, callback: Callable) -> void:
	if not source.is_connected(signal_name, callback):
		source.connect(signal_name, callback)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_record_failure(msg)


func _record_failure(msg: String) -> void:
	if not _failures.has(msg):
		_failures.append(msg)


func _phase_name(phase: int) -> String:
	match phase:
		Phase.START_LIBERATE_NW:
			return "START_LIBERATE_NW"
		Phase.COMPLETE_LIBERATE_NW_VISIT:
			return "COMPLETE_LIBERATE_NW_VISIT"
		Phase.COMPLETE_LIBERATE_NW_CONTROL:
			return "COMPLETE_LIBERATE_NW_CONTROL"
		Phase.WAIT_EASTWARD:
			return "WAIT_EASTWARD"
		Phase.WAIT_CITY_ZONE:
			return "WAIT_CITY_ZONE"
		Phase.COMPLETE_EASTWARD:
			return "COMPLETE_EASTWARD"
		Phase.WAIT_BLOCK_PARTY:
			return "WAIT_BLOCK_PARTY"
		Phase.KILL_CITY_PYLONS:
			return "KILL_CITY_PYLONS"
		Phase.WAIT_BLOCK_PARTY_COMPLETE:
			return "WAIT_BLOCK_PARTY_COMPLETE"
		_:
			return "UNKNOWN"


func _begin_cleanup(failures: Array[String], exit_code: int) -> void:
	if _cleanup_started:
		return

	for failure in failures:
		print("CITY MISSIONS TEST FAIL: ", failure)

	_cleanup_started = true
	_cleanup_exit_code = exit_code
	current_scene = null
	if is_instance_valid(_city):
		_city.queue_free()
