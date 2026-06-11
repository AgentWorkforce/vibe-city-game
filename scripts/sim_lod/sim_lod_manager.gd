class_name SimLODManager
extends Node

const Logic := preload("res://scripts/sim_lod/sim_lod_logic.gd")

const TIER_NEAR := Logic.TIER_NEAR
const TIER_MID := Logic.TIER_MID
const TIER_FAR := Logic.TIER_FAR

const GROUP_NAME := &"sim_lod_manager"

@export var near_distance: float = 35.0
@export var far_distance: float = 90.0
@export var reassess_interval: float = 0.5
@export var reaction_promote_seconds: float = 2.5
@export var lod_enabled: bool = true
@export var force_mid_as_near: bool = false
@export var force_far_as_near: bool = false
@export var auto_register_groups: Array[StringName] = [
	&"pedestrians",
	&"agents",
	&"traffic_cars",
]

var _subjects: Dictionary = {}
var _reassess_timer := 0.0
var _cached_player_position := Vector3.ZERO
var _has_cached_player := false
var _transition_counts: Dictionary = {}
var _assignment_counts := {
	"NEAR": 0,
	"MID": 0,
	"FAR": 0,
}

static var _pending_manager: WeakRef


static func get_or_create(requester: Node) -> Node:
	if requester == null or not requester.is_inside_tree():
		return null

	var tree := requester.get_tree()
	if tree == null:
		return null

	var existing := tree.get_first_node_in_group(GROUP_NAME)
	if existing != null:
		return existing

	if _pending_manager != null:
		var pending := _pending_manager.get_ref() as Node
		if pending != null and is_instance_valid(pending):
			return pending

	var manager := new()
	manager.name = "SimLODManager"
	_pending_manager = weakref(manager)
	var parent := tree.current_scene
	if parent == null:
		parent = requester.get_parent()
	if parent == null:
		parent = tree.root
	parent.call_deferred("add_child", manager)
	return manager


func _ready() -> void:
	add_to_group(GROUP_NAME)
	if _pending_manager != null and _pending_manager.get_ref() == self:
		_pending_manager = null
	_apply_diagnostic_overrides()
	_connect_events()
	_refresh_player_cache()
	_discover_subjects()
	_assign_all_tiers(true)


func _physics_process(delta: float) -> void:
	if not lod_enabled:
		return

	_reassess_timer -= delta
	if _reassess_timer > 0.0:
		return

	_reassess_timer = maxf(reassess_interval, 0.05)
	_refresh_player_cache()
	_assign_all_tiers(false)


func register_npc(subject: Node, subject_kind: StringName = &"") -> void:
	var subject_3d := subject as Node3D
	if subject_3d == null:
		return

	var subject_id := subject.get_instance_id()
	var is_new_subject := not _subjects.has(subject_id)
	if _subjects.has(subject_id):
		var existing := _subjects[subject_id] as Dictionary
		existing["kind"] = subject_kind
		_subjects[subject_id] = existing
	else:
		_subjects[subject_id] = {
			"node": subject_3d,
			"kind": subject_kind,
			"tier": TIER_NEAR,
			"distance_sq": 0.0,
			"mid_interval": 1,
			"promote_until_msec": 0,
		}

	_assign_subject_tier(subject_id, is_new_subject)


func unregister_npc(subject: Node) -> void:
	if subject == null:
		return
	_subjects.erase(subject.get_instance_id())


func promote_for_reaction(subject: Node, seconds: float = -1.0) -> void:
	if subject == null:
		return

	var subject_id := subject.get_instance_id()
	if not _subjects.has(subject_id):
		register_npc(subject)
	if not _subjects.has(subject_id):
		return

	var duration := reaction_promote_seconds if seconds < 0.0 else seconds
	var entry := _subjects[subject_id] as Dictionary
	var until_msec := Time.get_ticks_msec() + int(maxf(duration, 0.0) * 1000.0)
	entry["promote_until_msec"] = maxi(int(entry.get("promote_until_msec", 0)), until_msec)
	_subjects[subject_id] = entry
	_assign_subject_tier(subject_id, true)


func force_update_tiers() -> void:
	_refresh_player_cache()
	_discover_subjects()
	_assign_all_tiers(true)


func get_tier(subject: Node) -> int:
	if subject == null:
		return TIER_NEAR

	var subject_id := subject.get_instance_id()
	if not _subjects.has(subject_id):
		return TIER_NEAR
	var entry := _subjects[subject_id] as Dictionary
	return int(entry.get("tier", TIER_NEAR))


func get_tier_name(subject: Node) -> String:
	return Logic.tier_name(get_tier(subject))


func get_registered_count() -> int:
	_prune_invalid_subjects()
	return _subjects.size()


func get_tier_counts() -> Dictionary:
	var counts := {
		"NEAR": 0,
		"MID": 0,
		"FAR": 0,
	}
	_prune_invalid_subjects()
	for subject_id in _subjects.keys():
		var entry := _subjects[subject_id] as Dictionary
		var tier_name := Logic.tier_name(int(entry.get("tier", TIER_NEAR)))
		if counts.has(tier_name):
			counts[tier_name] = int(counts[tier_name]) + 1
	return counts


func get_transition_counts() -> Dictionary:
	return _transition_counts.duplicate()


func get_assignment_counts() -> Dictionary:
	return _assignment_counts.duplicate()


