extends RefCounted

const InputBindingCodec = preload("res://scripts/core/input_binding_codec.gd")
const InputBindingsScript = preload("res://scripts/core/input_bindings.gd")

var failures: Array = []


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func test_key_event_round_trips() -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_W
	event.shift_pressed = true

	var restored := _round_trip(event, "key")
	check(restored is InputEventKey, "key restored as wrong event type")
	check(InputBindingCodec.event_text(restored).contains("W"), "key text did not include key name")


func test_mouse_button_event_round_trips() -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.ctrl_pressed = true

	var restored := _round_trip(event, "mouse")
	check(restored is InputEventMouseButton, "mouse button restored as wrong event type")
	check(InputBindingCodec.event_text(restored).contains("Mouse Right"), "mouse text did not include button name")


func test_joy_button_event_round_trips() -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = 7

	var restored := _round_trip(event, "joy button")
	check(restored is InputEventJoypadButton, "joy button restored as wrong event type")
	check(InputBindingCodec.event_text(restored).contains("Left Stick"), "joy button text did not include button name")


func test_joy_axis_event_round_trips_for_display() -> void:
	var event := InputEventJoypadMotion.new()
	event.axis = 1
	event.axis_value = -0.7

	var restored := _round_trip(event, "joy axis")
	check(restored is InputEventJoypadMotion, "joy axis restored as wrong event type")
	check(InputBindingCodec.event_text(restored).contains("Left Stick Up"), "joy axis text did not include axis direction")


func test_corrupt_dicts_are_rejected() -> void:
	check(InputBindingCodec.dict_to_event({}) == null, "empty dictionary should be rejected")
	check(InputBindingCodec.dict_to_event({"type": "unknown"}) == null, "unknown type should be rejected")
	check(InputBindingCodec.dict_to_event({"type": "key"}) == null, "key without code should be rejected")
	check(InputBindingCodec.dict_to_event({"type": "mouse_button", "button_index": 0}) == null, "mouse button zero should be rejected")
	check(InputBindingCodec.dict_to_event({"type": "joy_button", "button_index": -1}) == null, "negative joy button should be rejected")
	check(InputBindingCodec.dict_to_event({"type": "joy_axis", "axis": 0, "axis_value": 0.0}) == null, "neutral joy axis should be rejected")


func test_capture_support_excludes_joy_axes() -> void:
	var axis := InputEventJoypadMotion.new()
	axis.axis = 1
	axis.axis_value = 1.0
	check(not InputBindingCodec.is_supported_capture_event(axis), "joy axes should be display-only for capture v1")

	var button := InputEventJoypadButton.new()
	button.button_index = 0
	button.pressed = true
	check(InputBindingCodec.is_supported_capture_event(button), "joy buttons should be capturable")


func test_manager_rebind_and_reset_restore_project_defaults() -> void:
	var original_jump_events := _snapshot_action("jump")
	var original_jump_signatures := _event_signatures(original_jump_events)
	var manager := InputBindingsScript.new()
	manager.save_path = "user://test_input_bindings_reset.json"
	_remove_user_file(manager.save_path)

	manager.call("_capture_project_defaults")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F
	manager.rebind(&"jump", key)
	check(_action_has_signature("jump", InputBindingCodec.event_signature(key)), "manager did not apply rebound key to InputMap")
	check(_action_signatures("jump").has(_first_signature_for_type(original_jump_events, "joy_button")), "keyboard rebind did not preserve gamepad button binding")

	manager.reset_action(&"jump")
	check(_action_signatures("jump") == original_jump_signatures, "reset_action did not restore project default jump events")

	_restore_action("jump", original_jump_events)
	_remove_user_file(manager.save_path)
	manager.free()


func test_manager_rebind_preserves_display_only_joy_axis() -> void:
	var original_camera_events := _snapshot_action("camera_left")
	var original_camera_signatures := _event_signatures(original_camera_events)
	var manager := InputBindingsScript.new()
	manager.save_path = "user://test_input_bindings_axis.json"
	_remove_user_file(manager.save_path)
	manager.call("_capture_project_defaults")

	var key := InputEventKey.new()
	key.physical_keycode = KEY_Q
	manager.rebind(&"camera_left", key)

	check(_action_has_signature("camera_left", InputBindingCodec.event_signature(key)), "keyboard rebind did not apply to camera_left")
	check(_action_signatures("camera_left").has(_first_signature_for_type(original_camera_events, "joy_axis")), "camera rebind did not preserve display-only joy axis")

	manager.reset_action(&"camera_left")
	check(_action_signatures("camera_left") == original_camera_signatures, "reset_action did not restore project default camera_left events")

	_restore_action("camera_left", original_camera_events)
	_remove_user_file(manager.save_path)
	manager.free()


func test_manager_corrupt_reload_restores_defaults() -> void:
	var original_jump_events := _snapshot_action("jump")
	var manager := InputBindingsScript.new()
	manager.save_path = "user://test_input_bindings_corrupt.json"
	_remove_user_file(manager.save_path)
	manager.call("_capture_project_defaults")

	var key := InputEventKey.new()
	key.physical_keycode = KEY_F
	manager.rebind(&"jump", key)

	var file := FileAccess.open(manager.save_path, FileAccess.WRITE)
	if file != null:
		file.store_string("{not valid json")
	manager.reload_from_disk()
	check(_action_signatures("jump") == _event_signatures(original_jump_events), "corrupt reload left stale runtime override in InputMap")

	_restore_action("jump", original_jump_events)
	_remove_user_file(manager.save_path)
	manager.free()


func _round_trip(event: InputEvent, label: String) -> InputEvent:
	var data := InputBindingCodec.event_to_dict(event)
	check(not data.is_empty(), "%s event did not serialize" % label)

	var restored := InputBindingCodec.dict_to_event(data)
	check(restored != null, "%s event did not restore" % label)
	if restored == null:
		return null

	check(
		InputBindingCodec.event_signature(event) == InputBindingCodec.event_signature(restored),
		"%s event signature changed during round-trip" % label
	)
	return restored


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


func _action_has_signature(action_name: String, signature: String) -> bool:
	return _action_signatures(action_name).has(signature)


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


func _first_signature_for_type(events: Array, type_name: String) -> String:
	for event in events:
		var input_event := event as InputEvent
		if input_event == null:
			continue

		var matches_type := false
		match type_name:
			"joy_button":
				matches_type = input_event is InputEventJoypadButton
			"joy_axis":
				matches_type = input_event is InputEventJoypadMotion
			"keyboard_mouse":
				matches_type = input_event is InputEventKey or input_event is InputEventMouseButton

		if matches_type:
			return InputBindingCodec.event_signature(input_event)
	return ""


func _remove_user_file(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
