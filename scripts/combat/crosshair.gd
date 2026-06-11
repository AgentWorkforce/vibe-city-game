extends CanvasLayer

@export var after_fire_seconds: float = 0.5
@export var line_length: float = 8.0
@export var line_gap: float = 6.0
@export var line_thickness: float = 2.0
@export var dot_size: float = 3.0
@export var crosshair_color: Color = Color(0.35, 1.0, 1.0, 0.9)

var _after_fire_timer: float = 0.0


func _ready() -> void:
	_build_crosshair()
	visible = false


func _process(delta: float) -> void:
	_after_fire_timer = maxf(_after_fire_timer - delta, 0.0)
	visible = Input.is_action_pressed("aim") or _after_fire_timer > 0.0


func show_after_fire() -> void:
	_after_fire_timer = after_fire_seconds


func _build_crosshair() -> void:
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_add_rect(root, "Dot", Vector2(-dot_size * 0.5, -dot_size * 0.5), Vector2(dot_size, dot_size))
	_add_rect(root, "Left", Vector2(-line_gap - line_length, -line_thickness * 0.5), Vector2(line_length, line_thickness))
	_add_rect(root, "Right", Vector2(line_gap, -line_thickness * 0.5), Vector2(line_length, line_thickness))
	_add_rect(root, "Top", Vector2(-line_thickness * 0.5, -line_gap - line_length), Vector2(line_thickness, line_length))
	_add_rect(root, "Bottom", Vector2(-line_thickness * 0.5, line_gap), Vector2(line_thickness, line_length))


func _add_rect(parent: Control, rect_name: String, offset: Vector2, size: Vector2) -> void:
	var rect := ColorRect.new()
	rect.name = rect_name
	rect.color = crosshair_color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.anchor_left = 0.5
	rect.anchor_right = 0.5
	rect.anchor_top = 0.5
	rect.anchor_bottom = 0.5
	rect.offset_left = offset.x
	rect.offset_top = offset.y
	rect.offset_right = offset.x + size.x
	rect.offset_bottom = offset.y + size.y
	parent.add_child(rect)
