# Temporary entry point until the ESC pause menu lands: this scene toggles with F10.
class_name InputSettingsScreen
extends CanvasLayer

const InputBindingsScript = preload("res://scripts/core/input_bindings.gd")
const InputBindingCodec = preload("res://scripts/core/input_binding_codec.gd")

const CYAN := Color(0.098, 0.89, 0.89, 1.0)
const SOFT_WHITE := Color(0.94, 0.98, 1.0, 1.0)
const GLASS := Color(0.035, 0.08, 0.09, 0.86)
const GLASS_LIGHT := Color(0.055, 0.11, 0.13, 0.74)
const WARNING := Color(1.0, 0.64, 0.24, 1.0)
const CAPTURE := Color(0.52, 0.92, 1.0, 1.0)

const ACTION_LABELS := {
	"move_forward": "Move Forward",
	"move_back": "Move Back",
	"move_left": "Move Left",
	"move_right": "Move Right",
	"jump": "Jump",
	"sprint": "Sprint",
	"interact": "Interact",
	"handbrake": "Handbrake",
	"look_behind": "Look Behind",
	"fire": "Fire",
	"aim": "Aim",
	"camera_left": "Camera Left",
	"camera_right": "Camera Right",
	"camera_up": "Camera Up",
	"camera_down": "Camera Down",
}

@onready var _root: Control = $Root
@onready var _panel: PanelContainer = $Root/Panel
@onready var _title: Label = $Root/Panel/Margin/Content/Header/Title
@onready var _reset_all_button: Button = $Root/Panel/Margin/Content/Header/ResetAllButton
@onready var _close_button: Button = $Root/Panel/Margin/Content/Header/CloseButton
@onready var _capture_banner: PanelContainer = $Root/Panel/Margin/Content/CaptureBanner
@onready var _capture_label: Label = $Root/Panel/Margin/Content/CaptureBanner/Margin/CaptureLabel
@onready var _rows_box: VBoxContainer = $Root/Panel/Margin/Content/Scroll/Rows

var _bindings: Node
var _rows: Dictionary = {}
var _capturing_action := ""
var _is_open := false
var _previous_pause_state := false
var _previous_mouse_mode := Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_set_process_always(self)
	set_process_input(true)
	set_process_unhandled_input(true)
	_resolve_bindings()
	_apply_static_style()
	_build_rows()
	_connect_binding_signals()
	_capture_banner.visible = false
	_root.visible = false


func _input(event: InputEvent) -> void:
	if _capturing_action == "":
		return

	_handle_capture_input(event)


func _unhandled_input(event: InputEvent) -> void:
	if _capturing_action != "":
		_handle_capture_input(event)
		return

	if _is_toggle_event(event):
		if _is_open:
			close_settings()
		else:
			open_settings()
		get_viewport().set_input_as_handled()
		return

	if _is_open and _is_escape_event(event):
		close_settings()
		get_viewport().set_input_as_handled()


func open_settings() -> void:
	if _is_open:
		return

	_previous_pause_state = get_tree().paused
	_previous_mouse_mode = Input.mouse_mode
	_is_open = true
	_root.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_rows()
	call_deferred("_focus_first_row")


func close_settings() -> void:
	if not _is_open:
		return

	_end_capture(false)
	_is_open = false
	_root.visible = false
	get_tree().paused = _previous_pause_state
	Input.mouse_mode = _previous_mouse_mode


func is_settings_open() -> bool:
	return _is_open


func _resolve_bindings() -> void:
	_bindings = get_node_or_null("/root/InputBindings")
	if _bindings != null:
		return

	var local_bindings := InputBindingsScript.new()
	local_bindings.name = "InputBindingsLocal"
	add_child(local_bindings)
	_bindings = local_bindings


func _connect_binding_signals() -> void:
	if _bindings == null or not _bindings.has_signal(&"bindings_changed"):
		return

	var callback := Callable(self, "_refresh_rows")
	if not _bindings.is_connected(&"bindings_changed", callback):
		_bindings.connect(&"bindings_changed", callback)


func _apply_static_style() -> void:
	_panel.add_theme_stylebox_override("panel", _make_panel_style(GLASS, Color(CYAN.r, CYAN.g, CYAN.b, 0.52), 8))
	_capture_banner.add_theme_stylebox_override("panel", _make_panel_style(Color(CAPTURE.r, CAPTURE.g, CAPTURE.b, 0.14), Color(CAPTURE.r, CAPTURE.g, CAPTURE.b, 0.68), 6))

	_title.add_theme_color_override("font_color", SOFT_WHITE)
	_title.add_theme_font_size_override("font_size", 22)
	_title.add_theme_constant_override("outline_size", 1)
	_title.add_theme_color_override("font_outline_color", Color(0.0, 0.05, 0.06, 0.82))

	_capture_label.add_theme_color_override("font_color", SOFT_WHITE)
	_capture_label.add_theme_font_size_override("font_size", 14)
	_capture_label.add_theme_constant_override("outline_size", 1)
	_capture_label.add_theme_color_override("font_outline_color", Color(0.0, 0.05, 0.06, 0.82))

	_style_button(_reset_all_button, 14)
	_style_button(_close_button, 14)
	_reset_all_button.pressed.connect(_reset_all)
	_close_button.pressed.connect(close_settings)


