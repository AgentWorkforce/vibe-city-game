extends Control

@onready var _settings: CanvasLayer = $InputSettings


func _ready() -> void:
	call_deferred("_open_settings")


func _open_settings() -> void:
	if _settings != null and _settings.has_method("open_settings"):
		_settings.call("open_settings")
