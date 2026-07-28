extends Node3D

signal item_disposed

@onready var area_3d: Area3D = $Area3D

func _ready() -> void:
	area_3d.body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if body is RigidBody3D and (body.is_in_group("pickable") or body.is_in_group("trash")):
		emit_signal("item_disposed")
		body.queue_free()
