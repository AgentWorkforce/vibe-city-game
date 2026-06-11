extends CanvasLayer

const PANEL_BG := Color(0.04, 0.08, 0.09, 0.72)
const PANEL_BORDER := Color(0.32, 0.92, 0.9, 0.85)
const TEXT_COLOR := Color(0.94, 0.99, 1.0, 1.0)

@export var streamer_path: NodePath
@export var visible_on_start := false

var _streamer: Node
var _panel: PanelContainer
var _label: Label


func _ready() -> void:
	_bind_or_build_panel()
	_resolve_streamer()
	_panel.visible = visible_on_start
	set_process(true)


func _process(delta: float) -> void:
	if not _panel.visible:
		return

	_resolve_streamer()
	_refresh_text(delta)


func _unhandled_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null:
		return
	if key_event.pressed and not key_event.echo and key_event.keycode == KEY_F3:
		_panel.visible = not _panel.visible
		get_viewport().set_input_as_handled()


func _bind_or_build_panel() -> void:
	_panel = get_node_or_null("Panel") as PanelContainer
	if _panel != null:
		_label = _panel.get_node_or_null("Margin/Readout") as Label
		if _label == null:
			_label = _panel.find_child("Readout", true, false) as Label
		return

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.position = Vector2(16.0, 16.0)
	_panel.custom_minimum_size = Vector2(300.0, 0.0)
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	_panel.add_child(margin)

	_label = Label.new()
	_label.name = "Readout"
	_label.text = "Streaming\nwaiting for streamer..."
	margin.add_child(_label)


func _resolve_streamer() -> void:
	if is_instance_valid(_streamer):
		return
	if streamer_path.is_empty():
		return
	_streamer = get_node_or_null(streamer_path)


func _refresh_text(delta: float) -> void:
	var frame_ms := maxf(delta, float(Performance.get_monitor(Performance.TIME_PROCESS))) * 1000.0
	var memory_mb := float(Performance.get_monitor(Performance.MEMORY_STATIC)) / (1024.0 * 1024.0)

	if not is_instance_valid(_streamer):
		_label.text = "Streaming\nresident: 0\ncoords: []\nframe: %.2f ms\nstatic memory: %.1f MB\nloads in flight: 0" % [
			frame_ms, memory_mb]
		return

	var resident_count := int(_streamer.call("get_resident_tile_count"))
	var coords := _format_coords(_streamer.call("get_resident_tile_coords"))
	var in_flight := int(_streamer.call("get_loads_in_flight_count"))
	_label.text = "Streaming\nresident: %d\ncoords: %s\nframe: %.2f ms\nstatic memory: %.1f MB\nloads in flight: %d" % [
		resident_count, coords, frame_ms, memory_mb, in_flight]


func _format_coords(coords_value: Variant) -> String:
	var coords := coords_value as Array
	if coords == null or coords.is_empty():
		return "[]"

	var parts: Array[String] = []
	for coord_value in coords:
		var coord := coord_value as Vector2i
		parts.append("(%d,%d)" % [coord.x, coord.y])
	return "[" + ", ".join(parts) + "]"