func _build_rows() -> void:
	for child in _rows_box.get_children():
		_rows_box.remove_child(child)
		child.queue_free()
	_rows.clear()

	for action_name in _action_names():
		var row := PanelContainer.new()
		row.name = "%sRow" % action_name
		row.custom_minimum_size = Vector2(0.0, 46.0)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_stylebox_override("panel", _make_row_style("normal"))

		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 10)
		margin.add_theme_constant_override("margin_top", 6)
		margin.add_theme_constant_override("margin_right", 10)
		margin.add_theme_constant_override("margin_bottom", 6)
		row.add_child(margin)

		var hbox := HBoxContainer.new()
		hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_theme_constant_override("separation", 10)
		margin.add_child(hbox)

		var action_button := Button.new()
		action_button.text = _action_label(action_name)
		action_button.custom_minimum_size = Vector2(210.0, 32.0)
		action_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		action_button.focus_mode = Control.FOCUS_ALL
		action_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		action_button.pressed.connect(_begin_capture.bind(action_name))
		_style_button(action_button, 14)
		hbox.add_child(action_button)

		var binding_button := Button.new()
		binding_button.custom_minimum_size = Vector2(390.0, 32.0)
		binding_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		binding_button.focus_mode = Control.FOCUS_ALL
		binding_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		binding_button.pressed.connect(_begin_capture.bind(action_name))
		_style_button(binding_button, 14)
		hbox.add_child(binding_button)

		var warning_label := Label.new()
		warning_label.custom_minimum_size = Vector2(92.0, 32.0)
		warning_label.text = "CONFLICT"
		warning_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		warning_label.add_theme_color_override("font_color", WARNING)
		warning_label.add_theme_font_size_override("font_size", 11)
		warning_label.visible = false
		hbox.add_child(warning_label)

		var reset_button := Button.new()
		reset_button.text = "Reset"
		reset_button.custom_minimum_size = Vector2(92.0, 32.0)
		reset_button.focus_mode = Control.FOCUS_ALL
		reset_button.pressed.connect(_reset_action.bind(action_name))
		_style_button(reset_button, 13)
		hbox.add_child(reset_button)

		_rows_box.add_child(row)
		_rows[action_name] = {
			"row": row,
			"action_button": action_button,
			"binding_button": binding_button,
			"warning_label": warning_label,
		}

	_refresh_rows()


func _begin_capture(action_name: String) -> void:
	if not _is_open:
		return

	_capturing_action = action_name
	_capture_banner.visible = true
	_capture_label.text = "PRESS KEY, MOUSE BUTTON, OR GAMEPAD BUTTON FOR %s   ESC CANCELS" % _action_label(action_name).to_upper()
	_refresh_rows()


func _end_capture(refresh: bool) -> void:
	if _capturing_action == "":
		return

	_capturing_action = ""
	_capture_banner.visible = false
	if refresh:
		_refresh_rows()


func _handle_capture_input(event: InputEvent) -> bool:
	if _is_escape_event(event):
		_end_capture(true)
		_mark_input_handled()
		return true

	if not InputBindingCodec.is_supported_capture_event(event):
		if _should_block_during_capture(event):
			_mark_input_handled()
			return true
		return false

	var normalized := InputBindingCodec.normalized_event(event)
	if normalized != null and _bindings != null and _bindings.has_method("rebind"):
		_bindings.call("rebind", StringName(_capturing_action), normalized)
	_end_capture(true)
	_mark_input_handled()
	return true


func _reset_action(action_name: String) -> void:
	if _bindings != null and _bindings.has_method("reset_action"):
		_bindings.call("reset_action", StringName(action_name))
	_refresh_rows()


func _reset_all() -> void:
	if _bindings != null and _bindings.has_method("reset_all"):
		_bindings.call("reset_all")
	_refresh_rows()


func _refresh_rows() -> void:
	if _rows.is_empty():
		return

	var conflicted := _conflicted_actions()
	for action_variant in _rows.keys():
		var action_name := String(action_variant)
		var row_data: Dictionary = _rows[action_name]
		var row := row_data["row"] as PanelContainer
		var binding_button := row_data["binding_button"] as Button
		var warning_label := row_data["warning_label"] as Label

		var is_capturing := action_name == _capturing_action
		var has_conflict := conflicted.has(action_name)
		if is_capturing:
			row.add_theme_stylebox_override("panel", _make_row_style("capture"))
			binding_button.text = "Press any key/button..."
		elif has_conflict:
			row.add_theme_stylebox_override("panel", _make_row_style("warning"))
			binding_button.text = _binding_text(action_name)
		else:
			row.add_theme_stylebox_override("panel", _make_row_style("normal"))
			binding_button.text = _binding_text(action_name)

		warning_label.visible = has_conflict and not is_capturing


