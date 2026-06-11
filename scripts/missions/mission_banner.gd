extends CanvasLayer

const CYAN := Color(0.098, 0.89, 0.89, 1.0)
const SOFT_WHITE := Color(0.94, 0.98, 1.0, 1.0)
const GLASS := Color(0.055, 0.11, 0.13, 0.72)
const EXPANDED_SIZE := Vector2(620.0, 76.0)
const COMPACT_SIZE := Vector2(520.0, 38.0)
const UPDATE_SECONDS := 3.0
const COMPLETE_SECONDS := 5.0

@onready var _root: Control = $Root
@onready var _panel: PanelContainer = $Root/Banner
@onready var _kicker: Label = $Root/Banner/Margin/Content/Kicker
@onready var _label: Label = $Root/Banner/Margin/Content/Objective

var _tween: Tween
var _events: Node


func _ready() -> void:
	_apply_style()
	_connect_events()
	_root.visible = false
	_root.modulate.a = 0.0


func _connect_events() -> void:
	_events = get_node_or_null("/root/Events")
	if _events == null:
		return

	_connect_event(&"mission_started", Callable(self, "_on_mission_started"))
	_connect_event(&"mission_objective", Callable(self, "_on_mission_objective"))
	_connect_event(&"mission_completed", Callable(self, "_on_mission_completed"))
	_connect_event(&"mission_failed", Callable(self, "_on_mission_failed"))


func _connect_event(signal_name: StringName, callback: Callable) -> void:
	if _events.has_signal(signal_name) and not _events.is_connected(signal_name, callback):
		_events.connect(signal_name, callback)


func _on_mission_started(mission: Node) -> void:
	var mission_title := ""
	if mission != null:
		mission_title = str(mission.get("title"))
	if mission_title.is_empty():
		mission_title = "Mission started"
	_show_text("MISSION", mission_title, UPDATE_SECONDS, true)


func _on_mission_objective(text: String) -> void:
	_show_text("OBJECTIVE", text, UPDATE_SECONDS, true)


func _on_mission_completed(_mission: Node) -> void:
	_show_text("COMPLETE", "DISTRICT LIBERATED — they left politely", COMPLETE_SECONDS, false)


func _on_mission_failed(_mission: Node, reason: String) -> void:
	_show_text("FAILED", "Mission failed - %s" % reason, COMPLETE_SECONDS, false)


func _show_text(kicker: String, text: String, seconds: float, compact_after: bool) -> void:
	if is_instance_valid(_tween):
		_tween.kill()

	_kicker.text = kicker
	_kicker.modulate.a = 1.0
	_label.text = text
	_kicker.visible = true
	_panel.custom_minimum_size = EXPANDED_SIZE
	_root.visible = true
	_root.modulate.a = 1.0

	_tween = create_tween()
	_tween.tween_interval(seconds)
	if compact_after:
		_tween.tween_property(_panel, "custom_minimum_size", COMPACT_SIZE, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_tween.parallel().tween_property(_kicker, "modulate:a", 0.0, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_tween.parallel().tween_property(_root, "modulate:a", 0.76, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_tween.finished.connect(func() -> void:
			_kicker.visible = false
		)
	else:
		_tween.tween_property(_root, "modulate:a", 0.0, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_tween.finished.connect(func() -> void:
			_root.visible = false
		)


func _apply_style() -> void:
	_panel.add_theme_stylebox_override("panel", _make_panel_style())

	_kicker.add_theme_color_override("font_color", Color(CYAN.r, CYAN.g, CYAN.b, 0.88))
	_kicker.add_theme_font_size_override("font_size", 12)

	_label.add_theme_color_override("font_color", SOFT_WHITE)
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_constant_override("outline_size", 1)
	_label.add_theme_color_override("font_outline_color", Color(0.0, 0.05, 0.06, 0.75))


func _make_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = GLASS
	style.border_color = Color(CYAN.r, CYAN.g, CYAN.b, 0.48)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.shadow_color = Color(0.0, 0.08, 0.09, 0.24)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0.0, 2.0)
	return style
