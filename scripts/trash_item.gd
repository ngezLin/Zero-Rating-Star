extends RigidBody3D

## Pickable and disposable trash item (Soda Can, Paper Ball, Crushed Box).
## Stored inside Trash Cart when collected.

signal disposed()

@export var trash_name: String = "Trash Item"
var is_disposed: bool = false

func _ready() -> void:
	add_to_group("pickable")
	add_to_group("trash")
	collision_layer = 1
	collision_mask = 1

func dispose() -> void:
	if is_disposed:
		return
	is_disposed = true
	disposed.emit()