func _conflicted_actions() -> Dictionary:
	var by_signature: Dictionary = {}
	for action_variant in _action_names():
		var action_name := String(action_variant)
		var seen_in_action := {}
		for event in _events_for_action(action_name):
			var signature := InputBindingCodec.event_signature(event)
			if signature.is_empty() or seen_in_action.has(signature):
				continue
			seen_in_action[signature] = true
			if not by_signature.has(signature):
				by_signature[signature] = []
			by_signature[signature].append(action_name)

	var result := {}
	for signature_variant in by_signature.keys():
		var actions: Array = by_signature[signature_variant]
		if actions.size() <= 1:
			continue
		for action_variant in actions:
			result[String(action_variant)] = true
	return result


func _binding_text(action_name: String) -> String:
	if _bindings != null and _bindings.has_method("get_binding_text"):
		return str(_bindings.call("get_binding_text", StringName(action_name)))
	return "Unbound"


func _events_for_action(action_name: String) -> Array[InputEvent]:
	if _bindings != null and _bindings.has_method("get_action_events"):
		return _bindings.call("get_action_events", StringName(action_name))
	if not InputMap.has_action(StringName(action_name)):
		return []
	return InputMap.action_get_events(StringName(action_name))


func _action_names() -> Array:
	if _bindings != null and _bindings.has_method("get_actions"):
		return _bindings.call("get_actions")
	return InputBindingsScript.GAMEPLAY_ACTIONS


func _action_label(action_name: String) -> String:
	return str(ACTION_LABELS.get(action_name, action_name.capitalize()))


func _focus_first_row() -> void:
	if not _is_open:
		return
	for action_variant in _action_names():
		var action_name := String(action_variant)
		if not _rows.has(action_name):
			continue
		var row_data: Dictionary = _rows[action_name]
		var action_button := row_data["action_button"] as Button
		if action_button != null:
			action_button.grab_focus()
		return


func _is_toggle_event(event: InputEvent) -> bool:
	var key := event as InputEventKey
	if key == null:
		return false
	return key.pressed and not key.echo and (key.keycode == KEY_F10 or key.physical_keycode == KEY_F10)


func _is_escape_event(event: InputEvent) -> bool:
	var key := event as InputEventKey
	if key == null:
		return false
	return key.pressed and not key.echo and (key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE)


func _should_block_during_capture(event: InputEvent) -> bool:
	return event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton


func _mark_input_handled() -> void:
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


func _style_button(button: Button, font_size: int) -> void:
	button.add_theme_color_override("font_color", SOFT_WHITE)
	button.add_theme_color_override("font_hover_color", SOFT_WHITE)
	button.add_theme_color_override("font_pressed_color", SOFT_WHITE)
	button.add_theme_color_override("font_focus_color", SOFT_WHITE)
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_stylebox_override("normal", _make_button_style(Color(0.02, 0.075, 0.085, 0.58), Color(CYAN.r, CYAN.g, CYAN.b, 0.32)))
	button.add_theme_stylebox_override("hover", _make_button_style(Color(0.04, 0.13, 0.14, 0.80), Color(CYAN.r, CYAN.g, CYAN.b, 0.62)))
	button.add_theme_stylebox_override("pressed", _make_button_style(Color(0.06, 0.19, 0.20, 0.90), Color(CYAN.r, CYAN.g, CYAN.b, 0.82)))
	button.add_theme_stylebox_override("focus", _make_button_style(Color(0.0, 0.0, 0.0, 0.0), Color(CYAN.r, CYAN.g, CYAN.b, 0.92)))


func _make_panel_style(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(0.0, 0.08, 0.09, 0.34)
	style.shadow_size = 12
	style.shadow_offset = Vector2(0.0, 2.0)
	return style


func _make_row_style(state: String) -> StyleBoxFlat:
	match state:
		"capture":
			return _make_panel_style(Color(CAPTURE.r, CAPTURE.g, CAPTURE.b, 0.16), Color(CAPTURE.r, CAPTURE.g, CAPTURE.b, 0.72), 5)
		"warning":
			return _make_panel_style(Color(WARNING.r, WARNING.g, WARNING.b, 0.10), Color(WARNING.r, WARNING.g, WARNING.b, 0.48), 5)
	return _make_panel_style(GLASS_LIGHT, Color(CYAN.r, CYAN.g, CYAN.b, 0.24), 5)


func _make_button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	return style


func _set_process_always(node: Node) -> void:
	node.process_mode = Node.PROCESS_MODE_ALWAYS
	for child in node.get_children():
		_set_process_always(child)
