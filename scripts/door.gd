extends StaticBody3D

## Interactive 3D door synced across multiplayer peers via RPC.

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
	if multiplayer.has_multiplayer_peer():
		rpc("_sync_set_door_state", not is_open)
	else:
		_sync_set_door_state(not is_open)

	if player and player.has_method("show_alert"):
		if is_open:
			player.show_alert("🚪 Door Has Been Opened!", 2.5)
		else:
			player.show_alert("🔒 Door Has Been Closed!", 2.5)

@rpc("any_peer", "call_local", "reliable")
func _sync_set_door_state(open: bool) -> void:
	is_open = open
	_update_door_state(null)

func _update_door_state(player: Node) -> void:
	if is_open:
		collision_layer = 4 # Shift layer so player on layer 1 passes through, but Raycast detects it
		if player and player is PhysicsBody3D:
			add_collision_exception_with(player)
	else:
		collision_layer = 1 # Solid collision blocking player
		if player and player is PhysicsBody3D:
			remove_collision_exception_with(player)