func get_diagnostic_state() -> Dictionary:
	return {
		"lod_enabled": lod_enabled,
		"force_mid_as_near": force_mid_as_near,
		"force_far_as_near": force_far_as_near,
		"tier_counts": get_tier_counts(),
		"transition_counts": get_transition_counts(),
		"assignment_counts": get_assignment_counts(),
	}


func _discover_subjects() -> void:
	if not is_inside_tree():
		return

	for group_name in auto_register_groups:
		for node in get_tree().get_nodes_in_group(group_name):
			var subject := node as Node3D
			if subject != null and subject.has_method("set_sim_tier"):
				register_npc(subject, group_name)


func _assign_all_tiers(force: bool) -> void:
	_prune_invalid_subjects()
	for subject_id in _subjects.keys():
		_assign_subject_tier(int(subject_id), force)


func _assign_subject_tier(subject_id: int, force: bool) -> void:
	if not _subjects.has(subject_id):
		return

	var entry := _subjects[subject_id] as Dictionary
	var subject := entry.get("node") as Node3D
	if subject == null or not is_instance_valid(subject):
		_subjects.erase(subject_id)
		return

	var previous_tier := int(entry.get("tier", TIER_NEAR))
	var previous_interval := int(entry.get("mid_interval", 1))
	var distance_sq := _distance_squared_to_player(_subject_position(subject))
	var base_tier := TIER_NEAR
	if lod_enabled and _has_cached_player:
		base_tier = Logic.tier_for_distance_squared(distance_sq, near_distance, far_distance)

	var promoted := Time.get_ticks_msec() <= int(entry.get("promote_until_msec", 0))
	var tier := Logic.promoted_tier(base_tier, promoted, TIER_MID)
	if force_mid_as_near and tier == TIER_MID:
		tier = TIER_NEAR
	if force_far_as_near and tier == TIER_FAR:
		tier = TIER_NEAR
	entry["distance_sq"] = distance_sq
	entry["tier"] = tier
	entry["mid_interval"] = Logic.mid_tick_interval_squared(distance_sq, near_distance, far_distance)
	_count_assignment(tier)

	if force or tier != previous_tier or int(entry["mid_interval"]) != previous_interval:
		if tier != previous_tier:
			_count_transition(previous_tier, tier)
		if subject.has_method("set_sim_lod"):
			subject.call("set_sim_lod", tier, int(entry["mid_interval"]))
		elif subject.has_method("set_sim_tier"):
			subject.call("set_sim_tier", tier)

	_subjects[subject_id] = entry


func _distance_squared_to_player(position: Vector3) -> float:
	if not _has_cached_player:
		return 0.0

	var flat_position := Vector3(position.x, 0.0, position.z)
	var flat_player := Vector3(_cached_player_position.x, 0.0, _cached_player_position.z)
	return flat_position.distance_squared_to(flat_player)


func _count_transition(from_tier: int, to_tier: int) -> void:
	var key := "%s>%s" % [Logic.tier_name(from_tier), Logic.tier_name(to_tier)]
	_transition_counts[key] = int(_transition_counts.get(key, 0)) + 1


func _count_assignment(tier: int) -> void:
	var key := Logic.tier_name(tier)
	if _assignment_counts.has(key):
		_assignment_counts[key] = int(_assignment_counts[key]) + 1


func _apply_diagnostic_overrides() -> void:
	var disabled_env := OS.get_environment("SIM_LOD_DISABLE")
	if _is_truthy_env(disabled_env):
		lod_enabled = false
	if _is_truthy_env(OS.get_environment("SIM_LOD_FORCE_MID_NEAR")):
		force_mid_as_near = true
	if _is_truthy_env(OS.get_environment("SIM_LOD_FORCE_FAR_NEAR")):
		force_far_as_near = true


func _is_truthy_env(value: String) -> bool:
	var clean := value.strip_edges().to_lower()
	return clean in ["1", "true", "yes", "on"]


func _refresh_player_cache() -> void:
	if not is_inside_tree():
		return

	var best_distance_sq := INF
	var best_position := Vector3.ZERO
	var found_player := false
	for node in get_tree().get_nodes_in_group(&"player"):
		var player := node as Node3D
		if player == null or not is_instance_valid(player):
			continue

		var player_position := _subject_position(player)
		var distance_sq := 0.0
		if found_player:
			distance_sq = player_position.distance_squared_to(_cached_player_position)
		if not found_player or distance_sq < best_distance_sq:
			best_distance_sq = distance_sq
			best_position = player_position
			found_player = true

	_has_cached_player = found_player
	if found_player:
		_cached_player_position = best_position


func _subject_position(subject: Node3D) -> Vector3:
	if subject.is_inside_tree():
		return subject.global_position
	return subject.position


func _prune_invalid_subjects() -> void:
	for subject_id in _subjects.keys():
		var entry := _subjects[subject_id] as Dictionary
		var subject := entry.get("node") as Node3D
		if subject == null or not is_instance_valid(subject):
			_subjects.erase(subject_id)


func _connect_events() -> void:
	var events := get_node_or_null("/root/Events")
	if events == null:
		return

	var shifted_callable := Callable(self, "_on_origin_shifted")
	if events.has_signal(&"origin_shifted") and not events.is_connected(&"origin_shifted", shifted_callable):
		events.connect(&"origin_shifted", shifted_callable)


func _on_origin_shifted(offset: Vector3) -> void:
	if _has_cached_player:
		_cached_player_position -= offset
