extends RigidBody3D

signal looted(amount: int)

@export var value: int = 150
var is_stolen: bool = false

func collect_loot() -> int:
	if not is_stolen:
		is_stolen = true
		emit_signal("looted", value)
		queue_free()
		return value
	return 0
