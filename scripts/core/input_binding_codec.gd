class_name InputBindingCodec
extends RefCounted

const VERSION := 1


static func event_to_dict(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		var key := event as InputEventKey
		var code := _effective_key_code(key)
		return {
			"type": "key",
			"keycode": int(key.keycode),
			"physical_keycode": int(key.physical_keycode),
			"key_label": int(key.key_label),
			"location": int(key.location),
			"alt": key.alt_pressed and code != KEY_ALT,
			"shift": key.shift_pressed and code != KEY_SHIFT,
			"ctrl": key.ctrl_pressed and code != KEY_CTRL,
			"meta": key.meta_pressed and code != KEY_META,
		}

	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		return {
			"type": "mouse_button",
			"button_index": int(mouse.button_index),
			"alt": mouse.alt_pressed,
			"shift": mouse.shift_pressed,
			"ctrl": mouse.ctrl_pressed,
			"meta": mouse.meta_pressed,
		}

	if event is InputEventJoypadButton:
		var button := event as InputEventJoypadButton
		return {
			"type": "joy_button",
			"button_index": int(button.button_index),
		}

	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		return {
			"type": "joy_axis",
			"axis": int(motion.axis),
			"axis_value": clampf(float(motion.axis_value), -1.0, 1.0),
		}

	return {}


static func dict_to_event(data: Variant) -> InputEvent:
	if typeof(data) != TYPE_DICTIONARY:
		return null

	var dict: Dictionary = data
	var type := str(dict.get("type", ""))
	match type:
		"key":
			return _dict_to_key_event(dict)
		"mouse_button":
			return _dict_to_mouse_button_event(dict)
		"joy_button":
			return _dict_to_joy_button_event(dict)
		"joy_axis":
			return _dict_to_joy_axis_event(dict)

	return null


static func events_to_data(events: Array) -> Array:
	var result: Array = []
	for event in events:
		var input_event := event as InputEvent
		if input_event == null:
			continue
		var data := event_to_dict(input_event)
		if not data.is_empty():
			result.append(data)
	return result


static func events_from_data(data: Variant) -> Array[InputEvent]:
	var result: Array[InputEvent] = []
	if typeof(data) != TYPE_ARRAY:
		return result

	for entry in data:
		var event := dict_to_event(entry)
		if event != null:
			result.append(event)
	return result


static func is_supported_event(event: InputEvent) -> bool:
	return not event_to_dict(event).is_empty()


static func is_supported_capture_event(event: InputEvent) -> bool:
	if event is InputEventKey:
		var key := event as InputEventKey
		return key.pressed and not key.echo and _has_key_code(key)

	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		return mouse.pressed and int(mouse.button_index) > 0

	if event is InputEventJoypadButton:
		var button := event as InputEventJoypadButton
		return button.pressed and int(button.button_index) >= 0

	return false


static func normalized_event(event: InputEvent) -> InputEvent:
	var data := event_to_dict(event)
	if data.is_empty():
		return null
	return dict_to_event(data)


static func event_signature(event: InputEvent) -> String:
	var data := event_to_dict(event)
	if data.is_empty():
		return ""
	return dict_signature(data)


static func dict_signature(data: Dictionary) -> String:
	var type := str(data.get("type", ""))
	match type:
		"key":
			var code := int(data.get("physical_keycode", 0))
			if code == 0:
				code = int(data.get("keycode", 0))
			if code == 0:
				code = int(data.get("key_label", 0))
			return "key:%d:%d:%d:%d:%d:%d" % [
				code,
				int(data.get("location", 0)),
				1 if bool(data.get("alt", false)) else 0,
				1 if bool(data.get("shift", false)) else 0,
				1 if bool(data.get("ctrl", false)) else 0,
				1 if bool(data.get("meta", false)) else 0,
			]
		"mouse_button":
			return "mouse:%d:%d:%d:%d:%d" % [
				int(data.get("button_index", 0)),
				1 if bool(data.get("alt", false)) else 0,
				1 if bool(data.get("shift", false)) else 0,
				1 if bool(data.get("ctrl", false)) else 0,
				1 if bool(data.get("meta", false)) else 0,
			]
		"joy_button":
			return "joy_button:%d" % int(data.get("button_index", -1))
		"joy_axis":
			return "joy_axis:%d:%s" % [
				int(data.get("axis", -1)),
				"negative" if float(data.get("axis_value", 0.0)) < 0.0 else "positive",
			]

	return ""


static func event_text(event: InputEvent) -> String:
	if event is InputEventKey:
		return _key_text(event as InputEventKey)
	if event is InputEventMouseButton:
		return _mouse_button_text(event as InputEventMouseButton)
	if event is InputEventJoypadButton:
		return "Pad %s" % _joy_button_name(int((event as InputEventJoypadButton).button_index))
	if event is InputEventJoypadMotion:
		return _joy_axis_text(event as InputEventJoypadMotion)
	return "Unbound"


static func _dict_to_key_event(dict: Dictionary) -> InputEventKey:
	var key := InputEventKey.new()
	key.keycode = int(dict.get("keycode", 0))
	key.physical_keycode = int(dict.get("physical_keycode", 0))
	key.key_label = int(dict.get("key_label", 0))
	key.location = int(dict.get("location", 0))
	key.alt_pressed = bool(dict.get("alt", false))
	key.shift_pressed = bool(dict.get("shift", false))
	key.ctrl_pressed = bool(dict.get("ctrl", false))
	key.meta_pressed = bool(dict.get("meta", false))
	key.pressed = false
	key.echo = false
	key.device = -1

	if not _has_key_code(key):
		return null
	return key


static func _dict_to_mouse_button_event(dict: Dictionary) -> InputEventMouseButton:
	var button_index := int(dict.get("button_index", 0))
	if button_index <= 0:
		return null

	var mouse := InputEventMouseButton.new()
	mouse.button_index = button_index
	mouse.alt_pressed = bool(dict.get("alt", false))
	mouse.shift_pressed = bool(dict.get("shift", false))
	mouse.ctrl_pressed = bool(dict.get("ctrl", false))
	mouse.meta_pressed = bool(dict.get("meta", false))
	mouse.pressed = false
	mouse.double_click = false
	mouse.device = -1
	return mouse


static func _dict_to_joy_button_event(dict: Dictionary) -> InputEventJoypadButton:
	var button_index := int(dict.get("button_index", -1))
	if button_index < 0:
		return null

	var button := InputEventJoypadButton.new()
	button.button_index = button_index
	button.pressed = false
	button.device = -1
	return button


static func _dict_to_joy_axis_event(dict: Dictionary) -> InputEventJoypadMotion:
	var axis := int(dict.get("axis", -1))
	var axis_value := float(dict.get("axis_value", 0.0))
	if axis < 0 or absf(axis_value) < 0.001:
		return null

	var motion := InputEventJoypadMotion.new()
	motion.axis = axis
	motion.axis_value = -1.0 if axis_value < 0.0 else 1.0
	motion.device = -1
	return motion


static func _has_key_code(key: InputEventKey) -> bool:
	return int(key.keycode) != 0 or int(key.physical_keycode) != 0 or int(key.key_label) != 0


static func _key_text(key: InputEventKey) -> String:
	var code := _effective_key_code(key)
	var text := OS.get_keycode_string(code)
	if text.is_empty():
		text = "Key %d" % code

	var parts := _modifier_parts(key)
	if not parts.is_empty():
		parts.append(text)
		return " + ".join(parts)
	return text


static func _effective_key_code(key: InputEventKey) -> int:
	var code := int(key.physical_keycode)
	if code == 0:
		code = int(key.keycode)
	if code == 0:
		code = int(key.key_label)
	return code


static func _mouse_button_text(mouse: InputEventMouseButton) -> String:
	var parts := _modifier_parts(mouse)
	parts.append("Mouse %s" % _mouse_button_name(int(mouse.button_index)))
	return " + ".join(parts)


static func _modifier_parts(event: InputEventWithModifiers) -> Array[String]:
	var parts: Array[String] = []
	if event.ctrl_pressed:
		parts.append("Ctrl")
	if event.alt_pressed:
		parts.append("Alt")
	if event.shift_pressed:
		parts.append("Shift")
	if event.meta_pressed:
		parts.append("Meta")
	return parts


static func _mouse_button_name(button_index: int) -> String:
	match button_index:
		MOUSE_BUTTON_LEFT:
			return "Left"
		MOUSE_BUTTON_RIGHT:
			return "Right"
		MOUSE_BUTTON_MIDDLE:
			return "Middle"
		MOUSE_BUTTON_WHEEL_UP:
			return "Wheel Up"
		MOUSE_BUTTON_WHEEL_DOWN:
			return "Wheel Down"
		MOUSE_BUTTON_WHEEL_LEFT:
			return "Wheel Left"
		MOUSE_BUTTON_WHEEL_RIGHT:
			return "Wheel Right"
		MOUSE_BUTTON_XBUTTON1:
			return "Back"
		MOUSE_BUTTON_XBUTTON2:
			return "Forward"
	return "Button %d" % button_index


static func _joy_button_name(button_index: int) -> String:
	var names := {
		0: "A",
		1: "B",
		2: "X",
		3: "Y",
		4: "Back",
		5: "Guide",
		6: "Start",
		7: "Left Stick",
		8: "Right Stick",
		9: "Left Shoulder",
		10: "Right Shoulder",
		11: "D-pad Up",
		12: "D-pad Down",
		13: "D-pad Left",
		14: "D-pad Right",
		15: "Misc",
		16: "Paddle 1",
		17: "Paddle 2",
		18: "Paddle 3",
		19: "Paddle 4",
		20: "Touchpad",
	}
	return str(names.get(button_index, "Button %d" % button_index))


static func _joy_axis_text(motion: InputEventJoypadMotion) -> String:
	var axis := int(motion.axis)
	var negative := float(motion.axis_value) < 0.0
	match axis:
		0:
			return "Pad Left Stick Left" if negative else "Pad Left Stick Right"
		1:
			return "Pad Left Stick Up" if negative else "Pad Left Stick Down"
		2:
			return "Pad Right Stick Left" if negative else "Pad Right Stick Right"
		3:
			return "Pad Right Stick Up" if negative else "Pad Right Stick Down"
		4:
			return "Pad Left Trigger -" if negative else "Pad Left Trigger"
		5:
			return "Pad Right Trigger -" if negative else "Pad Right Trigger"
	return "Pad Axis %d %s" % [axis, "-" if negative else "+"]
