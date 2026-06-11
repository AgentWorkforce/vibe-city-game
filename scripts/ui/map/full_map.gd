extends CanvasLayer

const CYAN := Color(0.098, 0.89, 0.89, 1.0)
const SOFT_WHITE := Color(0.94, 0.98, 1.0, 1.0)
const GLASS := Color(0.035, 0.08, 0.09, 0.82)

@onready var _root: Control = $Root
@onready var _panel: PanelContainer = $Root/Panel
@onready var _map_frame: PanelContainer = $Root/Panel/Margin/Content/MapFrame
@onready var _title: Label = $Root/Panel/Margin/Content/Header/Title

var _is_open := false
var _previous_pause_state := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_set_process_always(self)
	set_process_unhandled_input(true)
	_apply_style()
	_root.visible = false


func _unhandled_input(event: InputEvent) -> void:
	# project.godot is lead-owned, so full-map input stays local here instead
	# of adding an open_map action: M on keyboard, gamepad BACK button index 4.
	if not _is_toggle_event(event):
		return

	if _is_open:
		close_map()
	else:
		open_map()
	get_viewport().set_input_as_handled()


func open_map() -> void:
	if _is_open:
		return

	_previous_pause_state = get_tree().paused
	_is_open = true
	_root.visible = true
	get_tree().paused = true


func close_map() -> void:
	if not _is_open:
		return

	_is_open = false
	_root.visible = false
	get_tree().paused = _previous_pause_state


func is_map_open() -> bool:
	return _is_open


func _is_toggle_event(event: InputEvent) -> bool:
	var key := event as InputEventKey
	if key != null:
		return key.pressed and not key.echo and (key.keycode == KEY_M or key.physical_keycode == KEY_M)

	var button := event as InputEventJoypadButton
	if button != null:
		return button.pressed and button.button_index == 4

	return false


func _apply_style() -> void:
	_panel.add_theme_stylebox_override("panel", _make_panel_style(GLASS, Color(CYAN.r, CYAN.g, CYAN.b, 0.48), 8))
	_map_frame.add_theme_stylebox_override("panel", _make_panel_style(Color(0.015, 0.04, 0.045, 0.92), Color(CYAN.r, CYAN.g, CYAN.b, 0.64), 6))
	_title.add_theme_color_override("font_color", SOFT_WHITE)
	_title.add_theme_font_size_override("font_size", 18)
	_title.add_theme_constant_override("outline_size", 1)
	_title.add_theme_color_override("font_outline_color", Color(0.0, 0.05, 0.06, 0.82))


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


func _set_process_always(node: Node) -> void:
	node.process_mode = Node.PROCESS_MODE_ALWAYS
	for child in node.get_children():
		_set_process_always(child)
