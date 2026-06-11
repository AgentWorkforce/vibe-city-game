extends Node

const InputBindingCodec = preload("res://scripts/core/input_binding_codec.gd")

const DEFAULT_SAVE_PATH := "user://input_bindings.json"
const GAMEPLAY_ACTIONS := [
	"move_forward",
	"move_back",
	"move_left",
	"move_right",
	"jump",
	"sprint",
	"interact",
	"handbrake",
	"look_behind",
	"fire",
	"aim",
	"camera_left",
	"camera_right",
	"camera_up",
	"camera_down",
]

signal binding_changed(action: String)
signal bindings_changed

@export var save_path := DEFAULT_SAVE_PATH

var _default_events: Dictionary = {}
var _overrides: Dictionary = {}


func _ready() -> void:
	_capture_project_defaults()
	reload_from_disk()


func reload_from_disk() -> bool:
	_overrides = _read_overrides()
	_apply_all_overrides()
	bindings_changed.emit()
	return true


func rebind(action: StringName, event: InputEvent) -> bool:
	var action_name := String(action)
	if not _can_manage_action(action_name):
		push_warning("InputBindings ignored unknown action '%s'." % action_name)
		return false

	var normalized := InputBindingCodec.normalized_event(event)
	if normalized == null:
		push_warning("InputBindings ignored unsupported event for '%s'." % action_name)
		return false

	_overrides[action_name] = _events_for_rebind(action_name, normalized)
	_apply_events_to_action(action_name, _overrides[action_name])
	_write_overrides()
	binding_changed.emit(action_name)
	bindings_changed.emit()
	return true


func reset_action(action: StringName) -> bool:
	var action_name := String(action)
	if not _can_manage_action(action_name):
		push_warning("InputBindings cannot reset unknown action '%s'." % action_name)
		return false

	_overrides.erase(action_name)
	_apply_events_to_action(action_name, _default_events.get(action_name, []))
	_write_overrides()
	binding_changed.emit(action_name)
	bindings_changed.emit()
	return true


func reset_all() -> void:
	_overrides.clear()
	for action_name in GAMEPLAY_ACTIONS:
		if _can_manage_action(action_name):
			_apply_events_to_action(action_name, _default_events.get(action_name, []))
	_write_overrides()
	bindings_changed.emit()


func get_binding_text(action: StringName) -> String:
	var events := get_action_events(action)
	if events.is_empty():
		return "Unbound"

	var labels: Array[String] = []
	for event in events:
		labels.append(InputBindingCodec.event_text(event))
	return " / ".join(labels)


func get_actions() -> Array[String]:
	var actions: Array[String] = []
	for action_name in GAMEPLAY_ACTIONS:
		actions.append(action_name)
	return actions


func get_action_events(action: StringName) -> Array[InputEvent]:
	var action_name := String(action)
	if not InputMap.has_action(StringName(action_name)):
		return []
	return _duplicate_events(InputMap.action_get_events(StringName(action_name)))


func get_default_events(action: StringName) -> Array[InputEvent]:
	var action_name := String(action)
	return _duplicate_events(_default_events.get(action_name, []))


func is_known_action(action: StringName) -> bool:
	return GAMEPLAY_ACTIONS.has(String(action))


func _capture_project_defaults() -> void:
	_default_events.clear()
	for action_name in GAMEPLAY_ACTIONS:
		if InputMap.has_action(StringName(action_name)):
			_default_events[action_name] = _duplicate_events(InputMap.action_get_events(StringName(action_name)))
		else:
			_default_events[action_name] = []


func _read_overrides() -> Dictionary:
	if not FileAccess.file_exists(save_path):
		return {}

	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		push_warning("InputBindings could not read %s: %s" % [save_path, error_string(FileAccess.get_open_error())])
		return {}

	var json := JSON.new()
	var parse_error := json.parse(file.get_as_text())
	if parse_error != OK:
		push_warning("InputBindings ignored corrupt binding file at %s." % save_path)
		return {}

	var parsed: Variant = json.data
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("InputBindings ignored corrupt binding file at %s." % save_path)
		return {}

	var root: Dictionary = parsed
	if int(root.get("version", -1)) != InputBindingCodec.VERSION:
		push_warning("InputBindings ignored unsupported binding file version at %s." % save_path)
		return {}

	var actions_data: Variant = root.get("actions", {})
	if typeof(actions_data) != TYPE_DICTIONARY:
		push_warning("InputBindings ignored corrupt binding actions at %s." % save_path)
		return {}

	var loaded: Dictionary = {}
	var actions: Dictionary = actions_data
	for action_variant in actions.keys():
		var action_name := str(action_variant)
		if not _can_manage_action(action_name):
			continue

		var events := InputBindingCodec.events_from_data(actions[action_variant])
		if events.is_empty():
			push_warning("InputBindings skipped corrupt binding entry for '%s'." % action_name)
			continue
		loaded[action_name] = events

	return loaded


func _write_overrides() -> bool:
	var actions := {}
	for action_name in _overrides.keys():
		actions[action_name] = InputBindingCodec.events_to_data(_overrides[action_name])

	var payload := {
		"version": InputBindingCodec.VERSION,
		"actions": actions,
	}

	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_warning("InputBindings could not write %s: %s" % [save_path, error_string(FileAccess.get_open_error())])
		return false

	file.store_string(JSON.stringify(payload, "\t"))
	return true


func _apply_all_overrides() -> void:
	for action_name in GAMEPLAY_ACTIONS:
		if _can_manage_action(action_name):
			_apply_events_to_action(action_name, _default_events.get(action_name, []))

	for action_name in _overrides.keys():
		_apply_events_to_action(str(action_name), _overrides[action_name])


func _apply_events_to_action(action_name: String, events: Array) -> void:
	var action := StringName(action_name)
	if not InputMap.has_action(action):
		return

	InputMap.action_erase_events(action)
	for event in events:
		var input_event := event as InputEvent
		if input_event == null:
			continue
		var normalized := InputBindingCodec.normalized_event(input_event)
		if normalized != null:
			InputMap.action_add_event(action, normalized)


func _events_for_rebind(action_name: String, replacement: InputEvent) -> Array[InputEvent]:
	var result: Array[InputEvent] = []
	var seen := {}
	var replacement_family := _event_family(replacement)
	_add_unique_event(result, seen, replacement)

	for event in get_action_events(StringName(action_name)):
		if _event_family(event) == replacement_family:
			continue
		_add_unique_event(result, seen, event)

	return result


func _add_unique_event(events: Array[InputEvent], seen: Dictionary, event: InputEvent) -> void:
	var normalized := InputBindingCodec.normalized_event(event)
	if normalized == null:
		return

	var signature := InputBindingCodec.event_signature(normalized)
	if signature.is_empty() or seen.has(signature):
		return

	seen[signature] = true
	events.append(normalized)


func _event_family(event: InputEvent) -> StringName:
	if event is InputEventJoypadMotion:
		return &"joy_axis"
	if event is InputEventJoypadButton:
		return &"joy_button"
	if event is InputEventKey or event is InputEventMouseButton:
		return &"keyboard_mouse"
	return &"unknown"


func _can_manage_action(action_name: String) -> bool:
	return GAMEPLAY_ACTIONS.has(action_name) and InputMap.has_action(StringName(action_name))


func _duplicate_events(events: Array) -> Array[InputEvent]:
	var result: Array[InputEvent] = []
	for event in events:
		var input_event := event as InputEvent
		if input_event == null:
			continue
		var normalized := InputBindingCodec.normalized_event(input_event)
		if normalized != null:
			result.append(normalized)
	return result
