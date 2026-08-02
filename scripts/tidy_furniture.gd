extends StaticBody3D

## Furniture that starts knocked over / messy and can be righted by pressing [E].

signal tidied()

@export var object_name: String = "Chair"
@export var target_rotation_degrees: Vector3 = Vector3.ZERO
@export var target_position_offset: Vector3 = Vector3.ZERO

var is_tidied: bool = false
var initial_transform: Transform3D

func _ready() -> void:
	add_to_group("interactable")
	initial_transform = transform

func get_interaction_prompt() -> String:
	if is_tidied:
		return ""
	return "Press [E] to Right Knocked-Over " + object_name

func interact(player: Node = null) -> void:
	if is_tidied:
		return
	is_tidied = true
	tidied.emit()

	if player and player.has_method("show_alert"):
		player.show_alert("🪑 Set Upright: " + object_name + "!", 2.0)

	# Smoothly animate upright into target standing transform
	var target_rot_rad = Vector3(
		deg_to_rad(target_rotation_degrees.x),
		deg_to_rad(target_rotation_degrees.y),
		deg_to_rad(target_rotation_degrees.z)
	)

	var tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "rotation", target_rot_rad, 0.5)
	if target_position_offset != Vector3.ZERO:
		tween.tween_property(self, "position", position + target_position_offset, 0.5)
