extends Node
## Global event bus (autoload "Events"). Systems communicate through these
## signals instead of reaching into each other's scene trees.

## A crime was witnessed or detected. severity 1 (mischief) .. 5 (mayhem).
signal crime_committed(severity: int, position: Vector3)

## Wanted level changed. level 0 (clear) .. 5 (maximum assistance).
signal wanted_changed(level: int)

## District control shifted. control -1.0 (human) .. 1.0 (agent).
signal district_control_changed(district: StringName, control: float)

## Someone said a line out loud (for HUD/subtitles/debugging).
signal bark_emitted(speaker: Node, category: StringName, text: String)

## Player entered/exited a vehicle.
signal vehicle_entered(vehicle: Node)
signal vehicle_exited(vehicle: Node)
