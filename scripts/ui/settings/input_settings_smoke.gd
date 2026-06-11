extends SceneTree

const InputBindingCodec = preload("res://scripts/core/input_binding_codec.gd")

var _settings: Node
var _original_jump_events: Array[InputEvent] = []
var _previous_pause := false
var _failures: Array[String] = []
var _frames := 0


func _initialize() -> void:
	_original_jump_events = _snapshot_action("jump")
	_previous_pause = paused

	var packed := load("res://scenes/ui/settings/input_settings.tscn") as PackedScene
	if packed == null:
		_failures.append("could not load input settings scene")
		return

	_settings = packed.instantiate()
	root.add_child(_settings)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 2:
		return false

	_run_checks()
	_restore_action("jump", _original_jump_events)
	paused = _previous_pause

	if _settings != null and _settings.get_parent() != null:
		_settings.get_parent().remove_child(_settings)
		_settings.free()
	_settings = null

	if _failures.is_empty():
		print("INPUT SETTINGS SMOKE PASS")
		quit(0)
	else:
		for failure in _failures:
			print("INPUT SETTINGS SMOKE FAIL: ", failure)
		quit(1)
	return true


func _run_checks() -> void:
	if _settings == null:
		_failures.append("settings scene did not instantiate")
		return

	_settings.call("open_settings")
	_check(paused, "settings did not pause tree when opened")
	_check(bool(_settings.call("is_settings_open")), "settings did not report open state")

	var conflicts: Dictionary = _settings.call("_conflicted_actions")
	_check(conflicts.has("jump"), "default jump/handbrake Space conflict did not mark jump")
	_check(conflicts.has("handbrake"), "default jump/handbrake Space conflict did not mark handbrake")

	_settings.call("_focus_first_row")
	_settings.call("_begin_capture", "jump")
	_route_input(_make_key_event(KEY_SPACE))
	_check(str(_settings.get("_capturing_action")) == "", "routed Space key did not clear capture state")
	_check(_action_signatures("jump").has(_key_signature(KEY_SPACE)), "routed Space key was not captured while a button had focus")

	_restore_action("jump", _original_jump_events)
	_settings.call("_begin_capture", "jump")
	_route_input(_make_mouse_button_event(MOUSE_BUTTON_LEFT))
	_check(str(_settings.get("_capturing_action")) == "", "routed mouse button did not clear capture state")
	_check(_action_signatures("jump").has(_mouse_signature(MOUSE_BUTTON_LEFT)), "routed mouse button was not captured through the full-screen GUI root")

	_restore_action("jump", _original_jump_events)
	_settings.call("_begin_capture", "jump")
	_route_input(_make_key_event(KEY_ESCAPE))
	_check(str(_settings.get("_capturing_action")) == "", "ESC did not clear capture state")
	_check(_action_signatures("jump") == _event_signatures(_original_jump_events), "ESC capture cancel changed jump binding")

	_settings.call("close_settings")
	_check(paused == _previous_pause, "settings did not restore previous pause state")
	_check(not bool(_settings.call("is_settings_open")), "settings did not report closed state")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _route_input(event: InputEvent) -> void:
	root.push_input(event)


func _make_key_event(keycode: Key) -> InputEventKey:
	var key := InputEventKey.new()
	key.keycode = keycode
	key.physical_keycode = keycode
	key.pressed = true
	return key


func _make_mouse_button_event(button_index: MouseButton) -> InputEventMouseButton:
	var button := InputEventMouseButton.new()
	button.button_index = button_index
	button.pressed = true
	button.position = Vector2(320.0, 240.0)
	button.global_position = button.position
	return button


func _key_signature(keycode: Key) -> String:
	return InputBindingCodec.event_signature(_make_key_event(keycode))


func _mouse_signature(button_index: MouseButton) -> String:
	return InputBindingCodec.event_signature(_make_mouse_button_event(button_index))


func _snapshot_action(action_name: String) -> Array[InputEvent]:
	var result: Array[InputEvent] = []
	for event in InputMap.action_get_events(StringName(action_name)):
		var normalized := InputBindingCodec.normalized_event(event)
		if normalized != null:
			result.append(normalized)
	return result


func _restore_action(action_name: String, events: Array[InputEvent]) -> void:
	var action := StringName(action_name)
	InputMap.action_erase_events(action)
	for event in events:
		var normalized := InputBindingCodec.normalized_event(event)
		if normalized != null:
			InputMap.action_add_event(action, normalized)


func _action_signatures(action_name: String) -> Array[String]:
	return _event_signatures(InputMap.action_get_events(StringName(action_name)))


func _event_signatures(events: Array) -> Array[String]:
	var signatures: Array[String] = []
	for event in events:
		var input_event := event as InputEvent
		if input_event == null:
			continue
		var signature := InputBindingCodec.event_signature(input_event)
		if not signature.is_empty():
			signatures.append(signature)
	signatures.sort()
	return signatures
