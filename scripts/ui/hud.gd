extends CanvasLayer

const CYAN := Color(0.098, 0.89, 0.89, 1.0)
const SOFT_WHITE := Color(0.94, 0.98, 1.0, 1.0)
const GLASS := Color(0.055, 0.11, 0.13, 0.58)
const GLASS_STRONG := Color(0.055, 0.11, 0.13, 0.76)
const EMPTY_PIP := Color(0.94, 0.98, 1.0, 0.18)
const MAX_WANTED_LEVEL := 5
const BARK_VISIBLE_SECONDS := 4.0
const SPEED_BAR_MAX_KMH := 220.0

@onready var _wanted_meter: PanelContainer = $Root/WantedMeter
@onready var _wanted_label: Label = $Root/WantedMeter/Margin/Content/AssistanceLabel
@onready var _pip_row: HBoxContainer = $Root/WantedMeter/Margin/Content/PipRow
@onready var _bark_feed: VBoxContainer = $Root/BarkFeed
@onready var _speedometer: PanelContainer = $Root/Speedometer
@onready var _speed_title: Label = $Root/Speedometer/Margin/Content/Header/SpeedTitle
@onready var _speed_value: Label = $Root/Speedometer/Margin/Content/Readout/SpeedValue
@onready var _speed_unit: Label = $Root/Speedometer/Margin/Content/Readout/SpeedUnit
@onready var _speed_bar: ProgressBar = $Root/Speedometer/Margin/Content/SpeedBar

var _pips: Array[Panel] = []
var _wanted_level := 0
var _wanted_tween: Tween
var _speed_tween: Tween
var _current_vehicle: Node
var _bark_items: Array[Control] = []
var _events: Node


func _ready() -> void:
	_collect_pips()
	_apply_static_style()
	_events = get_node_or_null("/root/Events")
	_connect_events()
	_set_speedometer_visible(false, true)
	_on_wanted_changed(0)


func _process(_delta: float) -> void:
	if not _speedometer.visible:
		return

	if not is_instance_valid(_current_vehicle):
		_current_vehicle = null
		_set_speedometer_visible(false)
		return

	_update_speedometer(_read_vehicle_velocity(_current_vehicle))


func _connect_events() -> void:
	if not is_instance_valid(_events):
		return

	_connect_event_signal(&"wanted_changed", _on_wanted_changed)
	_connect_event_signal(&"bark_emitted", _on_bark_emitted)
	_connect_event_signal(&"vehicle_entered", _on_vehicle_entered)
	_connect_event_signal(&"vehicle_exited", _on_vehicle_exited)


func _connect_event_signal(signal_name: StringName, callback: Callable) -> void:
	if not _events.has_signal(signal_name):
		return
	if not _events.is_connected(signal_name, callback):
		_events.connect(signal_name, callback)


func _collect_pips() -> void:
	_pips.clear()
	for child in _pip_row.get_children():
		if child is Panel:
			_pips.append(child)


func _apply_static_style() -> void:
	_wanted_meter.add_theme_stylebox_override("panel", _make_panel_style(GLASS, CYAN, 1, 10))
	_speedometer.add_theme_stylebox_override("panel", _make_panel_style(GLASS_STRONG, CYAN, 1, 10))

	_wanted_label.add_theme_color_override("font_color", SOFT_WHITE)
	_wanted_label.add_theme_font_size_override("font_size", 13)
	_wanted_label.add_theme_constant_override("outline_size", 1)
	_wanted_label.add_theme_color_override("font_outline_color", Color(0.0, 0.05, 0.06, 0.75))

	for label in [_speed_title, _speed_unit]:
		label.add_theme_color_override("font_color", Color(0.94, 0.98, 1.0, 0.72))
		label.add_theme_font_size_override("font_size", 12)

	_speed_value.add_theme_color_override("font_color", SOFT_WHITE)
	_speed_value.add_theme_font_size_override("font_size", 34)
	_speed_value.add_theme_constant_override("outline_size", 1)
	_speed_value.add_theme_color_override("font_outline_color", Color(0.0, 0.05, 0.06, 0.75))

	_speed_bar.min_value = 0.0
	_speed_bar.max_value = SPEED_BAR_MAX_KMH
	_speed_bar.value = 0.0
	_speed_bar.show_percentage = false
	_speed_bar.add_theme_stylebox_override("background", _make_speed_bar_style(Color(0.94, 0.98, 1.0, 0.12), 4))
	_speed_bar.add_theme_stylebox_override("fill", _make_speed_bar_style(CYAN, 4))

	_refresh_pips()


