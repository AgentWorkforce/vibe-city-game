extends RefCounted

const EventsScript = preload("res://scripts/core/events.gd")
const PedestrianScript = preload("res://scripts/pedestrians/pedestrian_behavior.gd")
const SimLODLogic = preload("res://scripts/sim_lod/sim_lod_logic.gd")
const SimLODManagerScript = preload("res://scripts/sim_lod/sim_lod_manager.gd")

var failures: Array = []


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func test_tier_assignment_boundaries() -> void:
	check(SimLODLogic.tier_for_distance(0.0) == SimLODLogic.TIER_NEAR, "zero distance should be NEAR")
	check(SimLODLogic.tier_for_distance(34.99) == SimLODLogic.TIER_NEAR, "distance below near threshold should be NEAR")
	check(SimLODLogic.tier_for_distance(35.0) == SimLODLogic.TIER_MID, "near threshold should enter MID")
	check(SimLODLogic.tier_for_distance(89.99) == SimLODLogic.TIER_MID, "distance below far threshold should be MID")
	check(SimLODLogic.tier_for_distance(90.0) == SimLODLogic.TIER_FAR, "far threshold should enter FAR")
	check(SimLODLogic.tier_for_distance_squared(35.0 * 35.0) == SimLODLogic.TIER_MID, "squared near threshold should enter MID")
	check(SimLODLogic.tier_for_distance_squared(90.0 * 90.0) == SimLODLogic.TIER_FAR, "squared far threshold should enter FAR")


func test_mid_interval_scales_with_distance() -> void:
	check(SimLODLogic.mid_tick_interval(40.0) == 2, "near edge of MID should update every second frame")
	check(SimLODLogic.mid_tick_interval(75.0) == 3, "far edge of MID should update every third frame")
	check(SimLODLogic.mid_tick_interval_squared(40.0 * 40.0) == 2, "squared near edge should update every second frame")
	check(SimLODLogic.mid_tick_interval_squared(75.0 * 75.0) == 3, "squared far edge should update every third frame")


func test_promotion_never_demotes_near_subjects() -> void:
	check(
		SimLODLogic.promoted_tier(SimLODLogic.TIER_NEAR, true) == SimLODLogic.TIER_NEAR,
		"promotion should not demote NEAR subjects to MID"
	)
	check(
		SimLODLogic.promoted_tier(SimLODLogic.TIER_FAR, true) == SimLODLogic.TIER_MID,
		"promotion should raise FAR subjects to MID"
	)


func test_mid_tick_uses_accumulated_delta() -> void:
	var pedestrian := PedestrianScript.new()
	pedestrian.set_sim_lod(SimLODLogic.TIER_MID, 2)

	var should_process_a := bool(pedestrian.call("_begin_sim_lod_step", 0.016))
	var should_process_b := bool(pedestrian.call("_begin_sim_lod_step", 0.016))
	var compensated_delta := float(pedestrian.get("_sim_lod_step_delta"))

	check(not should_process_a, "first MID actor tick should be skipped")
	check(should_process_b, "second MID actor tick should process")
	check(absf(compensated_delta - 0.032) < 0.0001, "MID actor tick did not compensate accumulated delta")
	pedestrian.free()


func test_mid_motion_scale_compensates_solver_displacement() -> void:
	var physics_delta := 0.016
	var step_delta := 0.048
	var speed := 5.0
	var scale := SimLODLogic.motion_delta_scale(step_delta, physics_delta)
	var solver_displacement := speed * scale * physics_delta
	var expected_displacement := speed * step_delta

	check(absf(scale - 3.0) < 0.0001, "MID motion scale should match accumulated-to-physics delta ratio")
	check(absf(solver_displacement - expected_displacement) < 0.0001, "MID solver displacement should match accumulated intent displacement")
	check(SimLODLogic.motion_delta_scale(step_delta, 0.0) == 1.0, "zero physics delta should fall back to unscaled motion")


func test_far_pedestrian_promotes_to_mid_and_flees_on_nearby_crime() -> void:
	var fixture := _make_manager_fixture(Vector3.ZERO)
	var manager := fixture["manager"] as Node
	var world := fixture["world"] as Node3D
	var events := fixture["events"] as Node

	var pedestrian := PedestrianScript.new()
	pedestrian.name = "FarCrimePedestrian"
	pedestrian.idle_min_duration = 99.0
	pedestrian.idle_max_duration = 99.0
	pedestrian.set("_sim_lod_manager", manager)
	world.add_child(pedestrian)
	pedestrian.position = Vector3(120.0, 0.35, 0.0)
	events.connect(&"crime_committed", Callable(pedestrian, "_on_crime_committed"))
	manager.call("register_npc", pedestrian, &"pedestrian")

	manager.call("force_update_tiers")
	check(int(manager.call("get_tier", pedestrian)) == SimLODLogic.TIER_FAR, "pedestrian should start in FAR tier")

	events.emit_signal(&"crime_committed", 2, pedestrian.position)

	check(pedestrian.get_state_name() == "FLEE", "FAR pedestrian did not enter FLEE from nearby crime signal")
	check(int(manager.call("get_tier", pedestrian)) == SimLODLogic.TIER_MID, "FAR pedestrian was not promoted to MID for reaction")

	_cleanup_fixture(fixture)


func _make_manager_fixture(player_position: Vector3) -> Dictionary:
	var tree := Engine.get_main_loop() as SceneTree
	var root := tree.root
	_remove_existing_test_managers(tree)

	var installed_events := false
	var events := root.get_node_or_null("Events")
	if events == null:
		events = EventsScript.new()
		events.name = "Events"
		root.add_child(events)
		installed_events = true

	var world := Node3D.new()
	world.name = "SimLODTestWorld"
	root.add_child(world)

	var manager := SimLODManagerScript.new()
	manager.name = "SimLODManager"
	manager.auto_register_groups = []
	manager.set("_cached_player_position", player_position)
	manager.set("_has_cached_player", true)
	world.add_child(manager)

	var player := CharacterBody3D.new()
	player.name = "Player"
	player.add_to_group(&"player")
	world.add_child(player)
	player.position = player_position

	manager.call("force_update_tiers")

	return {
		"world": world,
		"manager": manager,
		"events": events,
		"installed_events": installed_events,
	}


func _cleanup_fixture(fixture: Dictionary) -> void:
	var world := fixture["world"] as Node
	if world != null and is_instance_valid(world):
		var parent := world.get_parent()
		if parent != null:
			parent.remove_child(world)
		world.free()

	if bool(fixture.get("installed_events", false)):
		var events := fixture["events"] as Node
		if events != null and is_instance_valid(events):
			var events_parent := events.get_parent()
			if events_parent != null:
				events_parent.remove_child(events)
			events.free()


func _remove_existing_test_managers(tree: SceneTree) -> void:
	for manager in tree.get_nodes_in_group(&"sim_lod_manager"):
		if manager == null:
			continue
		var parent := manager.get_parent()
		if parent != null:
			parent.remove_child(manager)
		manager.free()
