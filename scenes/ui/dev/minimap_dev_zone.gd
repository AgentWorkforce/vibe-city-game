extends Node3D

@export var district_name: StringName = &"playground_nw"
@export var control := 1.0


func get_control() -> float:
	return control


func is_liberated() -> bool:
	return control <= -1.0