func _on_wanted_changed(level: int) -> void:
	var previous_level := _wanted_level
	_wanted_level = clampi(level, 0, MAX_WANTED_LEVEL)
	_refresh_pips()

	if is_instance_valid(_wanted_tween):
		_wanted_tween.kill()

	_wanted_meter.visible = true
	if _wanted_level > 0:
		_wanted_meter.modulate.a = 1.0
		if _wanted_level > previous_level:
			_pulse_pip(_wanted_level - 1)
		return

	_wanted_tween = create_tween()
	_wanted_tween.tween_interval(2.0)
	_wanted_tween.tween_property(_wanted_meter, "modulate:a", 0.0, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_wanted_tween.finished.connect(func() -> void:
		if _wanted_level == 0:
			_wanted_meter.visible = false
	)


func _on_bark_emitted(_speaker: Node, _category: StringName, text: String) -> void:
	var item := _create_bark_item(text)
	_bark_feed.add_child(item)
	_bark_items.append(item)

	while _bark_items.size() > 2:
		var old_item: Control = _bark_items.pop_front()
		if is_instance_valid(old_item):
			old_item.queue_free()

	var tween := create_tween()
	tween.tween_interval(BARK_VISIBLE_SECONDS)
	tween.tween_property(item, "modulate:a", 0.0, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.finished.connect(func() -> void:
		if is_instance_valid(item):
			_bark_items.erase(item)
			item.queue_free()
	)


func _on_vehicle_entered(vehicle: Node) -> void:
	_current_vehicle = vehicle
	_update_speedometer(_read_vehicle_velocity(_current_vehicle))
	_set_speedometer_visible(true)


func _on_vehicle_exited(vehicle: Node) -> void:
	if vehicle == _current_vehicle or not is_instance_valid(_current_vehicle):
		_current_vehicle = null
		_set_speedometer_visible(false)


func _refresh_pips() -> void:
	for index in range(_pips.size()):
		var pip := _pips[index]
		var filled := index < _wanted_level
		pip.add_theme_stylebox_override("panel", _make_pip_style(filled))
		pip.modulate = Color(1.0, 1.0, 1.0, 1.0 if filled else 0.82)
		pip.scale = Vector2.ONE
		pip.pivot_offset = pip.custom_minimum_size * 0.5


func _pulse_pip(index: int) -> void:
	if index < 0 or index >= _pips.size():
		return

	var pip := _pips[index]
	pip.pivot_offset = pip.custom_minimum_size * 0.5
	var tween := create_tween()
	tween.tween_property(pip, "scale", Vector2(1.38, 1.38), 0.11).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(pip, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _create_bark_item(text: String) -> PanelContainer:
	var item := PanelContainer.new()
	item.custom_minimum_size = Vector2(620.0, 0.0)
	item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item.modulate.a = 0.0
	item.add_theme_stylebox_override("panel", _make_bark_style())

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 8)
	item.add_child(margin)

	var label := Label.new()
	label.text = "\"%s\"" % text.strip_edges()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", SOFT_WHITE)
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_constant_override("outline_size", 2)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.05, 0.06, 0.82))
	margin.add_child(label)

	var fade_in := create_tween()
	fade_in.tween_property(item, "modulate:a", 1.0, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	return item


func _set_speedometer_visible(visible: bool, immediate: bool = false) -> void:
	if is_instance_valid(_speed_tween):
		_speed_tween.kill()

	if immediate:
		_speedometer.visible = visible
		_speedometer.modulate.a = 1.0 if visible else 0.0
		return

	if visible:
		_speedometer.visible = true
		_speed_tween = create_tween()
		_speed_tween.tween_property(_speedometer, "modulate:a", 1.0, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	else:
		_speed_tween = create_tween()
		_speed_tween.tween_property(_speedometer, "modulate:a", 0.0, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		_speed_tween.finished.connect(func() -> void:
			if not is_instance_valid(_current_vehicle):
				_speedometer.visible = false
		)


func _update_speedometer(velocity: Vector3) -> void:
	var speed_kmh := velocity.length() * 3.6
	var display_speed := roundi(speed_kmh)
	_speed_value.text = "%03d" % display_speed
	_speed_bar.value = clampf(speed_kmh, 0.0, SPEED_BAR_MAX_KMH)


func _read_vehicle_velocity(vehicle: Node) -> Vector3:
	if not is_instance_valid(vehicle):
		return Vector3.ZERO

	var velocity_value: Variant = vehicle.get("linear_velocity")
	if velocity_value is Vector3:
		return velocity_value
	return Vector3.ZERO


func _make_panel_style(bg: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = Color(border.r, border.g, border.b, 0.44)
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(0.0, 0.08, 0.09, 0.26)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0.0, 2.0)
	return style


func _make_bark_style() -> StyleBoxFlat:
	var style := _make_panel_style(Color(0.035, 0.08, 0.09, 0.64), CYAN, 0, 8)
	style.border_color = CYAN
	style.border_width_left = 4
	return style


func _make_pip_style(filled: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = CYAN if filled else EMPTY_PIP
	style.border_color = Color(CYAN.r, CYAN.g, CYAN.b, 0.9 if filled else 0.48)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	return style


func _make_speed_bar_style(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	return style
