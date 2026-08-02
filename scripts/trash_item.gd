extends RigidBody3D

## Pickable and disposable trash item (Soda Can, Paper Ball, Crushed Box).

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

	# Shrink & fade out into trash bin
	freeze = true
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector3(0.01, 0.01, 0.01), 0.3)
	tween.tween_callback(queue_free)
