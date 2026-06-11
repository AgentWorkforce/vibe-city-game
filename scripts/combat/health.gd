class_name Health
extends Node
## Attach as a child named "Health" to anything damageable.
## Damage dealers call `apply_damage`; owners react to the signals.

signal damaged(amount: float, source: Node)
signal died(source: Node)

@export var max_health: float = 100.0
@export var destructible: bool = true

var current: float

var is_dead: bool:
	get:
		return current <= 0.0


func _ready() -> void:
	current = max_health


func apply_damage(amount: float, source: Node = null) -> void:
	if not destructible or is_dead:
		return
	current = maxf(current - amount, 0.0)
	damaged.emit(amount, source)
	if current <= 0.0:
		died.emit(source)


func heal_full() -> void:
	current = max_health


## Convenience for raycast hits: walks up from a collider to find a Health child.
static func find_in(node: Node) -> Health:
	var cursor := node
	while cursor != null:
		var health := cursor.get_node_or_null("Health") as Health
		if health != null:
			return health
		cursor = cursor.get_parent()
	return null
