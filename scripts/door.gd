extends StaticBody3D

@export var is_open: bool = false

func _ready() -> void:
	add_to_group("interactable")
	_update_door_state(null)

func get_interaction_prompt() -> String:
	if is_open:
		return "Press [E] to Close Door"
	else:
		return "Press [E] to Open Door"

func interact(player: Node = null) -> void:
	is_open = not is_open
	_update_door_state(player)

	if player and player.has_method("show_alert"):
		if is_open:
			player.show_alert("🚪 Door Has Been Opened! You can pass through.", 3.0)
		else:
			player.show_alert("🔒 Door Has Been Closed!", 3.0)

func _update_door_state(player: Node) -> void:
	if is_open:
		collision_layer = 4 # Shift layer so player on layer 1 passes through, but Raycast detects it
		if player and player is PhysicsBody3D:
			add_collision_exception_with(player)
	else:
		collision_layer = 1 # Solid collision blocking player
		if player and player is PhysicsBody3D:
			remove_collision_exception_with(player)
